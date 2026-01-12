`timescale 1ns / 1ps

module test();
    // System Signals
    reg clk_i = 0;
    reg rst_ni = 0;
    reg btn1 = 1;

    // Bus Interfaces
    wire scl_1, sda_1;
    wire scl_2, sda_2;

    pullup(sda_1);
    pullup(scl_1);

    pullup(sda_2);
    pullup(scl_2);

    wire [7:0] pwm_o;

    // 27 MHz Clock Generation
    always #18.5 clk_i = ~clk_i;

    // --- Device Under Test (DUT) ---
    top dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .scl_1_o(scl_1),
        .sda_1_io(sda_1),
        .scl_2_o(scl_2),
        .sda_2_io(sda_2),
        .pwm_o(pwm_o),
        .btn1(btn1)
    );

    reg [15:0] fake_analog_val = 16'h41234;
    reg [15:0] fake_analog_val2 = 16'h4321;

    ads1115_model #(
    .I2C_ADDR(7'b1001001)
    ) slave_device_1 (
        .sda(sda_1),
        .scl(scl_1),
        .analog_input(fake_analog_val)
    );

    ads1115_model #(
    .I2C_ADDR(7'b1001001)
    ) slave_device_2 (
        .sda(sda_2),
        .scl(scl_2),
        .analog_input(fake_analog_val2)
    );

    initial begin
        $dumpfile("3LFCC.vcd");
        $dumpvars(0, test);

        // System Startup
        #100 rst_ni = 1;

        #10000000
        $finish;
    end
endmodule