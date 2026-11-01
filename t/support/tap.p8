%import textio
tap {
    uword number = 0
    sub ok(bool passed, str name) {
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
    }
}
