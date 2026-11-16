%encoding iso
%import editor_hooks
%import xvitext
%import tap
main {
    sub start() {
        plat.init()
        txt.fill_screen($ff, $00)
        plat.clear_canvas()
        bool canvas = true
        ubyte row, col
        ubyte expected
        for row in 0 to 59 {
            for col in 0 to 79 {
                expected = $61
                if plat.PETSCII {
                    expected = $c6
                    if row == 0 or row == 59 or col == 0 or col == 79
                        expected = $50
                    else if row == 1 or row == 58 or col == 1 or col == 78
                        expected = $00
                }
                if txt.getclr(col, row) != expected
                    canvas = false
            }
        }
        x16screen.fill(plat.SCROLL_COL, plat.TOP_LINE, plat.SCROLL_WIDTH, $41, $ab)
        x16screen.fill(plat.SCROLL_COL, plat.TOP_LINE+1, plat.SCROLL_WIDTH, $42, $cd)
        x16screen.fill(plat.SCROLL_COL, plat.BOTTOM_LINE, plat.SCROLL_WIDTH, $43, $ef)
        plat.scroll_view_up()
        bool up = txt.getchr(plat.SCROLL_COL, plat.TOP_LINE) == $42 and txt.getclr(plat.SCROLL_COL, plat.TOP_LINE) == $cd
        bool up_last = txt.getchr(plat.RIGHT_MARGIN, plat.TOP_LINE) == $42 and txt.getclr(plat.RIGHT_MARGIN, plat.TOP_LINE) == $cd
        bool bottom = txt.getchr(plat.RIGHT_MARGIN, plat.BOTTOM_LINE) == $20
        ubyte normal = (plat.NORMAL_BG << 4) | plat.NORMAL_FG
        bottom = bottom and txt.getclr(plat.RIGHT_MARGIN, plat.BOTTOM_LINE) == normal
        plat.scroll_view_down()
        bool down = txt.getchr(plat.SCROLL_COL, plat.TOP_LINE+1) == $42 and txt.getclr(plat.SCROLL_COL, plat.TOP_LINE+1) == $cd
        bool down_last = txt.getchr(plat.RIGHT_MARGIN, plat.TOP_LINE+1) == $42 and txt.getclr(plat.RIGHT_MARGIN, plat.TOP_LINE+1) == $cd
        x16screen.fill(plat.SCROLL_COL, 10, plat.SCROLL_WIDTH, $44, $ed)
        plat.scroll_down_from(10)
        bool insert = txt.getchr(plat.RIGHT_MARGIN, 11) == $44 and txt.getclr(plat.RIGHT_MARGIN, 11) == $ed
        plat.clear_row(11)
        bool clear = txt.getchr(plat.RIGHT_MARGIN, 11) == $20 and txt.getclr(plat.RIGHT_MARGIN, 11) == normal
        bool edges = true
        for row in 0 to 59 {
            if plat.PETSCII {
                if txt.getclr(0, row) != $50 or txt.getclr(79, row) != $50
                    edges = false
                if row > 0 and row < 59 and (txt.getclr(1, row) != $00 or txt.getclr(78, row) != $00)
                    edges = false
            }
        }
        bool fixed_rows = true
        for col in 0 to 79 {
            expected = $61
            if plat.PETSCII
                expected = $50
            if txt.getclr(col, 0) != expected or txt.getclr(col, 59) != expected
                fixed_rows = false
        }
        txt.plot(13, 22)
        plat.clear_row(22)
        bool position = txt.get_column() == 13 and txt.get_row() == 22
        tap.ok(canvas, "canvas initializes every visible color cell including all four edges")
        tap.ok(up, "scroll up copies character and color at left edge")
        tap.ok(up_last, "scroll up includes final viewport column")
        tap.ok(bottom, "scroll clears exposed bottom row with frontend palette")
        tap.ok(down, "scroll down copies character and color at left edge")
        tap.ok(down_last, "scroll down includes final viewport column")
        tap.ok(insert, "insert-row scroll uses byte-aligned cell addresses")
        tap.ok(clear, "row clear covers final column without wrapping")
        tap.ok(edges, "scroll and row clear preserve VTUI green surround and black frame")
        tap.ok(fixed_rows, "scroll leaves top and bottom chrome in place")
        tap.ok(position, "row clear preserves logical cursor position")
        tap.done()
    }
}
