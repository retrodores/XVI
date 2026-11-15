%encoding iso
%import editor_hooks
%import xvitext
%import tap
main {
    pointer raw = memory("petraw", 32, 1)
    pointer window = memory("petwindow", 77, 1)
    sub start() {
        plat.init()
        tap.ok(vtui.pet2scr($41) == 1 and vtui.pet2scr($c1) == $41, "VTUI ABI converts unshifted and shifted PETSCII correctly")
        tap.ok(vtui.scr2pet(1) == $41, "VTUI reverse conversion uses the documented entrypoint")
        tap.ok(vtui.pet2scr($a0) == $60 and vtui.pet2scr($ff) == $5e and vtui.pet2scr($7f) == $5f, "VTUI converts high graphics pi and alternate PETSCII range")
        raw[0] = $c1
        raw[1] = 0
        vtui.gotoxy(4, 3)
        vtui.print_str2(raw, $61, true)
        vtui.gotoxy(4, 3)
        tap.ok(lsb(vtui.scan_char()) == $41, "print_str shares full PETSCII conversion with direct plotting")
        doctext.init(plat.text_start(), plat.TEXT_TOP)
        long expected_capacity = buffer.installed_banks
        expected_capacity -= 4
        expected_capacity <<= 13
        tap.ok(buffer.free() == expected_capacity, "VTUI text uses detected banked capacity outside code and BSS")
        tap.ok(buffer.eol == $0d, "PETSCII document uses CR separators")
        raw[0] = $41
        raw[1] = $c1
        raw[2] = $a0
        raw[3] = $ff
        raw[4] = $12
        raw[5] = $92
        doctext.after_cr = false
        tap.ok(doctext.clean(raw, 6) == 6 and raw[0] == $41 and raw[1] == $c1 and raw[2] == $a0 and raw[3] == $ff and raw[4] == $12 and raw[5] == $92, "clean preserves PETSCII graphics case and control bytes")
        raw[0] = $0d
        raw[1] = $0a
        raw[2] = $c2
        raw[3] = $0a
        doctext.after_cr = false
        tap.ok(doctext.clean(raw, 4) == 3 and raw[0] == $0d and raw[1] == $c2 and raw[2] == $0d, "normalize line separators without ASCII filtering")
        raw[0] = $0d
        doctext.after_cr = false
        void doctext.clean(raw, 1)
        raw[0] = $0a
        raw[1] = $a1
        tap.ok(doctext.clean(raw, 2) == 1 and raw[0] == $a1, "CRLF normalization survives chunk boundary")
        void doctext.insert_at(1, 0, $c1)
        uword line
        for line in 2 to 201 {
            void doctext.insert_empty(line)
            void doctext.insert_at(line, 0, $a0 + (line % 32) as ubyte)
        }
        tap.ok(doctext.count == 201 and buffer.get(doctext.pos(201)) == $a9, "document spans 201 lines independently of 56 screen rows")
        doctext.fetch(1, window)
        tap.ok(window[0] == $c1, "first line retains high-bit PETSCII after long document edits")
        doctext.fetch(201, window)
        tap.ok(window[0] == $a9, "last off-screen line is fetched from gap buffer")
        tap.ok(doctext.yank(201) and doctext.put(1) and doctext.count == 202 and buffer.get(0) == $a9, "yank and paste act on text beyond original screen")
        tap.ok(doctext.save("pet-roundtrip.seq"), "save entire PETSCII document rather than VRAM")
        doctext.clear()
        tap.ok(doctext.load("pet-roundtrip.seq") and doctext.count == 202, "reload preserves all lines beyond screen")
        tap.ok(buffer.get(0) == $a9 and buffer.get(doctext.pos(202)) == $a9, "file round-trip preserves first and final PETSCII bytes")
        doctext.clear()
        uword col
        for col in 0 to 159
            void doctext.insert_at(1, 0, $c1)
        tap.ok(doctext.length(1) == 160, "PETSCII line extends beyond one viewport")
        doctext.first_col = 100
        doctext.fetch(1, window)
        tap.ok(window[0] == $c1 and window[59] == $c1 and window[60] == $20, "panned PETSCII fetch preserves graphics and pads suffix")
        txt.plot(4, 2)
        plat.show_text(window)
        vtui.gotoxy(4, 2)
        tap.ok(lsb(vtui.scan_char()) == vtui.pet2scr($c1), "bundled VTUI binary renders high-bit PETSCII as screen codes")
        vtui.gotoxy(64, 2)
        tap.ok(lsb(vtui.scan_char()) == $20, "VTUI rendering pads visible window without touching document")
        tap.ok(buffer.check() and doctext.length(1) == 160, "rendering leaves gap buffer intact")
        tap.done()
    }
}
