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
