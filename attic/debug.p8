%import textio

; from good guy gillham - https://github.com/gillham/prog8libs/tree/main/assert

monitor {
    sub open() {
        %asm {{
            brk
        }}
    }
}

debug {
    const ubyte EQ = 1
    const ubyte NE = 2
    const ubyte GT = 3
    const ubyte GE = 4
    const ubyte LT = 5
    const ubyte LE = 6

    sub assert(uword one, uword two, ubyte check, str msg) -> bool {
        when check {
            EQ -> if one == two return true
            NE -> if one != two return true
            GT -> if one > two return true
            GE -> if one >= two return true
            LT -> if one < two return true
            LE -> if one <= two return true
            else -> {
                txt.print("\ninvalid assert check\n")
            }
        }
        txt.print("\nassert failure: ")
        txt.print_uwhex(one, true)
        when check {
            EQ -> txt.print(" == ")
            NE -> txt.print(" != ")
            GT -> txt.print(" > ")
            GE -> txt.print(" >= ")
            LT -> txt.print(" < ")
            LE -> txt.print(" <= ")
        }
        txt.print_uwhex(two, true)
        txt.nl()
        txt.print(msg)
        txt.nl()
        txt.print("halting. use the debugger.")
        txt.print("\npress 'm' for monitor. any other continues\n")
        if txt.waitkey() != 'm' return false
        monitor.open()
        repeat {}
    }
}
