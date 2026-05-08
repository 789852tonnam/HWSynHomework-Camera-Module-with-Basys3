`timescale 1ns/1ps
// debouncer.v
// Generic debouncer for W-bit input.
// Each bit uses a N-bit counter; output only changes after input is
// stable for 2^N cycles (~10 ms at 100 MHz with N=20).

module debouncer #(
    parameter W = 16,
    parameter N = 20
) (
    input  wire           clk,
    input  wire [W-1:0]   sw_in,
    output reg  [W-1:0]   sw_out
);

    genvar i;
    generate
        for (i = 0; i < W; i = i + 1) begin : gen_deb
            reg [N-1:0] cnt;
            reg         sync0, sync1;

            // Initialise to known values in simulation
            initial begin
                cnt   = {N{1'b0}};
                sync0 = 1'b0;
                sync1 = 1'b0;
            end

            always @(posedge clk) begin
                // Two-flop synchronizer to bring async input on-chip
                sync0 <= sw_in[i];
                sync1 <= sync0;

                if (sync1 == sw_out[i]) begin
                    cnt <= {N{1'b0}};
                end else begin
                    cnt <= cnt + 1'b1;
                    if (cnt == {N{1'b1}}) begin
                        sw_out[i] <= sync1;
                        cnt        <= {N{1'b0}};
                    end
                end
            end
        end
    endgenerate

    // Initialise outputs (synthesis will treat as reset-less FF initial value)
    initial sw_out = {W{1'b0}};

endmodule
