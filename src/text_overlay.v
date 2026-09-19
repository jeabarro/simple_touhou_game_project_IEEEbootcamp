/*
 * text_overlay.v -- title screen and game-over screen text
 *
 *   ATTRACT     BULLET HELL GAME        (big, yellow)
 *               PRESS DOWN TO START     (small, white)
 *
 *   GAME OVER   GAME OVER               (big, yellow)
 *               PRESS DOWN TO START     (small, white)
 *
 *   PLAYING     nothing
 *
 * Same idea as the timer in hud.v: no framebuffer, no per-character state.
 * Every pixel works out "which character cell am I in, which cell of that
 * glyph, is that cell lit" from hpos/vpos with subtracts and bit slices.
 *
 * Glyphs are 3 x 5 cells plus one blank column, so a character pitch is
 * 4 cells.  The cell size is a power of two, which turns every divide into
 * a bit slice:
 *
 *      big line    8 px cells -> glyph 24 x 40, pitch 32   (bits [8:5] pick the char)
 *      small line  4 px cells -> glyph 12 x 20, pitch 16   (bits [8:4] pick the char)
 *
 * The two lines never overlap vertically, so they share ONE font ROM: the
 * pixel path muxes (char code, cell column, cell row) first and looks the
 * glyph up once.
 *
 * To change a message, edit the two `case` tables below.  Characters not in
 * the font (anything outside A B D E G H L M N O P R S T U V W) need a new
 * glyph entry and a new C_xxx code.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module text_overlay (
    input  wire [9:0] hpos,
    input  wire [9:0] vpos,
    input  wire [1:0] state,        // 0 ATTRACT, 1 PLAYING, 2 GAME OVER
    output wire       text_on,
    output wire [5:0] text_rgb      // {R[1:0], G[1:0], B[1:0]}
);

    localparam [1:0] ST_PLAYING = 2'd1,
                     ST_OVER    = 2'd2;

    localparam [5:0] C_HEAD   = 6'b11_11_00;   // yellow headline
    localparam [5:0] C_PROMPT = 6'b11_11_11;   // white prompt

    // ------------------------------------------------------------ layout
    localparam [9:0] BIG_Y   = 10'd176;        // top of the headline
    localparam [9:0] SMALL_Y = 10'd288;        // top of the prompt
    localparam [9:0] SMALL_X = 10'd168;        // 19 chars * 16 px = 304 px, centred

    // The headline changes length, so it changes start column to stay centred:
    //   BULLET HELL GAME  16 chars * 32 = 512 px -> starts at  64
    //   GAME OVER          9 chars * 32 = 288 px -> starts at 176
    wire over = (state == ST_OVER);
    wire show = (state != ST_PLAYING);

    // ------------------------------------------------- character codes
    localparam [4:0] C_SP = 5'd0,  C_A = 5'd1,  C_B = 5'd2,  C_D = 5'd3,
                     C_E  = 5'd4,  C_G = 5'd5,  C_H = 5'd6,  C_L = 5'd7,
                     C_M  = 5'd8,  C_N = 5'd9,  C_O = 5'd10, C_P = 5'd11,
                     C_R  = 5'd12, C_S = 5'd13, C_T = 5'd14, C_U = 5'd15,
                     C_V  = 5'd16, C_W = 5'd17;

    // --------------------------------------------------- headline (big)
    wire [9:0] bx = hpos - (over ? 10'd176 : 10'd64);
    wire [9:0] by = vpos - BIG_Y;
    wire       in_big = show && (bx < (over ? 10'd288 : 10'd512)) && (by < 10'd40);

    reg [4:0] ch_big;
    always @* begin
        if (over) begin
            case (bx[8:5])                       //  G A M E _ O V E R
                4'd0:    ch_big = C_G;
                4'd1:    ch_big = C_A;
                4'd2:    ch_big = C_M;
                4'd3:    ch_big = C_E;
                4'd5:    ch_big = C_O;
                4'd6:    ch_big = C_V;
                4'd7:    ch_big = C_E;
                4'd8:    ch_big = C_R;
                default: ch_big = C_SP;
            endcase
        end else begin
            case (bx[8:5])                       //  B U L L E T _ H E L L _ G A M E
                4'd0:    ch_big = C_B;
                4'd1:    ch_big = C_U;
                4'd2:    ch_big = C_L;
                4'd3:    ch_big = C_L;
                4'd4:    ch_big = C_E;
                4'd5:    ch_big = C_T;
                4'd7:    ch_big = C_H;
                4'd8:    ch_big = C_E;
                4'd9:    ch_big = C_L;
                4'd10:   ch_big = C_L;
                4'd12:   ch_big = C_G;
                4'd13:   ch_big = C_A;
                4'd14:   ch_big = C_M;
                4'd15:   ch_big = C_E;
                default: ch_big = C_SP;
            endcase
        end
    end

    // --------------------------------------------------- prompt (small)
    wire [9:0] sx = hpos - SMALL_X;
    wire [9:0] sy = vpos - SMALL_Y;
    wire       in_small = show && (sx < 10'd304) && (sy < 10'd20);

    reg [4:0] ch_small;
    always @* begin
        case (sx[8:4])                           //  P R E S S _ D O W N _ T O _ S T A R T
            5'd0:    ch_small = C_P;
            5'd1:    ch_small = C_R;
            5'd2:    ch_small = C_E;
            5'd3:    ch_small = C_S;
            5'd4:    ch_small = C_S;
            5'd6:    ch_small = C_D;
            5'd7:    ch_small = C_O;
            5'd8:    ch_small = C_W;
            5'd9:    ch_small = C_N;
            5'd11:   ch_small = C_T;
            5'd12:   ch_small = C_O;
            5'd14:   ch_small = C_S;
            5'd15:   ch_small = C_T;
            5'd16:   ch_small = C_A;
            5'd17:   ch_small = C_R;
            5'd18:   ch_small = C_T;
            default: ch_small = C_SP;
        endcase
    end

    // ----------------------------------------- one shared glyph lookup
    wire [4:0] code = in_big ? ch_big  : ch_small;
    wire [1:0] col  = in_big ? bx[4:3] : sx[3:2];   // 0..2 glyph, 3 = spacing
    wire [2:0] row  = in_big ? by[5:3] : sy[4:2];   // 0..4

    // 3 x 5 font, MSB = top-left, scanning left to right, top to bottom
    reg [14:0] glyph;
    always @* begin
        case (code)
            C_A:     glyph = 15'b010_101_111_101_101;
            C_B:     glyph = 15'b110_101_111_101_110;
            C_D:     glyph = 15'b110_101_101_101_110;
            C_E:     glyph = 15'b111_100_110_100_111;
            C_G:     glyph = 15'b111_100_101_101_111;
            C_H:     glyph = 15'b101_101_111_101_101;
            C_L:     glyph = 15'b100_100_100_100_111;
            C_M:     glyph = 15'b111_111_111_101_101;
            C_N:     glyph = 15'b110_101_101_101_101;
            C_O:     glyph = 15'b111_101_101_101_111;
            C_P:     glyph = 15'b110_101_110_100_100;
            C_R:     glyph = 15'b110_101_110_101_101;
            C_S:     glyph = 15'b111_100_111_001_111;
            C_T:     glyph = 15'b111_010_010_010_010;
            C_U:     glyph = 15'b101_101_101_101_111;
            C_V:     glyph = 15'b101_101_101_101_010;
            C_W:     glyph = 15'b101_101_101_111_101;
            default: glyph = 15'b000_000_000_000_000;   // space
        endcase
    end

    // bit index = row * 3 + col, counted down from the MSB
    wire [3:0] idx  = {row, 1'b0} + {1'b0, row} + {2'd0, col};
    wire [3:0] bsel = 4'd14 - idx;

    assign text_on  = (in_big | in_small) && (col != 2'd3) && glyph[bsel];
    assign text_rgb = in_big ? C_HEAD : C_PROMPT;

endmodule
