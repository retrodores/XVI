%zeropage basicsafe
%option no_sysinit
%encoding iso

%import textio
%import strings
%import conv
%import syslib
%import diskio

main {
  sub start() {
    txt.iso()
    txt.print("Name of ISO file you wish to convert? ")
    str inputfile = " " * 60
    str outputfile = " " * 60
    if txt.input_chars(inputfile) != 0 {
      strings.strip(inputfile)
      if diskio.exists(inputfile) {
        txt.nl()
        txt.print("file found!")
        txt.nl()
        txt.print("Name of PETSCII file you wish to write? ")
        if txt.input_chars(outputfile) != 0 {
          strings.strip(outputfile)
          if diskio.exists(outputfile) {
            txt.nl()
            txt.print("Warning, output file exists!")
            sys.exit(0)
          }
          txt.nl()
          txt.print("Converting ISO file to PETSCII file ...")
        }
      }
    }
  }

  uword MaxLength = 76
  uword lineCount = 0

  sub load_file(str filepath) -> bool {
    strings.strip(filepath)

    ubyte idx   = 0
    READFILE:
    cbm.CLEARST() ; set so READST() is initially known to be clear
    if diskio.f_open(filepath) {
      while cbm.READST() == 0 {
        ;; reset these buffers
        str lineBuffer  = " " * (MaxLength + 1)
        ; read line
        ubyte length
        length, void = diskio.f_readline(lineBuffer)

        ; normalize line ending + whitespace
        strings.rstrip(lineBuffer)

        ; sanitize to match Insert/Replace printable ISO policy
        ubyte i
        for i in 0 to MaxLength-1 {
          ubyte ch = lineBuffer[i]
          if ch == 0 {
            break
          }
          if ch < 32 or ch > 126 {
            lineBuffer[i] = $20
          }
        }

;
; do conversion and saving in the next section
;

        main.lineCount++
      }
      diskio.f_close()
    }
    return true
  }
}

txt {
  %option merge

  ; from a commit in master
  sub iso2petscii(ubyte iso_char) -> ubyte {
    ; --converts iso 8859-15 character to petscii character (lowercase)
    if iso_char & $7f <= $20
      return petscii:' '  ; whitspace

    if iso_char <= $3f
      return iso_char  ; numbers and symbols

    if iso_char < $80
      return translate40to7F[iso_char-$40]

    return translateA0toFF[iso_char-$a0]

    ubyte[$40] translate40to7F = [
      $40, $c1, $c2, $c3, $c4, $c5, $c6, $c7, $c8, $c9, $ca, $cb, $cc, $cd, $ce, $cf,
      $d0, $d1, $d2, $d3, $d4, $d5, $d6, $d7, $d8, $d9, $da, $5b, $3f, $5d, $5e, $e4,
      $27, $41, $42, $43, $44, $45, $46, $47, $48, $49, $4a, $4b, $4c, $4d, $4e, $4f,
      $50, $51, $52, $53, $54, $55, $56, $57, $58, $59, $5a, $f3, $7d, $eb, $3f, $3f,
    ]
    ubyte[$60] translateA0toFF = [
      $20, $21, $20, $5c, $c5, $d9, $3f, $3f, $3f, $c3, $3f, $28, $3f, $3f, $d2, $e3,
      $3f, $3f, $32, $33, $3f, $3f, $ff, $3f, $3f, $31, $3f, $3e, $3f, $3f, $d9, $3f,
      $c1, $c1, $c1, $c1, $c1, $c1, $c1, $c3, $c5, $c5, $c5, $c5, $c9, $c9, $c9, $c9,
      $c4, $ce, $cf, $cf, $cf, $cf, $cf, $58, $cf, $d5, $d5, $d5, $d5, $d9, $3f, $53,
      $41, $41, $41, $41, $41, $41, $41, $43, $45, $45, $45, $45, $49, $49, $49, $49,
      $4f, $4e, $4f, $4f, $4f, $4f, $4f, $3f, $4f, $55, $55, $55, $55, $59, $3f, $59,
    ]
  }
}
