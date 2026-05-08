`timescale 1ns/1ps
// rgb121_to_rgb444.v
// Expands 4-bit RGB121 pixel to 12-bit RGB444 by bit replication.
// RGB121 encoding: [3]=R1, [2:1]=G2, [0]=B1
// RGB444 encoding: [11:8]=R4, [7:4]=G4, [3:0]=B4

module rgb121_to_rgb444 (
    input  wire [3:0]  in_rgb121,
    output wire [11:0] out_rgb444
);

    wire r1  = in_rgb121[3];
    wire [1:0] g2 = in_rgb121[2:1];
    wire b1  = in_rgb121[0];

    // R4 = {R,R,R,R}
    wire [3:0] r4 = {r1, r1, r1, r1};
    // G4 = {G[1],G[0],G[1],G[0]}
    wire [3:0] g4 = {g2[1], g2[0], g2[1], g2[0]};
    // B4 = {B,B,B,B}
    wire [3:0] b4 = {b1, b1, b1, b1};

    assign out_rgb444 = {r4, g4, b4};

endmodule
