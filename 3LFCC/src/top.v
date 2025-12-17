`timescale 1ns / 1ps

module top (
  // Clock and Reset
  input  wire        clk_i,           // External Clock Input (27MHz)
  input  wire        rst_i,           // External Reset (Assumed Active High SW3)

  // Analog Inputs (ADC Channels)
  input  wire        vauxp7_i,        // Channel 7 Positive
  input  wire        vauxn7_i,        // Channel 7 Negative
  input  wire        vauxp14_i,       // Channel 14 Positive
  input  wire        vauxn14_i,       // Channel 14 Negative
  input  wire        vauxp15_i,       // Channel 15 Positive
  input  wire        vauxn15_i,       // Channel 15 Negative

  // PWM Outputs
  output wire [7:0]  pwm_o
);

  // ---------------------------------------------------------------------------
  // 1. Clock & Reset Management
  // ---------------------------------------------------------------------------
  wire clk_100m;      // Main System Clock
  wire rst_ni;        // Internal Active-Low Reset
  wire locked;        // PLL Lock Status

  // Normalize reset: User button (High) -> System Reset (Low)
  assign rst_ni = ~rst_i;

  // FIXME: Temporary direct clock assignment for simulation/synthesis
  // In actual implementation, replace with PLL generating from 27MHz.
  // We have to consider that the TangNano 20K uses 27 MHz input clock.
  assign clk_100m = clk_i;

  /*
  // Placeholder for PLL
  gowin_rpll u_pll (
    .clkout (clk_100m),
    .lock   (locked),
    .reset  (~rst_ni),
    .clkin  (clk_i)
  );
  */

  // ---------------------------------------------------------------------------
  // 2. ADC Signal Declarations & wrapper
  // ---------------------------------------------------------------------------
  wire        adc_eoc;
  wire        adc_drdy;
  wire [15:0] adc_data_out;
  reg  [6:0]  adc_channel_addr;

  // Storage for ADC measurements
  reg  [15:0] v_meas_ch7_q;
  reg  [15:0] v_meas_ch14_q;
  reg  [15:0] v_meas_ch15_q;

  // Channel Indexing State Machine
  reg  [1:0]  ch_idx_q;

  // ADC Trigger (Start Conversion)
  wire        adc_start_conv;

  // ---------------------------------------------------------------------------
  // 3. Control System Signals
  // ---------------------------------------------------------------------------
  // Voltage References and Measurements
  reg  [15:0] v_fc_calc;    // Calculated Flying Cap Voltage
  reg  [15:0] v_out_meas;   // Measured Output Voltage

  // Reference Sequencer Signals (Soft Start)
  reg  [15:0] v_out_ref_q;
  reg  [20:0] tick_cnt_q;
  reg  [2:0]  seq_idx_q;
  reg         seq_dir_q;    // 1 = Up, 0 = Down

  // Controller Outputs
  wire [6:0]  duty_d1;
  wire [6:0]  duty_d2;

  // Fixed-Point Controller Constants
  localparam [15:0] VREF_0V0 = 16'h0000;
  localparam [15:0] VREF_0V6 = 16'h2653; // ~0.6 V
  localparam [15:0] VREF_1V2 = 16'h4CCE; // ~1.2 V
  localparam [15:0] VREF_1V8 = 16'h733A; // ~1.8 V
  localparam [15:0] V_FC_REF = 16'h6990;

  localparam integer STEP_CYCLES = 1000000;

  // ---------------------------------------------------------------------------
  // 4. ADC Data Acquisition Logic
  // ---------------------------------------------------------------------------

  // Simple channel sequencer: 7 -> 14 -> 15 -> 7
  always @* begin
    case (ch_idx_q)
      2'd0:    adc_channel_addr = 7'h17; // Ch 7
      2'd1:    adc_channel_addr = 7'h1E; // Ch 14
      2'd2:    adc_channel_addr = 7'h1F; // Ch 15
      default: adc_channel_addr = 7'h17;
    endcase
  end

  // Capture data on data ready (drdy)
  // Note: Original code had edge detection on drdy.
  // Assuming simple synchronous capture here for clarity.
  always @(posedge clk_100m or negedge rst_ni) begin
    if (!rst_ni) begin
      v_meas_ch7_q  <= 16'd0;
      v_meas_ch14_q <= 16'd0;
      v_meas_ch15_q <= 16'd0;
      ch_idx_q      <= 2'd0;
    end else begin
      if (adc_drdy) begin
        case (ch_idx_q)
          2'd0: v_meas_ch7_q  <= adc_data_out;
          2'd1: v_meas_ch14_q <= adc_data_out;
          2'd2: v_meas_ch15_q <= adc_data_out;
        endcase

        // Advance channel index
        if (ch_idx_q == 2'd2)
          ch_idx_q <= 2'd0;
        else
          ch_idx_q <= ch_idx_q + 1;
      end
    end
  end

  // Calculate System Voltages
  always @(posedge clk_100m or negedge rst_ni) begin
    if (!rst_ni) begin
      v_out_meas <= 16'd0;
      v_fc_calc  <= 16'd0;
    end else begin
      v_out_meas <= v_meas_ch14_q;

      if (v_meas_ch7_q >= v_meas_ch15_q)
        v_fc_calc <= v_meas_ch7_q - v_meas_ch15_q;
      else
        v_fc_calc <= 16'd0;
    end
  end

  // ---------------------------------------------------------------------------
  // 5. Reference Sequencer (Soft Start FSM)
  // ---------------------------------------------------------------------------
  always @(posedge clk_100m or negedge rst_ni) begin
    if (!rst_ni) begin
      tick_cnt_q  <= 0;
      seq_idx_q   <= 0;
      seq_dir_q   <= 1'b1; // Start moving UP
      v_out_ref_q <= VREF_0V0;
    end else begin
      if (tick_cnt_q == STEP_CYCLES - 1) begin
        tick_cnt_q <= 0;

        // Update Voltage Reference based on Index
        case (seq_idx_q)
          3'd0:    v_out_ref_q <= VREF_0V0;
          3'd1:    v_out_ref_q <= VREF_0V6;
          3'd2:    v_out_ref_q <= VREF_1V2;
          3'd3:    v_out_ref_q <= VREF_1V8;
          // default: v_out_ref_q <= VREF_0V0;
        endcase

        // Update Index State
        if (seq_dir_q) begin // Going Up
          if (seq_idx_q == 3'd3) begin
            seq_dir_q <= 1'b0;
            seq_idx_q <= 3'd2;
          end else begin
            seq_idx_q <= seq_idx_q + 3'd1;
          end
        end else begin // Going Down
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

  // TODO: Create/Instantiate ADC Lushay/Gowin Wrapper
  // For now, signals are unconnected or driven to 0 to prevent synthesis error
  assign adc_eoc      = 1'b0; // Temporary
  assign adc_drdy     = 1'b0; // Temporary
  assign adc_data_out = 16'd0; // Temporary

  // Timer Control
  timer_control u_timer_ctrl (
    .clk_i     (clk_100m),
    .rst_ni    (rst_ni),
    .eoc_i     (adc_eoc),
    .trigger_o (adc_start_conv)
  );

  // Control Algorithm (MATLAB Generated)
  // Mapping refactored names to original generated port names
  fcc_fixpt u_controller (
    .clk        (clk_100m),
    .reset      (~rst_ni),       // Active high reset for generated code
    .clk_enable (1'b1),
    .Voutref    (v_out_ref_q),
    .Vout       (v_out_meas),
    .Vfcref     (V_FC_REF),
    .Vfc        (v_fc_calc),
    .D1         (duty_d1),
    .D2         (duty_d2),
    // Unused outputs
    .ce_out     (),
    .ui         (),
    .uv         ()
  );

  // PS-PWM Modulator
  wire [3:0] pwm_signals;

  ps_pwm u_modulator (
    .clk_i         (clk_100m),
    .rst_ni        (rst_ni),
    .duty_d1_i     (duty_d1),
    .duty_d2_i     (duty_d2),
    .adc_trigger_o (),            // FIXME:Currently unconnected (tie to ADC wrapper later)
    .pwm_o         (pwm_signals)
  );

  // ---------------------------------------------------------------------------
  // 7. Output Assignments
  // ---------------------------------------------------------------------------
  // Mapping internal PWM signals to output ports
  // Bits 0-3 are PWM, 4-7 are debug/static based on original code
  assign pwm_o[3:0] = pwm_signals;
  assign pwm_o[4]   = 1'b1;
  assign pwm_o[5]   = 1'b1;
  assign pwm_o[6]   = 1'b0;
  assign pwm_o[7]   = 1'b0;

endmodule
