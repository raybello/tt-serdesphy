<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The Pure Sine Wave Generator is a digital Verilog-based module that produces a clean, stable sine wave output using a combination of lookup tables, PWM modulation, and optional feedback sampling.

1. **Waveform Generation (LUT-Based):**  
   A lookup table stores discrete sine wave values. A phase accumulator or counter steps through the table at a fixed rate. Each output value represents a point on the sine wave.

2. **SPWM Conversion (PWM Modulation):**  
   The digital sine value is compared against a high-frequency triangular or sawtooth carrier signal to generate **Sinusoidal Pulse Width Modulation (SPWM)**.  
   After filtering, this SPWM becomes a smooth analog sine wave.

3. **Clock Domain & Frequency Control:**  
   Sine wave frequency is adjusted by modifying the LUT step size or phase increment. A larger step equals a higher output frequency.

4. **Filtering (External or Digital):**  
   The SPWM output drives power switches, and a low-pass LC filter reconstructs the actual sine waveform.

5. **Optional Voltage Sampling Feedback:**  
   An ADC interface can sample voltage or current for amplitude regulation, overcurrent protection, and closed-loop stability.

---

## How to test

1. **Simulation in Verilog Testbench:**  
   - Instantiate the module and provide the system clock.  
   - Observe LUT output and PWM behavior in a simulator (ModelSim, Vivado Simulator, Verilator).  
   - Validate sine progression and proper duty-cycle modulation.

2. **Observe SPWM Output:**  
   - Use a logic analyzer or oscilloscope to view the PWM waveform.  
   - The duty cycle should vary in a sinusoidal pattern.

3. **Filter & Reconstruct Sine Wave:**  
   - Pass the SPWM through an LC filter or power stage filter.  
   - Verify a clean, low-distortion analog sine wave.

4. **Frequency Change Test:**  
   - Adjust LUT step size or phase increment in the module.  
   - Confirm frequency changes proportionally.

5. **Feedback Regulation (Optional):**  
   - Apply known voltages to the ADC input.  
   - Ensure amplitude regulation and protective actions behave as expected.

---

## External hardware

Depending on your implementation, the following hardware may be used:

- **LC Low-pass Filter** – Required for smoothing SPWM into an analog sine wave.  
- **MOSFET/IGBT H-Bridge Power Stage** – For high-power AC output.  
- **Gate Driver ICs** – For driving high/low-side power switches.  
- **External ADC (optional)** – For voltage or current sampling.  
- **Oscilloscope / Logic Analyzer** – For waveform verification.  
- **DC Power Supply** – Provides the input bus voltage for power stages.

Optional FPGA prototyping components:

- **PMOD DAC/ADC Modules** – For rapid testing and signal visualization.

