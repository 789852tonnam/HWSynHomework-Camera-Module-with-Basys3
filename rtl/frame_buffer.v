`timescale 1ns/1ps
// frame_buffer.v
// Split luma/chroma frame buffer for YCbCr 4:2:2 encoding.
//
// Luma buffer:   307,200 × 3 bits  (Y per pixel)      → 30 BRAM36K tiles
// Chroma buffer: 153,600 × 4 bits  (Cb2+Cr2 per pair) → 20 BRAM36K tiles
// Total: 50/50 BRAM36K tiles (100% utilization on XC7A35T)
//
// Write port clocked by pclk_in (camera PCLK ~24 MHz).
// Read port clocked by clk_25  (VGA pixel clock 25 MHz).
//
// Chroma is shared between horizontal pixel pairs:
//   pixel pair address = pixel_addr[18:1]  (÷2)
//   Even-column pixel writes chroma; odd-column pixel does not update chroma.

module frame_buffer (
    // Write port (camera side)
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,       // 0..307199 (pixel address)
    input  wire [2:0]  wr_luma,       // Y (3 bits)
    input  wire [3:0]  wr_chroma,     // {Cb[1:0], Cr[1:0]} (4 bits)
    input  wire        wr_chroma_en,  // write chroma (high on even columns)

    // Read port (VGA side)
    input  wire        rd_clk,
    input  wire [18:0] rd_addr,       // 0..307199 (pixel address)
    output reg  [2:0]  rd_luma,       // Y (1-cycle latency)
    output reg  [3:0]  rd_chroma      // {Cb[1:0], Cr[1:0]} (1-cycle latency)
);

    // --- Luma memory: 307,200 × 3 ---
    (* ram_style = "block" *)
    reg [2:0] luma_mem [0:307199];

    // --- Chroma memory: 153,600 × 4 ---
    // Indexed by pixel_addr[18:1] (pair address)
    (* ram_style = "block" *)
    reg [3:0] chroma_mem [0:153599];

    // Chroma pair addresses
    wire [17:0] wr_chroma_addr = wr_addr[18:1];
    wire [17:0] rd_chroma_addr = rd_addr[18:1];

    // Write port — luma
    always @(posedge wr_clk) begin
        if (wr_en)
            luma_mem[wr_addr] <= wr_luma;
    end

    // Write port — chroma (only on even columns)
    always @(posedge wr_clk) begin
        if (wr_en && wr_chroma_en)
            chroma_mem[wr_chroma_addr] <= wr_chroma;
    end

    // Read port — luma (synchronous, 1-cycle latency)
    always @(posedge rd_clk) begin
        rd_luma <= luma_mem[rd_addr];
    end

    // Read port — chroma (synchronous, 1-cycle latency)
    always @(posedge rd_clk) begin
        rd_chroma <= chroma_mem[rd_chroma_addr];
    end

endmodule
