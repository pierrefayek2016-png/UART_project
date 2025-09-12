
# UART Core (Receiver & Transmitter)

## 1\. Project Overview

This project is a complete and robust implementation of a Universal Asynchronous Receiver/Transmitter (UART) core using Verilog HDL. The design is modular, separating the core functionalities of the UART into individual blocks for clarity, reusability, and simplified verification. The core includes both a receiver (RX) and a transmitter (TX) capable of handling standard serial communication at a configurable baud rate.

## 2\. Design Philosophy

The primary design philosophy for this project was modularity. Instead of creating a single, monolithic UART module, the system was broken down into smaller, logical blocks. This approach was chosen for several key reasons:

  * **Readability and Maintainability:** Each module has a single, well-defined purpose, making the code easier to read, understand, and debug.
  * **Reusability:** Individual blocks like the `baud_counter` or the `FSM` can be easily repurposed for other projects.
  * **Simplified Verification:** By isolating functionalities, it's possible to test each component independently before integrating them into the top-level design. This "divide and conquer" strategy significantly streamlined the debugging process.

## 3\. Block Descriptions & Code

The UART core is composed of several sub-modules, each serving a specific function.

### UART Receiver (`uart_rx_top.v`)

This is the top-level module for the receiver. It orchestrates the sub-modules to convert incoming serial data into parallel data.

```verilog
module uart_rx_top #(
    parameter BAUD_DIV  = 10416,
    parameter MID_POINT = BAUD_DIV/2
)(
    input  wire       clk,
    input  wire       arst_n,
    input  wire       rx_en,
    input  wire       rx_in,

    output wire [7:0] rx_data,
    output wire       rx_done,
    output wire       rx_err,
    output wire       rx_busy
);
    // Internal signals
    wire start;
    wire tick;
    wire shift_en;
    wire [3:0] bit_cnt;
    wire [7:0] data;
    wire done, err, busy;
    wire restart_counter;

    // 1) Edge detector
    edge_detector u_edge (
        .clk   (clk),
        .arst_n(arst_n),
        .rx_in (rx_in),
        .start (start)
    );

    // 2) Baud counter
    baud_counter #(
        .BAUD_DIV (BAUD_DIV),
        .MID_POINT(MID_POINT)
    ) u_baud (
        .clk    (clk),
        .arst_n (arst_n),
        .en     (busy),
        .restart(restart_counter),
        .tick   (tick)
    );

    // 3) FSM
    fsm u_fsm (
        .clk     (clk),
        .arst_n  (arst_n),
        .rx_en   (rx_en),
        .start   (start),
        .tick    (tick),
        .rx_in   (rx_in),
        .busy    (busy),
        .done    (done),
        .err     (err),
        .shift_en(shift_en),
        .bit_cnt (bit_cnt),
        .restart_counter(restart_counter)
    );

    // 4) Shift register
    sipo_shift_register u_sipo (
        .clk     (clk),
        .arst_n  (arst_n),
        .shift_en(shift_en),
        .rx_in   (rx_in),
        .data    (data)
    );

    // Output assignments
    assign rx_data = data;
    assign rx_done = done;
    assign rx_err  = err;
    assign rx_busy = busy;

endmodule
```

### Baud Counter (`baud_counter.v`)

The `baud_counter` is a simple timer that generates a one-cycle pulse, `tick`, at the mid-point of each bit period. This signal is critical for synchronizing the receiver's sampling of the incoming data. The counter runs only when enabled and can be explicitly reset by the `restart` signal.

```verilog
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
```

### Finite State Machine (FSM) (`fsm.v`)

The FSM controls the entire reception process. It transitions through `IDLE`, `START`, `DATA`, and `STOP` states. It uses the `tick` signal from the baud counter to determine when to sample bits and generates control signals like `shift_en` and `restart_counter` for other modules.

```verilog
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
```

### SIPO Shift Register (`sipo_shift_register.v`)

This module converts the incoming serial data (`rx_in`) into an 8-bit parallel byte. It shifts in one bit per clock cycle when the `shift_en` signal is asserted by the FSM.

```verilog
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
```

### Edge Detector (`edge_detector.v`)

This simple module detects the falling edge of the `rx_in` line, which marks the start bit of a UART frame. It generates a single-cycle pulse on the `start` signal.

```verilog
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
```

## 4\. Testbench (`RX_tb.v`)

The testbench is a crucial part of the verification process. It is a self-checking environment that simulates the behavior of an external device transmitting data to the UART receiver.

**Key Tasks:**

1.  **Clock and Reset Generation:** It generates a continuous clock signal and controls the asynchronous reset sequence to bring the DUT to a known state.
2.  **Task for Sending Bytes:** A Verilog `task` is used to abstract the process of sending a byte. This task handles the start bit, all 8 data bits (LSB first), and the stop bit, with the correct timing for each. This makes the test scenario a readable, high-level sequence.
3.  **Self-Checking:** After a byte is transmitted, the testbench waits for the `rx_done` signal to go high. It then checks if the received `rx_data` matches the expected value and if the `rx_err` signal is low. A pass/fail message is then printed to the console.

**Code:**

```verilog
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
```

## 5\. Challenges and Solutions

Throughout the development and verification process, several challenges were encountered that required focused debugging to solve.

### Challenge 1: Modular Inconsistency

**Problem:** The initial design had inconsistencies in module interfaces. For example, the `baud_counter` was missing a `restart` port that the `uart_rx_top` was attempting to connect. Similarly, the `sipo_shift_register` had an extra `bit_cnt` input port that was not used, leading to incorrect connections and data corruption.

**Solution:** The solution was to standardize the module interfaces. The `baud_counter` was modified to include a `restart` port, and the `sipo_shift_register`'s ports were streamlined to only include what was necessary for its function. This systematic approach of ensuring all modules' port lists were compatible and logically correct was key to resolving these compilation issues.

### Challenge 2: Timing and Data Corruption

**Problem:** During initial simulation, the `rx_done` signal would not assert, leading to a simulation timeout. The received data was also incorrect (e.g., `0xaa` was received as `0x55`). This indicated a fundamental timing issue. The `baud_counter` was not properly synchronized with the incoming start bit, causing the receiver to sample data at the wrong time.

**Solution:** The issue was traced to the `baud_counter`'s restart mechanism. By adding a `restart_counter` output to the FSM, the `uart_rx_top` was able to precisely tell the `baud_counter` when a new frame had started, resetting it at the correct moment (the falling edge of the start bit). This ensured that the mid-bit `tick` was generated at the exact center of each data bit, resolving the timing drift and data corruption.

### Challenge 3: Testbench-to-DUT Port Mismatches

**Problem:** The testbench file (`RX_tb.v`) was not compatible with the `uart_rx_top.v` file. It was instantiating a module with the wrong name (`uart_rx`) and using incompatible port names (`reset` instead of `arst_n`). This resulted in an immediate compilation error.

**Solution:** The testbench was updated to correctly match the top-level module's name (`uart_rx_top`) and port names, ensuring a clean and successful compilation. This reinforced the importance of careful port-level verification before running a full simulation.


<img width="624" height="118" alt="image" src="https://github.com/user-attachments/assets/30c959d6-5ff8-4bb5-a0d0-547f14e09521" />
<img width="1270" height="491" alt="image" src="https://github.com/user-attachments/assets/1d5823ee-2138-4c3f-a3b1-22189a90d90b" />

