module frame_buffer_640x320(
    input clk_w, we,
    input [16:0] addr_w,  // ลดเหลือ 17-bit
    input [11:0] din,
    input clk_r,
    input [16:0] addr_r,  // ลดเหลือ 17-bit
    output reg [11:0] dout
);
    // 320 * 240 = 76,800 slots
    (* RAM_STYLE="BLOCK" *)
    reg [11:0] mem [0:76799];

    always @(posedge clk_w) if (we) mem[addr_w] <= din;
    always @(posedge clk_r) dout <= mem[addr_r];
endmodule

