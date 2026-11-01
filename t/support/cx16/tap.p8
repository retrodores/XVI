%encoding iso
%import textio
tap {
    uword number = 0
    sub ok(bool passed, str name) {
        if number == 0 {
            txt.nl()
            txt.print("# TAP BEGIN")
            txt.nl()
        }
        number++
        if not passed
            txt.print("not ")
        txt.print("ok ")
        txt.print_uw(number)
        txt.print(" - ")
        txt.print(name)
        txt.nl()
    }
    sub done() {
        txt.print("1..")
        txt.print_uw(number)
        txt.nl()
        @($9fb4) = 0
        %asm {{ jmp $ffff }}
    }
}
