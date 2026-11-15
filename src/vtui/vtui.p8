%import textio
vtui $8800 {
    %option no_symbol_prefixing
    %asmbinary "src/vtui/VTUI.BIN", 2     ; skip the 2 dummy load address bytes
    ; This bundled relocatable binary is initialized at $8800. Call once per load.
    ; Stable jump-table ABI for the maintained VTUI variant; see docs/VTUI-INTERFACE.md.
    extsub $8800 = initialize() clobbers(A, X, Y)
    extsub $8802 = screen_set(ubyte mode @A) clobbers(A, X, Y)
    extsub $8805 = set_bank(bool bank1 @Pc) clobbers(A)
    extsub $8808 = set_stride(ubyte stride @A) clobbers(A)
    extsub $880b = set_decr(bool incrdecr @Pc) clobbers(A)
    extsub $880e = clr_scr(ubyte char @A, ubyte colors @X) clobbers(Y)
    extsub $8811 = gotoxy(ubyte column @A, ubyte row @Y)
    extsub $8814 = plot_char(ubyte char @A, ubyte colors @X)
    extsub $8817 = scan_char() -> uword @AX
    extsub $881a = hline(ubyte char @A, ubyte length @Y, ubyte colors @X) clobbers(A)
    extsub $881d = vline(ubyte char @A, ubyte height @Y, ubyte colors @X) clobbers(A)
    extsub $8820 = print_str(str txtstring @R0, ubyte length @Y, ubyte colors @X, ubyte convertchars @A) clobbers(A, Y)
    extsub $8823 = fill_box(ubyte char @A, ubyte width @R1, ubyte height @R2, ubyte colors @X) clobbers(A, Y)
    extsub $8826 = pet2scr(ubyte char @A) -> ubyte @A
    extsub $8829 = scr2pet(ubyte char @A) -> ubyte @A
    extsub $882c = border(ubyte mode @A, ubyte width @R1, ubyte height @R2, ubyte colors @X) clobbers(Y)              ; NOTE: mode 6 means 'custom' characters taken from r3 - r6
    extsub $882f = save_rect(ubyte ramtype @A, bool vbank1 @Pc, uword address @R0, ubyte width @R1, ubyte height @R2) clobbers(A, X, Y)
    extsub $8832 = rest_rect(ubyte ramtype @A, bool vbank1 @Pc, uword address @R0, ubyte width @R1, ubyte height @R2) clobbers(A, X, Y)
    extsub $8835 = input_str(uword buffer @R0, ubyte buflen @Y, ubyte colors @X) clobbers (A) -> ubyte @Y             ; NOTE: returns string length
    extsub $8835 = input_str_lastkey(uword buffer @R0, ubyte buflen @Y, ubyte colors @X) clobbers (Y) -> ubyte @A     ; NOTE: returns lastkey press
    extsub $8835 = input_str_retboth(uword buffer @R0, ubyte buflen @Y, ubyte colors @X) clobbers () -> uword @AY     ; NOTE: returns lastkey press, string length
    extsub $8838 = get_bank() clobbers (A) -> bool @Pc
    extsub $883b = get_stride() -> ubyte @A
    extsub $883e = get_decr() clobbers (A) -> bool @Pc
    sub print_str2(str text, ubyte colors, bool convertchars) {
        ubyte n = 0
        while text[n] != 0 and n != 255
            n++
        ubyte convert = 0
        if not convertchars
            convert = $80
        print_str(text, n, colors, convert)
    }
}
