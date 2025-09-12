module baud_counter#(
    parameter BAUD_DIV=10416,
    parameter MID_POINT=10416/2
)(
    input wire clk,
    input wire arst_n,
    input wire en,
    input wire restart,
    output reg tick
);
    reg [15:0] counter;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            counter <= BAUD_DIV - 1;
        end else if (restart) begin
            counter <= BAUD_DIV - 1;
        end else if (en) begin
            counter <= (counter == 16'd0) ? BAUD_DIV - 1 : counter - 1;
        end
    end

    always @(*) begin
        tick = (counter == MID_POINT);
    end

endmodule
