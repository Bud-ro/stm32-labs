## Assignment

This lab adds an SPI1 master driver to the BSP and a Fujitsu
MB85RS64V FRAM driver to the `class_board` package. The application
keeps logging temperatures from the TMP102 (lab-06) but persists each
reading into FRAM so that they survive a power cycle. New commands:

- `START` - begin sampling. If FRAM is empty, initialise the
  bookkeeping words and log from address 0x0004. If FRAM already
  holds data from a previous session, start a fresh session
  immediately after the old last entry.
- `STOP` - halt sampling. Address words are left in place so the
  next `START` continues past them.
- `TEMP` - read the bookkeeping words, then dump every temperature
  in the most recent session along with the count and the start /
  end addresses.
- `CLEAR` - zero every cell in the FRAM (8192 bytes via a single
  WRITE command, since FRAM has no page boundary).

Pin map for the FRAM:

- SCK: PB3 (SPI1_SCK AF0) - taken from the shield's P2 header
  so PA5 stays free for the on-board LED
- MISO: PA6 (SPI1_MISO AF0)
- MOSI: PA7 (SPI1_MOSI AF0)
- CS: PB0 (plain GPIO, driven by the FRAM driver)

The original assignment was this:

Project

In this module's project, we are going to explore how to use the SPI
interface to read and write to an external random access memory:
MB85RS64V. Refer to the schematic from previous module for wiring
information. The U6 in the middle is this chip. U3 is not implemented
so you can ignore it.

Detailed grading items are listed as follows:

1. In your project, initialize and configure the SPI1 module with MX
   configurator. (10%)
2. Configure GPIO according to the instruction document. (10%)
3. Implement a `START` instruction, according to the instructions in
   the attachment. (40%)
4. Implement a `TEMP` instruction, according to the instructions in
   the attachment. (30%)
5. Implement a `CLEAN` instruction, according to the instructions in
   the attachment. (10%)

Please submit your project the same way as Module 4.

On the demonstration day, the TA will check your source code and
evaluate if functions 3 to 5 are implemented.
