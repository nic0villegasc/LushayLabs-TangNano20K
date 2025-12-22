// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

module adc #(
  parameter [6:0] Address   = 7'd0,
  parameter [2:0] MuxConfig = 3'b000
) (
  input  wire        clk_i,
  input  wire        rst_ni,

  // Application Interface
  input  wire        enable_i,
  output wire [15:0] data_o,
  output wire        data_ready_o,

  // I2C Controller Interface
  output wire [1:0]  i2c_instr_o,
  output wire        i2c_enable_o,
  output wire [7:0]  i2c_byte_o,
  input  wire [7:0]  i2c_byte_i,
  input  wire        i2c_complete_i
);

  // Constants
  localparam [7:0] CONFIG_REGISTER     = 8'h01;
  localparam [7:0] CONVERSION_REGISTER = 8'h00;

  // Task Indices
  localparam [1:0] TASK_SETUP      = 2'd0;
  localparam [1:0] TASK_CHECK_DONE = 2'd1;
  localparam [1:0] TASK_CHANGE_REG = 2'd2;
  localparam [1:0] TASK_READ_VALUE = 2'd3;

  // I2C Instructions
  localparam [1:0] INST_START_TX = 2'd0;
  localparam [1:0] INST_STOP_TX  = 2'd1;
  localparam [1:0] INST_READ_BYTE = 2'd2;
  localparam [1:0] INST_WRITE_BYTE = 2'd3;

  // FSM States
  localparam [2:0] STATE_IDLE         = 3'd0;
  localparam [2:0] STATE_RUN_TASK     = 3'd1;
  localparam [2:0] STATE_WAIT_FOR_I2C = 3'd2;
  localparam [2:0] STATE_INC_SUB_TASK = 3'd3;
  localparam [2:0] STATE_DONE         = 3'd4;
  localparam [2:0] STATE_DELAY        = 3'd5;

  // Internal Signals
  reg [2:0]  state_d, state_q;
  reg [1:0]  task_idx_d, task_idx_q;
  reg [2:0]  sub_task_idx_d, sub_task_idx_q;
  reg [15:0] data_d, data_q;
  reg [7:0]  counter_d, counter_q;
  reg        data_ready_d, data_ready_q;
  reg        process_started_d, process_started_q;
  
  reg [1:0]  i2c_instr_d;
  reg        i2c_enable_d;
  reg [7:0]  i2c_byte_d;

  // Sequential Block for Registers
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q           <= STATE_IDLE;
      task_idx_q        <= TASK_SETUP;
      sub_task_idx_q    <= 3'd0;
      data_q            <= 16'd0;
      counter_q         <= 8'd0;
      data_ready_q      <= 1'b1;
      process_started_q <= 1'b0;
    end else begin
      state_q           <= state_d;
      task_idx_q        <= task_idx_d;
      sub_task_idx_q    <= sub_task_idx_d;
      data_q            <= data_d;
      counter_q         <= counter_d;
      data_ready_q      <= data_ready_d;
      process_started_q <= process_started_d;
    end
  end

  // Combinational Block for Next-State Logic
  always @(*) begin
    // Default assignments to prevent latches
    state_d           = state_q;
    task_idx_d        = task_idx_q;
    sub_task_idx_d    = sub_task_idx_q;
    data_d            = data_q;
    counter_d         = counter_q;
    data_ready_d      = data_ready_q;
    process_started_d = process_started_q;

    i2c_instr_d       = INST_START_TX;
    i2c_enable_d      = 1'b0;
    i2c_byte_d        = 8'd0;

    case (state_q)
      STATE_IDLE: begin
        if (enable_i) begin
          state_d        = STATE_RUN_TASK;
          task_idx_d     = TASK_SETUP;
          sub_task_idx_d = 3'd0;
          data_ready_d   = 1'b0;
          counter_d      = 8'd0;
        end
      end

      STATE_RUN_TASK: begin
        case ({task_idx_q, sub_task_idx_q})
          {TASK_SETUP, 3'd0}, {TASK_CHECK_DONE, 3'd1},
          {TASK_CHANGE_REG, 3'd1}, {TASK_READ_VALUE, 3'd0}: begin
            i2c_instr_d  = INST_START_TX;
            i2c_enable_d = 1'b1;
            state_d      = STATE_WAIT_FOR_I2C;
          end

          {TASK_SETUP, 3'd1}, {TASK_CHANGE_REG, 3'd2},
          {TASK_CHECK_DONE, 3'd2}, {TASK_READ_VALUE, 3'd1}: begin
            i2c_instr_d  = INST_WRITE_BYTE;
            i2c_byte_d   = {Address, (task_idx_q == TASK_CHECK_DONE || 
                                      task_idx_q == TASK_READ_VALUE)};
            i2c_enable_d = 1'b1;
            state_d      = STATE_WAIT_FOR_I2C;
          end

          {TASK_SETUP, 3'd5}, {TASK_CHECK_DONE, 3'd5},
          {TASK_CHANGE_REG, 3'd4}, {TASK_READ_VALUE, 3'd5}: begin
            i2c_instr_d  = INST_STOP_TX;
            i2c_enable_d = 1'b1;
            state_d      = STATE_WAIT_FOR_I2C;
          end

          {TASK_SETUP, 3'd2}, {TASK_CHANGE_REG, 3'd3}: begin
            i2c_instr_d  = INST_WRITE_BYTE;
            i2c_byte_d   = (task_idx_q == TASK_SETUP) ? CONFIG_REGISTER : CONVERSION_REGISTER;
            i2c_enable_d = 1'b1;
            state_d      = STATE_WAIT_FOR_I2C;
          end

          {TASK_SETUP, 3'd3}: begin
            i2c_instr_d  = INST_WRITE_BYTE;
            // Config MSB: OS=1, MuxConfig, PGA=001 (4.096V), Mode=1 (Single-shot)
            i2c_byte_d   = {1'b1, MuxConfig, 3'b001, 1'b1};
            i2c_enable_d = 1'b1;
            state_d      = STATE_WAIT_FOR_I2C;
          end

          {TASK_SETUP, 3'd4}: begin
            i2c_instr_d  = INST_WRITE_BYTE;
            // Config LSB: 128SPS, Trad Comp, Alert Low, Non-latch, Disable Comp (2'b11)
            i2c_byte_d   = 8'b111_0_0_0_11;
            i2c_enable_d = 1'b1;
            state_d      = STATE_WAIT_FOR_I2C;
          end

          {TASK_CHECK_DONE, 3'd0}: begin
            state_d = STATE_DELAY;
          end

          {TASK_CHECK_DONE, 3'd3}, {TASK_READ_VALUE, 3'd2}: begin
            i2c_instr_d  = INST_READ_BYTE;
            i2c_enable_d = 1'b1;
            state_d      = STATE_WAIT_FOR_I2C;
          end

          {TASK_CHECK_DONE, 3'd4}, {TASK_READ_VALUE, 3'd3}: begin
            i2c_instr_d  = INST_READ_BYTE;
            data_d[15:8] = i2c_byte_i;
            i2c_enable_d = 1'b1;
            state_d      = STATE_WAIT_FOR_I2C;
          end

          {TASK_CHANGE_REG, 3'd0}: begin
            if (data_q[15]) begin
              state_d = STATE_INC_SUB_TASK;
            end else begin
              sub_task_idx_d = 3'd0;
              task_idx_d     = TASK_CHECK_DONE;
            end
          end

          {TASK_READ_VALUE, 3'd4}: begin
            data_d[7:0] = i2c_byte_i;
            state_d     = STATE_INC_SUB_TASK;
          end

          default: state_d = STATE_INC_SUB_TASK;
        endcase
      end

      STATE_WAIT_FOR_I2C: begin
        if (!process_started_q && !i2c_complete_i) begin
          process_started_d = 1'b1;
        end else if (i2c_complete_i && process_started_q) begin
          state_d           = STATE_INC_SUB_TASK;
          process_started_d = 1'b0;
        end
      end

      STATE_INC_SUB_TASK: begin
        state_d = STATE_RUN_TASK;
        if (sub_task_idx_q == 3'd5) begin
          sub_task_idx_d = 3'd0;
          if (task_idx_q == TASK_READ_VALUE) begin
            state_d = STATE_DONE;
          end else begin
            task_idx_d = task_idx_q + 1'b1;
          end
        end else begin
          sub_task_idx_d = sub_task_idx_q + 3'd1;
        end
      end

      STATE_DELAY: begin
        counter_d = counter_q + 8'd1;
        if (counter_q == 8'hFF) begin
          state_d = STATE_INC_SUB_TASK;
        end
      end

      STATE_DONE: begin
        data_ready_d = 1'b1;
        if (!enable_i) begin
          state_d = STATE_IDLE;
        end
      end

      default: state_d = STATE_IDLE;
    endcase
  end

  // Output Assignments
  assign data_o         = data_q;
  assign data_ready_o   = data_ready_q;
  assign i2c_instr_o    = i2c_instr_d;
  assign i2c_enable_o   = i2c_enable_d;
  assign i2c_byte_o     = i2c_byte_d;

endmodule