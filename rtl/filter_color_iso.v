`timescale 1ns/1ps
// filter_color_iso.v
// Color isolation filter: passes only the selected channel, zeros others.
// sel: 00=R, 01=G, 10=B, 11=R (default)
// in_rgb444[11:8]=R, [7:4]=G, [3:0]=B

module filter_color_iso (
    input  wire [11:0] in_rgb444,
    input  wire [1:0]  sel,
    output reg  [11:0] out_rgb444
);

    always @(*) begin
        case (sel)
            2'b00:   out_rgb444 = {in_rgb444[11:8], 4'b0000, 4'b0000}; // R only
            2'b01:   out_rgb444 = {4'b0000, in_rgb444[7:4],  4'b0000}; // G only
            2'b10:   out_rgb444 = {4'b0000, 4'b0000, in_rgb444[3:0]};  // B only
            default: out_rgb444 = {in_rgb444[11:8], 4'b0000, 4'b0000}; // R (default)
        endcase
    end

endmodule
