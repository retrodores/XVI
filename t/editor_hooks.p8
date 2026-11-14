; Link-only hooks referenced by the real X16 platform's unused UI routines.
; Document tests do not call splash/scroll UI. Fail if that boundary is crossed.
%import tap
main {
    %option merge
    sub say(str message) {
        tap.ok(false, "unexpected editor splash hook in document test")
    }
}
view {
    const ubyte TOP_LINE = 2
    const ubyte BOTTOM_LINE = 57
    const ubyte LEFT_MARGIN = 4
    uword CURR_TOP_LINE = 1
    str BLANK_ROW = " " * 80
    sub c() -> ubyte {
        tap.ok(false, "unexpected screen column hook in document test")
        return 0
    }
    sub r() -> ubyte {
        tap.ok(false, "unexpected screen row hook in document test")
        return 0
    }
}
