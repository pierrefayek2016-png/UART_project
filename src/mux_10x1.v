module mux_10to1 (
    input  wire [9:0] frame,   // UART frame
    input  wire [3:0] bit_cnt, // which bit to send
    output reg        tx_bit
);

    always @(*) begin
        case (bit_cnt)
            4'd0: tx_bit = frame[0]; // start
            4'd1: tx_bit = frame[1]; // data[0] LSB
            4'd2: tx_bit = frame[2];
            4'd3: tx_bit = frame[3];
            4'd4: tx_bit = frame[4];
            4'd5: tx_bit = frame[5];
            4'd6: tx_bit = frame[6];
            4'd7: tx_bit = frame[7];
            4'd8: tx_bit = frame[8]; // data[7] MSB
            4'd9: tx_bit = frame[9]; // stop
            default: tx_bit = 1'b1;  // idle line
        endcase
    end
endmodule


