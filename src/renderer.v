/*
 * renderer.v -- priority mux down to 2-bit R / G / B
 *
 * Priority, highest first:
 *      HUD  >  player core  >  player body  >  bullets  >  background
 *
 * The player is drawn ON TOP of bullets so you can always see yourself in a
 * dense wave.  That is exactly why bullets.v taps its own `bullet_on` signal
 * for collision instead of reading the final pixel colour.
 *
 * The ship is 10 x 10 px with a 4 x 4 white core marking the hitbox -- small
 * against the 32-48 px bullets, and the core makes near-misses legible.
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
    input  wire       bullet_on,
    input  wire       hud_on,
    input  wire [5:0] hud_rgb,
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

    localparam [11:0] HALF = 12'd5;

    // Same wraparound trick as bullets.v: one add, one subtract, one compare.
    wire [11:0] pdx = {2'd0, hpos} + HALF - {2'd0, player_px};
    wire [11:0] pdy = {2'd0, vpos} + HALF - {2'd0, player_py};

    wire body = (pdx < 12'd10) && (pdy < 12'd10);
    wire core = (pdx >= 12'd3) && (pdx < 12'd7) &&
                (pdy >= 12'd3) && (pdy < 12'd7);

    always @* begin
        if (!video_active)
            {R, G, B} = 6'b00_00_00;
        else if (hud_on)
            {R, G, B} = hud_rgb;
        else if (player_visible && core)
            {R, G, B} = C_CORE;
        else if (player_visible && body)
            {R, G, B} = C_SHIP;
        else if (bullet_on)
            {R, G, B} = C_BULLET;
        else
            {R, G, B} = (state == ST_OVER) ? C_BG_OVER : C_BG;
    end

endmodule
