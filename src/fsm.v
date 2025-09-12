
module fsm(
    input  wire       clk,
    input  wire       arst_n,
    input  wire       rx_en,     // enable receiver
    input  wire       start,     // 1-cycle pulse from edge detector
    input  wire       tick,      // mid-bit pulse from baud counter
    input  wire       rx_in,     // serial data input

    output reg        busy,      // high while receiving a frame
    output reg        done,      // pulse when a frame is received
    output reg        err,       // pulse if framing error or false start
    output reg        shift_en,  // pulse to shift a bit into SIPO
    output reg [3:0]  bit_cnt,   // current data bit index (0..7)
    output reg        restart_counter
);

    // State encoding
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    reg [1:0] state, next_state;

    // Sequential logic
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            state   <= IDLE;
            bit_cnt <= 4'd0;
        end else begin
            state <= next_state;

            // update bit counter
            if (state == DATA && tick)
                bit_cnt <= bit_cnt + 1;
        end
    end

    // Combinational logic
    always @(*) begin
        next_state      = state;
        busy            = 1'b0;
        done            = 1'b0;
        err             = 1'b0;
        shift_en        = 1'b0;
        restart_counter = 1'b0;

        case (state)

            IDLE: begin
                if (rx_en && start) begin
                    next_state = START;
                    restart_counter = 1'b1;
                end
            end

            START: begin
                busy = 1'b1;
                if (tick) begin
                    if (rx_in == 1'b0) begin
                        next_state = DATA;   // valid start bit
                    end else begin
                        err        = 1'b1;   // false start (line went high again)
                        next_state = IDLE;
                    end
                end
            end

            DATA: begin
                busy = 1'b1;
                if (tick) begin
                    shift_en = 1'b1;         // capture current bit
                    if (bit_cnt == 4'd7)     // last data bit
                        next_state = STOP;
                end
            end

            STOP: begin
                busy = 1'b1;
                if (tick) begin
                    if (rx_in == 1'b1)
                        done = 1'b1;         // valid stop bit -> frame complete
                    else
                        err  = 1'b1;         // framing error
                    next_state = IDLE;
                end
            end
        endcase
    end
endmodule
