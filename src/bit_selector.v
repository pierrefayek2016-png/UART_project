module bit_selector(
    input  wire       clk,
    input  wire       arst_n,
    input  wire       baud_tick,   // 1-cycle pulse per baud interval
    input  wire       start_tx,    // pulse to begin transmission
    output reg  [3:0] bit_cnt,     // current bit index (0..9)
    output reg        busy,        // high while transmitting
    output reg        done         // pulse when frame finished
);

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            bit_cnt <= 0;
            busy    <= 0;
            done    <= 0;
        end 
        else if (start_tx && !busy) begin
            // Only accept new start when not already busy
            busy    <= 1;
            done    <= 0;
            bit_cnt <= 0;
        end 
        else if (baud_tick && busy) begin
            if (bit_cnt == 9) begin   // last bit (stop)
                busy    <= 0;
                done    <= 1;   // pulse done after stop bit is sent
                bit_cnt <= 0;
            end else begin
                bit_cnt <= bit_cnt + 1;
                busy    <= 1;
                done    <= 0;
            end
        end 
        else begin
            done <= 0; // keep done low 
        end
    end

endmodule


