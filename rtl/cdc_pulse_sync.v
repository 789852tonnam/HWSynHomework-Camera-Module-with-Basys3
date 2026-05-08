`timescale 1ns/1ps
// cdc_pulse_sync.v
// Clock-domain crossing: converts a single-cycle pulse in clk_src domain
// to a single-cycle pulse in clk_dst domain using a toggle-based synchronizer.
//
// Methodology:
//   1. Toggle a flag in clk_src on each pulse_in.
//   2. Synchronize the flag through a 2-FF metastability chain in clk_dst.
//   3. XOR adjacent samples in clk_dst to detect the toggle → one-cycle pulse_out.
//
// Latency: 2–3 clk_dst cycles.
// Constraints: pulse_in must be a single cycle in clk_src and the minimum
// interval between pulses must be >2 clk_dst periods (typical CDC rule).

module cdc_pulse_sync (
    input  wire clk_src,      // source clock (e.g. PCLK ~24 MHz)
    input  wire clk_dst,      // destination clock (e.g. clk_25)
    input  wire rst_src,      // synchronous reset in clk_src domain (clears toggle)
    input  wire rst_dst,      // synchronous reset in clk_dst domain
    input  wire pulse_in,     // single-cycle pulse in clk_src domain
    output wire pulse_out     // single-cycle pulse in clk_dst domain
);

    // Toggle flip-flop in clk_src domain
    reg toggle_src;
    initial toggle_src = 1'b0;   // simulation init; synthesis ignores this
    always @(posedge clk_src) begin
        if (rst_src)
            toggle_src <= 1'b0;
        else if (pulse_in)
            toggle_src <= ~toggle_src;
    end

    // 3-FF synchronizer in clk_dst domain (2 for metastability, 1 for edge detect)
    // Initialized to 0 on reset; after rst releases they will track toggle_src.
    // Since rst_src also zeros toggle_src, the FFs and toggle will converge
    // to the same value (0) before rst_dst is released.
    (* ASYNC_REG = "TRUE" *)
    reg sync_ff1, sync_ff2, sync_ff3;

    always @(posedge clk_dst) begin
        if (rst_dst) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
            sync_ff3 <= 1'b0;
        end else begin
            sync_ff1 <= toggle_src;
            sync_ff2 <= sync_ff1;
            sync_ff3 <= sync_ff2;
        end
    end

    // Edge detect: XOR detects toggle
    assign pulse_out = sync_ff2 ^ sync_ff3;

endmodule
