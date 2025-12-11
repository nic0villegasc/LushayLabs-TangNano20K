module top
#(
  parameter STARTUP_WAIT = 32'd10000000
)
(
    input clk,
    output ioSclk,
    output ioSdin,
    output ioCs,
    output ioDc,
    output ioReset,
    input uartRx
);
    wire [9:0] pixelAddress;
    wire [7:0] textPixelData, chosenPixelData;
    wire [5:0] charAddress;
    reg [7:0] charOutput;

    wire uartByteReady;
    wire [7:0] uartDataIn;
    wire [1:0] rowNumber;

    screen #(STARTUP_WAIT) scr(
        clk, 
        ioSclk, 
        ioSdin, 
        ioCs, 
        ioDc, 
        ioReset, 
        pixelAddress,
        chosenPixelData
    );

    textEngine te(
        clk,
        pixelAddress,
        textPixelData,
        charAddress,
        charOutput
    );

    assign rowNumber = charAddress[5:4];

    uart u(
        clk,
        uartRx,
        uartByteReady,
        uartDataIn
    );

    always @(posedge clk) begin
        case (rowNumber)
            0: charOutput <= "A";
            1: charOutput <= "B";
            2: charOutput <= "C";
            3: charOutput <= "D";
        endcase
    end
    assign chosenPixelData = textPixelData;
endmodule