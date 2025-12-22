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
            toHex converter(clk_i, adc1_buffer_i[{i,2'b0}+:4], hexChar);
        end
    endgenerate
    
    // Channel 2 Hex
    generate
        for (i = 0; i < 4; i = i + 1) begin: g_hexValCh2
            wire [7:0] hexChar;
            toHex converter(clk_i, adc2_buffer_i[{i,2'b0}+:4], hexChar);
        end
    endgenerate

    wire [7:0] thousandsCh1, hundredsCh1, tensCh1, unitsCh1;
    wire [7:0] thousandsCh2, hundredsCh2, tensCh2, unitsCh2;

    toDec dec(
        clk_i, adc_voltage_fc_o, thousandsCh1, hundredsCh1, tensCh1, unitsCh1
    );
    toDec dec2(
        clk_i, adc_voltage_out_o, thousandsCh2, hundredsCh2, tensCh2, unitsCh2
    );

    // --- TEXT RENDERING ---
    wire [1:0] rowNumber;
    assign rowNumber = charAddress[5:4];
    
    always @(posedge clk_i) begin
        if (rowNumber == 2'd0) begin
            // Row 0: Ch1 Volts
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
        else if (rowNumber == 2'd1) begin
            // Row 1: Ch2 Volts
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
        else if (rowNumber == 2'd2) begin
            // Row 3: Sampling Frequency
            case (charAddress[3:0])
                0: charOutput <= "F"; // Ch2
                1: charOutput <= "s";
                //4: charOutput <= thousands_counter;
                //5: charOutput <= ".";
                6: charOutput <= hundreds_counter;
                7: charOutput <= tens_counter;
                8: charOutput <= units_counter;
                10: charOutput <= "H";
                11: charOutput <= "z";
                default: charOutput <= " ";
            endcase
        end
        /*else if (rowNumber == 2'd3) begin
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
        end*/
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
  wire [6:0]  duty_d1_o;
  wire [6:0]  duty_d2_o;

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
    wire [1:0] i2c1_instruction_i;
    wire [7:0] i2c1_byte_to_send_i, i2c1_byte_received_o;
    wire i2c1_complete_o, i2c1_enable_i;
    wire sdaIn_1, sdaOut_1, isSending_1;

    assign sda_1_io = (isSending_1 & ~sdaOut_1) ? 1'b0 : 1'bz;
    assign sdaIn_1 = sda_1_io ? 1'b1 : 1'b0;

    i2c c(
        clk_i, sdaIn_1, sdaOut_1, isSending_1, scl_1_o,
        i2c1_instruction_i, i2c1_enable_i, i2c1_byte_to_send_i, i2c1_byte_received_o, i2c1_complete_o
    );

    // --- I2C BUS 2 (ADC 2) ---
    wire [1:0] i2c2_instruction_i;
    wire [7:0] i2c2_byte_to_send_i, i2c2_byte_received_o;
    wire i2c2_complete_o, i2c2_enable_i;
    wire sdaIn_2, sdaOut_2, isSending_2;

    // Tristate logic for Bus 2
    assign sda_2_io = (isSending_2 & ~sdaOut_2) ? 1'b0 : 1'bz;
    assign sdaIn_2 = sda_2_io ? 1'b1 : 1'b0;

    i2c c2(
        clk_i, sdaIn_2, sdaOut_2, isSending_2, scl_2_o,
        i2c2_instruction_i, i2c2_enable_i, i2c2_byte_to_send_i, i2c2_byte_received_o, i2c2_complete_o
    );

    // --- ADC INSTANCES ---

    // ADC 1 Control Signals
    reg adc1_enable_i = 0;
    wire [15:0] adc1_data_o;
    wire adc1_ready_o;
    
    // ADC 2 Control Signals
    reg adc2_enable_i = 0;
    wire [15:0] adc2_data_o;
    wire adc2_ready_o;

    // ADC 1 Instance
    adc #(.address(7'b1001001), .MUX_CONFIG(3'b000)) u_adc_1(
        .clk_i(clk_i),
        .data_o(adc1_data_o),
        .data_ready_o(adc1_ready_o),
        .enable_i(adc1_enable_i),
        .i2c_instruction_o(i2c1_instruction_i),
        .i2c_enable_o(i2c1_enable_i),
        .i2c_byte_to_send_o(i2c1_byte_to_send_i),
        .i2c_byte_received_i(i2c1_byte_received_o),
        .i2c_complete_i(i2c1_complete_o)
    );

    // ADC 2 Instance (Same address, distinct I2C bus and Mux config)
    adc #(.address(7'b1001001), .MUX_CONFIG(3'b100)) u_adc_2(
        .clk_i(clk_i),
        .data_o(adc2_data_o),
        .data_ready_o(adc2_ready_o),
        .enable_i(adc2_enable_i),
        .i2c_instruction_o(i2c2_instruction_i),
        .i2c_enable_o(i2c2_enable_i),
        .i2c_byte_to_send_o(i2c2_byte_to_send_i),
        .i2c_byte_received_i(i2c2_byte_received_o),
        .i2c_complete_i(i2c2_complete_o)
    );

    // --- DATA BUFFERS ---
    reg [15:0] adc1_buffer_i = 0;
    reg [15:0] adc2_buffer_i = 0;
    reg [11:0] adc_voltage_fc_o = 0;
    reg [11:0] adc_voltage_out_o = 0;

    // --- FSM STATE MACHINE ---
    localparam STATE_TRIGGER_CONV = 0;
    localparam STATE_WAIT_FOR_START = 1;
    localparam STATE_SAVE_VALUE_WHEN_READY = 2;

    reg [2:0] drawState = 0;
    
    // Flags to ensure we capture both channels before resetting
    reg adc1_done_o = 0;
    reg adc2_done_o = 0;
    reg adc_eoc_o = 0;
    wire adc_start_i;

    // fsm_adc: Main ADC Control FSM
    always @(posedge clk_i) begin
        case (drawState)
            STATE_TRIGGER_CONV: begin
              adc_eoc_o <= 0;
              if(adc_start_i) begin
                // Trigger both ADCs
                adc1_enable_i <= 1;
                adc2_enable_i <= 1;
                adc1_done_o <= 0;
                adc2_done_o <= 0;
                drawState <= STATE_WAIT_FOR_START;
              end
            end
            STATE_WAIT_FOR_START: begin
                // Wait for both to acknowledge (DataReady goes LOW when busy)
                // We proceed only when both are busy to ensure we don't catch a stale "Ready"
                if (~adc1_ready_o && ~adc2_ready_o) begin
                    drawState <= STATE_SAVE_VALUE_WHEN_READY;
                end
            end
            STATE_SAVE_VALUE_WHEN_READY: begin
                // Capture Channel 1
                if (adc1_ready_o && !adc1_done_o) begin
                    adc1_buffer_i <= adc1_data_o;
                    adc_voltage_fc_o <= adc1_data_o[15] ? 12'd0 : adc1_data_o[14:3];
                    adc1_enable_i <= 0; // Stop ADC 1
                    adc1_done_o <= 1;
                end

                // Capture Channel 2
                if (adc2_ready_o && !adc2_done_o) begin
                    adc2_buffer_i <= adc2_data_o;
                    adc_voltage_out_o <= adc2_data_o[15] ? 12'd0 : adc2_data_o[14:3];
                    adc2_enable_i <= 0; // Stop ADC 2
                    adc2_done_o <= 1;
                end

                // Go back only when both are done
                if (adc1_done_o && adc2_done_o) begin
                    adc_eoc_o <= 1;
                    drawState <= STATE_TRIGGER_CONV;
                end
            end
            default: begin
                drawState <= STATE_TRIGGER_CONV;
            end
        endcase
    end

    reg enable_control_i;

  // ---------------------------------------------------------------------------
  // Synchronization Logic
  // ---------------------------------------------------------------------------
  // Only run the controller when BOTH ADCs have finished

  // Timer Control
  // CountMax = 7.5us * 27MHz = 202.5 -> 202 ticks
  timer_control #(
    .CountMax (43200)
  ) u_timer_ctrl (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .eoc_i     (adc_eoc_o),
    .trigger_o (enable_control_i)
  );

  /// ---------------------------------------------------------------------------
  // Control Algorithm
  // ---------------------------------------------------------------------------
  fcc_fixpt u_controller (
    .clk        (clk_i),
    .reset      (~rst_ni),
    .clk_enable (enable_control_i), // Waits for both ADCs
    .Voutref    (v_out_ref_q),
    .Vout       (adc_voltage_out_o),     // Direct connection from ADC 2
    .Vfcref     (V_FC_REF),
    .Vfc        (adc_voltage_fc_o),      // Direct connection from ADC 1
    .D1         (duty_d1_o),
    .D2         (duty_d2_o),
    .ce_out     (),
    .ui         (),
    .uv         ()
  );

  /// ---------------------------------------------------------------------------
  // Average Sampling Time Calculation
  /// ---------------------------------------------------------------------------

  /// ---------------------------------------------------------------------------
  // Average Sampling Time Calculation (FIXED)
  /// ---------------------------------------------------------------------------

  reg [24:0] clk_counter;
  reg [15:0] sample_count = 0;       // Increased to 16-bit to prevent overflow > 4095Hz
  reg [15:0] freq_display_hold = 0;  // NEW: Holds the value to show on screen

  always @(posedge clk_i) begin
    if(!rst_ni) begin
      clk_counter <= 0;
      pwm_o[5] <= 1;
      sample_count <= 0;
      freq_display_hold <= 0;
    end else begin
      // 1. Count the samples
      // The FSM ensures this condition is true for exactly 1 cycle per conversion
      if (adc1_done_o && adc2_done_o) begin
        sample_count <= sample_count + 1;
      end

      // 2. One Second Timer (27 MHz)
      if(clk_counter == 25'd27000000) begin
        clk_counter <= 0;
        
        // LATCH: Save the result to the display register
        freq_display_hold <= sample_count; 
        
        // RESET: Clear the counter for the new second
        sample_count <= 0;
        
        // Toggle Heartbeat LED
        pwm_o[5] <= ~pwm_o[5]; 
      end else begin
        clk_counter <= clk_counter + 1;
      end
    end
  end

  wire [7:0] thousands_counter, hundreds_counter, tens_counter, units_counter;

  // 3. Connect the HOLD register (Static Value) to the display, not the counter
  toDec dec3(
    clk_i, 
    freq_display_hold,
    thousands_counter, 
    hundreds_counter, 
    tens_counter, 
    units_counter
  );

  /// ---------------------------------------------------------------------------
  // PS-PWM MODULATOR
  /// ---------------------------------------------------------------------------

  // PS-PWM Modulator
  wire [3:0] pwm_signals_o;

  ps_pwm u_modulator (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .duty_d1_i     (duty_d1_o),
    .duty_d2_i     (duty_d2_o),
    .adc_trigger_o (adc_start_i),
    .pwm_o         (pwm_signals_o)
  );

  // ---------------------------------------------------------------------------
  // 7. Output Assignments
  // ---------------------------------------------------------------------------
  // Bits 0-3: PWM Signals
  assign pwm_o[3:0] = pwm_signals_o;

  // Bits 4-7: Debug / Static outputs (Keep original behavior)
  assign pwm_o[4]   = 1'b1;
  assign pwm_o[6]   = 1'b0;
  assign pwm_o[7]   = 1'b0;

endmodule
