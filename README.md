# Tang Nano 20K FPGA Examples (Lushay Labs Adaptation)

This repository serves as a collection of Verilog/SystemVerilog examples and projects for the **Sipeed Tang Nano 20K** FPGA development board. 

These projects are adaptations of the [Lushay Labs Tang Nano 9K tutorials](https://learn.lushaylabs.com/), modified to accommodate the specific pinouts, constraints, and logic levels of the 20K variant. The repository covers practical FPGA implementations ranging from basic logic to complex peripheral drivers (I2C, SPI, UART).

## 📂 Repository Structure

* **`docs/`**: Documentation and reference materials, including PDF versions of the original Lushay Labs tutorials and specific notes on the 20K adaptations.
* **`examples/`**: The main source code folders. Each project typically includes `src/`, `test/` (testbenches), `binaries/`, and the critical `.cst` constraint files.

| Project Folder | Description | Key Protocol/Concepts |
| :--- | :--- | :--- |
| **`counter/`** | Basic "Hello World" project. Blinks LEDs by dividing the onboard clock. | Clock Division, Basic Logic |
| **`uart/`** | Serial communication interface. Receives data from a PC and displays binary values. | UART (RX/TX), State Machines |
| **`OLED/`** | Drivers for an external SSD1306 display. Includes text rendering engines and font handling. | SPI (4-wire), Memory Mapping |
| **`display_data/`** | A dashboard integration project. Displays UART text, binary/hex counters, and a progress bar simultaneously. | System Integration, Data Conversion |
| **`adc/`** | Interface for the ADS1115 Analog-to-Digital Converter. | I2C, Micro-Procedures, Bidirectional IO |

## 🛠️ Hardware & Toolchain

### Hardware
* **FPGA:** Sipeed Tang Nano 20K (Gowin GW2A-LV18QN88C8/I7)
* **Display:** 0.96" SSD1306 OLED (SPI)
* **ADC:** ADS1115 (I2C)
* **Host Environment:** Tested on macOS Sequoia (M1 Apple Silicon), but compatible with Linux/Windows.

### Software Prerequisites
The workflow relies on the open-source FPGA toolchain (OSS-CAD-Suite):
1.  **Yosys:** For synthesis.
2.  **NextPnR:** For Place and Route (Gowin version).
3.  **Apicula:** For bitstream generation.
4.  **openFPGALoader:** For flashing the board.
5.  **Visual Studio Code** (Optional): Used with the **Lushay Code** extension for automated build tasks.

## ⚠️ Key Adaptations for Tang Nano 20K

If you are following the original Lushay Labs (9K) tutorials, note the following critical changes implemented in this repo:

1.  **Clock Pin:** The 20K uses **Pin 4** for the 27MHz system clock (unlike Pin 52 on the 9K).
2.  **LED Logic Levels:** The onboard LEDs on the 20K require **3.3V (LVCMOS33)** logic.
    * *Note:* Using the default 1.8V template from 9K tutorials will cause build errors.
3.  **UART Pins:** The physical pins for TX/RX differ from the 9K. Check the `tangnano20k.cst` file in the `uart` folder for the correct mapping.
4.  **Toolchain Config:** The JSON configuration files in each example have been updated to target the `GW2A-18` family.

## 🚀 Usage

### Building a Project (CLI)

(This has not been tested as I used the extension for building the projects)

You can build any project manually using the open-source toolchain. Example for the `counter` project:

```bash
# 1. Synthesize
yosys -p "read_verilog src/top.v; synth_gowin -top top -json counter.json"

# 2. Place and Route (Note the device family GW2A-18)
nextpnr-gowin --json counter.json --write counter_pnr.json --device GW2A-LV18QN88C8/I7 --family GW2A-18 --cst tangnano20k.cst

# 3. Pack Bitstream
gowin_pack -d GW2A-18 -o counter.fs counter_pnr.json

```

### Flashing the Board

```bash
openFPGALoader -b tangnano20k counter.fs

```

### Simulation and Testbenches are located in the `test/` folders. To view waveforms:

```bash
iverilog -o test_output -s testbench_name test/testbench.v src/module.v
vvp test_output
open -a Scave adc.vcd # Or use GTKWave / WaveTrace

```

## 📚 Credits 
* **Original Tutorials:** [Lushay Labs](https://learn.lushaylabs.com/) - An excellent resource for open-source FPGA development.
* **Adaptation:** Adapted for the Tang Nano 20K by Nicolás Villegas.