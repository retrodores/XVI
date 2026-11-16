; Bounded VERA text operations. Coordinates are cells, addresses are bytes.
%import textio
x16screen {
    sub fill(ubyte col, ubyte row, ubyte width, ubyte character, ubyte colors) {
        cx16.vaddr(msw(txt.VERA_TEXTMATRIX), lsw(txt.VERA_TEXTMATRIX) + 256*row + 2*(col as uword), 0, 1)
        repeat width {
            cx16.VERA_DATA0 = character
            cx16.VERA_DATA0 = colors
        }
    }
    sub copy_row(ubyte source, ubyte dest, ubyte col, ubyte width) {
        cx16.vaddr(msw(txt.VERA_TEXTMATRIX), lsw(txt.VERA_TEXTMATRIX) + 256*source + 2*(col as uword), 0, 1)
        cx16.vaddr(msw(txt.VERA_TEXTMATRIX), lsw(txt.VERA_TEXTMATRIX) + 256*dest + 2*(col as uword), 1, 1)
        repeat width {
            cx16.VERA_DATA1 = cx16.VERA_DATA0
            cx16.VERA_DATA1 = cx16.VERA_DATA0
        }
    }
}
