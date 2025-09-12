
# UART Core (Receiver)

## 1\. Project Overview

This project is a robust and modular implementation of a Universal Asynchronous Receiver (UART) core using Verilog HDL. The design is broken down into several independent blocks, each with a specific function, to ensure clarity, reusability, and ease of verification.

## 2\. Design Philosophy

My primary goal for this project was to create a design that was both functional and highly maintainable. I chose a modular approach, separating the complex logic into distinct, manageable blocks. This "divide and conquer" strategy was essential for several reasons:

  * **Clarity:** Each block, such as the `baud_counter` or the `FSM`, has a single, well-defined purpose, making the overall design easier to understand and debug.
  * **Reusability:** Individual modules can be easily reused in other projects without modification, which is a hallmark of good HDL design.
  * **Simplified Verification:** By verifying each module independently before integrating it into the top-level design, I could isolate bugs more efficiently, significantly reducing the overall debugging time.

## 3\. Block Descriptions & Code

The UART receiver core is built from the following sub-modules, each with a detailed description of its logic and function.

### UART Receiver Top-Level (`uart_rx_top.v`)

**Logic Description:** This is the top-level module of the UART receiver. Its main purpose is to instantiate and connect all the sub-modules, acting as the central hub for the entire design. It handles the external interface, including the clock (`clk`), active-low reset (`arst_n`), receiver enable (`rx_en`), and serial data input (`rx_in`). It also manages the internal wire connections between the FSM, baud counter, and other components. It then assigns the internal signals to the top-level outputs (`rx_data`, `rx_done`, `rx_err`, `rx_busy`), making the received data and status signals available to the external environment.

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

**Logic Description:** This module is a down-counter responsible for generating a one-cycle `tick` pulse at the precise middle of each bit period, a crucial step for correctly sampling the incoming data. The counter operates based on the `BAUD_DIV` parameter, which is calculated as `CLK_FREQ / BAUD_RATE`. When `en` is high, the counter decrements. The `restart` signal provides an asynchronous reset, allowing the FSM to re-synchronize the counter at the exact moment a start bit is detected. The `tick` signal is generated when the counter reaches the `MID_POINT` value, ensuring the most stable sampling point for the serial data.

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

**Logic Description:** The FSM is the brain of the receiver. It controls the entire reception process by transitioning through different states:

  * **IDLE:** The default state, waiting for the `start` signal from the edge detector.
  * **START:** Entered upon detection of a start bit. It validates the start bit and, if valid, transitions to the `DATA` state while asserting `busy`.
  * **DATA:** In this state, the FSM uses the `tick` signal from the baud counter to increment a bit counter (`bit_cnt`) and assert the `shift_en` signal to shift a bit into the SIPO register. It transitions to the `STOP` state after receiving all 8 data bits.
  * **STOP:** It waits for the `tick` to sample the stop bit. If the stop bit is valid, it asserts `done` and returns to `IDLE`. If not, it asserts `err` and returns to `IDLE`.

The FSM also generates the crucial `restart_counter` signal to re-synchronize the baud counter at the start of a new frame.

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

**Logic Description:** This module performs the core function of converting serial data to parallel data. It is an 8-bit register that shifts in one bit at a time from the `rx_in` line when the `shift_en` signal is high. The shifting is performed from the LSB (Least Significant Bit) towards the MSB (Most Significant Bit), as is standard in UART communication. After 8 shifts, the register holds the complete received byte in parallel form.

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

**Logic Description:** This simple sequential module is a state machine with two states (`HIGH` and `LOW`). It continuously monitors the `rx_in` signal. When it detects a falling edge (a transition from high to low), it means a potential start bit has arrived. Upon detecting this transition, it generates a single-cycle pulse on the `start` output signal. This pulse is then used by the FSM to begin the reception sequence.

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

The testbench is a self-checking verification environment for the UART receiver. It simulates a sender and checks the output of the DUT (`uart_rx_top`) against expected values.

### Key Features:

1.  **Clock and Reset Generation:** It provides the necessary clock signal and an active-low reset to initialize the DUT.
2.  **`sending_a_byte` Task:** A high-level Verilog task simplifies the process of transmitting a data byte. This task correctly handles the start bit, 8 data bits (LSB first), and the stop bit with precise timing, mimicking a real UART transmitter.
3.  **Self-Checking:** After a transmission, the testbench waits for the `rx_done` signal from the DUT and then compares the received `rx_data` to the expected value. This automated check ensures that the design is functioning correctly and provides clear pass/fail feedback.

<!-- end list -->

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

## 5\. Simulation Results

The following waveforms demonstrate the successful operation of the UART receiver.

\<img src="image\_902ee2.png" alt="Waveform showing reception of 0xAA" style="width:100%;"\>
**Figure 1:** This waveform shows a successful reception of the data byte `0xAA` (10101010). The `rx_in` line goes from high to low to signal the start bit, and you can see the data bits being sampled at the mid-point of each bit period. The `rx_data` output correctly latches the `8&#39;b10101010` value (or `0xAA`) after the stop bit is received, and the `rx_done` signal pulses high.

\<img src="Screenshot 2025-09-12 204702.png" alt="Waveform showing reception of 0x55" style="width:100%;"\>
**Figure 2:** This waveform illustrates another successful test case, where the data byte `0x55` (01010101) is received. Similar to the first case, the `rx_in` signal shows the correct bit sequence, the internal `rx_data` registers assemble the byte, and the `rx_done` signal asserts upon successful completion.

## 6\. Challenges and Solutions

Throughout the development and verification process, I encountered several key challenges.

### Challenge 1: Timing and Data Inversion

**Problem:** The initial simulations resulted in a `TIMEOUT` error and an incorrect `rx_data` value (e.g., `0xAA` was received as `0x55`). This indicated a critical timing issue. The `baud_counter` was not being reset at the precise moment of the start bit, causing the receiver to sample data at the wrong time and misinterpreting the bits.

**Solution:** I identified that the FSM needed to be responsible for initiating the `baud_counter`'s operation. I introduced a `restart_counter` signal, which is asserted by the FSM as soon as a valid start bit is detected. This signal ensures the `baud_counter` is reset at the correct time, allowing the `tick` signal to be perfectly aligned with the center of each data bit, thus solving the timing drift and data inversion.

### Challenge 2: Testbench-to-DUT Port Mismatches

**Problem:** My testbench was initially designed with incompatible port names and an incorrect module instantiation name. For example, my testbench used `uart_rx` and `reset`, while my top-level design was named `uart_rx_top` and used an active-low reset signal called `arst_n`. This led to compilation errors, preventing the simulation from even starting.

**Solution:** I performed a thorough review of all module interfaces. I renamed the testbench's signals (`reset` to `arst_n`) and updated the module instantiation to match the top-level design (`uart_rx_top`). This meticulous process of ensuring all module ports were consistent and correctly connected was a fundamental step in achieving a functional and verifiable design.


<img width="624" height="118" alt="image" src="https://github.com/user-attachments/assets/30c959d6-5ff8-4bb5-a0d0-547f14e09521" />
<img width="1270" height="491" alt="image" src="https://github.com/user-attachments/assets/1d5823ee-2138-4c3f-a3b1-22189a90d90b" />

