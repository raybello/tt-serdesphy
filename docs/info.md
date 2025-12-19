<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The SERDES PHY is a digital Verilog-based module that provides serializer/deserializer physical layer functionality for high-speed data transmission.

![System Overview](./arch.svg)

1. **Parallel-to-Serial Conversion:**  
   The transmitter takes parallel data and converts it to a serial bitstream for transmission over high-speed interfaces.

2. **Serial-to-Parallel Conversion:**  
   The receiver recovers the serial bitstream and converts it back to parallel data format.

3. **Clock Data Recovery (CDR):**  
   The receiver extracts timing information from the incoming serial data to synchronize with the transmitter.

4. **Line Coding and Encoding:**  
   Data is encoded using appropriate line coding schemes (e.g., 8b/10b, NRZ) for reliable transmission.

5. **Equalization and Signal Conditioning:**  
   Signal conditioning circuits compensate for channel impairments and ensure signal integrity.

---

## How to test

1. **Simulation in Verilog Testbench:**  
   - Instantiate the module and provide the system clock.  
   - Observe serialization/deserialization behavior in a simulator (ModelSim, Vivado Simulator, Verilator).  
   - Validate proper data conversion and timing relationships.

2. **Observe Serial Data Output:**  
   - Use a logic analyzer or high-speed oscilloscope to view the serial data waveform.  
   - Verify proper bit timing and data patterns.

3. **Test Parallel Data Interface:**  
   - Apply known parallel data patterns at the transmitter input.  
   - Verify correct recovery at the receiver output.

4. **Clock Domain Testing:**  
   - Test with different clock frequencies and phase relationships.  
   - Verify proper clock data recovery functionality.

5. **Signal Integrity Testing (Optional):**  
   - Test with various channel conditions and impairments.  
   - Verify equalization and error correction performance.

---

## External hardware

Depending on your implementation, the following hardware may be used:

- **High-Speed Transceivers** – Required for serial data transmission and reception.  
- **Clock Generation Circuits** – For providing reference clocks and PLL functionality.  
- **Signal Conditioning Components** – For line driving and impedance matching.  
- **External Test Equipment** – For high-speed signal analysis and validation.  
- **Oscilloscope / Logic Analyzer** – For waveform verification and timing analysis.  
- **Power Supplies** – For providing clean power to high-speed circuits.

Optional FPGA prototyping components:

- **High-Speed PMOD Modules** – For rapid testing of serial interfaces.  
- **JTAG Debug Interfaces** – For real-time monitoring and debugging.

