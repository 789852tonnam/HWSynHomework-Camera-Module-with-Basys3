`timescale 1ns/1ps
// filter_invert.v
// Color inversion filter: bitwise NOT of RGB444.

module filter_invert (
    input  wire [11:0] in_rgb444,
    output wire [11:0] out_rgb444
);

    assign out_rgb444 = ~in_rgb444;

endmodule
