## Assignment

This lab is essentially identical to [lab-03](../lab-03/ASSIGNMENT.md) - print a
string on Tera Term once per second and blink the on-board LED. The Zig BSP
already drove the UART and LED through direct register manipulation (no STM32
HAL), so the only material difference in lab-05 is that the lab now configures
the system clock to 32 MHz instead of running on the HSI16 reset default.

The Zig translation deviates from item 4 of the original assignment: GPIO
initialization is *not* embedded inside the clock-config function. Mixing
RCC/PLL bring-up with board-level GPIO setup is a layering violation that
makes the clock module unusable from any other lab. Here, `clock.zig` exposes
a reusable `Config` (currently `.hsi16` and `.pll_32mhz`) and the LED bring-up
stays where it belongs in `hardware.init`. Both halves remain register-level
register manipulations, which is the spirit of the assignment requirement.

The original assignment was this:

Project:

1. Develop this module's code base on the previous module. Use your version of UART initialization function in this module. (5%)
2. Create a user defined "USR_SystemClock_Config()" function to configure the RCC module with registers to setup HCLK and PCLK to be 32MHz, and replace the automatic generated one. Make sure you review the lecture and follow the configuration sequence. (25%)
3. Verify this function works by printing a string of text of your choice on Tera Term. (20%)
4. Add GPIO initialization code in the "USR_SystemClock_Config()" function to initialize the LED pin, with registers manipulation. (25%)
5. Blink the onboard LED in the main() with 1s interval, by manipulating registers. You can still use HAL_Delay() function. (20%)
6. Make a commit to your project at this point, make sure it includes all the changes. (5%)

Please submit your project the same way as Module 4.

On the demo day, please show the source code to TA, as well as explain all the registers involved in configurating the clock and the GPIO.
