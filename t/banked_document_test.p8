%encoding iso
%import editor_hooks
%import xvitext
%import tap
main {
    pointer block = memory("bankfixture", 512, 1)
    pointer window = memory("widewindow", 77, 1)
    sub expected(long position) -> ubyte {
        position >>= 9
        uword index = position as uword
        return 'a' + (index % 26) as ubyte
    }
    sub start() {
        ubyte entry_bank = @($00)
        doctext.init(0, 0)
        long size = buffer.capacity
        tap.ok(buffer.installed_banks == 64 or buffer.installed_banks == 256, "detect stock or fully expanded RAM")
        long expected_capacity = buffer.installed_banks
        expected_capacity -= 4
        expected_capacity <<= 13
        tap.ok(size == expected_capacity, "reserve first four banks and use detected remainder")
        tap.ok(size > 65535, "banked text capacity exceeds 16-bit addressing")
        @($00) = 3
        long position = 0
        while position < size {
            sys.memset(block, 512, expected(position))
            if not buffer.insert_bytes(block, 512, position) {
                tap.ok(false, "fill all detected banks")
                tap.done()
            }
            position += 512
        }
        tap.ok(buffer.length() == size and buffer.free() == 0 and buffer.check(), "fill all detected document banks exactly")
        tap.ok(@($00) == 3, "bank transfers restore caller's selected bank")
        tap.ok(buffer.get(0) == expected(0) and buffer.get(8191) == expected(8191) and buffer.get(8192) == expected(8192), "bytes across first bank boundary remain distinct")
        tap.ok(buffer.get(65535) == expected(65535) and buffer.get(65536) == expected(65536), "read text across 64 KiB boundary")
        tap.ok(buffer.get(size-1) == expected(size-1), "highest installed bank is usable without aliasing")
        tap.ok(not buffer.insert_char('!', 0) and buffer.length() == size, "full banked document rejects overflow")
        buffer.set_mark(0, 65537)
        tap.ok(buffer.delete_nchar(3, 65535) == 3 and buffer.get_mark(0) == 65535, "wide marks follow deletion across 64 KiB")
        buffer.move_gap(0)
        tap.ok(buffer.get(0) == expected(0) and buffer.get(65535) == expected(65538) and buffer.check(), "move gap across many banks with three-byte free gap")
        tap.ok(buffer.insert("XYZ", 65535) and buffer.length() == size and buffer.get(65535) == 'X' and buffer.get(65537) == 'Z', "insert across 64 KiB after cross-bank gap move")
        doctext.first_col = 65530
        doctext.fetch(1, window)
        tap.ok(window[5] == 'X' and window[7] == 'Z', "document window uses wide column positions")
        tap.ok(doctext.save("wide.seq"), "save a full-capacity banked document through main-RAM staging")
        doctext.clear()
        tap.ok(doctext.load("wide.seq") and not doctext.truncated and buffer.length() == size, "reload full-capacity file including final line ending")
        tap.ok(buffer.get(65535) == 'X' and buffer.get(size-1) == expected(size-1), "wide edits and last bank survive disk round-trip")
        tap.ok(@($00) == 3 and buffer.check(), "file I/O and scans preserve bank selector and invariants")
        doctext.clear()
        sys.memset(block, 512, buffer.eol)
        uword line_block
        for line_block in 0 to 136
            void buffer.insert_bytes(block, 512, buffer.length())
        tap.ok(buffer.line_number(buffer.length()) == 70144, "line counting exceeds 65535 separators")
        tap.ok(doctext.save("lines.seq") and doctext.load("lines.seq") and doctext.count == 70145, "disk round-trip retains more than 65535 lines")
        tap.ok(doctext.pos(70001) == 70000 and doctext.length(70001) == 0, "document lookup accepts wide line numbers")
        @($00) = entry_bank
        tap.done()
    }
}
