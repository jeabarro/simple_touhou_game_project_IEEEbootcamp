/*
 * project.v -- Endless bullet-hell game for Tiny Tapeout / VGA Playground
 *
 * Top-level wrapper.  Everything here is plumbing: pin mapping, the pixel
 * clock domain, and the single `frame_tick` pulse that the whole game runs on.
 *
 * External files you also need (unmodified, from the VGA Playground):
 *   hvsync_generator.v   -- from any VGA Playground preset
 *   gamepad_pmod.v       -- from the "gamepad" preset (gamepad_pmod_single)
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_bullet_hell (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs (Tiny VGA Pmod)
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path
    input  wire       ena,      // always 1 when powered
    input  wire       clk,      // 25.175 MHz pixel clock
    input  wire       rst_n     // active-low reset
);

    // ---------------------------------------------------------------- video
    wire        hsync, vsync, video_active;
    wire [9:0]  hpos, vpos;
    wire [1:0]  R, G, B;

    // Tiny VGA Pmod bit order
    assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    hvsync_generator hvsync_gen (
        .clk        (clk),
        .reset      (~rst_n),
        .hsync      (hsync),
        .vsync      (vsync),
        .display_on (video_active),
        .hpos       (hpos),
        .vpos       (vpos)
    );

    // One pulse per frame, at the first pixel of vertical blanking.
    // Every register in the game updates here and nowhere else, so nothing
    // can change while the beam is drawing -> no tearing.
    wire frame_tick = (vpos == 10'd480) && (hpos == 10'd0);

    // ---------------------------------------------------------------- input
    wire up, down, left, right;

    input_ctrl u_input (
        .clk   (clk),
        .rst_n (rst_n),
        .ui_in (ui_in),
        .up    (up),
        .down  (down),
        .left  (left),
        .right (right)
    );

    // ------------------------------------------------------------- rng core
    wire [15:0] rnd;
    wire [2:0]  rnd_pattern;

    rng u_rng (
        .clk         (clk),
        .rst_n       (rst_n),
        .rnd         (rnd),
        .pattern_id  (rnd_pattern)
    );

    // ------------------------------------------------------- game / control
    wire [1:0] state;
    wire [1:0] lives;
    wire [1:0] diff;
    wire [3:0] t_d3, t_d2, t_d1, t_d0;
    wire       player_visible, new_game, hit;

    wire playing       = (state == 2'd1);
    wire player_active = (state != 2'd2);   // move in ATTRACT and PLAYING

    game_ctrl u_game (
        .clk            (clk),
        .rst_n          (rst_n),
        .frame_tick     (frame_tick),
        .down           (down),
        .hit            (hit),
        .state          (state),
        .lives          (lives),
        .diff           (diff),
        .d3             (t_d3),
        .d2             (t_d2),
        .d1             (t_d1),
        .d0             (t_d0),
        .player_visible (player_visible),
        .new_game       (new_game)
    );

    // ---------------------------------------------------------- player ship
    wire [9:0] player_px, player_py;

    player u_player (
        .clk        (clk),
        .rst_n      (rst_n),
        .frame_tick (frame_tick),
        .active     (player_active),
        .rst_pos    (new_game),
        .up         (up),
        .down       (down),
        .left       (left),
        .right      (right),
        .px         (player_px),
        .py         (player_py)
    );

    // ------------------------------------------------------ wave sequencer
    wire [2:0]  pattern_id;
    wire [11:0] mov;
    wire [9:0]  rnd_a;
    wire [7:0]  rnd_b;
    wire        wave_active;

    attack_seq u_seq (
        .clk         (clk),
        .rst_n       (rst_n),
        .frame_tick  (frame_tick),
        .playing     (playing),
        .new_game    (new_game),
        .diff        (diff),
        .rnd         (rnd),
        .rnd_pattern (rnd_pattern),
        .pattern_id  (pattern_id),
        .mov         (mov),
        .rnd_a       (rnd_a),
        .rnd_b       (rnd_b),
        .wave_active (wave_active)
    );

    // ------------------------------------------------------ bullet geometry
    wire bullet_on;

    bullets u_bullets (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_tick   (frame_tick),
        .video_active (video_active),
        .hpos         (hpos),
        .vpos         (vpos),
        .pattern_id   (pattern_id),
        .wave_active  (wave_active),
        .mov          (mov),
        .rnd_a        (rnd_a),
        .rnd_b        (rnd_b),
        .player_px    (player_px),
        .player_py    (player_py),
        .bullet_on    (bullet_on),
        .hit          (hit)
    );

    // ------------------------------------------------------------------ HUD
    wire       hud_on;
    wire [5:0] hud_rgb;

    hud u_hud (
        .hpos    (hpos),
        .vpos    (vpos),
        .d3      (t_d3),
        .d2      (t_d2),
        .d1      (t_d1),
        .d0      (t_d0),
        .lives   (lives),
        .hud_on  (hud_on),
        .hud_rgb (hud_rgb)
    );

    // ------------------------------------------------------------- renderer
    renderer u_render (
        .hpos           (hpos),
        .vpos           (vpos),
        .video_active   (video_active),
        .state          (state),
        .player_px      (player_px),
        .player_py      (player_py),
        .player_visible (player_visible),
        .bullet_on      (bullet_on),
        .hud_on         (hud_on),
        .hud_rgb        (hud_rgb),
        .R              (R),
        .G              (G),
        .B              (B)
    );

    // unused
    wire _unused = &{ena, uio_in, ui_in[7], 1'b0};

endmodule
