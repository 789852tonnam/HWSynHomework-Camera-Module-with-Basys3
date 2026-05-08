`timescale 1ns/1ps
// Split luma + chroma frame buffer for YCbCr 4:2:2 storage.
//
// Luma:   307,200 entries x 3 bits  (Y per pixel)        ~30 BRAM36 tiles
// Chroma: 153,600 entries x 4 bits  (Cb2/Cr2 per pair)   ~20 BRAM36 tiles
// Total: ~50 / 50 BRAM36 on XC7A35T (full utilization).
//
// Chroma is shared between adjacent horizontal pixels (4:2:2 subsampling).
// Even columns write chroma; odd columns read the same chroma word as the
// preceding even column (rd_addr[18:1] selects the chroma pair).
//
// Read latency: 1 cycle (synchronous BRAM read).

module frame_buffer (
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [2:0]  wr_luma,
    input  wire [3:0]  wr_chroma,
    input  wire        wr_chroma_en,

    input  wire        rd_clk,
    input  wire [18:0] rd_addr,
    output reg  [2:0]  rd_luma,
    output reg  [3:0]  rd_chroma
);

    (* ram_style = "block" *) reg [2:0] luma_mem   [0:307199];
    (* ram_style = "block" *) reg [3:0] chroma_mem [0:153599];

    wire [17:0] wr_chroma_addr = wr_addr[18:1];
    wire [17:0] rd_chroma_addr = rd_addr[18:1];

    always @(posedge wr_clk) begin
        if (wr_en)
            luma_mem[wr_addr] <= wr_luma;
    end

    always @(posedge wr_clk) begin
        if (wr_en && wr_chroma_en)
            chroma_mem[wr_chroma_addr] <= wr_chroma;
    end

    always @(posedge rd_clk) rd_luma   <= luma_mem[rd_addr];
    always @(posedge rd_clk) rd_chroma <= chroma_mem[rd_chroma_addr];

endmodule
