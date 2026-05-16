/// Command accumulator backed by a fixed-size circular buffer.
/// Tracks input length, overflow detection, backspace support,
/// and linear command extraction.
pub const CommandBuffer = struct {
    buf: []u8,
    head: usize = 0,
    input_len: usize = 0,
    overflowed: bool = false,

    pub fn add(self: *CommandBuffer, c: u8) void {
        self.buf[self.head] = c;
        self.head = if (self.head + 1 >= self.buf.len) 0 else self.head + 1;
        if (self.input_len < self.buf.len) {
            self.input_len += 1;
        } else {
            self.overflowed = true;
        }
    }

    pub fn removeLast(self: *CommandBuffer) bool {
        if (self.input_len == 0) return false;
        self.head = if (self.head == 0) self.buf.len - 1 else self.head - 1;
        self.buf[self.head] = 0;
        self.input_len -= 1;
        return true;
    }

    pub fn currentInput(self: *const CommandBuffer, out: []u8) []const u8 {
        const n = @min(self.input_len, self.buf.len);
        var pos = if (self.head >= n) self.head - n else self.buf.len - (n - self.head);
        for (0..n) |i| {
            out[i] = self.buf[pos];
            pos = if (pos + 1 >= self.buf.len) 0 else pos + 1;
        }
        return out[0..n];
    }

    pub fn resetInput(self: *CommandBuffer) void {
        self.input_len = 0;
        self.overflowed = false;
    }
};
