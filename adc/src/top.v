`default_nettype none
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
    inout i2cSda,
    output i2cScl
);

    wire [9:0] pixelAddress;
    wire [7:0] textPixelData;
    wire [5:0] charAddress;
    reg [7:0] charOutput = "A";

    screen #(STARTUP_WAIT) scr(
        clk, 
        ioSclk, 
        ioSdin, 
        ioCs, 
        ioDc, 
        ioReset, 
        pixelAddress,
        textPixelData
    );

    textEngine te(
        clk,
        pixelAddress,
        textPixelData,
        charAddress,
        charOutput
    );

    wire [1:0] i2cInstruction;
    wire [7:0] i2cByteToSend;
    wire [7:0] i2cByteReceived;
    wire i2cComplete;
    wire i2cEnable;

    wire sdaIn;
    wire sdaOut;
    wire isSending;
    assign i2cSda = (isSending & ~sdaOut) ? 1'b0 : 1'bz;
    assign sdaIn = i2cSda ? 1'b1 : 1'b0;

    i2c c(
        clk,
        sdaIn,
        sdaOut,
        isSending,
        i2cScl,
        i2cInstruction,
        i2cEnable,
        i2cByteToSend,
        i2cByteReceived,
        i2cComplete
    );

    reg [1:0] adcChannel = 0;
    wire [15:0] adcOutputData;
    wire adcDataReady;
    reg adcEnable = 0;

    adc #(7'b1001001) a(
        clk,
        adcChannel,
        adcOutputData,
        adcDataReady,
        adcEnable,
        i2cInstruction,
        i2cEnable,
        i2cByteToSend,
        i2cByteReceived,
        i2cComplete
    );

    reg [15:0] adcOutputBufferCh1 = 0;
    reg [15:0] adcOutputBufferCh2 = 0;
    reg [11:0] voltageCh1 = 0;
    reg [11:0] voltageCh2 = 0;

    localparam STATE_TRIGGER_CONV = 0;
    localparam STATE_WAIT_FOR_START = 1;
    localparam STATE_SAVE_VALUE_WHEN_READY = 2;

    reg [2:0] drawState = 0;

    always @(posedge clk) begin
        case (drawState)
            STATE_TRIGGER_CONV: begin
                adcEnable <= 1;
                drawState <= STATE_WAIT_FOR_START;
            end
            STATE_WAIT_FOR_START: begin
                if (~adcDataReady) begin
                    drawState <= STATE_SAVE_VALUE_WHEN_READY;
                end
            end
            STATE_SAVE_VALUE_WHEN_READY: begin
                if (adcDataReady) begin
                    adcChannel <= adcChannel[0] ? 2'b00 : 2'b01;
                    if (~adcChannel[0]) begin
                        adcOutputBufferCh1 <= adcOutputData;
                        voltageCh1 <= adcOutputData[15] ? 
                            12'd0 : adcOutputData[14:3];
                    end
                    else begin
                        adcOutputBufferCh2 <= adcOutputData;
                        voltageCh2 <= adcOutputData[15] ? 
                            12'd0 : adcOutputData[14:3];
                    end
                    drawState <= STATE_TRIGGER_CONV;
                    adcEnable <= 0;
                end
            end
        endcase
    end

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) begin: hexValCh1 
            wire [7:0] hexChar;
            toHex converter(clk, adcOutputBufferCh1[{i,2'b0}+:4], hexChar);
        end
    endgenerate
    generate
        for (i = 0; i < 4; i = i + 1) begin: hexValCh2
            wire [7:0] hexChar;
            toHex converter(clk, adcOutputBufferCh2[{i,2'b0}+:4], hexChar);
        end
    endgenerate

    wire [7:0] thousandsCh1, hundredsCh1, tensCh1, unitsCh1;
    wire [7:0] thousandsCh2, hundredsCh2, tensCh2, unitsCh2;

    toDec dec(
        clk,
        voltageCh1,
        thousandsCh1,
        hundredsCh1,
        tensCh1,
        unitsCh1
    );

    toDec dec2(
        clk,
        voltageCh2,
        thousandsCh2,
        hundredsCh2,
        tensCh2,
        unitsCh2
    );

    wire [1:0] rowNumber;
    assign rowNumber = charAddress[5:4];
    always @(posedge clk) begin
        if (rowNumber == 2'd0) begin
            case (charAddress[3:0])
                0: charOutput <= "D";
                1: charOutput <= "i";
                2: charOutput <= "f";
                4: charOutput <= "r";
                5: charOutput <= "a";
                6: charOutput <= "w";
                8: charOutput <= "0";
                9: charOutput <= "x";
                10: charOutput <= hexValCh1[3].hexChar;
                11: charOutput <= hexValCh1[2].hexChar;
                12: charOutput <= hexValCh1[1].hexChar;
                13: charOutput <= hexValCh1[0].hexChar;
                default: charOutput <= " ";
            endcase
        end
        else if (rowNumber == 2'd1) begin
            case (charAddress[3:0])
                0: charOutput <= "D";
                1: charOutput <= "i";
                2: charOutput <= "f";
                4: charOutput <= thousandsCh1;
                5: charOutput <= ".";
                6: charOutput <= hundredsCh1;
                7: charOutput <= tensCh1;
                8: charOutput <= unitsCh1;
                10: charOutput <= "V";
                11: charOutput <= "o";
                12: charOutput <= "l";
                13: charOutput <= "t";
                14: charOutput <= "s";
                default: charOutput <= " ";
            endcase
        end
        /*else if (rowNumber == 2'd2) begin
            case (charAddress[3:0])
                0: charOutput <= "C";
                1: charOutput <= "h";
                2: charOutput <= "2";
                4: charOutput <= "r";
                5: charOutput <= "a";
                6: charOutput <= "w";
                8: charOutput <= "0";
                9: charOutput <= "x";
                10: charOutput <= hexValCh2[3].hexChar;
                11: charOutput <= hexValCh2[2].hexChar;
                12: charOutput <= hexValCh2[1].hexChar;
                13: charOutput <= hexValCh2[0].hexChar;
                default: charOutput <= " ";
            endcase
        end
        else if (rowNumber == 2'd3) begin
            case (charAddress[3:0])
                0: charOutput <= "C";
                1: charOutput <= "h";
                2: charOutput <= "2";
                4: charOutput <= thousandsCh2;
                5: charOutput <= ".";
                6: charOutput <= hundredsCh2;
                7: charOutput <= tensCh2;
                8: charOutput <= unitsCh2;
                10: charOutput <= "V";
                11: charOutput <= "o";
                12: charOutput <= "l";
                13: charOutput <= "t";
                14: charOutput <= "s";
                default: charOutput <= " ";
            endcase
        end*/
    end

endmodule