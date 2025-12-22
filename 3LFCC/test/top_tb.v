`timescale 1ns / 1ps

module test();
    // System Signals
    reg clk_i = 0;
    reg rst_ni = 0;
    reg btn1 = 1;

    // Bus Interfaces
    wire scl_1, sda_1;
    wire scl_2, sda_2;
    wire [7:0] pwm_o;

    // 27 MHz Clock Generation
    always #18.5 clk_i = ~clk_i;

    // --- Device Under Test (DUT) ---
    top dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .scl_1_o(scl_1),
        .sda_1_io(sda_1),
        .scl_2_o(scl_2),
        .sda_2_io(sda_2),
        .pwm_o(pwm_o),
        .btn1(btn1)
    );

    // --- Mock ADS1115 I2C Slaves ---
    // Channel 1: Flying Cap Voltage (V_FC_REF is 16'h6990) [cite: 45]
    ads1115_model #(.SLAVE_ADDR(7'b1001001), .MOCK_VAL(16'h6990)) adc_fc (
        .scl(scl_1), .sda(sda_1)
    );

    // Channel 2: Vout (Targeting 1.2V which is 16'h4CCE) [cite: 44]
    ads1115_model #(.SLAVE_ADDR(7'b1001001), .MOCK_VAL(16'h4CCE)) adc_vout (
        .scl(scl_2), .sda(sda_2)
    );

    initial begin
        $dumpfile("3LFCC.vcd");
        $dumpvars(0, test);

        // System Startup
        #100 rst_ni = 1;
        #1000 btn1 = 0; // Trigger conversion via button
        #1000 btn1 = 1;

        // Note: The ADC module performs 4 tasks (Setup, Check, Change, Read) [cite: 144]
        // Each task involves multiple I2C transactions. Simulation needs time.
        #500000; 

        if (pwm_o[3:0] != 4'b0000)
            $display("Success: PWM activity detected after ADC conversion cycle.");
        else
            $display("Warning: No PWM activity. Check if ADC state machine is hanging.");
            
        $finish;
    end
endmodule

// --- ADS1115 Behavioral Model ---
module ads1115_model #(
    parameter [6:0]  SLAVE_ADDR = 7'b1001001,
    parameter [15:0] MOCK_VAL   = 16'h1234
) (
    input  wire scl,
    inout  wire sda
);

    // FSM States
    localparam STATE_IDLE      = 3'd0;
    localparam STATE_ADDR      = 3'd1;
    localparam STATE_ACK_ADDR  = 3'd2;
    localparam STATE_READ_DATA = 3'd3;
    localparam STATE_ACK_DATA  = 3'd4;

    reg [2:0]  state = STATE_IDLE;
    reg [3:0]  bit_cnt = 0;
    reg [7:0]  shift_reg = 0;
    reg [15:0] data_to_send = MOCK_VAL;
    reg        byte_sel = 0; // 0 for MSB, 1 for LSB
    reg        sda_out = 1'b1;

    // Tristate control: Drive 0 if sda_out is 0, otherwise release to High-Z
    assign sda = (sda_out == 1'b0) ? 1'b0 : 1'bz;

    // Detect Start Condition (SDA falls while SCL is high)
    always @(negedge sda) begin
        if (scl) begin
            state <= STATE_ADDR;
            bit_cnt <= 0;
            sda_out <= 1'b1;
        end
    end

    // Detect Stop Condition (SDA rises while SCL is high)
    always @(posedge sda) begin
        if (scl) state <= STATE_IDLE;
    end

    // Main State Machine on SCL edges
    always @(posedge scl) begin
        case (state)
            STATE_ADDR: begin
                shift_reg <= {shift_reg[6:0], sda};
            end
            STATE_READ_DATA: begin
                // Master is sampling here, we prepare next bit on negedge
            end
        endcase
    end

    always @(negedge scl) begin
        case (state)
            STATE_ADDR: begin
                if (bit_cnt == 7) begin
                    // Check if address matches and it's a READ (LSB = 1)
                    if (shift_reg[7:1] == SLAVE_ADDR) begin
                        state <= STATE_ACK_ADDR;
                        sda_out <= 1'b0; // Send ACK
                    end else begin
                        state <= STATE_IDLE;
                    end
                    bit_cnt <= 0;
                end else begin
                    bit_cnt <= bit_cnt + 1;
                end
            end

            STATE_ACK_ADDR: begin
                state <= STATE_READ_DATA;
                // Load MSB or LSB based on byte_sel
                shift_reg <= byte_sel ? data_to_send[7:0] : data_to_send[15:8];
                sda_out <= shift_reg[7]; 
                bit_cnt <= 0;
            end

            STATE_READ_DATA: begin
                if (bit_cnt == 7) begin
                    state <= STATE_ACK_DATA;
                    sda_out <= 1'b1; // Release for Master ACK/NACK
                end else begin
                    sda_out <= shift_reg[6-bit_cnt];
                    bit_cnt <= bit_cnt + 1;
                end
            end

            STATE_ACK_DATA: begin
                // Master pulls SDA low for ACK if it wants more data
                byte_sel <= ~byte_sel; // Toggle between MSB and LSB
                state <= STATE_ADDR; // Simplified: wait for next transaction/start
            end
        endcase
    end
endmodule