/*
 * attack_seq.v -- wave sequencer
 *
 *   REST (no bullets, timer counts down)
 *     -> ACTIVE (one pattern animates until it has left the screen)
 *       -> REST ...
 *
 * Because every pattern terminates on POSITION rather than on a fixed frame
 * count, bullet speed can scale with difficulty without ever leaving stale
 * bullets on screen when the wave ends.  `timer` is only a safety cap.
 *
 * All motion in the entire bullet system comes from one 12-bit accumulator,
 * `mov`.  Each pattern reinterprets it:
 *
 *   id 0  falling bars      mov = top edge of the bars,   -320 -> 480
 *   id 1  radiating diamond mov = radius,                    0 -> 640
 *   id 2  crunching diamond mov = radius,                  360 -> 0
 *   id 3  sweeping box      mov = left edge of the box,   -240 -> 640
 *   id 4  side walls        mov = wall inset from centre,  328 -> 40,
 *                           closing in from the sides, then vanishing
 *                           before the gap fully seals -- see P5_MIN below
 *
 * Negative positions are stored as 12-bit two's complement and every
 * "is this pixel inside" test in bullets.v is a single unsigned compare that
 * relies on the wraparound.  See bullets.v for why that works.
 *
 * Difficulty has two knobs, both driven by `diff`:
 *   - bullets get faster    (spd)
 *   - rest periods shrink   (rest_len)
 *
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module attack_seq (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_tick,
    input  wire        playing,
    input  wire        new_game,
    input  wire [1:0]  diff,
    input  wire [15:0] rnd,
    input  wire [2:0]  rnd_pattern,

    output reg  [2:0]  pattern_id,
    output reg  [11:0] mov,
    output reg  [9:0]  rnd_a,
    output reg  [7:0]  rnd_b,
    output reg         wave_active
);

    // ------------------------------------------------------------- geometry
    localparam [11:0] P1_H     = 12'd320;   // height of the falling bars
    localparam [11:0] P3_R0    = 12'd360;   // crunch starting radius
    localparam [11:0] P4_W     = 12'd240;   // sweeping box width
    localparam [11:0] P5_INS0  = 12'd328;   // walls' starting inset -- above
                                             // the max possible |dx| (320),
                                             // so they start fully offscreen
    localparam [11:0] P5_MIN   = 12'd40;    // inset where the walls vanish;
                                             // stopping short of 0 means the
                                             // gap never fully seals, so a
                                             // centred player is never
                                             // guaranteed an unavoidable hit

    // Safety caps only -- normal termination is positional.
    localparam [9:0]  P1_LEN   = 10'd400;
    localparam [9:0]  P2_LEN   = 10'd300;
    localparam [9:0]  P3_LEN   = 10'd200;
    localparam [9:0]  P4_LEN   = 10'd400;
    localparam [9:0]  P5_LEN   = 10'd150;

    localparam [9:0]  FIRST_REST = 10'd90;  // 1.5 s before the first wave
    localparam [9:0]  REST_BASE  = 10'd150; // 2.5 s, shrinks with difficulty

    localparam        REST = 1'b0,
                      ACTIVE = 1'b1;

    reg       seq_state;
    reg [9:0] timer;

    // ------------------------------- decode for the pattern about to START
    reg [11:0] start_mov;
    reg [9:0]  start_len;
    always @* begin
        case (rnd_pattern)
            3'd0:    begin start_mov = 12'd0 - P1_H;  start_len = P1_LEN; end
            3'd1:    begin start_mov = 12'd0;         start_len = P2_LEN; end
            3'd2:    begin start_mov = P3_R0;         start_len = P3_LEN; end
            3'd3:    begin start_mov = 12'd0 - P4_W;  start_len = P4_LEN; end
            3'd4:    begin start_mov = P5_INS0;       start_len = P5_LEN; end
            default: begin start_mov = P5_INS0;       start_len = P5_LEN; end
        endcase
    end

    // ----------------------------- decode for the pattern currently RUNNING
    reg        dir_dn;     // 1 = mov counts down
    reg        moving;
    reg [11:0] spd_base;
    always @* begin
        case (pattern_id)
            3'd0:    begin dir_dn = 1'b0; moving = 1'b1; spd_base = 12'd3; end
            3'd1:    begin dir_dn = 1'b0; moving = 1'b1; spd_base = 12'd3; end
            3'd2:    begin dir_dn = 1'b1; moving = 1'b1; spd_base = 12'd3; end
            3'd3:    begin dir_dn = 1'b0; moving = 1'b1; spd_base = 12'd3; end
            // Walls close in the same way the diamond crunches: mov counts
            // down, and bullets.v reads it straight as the current inset.
            3'd4:    begin dir_dn = 1'b1; moving = 1'b1; spd_base = 12'd3; end
            default: begin dir_dn = 1'b1; moving = 1'b1; spd_base = 12'd3; end
        endcase
    end

    wire [11:0] spd = moving ? (spd_base + {10'd0, diff}) : 12'd0;

    // --------------------------------------------- has this wave finished?
    reg wave_over;
    always @* begin
        case (pattern_id)
            // bit 11 set means mov is still negative (offscreen above/left)
            3'd0:    wave_over = (!mov[11]) && (mov >= 12'd480);
            3'd1:    wave_over = (mov >= 12'd640);
            3'd2:    wave_over = (mov == 12'd0);
            3'd3:    wave_over = (!mov[11]) && (mov >= 12'd640);
            3'd4:    wave_over = (mov <= P5_MIN);
            default: wave_over = (mov <= P5_MIN);
        endcase
    end

    // rest_len = REST_BASE - diff * 36  ->  150 / 114 / 78 / 42 frames
    wire [9:0] rest_len = REST_BASE - {3'd0, diff, 5'd0} - {6'd0, diff, 2'd0};

    // ------------------------------------------------------------ sequencer
    always @(posedge clk) begin
        if (!rst_n) begin
            seq_state   <= REST;
            timer       <= FIRST_REST;
            wave_active <= 1'b0;
            pattern_id  <= 3'd0;
            mov         <= 12'd0;
            rnd_a       <= 10'd0;
            rnd_b       <= 8'd0;
        end else if (frame_tick) begin
            if (new_game || !playing) begin
                seq_state   <= REST;
                timer       <= FIRST_REST;
                wave_active <= 1'b0;
            end else begin
                case (seq_state)
                    REST: begin
                        if (timer == 10'd0) begin
                            // commit to a wave: latch the pattern and its
                            // random placement for the whole wave
                            pattern_id  <= rnd_pattern;
                            rnd_a       <= rnd[9:0];
                            rnd_b       <= rnd[15:8];
                            mov         <= start_mov;
                            timer       <= start_len;
                            wave_active <= 1'b1;
                            seq_state   <= ACTIVE;
                        end else begin
                            timer       <= timer - 1'b1;
                            wave_active <= 1'b0;
                        end
                    end

                    ACTIVE: begin
                        if (wave_over || (timer == 10'd0)) begin
                            wave_active <= 1'b0;
                            seq_state   <= REST;
                            timer       <= rest_len;
                        end else begin
                            timer <= timer - 1'b1;
                            mov   <= dir_dn ? ((mov < spd) ? 12'd0 : mov - spd)
                                            : (mov + spd);
                        end
                    end
                endcase
            end
        end
    end

endmodule
