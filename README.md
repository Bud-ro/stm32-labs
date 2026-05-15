# stm32-zig-labs

Bare-metal Zig labs for the STM32G071RB on the NUCLEO-G071RB board.
The course wanted us to use the STM32CubeIDE, but I am _not_ a fan of it.
Of course I'll have to anyways (I won't publish those), but this is simply 
to show that there is a significantly simpler way to do embedded development.

All labs work on Zig 0.16.0, and can be flashed using Zig build system commands
that orchestrate OpenOCD. You can also debug, albeit the experience is somewhat bad.

## Prerequisites

- [Zig](https://ziglang.org/download/) >= 0.16.0
- [OpenOCD](https://openocd.org/) (for flashing)
- `gdb-multiarch` (for debugging)

## Building

```sh
zig build -Dlab=lab-03
```

The build produces an ELF and a raw `.bin`, and prints a flash/RAM memory usage report:
```
FLASH:
  .isr_vector              192 bytes
  .text                    680 bytes
  .rodata                   52 bytes
  .ARM.exidx               104 bytes
      1028 bytes used  (0.78%)
    130044 bytes free  (99.21%)

RAM:
  .bss                      36 bytes
        36 bytes used  (0.09%)
     36828 bytes free  (99.90%)
```

## Flashing

```sh
zig build flash -Dlab=lab-03
```

Flashes via ST-Link using OpenOCD.

## Debugging

Open the project in VS Code with the Cortex-Debug extension. The `.vscode/launch.json` is pre-configured — select the lab from the picker and press F5.

## Project Structure

```
build.zig              Top-level build — dispatches to the selected lab
nucleo-g071rb/         Board support package (BSP)
lab-xx/                Folder containing standalone package for a certain lab.
```

## License

This project is licensed under The MIT License. See [LICENSE](LICENSE) for details.
