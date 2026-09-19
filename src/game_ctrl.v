/*
 * game_ctrl.v -- top-level game state machine
 *
 * States:  ATTRACT -> PLAYING -> GAME OVER -> PLAYING
 * Start / restart is the DOWN button, edge-detected at frame rate.
 *
 * Holds:
 *   - lives (3, so the player survives two hits and dies on the third)
 *   - invincibility frames after a hit, with a blink signal for the renderer
 *   - the survival timer, kept in BCD so hud.v can index the font directly.
 *     Binary-to-decimal conversion is expensive; a decade cascade is not.
 *   - the difficulty level derived from elapsed time
 *
 * 60 fps assumed: 6 frames = 0.1 s exactly.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module game_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       frame_tick,
    input  wire       down,            // start / restart button (level)
    input  wire       hit,             // from bullets.v, valid at frame_tick

    output reg  [1:0] state,           // 0 ATTRACT, 1 PLAYING, 2 GAME OVER
    output reg  [1:0] lives,
    output reg  [1:0] diff,            // 0..3, drives wave pacing
    output reg  [3:0] d3,              // hundreds of seconds
    output reg  [3:0] d2,              // tens of seconds
    output reg  [3:0] d1,              // seconds
    output reg  [3:0] d0,              // tenths
    output wire       player_visible,  // low while blinking during i-frames
    output reg        new_game         // 1-frame pulse
);

    localparam [1:0] ST_ATTRACT = 2'd0,
                     ST_PLAYING = 2'd1,
                     ST_OVER    = 2'd2;

    localparam [7:0] INVUL_START = 8'd60;    // 1.0 s grace at wave zero
    localparam [7:0] INVUL_HIT   = 8'd120;   // 2.0 s after taking a hit
    localparam [7:0] OVER_HOLD   = 8'd60;    // lockout so a held button
                                             // cannot instantly restart

    reg       down_q;
    reg [7:0] invul;
    reg [2:0] tenth;       // 0..5 frame prescaler
    reg [7:0] hold;
    reg [5:0] fcnt;        // free-running frame counter, drives the blink

    wire start_edge = down & ~down_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            state  <= ST_ATTRACT;
            lives  <= 2'd3;
            d3 <= 4'd0; d2 <= 4'd0; d1 <= 4'd0; d0 <= 4'd0;
            invul  <= 8'd0;
            tenth  <= 3'd0;
            hold   <= 8'd0;
            fcnt   <= 6'd0;
            down_q <= 1'b0;
            new_game <= 1'b0;
        end else if (frame_tick) begin
            down_q   <= down;
            fcnt     <= fcnt + 1'b1;
            new_game <= 1'b0;
            if (invul != 8'd0) invul <= invul - 1'b1;

            case (state)
                // ------------------------------------------------ ATTRACT
                ST_ATTRACT: begin
                    if (start_edge) begin
                        state <= ST_PLAYING;
                        lives <= 2'd3;
                        d3 <= 4'd0; d2 <= 4'd0; d1 <= 4'd0; d0 <= 4'd0;
                        tenth    <= 3'd0;
                        invul    <= INVUL_START;
                        new_game <= 1'b1;
                    end
                end

                // ------------------------------------------------ PLAYING
                ST_PLAYING: begin
                    // survival timer: 6 frames per tenth of a second
                    if (tenth == 3'd5) begin
                        tenth <= 3'd0;
                        if (d0 == 4'd9) begin
                            d0 <= 4'd0;
                            if (d1 == 4'd9) begin
                                d1 <= 4'd0;
                                if (d2 == 4'd9) begin
                                    d2 <= 4'd0;
                                    if (d3 != 4'd9) d3 <= d3 + 1'b1;
                                end else d2 <= d2 + 1'b1;
                            end else d1 <= d1 + 1'b1;
                        end else d0 <= d0 + 1'b1;
                    end else begin
                        tenth <= tenth + 1'b1;
                    end

                    // damage -- these assignments come after the decrement
                    // above, so they win when both fire on the same frame
                    if (hit && (invul == 8'd0)) begin
                        if (lives > 2'd1) begin
                            lives <= lives - 1'b1;
                            invul <= INVUL_HIT;
                        end else begin
                            lives <= 2'd0;
                            state <= ST_OVER;
                            hold  <= OVER_HOLD;
                        end
                    end
                end

                // ---------------------------------------------- GAME OVER
                ST_OVER: begin
                    if (hold != 8'd0) begin
                        hold <= hold - 1'b1;
                    end else if (start_edge) begin
                        state <= ST_PLAYING;
                        lives <= 2'd3;
                        d3 <= 4'd0; d2 <= 4'd0; d1 <= 4'd0; d0 <= 4'd0;
                        tenth    <= 3'd0;
                        invul    <= INVUL_START;
                        new_game <= 1'b1;
                    end
                end

                default: state <= ST_ATTRACT;
            endcase
        end
    end

    // Blink at ~7.5 Hz while invulnerable so the player can see the i-frames.
    assign player_visible = (invul == 8'd0) || fcnt[2];

    // Difficulty from elapsed seconds.  d2 is tens-of-seconds.
    always @* begin
        if      (d3 != 4'd0)  diff = 2'd3;   // past 100 s
        else if (d2 >= 4'd6)  diff = 2'd3;   // past 60 s
        else if (d2 >= 4'd3)  diff = 2'd2;   // past 30 s
        else if (d2 >= 4'd1)  diff = 2'd1;   // past 10 s
        else                  diff = 2'd0;
    end

endmodule
