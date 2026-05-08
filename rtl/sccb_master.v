`timescale 1ns/1ps
// SCCB 3-byte write master for OV7670.
// Frame: START | ID(8) | DC | SUB(8) | DC | DATA(8) | DC | STOP
//
// SCL period = 4 * HALF_PER_CYCLES clocks (two half-bit phases per bit, two for START/STOP).
// Default HALF_PER_CYCLES = 128 -> ~49 kHz SCL at 25 MHz clk (well under SCCB max 400 kHz).
//
// Open-drain bus model:
//   scl, sda are 1 when released (rely on board-level pull-ups), 0 when driven low.
//   Master releases SDA during the 3 DC slots so the slave can ACK.
//   ACK is sampled at the midpoint of the SCL-high half on each DC slot.

module sccb_master #(
    parameter integer HALF_PER_CYCLES = 128   // half SCL period in clk cycles
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        start,
    input  wire [7:0]  id,
    input  wire [7:0]  sub_addr,
    input  wire [7:0]  data,

    output reg         done,
    output reg         busy,
    output reg         ack_id,
    output reg         ack_sub,
    output reg         ack_data,

    output wire        scl,
    inout  wire        sda
);

    // Drive mask: 1 = master drives, 0 = master releases (DC / ACK slot)
    // Layout: [26:19] ID, [18] DC, [17:10] SUB, [9] DC, [8:1] DATA, [0] DC
    localparam [26:0] DRIVE_MASK = 27'b111111110_111111110_111111110;

    localparam [2:0]
        S_IDLE   = 3'd0,
        S_START  = 3'd1,   // SCL=1, drop SDA -> START condition
        S_LOW    = 3'd2,   // SCL=0, set SDA to current bit
        S_HIGH   = 3'd3,   // SCL=1, hold SDA; sample ACK on DC slots
        S_STOP_A = 3'd4,   // SCL=0, SDA=0
        S_STOP_B = 3'd5,   // SCL=1, SDA=0
        S_STOP_C = 3'd6;   // SCL=1, SDA released -> bus idle

    reg [2:0]  state;
    reg [26:0] shift;
    reg [4:0]  bit_idx;          // 26 down to 0
    reg [$clog2(HALF_PER_CYCLES)-1:0] div;
    reg        scl_r;
    reg        sda_low;          // 1 = drive SDA low; 0 = release

    wire phase_done = (div == HALF_PER_CYCLES - 1);
    wire bit_drives = DRIVE_MASK[bit_idx];
    wire drive_low_now = bit_drives && (shift[26] == 1'b0);

    // SDA: drive low if sda_low=1, else release. sda_in reads bus state.
    assign sda = sda_low ? 1'b0 : 1'bz;
    assign scl = scl_r   ? 1'bz : 1'b0;
    wire sda_in = (sda === 1'bz) ? 1'b1 : sda;

    initial begin
        state    = S_IDLE;
        shift    = 27'd0;
        bit_idx  = 5'd0;
        div      = 0;
        scl_r    = 1'b1;
        sda_low  = 1'b0;
        busy     = 1'b0;
        done     = 1'b0;
        ack_id   = 1'b1;
        ack_sub  = 1'b1;
        ack_data = 1'b1;
    end

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            div      <= 0;
            scl_r    <= 1'b1;
            sda_low  <= 1'b0;
            busy     <= 1'b0;
            done     <= 1'b0;
            ack_id   <= 1'b1;
            ack_sub  <= 1'b1;
            ack_data <= 1'b1;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    scl_r   <= 1'b1;
                    sda_low <= 1'b0;
                    if (start && !busy) begin
                        // Pack with 1's in DC slots; mask suppresses driving anyway
                        shift   <= {id, 1'b1, sub_addr, 1'b1, data, 1'b1};
                        bit_idx <= 5'd26;
                        busy    <= 1'b1;
                        sda_low <= 1'b1;       // drop SDA while SCL high = START
                        state   <= S_START;
                        div     <= 0;
                    end
                end

                S_START: begin
                    scl_r   <= 1'b1;
                    sda_low <= 1'b1;
                    if (phase_done) begin state <= S_LOW; div <= 0; end
                    else div <= div + 1'b1;
                end

                S_LOW: begin
                    scl_r   <= 1'b0;
                    sda_low <= drive_low_now;
                    if (phase_done) begin state <= S_HIGH; div <= 0; end
                    else div <= div + 1'b1;
                end

                S_HIGH: begin
                    scl_r   <= 1'b1;
                    sda_low <= drive_low_now;

                    // Sample ACK at midpoint of high phase on the 3 DC slots
                    if (div == (HALF_PER_CYCLES >> 1) && !bit_drives) begin
                        case (bit_idx)
                            5'd18: ack_id   <= sda_in;
                            5'd9:  ack_sub  <= sda_in;
                            5'd0:  ack_data <= sda_in;
                            default: ;
                        endcase
                    end

                    if (phase_done) begin
                        div <= 0;
                        if (bit_idx == 5'd0) begin
                            state <= S_STOP_A;
                        end else begin
                            shift   <= {shift[25:0], 1'b1};
                            bit_idx <= bit_idx - 5'd1;
                            state   <= S_LOW;
                        end
                    end else div <= div + 1'b1;
                end

                S_STOP_A: begin
                    scl_r   <= 1'b0;
                    sda_low <= 1'b1;
                    if (phase_done) begin state <= S_STOP_B; div <= 0; end
                    else div <= div + 1'b1;
                end

                S_STOP_B: begin
                    scl_r   <= 1'b1;
                    sda_low <= 1'b1;
                    if (phase_done) begin state <= S_STOP_C; div <= 0; end
                    else div <= div + 1'b1;
                end

                S_STOP_C: begin
                    scl_r   <= 1'b1;
                    sda_low <= 1'b0;
                    if (phase_done) begin
                        state <= S_IDLE;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        div   <= 0;
                    end else div <= div + 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
