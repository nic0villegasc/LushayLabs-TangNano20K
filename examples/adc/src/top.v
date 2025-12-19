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
    inout i2cSda_1,
    output i2cScl_1,
    inout i2cSda_2, // Second I2C Bus Data
    output i2cScl_2, // Second I2C Bus Clock
    input btn1
);

    // --- SCREEN & TEXT ENGINE ---
    wire [9:0] pixelAddress;
    wire [7:0] textPixelData;
    wire [5:0] charAddress;
    reg [7:0] charOutput = "A";

    screen #(STARTUP_WAIT) scr(
        clk, ioSclk, ioSdin, ioCs, ioDc, ioReset, pixelAddress, textPixelData
    );
    textEngine te(
        clk, pixelAddress, textPixelData, charAddress, charOutput
    );

    // --- I2C BUS 1 (ADC 1) ---
    wire [1:0] i2cInstruction;
    wire [7:0] i2cByteToSend, i2cByteReceived;
    wire i2cComplete, i2cEnable;
    wire sdaIn_1, sdaOut_1, isSending_1;

    assign i2cSda_1 = (isSending_1 & ~sdaOut_1) ? 1'b0 : 1'bz;
    assign sdaIn_1 = i2cSda_1 ? 1'b1 : 1'b0;

    i2c c(
        clk, sdaIn_1, sdaOut_1, isSending_1, i2cScl_1,
        i2cInstruction, i2cEnable, i2cByteToSend, i2cByteReceived, i2cComplete
    );

    // --- I2C BUS 2 (ADC 2) ---
    wire [1:0] i2cInstruction_2;
    wire [7:0] i2cByteToSend_2, i2cByteReceived_2;
    wire i2cComplete_2, i2cEnable_2;
    wire sdaIn_2, sdaOut_2, isSending_2;

    // Tristate logic for Bus 2
    assign i2cSda_2 = (isSending_2 & ~sdaOut_2) ? 1'b0 : 1'bz;
    assign sdaIn_2 = i2cSda_2 ? 1'b1 : 1'b0;

    i2c c2(
        clk, sdaIn_2, sdaOut_2, isSending_2, i2cScl_2,
        i2cInstruction_2, i2cEnable_2, i2cByteToSend_2, i2cByteReceived_2, i2cComplete_2
    );

    // --- ADC INSTANCES ---

    // ADC 1 Control Signals
    reg adcEnable = 0;
    wire [15:0] adcOutputData;
    wire adcDataReady;
    
    // ADC 2 Control Signals
    reg adcEnable2 = 0;
    wire [15:0] adcOutputData2;
    wire adcDataReady2;

    // ADC 1 Instance
    adc #(.address(7'b1001001), .MUX_CONFIG(3'b000)) a(
        clk, adcOutputData, adcDataReady, adcEnable,
        i2cInstruction, i2cEnable, i2cByteToSend, i2cByteReceived, i2cComplete
    );

    // ADC 2 Instance (Same address, distinct I2C bus and Mux config)
    adc #(.address(7'b1001001), .MUX_CONFIG(3'b100)) a2(
        clk, adcOutputData2, adcDataReady2, adcEnable2,
        i2cInstruction_2, i2cEnable_2, i2cByteToSend_2, i2cByteReceived_2, i2cComplete_2
    );

    // --- DATA BUFFERS ---
    reg [15:0] adcOutputBufferCh1 = 0;
    reg [15:0] adcOutputBufferCh2 = 0;
    reg [11:0] voltageCh1 = 0;
    reg [11:0] voltageCh2 = 0;

    // --- FSM STATE MACHINE ---
    localparam STATE_TRIGGER_CONV = 0;
    localparam STATE_WAIT_FOR_START = 1;
    localparam STATE_SAVE_VALUE_WHEN_READY = 2;

    reg [2:0] drawState = 0;
    
    // Flags to ensure we capture both channels before resetting
    reg ch1_done = 0;
    reg ch2_done = 0;

    // Button Debounce Logic
    reg [1:0] btn_sync;
    reg btn_prev;
    reg [15:0] debounce_cnt;
    reg trigger_pulse;

    always @(posedge clk) begin
        btn_sync <= {btn_sync[0], ~btn1};
        if (btn_sync[1] != btn_prev) begin
            if (&debounce_cnt) begin
                btn_prev <= btn_sync[1];
                debounce_cnt <= 0;
            end else begin
                debounce_cnt <= debounce_cnt + 1;
            end
        end else begin
            debounce_cnt <= 0;
        end
        trigger_pulse <= (btn_sync[1] && !btn_prev && &debounce_cnt);
    end

    // Main ADC Control FSM
    always @(posedge clk) begin
        case (drawState)
            STATE_TRIGGER_CONV: begin
              if(trigger_pulse) begin
                // Trigger both ADCs
                adcEnable <= 1;
                adcEnable2 <= 1;
                ch1_done <= 0;
                ch2_done <= 0;
                drawState <= STATE_WAIT_FOR_START;
              end
            end
            STATE_WAIT_FOR_START: begin
                // Wait for both to acknowledge (DataReady goes LOW when busy)
                // We proceed only when both are busy to ensure we don't catch a stale "Ready"
                if (~adcDataReady && ~adcDataReady2) begin
                    drawState <= STATE_SAVE_VALUE_WHEN_READY;
                end
            end
            STATE_SAVE_VALUE_WHEN_READY: begin
                // Capture Channel 1
                if (adcDataReady && !ch1_done) begin
                    adcOutputBufferCh1 <= adcOutputData;
                    voltageCh1 <= adcOutputData[15] ? 12'd0 : adcOutputData[14:3];
                    adcEnable <= 0; // Stop ADC 1
                    ch1_done <= 1;
                end

                // Capture Channel 2
                if (adcDataReady2 && !ch2_done) begin
                    adcOutputBufferCh2 <= adcOutputData2;
                    voltageCh2 <= adcOutputData2[15] ? 12'd0 : adcOutputData2[14:3];
                    adcEnable2 <= 0; // Stop ADC 2
                    ch2_done <= 1;
                end

                // Go back only when both are done
                if (ch1_done && ch2_done) begin
                    drawState <= STATE_TRIGGER_CONV;
                end
            end
            default: begin
                drawState <= STATE_TRIGGER_CONV;
            end
        endcase
    end

    // --- DISPLAY CONVERSION ---
    genvar i;
    // Channel 1 Hex
    generate
        for (i = 0; i < 4; i = i + 1) begin: g_hexValCh1
            wire [7:0] hexChar;
            toHex converter(clk, adcOutputBufferCh1[{i,2'b0}+:4], hexChar);
        end
    endgenerate
    
    // Channel 2 Hex
    generate
        for (i = 0; i < 4; i = i + 1) begin: g_hexValCh2
            wire [7:0] hexChar;
            toHex converter(clk, adcOutputBufferCh2[{i,2'b0}+:4], hexChar);
        end
    endgenerate

    wire [7:0] thousandsCh1, hundredsCh1, tensCh1, unitsCh1;
    wire [7:0] thousandsCh2, hundredsCh2, tensCh2, unitsCh2;

    toDec dec(
        clk, voltageCh1, thousandsCh1, hundredsCh1, tensCh1, unitsCh1
    );
    toDec dec2(
        clk, voltageCh2, thousandsCh2, hundredsCh2, tensCh2, unitsCh2
    );

    // --- TEXT RENDERING ---
    wire [1:0] rowNumber;
    assign rowNumber = charAddress[5:4];
    
    always @(posedge clk) begin
        if (rowNumber == 2'd0) begin
            // Row 0: Ch1 Raw Hex
            case (charAddress[3:0])
                0: charOutput <= "D"; // Dif
                1: charOutput <= "i";
                2: charOutput <= "f";
                4: charOutput <= "r";
                5: charOutput <= "a";
                6: charOutput <= "w";
                8: charOutput <= "0";
                9: charOutput <= "x";
                10: charOutput <= g_hexValCh1[3].hexChar;
                11: charOutput <= g_hexValCh1[2].hexChar;
                12: charOutput <= g_hexValCh1[1].hexChar;
                13: charOutput <= g_hexValCh1[0].hexChar;
                default: charOutput <= " ";
            endcase
        end
        else if (rowNumber == 2'd1) begin
            // Row 1: Ch1 Volts
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
        else if (rowNumber == 2'd2) begin
            // Row 2: Ch2 Raw Hex
            case (charAddress[3:0])
                0: charOutput <= "O"; // Ch2
                1: charOutput <= "u";
                2: charOutput <= "t";
                4: charOutput <= "r";
                5: charOutput <= "a";
                6: charOutput <= "w";
                8: charOutput <= "0";
                9: charOutput <= "x";
                // Fixed: referencing g_hexValCh2
                10: charOutput <= g_hexValCh2[3].hexChar;
                11: charOutput <= g_hexValCh2[2].hexChar;
                12: charOutput <= g_hexValCh2[1].hexChar;
                13: charOutput <= g_hexValCh2[0].hexChar;
                default: charOutput <= " ";
            endcase
        end
        else if (rowNumber == 2'd3) begin
            // Row 3: Ch2 Volts
            case (charAddress[3:0])
                0: charOutput <= "O"; // Ch2
                1: charOutput <= "u";
                2: charOutput <= "t";
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
        end
    end

endmodule
