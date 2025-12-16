module counterM(
    input clk,
    output reg [7:0] counterValue = 0,
);
    reg [32:0] clockCounter = 0;

    localparam WAIT_TIME = 1000000;

    always @(posedge clk) begin
        if (clockCounter == WAIT_TIME) begin
            clockCounter <= 0;
            counterValue <= counterValue + 1;
        end
        else
            clockCounter <= clockCounter + 1;
    end
endmodule