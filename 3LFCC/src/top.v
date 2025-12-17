`timescale 1ns / 1ps

module top (
  // Clock and Reset
  input  wire        clk_i,           // 27 MHz Tang Nano Clock
  input  wire        rst_i,           // External Reset (Active High Button)

  // I2C Interface (ADS1115 ADC)
  output wire        scl_o,           // Serial Clock
  inout  wire        sda_io,          // Serial Data (Bidirectional)

  // PWM Outputs
  output wire [7:0]  pwm_o            // Mapped to JE pins
);

  // ---------------------------------------------------------------------------
  // 1. Clock & Reset Management
  // ---------------------------------------------------------------------------
  wire rst_ni;        // Internal Active-Low Reset

  // Normalize reset: User button (High) -> System Reset (Low)
  assign rst_ni = ~rst_i;

  // ---------------------------------------------------------------------------
  // 2. ADC Subsystem Signals
  // ---------------------------------------------------------------------------
  // Wrapper <-> I2C Master connections
  wire [1:0]  i2c_inst;
  wire        i2c_en;
  wire [7:0]  i2c_byte_tx;
  wire [7:0]  i2c_byte_rx;
  wire        i2c_done;
  wire        i2c_busy;

  // Tri-state buffer signals
  wire        sda_out_wire;
  wire        sda_in_wire;

  // ADC Data signals
  wire        adc_drdy;
  wire        adc_start_conv; // From Timer
  wire [15:0] adc_data_out;

  // Storage for ADC measurements
  reg  [15:0] v_meas_ch0_q; // Previously Ch7 (Flying Cap +)
  reg  [15:0] v_meas_ch1_q; // Previously Ch14 (Vout)
  reg  [15:0] v_meas_ch2_q; // Previously Ch15 (Flying Cap -)

  // Channel Sequencer
  reg  [1:0]  ch_idx_q;     // 0=AIN0, 1=AIN1, 2=AIN2

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
  // 4. ADC Data Acquisition Logic
  // ---------------------------------------------------------------------------

  // Capture data when ADC reports "Data Ready"
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      v_meas_ch0_q  <= 16'd0;
      v_meas_ch1_q  <= 16'd0;
      v_meas_ch2_q  <= 16'd0;
      ch_idx_q      <= 2'd0;
    end else begin
      if (adc_drdy) begin
        // Store data based on current channel
        case (ch_idx_q)
          2'd0: v_meas_ch0_q <= adc_data_out;
          2'd1: v_meas_ch1_q <= adc_data_out;
          2'd2: v_meas_ch2_q <= adc_data_out;
          default: ;
        endcase

        // Advance channel index (Round Robin: 0 -> 1 -> 2 -> 0)
        if (ch_idx_q == 2'd2)
          ch_idx_q <= 2'd0;
        else
          ch_idx_q <= ch_idx_q + 1;
      end
    end
  end

  // Calculate System Voltages
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      v_out_meas <= 16'd0;
      v_fc_calc  <= 16'd0;
    end else begin
      v_out_meas <= v_meas_ch1_q; // Vout is AIN1

      // Vfc = V_pos (AIN0) - V_neg (AIN2)
      if (v_meas_ch0_q >= v_meas_ch2_q)
        v_fc_calc <= v_meas_ch0_q - v_meas_ch2_q;
      else
        v_fc_calc <= 16'd0;
    end
  end

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

  // ---------------------------------------------------------------------------
  // 6. Submodule Instantiations
  // ---------------------------------------------------------------------------

  // ADC Wrapper (Driver)
  adc #(
    .address (7'd72) // 0x48 ADS1115
  ) u_adc (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .channel_i          (ch_idx_q),      // 0=AIN0, 1=AIN1, 2=AIN2
    .enable_i           (adc_start_conv),// Trigger from Timer
    .data_o             (adc_data_out),
    .data_ready_o       (adc_drdy),

    // I2C Connections
    .i2c_instruction_o  (i2c_inst),
    .i2c_enable_o       (i2c_en),
    .i2c_byte_to_send_o (i2c_byte_tx),
    .i2c_byte_received_i(i2c_byte_rx),
    .i2c_complete_i     (i2c_done)
  );

  // I2C Master (Physical Layer)
  i2c #(
    .DividerWidth (7) // 7 bits @ 27MHz = ~210kHz I2C Clock
  ) u_i2c (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .sda_i           (sda_in_wire),
    .sda_o           (sda_out_wire),
    .scl_o           (scl_o),
    .instruction_i   (i2c_inst),
    .enable_i        (i2c_en),
    .byte_to_send_i  (i2c_byte_tx),
    .byte_received_o (i2c_byte_rx),
    .complete_o      (i2c_done),
    .is_sending_o    (i2c_busy)
  );

  // Tri-State Logic for I2C SDA
  assign sda_io = (i2c_busy && !sda_out_wire) ? 1'b0 : 1'bz;
  assign sda_in_wire = sda_io;

  // Timer Control
  // CountMax = 7.5us * 27MHz = 202.5 -> 202 ticks
  timer_control #(
    .CountMax (202)
  ) u_timer_ctrl (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .eoc_i     (adc_drdy),       // Sync next trigger to previous Done
    .trigger_o (adc_start_conv)
  );

  // Control Algorithm (MATLAB Generated)
  fcc_fixpt u_controller (
    .clk        (clk_i),
    .reset      (~rst_ni),       // Code expects Active High reset
    .clk_enable (1'b1),
    .Voutref    (v_out_ref_q),
    .Vout       (v_out_meas),
    .Vfcref     (V_FC_REF),
    .Vfc        (v_fc_calc),
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
    .adc_trigger_o (),            // Not used, using Timer Control
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
