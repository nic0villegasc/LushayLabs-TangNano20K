`timescale 1ns / 1ps
/* verilator lint_off DECLFILENAME */
module test;
/* verilator lint_on DECLFILENAME */
  // ---------------------------------------------------------------------------
  // 1. Signal Declarations
  // ---------------------------------------------------------------------------
  reg        clk_125m;
  reg        rst_user;  // Simulates the physical button (Active High)
  
  // Analog inputs (Simulated as static for now)
  reg        vauxp7, vauxn7;
  reg        vauxp14, vauxn14;
  reg        vauxp15, vauxn15;
  reg        sw0, sw1;

  // Outputs
  wire [7:0] pwm_out;

  // ---------------------------------------------------------------------------
  // 2. Unit Under Test (UUT) Instantiation
  // ---------------------------------------------------------------------------
  top uut (
    .clk_i (clk_125m),
    .rst_i      (rst_user),    // Active High input
    
    // Analog inputs (tied to 0 for basic connectivity check)
    .vauxp7_i   (vauxp7),
    .vauxn7_i   (vauxn7),
    .vauxp14_i  (vauxp14),
    .vauxn14_i  (vauxn14),
    .vauxp15_i  (vauxp15),
    .vauxn15_i  (vauxn15),
    
    .pwm_o      (pwm_out)
  );

  // ---------------------------------------------------------------------------
  // 3. Clock Generation (125 MHz -> 8 ns period)
  // ---------------------------------------------------------------------------
  initial begin
    clk_125m = 0;
    forever #4 clk_125m = ~clk_125m; // Toggle every 4ns
  end

  // ---------------------------------------------------------------------------
  // 4. Test Stimulus
  // ---------------------------------------------------------------------------
  initial begin
    // Initialize Inputs
    rst_user = 1; // Assert Reset (Active High button)
    vauxp7 = 0; vauxn7 = 0;
    vauxp14 = 0; vauxn14 = 0;
    vauxp15 = 0; vauxn15 = 0;
    sw0 = 0; sw1 = 0;

    // Wait 100 ns for global reset (GSR)
    #100;
    
    $display("Test Started: Applying Reset...");
    
    // Hold Reset for 10 clock cycles
    repeat(10) @(posedge clk_125m);
    
    // Release Reset
    rst_user = 0; 
    $display("Reset Released. Checking for PWM activity...");

    // Run simulation for a bit to observe PWM
    // Note: The Soft-Start sequencer is slow (1M cycles), so we might not 
    // see the reference change in a short sim, but PWM should run immediately.
    repeat(2000) @(posedge clk_125m);

    $display("Simulation Finished. Check waveforms.");
    $finish;
  end

  initial begin
      $dumpfile("adc.vcd");
      $dumpvars(0,test);
  end
endmodule
