`timescale 1ns/1ps
// Verifies SCCB 3-byte write FSM:
//   - START condition (SDA falls while SCL high)
//   - 27 bit-slots driven over SCL toggles
//   - master releases SDA in 3 ACK slots (slave high -> ack=1 NAK-style)
//   - STOP condition (SDA rises while SCL high)
//   - done pulse + busy clears
module tb_sccb_master;
    reg clk = 0;
    always #5 clk = ~clk;     // 100 MHz

    reg        rst   = 1;
    reg        start = 0;
    reg  [7:0] id    = 8'h42;
    reg  [7:0] sub   = 8'h12;
    reg  [7:0] data  = 8'h80;
    wire       done, busy, ack_id, ack_sub, ack_data;
    wire       scl;
    wire       sda;

    // External pull-up emulation: when DUT releases SDA (Z), it reads as 1.
    pullup(sda);
    pullup(scl);

    sccb_master #(.HALF_PER_CYCLES(4)) dut (
        .clk(clk), .rst(rst),
        .start(start), .id(id), .sub_addr(sub), .data(data),
        .done(done), .busy(busy),
        .ack_id(ack_id), .ack_sub(ack_sub), .ack_data(ack_data),
        .scl(scl), .sda(sda)
    );

    // Edge counters for sanity
    integer scl_falls = 0;
    integer scl_rises = 0;
    reg     scl_prev  = 1'b1;
    integer done_count = 0;
    reg     start_seen = 0;
    reg     stop_seen  = 0;
    reg     sda_prev   = 1'b1;

    always @(posedge clk) begin
        // SCL edge counts
        if (scl_prev && !scl) scl_falls = scl_falls + 1;
        if (!scl_prev &&  scl) scl_rises = scl_rises + 1;
        scl_prev <= scl;

        // START = SDA fall while SCL high
        if (scl && sda_prev && !sda) start_seen <= 1'b1;
        // STOP  = SDA rise while SCL high (after START was seen)
        if (scl && !sda_prev && sda && start_seen) stop_seen <= 1'b1;
        sda_prev <= sda;

        if (done) done_count = done_count + 1;
    end

    initial begin
        $dumpfile("sim/sccb_master.vcd");
        $dumpvars(0, tb_sccb_master);

        repeat (4) @(posedge clk);
        rst = 0;
        repeat (4) @(posedge clk);

        // Kick a transaction
        @(posedge clk); start <= 1'b1;
        @(posedge clk); start <= 1'b0;

        // Wait for done (worst-case ~ 27 bits * 4 phases * HALF_PER + STOP)
        // 27 * 2 * 4 + start + 3*stop ~ 240 cycles. Wait generously.
        begin : wait_done
            integer t;
            for (t = 0; t < 5000; t = t + 1) begin
                @(posedge clk);
                if (done) disable wait_done;
            end
            $display("FAIL: timeout waiting for done");
            $finish_and_return(1);
        end

        // After done, busy must clear within a couple cycles
        @(posedge clk);
        if (busy !== 1'b0) begin
            $display("FAIL: busy still high after done");
            $finish_and_return(1);
        end

        // Each bit phase has SCL low+high -> at least 27 SCL-rising edges
        if (scl_rises < 27) begin
            $display("FAIL: only %0d SCL rises, expected >=27", scl_rises);
            $finish_and_return(1);
        end
        if (!start_seen) begin
            $display("FAIL: START condition not detected");
            $finish_and_return(1);
        end
        if (!stop_seen) begin
            $display("FAIL: STOP condition not detected");
            $finish_and_return(1);
        end
        // Slave never pulls SDA -> all ACKs read as 1 (NAK)
        if (ack_id !== 1'b1 || ack_sub !== 1'b1 || ack_data !== 1'b1) begin
            $display("FAIL: ack_id=%b ack_sub=%b ack_data=%b expected 1/1/1 (no slave)",
                     ack_id, ack_sub, ack_data);
            $finish_and_return(1);
        end
        if (done_count !== 1) begin
            $display("FAIL: done pulsed %0d times, expected 1", done_count);
            $finish_and_return(1);
        end

        $display("PASS: SCCB master: START+27 bits+STOP, done=%0d, scl_rises=%0d",
                 done_count, scl_rises);
        $finish;
    end
endmodule
