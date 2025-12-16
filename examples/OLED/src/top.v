module top
(
    input clk,
    output io_sclk,
    output io_sdin,
    output io_cs,
    output io_dc,
    output io_reset,
);
    wire [9:0] pixelAddress;
    wire [7:0] pixelData;

    oled scr(
        clk, 
        io_sclk, 
        io_sdin, 
        io_cs, 
        io_dc, 
        io_reset, 
        pixelAddress,
        pixelData
    );

    textEngine te(
        clk,
        pixelAddress,
        pixelData
    );
endmodule