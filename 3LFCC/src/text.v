`default_nettype none

module textEngine (
    input clk_i,
    input [9:0] pixel_address_i,
    output [7:0] pixel_data_o,
    output [5:0] char_address_o,
    input [7:0] char_data_i
);
    reg [7:0] fontBuffer [1519:0];
    initial $readmemh("../binaries/font.hex", fontBuffer);

    wire [2:0] columnAddress;
    wire topRow;

    reg [7:0] outputBuffer;
    wire [7:0] chosenChar;

    always @(posedge clk_i) begin
        outputBuffer <= fontBuffer[((chosenChar-8'd32) << 4) + (columnAddress << 1) + (topRow ? 0 : 1)];
    end

    assign char_address_o = {pixel_address_i[9:8],pixel_address_i[6:3]};
    assign columnAddress = pixel_address_i[2:0];
    assign topRow = !pixel_address_i[7];

    assign chosenChar = (char_data_i >= 32 && char_data_i <= 126) ? char_data_i : 32;
    assign pixel_data_o = outputBuffer;
endmodule