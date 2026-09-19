/*
 * overlay.v -- title / game-over message overlay
 *
 * Renders two centred lines of text depending on `state`:
 *   ATTRACT    "BULLET HELL GAME"   /  "PRESS DOWN TO START"
 *   GAME OVER  "GAME OVER"          /  "PRESS DOWN TO START"
 *   PLAYING    nothing
 *
 * Same idiom as the digit font in hud.v: a ROM is just a case statement in a
 * combinational always block.  No `initial` block is used anywhere, because
 * on an ASIC flow that only reliably sets flip-flop reset values, not memory
 * contents -- a case statement synthesizes straight to gates instead.
 *
 * Geometry is chosen so every division in this module is a bit-slice:
 * each character cell is 32 px wide (8 font units x 4x scale, and 32 is a
 * power of two) and each font pixel is a 4x4 px square, so "which character"
 * and "which pixel inside the glyph" both fall out of hpos/vpos for free.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module overlay (
    input  wire [9:0] hpos,
    input  wire [9:0] vpos,
    input  wire [1:0] state,
    output wire        overlay_on,
    output wire [5:0]  overlay_rgb     // {R[1:0], G[1:0], B[1:0]}
);

    localparam [1:0] ST_OVER = 2'd2;

    localparam [5:0] C_TITLE = 6'b00_11_11;   // cyan
    localparam [5:0] C_OVER  = 6'b11_00_00;   // red
    localparam [5:0] C_INSTR = 6'b11_11_11;   // white

    // ---------------------------------------------------------- char codes
    localparam [4:0]
        C_A=5'd0,  C_B=5'd1,  C_D=5'd2,  C_E=5'd3,  C_G=5'd4,  C_H=5'd5,
        C_L=5'd6,  C_M=5'd7,  C_N=5'd8,  C_O=5'd9,  C_P=5'd10, C_R=5'd11,
        C_S=5'd12, C_T=5'd13, C_U=5'd14, C_V=5'd15, C_W=5'd16, C_SP=5'd17;

    // ----------------------------------------------------------- messages
    localparam [1:0] STR_TITLE = 2'd0;   // "BULLET HELL GAME"    16 chars
    localparam [1:0] STR_INSTR = 2'd1;   // "PRESS DOWN TO START" 19 chars
    localparam [1:0] STR_OVER  = 2'd2;   // "GAME OVER"            9 chars

    localparam [11:0] TITLE_W = 12'd512;  // 16 * 32
    localparam [11:0] INSTR_W = 12'd608;  // 19 * 32
    localparam [11:0] OVER_W  = 12'd288;  //  9 * 32

    localparam [11:0] TITLE_X = 12'd64;   // (640 - TITLE_W) / 2
    localparam [11:0] OVER_X  = 12'd176;  // (640 - OVER_W)  / 2
    localparam [11:0] INSTR_X = 12'd16;   // (640 - INSTR_W) / 2
    localparam [11:0] ROW0_Y  = 12'd180;
    localparam [11:0] ROW1_Y  = 12'd268;

    localparam [11:0] CELL = 12'd32;      // px per character cell
    localparam [11:0] GH   = 12'd28;      // glyph height, px (7 rows x 4)

    // --------------------------------------------------------- row select
    wire        show   = (state != 2'd1);              // hidden in PLAYING
    wire [1:0]  top_str = (state == ST_OVER) ? STR_OVER : STR_TITLE;
    wire [11:0] top_x0  = (state == ST_OVER) ? OVER_X   : TITLE_X;
    wire [11:0] top_w   = (state == ST_OVER) ? OVER_W   : TITLE_W;

    wire [11:0] ry0 = {2'd0, vpos} - ROW0_Y;
    wire [11:0] ry1 = {2'd0, vpos} - ROW1_Y;
    wire in_row0 = show && (ry0 < GH);
    wire in_row1 = show && (ry1 < GH);

    wire [1:0]  sel_str = in_row0 ? top_str : STR_INSTR;
    wire [11:0] sel_x0  = in_row0 ? top_x0  : INSTR_X;
    wire [11:0] sel_w   = in_row0 ? top_w   : INSTR_W;
    wire [11:0] sel_ry  = in_row0 ? ry0     : ry1;
    wire [5:0]  sel_rgb = in_row0 ? ((state == ST_OVER) ? C_OVER : C_TITLE)
                                  : C_INSTR;

    // ------------------------------------------------- character position
    wire [11:0] rx        = {2'd0, hpos} - sel_x0;
    wire        in_row_x  = rx < sel_w;
    wire [4:0]  char_idx  = rx[9:5];      // rx / 32,  0..18
    wire [4:0]  col_px    = rx[4:0];      // rx % 32
    wire [4:0]  row_px    = sel_ry[4:0];  // 0..27
    wire [2:0]  font_col  = col_px[4:2];  // col_px / 4, 0..7
    wire [2:0]  font_row  = row_px[4:2];  // row_px / 4, 0..6

    // ----------------------------------------------------- string -> code
    reg [4:0] code;
    always @* begin
        case (sel_str)
            STR_TITLE: case (char_idx)      // "BULLET HELL GAME"
                5'd0:  code = C_B;  5'd1:  code = C_U;  5'd2:  code = C_L;
                5'd3:  code = C_L;  5'd4:  code = C_E;  5'd5:  code = C_T;
                5'd6:  code = C_SP; 5'd7:  code = C_H;  5'd8:  code = C_E;
                5'd9:  code = C_L;  5'd10: code = C_L;  5'd11: code = C_SP;
                5'd12: code = C_G;  5'd13: code = C_A;  5'd14: code = C_M;
                5'd15: code = C_E;
                default: code = C_SP;
            endcase
            STR_INSTR: case (char_idx)      // "PRESS DOWN TO START"
                5'd0:  code = C_P;  5'd1:  code = C_R;  5'd2:  code = C_E;
                5'd3:  code = C_S;  5'd4:  code = C_S;  5'd5:  code = C_SP;
                5'd6:  code = C_D;  5'd7:  code = C_O;  5'd8:  code = C_W;
                5'd9:  code = C_N;  5'd10: code = C_SP; 5'd11: code = C_T;
                5'd12: code = C_O;  5'd13: code = C_SP; 5'd14: code = C_S;
                5'd15: code = C_T;  5'd16: code = C_A;  5'd17: code = C_R;
                5'd18: code = C_T;
                default: code = C_SP;
            endcase
            STR_OVER: case (char_idx)       // "GAME OVER"
                5'd0: code = C_G;  5'd1: code = C_A;  5'd2: code = C_M;
                5'd3: code = C_E;  5'd4: code = C_SP; 5'd5: code = C_O;
                5'd6: code = C_V;  5'd7: code = C_E;  5'd8: code = C_R;
                default: code = C_SP;
            endcase
            default: code = C_SP;
        endcase
    end

    // ------------------------------------------------------- code -> glyph
    // 5 x 7 font, packed MSB-first: bit 34 is the top-left pixel, bit 0 is
    // the bottom-right pixel.
    reg [34:0] glyph;
    always @* begin
        case (code)
            C_A: glyph = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            C_B: glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
            C_D: glyph = {5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
            C_E: glyph = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
            C_G: glyph = {5'b01110,5'b10001,5'b10000,5'b10011,5'b10001,5'b10001,5'b01110};
            C_H: glyph = {5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            C_L: glyph = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
            C_M: glyph = {5'b10001,5'b11011,5'b10101,5'b10001,5'b10001,5'b10001,5'b10001};
            C_N: glyph = {5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
            C_O: glyph = {5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            C_P: glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
            C_R: glyph = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
            C_S: glyph = {5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
            C_T: glyph = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
            C_U: glyph = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            C_V: glyph = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
            C_W: glyph = {5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b11011,5'b10001};
            default: glyph = 35'b0;              // space
        endcase
    end

    // Row R, column C (0 = leftmost) sits at bit (34 - 5*R - C).  5*R is a
    // small-constant multiply, i.e. free after synthesis, but this table
    // sidesteps the `*` operator entirely to keep the whole module
    // divide/multiply-free, matching the rest of this design.
    reg [5:0] row_base;
    always @* begin
        case (font_row)
            3'd0: row_base = 6'd0;
            3'd1: row_base = 6'd5;
            3'd2: row_base = 6'd10;
            3'd3: row_base = 6'd15;
            3'd4: row_base = 6'd20;
            3'd5: row_base = 6'd25;
            default: row_base = 6'd30;           // font_row == 6
        endcase
    end

    wire       glyph_col_ok = font_col < 3'd5;    // cols 5..7 are letter gap

    // Zero the column term outside the glyph so bit_idx never leaves 0..34,
    // even before glyph_col_ok masks the result below -- a variable
    // bit-select that could stray outside the vector's declared range is
    // worth avoiding on its own, not just relying on the AND to hide it.
    wire [5:0] col_term = glyph_col_ok ? {3'd0, font_col} : 6'd0;
    wire [5:0] bit_idx  = 6'd34 - row_base - col_term;
    wire       pixel_on = glyph_col_ok && glyph[bit_idx];

    assign overlay_on  = (in_row0 | in_row1) && in_row_x && pixel_on;
    assign overlay_rgb = sel_rgb;

endmodule
