; Test-only adapter: select the production buffer's portable scan paths.
; Assembly helpers must never be called in these VM tests.
%import textio
%import syslib
fastmem {
    const bool FAST = false
    sub unexpected() {
        txt.print("Bail out! VM test called an assembly-only fastmem helper\n")
        sys.exit(1)
    }
    sub find(uword p, uword n, ubyte value) -> uword {
        unexpected()
        return n
    }
    sub find_back(uword p, uword n, ubyte value) -> uword {
        unexpected()
        return $ffff
    }
    sub count(uword p, uword n, ubyte value) -> uword {
        unexpected()
        return 0
    }
}
