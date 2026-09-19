/*
 * bullets.v -- all five attack patterns, and collision
 *
 * There is no bullet array here.  Every pattern is a RULE about position, so
 * the only state in the whole bullet system lives in attack_seq.v (one motion
 * accumulator plus two latched random numbers).
 *
 * ----------------------------------------------------------------------
 * The shared datapath
 * ----------------------------------------------------------------------
 * Only one pattern is active at a time, so all five reuse one anchor and one
 * pair of subtractors:
 *
 *      dx = hpos - ax      dy = vpos - ay      (12-bit, unsigned, wrapping)
 *
 * Negative differences wrap to very large values, so "0 <= d < SIZE" reduces
 * to the single unsigned compare "d < SIZE".  That is why an object parked
 * offscreen (a negative anchor) needs no extra guard logic, and why nothing
 * in this file is declared signed.
 *
 * Bullets are large (32-48 px) and square, which is both what the design
 * calls for visually and the cheapest possible shape: pure range compares.
 * Their MOTION is smooth because the anchors advance a few pixels per frame;
 * the coarse grid only ever describes layout, never movement.
 *
 * ----------------------------------------------------------------------
 * Collision
 * ----------------------------------------------------------------------
 * Rather than evaluate the geometry a second time at the player's position,
 * we sample the renderer's own bullet signal as the beam sweeps across the
 * player hitbox and latch the result.  Cost: two compares and one flip-flop,
 * and render and collision can never disagree.
 *
 * Note that `bullet_on` is tapped BEFORE the priority mux in renderer.v --
 * after it, the player sprite would cover the bullet and no hit would ever
 * register.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module bullets (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_tick,
    input  wire        video_active,
    input  wire [9:0]  hpos,
    input  wire [9:0]  vpos,

    input  wire [2:0]  pattern_id,
    input  wire        wave_active,
    input  wire [11:0] mov,
    input  wire [9:0]  rnd_a,
    input  wire [7:0]  rnd_b,

    input  wire [9:0]  player_px,
    input  wire [9:0]  player_py,

    output wire        bullet_on,
    output reg         hit
);

    // ---------------------------------------------------------- dimensions
    localparam [11:0] P1_BARW  = 12'd48;    // bar width, pitch is fixed at 128
    localparam [11:0] P1_H     = 12'd320;   // bar height

    localparam [11:0] BR       = 12'd16;    // diamond bullet half-size (32x32)
    localparam [11:0] P3_MIN   = 12'd24;    // crunch: vanish below this radius

    localparam [11:0] P4_W     = 12'd240;   // box outer width
    localparam [11:0] P4_H     = 12'd168;   // box outer height
    localparam [11:0] P4_T     = 12'd44;    // box wall thickness

    localparam [11:0] HB       = 12'd3;     // player hitbox half-size (6x6)

    // ------------------------------------------------------ random placement
    // rnd_a and rnd_b come from disjoint LFSR slices so x and y are
    // independent.  Ranges are chosen to keep the shape mostly on screen.
    wire [11:0] cx   = 12'd64  + {3'd0, rnd_a[8:0]};   //  64 .. 575
    wire [11:0] cy   = 12'd112 + {4'd0, rnd_b[7:0]};   // 112 .. 367
    wire [11:0] boxy = 12'd40  + {4'd0, rnd_b[7:0]};   //  40 .. 295

    // --------------------------------------------------------- anchor mux
    reg [11:0] ax, ay;
    always @* begin
        case (pattern_id)
            3'd0:    begin ax = {5'd0, rnd_a[6:0]}; ay = mov;      end // lanes
            3'd1,
            3'd2:    begin ax = cx;                 ay = cy;       end // diamond
            3'd3:    begin ax = mov;                ay = boxy;     end // box
            3'd4:    begin ax = 12'd320;             ay = 12'd240;  end // walls
            default: begin ax = 12'd320;             ay = 12'd240;  end
        endcase
    end

    // --------------------------------------------------- shared arithmetic
    wire [11:0] sx = {2'd0, hpos};
    wire [11:0] sy = {2'd0, vpos};

    wire [11:0] dx = sx - ax;
    wire [11:0] dy = sy - ay;

    wire [11:0] adx = dx[11] ? (12'd0 - dx) : dx;      // |dx|
    wire [11:0] ady = dy[11] ? (12'd0 - dy) : dy;      // |dy|

    wire [11:0] erx = (adx >= mov) ? (adx - mov) : (mov - adx);   // ||dx| - r|
    wire [11:0] ery = (ady >= mov) ? (ady - mov) : (mov - ady);   // ||dy| - r|

    // ------------------------------------------------------- the predicates

    // 1: three... five vertical bars falling together.
    // The lane pattern repeats every 128 px, so taking the low 7 bits of dx
    // gives modulo-128 for free -- no divider, no per-bar comparator.
    // rnd_a[6:0] slides the whole comb sideways each wave so the safe lanes
    // are never in the same place twice.
    wire h1 = (dx[6:0] < P1_BARW[6:0]) && (dy < P1_H);

    // 2 and 3: four bullets at (cx, cy+-r) and (cx+-r, cy).
    // Identical geometry; only the direction of r differs, which is why these
    // two patterns cost barely more than one.
    wire h_diamond = ((adx < BR) && (ery < BR))     // the vertical pair
                  || ((ady < BR) && (erx < BR));    // the horizontal pair

    wire h2 = h_diamond;
    wire h3 = h_diamond && (mov >= P3_MIN);         // vanish at the centre

    // 4: hollow box sweeping left to right -- outer rectangle minus inner.
    wire h4 = (dx < P4_W) && (dy < P4_H)
              && !((dx >= P4_T) && (dx < (P4_W - P4_T)) &&
                   (dy >= P4_T) && (dy < (P4_H - P4_T)));

    // 5: two full-height walls closing in from the sides.  `mov` IS the
    // current inset -- attack_seq.v counts it down from off-screen (328)
    // toward P5_MIN, the same way it counts the crunch pattern's radius
    // down toward P3_MIN, so this is the same trick applied to a threshold
    // instead of a distance.
    wire h5 = (adx >= mov);

    reg raw;
    always @* begin
        case (pattern_id)
            3'd0:    raw = h1;
            3'd1:    raw = h2;
            3'd2:    raw = h3;
            3'd3:    raw = h4;
            3'd4:    raw = h5;
            default: raw = h5;
        endcase
    end

    assign bullet_on = wave_active && raw;

    // ---------------------------------------------------------- collision
    // Small centred hitbox, as bullet-hell convention expects.  It is also
    // the cheap option: a 6x6 window is two compares.
    wire [11:0] hbx = sx + HB - {2'd0, player_px};
    wire [11:0] hby = sy + HB - {2'd0, player_py};
    wire in_hitbox  = (hbx < (HB << 1)) && (hby < (HB << 1));

    always @(posedge clk) begin
        if (!rst_n)
            hit <= 1'b0;
        else if (frame_tick)
            hit <= 1'b0;                       // game_ctrl samples the old
                                               // value on this same edge
        else if (video_active && in_hitbox && bullet_on)
            hit <= 1'b1;
    end

endmodule
