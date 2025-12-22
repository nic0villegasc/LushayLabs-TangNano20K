`timescale 1ns / 1ps

module top (
  // Clock and Reset
  input  wire        clk_i,           // 27 MHz Tang Nano Clock
  input  wire        rst_ni,           // External Reset (Active High Button)

  // ADC 1 Interface (Differential - Flying Cap)
  output wire       scl_1_o,
  inout  wire       sda_1_io,

  // ADC 2 Interface (Single Ended - Vout)
  output wire       scl_2_o,
  inout  wire       sda_2_io,

  // PWM Outputs
  output wire [7:0]  pwm_o,

  // Screen
  output wire ioSclk,
  output wire ioSdin,
  output wire ioCs,
  output wire ioDc,
  output wire ioReset,
  input wire btn1
);

  // --- SCREEN & TEXT ENGINE ---
    wire [9:0] pixelAddress;
    wire [7:0] textPixelData;
    wire [5:0] charAddress;
    reg [7:0] charOutput = "A";

    screen #(32'd10000000) scr(
        clk_i, ioSclk, ioSdin, ioCs, ioDc, ioReset, pixelAddress, textPixelData
    );
    textEngine te(
        clk_i, pixelAddress, textPixelData, charAddress, charOutput
    );

    // --- DISPLAY CONVERSION ---
    genvar i;
    // Channel 1 Hex
    generate
        for (i = 0; i < 4; i = i + 1) begin: g_hexValCh1
            wire [7:0] hexChar;
            toHex converter(clk_i, adcOutputBufferCh1[{i,2'b0}+:4], hexChar);
        end
    endgenerate
    
    // Channel 2 Hex
    generate
        for (i = 0; i < 4; i = i + 1) begin: g_hexValCh2
            wire [7:0] hexChar;
            toHex converter(clk_i, adcOutputBufferCh2[{i,2'b0}+:4], hexChar);
        end
    endgenerate

    wire [7:0] thousandsCh1, hundredsCh1, tensCh1, unitsCh1;
    wire [7:0] thousandsCh2, hundredsCh2, tensCh2, unitsCh2;

    toDec dec(
        clk_i, voltageCh1, thousandsCh1, hundredsCh1, tensCh1, unitsCh1
    );
    toDec dec2(
        clk_i, voltageCh2, thousandsCh2, hundredsCh2, tensCh2, unitsCh2
    );

    // --- TEXT RENDERING ---
    wire [1:0] rowNumber;
    assign rowNumber = charAddress[5:4];
    
    always @(posedge clk_i) begin
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

  // ---------------------------------------------------------------------------
  // 3. Control System Signals
  // ---------------------------------------------------------------------------
  // Voltage Calculations
  reg  [15:0] v_fc_calc;    // Calculated Flying Cap Voltage
  reg  [15:0] v_out_meas;   // Measured Output Voltage

  // Reference Sequencer (Soft Start)
  reg  [15:0] v_out_ref_q;
  reg  [20:0] tick_cnt_q;
  reg  [2:0]  seq_idx_q;
  reg         seq_dir_q;    // 1 = Up, 0 = Down

  // Controller Outputs
  wire [6:0]  duty_d1;
  wire [6:0]  duty_d2;

  // Constants
  localparam [15:0] VREF_0V0 = 16'h0000;
  localparam [15:0] VREF_0V6 = 16'h2653;
  localparam [15:0] VREF_1V2 = 16'h4CCE;
  localparam [15:0] VREF_1V8 = 16'h733A;
  localparam [15:0] V_FC_REF = 16'h6990;

  // 1 Million cycles @ 27MHz is ~37ms per step (reasonable for soft start)
  localparam integer STEP_CYCLES = 1000000;

  // ---------------------------------------------------------------------------
  // 5. Reference Sequencer (Soft Start FSM)
  // ---------------------------------------------------------------------------
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tick_cnt_q  <= 0;
      seq_idx_q   <= 0;
      seq_dir_q   <= 1'b1;
      v_out_ref_q <= VREF_0V0;
    end else begin
      if (tick_cnt_q == STEP_CYCLES - 1) begin
        tick_cnt_q <= 0;

        case (seq_idx_q)
          3'd0:    v_out_ref_q <= VREF_0V0;
          3'd1:    v_out_ref_q <= VREF_0V6;
          3'd2:    v_out_ref_q <= VREF_1V2;
          3'd3:    v_out_ref_q <= VREF_1V8;
          default: v_out_ref_q <= VREF_0V0;
        endcase

        if (seq_dir_q) begin
          if (seq_idx_q == 3'd3) begin
            seq_dir_q <= 1'b0;
            seq_idx_q <= 3'd2;
          end else begin
            seq_idx_q <= seq_idx_q + 3'd1;
          end
        end else begin
          if (seq_idx_q == 3'd0) begin
            seq_dir_q <= 1'b1;
            seq_idx_q <= 3'd1;
          end else begin
            seq_idx_q <= seq_idx_q - 3'd1;
          end
        end
      end else begin
        tick_cnt_q <= tick_cnt_q + 1;
      end
    end
  end

  // --- I2C BUS 1 (ADC 1) ---
    wire [1:0] i2cInstruction;
    wire [7:0] i2cByteToSend, i2cByteReceived;
    wire i2cComplete, i2cEnable;
    wire sdaIn_1, sdaOut_1, isSending_1;

    assign sda_1_io = (isSending_1 & ~sdaOut_1) ? 1'b0 : 1'bz;
    assign sdaIn_1 = sda_1_io ? 1'b1 : 1'b0;

    i2c c(
        clk_i, sdaIn_1, sdaOut_1, isSending_1, scl_1_o,
        i2cInstruction, i2cEnable, i2cByteToSend, i2cByteReceived, i2cComplete
    );

    // --- I2C BUS 2 (ADC 2) ---
    wire [1:0] i2cInstruction_2;
    wire [7:0] i2cByteToSend_2, i2cByteReceived_2;
    wire i2cComplete_2, i2cEnable_2;
    wire sdaIn_2, sdaOut_2, isSending_2;

    // Tristate logic for Bus 2
    assign sda_2_io = (isSending_2 & ~sdaOut_2) ? 1'b0 : 1'bz;
    assign sdaIn_2 = sda_2_io ? 1'b1 : 1'b0;

    i2c c2(
        clk_i, sdaIn_2, sdaOut_2, isSending_2, scl_2_o,
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
        clk_i, adcOutputData, adcDataReady, adcEnable,
        i2cInstruction, i2cEnable, i2cByteToSend, i2cByteReceived, i2cComplete
    );

    // ADC 2 Instance (Same address, distinct I2C bus and Mux config)
    adc #(.address(7'b1001001), .MUX_CONFIG(3'b100)) a2(
        clk_i, adcOutputData2, adcDataReady2, adcEnable2,
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
    /*reg [1:0] btn_sync;
    reg btn_prev;
    reg [15:0] debounce_cnt;
    reg trigger_pulse;

    always @(posedge clk_i) begin
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
    end*/

    // Main ADC Control FSM
    always @(posedge clk_i) begin
        case (drawState)
            STATE_TRIGGER_CONV: begin
              controller_en <= 0;
              if(adc_start_conv) begin
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
                    controller_en <= 1;
                    drawState <= STATE_TRIGGER_CONV;
                end
            end
            default: begin
                drawState <= STATE_TRIGGER_CONV;
            end
        endcase
    end

  // ---------------------------------------------------------------------------
  // Synchronization Logic
  // ---------------------------------------------------------------------------
  // Only run the controller when BOTH ADCs have finished
  wire controller_en;
  assign controller_en = adc_drdy_1 && adc_drdy_2;

  // Timer Control
  // CountMax = 7.5us * 27MHz = 202.5 -> 202 ticks
  /*timer_control #(
    .CountMax (202)
  ) u_timer_ctrl (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .eoc_i     (adc_drdy),       // Sync next trigger to previous Done
    .trigger_o (adc_start_conv)
  );*/

  /// ---------------------------------------------------------------------------
  // Control Algorithm
  // ---------------------------------------------------------------------------
  fcc_fixpt u_controller (
    .clk        (clk_i),
    .reset      (~rst_ni),
    .clk_enable (controller_en), // Waits for both ADCs
    .Voutref    (v_out_ref_q),
    .Vout       (v_out_raw),     // Direct connection from ADC 2
    .Vfcref     (V_FC_REF),
    .Vfc        (v_fc_raw),      // Direct connection from ADC 1
    .D1         (duty_d1),
    .D2         (duty_d2),
    .ce_out     (),
    .ui         (),
    .uv         ()
  );

  // PS-PWM Modulator
  wire [3:0] pwm_signals;

  ps_pwm u_modulator (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .duty_d1_i     (duty_d1),
    .duty_d2_i     (duty_d2),
    .adc_trigger_o (adc_start_conv),
    .pwm_o         (pwm_signals)
  );

  // ---------------------------------------------------------------------------
  // 7. Output Assignments
  // ---------------------------------------------------------------------------
  // Bits 0-3: PWM Signals
  assign pwm_o[3:0] = pwm_signals;

  // Bits 4-7: Debug / Static outputs (Keep original behavior)
  assign pwm_o[4]   = 1'b1;
  assign pwm_o[5]   = 1'b1;
  assign pwm_o[6]   = 1'b0;
  assign pwm_o[7]   = 1'b0;

endmodule
