; xvi2 on the Commander X16: what depends on the target.  Each target has
; this block "plat" (and the block "cursor") with the same names; the
; virtual target only has the parts doctext uses, for its tests.

%import conv
%import diskio
%import strings
%import textio
%encoding iso

plat {
    ; the screen
    const ubyte COLS          = 80
    const ubyte LEFT_MARGIN   = 4
    const ubyte RIGHT_MARGIN  = 79
    const ubyte HEIGHT        = 56  ; absolute height of the edit/view area
    const ubyte TOP_LINE      = 2   ; row of the first line of the document
    const ubyte BOTTOM_LINE   = 57  ; row of the last line of the view port
    const ubyte FOOTER_LINE   = 59
    const ubyte ROW_LEN       = 79  ; what can be written on a row from column 0
    const bool LINE_NUMBERS   = true

    ; the columns of text on screen
    const ubyte TEXT_WIDTH    = 76

    ; the text goes from the end of the program up to here
    const uword TEXT_TOP      = $9f00

    sub init() {
        txt.iso()
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
        txt.plot(0, FOOTER_LINE)        ; blank footer line
        print(view.BLANK_ROW)
        txt.plot(0, 1)                  ; blank top line
        main.say(view.BLANK_ROW)
        print(view.BLANK_ROW)
        txt.scroll_up()
    }

    ; the rows of the view one down, the top one is free
    sub scroll_view_down() {
        txt.scrolldown()
    }

    ; the rows of the view from row on one down, that row is free
    sub scroll_down_from(ubyte row) {
        txt.scrolldown_nlast(row, LEFT_MARGIN)
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

    ; after diskio.f_close_w(): did the writing work?
    sub write_ok() -> bool {
        return true
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
