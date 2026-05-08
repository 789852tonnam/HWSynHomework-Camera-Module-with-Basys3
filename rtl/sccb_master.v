`timescale 1ns/1ps
// sccb_master.v
// SCCB (I2C-compatible) 3-phase write master for OV7670.
//
// Ported from the proven i2c_sender.v used in the uec2_projekt reference design
// (Bekasiak/Warcholak, AGH University, derived from fpga4student.com OV7670+Basys3).
//
// Protocol: START -> ID byte (8b+ACK) -> SUB_ADDR byte (8b+ACK) -> DATA byte (8b+ACK) -> STOP
//
// Implementation approach: 32-bit shift registers (data_sr, busy_sr).
//   data_sr holds the full transaction bit pattern, shifted left each clock division.
//   busy_sr is a one-hot activity mask: when busy_sr[31:0]==0, the transaction is done.
//   An internal 8-bit divider produces the SCL timing (clk/256 per half-period,
//   giving SCL ~ clk/512; at 25 MHz: ~49 kHz).
//
// clk_div_run port is kept for top.v port compatibility (SW[11] mux wiring).
// It is NOT used internally — the reference design uses an internal fixed divider.
// SW[11] slow-SCCB mode has no effect on this module. The signal is consumed
// by a dead-wire tie-off to suppress unused-input warnings.
//
// Open-drain model:
//   scl: assign scl = sioc_int ? 1'bz : 1'b0;
//   sda: released during ACK slots and when data bit is 1; driven low when bit is 0.
//
// ACK sampling: added on top of reference (not present in original i2c_sender.v).
//   Samples SDA when SCL is high during each of the 3 ACK windows.
//   Enables SW[10] diagnostic (successful_xacts counter in cam_config).
//
// Ports:
//   clk_div_run — kept for wiring compatibility only; ignored internally

module sccb_master #(
    parameter CLK_DIV_W = 11   // width kept for port compatibility
) (
    input  wire                  clk,
    input  wire                  rst,

    // Wiring-compatibility port: kept so top.v needs no changes.
    // SW[11] slow-SCCB mode has no effect on this implementation
    // (internal fixed 8-bit divider is used instead).
    input  wire [CLK_DIV_W-1:0]  clk_div_run,

    // User interface
    input  wire        start,        // 1-cycle pulse to begin a transaction
    input  wire [7:0]  id,           // device ID byte (e.g., 0x42 for OV7670 write)
    input  wire [7:0]  sub_addr,     // register address byte
    input  wire [7:0]  data,         // register value byte

    output reg         done,         // 1-cycle pulse when transaction completes
    output reg         busy,         // high throughout the transaction

    // ACK sampling outputs (0 = slave ACK'd, 1 = NACK / no response)
    output reg         ack_id,       // sampled after ID byte ACK slot
    output reg         ack_sub,      // sampled after sub_addr byte ACK slot
    output reg         ack_data,     // sampled after data byte ACK slot
    output reg         ack_valid,    // 1-cycle pulse when all 3 ACKs are captured

    // Open-drain bus (Z = released/high, 0 = driven low)
    output wire        scl,
    inout  wire        sda
);

    // -----------------------------------------------------------------------
    // Suppress unused-port warning for clk_div_run
    // -----------------------------------------------------------------------
    wire _unused_div = &{1'b0, clk_div_run};

    // -----------------------------------------------------------------------
    // Shift registers and divider (reference approach)
    // -----------------------------------------------------------------------
    // data_sr[31]: MSB is always the current SDA output bit.
    //   Bit pattern loaded on transaction start:
    //   {3'b100, id[7:0], 1'b0, sub_addr[7:0], 1'b0, data[7:0], 1'b0, 2'b01}
    //   Breakdown:
    //     bits [31:29] = 3'b100  — START condition framing (SDA high->low while SCL high)
    //     bits [28:21] = id[7:0]
    //     bit  [20]    = 1'b0    — ACK slot 1 (master releases SDA)
    //     bits [19:12] = sub_addr[7:0]
    //     bit  [11]    = 1'b0    — ACK slot 2 (master releases SDA)
    //     bits [10:3]  = data[7:0]
    //     bit  [2]     = 1'b0    — ACK slot 3 (master releases SDA)
    //     bits [1:0]   = 2'b01   — STOP framing (SDA low->high while SCL high)
    //
    // busy_sr[31:0]: one-hot activity register. When all zero, transaction is done.
    //   Loaded as {3'b111, 9'b111111111, 9'b111111111, 9'b111111111, 2'b11}
    //   = 32'hFFFFFFFF minus 2 (= 32'hFFFFFFFC -- but reference uses the full patterns).
    //   Specifically: 3'b111 || 9'b1_1111_1111 || 9'b1_1111_1111 || 9'b1_1111_1111 || 2'b11
    //   = 0b111_111111111_111111111_111111111_11 = 0xFFFFFFFF (but that's 33 bits).
    //   Reference actually uses: busy_sr = {3'b111, 9'h1FF, 9'h1FF, 9'h1FF, 2'b11}
    //   which with concatenation = 3+9+9+9+2 = 32 bits = 32'hFFFFFFFF - but written as:
    //   {3'b111, 9'b1_1111_1111, 9'b1_1111_1111, 9'b1_1111_1111, 2'b11}
    //
    // divider[7:0]: 8-bit counter. Shifts both registers left when it wraps (255->0).
    //   SCL phase is derived from divider[7:6]:
    //     2'b00 → SCL low (default data bits)
    //     2'b01, 2'b10, 2'b11 → SCL high (for special cases)
    //   See the case statement below for exact SCL encoding per reference.

    reg [31:0] data_sr;
    reg [31:0] busy_sr;
    reg [7:0]  divider;
    reg        sioc_int;   // internal SCL state: 1=high/released, 0=low

    // SDA open-drain driver: released (Z) during ACK slots or when data bit is 1
    reg sda_drv;           // 1 = release (Z), 0 = drive low
    assign sda  = sda_drv ? 1'bz : 1'b0;
    assign scl  = sioc_int ? 1'bz : 1'b0;

    // Read SDA back: treat Z as 1 (floating high via external pullup = no slave ACK)
    wire sda_in = (sda === 1'bz) ? 1'b1 : sda;

    // -----------------------------------------------------------------------
    // Initial blocks — X-prop avoidance (learned from v1 simulation issues)
    // -----------------------------------------------------------------------
    initial begin
        data_sr   = 32'hFFFFFFFF;
        busy_sr   = 32'd0;
        divider   = 8'd0;
        sioc_int  = 1'b1;
        sda_drv   = 1'b1;
        busy      = 1'b0;
        done      = 1'b0;
        ack_id    = 1'b1;
        ack_sub   = 1'b1;
        ack_data  = 1'b1;
        ack_valid = 1'b0;
    end

    // -----------------------------------------------------------------------
    // SDA combinational driver
    // Release SDA during ACK slots so slave can pull it low to acknowledge.
    // ACK windows are detected by the pattern in busy_sr:
    //   ACK1 window: busy_sr[29:28] == 2'b10  (after ID byte)
    //   ACK2 window: busy_sr[20:19] == 2'b10  (after sub_addr byte)
    //   ACK3 window: busy_sr[11:10] == 2'b10  (after data byte)
    // Outside these windows, SDA follows data_sr[31] (1=release, 0=drive low).
    // -----------------------------------------------------------------------
    always @(*) begin
        if ((busy_sr[29:28] == 2'b10) ||
            (busy_sr[20:19] == 2'b10) ||
            (busy_sr[11:10] == 2'b10))
            sda_drv = 1'b1;       // release SDA during ACK window
        else
            sda_drv = data_sr[31]; // drive SDA from shift register MSB
    end

    // -----------------------------------------------------------------------
    // ACK sampling windows (used for sampling sda_in when SCL is high)
    // -----------------------------------------------------------------------
    wire ack1_window = (busy_sr[29:28] == 2'b10);  // first byte ACK
    wire ack2_window = (busy_sr[20:19] == 2'b10);  // second byte ACK
    wire ack3_window = (busy_sr[11:10] == 2'b10);  // third byte ACK

    // -----------------------------------------------------------------------
    // Main clocked process: SCL generation, shift register advance, handshake
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            busy_sr   <= 32'd0;
            data_sr   <= 32'hFFFFFFFF;
            divider   <= 8'd0;
            sioc_int  <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
            ack_id    <= 1'b1;
            ack_sub   <= 1'b1;
            ack_data  <= 1'b1;
            ack_valid <= 1'b0;
        end else begin
            done      <= 1'b0;
            ack_valid <= 1'b0;

            if (busy_sr[31] == 1'b0) begin
                // Idle: no active transaction
                sioc_int <= 1'b1;

                if (start == 1'b1 && busy == 1'b0) begin
                    // Wait for divider to be 0 before loading (reference requirement)
                    if (divider == 8'h00) begin
                        // Load transaction data into shift registers
                        data_sr <= {3'b100, id, 1'b0, sub_addr, 1'b0, data, 1'b0, 2'b01};
                        busy_sr <= {3'b111, 9'b1_1111_1111,
                                            9'b1_1111_1111,
                                            9'b1_1111_1111,
                                    2'b11};
                        busy    <= 1'b1;
                        // done is the "taken" signal in reference: pulses here to start
                        // (In our interface this is wrong — done should pulse at END.
                        // Reference "taken" signals the controller to advance ROM.
                        // We keep busy=1 throughout and set done at the end.)
                    end else begin
                        divider <= divider + 8'd1;
                    end
                end
            end else begin
                // Active transaction: generate SCL waveform based on busy_sr state
                // This is a direct translation of the reference's case statement.
                // The case key is {busy_sr[31:29], busy_sr[2:0]} which encodes
                // the position within the START and STOP framing bits.
                case ({busy_sr[31:29], busy_sr[2:0]})
                    // START framing: high bit (busy_sr[31:29]=3'b111, low bits=3'b111)
                    // SCL stays high during START setup
                    {3'b111, 3'b111}: begin
                        case (divider[7:6])
                            2'b00: sioc_int <= 1'b1;
                            2'b01: sioc_int <= 1'b1;
                            2'b10: sioc_int <= 1'b1;
                            default: sioc_int <= 1'b1;
                        endcase
                    end
                    // START framing continued (busy_sr[31:29]=3'b111, low=3'b110)
                    {3'b111, 3'b110}: begin
                        case (divider[7:6])
                            2'b00: sioc_int <= 1'b1;
                            2'b01: sioc_int <= 1'b1;
                            2'b10: sioc_int <= 1'b1;
                            default: sioc_int <= 1'b1;
                        endcase
                    end
                    // START -> first data bit: SCL goes low
                    {3'b111, 3'b100}: begin
                        case (divider[7:6])
                            2'b00: sioc_int <= 1'b0;
                            2'b01: sioc_int <= 1'b0;
                            2'b10: sioc_int <= 1'b0;
                            default: sioc_int <= 1'b0;
                        endcase
                    end
                    // STOP framing: last data transitions, SCL rises then SDA rises
                    {3'b110, 3'b000}: begin
                        case (divider[7:6])
                            2'b00: sioc_int <= 1'b0;
                            2'b01: sioc_int <= 1'b1;
                            2'b10: sioc_int <= 1'b1;
                            default: sioc_int <= 1'b1;
                        endcase
                    end
                    // STOP holding: SCL high
                    {3'b100, 3'b000}: begin
                        case (divider[7:6])
                            2'b00: sioc_int <= 1'b1;
                            2'b01: sioc_int <= 1'b1;
                            2'b10: sioc_int <= 1'b1;
                            default: sioc_int <= 1'b1;
                        endcase
                    end
                    // Final idle: both high
                    {3'b000, 3'b000}: begin
                        case (divider[7:6])
                            2'b00: sioc_int <= 1'b1;
                            2'b01: sioc_int <= 1'b1;
                            2'b10: sioc_int <= 1'b1;
                            default: sioc_int <= 1'b1;
                        endcase
                    end
                    // Default: normal data clocking
                    // SCL low when divider[7:6]=00 or 11, high when 01 or 10
                    default: begin
                        case (divider[7:6])
                            2'b00: sioc_int <= 1'b0;
                            2'b01: sioc_int <= 1'b1;
                            2'b10: sioc_int <= 1'b1;
                            default: sioc_int <= 1'b0;
                        endcase
                    end
                endcase

                // ACK sampling: capture SDA when SCL is high during ACK windows.
                // sioc_int=1 means SCL is high (the safe sampling moment).
                if (ack1_window && sioc_int) ack_id   <= sda_in;
                if (ack2_window && sioc_int) ack_sub  <= sda_in;
                if (ack3_window && sioc_int) ack_data <= sda_in;

                // Shift advance: when divider wraps 255->0, shift both registers left
                if (divider == 8'hFF) begin
                    busy_sr <= {busy_sr[30:0], 1'b0};
                    data_sr <= {data_sr[30:0], 1'b1};
                    divider <= 8'd0;
                end else begin
                    divider <= divider + 8'd1;
                end

                // Detect transaction completion: busy_sr has fully shifted out
                // (busy_sr[31] will be 0 on the next cycle after the last shift).
                // We pulse done and clear busy the cycle after busy_sr reaches 0.
                // Check: when busy_sr is about to become all-zero (current busy_sr[30:0]==0
                // and divider==255, meaning next shift makes busy_sr=0).
                if (busy_sr[30:0] == 31'd0 && divider == 8'hFF) begin
                    done      <= 1'b1;
                    busy      <= 1'b0;
                    ack_valid <= 1'b1;
                end
            end
        end
    end

endmodule
