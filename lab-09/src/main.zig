//! Lab 09: button-triggered ADC over DMA, plus a 1 Hz LED heartbeat.
//!
//! Everything below is deliberately register-level: the assignment is
//! to show ADC + DMA + EXTI working in concert without leaning on a
//! HAL. The only abstraction we pull in from the BSP is the GPIO Pin
//! helper (so we don't open-code MODER masks) and EXTI line setup.
//!
//! Wiring:
//!   - Potentiometer feeds the LMV358 op-amp; its output enters the
//!     MCU on PC4 (ADC1_IN17) when J8 pins 2-3 are shorted.
//!   - User button B1: PC13, active low, EXTI line 13.
//!
//! Flow: button press -> EXTI ISR sets ADSTART -> ADC sequences one
//! channel ten times -> DMA streams each result into `adc_samples`
//! -> on DMA transfer-complete, the ISR stops the ADC, averages the
//! buffer, and prints the voltage. The super-loop is just `wfi` once
//! the TX ring has drained.
const board = @import("board");

const chip = board.chip;
const adc = chip.peripherals.ADC;
const dma = chip.peripherals.DMA;
const dmamux = chip.peripherals.DMAMUX;
const rcc = chip.peripherals.RCC;
const nvic = chip.peripherals.NVIC;

const SYSCLK: board.clock.Config = .pll_32mhz;

const SAMPLE_COUNT: u16 = 10;
const VREF_MV: u32 = 3300;
/// DMAMUX request line for the ADC trigger on STM32G071 (DMAREQ_ID = 5).
const DMA_REQ_ADC: u8 = 5;

/// ADC sample landing zone. Filled by DMA, read once by `onDmaComplete`.
var adc_samples: [SAMPLE_COUNT]u16 = .{0} ** SAMPLE_COUNT;

const pot_pin = board.gpio.Pin(.C, 4);
const button_pin = board.gpio.Pin(.C, 13);

/// SysTick fires at 1 kHz; toggle the LED every 1000 ticks for a 1 Hz
/// heartbeat. Counting in the ISR avoids dragging in erd_core just for
/// blink - the rest of the lab is deliberately interrupt-only.
var blink_ticks: u16 = 0;

fn sysTick() callconv(.c) void {
    blink_ticks +%= 1;
    if (blink_ticks >= 1000) {
        blink_ticks = 0;
        board.Hardware.led.toggle();
    }
}

fn buttonHandler() callconv(.c) void {
    board.exti.clearPending(13);
    // Re-arm DMA for another batch (CNDTR is decremented during the
    // previous transfer, so writing it back to SAMPLE_COUNT prepares
    // the channel). The channel must be disabled before CNDTR is
    // rewritten; CCR.EN was cleared automatically when CNDTR hit zero
    // on the previous burst.
    dma.CCR1.modify(.{ .EN = 0 });
    dma.CNDTR1.write(.{ .NDT = SAMPLE_COUNT });
    dma.CCR1.modify(.{ .EN = 1 });

    adc.ADC_CR.modify(.{ .ADSTART = .B_0x1 });
}

fn dmaCompleteHandler() callconv(.c) void {
    // Stop the (continuous) ADC and discard any overrun left from the
    // race between the last DMA pull and the conversion that followed.
    adc.ADC_CR.modify(.{ .ADSTP = .B_0x1 });
    while (adc.ADC_CR.read().ADSTART == .B_0x1) {}
    adc.ADC_ISR.write(.{ .OVR = .B_0x1 });

    // Clear channel 1's global + transfer-complete + half-transfer +
    // transfer-error flags. (regz named these by bit position - the
    // bottom four bits are all channel 1, despite the misleading
    // CGIF0/CTCIF1/CHTIF2/CTEIF3 numbering.)
    dma.IFCR.write(.{ .CGIF0 = 1, .CTCIF1 = 1, .CHTIF2 = 1, .CTEIF3 = 1 });

    var sum: u32 = 0;
    for (adc_samples) |s| sum += s;
    const avg: u32 = sum / SAMPLE_COUNT;

    // 12-bit ADC, VREF = 3.3 V. mV = avg * 3300 / 4095. We carry one
    // extra digit so the printout reads as millivolts -> "1.234 V".
    const mv: u32 = (avg * VREF_MV) / 4095;
    const serial = board.Hardware.serial;
    serial.puts("Voltage: ");
    printUint(mv / 1000);
    serial.putc('.');
    const frac = mv % 1000;
    serial.putc('0' + @as(u8, @intCast(frac / 100)));
    serial.putc('0' + @as(u8, @intCast((frac / 10) % 10)));
    serial.putc('0' + @as(u8, @intCast(frac % 10)));
    serial.puts(" V (raw avg ");
    printUint(avg);
    serial.puts(")\r\n");
}

pub export const vector_table linksection(".isr_vector") =
    board.startup.vectorTable(.{
        .SysTick = &sysTick,
        .EXTI4_15 = &buttonHandler,
        .DMA_Channel1 = &dmaCompleteHandler,
    });

