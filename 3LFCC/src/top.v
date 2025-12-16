`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/01/2025 09:49:40 PM
// Design Name: 
// Module Name: Top
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


module top(

    input wire CLK_125MHz,

    input wire SW3_RST, SW0, SW1, // CAMBIAR ESTOS EN EL CONSTRAINT
    
    input vauxp7, vauxn7,   // canal 7
    input vauxp14, vauxn14, // canal 14
    input vauxp15, vauxn15, // canal 15
    
    //output wire eoc_out, trigger_out,
    
    output wire [7:0] JE // d8 d7 d6 d5 d4 d3 d2 d1

    );
    
/*   clk_wiz_0 clk_wiz_inst
  (
    // Clock out ports  
    .clk_out1(CLK_100MHz),
    // Status and control signals               
    .reset(SW3_RST), 
    .locked(locked),
  // Clock in ports
    .clk_in1(CLK_125MHz)
  ); */
    
//------------------------------------------------------
// Señales del XADC
//------------------------------------------------------
wire trigger_out;
wire eoc_out;
wire drdy_out;
wire [15:0] do_out;
wire [4:0] channel_out; // (no usado aquí, pero útil para debug)

// Dirección actual del canal
reg [6:0] daddr = 0;

// Flanco de drdy_out (detección de dato válido)
reg [1:0] drdy_d = 2'b00;
always @(posedge CLK_100MHz)
    drdy_d <= {drdy_d[0], drdy_out};

wire drdy_fall = (drdy_d == 2'b10); // flanco descendente (igual que en la demo)

//------------------------------------------------------
// Variables para almacenar cada canal
//------------------------------------------------------
reg [15:0] data7  = 16'd0;
reg [15:0] data14 = 16'd0;
reg [15:0] data15 = 16'd0;
wire convst_in;
// �?ndice de canal actual
reg [1:0] ch_index = 0;

//------------------------------------------------------
// Instancia del XADC
//------------------------------------------------------
/* xadc_wiz_0 xadc_inst (
    .dclk_in    (CLK_100MHz),
    //.reset_in   (SW3_RST),
    .den_in     (eoc_out),     // inicia nueva conversión tras EOC
    .dwe_in     (1'b0),
    .daddr_in   (daddr),       // canal a convertir (controlado por FSM)
    .di_in      (16'h0000),
    .do_out     (do_out),
    .drdy_out   (drdy_out),
    .eoc_out    (eoc_out),
    .convst_in(convst_in),

    .vauxp7     (vauxp7), .vauxn7(vauxn7),
    .vauxp14    (vauxp14), .vauxn14(vauxn14),
    .vauxp15    (vauxp15), .vauxn15(vauxn15),

    .vp_in      (1'b0),
    .vn_in      (1'b0)
); */

//------------------------------------------------------
// Secuencia de canales (7 ? 14 ? 15 ? ...)
//------------------------------------------------------
always @(*) begin
    case (ch_index)
        2'd0: daddr = 7'h17; // VAUX7
        2'd1: daddr = 7'h1E; // VAUX14
        2'd2: daddr = 7'h1F; // VAUX15
        default: daddr = 7'h17;
    endcase
end

//------------------------------------------------------
// Captura del resultado en cada flanco de DRDY
//------------------------------------------------------
always @(posedge CLK_100MHz) begin
    if (drdy_fall) begin
        case (ch_index)
            2'd0: data7  <= do_out[15:0];
            2'd1: data14 <= do_out[15:0];
            2'd2: data15 <= do_out[15:0];
        endcase
        ch_index <= (ch_index == 2'd2) ? 2'd0 : ch_index + 1;
    end
end

//------------------------------------------------------
// Ejemplo de uso: calcular Vfc = VAUX7 - VAUX15
//------------------------------------------------------
reg [15:0] Vout;
reg [15:0] Vfc;
always @(posedge CLK_100MHz) begin

    Vout <= data14;
    if (data7 >= data15)
        Vfc <= data7 - data15;
    else
        Vfc <= 16'd0;
end

    
    /*********** TIMER CONTROL 6.5us ***********/ 
    //wire trigger_out;
    Timer_Control Timer_Control_inst (
        .clk(CLK_100MHz),
        .rst(SW3_RST),
        .eoc(eoc_out),
        .trigger(trigger_out)
    );
    
    /*********** CONTROL PI ***********/
    wire ap_start;
    wire ap_done;
    wire ap_idle;
    wire ap_ready;
    
    reg ap_start_reg;
    always @(posedge CLK_100MHz) begin
        if (SW3_RST)
            ap_start_reg <= 0;
        else
            ap_start_reg <= trigger_out ;//&& ap_idle;
    end
    assign ap_start = ap_start_reg;

    //reg  [15:0] Voutref;
    reg  [15:0] Vfcref = 16'h6990;

localparam integer STEP_CYCLES = 1_000_000;

// Referencias de voltaje (0 a 1.8 V en pasos de 0.6 V)
localparam [15:0] VREF_0V   = 16'h0000;
localparam [15:0] VREF_0V6  = 16'h2653; // ?0.6 V
localparam [15:0] VREF_1V2  = 16'h4CCE; // ?1.2 V
localparam [15:0] VREF_1V8  = 16'h733A; // ?1.8 V

// ============================================================
// Registros
// ============================================================
reg [20:0] tick = 0;
reg [2:0]  idx  = 0;        // índice 0..3
reg        up_down = 1'b1;  // 1=sube, 0=baja
reg [15:0] Voutref = VREF_0V;

// ============================================================
// Lógica secuencial
// ============================================================
always @(posedge CLK_100MHz or posedge SW3_RST) begin
  if (SW3_RST) begin
    tick     <= 0;
    idx      <= 0;
    up_down  <= 1'b1;
    Voutref  <= VREF_0V;
  end else begin
    if (tick == STEP_CYCLES - 1) begin
      tick <= 0;

      // ====== 1. Mostrar el valor actual ======
      case (idx)
        3'd0: Voutref <= VREF_0V;
        3'd1: Voutref <= VREF_0V6;
        3'd2: Voutref <= VREF_1V2;
        3'd3: Voutref <= VREF_1V8;
        default: Voutref <= VREF_0V;
      endcase

      // ====== 2. Actualizar dirección e índice ======
      if (up_down) begin
        if (idx == 3'd3) begin
          up_down <= 1'b0;  // llegó arriba -> bajar
          idx     <= 3'd2;
        end else begin
          idx <= idx + 3'd1;
        end
      end else begin
        if (idx == 3'd0) begin
          up_down <= 1'b1;  // llegó abajo -> subir
          idx     <= 3'd1;
        end else begin
          idx <= idx - 3'd1;
        end
      end

    end else begin
      tick <= tick + 1'b1;
    end
  end
end

// VERSION DE 0 A 3V CON PASOS DE 0.5V
//localparam integer STEP_CYCLES = 1_000_000;

//localparam [15:0] VREF_0V    = 16'h0000;
//localparam [15:0] VREF_0V75  = 16'h2FFC;
//localparam [15:0] VREF_1V5   = 16'h5FF8;
//localparam [15:0] VREF_2V25  = 16'h8FF4;
//localparam [15:0] VREF_3V0   = 16'hBFF0;

//// ============================================================
//// Registros
//// ============================================================
//reg [20:0] tick = 0;      // cuenta hasta STEP_CYCLES
//reg [2:0]  idx  = 0;      // índice 0..4
//reg        up_down = 1'b1; // 1=sube, 0=baja
//reg [15:0] Voutref = VREF_0V;

//// ============================================================
//// Lógica secuencial
//// ============================================================
//always @(posedge CLK_100MHz or posedge SW3_RST) begin
//  if (SW3_RST) begin
//    tick     <= 0;
//    idx      <= 0;
//    up_down  <= 1'b1;
//    Voutref  <= VREF_0V;
//  end else begin
//    if (tick == STEP_CYCLES - 1) begin
//      tick <= 0;

//      // ====== 1. Mostrar el valor actual ======
//      case (idx)
//        3'd0: Voutref <= VREF_0V;
//        3'd1: Voutref <= VREF_0V75;
//        3'd2: Voutref <= VREF_1V5;
//        3'd3: Voutref <= VREF_2V25;
//        3'd4: Voutref <= VREF_3V0;
//        default: Voutref <= VREF_0V;
//      endcase

//      // ====== 2. Actualizar dirección e índice ======
//      if (up_down) begin
//        if (idx == 3'd4) begin
//          up_down <= 1'b0;       // llegó arriba ? bajar
//          idx     <= 3'd3;       // empieza a bajar un paso
//        end else begin
//          idx <= idx + 3'd1;     // sigue subiendo
//        end
//      end else begin
//        if (idx == 3'd0) begin
//          up_down <= 1'b1;       // llegó abajo ? subir
//          idx     <= 3'd1;       // empieza a subir un paso
//        end else begin
//          idx <= idx - 3'd1;     // sigue bajando
//        end
//      end

//    end else begin
//      tick <= tick + 1'b1;
//    end
//  end
//end

    wire [6:0] D1;
    wire D1_ap_vld;
    wire [6:0] D2;
    wire D2_ap_vld;
    wire [6:0] ui;
    wire ui_ap_vld;
    wire [6:0] uv;
    wire uv_ap_vld;

fcc_fixpt fcc(
    .clk(CLK_100MHz),
    .reset(SW3_RST),
    .Voutref(Voutref),
    .Vout(Vout),
    .Vfcref(Vfcref),
    .Vfc(Vfc),
   .D1(D1),
   .D2(D2),
   .ui(),
   .uv()
);
    
    /*********** Modulacion PS-PWM ***********/ 
    
    wire [3:0] JE_pwm;
    assign JE[3:0] = JE_pwm;  // Bits conectados al modulo
    assign JE[4] = 1'b1;
    assign JE[5] = 1'b1;
    assign JE[6] = 1'b0;
    assign JE[7] = 1'b0;
    
    PS_PWM pwm_inst (
        .clk(CLK_100MHz),
        .RST(SW3_RST),
        .d1(D1),//.d1(7'd70),//.d1(D1),
        .d2(D2),//.d2(7'd70),//.d2(D2),
        .XADC_Event(convst_in),
        .JE(JE_pwm)
    );
endmodule
