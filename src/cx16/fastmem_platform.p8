; the text stores' byte scans and copies: in 6502 assembler (src/fastmem.p8)
%import fastmem

fastmem {
%option merge
    ; the stores use these routines (see fastmem.FAST in vic20)
    const bool FAST = true
}
