`default_nettype none

module adc #(
    parameter integer address = 7'd72
) (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Configuration
    // 3-bit MUX code from Datasheet:
    // 000 : AINP=AIN0, AINN=AIN1 (Differential Vfc)
    // 100 : AINP=AIN0, AINN=GND  (Single-Ended Vout)
    input  wire [2:0]  mux_config_i,

    input  wire        enable_i,        // Start Conversion
    output reg  [15:0] data_o,
    output reg         data_ready_o,

    // I2C Interface connections
    output reg  [1:0]  i2c_instruction_o,
    output reg         i2c_enable_o,
    output reg  [7:0]  i2c_byte_to_send_o,
    input  wire [7:0]  i2c_byte_received_i,
    input  wire        i2c_complete_i
);

    // Config Register Template
    // We only store the static parts here. The dynamic parts (OS and MUX)
    // are injected during the state machine execution.
    // [15] OS = 1 (Start)
    // [14:12] MUX = DYNAMIC
    // [11:9] PGA = 001 (+/- 4.096V)
    // [8] MODE = 1 (Single-Shot)
    // [7:0] Data Rate, Comp, etc. = 0x83 (128SPS, Disable Comp)

    localparam CONFIG_MSB_TEMPLATE = 5'b1_000_1; // OS(1) + Placeholder(000) + PGA_High(1)
    localparam CONFIG_LSB_DEFAULT  = 8'b1000_0011; // PGA_Low(00) + Mode(1) + DR(100) + Comp(00011)

    // Constants
    localparam CONFIG_REGISTER     = 8'b00000001;
    localparam CONVERSION_REGISTER = 8'b00000000;

    localparam TASK_SETUP       = 0;
    localparam TASK_CHECK_DONE  = 1;
    localparam TASK_CHANGE_REG  = 2;
    localparam TASK_READ_VALUE  = 3;

    localparam INST_START_TX    = 0;
    localparam INST_STOP_TX     = 1;
    localparam INST_READ_BYTE   = 2;
    localparam INST_WRITE_BYTE  = 3;

    localparam STATE_IDLE           = 0;
    localparam STATE_RUN_TASK       = 1;
    localparam STATE_WAIT_FOR_I2C   = 2;
    localparam STATE_INC_SUB_TASK   = 3;
    localparam STATE_DONE           = 4;
    localparam STATE_DELAY          = 5;

    reg [1:0] taskIndex;
    reg [2:0] subTaskIndex;
    reg [4:0] state;
    reg [7:0] counter;
    reg       processStarted;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= STATE_IDLE;
            data_ready_o <= 0;
            data_o <= 0;
            i2c_enable_o <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (enable_i) begin
                        state <= STATE_RUN_TASK;
                        taskIndex <= 0;
                        subTaskIndex <= 0;
                        data_ready_o <= 0;
                        counter <= 0;
                    end
                end

                STATE_RUN_TASK: begin
                    case ({taskIndex, subTaskIndex})
                        // 1. Send START Condition
                        {TASK_SETUP, 3'd0},
                        {TASK_CHECK_DONE, 3'd1},
                        {TASK_CHANGE_REG, 3'd1},
                        {TASK_READ_VALUE, 3'd0}: begin
                            i2c_instruction_o <= INST_START_TX;
                            i2c_enable_o <= 1;
                            state <= STATE_WAIT_FOR_I2C;
                        end

                        // 2. Send Address + Write (or Read)
                        {TASK_SETUP, 3'd1},
                        {TASK_CHANGE_REG, 3'd2},
                        {TASK_CHECK_DONE, 3'd2},
                        {TASK_READ_VALUE, 3'd1}: begin
                            i2c_instruction_o <= INST_WRITE_BYTE;
                            i2c_byte_to_send_o <= {
                                address,
                                (taskIndex == TASK_CHECK_DONE || taskIndex == TASK_READ_VALUE)
                                ? 1'b1 : 1'b0
                            };
                            i2c_enable_o <= 1;
                            state <= STATE_WAIT_FOR_I2C;
                        end

                        // 3. Send STOP Condition
                        {TASK_SETUP, 3'd5},
                        {TASK_CHECK_DONE, 3'd5},
                        {TASK_CHANGE_REG, 3'd4},
                        {TASK_READ_VALUE, 3'd5}: begin
                            i2c_instruction_o <= INST_STOP_TX;
                            i2c_enable_o <= 1;
                            state <= STATE_WAIT_FOR_I2C;
                        end

                        // 4. Select Register (Config or Conversion)
                        {TASK_SETUP, 3'd2},
                        {TASK_CHANGE_REG, 3'd3}: begin
                            i2c_instruction_o <= INST_WRITE_BYTE;
                            i2c_byte_to_send_o <= (taskIndex == TASK_SETUP)
                            ? CONFIG_REGISTER : CONVERSION_REGISTER;
                            i2c_enable_o <= 1;
                            state <= STATE_WAIT_FOR_I2C;
                        end

                        // 5. Write Config MSB
                        {TASK_SETUP, 3'd3}: begin
                            i2c_instruction_o <= INST_WRITE_BYTE;
                            // [15]=1 (Start), [14:12]=mux_config_i, [11:8]=PGA/Mode
                            i2c_byte_to_send_o <= {1'b1, mux_config_i, 4'b0011};
                            i2c_enable_o <= 1;
                            state <= STATE_WAIT_FOR_I2C;
                        end

                        // 6. Write Config LSB
                        {TASK_SETUP, 3'd4}: begin
                            i2c_instruction_o <= INST_WRITE_BYTE;
                            i2c_byte_to_send_o <= CONFIG_LSB_DEFAULT;
                            i2c_enable_o <= 1;
                            state <= STATE_WAIT_FOR_I2C;
                        end

                        {TASK_CHECK_DONE, 3'd0}: state <= STATE_DELAY;

                        {TASK_CHECK_DONE, 3'd3},
                        {TASK_READ_VALUE, 3'd2}: begin
                            i2c_instruction_o <= INST_READ_BYTE;
                            i2c_enable_o <= 1;
                            state <= STATE_WAIT_FOR_I2C;
                        end

                        {TASK_CHECK_DONE, 3'd4},
                        {TASK_READ_VALUE, 3'd3}: begin
                            i2c_instruction_o <= INST_READ_BYTE;
                            data_o[15:8] <= i2c_byte_received_i; // Capture MSB
                            i2c_enable_o <= 1;
                            state <= STATE_WAIT_FOR_I2C;
                        end

                        {TASK_CHANGE_REG, 3'd0}: begin
                            // Check MSB of Config Register to see if conversion is done
                            if (data_o[15]) state <= STATE_INC_SUB_TASK;
                            else begin
                                subTaskIndex <= 0;
                                taskIndex <= TASK_CHECK_DONE;
                            end
                        end

                        {TASK_READ_VALUE, 3'd4}: begin
                            state <= STATE_INC_SUB_TASK;
                            data_o[7:0] <= i2c_byte_received_i; // Capture LSB
                        end

                        default: state <= STATE_INC_SUB_TASK;
                    endcase
                end

                STATE_WAIT_FOR_I2C: begin
                    if (~processStarted && ~i2c_complete_i)
                        processStarted <= 1;
                    else if (i2c_complete_i && processStarted) begin
                        state <= STATE_INC_SUB_TASK;
                        processStarted <= 0;
                        i2c_enable_o <= 0;
                    end
                end

                STATE_INC_SUB_TASK: begin
                    state <= STATE_RUN_TASK;
                    if (subTaskIndex == 3'd5) begin
                        subTaskIndex <= 0;
                        if (taskIndex == TASK_READ_VALUE) state <= STATE_DONE;
                        else taskIndex <= taskIndex + 1;
                    end else begin
                        subTaskIndex <= subTaskIndex + 1;
                    end
                end

                STATE_DELAY: begin
                    counter <= counter + 1;
                    if (counter == 8'b11111111) state <= STATE_INC_SUB_TASK;
                end

                STATE_DONE: begin
                    data_ready_o <= 1;
                    if (~enable_i) state <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule
