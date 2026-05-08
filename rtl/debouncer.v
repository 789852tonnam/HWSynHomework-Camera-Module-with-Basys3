`timescale 1ns/1ps
// W-bit debouncer with two-flop synchronizer + N-bit stability counter.
// Output bit transitions only after the synchronized input is stable for 2^N clocks.

module debouncer #(
    parameter W = 16,
    parameter N = 20
) (
    input  wire           clk,
    input  wire [W-1:0]   sw_in,
    output reg  [W-1:0]   sw_out
);

    initial sw_out = {W{1'b0}};

    genvar i;
    generate
        for (i = 0; i < W; i = i + 1) begin : g_bit
            reg [N-1:0] cnt;
            reg         s0, s1;

            initial begin
                cnt = {N{1'b0}};
                s0  = 1'b0;
                s1  = 1'b0;
            end

            always @(posedge clk) begin
                s0 <= sw_in[i];
                s1 <= s0;

                if (s1 == sw_out[i]) begin
                    cnt <= {N{1'b0}};
                end else if (&cnt) begin
                    sw_out[i] <= s1;
                    cnt       <= {N{1'b0}};
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    endgenerate

endmodule
