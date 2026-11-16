; PETSCII/VTUI frontend for the Commander X16. The shared editor uses
; ASCII commands/status strings, but document input/output stays PETSCII.
%encoding iso
%import x16screen
%import textio
%import strings
%import diskio
%import vtui
plat {
    const bool PETSCII = true
    const bool LINE_NUMBERS = false
    const ubyte NORMAL_FG = 6
    const ubyte NORMAL_BG = 12
    const ubyte SCROLL_COL = 2
    const ubyte SCROLL_WIDTH = 76
    const ubyte COLS = 80
    const ubyte LEFT_MARGIN = 2
    const ubyte RIGHT_MARGIN = 77
    const ubyte HEIGHT = 56
    const ubyte TOP_LINE = 2
    const ubyte BOTTOM_LINE = 57
    const ubyte FOOTER_LINE = 58
    const ubyte ROW_LEN = 79
    const ubyte TEXT_WIDTH = 76
    const uword TEXT_TOP = 0
    sub text_start() -> uword { return 0 }
    ubyte foreground = NORMAL_FG
    ubyte background = NORMAL_BG
    str filename = " " * 80

    sub init() {
        txt.iso_off()
        vtui.initialize()
        vtui.screen_set(0)
        txt.lowercase()
        clear_canvas()
    }
    sub normal_colors() { colors(NORMAL_FG, NORMAL_BG) }
    sub status_colors() { colors(1, 0) }
    sub clear_canvas() {
        normal_colors()
        ; Original XVI palette: green surround, gray/blue interior, black frame.
        vtui.clr_scr($20, $50)
        vtui.gotoxy(1, 1)
        vtui.fill_box($20, 77, 57, $c6)
        vtui.gotoxy(1, 1)
        vtui.border(1, 78, 58, $00)
        txt.plot(LEFT_MARGIN, TOP_LINE)
    }
    sub clear_row(ubyte row) {
        if row >= TOP_LINE and row <= BOTTOM_LINE
            x16screen.fill(LEFT_MARGIN, row, TEXT_WIDTH, $20, $c6)
        else if row == FOOTER_LINE
            x16screen.fill(1, row, 78, $20, $01)
        else if row == 0
            x16screen.fill(0, row, COLS, $20, $50)
    }
    sub empty_row(ubyte row) { clear_row(row) }

    sub quit() {
        txt.clear_screen()
        sys.exit(0)
    }
    sub getkey() -> ubyte { return cbm.GETIN2() }
    sub command_char(ubyte c) { draw(pet(c)) }
    sub command_key() -> ubyte {
        ubyte c = getkey()
        if c >= $41 and c <= $5a
            return c + $20
        if c >= $c1 and c <= $da
            return c - $80
        return c
    }
    sub printable(ubyte c) -> bool {
        return c >= $20 and (c < $80 or c >= $a0)
    }
    sub pet(ubyte c) -> ubyte {
        if c >= $61 and c <= $7a
            return c - $20
        if c >= $41 and c <= $5a
            return c + $80
        return c
    }
    sub draw(ubyte c) {
        ubyte col = txt.get_column()
        ubyte row = txt.get_row()
        vtui.gotoxy(col, row)
        ubyte screen = $20
        if printable(c)
            screen = vtui.pet2scr(c)
        ubyte colors = (background << 4) | foreground
        if row == 0 or row == 59 or col == 0 or col == 79
            colors = $50 | foreground
        else if row == FOOTER_LINE
            colors = $01
        vtui.plot_char(screen, colors)
        if col < COLS-1
            txt.plot(col+1, row)
    }
    ; UI text is canonical ASCII, separate from PETSCII document bytes.
    sub print(str text) {
        ubyte i = 0
        while text[i] != 0 and i < COLS {
            draw(pet(text[i]))
            i++
        }
    }
    sub putc(ubyte c) { draw(c) }
    sub show_text(str text) {
        ubyte i
        for i in 0 to TEXT_WIDTH-1
            draw(text[i])
    }
    sub nl() {
        if txt.get_row() < FOOTER_LINE
            txt.plot(0, txt.get_row()+1)
    }
    sub colors(ubyte fg, ubyte bg) {
        foreground = fg
        background = bg
    }
    sub color(ubyte fg) { foreground = fg }
    sub splash_text() {
        txt.plot(LEFT_MARGIN, 8)
        print("XVI - Commander X16 PETSCII / VTUI")
        txt.plot(LEFT_MARGIN, 9)
        print("Gap-buffer development build")
        txt.plot(LEFT_MARGIN, 10)
        print("i: insert   R: replace   :e file: open   :q: quit")
    }
    sub scroll_view_up() {
        ubyte row
        for row in TOP_LINE to BOTTOM_LINE-1
            x16screen.copy_row(row+1, row, SCROLL_COL, SCROLL_WIDTH)
        clear_row(BOTTOM_LINE)
    }
    sub scroll_view_down() { scroll_down_from(TOP_LINE) }
    sub scroll_down_from(ubyte top) {
        top = max(TOP_LINE, top)
        ubyte row = BOTTOM_LINE
        while row > top {
            x16screen.copy_row(row-1, row, SCROLL_COL, SCROLL_WIDTH)
            row--
        }
        if top <= BOTTOM_LINE
            clear_row(top)
    }

    ; Canonical command filenames are ASCII; X16 DOS sees PETSCII.
    sub dos_name(str name) {
        ubyte i = 0
        while name[i] != 0 and i < 79 {
            filename[i] = pet(name[i])
            i++
        }
        filename[i] = 0
    }
    sub exists(str name) -> bool { dos_name(name) return diskio.exists(filename) }
    sub delete(str name) { dos_name(name) diskio.delete(filename) }
    sub rename(str old_name, str new_name) {
        str old = " " * 80
        dos_name(old_name)
        void strings.copy(filename, old)
        dos_name(new_name)
        diskio.rename(old, filename)
    }
    sub open_read(str name) -> bool { dos_name(name) return diskio.f_open(filename) }
    sub open_write(str name) -> bool { dos_name(name) return diskio.f_open_w(filename) }
}
cursor {
    ubyte saved_char = $20
    sub save_char(ubyte c, ubyte r) {
        saved_char = $20
        if r < view.TOP_LINE or r > view.BOTTOM_LINE or c < view.LEFT_MARGIN
            return
        long line = view.CURR_TOP_LINE + r - view.TOP_LINE
        long position = doctext.pos(line)
        long col = doctext.first_col + c - view.LEFT_MARGIN
        if position != buffer.NONE and col < doctext.length(line)
            saved_char = buffer.get(position + col)
    }
    sub save_current_char(ubyte c, ubyte r) { save_char(c, r) }
    sub restore_current_char() {
        ubyte c = view.c()
        ubyte r = view.r()
        plat.putc(saved_char)
        txt.plot(c, r)
    }
    sub hide() { restore_current_char() saved_char = $20 }
    sub place(ubyte c, ubyte r) { restore_current_char() replace(c, r) }
    sub replace(ubyte c, ubyte r) {
        txt.plot(c, r)
        save_char(c, r)
        vtui.gotoxy(c, r)
        ubyte screen = $20
        if plat.printable(saved_char)
            screen = vtui.pet2scr(saved_char)
        vtui.plot_char(screen, $61)
        txt.plot(c, r)
    }
}

