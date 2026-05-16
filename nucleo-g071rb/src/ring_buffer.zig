/// SPSC byte ring buffer backed by an external slice.
///
/// Safe for ISR-to-main-loop use on single-core Cortex-M:
///  - Byte loads/stores are single-copy atomic (ARMv6-M ARM A3.5.3)
///  - STRB is a true byte write on AHB-Lite, not a read-modify-write
///    (AMBA 3 AHB-Lite spec, HSIZE byte-lane selection)
///  - Head is only written by the producer, tail only by the consumer
///  - pop() contains compiler fences (zero-cost memory clobber) to
///    force reload of head and to order the buf read before the tail
///    write - no reliance on external barriers
///  - push() needs no fences: the ISR runs to completion on M0+, so
///    all stores are committed before the main loop resumes
///
/// Assumes the consumer services the buffer fast enough that it never
/// fills. push() returns false on overflow but does not signal the
/// condition - bytes are silently lost.
pub const RingBuffer = struct {
    buf: []u8,
    head: usize = 0,
    tail: usize = 0,

    fn compilerFence() void {
        asm volatile ("" ::: .{ .memory = true });
    }

    pub fn push(self: *RingBuffer, byte: u8) bool {
        const next = if (self.head + 1 >= self.buf.len) 0 else self.head + 1;
        if (next == self.tail) return false;
        self.buf[self.head] = byte;
        self.head = next;
        return true;
    }

    pub fn pop(self: *RingBuffer) ?u8 {
        compilerFence();
        if (self.head == self.tail) return null;
        const byte = self.buf[self.tail];
        self.tail = if (self.tail + 1 >= self.buf.len) 0 else self.tail + 1;
        return byte;
    }

    pub fn nonEmpty(self: *const RingBuffer) bool {
        compilerFence();
        return self.head != self.tail;
    }
};
