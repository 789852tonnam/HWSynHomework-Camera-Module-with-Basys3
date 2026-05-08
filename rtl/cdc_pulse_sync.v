`timescale 1ns/1ps
// Toggle-based pulse CDC: 1-cycle pulse in clk_src -> 1-cycle pulse in clk_dst.
// Requires pulse_in spacing >= 2 clk_dst periods.

module cdc_pulse_sync (
    input  wire clk_src,
    input  wire clk_dst,
    input  wire rst_src,
    input  wire rst_dst,
    input  wire pulse_in,
    output wire pulse_out
);

    reg toggle_src;
    initial toggle_src = 1'b0;
    always @(posedge clk_src) begin
        if (rst_src)         toggle_src <= 1'b0;
        else if (pulse_in)   toggle_src <= ~toggle_src;
    end

    (* ASYNC_REG = "TRUE" *) reg s1, s2, s3;

    always @(posedge clk_dst) begin
        if (rst_dst) {s1, s2, s3} <= 3'b0;
        else         {s1, s2, s3} <= {toggle_src, s1, s2};
    end

    assign pulse_out = s2 ^ s3;

endmodule