txt {
    %option merge

    sub scrolldown_nlast(ubyte top_row, ubyte col_start) {
        ubyte columns, rows, j
        columns, rows = txt.size()
        rows--
        while rows>top_row {
            rows--
            uword vera_addr = lsw(txt.VERA_TEXTMATRIX) + 256*rows
            cx16.vaddr(msw(txt.VERA_TEXTMATRIX), vera_addr+col_start,     0 ,1) ; source row
            cx16.vaddr(msw(txt.VERA_TEXTMATRIX), vera_addr+col_start+256, 1, 1) ; target row
            for j in col_start to columns-1 {
                cx16.VERA_DATA1 = cx16.VERA_DATA0       ; copy tile
                cx16.VERA_DATA1 = cx16.VERA_DATA0       ; copy color
            }
        }
    }

    sub scrolldown() {
        ubyte columns, rows
        columns, rows = txt.size()
        rows--
        while rows>0 {
            rows--
            uword vera_addr = lsw(txt.VERA_TEXTMATRIX) + 256*rows
            cx16.vaddr(msw(txt.VERA_TEXTMATRIX), vera_addr, 0 ,1)       ; source row
            cx16.vaddr(msw(txt.VERA_TEXTMATRIX), vera_addr+256, 1, 1)   ; target row
            repeat columns {
                cx16.VERA_DATA1 = cx16.VERA_DATA0       ; copy tile
                cx16.VERA_DATA1 = cx16.VERA_DATA0       ; copy color
            }
        }
    }
}
