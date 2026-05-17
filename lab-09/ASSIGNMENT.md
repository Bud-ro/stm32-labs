## Assignment

This lab is the "low-power, parallel" lab: the application is entirely
interrupt-driven and the main loop is just `wfi`. Pressing the
Nucleo's blue button (B1) starts a 10-sample ADC sweep of the
potentiometer on the class shield; DMA streams the conversions into
SRAM without CPU involvement; the DMA Transfer Complete ISR averages
the buffer and prints the equivalent voltage.

Wiring:

- The potentiometer (RV1) feeds the LMV358 op-amp on the shield.
  Output OUT1 reaches PC4 (ADC1_IN17) **only when J8 pins 2-3 are
  shorted** - leave that jumper installed.
- The blue button is the Nucleo-on-board B1, which is hard-wired to
  PC13 and pulls low when pressed.

Register-level configuration (per the assignment text):

- DMA: channel 1 in peripheral-to-memory mode, 16-bit access on both
  sides, MINC=1, TCIE=1; CNDTR = 10. DMAMUX channel 0 routes the ADC
  request line (DMAREQ_ID = 5) to DMA channel 1.
- ADC: regulator -> calibrate -> enable. CFGR1.DMAEN = 1, software
  trigger. CHSELR bit 17 selects channel 17 (PC4). SMPR = 0b111 (max
  sampling time, since the op-amp output isn't a low-impedance source).
- EXTI13: routed to port C in EXTICR4 (port code 2), falling edge,
  unmasked, NVIC EXTI4_15 enabled.

The "use floating number" hint from the spec is satisfied with
fixed-point math - millivolts go through `u32` arithmetic and the
printout reads as `1.234 V`. Software floating point would balloon
code size on Cortex-M0+ for no observable benefit here.

The original assignment was this:

Project

The goal for our practice this week is to build a demonstration
project to explore the parallel processing capability and low-power
feature of our MCU. The project will be interrupt-driven. The main
loop will be fairly empty and most of the application code goes to
interrupt service routines. The MCU stays dormant most of the time.
When the user presses the blue tactile button, the ADC starts
sampling the potentiometer voltage. With the help of the DMA, the
conversion results are stored in the SRAM without using the CPU. Once
10 samples are ready, the CPU calculates the average and displays the
voltage measurement on Tera Term.

1. Create a new project and initialize all the peripherals according
   to the project discussion video. (10%)
2. Initialize the DMA module in register level to move 10 conversion
   results from the data register of ADC to an array. (20%)
3. Initialize the ADC module in register level to sample the
   potentiometer reading, and use the DMA to move the results to the
   array defined in step 2. (20%) [Make sure you short pin 2 & 3 on J8]
4. Write an interrupt service routine to respond to the user button
   press, and start the ADC conversion. (20%)
5. Write an interrupt service routine to handle DMA transfer
   completion event for moving 10 ADC conversion results. Calculate
   the average of the reading, and display corresponding voltage on
   tera term using floating number. (20%)
6. Put the MCU to sleep mode in the while loop in the main function,
   so our application reduces power consumption when it is not
   conducting A/D conversion. (10%)
