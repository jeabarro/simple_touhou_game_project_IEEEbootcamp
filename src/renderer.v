/*
 * renderer.v -- priority mux down to 2-bit R / G / B
 *
 * Priority, highest first:
 *   HUD  >  overlay text  >  player  >  bullets  >  background
 *
 * The player is drawn ON TOP of bullets so you can always see yourself in a
 * dense wave.  That is exactly why bullets.v taps its own `bullet_on` signal
 * for collision instead of reading the final pixel colour.  Overlay text
 * sits above the player too, so moving the ship during the title screen can
 * never obscure "press down to start".
 *
 * The ship has three skins, chosen by state, cheapest first:
 *   idle    a 10 x 10 square, cyan, with a 4 x 4 white core marking the
 *           hitbox -- small against the 32-48 px bullets, and the core
 *           makes near-misses legible
 *   moving  the same box reshaped into a diamond (Manhattan-distance test,
 *           the same idiom bullets.v uses for its own diamond patterns) and
 *           recoloured to warm yellow, so holding a direction key is
 *           visibly different from drifting
 *   dead    (state == GAME OVER) an X drawn across the same box in a dim
 *           red, frozen wherever the ship was when it took the last hit --
 *           player.v already stops updating px/py the instant `active`
 *           drops, so no extra latching is needed here
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
    input  wire       moving,
    input  wire       bullet_on,
    input  wire       hud_on,
    input  wire [5:0] hud_rgb,
    input  wire       overlay_on,
    input  wire [5:0] overlay_rgb,
    output reg  [1:0] R,
    output reg  [1:0] G,
    output reg  [1:0] B
);

    localparam [1:0] ST_OVER = 2'd2;

    localparam [5:0] C_BG        = 6'b00_00_01;   // deep blue
    localparam [5:0] C_BG_OVER   = 6'b01_00_00;   // dull red on game over
    localparam [5:0] C_BULLET    = 6'b11_01_00;   // hot orange
    localparam [5:0] C_SHIP      = 6'b00_11_11;   // cyan   -- idle
    localparam [5:0] C_SHIP_MOVE = 6'b11_11_00;   // yellow -- thrust
    localparam [5:0] C_CORE      = 6'b11_11_11;   // white hitbox marker
    localparam [5:0] C_WRECK     = 6'b10_00_00;   // dim red -- destroyed

    localparam [11:0] HALF = 12'd5;

    wire dead = (state == ST_OVER);

    // Same wraparound trick as bullets.v: one add, one subtract, one compare.
    wire [11:0] pdx = {2'd0, hpos} + HALF - {2'd0, player_px};
    wire [11:0] pdy = {2'd0, vpos} + HALF - {2'd0, player_py};

    wire body = (pdx < 12'd10) && (pdy < 12'd10);
    wire core = (pdx >= 12'd3) && (pdx < 12'd7) &&
                (pdy >= 12'd3) && (pdy < 12'd7);

    // Coordinates within the box, valid only where `body` is true.
    wire [3:0] cx = pdx[3:0];
    wire [3:0] cy = pdy[3:0];

    // -- moving skin: diamond inscribed in the box, touching edge midpoints
    wire [4:0] mx  = {cx, 1'b0};                          // 2*cx
    wire [4:0] my  = {cy, 1'b0};                          // 2*cy
    wire [4:0] amx = (mx >= 5'd9) ? (mx - 5'd9) : (5'd9 - mx);
    wire [4:0] amy = (my >= 5'd9) ? (my - 5'd9) : (5'd9 - my);
    wire diamond   = body && ((amx + amy) <= 5'd9);

    wire shape = moving ? diamond : body;

    // -- dead skin: a thick X across the box
    wire [3:0] adiff = (cx >= cy) ? (cx - cy) : (cy - cx);
    wire [4:0] csum  = cx + cy;
    wire wreck = body && ((adiff <= 4'd1) ||
                          ((csum >= 5'd8) && (csum <= 5'd10)));

    always @* begin
        if (!video_active)
            {R, G, B} = 6'b00_00_00;
        else if (hud_on)
            {R, G, B} = hud_rgb;
        else if (overlay_on)
            {R, G, B} = overlay_rgb;
        else if (player_visible && dead && wreck)
            {R, G, B} = C_WRECK;
        else if (player_visible && !dead && core)
            {R, G, B} = C_CORE;
        else if (player_visible && !dead && shape)
            {R, G, B} = moving ? C_SHIP_MOVE : C_SHIP;
        else if (bullet_on)
            {R, G, B} = C_BULLET;
        else
            {R, G, B} = dead ? C_BG_OVER : C_BG;
    end

endmodule
