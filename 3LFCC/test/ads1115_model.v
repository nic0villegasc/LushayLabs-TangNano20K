`timescale 1ns / 1ps

module ads1115_model #(
    parameter I2C_ADDR = 7'b1001001
)(
    inout wire sda,
    input wire scl,
    input wire [15:0] analog_input
);

    reg [15:0] registers [0:3]; 
    reg [1:0]  addr_pointer = 0;
    
    // Safety Counter to prevent Deadlock
    integer bytes_sent_in_trans = 0;

    initial begin
        registers[0] = 16'h0000; registers[1] = 16'h8583;
        registers[2] = 16'h8000; registers[3] = 16'h7FFF;
    end

    localparam STATE_IDLE = 0, STATE_ADDR = 1, STATE_RW = 2, STATE_ACK_ADDR = 3;
    localparam STATE_DATA_TX = 4, STATE_ACK_TX = 5, STATE_DATA_RX = 6, STATE_ACK_RX = 7;

    reg [3:0] state = STATE_IDLE;
    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;
    reg rw_bit; 
    reg [15:0] temp_reg_val;
    reg first_byte_received; 
    reg sda_out = 1;

    assign sda = (sda_out == 0) ? 1'b0 : 1'bz;

    reg start_det, stop_det;
    always @(negedge sda) if (scl) start_det <= 1;
    always @(posedge sda) if (scl) stop_det <= 1;

    always @(negedge scl or posedge start_det or posedge stop_det) begin
        if (start_det) begin
            state <= STATE_ADDR;
            bit_cnt <= 7;
            start_det <= 0; stop_det <= 0;
            first_byte_received <= 0;
            bytes_sent_in_trans <= 0; // Reset counter
            registers[0] <= analog_input; 
        end 
        else if (stop_det) begin
            state <= STATE_IDLE;
            start_det <= 0; stop_det <= 0;
            sda_out <= 1;
        end 
        else begin
            case (state)
                STATE_ADDR: begin
                    shift_reg <= {shift_reg[6:0], sda};
                    if (bit_cnt == 0) state <= STATE_RW;
                    else bit_cnt <= bit_cnt - 1;
                end
                STATE_RW: begin
                    rw_bit <= sda;
                    if ({shift_reg[6:0]} == I2C_ADDR) begin
                        state <= STATE_ACK_ADDR;
                        sda_out <= 0; 
                    end else state <= STATE_IDLE;
                end
                STATE_ACK_ADDR: begin
                    if (rw_bit) begin 
                        state <= STATE_DATA_TX;
                        bit_cnt <= 7;
                        temp_reg_val <= registers[addr_pointer];
                        sda_out <= registers[addr_pointer][15]; 
                        bytes_sent_in_trans <= 1; // Started 1st byte
                    end else begin
                        state <= STATE_DATA_RX;
                        bit_cnt <= 7;
                        sda_out <= 1; 
                    end
                end
                STATE_DATA_TX: begin
                    temp_reg_val <= {temp_reg_val[14:0], 1'b0};
                    if (bit_cnt == 0) begin
                        state <= STATE_ACK_TX;
                        sda_out <= 1; 
                    end else begin
                        bit_cnt <= bit_cnt - 1;
                        sda_out <= temp_reg_val[14]; 
                    end
                end
                STATE_ACK_TX: begin 
                    // Master ACKs here.
                    state <= STATE_DATA_TX;
                    bit_cnt <= 7;
                    
                    // --- HACK FIX FOR DEADLOCK ---
                    // If we have already sent 2 bytes (MSB+LSB), we assume 
                    // the Master wants to Stop, even if it sent an ACK.
                    // We FORCE release of the bus (Logic 1) so Stop can happen.
                    if (bytes_sent_in_trans >= 2) begin
                        sda_out <= 1; // Don't drive the bus!
                    end else begin
                        sda_out <= temp_reg_val[15]; 
                        bytes_sent_in_trans <= bytes_sent_in_trans + 1;
                    end
                end
                STATE_DATA_RX: begin
                    shift_reg <= {shift_reg[6:0], sda};
                    if (bit_cnt == 0) begin
                        state <= STATE_ACK_RX;
                        sda_out <= 0; 
                    end else bit_cnt <= bit_cnt - 1;
                end
                STATE_ACK_RX: begin
                    sda_out <= 1;
                    if (!first_byte_received) begin
                        addr_pointer <= shift_reg[1:0];
                        first_byte_received <= 1;
                    end else begin
                        registers[addr_pointer] <= {registers[addr_pointer][7:0], shift_reg};
                    end
                    state <= STATE_DATA_RX;
                    bit_cnt <= 7;
                end
            endcase
        end
    end
endmodule