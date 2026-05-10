`timescale 1ns/1ps
// Verifies sccb_config (320-path 8-register SCCB sequencer):
//   - Walks 8 register entries via 4-phase SCCB state machine
//   - Each entry produces START + 24 data bits (3 bytes) + STOP on sioc/siod
//   - Counts STOP conditions (siod rises while sioc high after START seen)
//   - Expects exactly 8 STOP events (one per register write)
module tb_sccb_config;
    reg clk = 0;
    always #20 clk = ~clk;    // 25 MHz

    wire sioc;
    wire siod;
    pullup(sioc);
    pullup(siod);

    sccb_config dut (.clk(clk), .sioc(sioc), .siod(siod));

    // Detect STOP: siod rises while sioc is high (after start seen)
    integer stop_count = 0;
    reg siod_prev = 1'b1;
    reg sioc_prev = 1'b1;
    reg start_seen = 0;

    always @(posedge clk) begin
        // START = siod falls while sioc high
        if (sioc && siod_prev && !siod) start_seen <= 1'b1;
        // STOP  = siod rises while sioc high, after a START
        if (sioc && !siod_prev && siod && start_seen) begin
            stop_count = stop_count + 1;
            start_seen <= 1'b0;
        end
        siod_prev <= siod;
        sioc_prev <= sioc;
    end

    initial begin
        $dumpfile("sim/320/sccb_config.vcd");
        $dumpvars(0, tb_sccb_config);

        // Budget per register: i2c_clk period = 64 sys clk.
        // ~100 i2c phases per transaction = 6400 sys cycles.
        // reg_idx=1 waits 400 i2c_clk extra = 25600 sys cycles.
        // 8 regs * 6400 + 25600 + margin = ~120000 sys cycles
        begin : wait_done
            integer t;
            for (t = 0; t < 300000; t = t + 1) begin
                @(posedge clk);
                if (stop_count >= 8) disable wait_done;
            end
        end

        if (stop_count < 8) begin
            $display("FAIL: only %0d STOP conditions seen (expected 8)", stop_count);
            $finish_and_return(1);
        end

        $display("PASS: sccb_config sent %0d register writes (STOP conditions)", stop_count);
        $finish;
    end
endmodule
