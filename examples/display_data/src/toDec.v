module toDec(
    input clk,
    input [7:0] value,
    output reg [7:0] hundreds = "0",
    output reg [7:0] tens = "0",
    output reg [7:0] units = "0"
);
    reg [11:0] digits = 0;
    reg [7:0] cachedValue = 0;
    reg [3:0] stepCounter = 0;
    reg [3:0] state = 0;

    localparam START_STATE = 0;
    localparam ADD3_STATE = 1;
    localparam SHIFT_STATE = 2;
    localparam DONE_STATE = 3;

    always @(posedge clk) begin
        case (state)
            START_STATE: begin
                cachedValue <= value;
                stepCounter <= 0;
                digits <= 0;
                state <= ADD3_STATE;
            end
            ADD3_STATE: begin
                digits <= digits + 
                    ((digits[3:0] >= 5) ? 12'd3 : 12'd0) + 
                    ((digits[7:4] >= 5) ? 12'd48 : 12'd0) + 
                    ((digits[11:8] >= 5) ? 12'd768 : 12'd0);
                state <= SHIFT_STATE;
            end
            SHIFT_STATE: begin
                digits <= {digits[10:0],cachedValue[7]};
                cachedValue <= {cachedValue[6:0],1'b0};
                if (stepCounter == 7)
                    state <= DONE_STATE;
                else begin
                    state <= ADD3_STATE;
                    stepCounter <= stepCounter + 1;
                end
            end
            DONE_STATE: begin
                hundreds <= digits[11:8] + 8'd48;
                tens <= digits[7:4] + 8'd48;
                units <= digits[3:0] + 8'd48;
                state <= START_STATE;
            end
        endcase
    end
endmodule