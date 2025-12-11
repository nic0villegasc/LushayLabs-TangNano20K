module textEngine (
    input clk,
    input [9:0] pixelAddress,
    output [7:0] pixelData
);
    reg [7:0] fontBuffer [1519:0];
    initial $readmemh("../binaries/font.hex", fontBuffer);

    wire [5:0] charAddress;    
    wire [2:0] columnAddress;    
    wire topRow;    

    reg [7:0] outputBuffer;

    assign charAddress = {pixelAddress[9:8],pixelAddress[6:3]};
    assign columnAddress = pixelAddress[2:0];
    assign topRow = !pixelAddress[7];

    assign pixelData = outputBuffer;

    wire [7:0] charOutput, chosenChar;
    assign chosenChar = (charOutput >= 32 && charOutput <= 126) ? charOutput : 32;

    always @(posedge clk) begin
        outputBuffer <= fontBuffer[((chosenChar-8'd32) << 4) + (columnAddress << 1) + (topRow ? 0 : 1)];
    end

    wire [7:0] charOutput1, charOutput2, charOutput3, charOutput4;

    textRow #(6'd0) t1(
        clk,
        charAddress,
        charOutput1,
    );
    textRow #(6'd16) t2(
        clk,
        charAddress,
        charOutput2
    );
    textRow #(6'd32) t3(
        clk,
        charAddress,
        charOutput3
    );
    textRow #(6'd48) t4(
        clk,
        charAddress,
        charOutput4
    );

    assign charOutput = (charAddress[5] && charAddress[4]) ? charOutput4 : ((charAddress[5]) ? charOutput3 : ((charAddress[4]) ? charOutput2 : charOutput1));
    
endmodule