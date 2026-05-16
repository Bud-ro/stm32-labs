## Assignment

This lab adds an I2C1 master driver to the BSP and uses it to drive a
TMP102 temperature sensor sitting on a shield board. The shield's J4
connector wires pin 1 (SCL) and pin 2 (SDA) to the TMP102; on the
NUCLEO-G071RB those land on PB8 (SCL, AF6) and PB9 (SDA, AF6), which
are also exposed as Arduino D15/D14.

The application reuses the Lab 04 ring buffer / parser to accept
`START` and `STOP` commands over USART2. `START` kicks off a periodic
one-shot temperature read at 1 Hz; `STOP` halts the periodic reads.
The on-board LED still blinks at 1 Hz throughout. Conversions are
triggered by writing `OS = 1` to the TMP102 configuration register in
shutdown mode (`SD = 1`) - each `OS` write produces exactly one
conversion. A 30 ms one-shot software timer fires after the trigger to
read the result, so the super-loop stays free to drain UART and run
the LED blinker while the sensor settles.

The original assignment was this:

Project

In this module's project, we are going to explore how to use I2C
interface to read a temperature sensor: TMP102. Attach the sensor
board to your MCU development board, and the sensor will be connected
to the GPIOs through the connector.

Integrate the parser to receive commands to start and stop the
temperature reading operation. Detailed grading items are listed as
follows:

1. Based on Module 5, enable the I2C1 peripheral. Configure I2C pins
   according to the schematic. The I2C speed can be either standard or
   fast. You can use the MX configurator to initialize the I2C. (20%)
2. Implement a TMP102 initialization routine, with name
   `HAL_StatusTypeDef tmp102_initialize();`. You can adopt the
   `HAL_StatusTypeDef` as this function's return type to indicate if
   the TMP102 sensor has been initialized. (30%)
3. Implement temperature reading and print with 1s interval when
   "START" command has been received. one-shot mode with the "OS"
   command should be used. (30%)
4. Stop the temperature reading when "STOP" command has been
   received. (20%)

Please submit your project the same way as Module 4.

On the project demonstration visit, show the TA your source code,
briefly explain the logic, highlight how did you configure the
one-shot mode, how did you configure the address of the i2c device,
and the differences between the I2C read and write operation.
