`timescale 1ns/1ps
// line_buffer3.v
// 3-line circular shift buffer for 3×3 Sobel neighbourhood.
//
// Stores the last 3 rows of LUMA values from the frame buffer.
// Uses 3 RAM arrays of 640 × 3 bits indexed by column.
// Uses distributed RAM (LUTs) since all BRAM is consumed by the
// frame buffer. Cost: ~140 LUTs out of 20,800 available.
// On each pixel clock:
//   - Current pixel is written into the "write" line.
//   - The three output lines (top, mid, bot) are the three RAM lines
//     rotationally indexed by (row mod 3).
// Left/right edge pixels (col=0 and col=639) cause the 3×3 window to
// be zero-padded at the caller level (filter_edge checks h_count/v_count).
//
// Parameters:
//   WIDTH  - line width in pixels (default 640)

module line_buffer3 #(
    parameter WIDTH = 640
) (
    input  wire        clk,
    input  wire        rst,

    // Pixel input
    input  wire [2:0]  pix_in,         // current pixel luma (Y, 3 bits)
    input  wire        pix_valid,      // write enable (high during active video)

    // Position
    input  wire [9:0]  h_count,        // 0..WIDTH-1
    input  wire [9:0]  v_count,        // 0..479

    // 3×3 neighbourhood outputs (top=2 rows back, mid=1 row back, bot=current)
    // Columns: _l = col-1 (left), _c = col (centre), _r = col+1 (right)
    output reg  [2:0]  top_l, top_c, top_r,
    output reg  [2:0]  mid_l, mid_c, mid_r,
    output reg  [2:0]  bot_l, bot_c, bot_r
);

    // Three line buffers — distributed RAM (LUTs) since all BRAM is
    // consumed by the frame buffer. 3 × 640 × 3 bits ≈ 140 LUTs.
    (* ram_style = "distributed" *)
    reg [2:0] lb [0:2][0:WIDTH-1];

    // Initialize memory to zero (simulation safety; synthesis ignores initial)
    integer _ii, _jj;
    initial begin
        for (_ii = 0; _ii < 3; _ii = _ii + 1)
            for (_jj = 0; _jj < WIDTH; _jj = _jj + 1)
                lb[_ii][_jj] = 3'b0;
    end

    // wr_idx: which physical buffer is currently being WRITTEN.
    // Advances at the end of each line (last pixel of row).
    // After row N finishes, wr_idx points to where row N+1 will go.
    //
    // Read indices are derived from wr_idx to reflect the most recently
    // completed rows:
    //   rd_bot = (wr_idx + 2) % 3  → buffer written two advances ago (row N)
    //   rd_mid = (wr_idx + 1) % 3  → buffer written one advance ago  (row N-1)
    //   rd_top = wr_idx % 3        → buffer next in queue             (row N-2)
    reg [1:0] wr_idx;    // 0, 1, or 2

    // rd_bot = (wr_idx + 2) % 3   most recently completed row
    // rd_mid = (wr_idx + 1) % 3   one row older
    // rd_top = wr_idx % 3         two rows older (oldest of the three)
    wire [1:0] rd_bot_idx = (wr_idx == 2'd0) ? 2'd2 :
                            (wr_idx == 2'd1) ? 2'd0 : 2'd1;
    wire [1:0] rd_mid_idx = (wr_idx == 2'd0) ? 2'd1 :
                            (wr_idx == 2'd1) ? 2'd2 : 2'd0;
    wire [1:0] rd_top_idx = wr_idx;

    // -----------------------------------------------------------------------
    // Write: store current pixel into the current write buffer
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (pix_valid) begin
            lb[wr_idx][h_count] <= pix_in;
        end
    end

    // Advance wr_idx at the end of each line (last pixel clocked in)
    always @(posedge clk) begin
        if (rst) begin
            wr_idx <= 2'd0;
        end else if (pix_valid && h_count == WIDTH - 1) begin
            wr_idx <= (wr_idx == 2'd2) ? 2'd0 : wr_idx + 2'd1;
        end
    end

    // -----------------------------------------------------------------------
    // Read: latch 3×3 neighbourhood (registered — 1-cycle read latency)
    // Left  column: h_count > 0       ? h_count-1 : 0
    // Centre column: h_count
    // Right column: h_count < WIDTH-1 ? h_count+1 : WIDTH-1
    // Edge zeroing is left to filter_edge.
    // -----------------------------------------------------------------------
    wire [9:0] col_l = (h_count > 0)          ? h_count - 10'd1 : 10'd0;
    wire [9:0] col_c = h_count;
    wire [9:0] col_r = (h_count < WIDTH - 1)  ? h_count + 10'd1 : (WIDTH - 1);

    always @(posedge clk) begin
        // Top row (2 rows back)
        top_l <= lb[rd_top_idx][col_l];
        top_c <= lb[rd_top_idx][col_c];
        top_r <= lb[rd_top_idx][col_r];
        // Middle row (1 row back)
        mid_l <= lb[rd_mid_idx][col_l];
        mid_c <= lb[rd_mid_idx][col_c];
        mid_r <= lb[rd_mid_idx][col_r];
        // Bottom row (most recently completed row)
        bot_l <= lb[rd_bot_idx][col_l];
        bot_c <= lb[rd_bot_idx][col_c];
        bot_r <= lb[rd_bot_idx][col_r];
    end

endmodule
