module edge_detector (
    input  wire clk,
    input  wire arst_n,
    input  wire rx_in,
    output reg  start    // pulse when falling edge detected
);

    // State encoding
    localparam HIGH = 1'b0;
    localparam LOW  = 1'b1;

    reg state, next_state;

    // Sequential state update
    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            state <= HIGH;      // idle high initially
        else
            state <= next_state;
    end

    // Mealy logic
    always @(*) begin
        next_state = state;
        start      = 1'b0;  // default

        case (state)
            HIGH: begin
                if (rx_in == 1'b0) begin
                    // Falling edge detected
                    start      = 1'b1;   
                    next_state = LOW;
                end
            end
            LOW: begin
                if (rx_in == 1'b1)
                    next_state = HIGH;
            end
        endcase
    end

endmodule
