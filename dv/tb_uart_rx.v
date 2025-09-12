`timescale 1ns/1ps

module uart_rx_tb;

    reg clk;
    reg arst_n;
    reg rx_en;
    reg rx_in;
    wire rx_done;
    wire rx_err;
    wire rx_busy;
    wire [7:0] rx_data;

    uart_rx_top uut (
        .clk(clk),
        .arst_n(arst_n),
        .rx_en(rx_en),
        .rx_in(rx_in),
        .rx_done(rx_done),
        .rx_err(rx_err),
        .rx_data(rx_data),
        .rx_busy(rx_busy)
    );

    initial begin
      forever #5 clk = ~clk;
    end

    task sending_a_byte;
        input [7:0] d;
        integer i;
        begin
            rx_in = 0;
            #104160;
            for (i=0; i<8; i=i+1) begin
                rx_in = d[i];
                #104160;
            end

            rx_in = 1;
            #104160;
        end
    endtask

    initial begin
      clk = 0;
      rx_in = 1;   // idle
      arst_n = 0; // reset active low
      rx_en = 0;

      #100;
      arst_n = 1; // reset release
      rx_en = 1;


      $display("Sending 00001111...");
      sending_a_byte(8'b00001111);
      @(posedge rx_done);
      $display("Reception complete. Data = %b", rx_data);
      #1000;
      $stop;
    end

endmodule
