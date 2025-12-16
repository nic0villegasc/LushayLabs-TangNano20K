`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/01/2025 10:05:04 PM
// Design Name: 
// Module Name: PS_PWM
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


module PS_PWM(

    input clk,        // Reloj principal 
    input RST,            // senal de reset SW
    
    input [6:0] d1,       // ciclo de trabajo 1 que viene del controlador // Conexion interna
    input [6:0] d2,       // ciclo de trabajo 2 que viene del controlador  // Conexion interna
    
    output wire XADC_Event,
    output wire [3:0] JE
);

reg [4:0] dt= 5'd2; 
/**************** ETAPA DE SHIFT REGISTER ****************/
//wire CLK_SELECTOR;
//wire [4:0] dt;
//wire [2:0]OUTPUT_SELECTOR_EXTERNAL;
//wire ENABLE_OUTPUT;

//Shift_Register Shift_Register_Inst(
//    CLK_SR,
//    RST,
//    Data_SR,
//    {ENABLE_OUTPUT, CLK_SELECTOR, OUTPUT_SELECTOR_EXTERNAL[2], OUTPUT_SELECTOR_EXTERNAL[1], OUTPUT_SELECTOR_EXTERNAL[0], dt[4], dt[3], dt[2], dt[1], dt[0]}
//);


// ila_shift_regitster your_instance_name (
// 	.clk(CLK_PRIMARY), // input wire clk


// 	.probe0(CLK_SR), // input wire [0:0]  probe0  
// 	.probe1({ENABLE_OUTPUT, CLK_SELECTOR, OUTPUT_SELECTOR_EXTERNAL[2], OUTPUT_SELECTOR_EXTERNAL[1], OUTPUT_SELECTOR_EXTERNAL[0], dt[4], dt[3], dt[2], dt[1], dt[0]}), // input wire [9:0]  probe1 
// 	.probe2(RST), // input wire [0:0]  probe2
//     .probe3(d1), // input wire [6:0]  probe3 
// 	.probe4(d2) // input wire [6:0]  probe4
// );



// El orden para meter los datos es (de primero a ultimo): 
// dt[0]
// dt[1]
// dt[2]
// dt[3]
// dt[4]
// OUTPUT_SELECTOR_EXTERNAL[0]
// OUTPUT_SELECTOR_EXTERNAL[1]
// OUTPUT_SELECTOR_EXTERNAL[2]
// CLK_SELECTOR
// ENABLE_OUTPUT

///**************** ETAPA DE MUX CLK ****************/

//wire clk;

//// Selecci?n de reloj: CLK_SELECTOR = 1 selecciona CLK_SECONDARY (externo), CLK_SELECTOR = 0 selecciona CLK_PRIMARY (PLL)
//assign clk = CLK_SELECTOR ? CLK_SECONDARY : CLK_PRIMARY;


/**************** ETAPA DE TRIANGULARES ****************/

wire [6:0] triangular_0;
Signal_Generator_0phase Signal_Generator_1_0phase_inst(
    clk,
    RST,
    XADC_Event,
    triangular_0
);

wire [6:0] triangular_180;
Signal_Generator_180phase Signal_Generator_1_180phase_inst(
    clk,
    RST,
    triangular_180
);

/**************** ETAPA DE COMPARACION ****************/

wire Output_Comparison_1;
Comparator Comparator_Inst_1(
    d1,
    triangular_0,
    Output_Comparison_1
);

wire Output_Comparison_2;
Comparator Comparator_Inst_2(
    d2,
    triangular_180,
    Output_Comparison_2
);

/**************** ETAPA DE DEAD-TIME GENERATOR ****************/

wire pmos1_prev; 
Dead_Time_Generator Dead_Time_Generator_inst_1(
    clk,
    dt,
    Output_Comparison_1,
    pmos1_prev
);

wire Not_Output_Comparison_1;
wire nmos2_prev;
assign Not_Output_Comparison_1 = ~Output_Comparison_1;
Dead_Time_Generator Dead_Time_Generator_inst_2(
    clk,
    dt,
    Not_Output_Comparison_1,
    nmos2_prev
);

wire pmos2_prev;
Dead_Time_Generator Dead_Time_Generator_inst_3(
    clk,
    dt,
    Output_Comparison_2,
    pmos2_prev
);

wire Not_Output_Comparison_2;
wire nmos1_prev;
assign Not_Output_Comparison_2 = ~Output_Comparison_2;
Dead_Time_Generator Dead_Time_Generator_inst_4(
    clk,
    dt,
    Not_Output_Comparison_2,
    nmos1_prev
);

/**************** ETAPA RESET ****************/

assign JE[0] = RST ? 1 : ~pmos1_prev;
assign JE[1] = RST ? 1 : ~pmos2_prev;
assign JE[2] = RST ? 0 : nmos1_prev;
assign JE[3] = RST ? 0 : nmos2_prev;

endmodule