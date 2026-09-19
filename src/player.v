/*
 * player.v -- player ship position
 *
 * Position is held in Q10.2 fixed point (2 fractional bits) so the ship can
 * move at a non-integer number of pixels per frame.  This is what decouples
 * the player's step granularity from the coarse grid the attack patterns are
 * laid out on: SPEED is in quarter-pixels, so 9 => 2.25 px/frame => 135 px/s.
 * Change SPEED alone to retune the feel; nothing else depends on it.
 *
 * Only the integer part (px/py) leaves the module.  The fraction never
 * reaches the renderer, so there is no cost on the pixel path.
 *
 * `face` reports which direction buttons are held, sampled once per frame
 * like everything else so the sprite can never change halfway down the
 * screen.  Opposing presses cancel, exactly as they do for movement, so
 * the sprite always matches what the ship is being told to do.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module player #(
    parameter [11:0] SPEED = 12'd9      // quarter-pixels per frame
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       frame_tick,
    input  wire       active,           // may the ship move this frame?
    input  wire       rst_pos,          // 1-frame pulse: recentre
    input  wire       up,
    input  wire       down,
    input  wire       left,
    input  wire       right,
    output wire [9:0] px,               // integer centre, pixels
    output wire [9:0] py,
    output reg  [3:0] face              // {up, down, left, right}, held this frame
);

    localparam [11:0] HALF    = 12'd5;                  // ship is 10 x 10 px

    // Bounds in Q10.2.
    localparam [11:0] X_MIN   = (12'd0   + HALF) << 2;  //   20
    localparam [11:0] X_MAX   = (12'd639 - HALF) << 2;  // 2536
    localparam [11:0] Y_MIN   = (12'd0   + HALF) << 2;  //   20
    localparam [11:0] Y_MAX   = (12'd479 - HALF) << 2;  // 1896

    localparam [11:0] START_X = 12'd320 << 2;
    localparam [11:0] START_Y = 12'd384 << 2;           // lower middle

    reg [11:0] xq, yq;

    always @(posedge clk) begin
        if (!rst_n) begin
            xq   <= START_X;
            yq   <= START_Y;
            face <= 4'b0000;
        end else if (frame_tick) begin
            face <= active ? {up & ~down, down & ~up, left & ~right, right & ~left}
                           : 4'b0000;

            if (rst_pos) begin
                xq <= START_X;
                yq <= START_Y;
            end else if (active) begin
                // horizontal -- opposing presses cancel
                if (left && !right)
                    xq <= (xq < (X_MIN + SPEED)) ? X_MIN : (xq - SPEED);
                else if (right && !left)
                    xq <= (xq > (X_MAX - SPEED)) ? X_MAX : (xq + SPEED);

                // vertical
                if (up && !down)
                    yq <= (yq < (Y_MIN + SPEED)) ? Y_MIN : (yq - SPEED);
                else if (down && !up)
                    yq <= (yq > (Y_MAX - SPEED)) ? Y_MAX : (yq + SPEED);
            end
        end
    end

    assign px = xq[11:2];
    assign py = yq[11:2];

endmodule
