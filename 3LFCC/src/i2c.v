`timescale 1ns / 1ps

module i2c #(
    parameter integer DividerWidth = 7  // 7 bits @ 27MHz = ~210kHz
) (
    input  wire       clk_i,
    input  wire       rst_ni,           // Active-Low Reset

    // I2C Physical Signals
    input  wire       sda_i,            // SDA Input
    output reg        sda_o,            // SDA Output
    output reg        scl_o,            // SCL Output

    // Control Interface
    input  wire [1:0] instruction_i,    // 00=Start, 01=Stop, 10=Read, 11=Write
    input  wire       enable_i,         // Pulse to start command
    input  wire [7:0] byte_to_send_i,   // Data to write
    output reg  [7:0] byte_received_o,  // Data read
    output reg        complete_o,       // Command done pulse
    output reg        is_sending_o      // Busy status
);

    // State Encoding
    localparam INST_START_TX   = 0;
    localparam INST_STOP_TX    = 1;
    localparam INST_READ_BYTE  = 2;
    localparam INST_WRITE_BYTE = 3;
    localparam STATE_IDLE      = 4;
    localparam STATE_DONE      = 5;
    localparam STATE_SEND_ACK  = 6;
    localparam STATE_RCV_ACK   = 7;

    // Registers
    reg [DividerWidth-1:0] clk_div_q;
    reg [2:0]              state_q;
    reg [2:0]              bit_cnt_q;

    // Helper: Extract phase from top 2 bits of divider
    // 00 = Low, 01 = Rising, 10 = High, 11 = Falling
    wire [1:0] phase = clk_div_q[DividerWidth-1:DividerWidth-2];

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q         <= STATE_IDLE;
            clk_div_q       <= 0;
            bit_cnt_q       <= 0;
            scl_o           <= 1'b1;
            sda_o           <= 1'b1;
            is_sending_o    <= 1'b0;
            complete_o      <= 1'b0;
            byte_received_o <= 8'd0;
        end else begin
            case (state_q)
                STATE_IDLE: begin
                    if (enable_i) begin
                        complete_o   <= 0;
                        clk_div_q    <= 0;
                        bit_cnt_q    <= 0;
                        state_q      <= {1'b0, instruction_i};
                    end
                end

                INST_START_TX: begin
                    is_sending_o <= 1;
                    clk_div_q    <= clk_div_q + 1;

                    if (phase == 2'b00) begin
                        scl_o <= 1;
                        sda_o <= 1;
                    end else if (phase == 2'b01) begin
                        sda_o <= 0; // SDA falls while SCL High -> START
                    end else if (phase == 2'b10) begin
                        scl_o <= 0;
                    end else if (phase == 2'b11) begin
                        state_q <= STATE_DONE;
                    end
                end

                INST_STOP_TX: begin
                    is_sending_o <= 1;
                    clk_div_q    <= clk_div_q + 1;

                    if (phase == 2'b00) begin
                        scl_o <= 0;
                        sda_o <= 0;
                    end else if (phase == 2'b01) begin
                        scl_o <= 1;
                    end else if (phase == 2'b10) begin
                        sda_o <= 1; // SDA rises while SCL High -> STOP
                    end else if (phase == 2'b11) begin
                        state_q <= STATE_DONE;
                    end
                end

                INST_READ_BYTE: begin
                    is_sending_o <= 0;
                    clk_div_q    <= clk_div_q + 1;

                    if (phase == 2'b00) begin
                        scl_o <= 0;
                    end else if (phase == 2'b01) begin
                        scl_o <= 1;
                    end else if (clk_div_q == {1'b1, {(DividerWidth-1){1'b0}}}) begin 
                        // Exact Middle of High Period (MSB=1, rest=0)
                        byte_received_o <= {byte_received_o[6:0], sda_i ? 1'b1 : 1'b0};
                    end else if (clk_div_q == {DividerWidth{1'b1}}) begin 
                        // End of cycle
                        bit_cnt_q <= bit_cnt_q + 1;
                        if (bit_cnt_q == 3'b111) begin
                            state_q <= STATE_SEND_ACK;
                        end
                    end else if (phase == 2'b11) begin 
                         scl_o <= 0;
                    end
                end

                STATE_SEND_ACK: begin
                    is_sending_o <= 1;
                    sda_o        <= 0; // Send ACK (Low)
                    clk_div_q    <= clk_div_q + 1;

                    if (phase == 2'b01) begin
                        scl_o <= 1;
                    end else if (clk_div_q == {DividerWidth{1'b1}}) begin
                        state_q <= STATE_DONE;
                    end else if (phase == 2'b11) begin
                        scl_o <= 0;
                    end
                end

                INST_WRITE_BYTE: begin
                    is_sending_o <= 1;
                    clk_div_q    <= clk_div_q + 1;
                    sda_o        <= byte_to_send_i[3'd7 - bit_cnt_q];

                    if (phase == 2'b00) begin
                        scl_o <= 0;
                    end else if (phase == 2'b01) begin
                        scl_o <= 1;
                    end else if (clk_div_q == {DividerWidth{1'b1}}) begin
                        bit_cnt_q <= bit_cnt_q + 1;
                        if (bit_cnt_q == 3'b111) begin
                            state_q <= STATE_RCV_ACK;
                        end
                    end else if (phase == 2'b11) begin
                        scl_o <= 0;
                    end
                end

                STATE_RCV_ACK: begin
                    is_sending_o <= 0;
                    clk_div_q    <= clk_div_q + 1;

                    if (phase == 2'b01) begin
                        scl_o <= 1;
                    end else if (clk_div_q == {DividerWidth{1'b1}}) begin
                        state_q <= STATE_DONE;
                    end else if (phase == 2'b11) begin
                        scl_o <= 0;
                    end
                end

                STATE_DONE: begin
                    complete_o <= 1;
                    // Auto-return to IDLE if enable is dropped, or wait for it to drop
                    if (!enable_i) state_q <= STATE_IDLE;
                end
            endcase
        end
    end

endmodule