pub fn main() noreturn {
    board.Hardware.init(SYSCLK);

    const serial = board.Hardware.serial;
    serial.puts("Lab 09: button-triggered ADC over DMA\r\n");
    serial.puts("Press the blue button (B1) to sample the potentiometer.\r\n");

    setupAdc();
    setupDma();
    setupButton();

    // The application proper is fully interrupt-driven: the button
    // starts a batch, the DMA TC ISR averages and prints. The main loop
    // only services UART TX drain; on every iteration with no remaining
    // work it sleeps until the next interrupt.
    while (true) {
        if (!board.Hardware.runUarts()) asm volatile ("wfi");
    }
}

fn setupAdc() void {
    rcc.IOPENR.modify(.{ .IOPCEN = 1 });
    rcc.APBENR2.modify(.{ .ADCEN = 1 });

    pot_pin.configure(.{ .mode = .analog });

    // Enable the ADC voltage regulator and wait for it to stabilise.
    // RM specifies tADCVREG_SETUP = 20 us; at 32 MHz that's ~640 cycles.
    adc.ADC_CR.modify(.{ .ADVREGEN = .B_0x1 });
    busyDelayCycles(700);

    // Trigger and wait for end-of-calibration. (ADCAL self-clears.)
    adc.ADC_CR.modify(.{ .ADCAL = .B_0x1 });
    while (adc.ADC_CR.read().ADCAL == .B_0x1) {}

    // Enable the ADC, wait for ADRDY.
    adc.ADC_ISR.write(.{ .ADRDY = .B_0x1 });
    adc.ADC_CR.modify(.{ .ADEN = .B_0x1 });
    while (adc.ADC_ISR.read().ADRDY == .B_0x0) {}

    // DMAEN=1 lets the ADC ask DMA to move each conversion result.
    // CONT=1 keeps converting until ADSTP, which lets DMA pull one
    // full burst back-to-back. DMACFG=0 (one-shot) means the channel
    // disables itself after CNDTR ticks down, so onDmaComplete only
    // fires once per button press.
    adc.ADC_CFGR1.modify(.{ .DMAEN = .B_0x1, .CONT = .B_0x1 });

    // Longest sampling time (160.5 ADC clock cycles) - pot output
    // through the LMV358 has high source impedance.
    adc.ADC_SMPR.modify(.{ .SMP1 = .B_0x7 });

    // Select channel 17 in bit-mask mode (CHSELRMOD = 0 at reset).
    adc.ADC_CHSELRMOD0.modify(.{ .CHSEL17 = .B_0x1 });
    while (adc.ADC_ISR.read().CCRDY == .B_0x0) {}
    adc.ADC_ISR.write(.{ .CCRDY = .B_0x1 });
}

fn setupDma() void {
    rcc.AHBENR.modify(.{ .DMAEN = 1 });

    // Route DMA channel 1 (DMAMUX channel 0) to the ADC request line.
    dmamux.DMAMUX_C0CR.modify(.{ .DMAREQ_ID = DMA_REQ_ADC });

    dma.CPAR1.write(.{ .PA = @intFromPtr(&adc.ADC_DR) });
    dma.CMAR1.write(.{ .MA = @intFromPtr(&adc_samples) });
    dma.CNDTR1.write(.{ .NDT = SAMPLE_COUNT });

    // 16-bit peripheral + memory transfers, memory pointer auto-
    // increments, fire the channel-1 IRQ on TC. DIR=0 (peripheral
    // -> memory) is the reset value and stays put. Enable last.
    dma.CCR1.modify(.{
        .TCIE = 1,
        .MINC = 1,
        .PSIZE = 0b01,
        .MSIZE = 0b01,
    });
    dma.CCR1.modify(.{ .EN = 1 });

    nvic.ISER.write(.{ .bits = 1 << chip.irqIndex("DMA_Channel1") });
}

fn setupButton() void {
    // GPIOC clock already enabled in setupAdc.
    // PC13 defaults to *analog* on STM32G0 (GPIOC_MODER reset =
    // 0xFFFF_FFFF), so flip it to input before unmasking EXTI -
    // otherwise the Schmitt trigger sees nothing. The Nucleo has a
    // 10 kohm pull-up on PC13; pressing B1 drops the line to GND, so
    // we trigger on the falling edge.
    button_pin.configure(.{ .mode = .input });
    board.exti.enable(.C, 13, .falling);
}

fn busyDelayCycles(comptime cycles: u32) void {
    var i: u32 = 0;
    while (i < cycles) : (i += 1) {
        asm volatile ("nop" ::: .{ .memory = true });
    }
}

fn printUint(n: u32) void {
    const serial = board.Hardware.serial;
    if (n == 0) {
        serial.putc('0');
        return;
    }
    var digits: [10]u8 = undefined;
    var v = n;
    var i: usize = 0;
    while (v > 0) : (i += 1) {
        digits[i] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
    while (i > 0) {
        i -= 1;
        serial.putc(digits[i]);
    }
}
