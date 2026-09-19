/*
 * hud.v -- survival timer (upper right) and life pips (upper left)
 *
 * The timer arrives already in BCD from game_ctrl, so this module is a font
 * lookup and some range compares -- no arithmetic on the pixel path.
 *
 * Layout of the timer field, 16 px per slot, glyphs drawn at 4x scale from a
 * 3 x 5 font (12 x 20 px on screen):
 *
 *      slot 0   slot 1   slot 2   slot 3   slot 4
 *       d3       d2       d1        .        d0
 *      100s      10s       1s              tenths
 *
 * Slot selection is just bits of the offset -- dividing by 16 is free.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module hud (
    input  wire [9:0] hpos,
    input  wire [9:0] vpos,
    input  wire [3:0] d3,
    input  wire [3:0] d2,
    input  wire [3:0] d1,
    input  wire [3:0] d0,
    input  wire [1:0] lives,
    output wire       hud_on,
    output wire [5:0] hud_rgb      // {R[1:0], G[1:0], B[1:0]}
);

    localparam [5:0] C_WHITE = 6'b11_11_11;
    localparam [5:0] C_GREEN = 6'b00_11_00;
    localparam [5:0] C_DIM   = 6'b01_01_01;

    // ------------------------------------------------------ timer readout
    localparam [11:0] TX = 12'd548;    // field spans 548 .. 627
    localparam [11:0] TY = 12'd16;

    wire [11:0] tx = {2'd0, hpos} - TX;
    wire [11:0] ty = {2'd0, vpos} - TY;

    wire in_timer  = (tx < 12'd80) && (ty < 12'd20);

    wire [2:0] slot = tx[6:4];         // 0..4
    wire [1:0] col  = tx[3:2];         // 0..3, glyph uses 0..2
    wire [2:0] row  = ty[4:2];         // 0..4

    reg [3:0] dsel;
    always @* begin
        case (slot)
            3'd0:    dsel = d3;
            3'd1:    dsel = d2;
            3'd2:    dsel = d1;
            default: dsel = d0;        // slot 4
        endcase
    end

    // 3 x 5 digit font, MSB = top-left, scanning left to right, top to bottom
    reg [14:0] glyph;
    always @* begin
        case (dsel)
            4'd0:    glyph = 15'b111_101_101_101_111;
            4'd1:    glyph = 15'b010_110_010_010_111;
            4'd2:    glyph = 15'b111_001_111_100_111;
            4'd3:    glyph = 15'b111_001_111_001_111;
            4'd4:    glyph = 15'b101_101_111_001_001;
            4'd5:    glyph = 15'b111_100_111_001_111;
            4'd6:    glyph = 15'b111_100_111_101_111;
            4'd7:    glyph = 15'b111_001_001_001_001;
            4'd8:    glyph = 15'b111_101_111_101_111;
            default: glyph = 15'b111_101_111_001_111;
        endcase
    end

    // bit index = row * 3 + col, counted down from the MSB
    wire [4:0] idx  = {1'b0, row, 1'b0} + {2'd0, row} + {3'd0, col};
    wire [3:0] bsel = 4'd14 - idx[3:0];

    wire digit_pix = in_timer && (slot != 3'd3) && (col != 2'd3) && glyph[bsel];

    // decimal point: one 4 x 4 cell at the bottom of slot 3
    wire dot_pix   = in_timer && (slot == 3'd3) && (row == 3'd4) && (col == 2'd0);

    // ---------------------------------------------------------- life pips
    localparam [11:0] LX = 12'd16;
    localparam [11:0] LY = 12'd16;

    wire [11:0] lx = {2'd0, hpos} - LX;
    wire [11:0] ly = {2'd0, vpos} - LY;

    // three 20 x 20 pips on a 32 px pitch
    wire in_lives  = (lx < 12'd96) && (ly < 12'd20) && (lx[4:0] < 5'd20);
    wire [1:0] pip = lx[6:5];
    wire pip_full  = (pip < lives);

    // ------------------------------------------------------------- output
    assign hud_on  = digit_pix | dot_pix | in_lives;
    assign hud_rgb = in_lives ? (pip_full ? C_GREEN : C_DIM) : C_WHITE;

endmodule
