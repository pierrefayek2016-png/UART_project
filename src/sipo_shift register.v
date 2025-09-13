module sipo_shift_register(
    input  wire        clk,
    input  wire        arst_n,
    input  wire        shift_en,
    input  wire        rx_in,
    output reg  [7:0]  data
);

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            data <= 8'b0;
        end
        else if (shift_en) begin
            data <= {data[6:0], rx_in};
        end
    end
endmodule
