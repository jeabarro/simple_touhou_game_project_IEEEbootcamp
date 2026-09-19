/*
 * renderer.v -- priority mux down to 2-bit R / G / B
 *
 * Priority, highest first:
 *      HUD  >  player core  >  player body  >  text  >  bullets  >  background
 *
 * The player is drawn ON TOP of bullets so you can always see yourself in a
 * dense wave.  That is exactly why bullets.v taps its own `bullet_on` signal
 * for collision instead of reading the final pixel colour.
 *
 * ----------------------------------------------------------------------
 * The ship
 * ----------------------------------------------------------------------
 * 10 x 10 px, drawn from a 5 x 5 bitmap of 2 x 2 px cells, so it stays small
 * against the 32-48 px bullets but is still blocky enough to read.  The sprite
 * changes with the buttons held (`face`, from player.v):
 *
 *      nothing held      square
 *      one direction     triangle pointing that way
 *      two directions    corner triangle pointing diagonally
 *      game over         X
 *
 * The 4 x 4 white core marks the hitbox and is drawn in every live sprite so
 * near-misses stay legible.  It is not drawn once the ship is dead.
 *
 * To redraw a sprite, edit its 5 x 5 pattern in the SP_xxx table below:
 * 1 = lit cell, top row first.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module renderer (
    input  wire [9:0] hpos,
    input  wire [9:0] vpos,
    input  wire       video_active,
    input  wire [1:0] state,
    input  wire [9:0] player_px,
    input  wire [9:0] player_py,
    input  wire       player_visible,
    input  wire [3:0] face,           // {up, down, left, right}
    input  wire       bullet_on,
    input  wire       hud_on,
    input  wire [5:0] hud_rgb,
    input  wire       text_on,
    input  wire [5:0] text_rgb,
    output reg  [1:0] R,
    output reg  [1:0] G,
    output reg  [1:0] B
);

    localparam [1:0] ST_OVER = 2'd2;

    localparam [5:0] C_BG      = 6'b00_00_01;   // deep blue
    localparam [5:0] C_BG_OVER = 6'b01_00_00;   // dull red on game over
    localparam [5:0] C_BULLET  = 6'b11_01_00;   // hot orange
    localparam [5:0] C_SHIP    = 6'b00_11_11;   // cyan
    localparam [5:0] C_CORE    = 6'b11_11_11;   // white hitbox marker
    localparam [5:0] C_DEAD    = 6'b11_11_11;   // white X

    localparam [11:0] HALF = 12'd5;

    wire dead = (state == ST_OVER);

    // ------------------------------------------------------------ sprites
    // 5 x 5 cells, top row first, 1 = lit.
    localparam [24:0] SP_IDLE = { 5'b11111,
                                  5'b11111,
                                  5'b11111,
                                  5'b11111,
                                  5'b11111 };

    localparam [24:0] SP_UP   = { 5'b00100,
                                  5'b01110,
                                  5'b01110,
                                  5'b11111,
                                  5'b11111 };

    localparam [24:0] SP_DOWN = { 5'b11111,
                                  5'b11111,
                                  5'b01110,
                                  5'b01110,
                                  5'b00100 };

    localparam [24:0] SP_LEFT = { 5'b00011,
                                  5'b01111,
                                  5'b11111,
                                  5'b01111,
                                  5'b00011 };

    localparam [24:0] SP_RIGHT = { 5'b11000,
                                   5'b11110,
                                   5'b11111,
                                   5'b11110,
                                   5'b11000 };

    localparam [24:0] SP_UL   = { 5'b11111,
                                  5'b11111,
                                  5'b11110,
                                  5'b11110,
                                  5'b11100 };

    localparam [24:0] SP_UR   = { 5'b11111,
                                  5'b11111,
                                  5'b01111,
                                  5'b01111,
                                  5'b00111 };

    localparam [24:0] SP_DL   = { 5'b11100,
                                  5'b11110,
                                  5'b11110,
                                  5'b11111,
                                  5'b11111 };

    localparam [24:0] SP_DR   = { 5'b00111,
                                  5'b01111,
                                  5'b01111,
                                  5'b11111,
                                  5'b11111 };

    localparam [24:0] SP_DEAD = { 5'b10001,
                                  5'b01010,
                                  5'b00100,
                                  5'b01010,
                                  5'b10001 };

    reg [24:0] spr;
    always @* begin
        if (dead) spr = SP_DEAD;
        else begin
            case (face)                         // {up, down, left, right}
                4'b1000: spr = SP_UP;
                4'b0100: spr = SP_DOWN;
                4'b0010: spr = SP_LEFT;
                4'b0001: spr = SP_RIGHT;
                4'b1010: spr = SP_UL;
                4'b1001: spr = SP_UR;
                4'b0110: spr = SP_DL;
                4'b0101: spr = SP_DR;
                default: spr = SP_IDLE;         // nothing held (opposites cancel)
            endcase
        end
    end

    // Same wraparound trick as bullets.v: one add, one subtract, one compare.
    wire [11:0] pdx = {2'd0, hpos} + HALF - {2'd0, player_px};
    wire [11:0] pdy = {2'd0, vpos} + HALF - {2'd0, player_py};

    // 2 x 2 px cells: bits [3:1] of the offset are the cell column / row
    wire [2:0] cc = pdx[3:1];
    wire [2:0] cr = pdy[3:1];

    reg [4:0] cells;
    always @* begin
        case (cr)
            3'd0:    cells = spr[24:20];
            3'd1:    cells = spr[19:15];
            3'd2:    cells = spr[14:10];
            3'd3:    cells = spr[9:5];
            default: cells = spr[4:0];
        endcase
    end

    wire in_box = (pdx < 12'd10) && (pdy < 12'd10);
    wire body   = in_box && cells[3'd4 - cc];
    wire core   = !dead && (pdx >= 12'd3) && (pdx < 12'd7) &&
                          (pdy >= 12'd3) && (pdy < 12'd7);

    always @* begin
        if (!video_active)
            {R, G, B} = 6'b00_00_00;
        else if (hud_on)
            {R, G, B} = hud_rgb;
        else if (player_visible && core)
            {R, G, B} = C_CORE;
        else if (player_visible && body)
            {R, G, B} = dead ? C_DEAD : C_SHIP;
        else if (text_on)
            {R, G, B} = text_rgb;
        else if (bullet_on)
            {R, G, B} = C_BULLET;
        else
            {R, G, B} = dead ? C_BG_OVER : C_BG;
    end

endmodule
