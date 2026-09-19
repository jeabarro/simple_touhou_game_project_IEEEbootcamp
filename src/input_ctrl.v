/*
 * input_ctrl.v -- button source abstraction
 *
 * Auto-detects the Gamepad Pmod on ui_in[6:4].  If it is not present, falls
 * back to raw pushbuttons on ui_in[3:0].  The rest of the design never knows
 * or cares which one is in use.
 *
 *   ui_in[4] LATCH   ui_in[5] CLOCK   ui_in[6] DATA      (Gamepad Pmod)
 *   ui_in[0] UP      ui_in[1] DOWN    ui_in[2] LEFT  ui_in[3] RIGHT  (manual)
 *
 * Only levels are exported.  Edge detection happens at frame rate inside
 * game_ctrl -- a 25 MHz-wide pulse would be missed by 60 Hz logic.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module input_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] ui_in,
    output wire       up,
    output wire       down,
    output wire       left,
    output wire       right
);

    wire gp_present;
    wire gp_up, gp_down, gp_left, gp_right;
    wire gp_a, gp_b, gp_x, gp_y, gp_l, gp_r, gp_start, gp_select;

    gamepad_pmod_single gamepad (
        // inputs
        .rst_n      (rst_n),
        .clk        (clk),
        .pmod_data  (ui_in[6]),
        .pmod_clk   (ui_in[5]),
        .pmod_latch (ui_in[4]),
        // outputs
        .is_present (gp_present),
        .b          (gp_b),
        .y          (gp_y),
        .select     (gp_select),
        .start      (gp_start),
        .up         (gp_up),
        .down       (gp_down),
        .left       (gp_left),
        .right      (gp_right),
        .a          (gp_a),
        .x          (gp_x),
        .l          (gp_l),
        .r          (gp_r)
    );

    // Two-stage synchronizer for the raw pushbuttons.
    reg [3:0] sync0, sync1;
    always @(posedge clk) begin
        if (!rst_n) begin
            sync0 <= 4'h0;
            sync1 <= 4'h0;
        end else begin
            sync0 <= ui_in[3:0];
            sync1 <= sync0;
        end
    end

    assign up    = gp_present ? gp_up    : sync1[0];
    assign down  = gp_present ? gp_down  : sync1[1];
    assign left  = gp_present ? gp_left  : sync1[2];
    assign right = gp_present ? gp_right : sync1[3];

    wire _unused = &{gp_a, gp_b, gp_x, gp_y, gp_l, gp_r, gp_start, gp_select,
                     ui_in[7], 1'b0};

endmodule
