module textRow #(
    parameter ADDRESS_OFFSET = 8'd0
) (
    input clk,
    input [7:0] readAddress,
    output [7:0] outByte
);
    reg [7:0] textBuffer [15:0];

    assign outByte = textBuffer[(readAddress-ADDRESS_OFFSET)];

    integer i;
    initial begin
        for (i=0; i<15; i=i+1) begin
            textBuffer[i] = 0;
        end
        textBuffer[0] = "L";
        textBuffer[1] = "u";
        textBuffer[2] = "s";
        textBuffer[3] = "h";
        textBuffer[4] = "a";
        textBuffer[5] = "y";
        textBuffer[6] = " ";
        textBuffer[7] = "L";
        textBuffer[8] = "a";
        textBuffer[9] = "b";
        textBuffer[10] = "s";
        textBuffer[11] = "!";
    end
endmodule