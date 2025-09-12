module frame_register(
    input  wire       clk,
    input  wire       arst_n,
    input  wire       load,      // pulse to load a new frame
    input  wire [7:0] data,      // parallel data to transmit
    output reg  [9:0] frame      // UART frame (start + data + stop)
);

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            frame <= 10'b1111111111;   // idle = high
        end 
        else if (load) begin
            frame[0] <= 1'b0;     // start bit
            frame[1] <= data[0];  // bit0 (LSB)
            frame[2] <= data[1];
            frame[3] <= data[2];
            frame[4] <= data[3];
            frame[5] <= data[4];
            frame[6] <= data[5];
            frame[7] <= data[6];
            frame[8] <= data[7];  // bit7 (MSB)
            frame[9] <= 1'b1;     // stop bit
        end
    end
endmodule

