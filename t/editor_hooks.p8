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
