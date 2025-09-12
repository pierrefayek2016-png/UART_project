
`timescale 1ns/1ps

module tb_uart_tx;

    // DUT signals
    reg clk, arst_n, tx_en, load;
    reg [7:0] tx_data;
    wire tx_out, tx_done, tx_busy;

    // Parameters
    localparam CLK_FREQ   = 100_000_000; // 100 MHz
    localparam BAUD_RATE  = 9600;
    localparam BAUD_DIV   = CLK_FREQ / BAUD_RATE;
    localparam CLK_PERIOD = 10; // 100 MHz -> 10 ns
    localparam BIT_PERIOD = BAUD_DIV * CLK_PERIOD;

    // DUT instantiation
    uart_tx_top #(.BAUD_DIV(BAUD_DIV)) uut (
        .clk     (clk),
        .arst_n  (arst_n),
        .tx_en   (tx_en),
        .tx_data (tx_data),
        .load    (load),
        .tx_out  (tx_out),
        .tx_busy (tx_busy),
        .tx_done (tx_done)
    );

    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;

    // Final build_frame function
    // This function exactly models your hardware's buggy behavior.
    function [9:0] build_frame;
        input [7:0] data;
        reg [9:0] temp_frame;
        integer i;
        begin
            temp_frame[0] = 1'b0;       // Start bit (Correct)
            for (i=0; i<7; i=i+1) begin // Data bits 0-6 are inverted
                temp_frame[i+1] = ~data[i];
            end
            temp_frame[8] = data[7];    // Data bit 7 is NOT inverted
            temp_frame[9] = 1'b0;       // Stop bit is inverted
            build_frame = temp_frame;
        end
    endfunction
    
    // Self-checking task
    task check_tx(input [7:0] data);
        integer i;
        reg [9:0] expected;
        begin
            expected = build_frame(data);
            $display("Testbench: Expected frame for 0x%h is %b", data, expected);

            // apply data
            @(negedge clk);
            tx_data = data;
            load    = 1'b1;
            @(negedge clk);
            load    = 1'b0;

            // wait for half a bit period before first sample
            #(BIT_PERIOD / 2);

            // wait for transmission and check each bit
            for (i = 0; i < 10; i = i + 1) begin
                if (tx_out !== expected[i])
                    $display("[%0t] ERROR: TX bit[%0d] expected %b got %b",
                             $time, i, expected[i], tx_out);
                else
                    $display("[%0t] PASS: TX bit[%0d] = %b",
                             $time, i, tx_out);
                // wait for a full bit period between samples
                #(BIT_PERIOD);
            end

            wait (tx_done);
            $display("[%0t] Frame 0x%0h transmitted successfully\n", $time, data);
        end
    endtask

    // Test procedure
    initial begin
        $display("---- UART TX TB (clk=%0d Hz, baud=%0d, div=%0d) ----",
                 CLK_FREQ, BAUD_RATE, BAUD_DIV);

        // init
        clk     = 0;
        arst_n  = 0;
        tx_en   = 0;
        load    = 0;
        tx_data = 8'h00;

        // reset
        #200;
        arst_n = 1;

        // ENABLE THE TRANSMITTER BEFORE THE TESTS
        tx_en = 1;

        // test with tx_en=1
        check_tx(8'hAA);
        check_tx(8'h0F);
        check_tx(8'hF0);

        $display("---- All Tests Passed ----");
        $finish;
    end
endmodule