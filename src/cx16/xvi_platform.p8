; Commander X16 screen, keyboard, cursor, and file helpers for XVI2.
; Kept separate from document code for focused headless tests.

%import conv
%import diskio
%import strings
%import x16screen
%import textio
%encoding iso

plat {
    const bool PETSCII = false
    const bool LINE_NUMBERS = true
    const ubyte NORMAL_FG = 1
    const ubyte NORMAL_BG = 6
    const ubyte SCROLL_COL = 0
    const ubyte SCROLL_WIDTH = 80
    ; the screen
    const ubyte COLS          = 80
    const ubyte LEFT_MARGIN   = 4
    const ubyte RIGHT_MARGIN  = 79
    const ubyte HEIGHT        = 56  ; absolute height of the edit/view area
    const ubyte TOP_LINE      = 2   ; row of the first line of the document
    const ubyte BOTTOM_LINE   = 57  ; row of the last line of the view port
    const ubyte FOOTER_LINE   = 59
    const ubyte ROW_LEN       = 79  ; what can be written on a row from column 0

    ; the columns of text on screen
    const ubyte TEXT_WIDTH    = 76

    ; the text goes from the end of the program up to here
    const uword TEXT_TOP      = $9f00

    sub text_start() -> uword { return sys.progend() }

    sub init() {
        txt.iso()
        normal_colors()
        clear_canvas()
    }

    sub normal_colors() { colors(NORMAL_FG, NORMAL_BG) }
    sub status_colors() { normal_colors() }
    sub clear_canvas() {
        normal_colors()
        txt.fill_screen($20, $61)
        txt.plot(0, 0)
    }
    sub clear_row(ubyte row) { x16screen.fill(0, row, COLS, $20, $61) }
    sub empty_row(ubyte row) {
        clear_row(row)
        x16screen.fill(0, row, 1, $7e, $61)
    }

    ; back to BASIC
    sub quit() {
        txt.clear_screenchars($20)
        txt.iso_off()
        sys.exit(0)
    }

    ; a key (0: none)
    sub getkey() -> ubyte {
        return cbm.GETIN2()
    }

    sub command_char(ubyte c) { putc(c) }
    sub command_key() -> ubyte { return getkey() }
    sub printable(ubyte c) -> bool { return c >= 32 and c <= 126 }
    sub show_text(str text) { print(text) }

    sub print(str x) {
        cbm.CHROUT($80)
        txt.print(x)
    }

    sub putc(ubyte c) {
        if c == $22 {
            cbm.CHROUT($80)
        }
        txt.chrout(c)
    }

    sub nl() {
        txt.nl()
    }

    sub colors(ubyte fg, ubyte bg) {
        txt.color2(fg, bg)
    }

    sub color(ubyte fg) {
        txt.color(fg)
    }

    sub splash_text() {
        repeat 20 {
            txt.plot(0, txt.get_row())
            main.say("~    ")
        }
        main.say("~                             XVI - Commander X16 Vi               ")
        main.say("~                                                                  ")
        main.say("~                                version 2.0.RC-0                  ")
        main.say("~                                                                  ")
        main.say("~                      by Brett Estrade, Andrew Gillham, et al.    ")
        main.say("~                                                                  ")
        main.say("~                     XVI is open source and freely distributable  ")
        main.say("~                    writting using the Prog8 Programming Language ")
        main.say("~                                                                  ")
        main.say("~                             Sponsor Prog8 development!           ")
        main.say("~                                                                  ")
        main.say("~                                  http://p8ug.org                 ")
        main.say("~                                                                  ")
        main.say("~                  type  <esc>R to open new buffer in Replace mode ")
        main.say("~                  type  <esc>i to open new buffer in Insert  mode ")
        main.say("~                  type  :e filepath<Enter>   to load file to edit ")
        main.say("~                  type  :q<Enter>            to exit              ")
        repeat 21 {
            txt.plot(0, txt.get_row())
            main.say("~    ")
        }
    }

    ; the rows of the view one up, the bottom one is free
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

    ; disk

    sub exists(str name) -> bool {
        return diskio.exists(name)
    }

    sub delete(str name) {
        diskio.delete(name)
    }

    sub rename(str old_name, str new_name) {
        diskio.rename(old_name, new_name)
    }

    sub open_read(str name) -> bool {
        return diskio.f_open(name)
    }

    sub open_write(str name) -> bool {
        return diskio.f_open_w(name)
    }

}

cursor {
    ubyte saved_char

    sub save_char(ubyte c, ubyte r) {
        saved_char = txt.getchr(c,r)
    }

    sub save_current_char(ubyte c, ubyte r) {
        save_char(c,r)
    }

    sub restore_current_char() {
        ubyte c = view.c()
        ubyte r = view.r()
        txt.plot(c,r)
        plat.putc(saved_char)
        txt.plot(c,r)
    }

    sub hide() {
        restore_current_char()
        saved_char = $20
    }

    ; the cursor is the underlying character, with the color scheme inverted
    sub place(ubyte new_c, ubyte new_r) {
        restore_current_char()  ;; restore char in current cursor location
        txt.plot(new_c,new_r)   ;; move cursor to new location
        save_current_char(new_c, new_r)     ;; save char in the current location (here, the new c,r)
        plat.putc(saved_char)
        txt.setclr(new_c,new_r,$16) ; inverses color
        txt.plot(new_c,new_r)   ;; move cursor back after txt.chrout advances cursor
    }

    ; the cursor is the underlying character, with the color scheme inverted
    sub replace(ubyte new_c, ubyte new_r) {
        save_current_char(new_c, new_r)     ;; save char in the current location (here, the new c,r)
        txt.setclr(new_c,new_r,$16) ; inverses color
        txt.plot(new_c,new_r)   ;; move cursor back after txt.chrout advances cursor
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
