%encoding iso
%import diskio
%import conv
%import strings
; TAP goes to VICE's temporary filesystem device, not the C64 screen.
tap {
    uword number = 0
    bool failed = false
    sub stop(ubyte code) {
        @($d7ff) = code
        repeat {}
    }
    sub emit(str text) {
        if not diskio.f_write(text as uword, strings.length(text))
            stop(2)
    }
    sub ok(bool passed, str name) {
        if number == 0 {
            diskio.drivenumber = 8
            if not diskio.f_open_w(petscii:"tap.out")
                stop(2)
        }
        number++
        if not passed {
            failed = true
            emit("not ")
        }
        emit("ok ")
        emit(conv.str_uw(number))
        emit(" - ")
        emit(name)
        emit("\x0a")
    }
    sub done() {
        emit("1..")
        emit(conv.str_uw(number))
        emit("\x0a")
        diskio.f_close_w()
        if failed
            stop(1)
        stop(0)
    }
}
