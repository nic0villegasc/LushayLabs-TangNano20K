`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/01/2025 10:35:51 PM
// Design Name: 
// Module Name: Timer_Control
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module Timer_Control(

    input wire clk,           // Reloj del sistema (100 MHz)
    input wire rst,           // Reset s�ncrono
    input wire eoc,           // Se�al EOC del XADC (pulsos)
    output reg trigger        // Salida: pulso sincronizado con EOC cada 6.5us
);

    localparam integer COUNT_MAX = 750; // 6 us @ 125 MHz

    reg [9:0] counter;
    reg timer_done;
    reg wait_eoc;

    always @(posedge clk) begin
        if (rst) begin
            counter <= 0;
            timer_done <= 0;
            wait_eoc <= 0;
            trigger <= 0;
        end else begin
            trigger <= 0;  // pulso solo de 1 ciclo

            // Conteo de tiempo
            if (!timer_done) begin
                if (counter < COUNT_MAX) begin
                    counter <= counter + 1;
                end else begin
                    timer_done <= 1;
                    wait_eoc <= 1;  // esperar EOC una vez alcanzado tiempo
                end
            end

            // Esperar EOC despu�s de timer_done
            if (wait_eoc && eoc) begin
                trigger <= 1;       // Pulso de trigger
                counter <= 0;       // Reiniciar contador
                timer_done <= 0;
                wait_eoc <= 0;
            end
        end
    end

endmodule
