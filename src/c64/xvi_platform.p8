; xvi2 on the C64 (see src/cx16/xvi_platform.p8 for what this is).
;
; The text stays ASCII, as in the files: keys are translated to it in
; getkey(), and all output goes through to_screen.  There's no ISO mode.
; Nothing is printed with CHROUT: it scrolls the screen and links rows when
; it reaches the last column, and it's slow.  The columns from 0 to 39 are all
; written directly to screen memory.

%import conv
%import diskio
%import strings
%import textio
%encoding iso

plat {
    ; the screen
    const ubyte COLS          = 40
    const ubyte LEFT_MARGIN   = 0
    const ubyte RIGHT_MARGIN  = 39
    const ubyte HEIGHT        = 23  ; absolute height of the edit/view area
    const ubyte TOP_LINE      = 1   ; row of the first line of the document
    const ubyte BOTTOM_LINE   = 23  ; row of the last line of the view port
    const ubyte FOOTER_LINE   = 24
    const ubyte ROW_LEN       = 40  ; what can be written on a row from column 0
    const bool LINE_NUMBERS   = false

    ; the columns of text on screen
    const ubyte TEXT_WIDTH    = 40

    ; the text goes from the end of the program up to here (Prog8's startup
    ; banks out BASIC; the R0-R15 virtual registers are at $cfe0-$cfff)
    const uword TEXT_TOP      = $cfe0

    ; ASCII to screen codes of the lowercase character set.  characters it
    ; doesn't have get something like them: \ is a pound sign, ^ an up arrow,
    ; ` a ', { } are ( ) and ~ a -.  the file keeps the real ones.
    ubyte[128] to_screen = [
        $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20,
        $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20,
        $20, $21, $22, $23, $24, $25, $26, $27, $28, $29, $2a, $2b, $2c, $2d, $2e, $2f,
        $30, $31, $32, $33, $34, $35, $36, $37, $38, $39, $3a, $3b, $3c, $3d, $3e, $3f,
        $00, $41, $42, $43, $44, $45, $46, $47, $48, $49, $4a, $4b, $4c, $4d, $4e, $4f,
        $50, $51, $52, $53, $54, $55, $56, $57, $58, $59, $5a, $1b, $1c, $1d, $1e, $64,
        $27, $01, $02, $03, $04, $05, $06, $07, $08, $09, $0a, $0b, $0c, $0d, $0e, $0f,
        $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $1a, $28, $5d, $29, $2d, $20
    ]
    ubyte[128] to_ascii      ; back, for the character under the cursor

    sub init() {
        ubyte i
        for i in 127 downto 32 {
            to_ascii[to_screen[i]] = i
        }
        txt.lowercase()
        c64.EXTCOL = 6
        c64.BGCOL0 = 6
        txt.color(1)
    }

    ; back to BASIC
    sub quit() {
        txt.clear_screen()
        sys.exit(0)
    }

    ; a key as ASCII, or as the control code it has in PETSCII (the cursor
    ; keys, DEL, RETURN).  0: none
    sub getkey() -> ubyte {
        ubyte k = cbm.GETIN2()
        when k {
            $03, $5f -> return $1b      ; RUN/STOP and the left arrow are Esc
            $41 to $5a -> return k + $20
            $61 to $7a -> return k - $20
            $c1 to $da -> return k - $80
            $a4 -> return '_'           ; C= @
            $dd -> return '|'           ; Shift -
            $de -> return '~'           ; pi: Shift up arrow
            $db -> return '{'           ; Shift +
            $ba -> return '}'           ; Shift @
            $c0 -> return '`'           ; Shift *
        }
        return k
    }

    sub row_addr(ubyte row) -> uword {
        return mkword(cbm.HIBASE, 0) + (row as uword) * 40
    }

    ; a string at the cursor, cut off at the end of the row
    sub print(str x) {
        ubyte col = txt.get_column()
        ubyte row = txt.get_row()
        uword addr = row_addr(row) + col
        ubyte c
        repeat {
            c = @(x)
            if c == 0 or col == COLS {
                break
            }
            @(addr) = to_screen[c & $7f]
            addr++
            x++
            col++
        }
        if col == COLS {
            col--
        }
        txt.plot(col, row)
    }

    sub putc(ubyte c) {
        ubyte col = txt.get_column()
        ubyte row = txt.get_row()
        @(row_addr(row) + col) = to_screen[c & $7f]
        if col != COLS-1 {
            txt.plot(col+1, row)
        }
    }

    sub nl() {
        ubyte row = txt.get_row()
        if row != FOOTER_LINE {
            txt.plot(0, row+1)
        }
    }

    ; (the whole text is one color: color RAM isn't touched)
    sub colors(ubyte fg, ubyte bg) {
    }

    sub color(ubyte fg) {
    }

    sub splash_text() {
        txt.plot(0, TOP_LINE)
        repeat 3 {
            main.say("~")
        }
        main.say("~          XVI - C64 Vi")
        main.say("~")
        main.say("~         version 2.0.RC-0")
        main.say("~")
        main.say("~  by Brett Estrade, Andrew Gillham,")
        main.say("~  et al.")
        main.say("~")
        main.say("~  XVI is open source and freely")
        main.say("~  distributable, written in Prog8")
        main.say("~         http://p8ug.org")
        main.say("~")
        main.say("~  <stop>R  new buffer, Replace mode")
        main.say("~  <stop>i  new buffer, Insert mode")
        main.say("~  :e file<return>  load a file")
        main.say("~  :q<return>       exit")
        repeat 5 {
            main.say("~")
        }
    }

    sub copy_row(ubyte source, ubyte target) {
        sys.memcopy(row_addr(source), row_addr(target), COLS)
    }

    ; the rows of the view one up, the bottom one is free
    sub scroll_view_up() {
        ubyte row = TOP_LINE
        while row != BOTTOM_LINE {
            copy_row(row+1, row)
            row++
        }
    }

    ; the rows of the view one down, the top one is free
    sub scroll_view_down() {
        scroll_down_from(TOP_LINE)
    }

    ; the rows of the view from row on one down, that row is free
    sub scroll_down_from(ubyte row) {
        ubyte r = BOTTOM_LINE
        while r > row {
            copy_row(r-1, r)
            r--
        }
    }

    ; disk: file names are PETSCII there.  (not diskio.exists(): probing for
    ; a missing file with a read channel hangs the 1541 after a number of
    ; tries, see bugs/diskio_missing_file.md)

    str name1 = " " * 40
    str name2 = " " * 40
    str drive_status = " " * 40
    ubyte drive_code

    ; copy an ASCII name to dest in PETSCII
    sub dos_name(str name, str dest) {
        ubyte i = 0
        ubyte c
        repeat {
            c = name[i]
            if c >= 'a' and c <= 'z' {
                c -= $20
            }
            else if c >= 'A' and c <= 'Z' {
                c += $80
            }
            dest[i] = c
            if c == 0 or i == 38 {
                break
            }
            i++
        }
        dest[i] = 0
    }

    ; read the drive's status, which clears it.  (like diskio.status(), but
    ; that ignores a failing CHKIN and then reads the keyboard)
    sub read_drive_status() {
        ubyte n = 0
        ubyte c
        drive_status[0] = 0
        cbm.SETNAM(0, drive_status)
        cbm.SETLFS(15, diskio.drivenumber, 15)
        void cbm.OPEN()
        if_cc {
            if not cbm.CHKIN(15) {
                while cbm.READST() == 0 and n < len(drive_status) - 1 {
                    c = cbm.CHRIN()
                    if c == $0d or c == $0a {
                        break
                    }
                    drive_status[n] = c
                    n++
                }
                drive_status[n] = 0
            }
            cbm.CLRCHN()
            cbm.CLOSE(15)
        }
        drive_code = 255
        if drive_status[0] >= '0' and drive_status[0] <= '9' {
            drive_code = conv.str2uword(drive_status) as ubyte
        }
    }

    sub exists(str name) -> bool {
        dos_name(name, name1)
        cbm.SETNAM(strings.length(name1), name1)
        cbm.SETLFS(11, diskio.drivenumber, 11)
        void cbm.OPEN()
        read_drive_status()
        cbm.CLOSE(11)
        return drive_code < 20
    }

    sub delete(str name) {
        dos_name(name, name1)
        diskio.delete(name1)
    }

    sub rename(str old_name, str new_name) {
        dos_name(old_name, name1)
        dos_name(new_name, name2)
        diskio.rename(name1, name2)
    }

    sub open_read(str name) -> bool {
        dos_name(name, name1)
        return diskio.f_open(name1)
    }

    ; as a SEQ file.  the file must not exist yet.
    sub open_write(str name) -> bool {
        dos_name(name, name1)
        void strings.append(name1, ",S,W")
        return diskio.f_open_w(name1)
    }

    ; after diskio.f_close_w(): did the writing work?  (the status can't be
    ; read before the file is closed: closing channel 15 closes every file)
    sub write_ok() -> bool {
        read_drive_status()
        return drive_code < 20
    }
}

cursor {
    ubyte saved_char            ; ASCII

    sub put(ubyte c, ubyte r, ubyte code) {
        @(plat.row_addr(r) + c) = code
    }

    sub save_char(ubyte c, ubyte r) {
        saved_char = plat.to_ascii[txt.getchr(c,r) & $7f]
    }

    sub save_current_char(ubyte c, ubyte r) {
        save_char(c,r)
    }

    sub restore_current_char() {
        put(view.c(), view.r(), plat.to_screen[saved_char & $7f])
    }

    sub hide() {
        restore_current_char()
        saved_char = $20
    }

    ; the cursor is the underlying character, reversed
    sub place(ubyte new_c, ubyte new_r) {
        restore_current_char()
        replace(new_c, new_r)
    }

    sub replace(ubyte new_c, ubyte new_r) {
        save_current_char(new_c, new_r)
        put(new_c, new_r, plat.to_screen[saved_char & $7f] | $80)
        txt.plot(new_c, new_r)
    }
}
