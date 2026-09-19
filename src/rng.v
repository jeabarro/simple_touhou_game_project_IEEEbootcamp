/*
 * rng.v -- 16-bit Galois LFSR + weighted attack-pattern picker
 *
 * The LFSR free-runs at the pixel clock and is NEVER stopped or reseeded.
 * That is deliberate: the seed the player actually gets is determined by how
 * many clocks elapse between reset and them pressing DOWN, which is
 * effectively unpredictable.
 *
 * pattern_id is combinational and changes every clock.  attack_seq latches it
 * at the instant a new wave begins.
 *
 * Weighting: an 8-bit draw compared against a cumulative threshold ladder.
 * Retune the game's feel by editing W1..W4 only -- nothing else depends on it.
 *
 *   id 0  falling bars      77/256 = 30.1 %
 *   id 1  radiating diamond 56/256 = 21.9 %
 *   id 2  crunching diamond 56/256 = 21.9 %
 *   id 3  sweeping box      46/256 = 18.0 %
 *   id 4  side walls        21/256 =  8.2 %
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module rng (
    input  wire        clk,
    input  wire        rst_n,
    output wire [15:0] rnd,
    output reg  [2:0]  pattern_id
);

    // cumulative thresholds -- must be non-decreasing and < 256
    localparam [7:0] W1 = 8'd77;    // end of pattern 0
    localparam [7:0] W2 = 8'd133;   // end of pattern 1
    localparam [7:0] W3 = 8'd189;   // end of pattern 2
    localparam [7:0] W4 = 8'd235;   // end of pattern 3, rest is pattern 4

    reg [15:0] lfsr;

    always @(posedge clk) begin
        if (!rst_n)
            lfsr <= 16'hACE1;                       // any non-zero seed
        else
            lfsr <= lfsr[0] ? ({1'b0, lfsr[15:1]} ^ 16'hB400)
                            :  {1'b0, lfsr[15:1]};
    end

    assign rnd = lfsr;

    wire [7:0] draw = lfsr[7:0];

    always @* begin
        if      (draw < W1) pattern_id = 3'd0;
        else if (draw < W2) pattern_id = 3'd1;
        else if (draw < W3) pattern_id = 3'd2;
        else if (draw < W4) pattern_id = 3'd3;
        else                pattern_id = 3'd4;
    end

endmodule
