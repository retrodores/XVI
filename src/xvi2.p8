; BUGS:
; - dd bug
; -- 1. open a file, immediately jump to the botton
; -- 2. add a few lines at the bottom with 'o', typing some
; -- 3. hit <esc>, then do "dd"

; TODO:
; - add 'dG' for (gillham)
; - isolate remaining cursor issues
; - get rid of full screen redraw with "dd"
; - implement a proper commandline parser
; - add fast "scroll_down" on in 'R' and hit 'enter' (currently way to slow
; -- when it hits draw_screen() on new buffer)
; - :set number / :set nonumber (turns line numbers on/off)

; ONGOING:
; - regression testing

; FUTURE TODO:
; - ":/" (requested by Sam)
; - allow many more lines (convert Line to use str instead permanent line)
; - do not write contiguous spaces (fully blank line, trim when writing)
; -- this might be an optimization that is needed when we increase line
; -- support > 140
; - stack based "undo" (p/P, o/O, dd)
; - fast "save_line_buffer"

; DONE:
; - verify as part of that, "~" is not present at the start in some cases, fix that
; - wq! - force save, force save and quit
; - add checks around wq, wq! (buffer, first command?)
; See CHANGELOG for the rest

%zeropage basicsafe
%option no_sysinit
%encoding iso

%import textio
%import strings
%import conv
%import syslib
%import diskio
%import debug
;;; %import messages

mode {
  const ubyte INIT            = 0
  const ubyte NAV             = 1  ; modal state for navigation, default state
  const ubyte INSERT          = 2  ; modal state for insert mode, triggered with ctrl-i
  const ubyte REPLACE         = 3  ; modal state for replacement mode, triggered with ctrl-r
  const ubyte COMMAND         = 4  ; modal state for entering a command
}

flags {
  ; display flags
  bool        UNSAVED         = false
  bool        VERBOSE_STATUS  = false
  bool        FIRST_COMMAND   = true
}

view {
  const ubyte LEFT_MARGIN     = 4
  const ubyte RIGHT_MARGIN    = 79
  const ubyte HEIGHT          = 56 ; absolute height of the edit/view area
  const ubyte TOP_LINE        = 2  ; row+1 of the first line of the document (FIRST_LINE_IDX)
  const ubyte MIDDLE_LINE     = 27
  const ubyte BOTTOM_LINE     = 57 ; row+1 of the last line of the view port (LAST_LINE_IDX)
  const ubyte FOOTER_LINE     = 59
  str         BLANK_LINE79    = " " * 79
  str         BLANK_LINE76    = " " * 76
  uword       CURR_TOP_LINE   = 1  ; tracks which actual doc line is at TOP_LINE
  uword[main.MaxLines] INDEX       ; Line to address look up
  uword       CLIPBOARD       = 0  ; holds the address of the current line we can "paste"

  sub r() -> ubyte {
    return txt.get_row()
  }

  sub c() -> ubyte {
    return txt.get_column()
  }

  sub insert_line_before (uword new_addr, uword curr_line, uword lineCount) -> uword {
    uword newLineCount = lineCount + 1    ; new line count
    uword curr_idx     = curr_line - 1    ; array index in view.INDEX to put the new line addres
    uword last_idx     = newLineCount - 1 ; idx of the last line in the document

    uword i
    ; Note: the range decrements by 1 from last_idx to the idx right before new_idx,
    ; which is new_idx+1, since we're decrementing; ensures old contents in new_idx
    ; get copied into the slot 'below' it ...
    for i in last_idx downto curr_idx+1 step -1 {
      ubyte idx = i as ubyte
      view.INDEX[idx] = view.INDEX[idx-1]
    }

    ; finally, insert new address into the new_idx slot
    view.INDEX[curr_idx as ubyte] = new_addr

    return newLineCount
  }

  sub insert_line_after (uword new_addr, uword curr_line, uword lineCount) -> uword {
    uword next_line    = curr_line + 1    ; next line number
    uword newLineCount = lineCount + 1    ; new line count
    uword new_idx      = next_line - 1    ; array index in view.INDEX to put the new line addres
    uword last_idx     = newLineCount - 1 ; idx of the last line in the document

    uword i
    ; Note: the range decrements by 1 from last_idx to the idx right before new_idx,
    ; which is new_idx+1, since we're decrementing; ensures old contents in new_idx
    ; get copied into the slot 'below' it ...
    for i in last_idx downto new_idx+1 step -1 {
      ubyte idx = i as ubyte
      view.INDEX[idx] = view.INDEX[idx-1]
    }

    ; finally, insert new address into the new_idx slot
    view.INDEX[new_idx as ubyte] = new_addr

    return newLineCount
  }

  sub delete_item (uword curr_line, uword lineCount) -> uword {
    uword newLineCount = lineCount - 1
    uword i
    for i in curr_line-1 to newLineCount {
      ubyte idx = i as ubyte
      view.INDEX[idx] = view.INDEX[idx + 1]
    }
    return newLineCount
  }
}

cursor {
  ubyte saved_char

  sub save_char(ubyte c, ubyte r) {
    saved_char = txt.getchr(c,r)
  }

  sub save_current_char(ubyte c, ubyte r) {
    save_char(c,r)
  }

  sub restore_current_char() {
    ubyte c = view.c()
    ubyte r = view.r()
    txt.plot(c,r)
    if saved_char == $22 {
      cbm.CHROUT($80)
    }
    txt.chrout(saved_char)
    txt.plot(c,r)
  }

  sub hide() {
    restore_current_char()
    saved_char = $20
  }

  ; the cursor is the underlying character, with the color scheme inverted
  sub place(ubyte new_c, ubyte new_r) {
    restore_current_char()  ;; restore char in current cursor location
    txt.plot(new_c,new_r)   ;; move cursor to new location
    save_current_char(new_c, new_r)     ;; save char in the current location (here, the new c,r)
    if saved_char == $22 {
      cbm.CHROUT($80)
    }
    txt.chrout(saved_char)
    txt.setclr(new_c,new_r,$16) ; inverses color
    txt.plot(new_c,new_r)   ;; move cursor back after txt.chrout advances cursor
  }

  ; the cursor is the underlying character, with the color scheme inverted
  sub replace(ubyte new_c, ubyte new_r) {
    save_current_char(new_c, new_r)     ;; save char in the current location (here, the new c,r)
    txt.setclr(new_c,new_r,$16) ; inverses color
    txt.plot(new_c,new_r)   ;; move cursor back after txt.chrout advances cursor
  }

}

command {
  str cmdBuffer = " " * 60
  ubyte col, row

  sub prompt () {
    ubyte cmdchar
   cursor.hide()
    void strings.copy(" " * 60, cmdBuffer)
    txt.plot(0, view.FOOTER_LINE) ; move cursor to the starting position for writing
    main.prints(view.BLANK_LINE79)
    txt.plot(0, view.FOOTER_LINE)
    txt.print(":")
  CMDINPUT:
    void, cmdchar = cbm.GETIN()
    if cmdchar != $0d { ; any character now but <ENTER>
      if cmdchar == $22 {
        cbm.CHROUT($80)
      }
      txt.chrout(cmdchar)
    }
    else {
      ; reads in the command and puts it into view.cmdBuffer for additional
      ; processing in the view code
      ubyte i
      for i in 0 to strings.length(cmdBuffer) - 1 {
        cmdBuffer[i] = txt.getchr(i+1, view.FOOTER_LINE)
      }
      strings.strip(command.cmdBuffer)
      return;
    }
    goto CMDINPUT
  }

  sub process() {
    ubyte cmd_offset = 1
    bool force = false

    col = view.c()
    row = view.r()

    if command.cmdBuffer[1] == $21 { ; $21 is "!"
      force = true
      cmd_offset = 2
    }

    ; parse out file name (everything after ":N")
    str cmd = " " * 60
    ubyte cmd_length = strings.copy(command.cmdBuffer, cmd)
    str fn1 = " " * 60

    strings.slice(cmd, cmd_offset, cmd_length-cmd_offset, fn1) ; <- somehow this is affecting main.lineCount ...
    strings.strip(fn1) ; prep filename

    ; catch wq, wq!
    if cmd_length <= 4 and strings.compare(cmd, "wq") == 0 or strings.compare(cmd, "wq!") == 0 {
      main.save_current_file() 
      txt.clear_screenchars($20)
      txt.iso_off()
      sys.exit(0)
    }

    when command.cmdBuffer[0] {
      'e' -> {
        if flags.FIRST_COMMAND == false and flags.UNSAVED == true and not force {
          main.warn("Unsaved changes exist.")
          return ; jumps back to caller
        }
        flags.FIRST_COMMAND = false
        if strings.length(fn1) > 0 {
          if ( main.load_file(fn1) ) {
            flags.UNSAVED = false
            view.CURR_TOP_LINE = 1
            main.MODE = mode.NAV
            main.draw_screen()
            main.toggle_nav()
            cursor.place(view.LEFT_MARGIN, view.TOP_LINE)
            main.update_tracker()
            goto main.start.NAVCHARLOOP  ; start main loop
          }
          ; even if ":e! non-existent-file", do not replace current content with empty buffer
          else if flags.UNSAVED == true {
            cursor.place(view.c(), view.r())
            main.update_tracker()
            goto main.start.NAVCHARLOOP  ; start main loop
          }
        }
        main.init_empty_buffer(1)
        main.start.char = 'R'
        flags.UNSAVED = true
        main.toggle_nav()
        cursor.place(view.LEFT_MARGIN, view.TOP_LINE)
        main.update_tracker()
        goto main.start.SKIP_NAVCHARLOOP ; will process 'R' and start in REPLACE mode
      }
      'q' -> {
        if flags.UNSAVED == true and not force {
          main.warn("Unsaved changes exist. Use q! to override ...")
          return
        }
        else {
          txt.clear_screenchars($20)
          txt.iso_off()
          sys.exit(0)
        }
      }
      'w' -> {
        if flags.FIRST_COMMAND == true and flags.UNSAVED == false and not force {
          main.warn("Nothing to save!")
          goto main.start.FIRST_OPEN  ; start main loop
          return
        }
        flags.FIRST_COMMAND = false
        ; 'w' is for "write" - fn1 is the filename
        if strings.length(fn1) > 0 {
          if diskio.exists(fn1) and not force {
            main.warn("File Exists. Use w! to override ...")
          }
          else {
            diskio.delete(fn1)
            main.save_as(fn1)
            void strings.copy(fn1, main.doc.filepath)
          }
        }
        else {
          ; GUARD: refuse :w with no name on a new buffer
          str cur = " " * 60
          void strings.copy(main.doc.filepath, cur)
          strings.trim(cur)
          if strings.length(cur) == 0 {
           main.warn("No filename. Use :w filename")
          }
          else {
            main.save_current_file()
          }
        }
      }
      else -> {
        cursor.place(view.LEFT_MARGIN, view.TOP_LINE)
        main.warn("Not an editor command!")
      }
    }
  }
}

main {
  ubyte MODE         = mode.NAV ; initial mode is NAV
  uword NAVCHARCOUNT = 0        ; the main "clock"
  uword lineCount

  struct Document {
    ubyte tabNum    ; 0
    ubyte charset   ; 0 = ISO, 1 = PETSCII
    ubyte startBank ; actual bank number for switching
    uword firstLine ; address of the first line of the document
    uword lineCount ; number of lines
    ^^ubyte filepath
    ubyte data00, data01, data02, data03, data04, data05, data06, data07
    ubyte data08, data09, data10, data11, data12, data13, data14, data15
    ubyte data16, data17, data18, data19, data20, data21, data22, data23
    ubyte data24, data25, data26, data27, data28, data29, data30, data31
    ubyte data32, data33, data34, data35, data36, data37, data38, data39
    ubyte data40, data41, data42, data43, data44, data45, data46, data47
    ubyte data48, data49, data50, data51, data52, data53, data54, data55
    ubyte data56, data57, data58, data59, data60, data61, data62, data63
    ubyte data64, data65, data66, data67, data68, data69, data70, data71
    ubyte data72, data73, data74, data75, data76, data77, data78, data79
    ubyte nullbyte
  }

  struct Line {
    ^^Line prev
    ^^Line next
    ^^ubyte text
    ubyte data00, data01, data02, data03, data04, data05, data06, data07
    ubyte data08, data09, data10, data11, data12, data13, data14, data15
    ubyte data16, data17, data18, data19, data20, data21, data22, data23
    ubyte data24, data25, data26, data27, data28, data29, data30, data31
    ubyte data32, data33, data34, data35, data36, data37, data38, data39
    ubyte data40, data41, data42, data43, data44, data45, data46, data47
    ubyte data48, data49, data50, data51, data52, data53, data54, data55
    ubyte data56, data57, data58, data59, data60, data61, data62, data63
    ubyte data64, data65, data66, data67, data68, data69, data70, data71
    ubyte data72, data73, data74, data75, nullbyte
  }

  ^^Document doc

  const uword MaxLength  = 76
  const uword LineSize   = sizeof(Line)

  const uword MaxLines   = 256
  const uword BufferSize = MaxLines * LineSize
  uword Buffer           = memory("Buffer", BufferSize, 1)

  ^^Line next = Buffer
  ^^Line head = 0 ; points to first line
  ^^Line tail = 0 ; points to last line

  ; Allocator for linked list of Line instances contributed
  ; by MarkTheStrange on #prog8-dev
  sub allocLine(^^ubyte initial) -> ^^Line {
    ^^Line this = next                   ; return next space
    ; don't run past end of Buffer
    if next > (Buffer+BufferSize-LineSize) return $0000
    next += 1                            ; advance by sizeof struct
    ; link the new line in
    if head == 0 {
        head = this
    } else {
        tail.next = this
    }

    ; populate the fields
    this.prev = tail
    this.next = 0
    this.text = &this.data00            ; text buffer embedded in struct
    void strings.copy(initial, this.text)
    @(this.text + MaxLength) = 0         ; null terminate

    tail = this
    ; and return
    return this
  }

  sub allocNewLine(^^ubyte initial) -> ^^Line {
    ^^Line this = next                   ; return next space
    ; don't run past end of Buffer
    if next > (Buffer+BufferSize-LineSize) return $0000
    next += 1                            ; advance by sizeof struct
    ; populate the fields
    this.prev = 0
    this.next = 0
    this.text = &this.data00            ; text buffer embedded in struct
    strings.rstrip(initial)
    void strings.copy(view.BLANK_LINE79, this.text) ; initialize with BLANK_LINE79, eliminates random garbage
    void strings.copy(initial, this.text); then add text
    @(this.text + MaxLength) = 0         ; null terminate
    return this
  }

  sub freeAll() {
    next = Buffer
    sys.memset(next, BufferSize, 0)
  }

  ; initiates initial buffer without a file, jumps to REPLACEMODE
  ; so user can start typing right away
  sub init_empty_buffer(ubyte lines) {
    freeAll()
    txt.plot(view.LEFT_MARGIN, view.TOP_LINE)
    flags.UNSAVED = false
    main.lineCount = 0

    ubyte idx   = 0
    str lineBuffer  = " " * (MaxLength + 1)

    repeat lines {
      uword lineAddr = allocLine(lineBuffer)
      idx = main.lineCount as ubyte
      view.INDEX[idx] = lineAddr
      main.lineCount++
    }
    flags.UNSAVED = true
    main.draw_screen()
    cursor.place(view.LEFT_MARGIN, view.TOP_LINE)
    main.printLineNum(1)
  }

  sub load_file(str filepath) -> bool {
    strings.strip(filepath)
    txt.plot(view.LEFT_MARGIN, view.TOP_LINE)

    if not diskio.exists(filepath) {
      warn("File does not exist!")
      return false
    }

    info("Loading file ...")

    ; only do this if file wanted is found
    freeAll()

    flags.UNSAVED = false
    main.lineCount = 0

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

        ; enforce max length AFTER sanitizing
        if length > MaxLength {
          str tmp = " " * (MaxLength + 1)
          strings.slice(lineBuffer, 0, MaxLength, tmp)
          void strings.copy(tmp, lineBuffer)
        }

        uword lineAddr = allocLine(lineBuffer)
        ; out of memory == $0000, stop reading.
        if lineAddr == $0000 {
            warn("File too big!")
            break
        }
        idx = main.lineCount as ubyte
        view.INDEX[idx] = lineAddr
        main.lineCount++
      }
      diskio.f_close()
      txt.clear_screen()
      void strings.copy(filepath,doc.filepath)
    }
    else {
      diskio.f_close()
      warn("Can't open file!")
      return false
    }
    return true
  }

  sub splash() {
    txt.clear_screen()
    txt.plot(0,view.TOP_LINE)
    init_empty_buffer(1)
    repeat 20 {
      txt.plot(0, txt.get_row())
      say("~    ")
    }
    say("~                             XVI - Commander X16 Vi               ")
    say("~                                                                  ")
    say("~                             version 2.0 pre-ALPHA                ")
    say("~                                                                  ")
    say("~                             by Brett Estrade et al.              ")
    say("~                                                                  ")
    say("~                    XVI is open source and freely distributable   ")
    say("~                                                                  ")
    say("~                             Sponsor Prog8 development!           ")
    say("~                                  http://p8ug.org                 ")
    say("~                                                                  ")
    say("~                  type  <esc>R to open new buffer in Replace mode ")
    say("~                  type  <esc>i to open new buffer in Insert  mode ")
    say("~                  type  :e filepath<Enter>    to load file to edit")
    say("~                  type  :q<Enter>             to exit             ")
    repeat 21 {
      txt.plot(0, txt.get_row())
      say("~    ")
    }
  }

  sub clear_splash() {
    txt.clear_screen()
    txt.plot(0,view.TOP_LINE+1)
    repeat 55 {
      txt.plot(0, txt.get_row())
      say("~    ")
    }
    txt.plot(view.LEFT_MARGIN, view.TOP_LINE)
    cursor.place(view.LEFT_MARGIN, view.TOP_LINE)
  }

  sub save_current_file() {
     str oldback = " " * 60
     void strings.copy(doc.filepath,oldback)
     strings.trim(oldback)

     ; GUARD: new/unnamed buffer
     if strings.length(oldback) == 0 {
       warn("No filename. Use :w filename")
       return
     }

     void strings.append(oldback, ".swp") ; basically vi's .swp file
     if diskio.exists(oldback) {
       diskio.delete(oldback)
     }
     diskio.rename(doc.filepath, oldback)
     save_as(doc.filepath)
     diskio.delete(oldback)
  }

  ; Safe save: never dereference line when it becomes 0
  sub save_as(str filepath) {
    info_noblock("saving ...")

    ubyte i
    ubyte ub
    const ubyte maxLen = main.MaxLength

    void diskio.f_open_w_seek(filepath)

    if main.lineCount == 0 {
      diskio.f_close_w()
      flags.UNSAVED = false
      info_noblock("          ")
      return
    }

    str writeBuffer = " " * maxLen
    ^^Line line = view.INDEX[0]

    while line != 0 {
      ; prepare this line
      void strings.copy(line.text, writeBuffer)
      strings.rstrip(writeBuffer)

      ; write only printable ISO bytes from the fixed-width line buffer
      for i in 0 to maxLen-1 {
        ub = writeBuffer[i]
        if ub == 0 {        ; stop at terminator
          break
        }
        if ub >= 32 and ub <= 126 {
          void diskio.f_write(&ub, 1)
        }
      }

      ; newline (LF)
      ub = $0a
      void diskio.f_write(&ub, 1)

      ; advance
      line = line.next
    }

    diskio.f_close_w()

    flags.UNSAVED     = false
    info_noblock("          ")
  }

  sub navchar_start() {
    main.NAVCHARCOUNT++
  }

  sub toggle_nav() {
    main.MODE = mode.NAV
    main.update_tracker()
  }

  sub start () {
    txt.iso()
    doc.tabNum               = 0 ; for future proofing
    doc.charset              = 0 ; for future proofing
    doc.startBank            = 1 ; for future proofing
    doc.firstLine            = Buffer
    doc.filepath             = " " * 80
    @(doc.filepath+80)       = 0

    main.lineCount            = 0
    main.MODE = mode.INIT

    sys.wait(20)

    ubyte char = 0
    ubyte col
    ubyte row

    ;txt.plot(0,1)
    ;cursor.place(view.LEFT_MARGIN, view.TOP_LINE)

    FIRST_OPEN: 
    flags.FIRST_COMMAND = true

    splash()

    ; this is the main loop
    NAVCHARLOOP:
      void, char = cbm.GETIN()

    SKIP_NAVCHARLOOP:               ; jump to here to skip input

      navchar_start()               ; event hook

      if char == $00 {
        goto NAVCHARLOOP
      }

      col = view.c()
      row = view.r()

      ; On splash/INIT: treat ESC as a prefix so ESC+R / ESC+i is instant.
      if main.MODE == mode.INIT {
        when char {
          'R','i','a' -> {
            toggle_nav()
            flags.UNSAVED = true
            main.clear_splash()
            main.printLineNum(1)
            main.update_tracker()
          }
          ':'  -> {
            flags.FIRST_COMMAND = true
            command.prompt()        ; populates command.cmdBuffer
            goto PROCESS_COMMAND
          }
        }

        ; "goto" dispatcher on edit or command modes
        when char {
          'R'  -> { goto RLOOP2 }
          'i'  -> { goto ILOOP  }
          'a'  -> { goto ILOOP  }
        }
        goto NAVCHARLOOP
      }

      when char {
        $07 -> {
          if flags.VERBOSE_STATUS == true {
            flags.VERBOSE_STATUS = false
          }
          else {
            flags.VERBOSE_STATUS = true
          }
          main.update_tracker()
        }
        ':' -> {                         ; command line
          if main.MODE == mode.NAV {
            command.prompt()             ; populates command.cmdBuffer

            PROCESS_COMMAND:
            ; clear command line
            txt.plot(0, view.FOOTER_LINE)
            prints(view.BLANK_LINE79)
            main.update_tracker()
            command.process()
          }

          ;debug.assert(main.lineCount, 93, debug.EQ, "ln 515 ... main.lineCount == 93")
          toggle_nav()
          cursor.replace(col, row)
          main.update_tracker()
        }
        'D' -> {
          if main.MODE == mode.NAV {
            main.clear_current_line()
          }
        }
        'd' -> {
          if main.MODE == mode.NAV {
            DDLOOP:
            void, char = cbm.GETIN()
            when char {
              $1b -> {       ; ESC key, throw into NAV mode from any other mode
                toggle_nav()
                goto NAVCHARLOOP
              }
              'd' -> {
                main.do_dd()
                goto NAVCHARLOOP
              }
            }
            goto DDLOOP
          }
        }
        'O' -> {
          if main.MODE == mode.NAV {
            main.insert_line_above()
            goto RLOOP2 ; REPLACE mode, start editing blank line immediately
          }
        }
        'o' -> {
          if main.MODE == mode.NAV {
            main.insert_line_below()
            goto RLOOP2 ; REPLACE mode, start editing blank line immediately
          }
        }
        'Y' -> {
          main.do_yy()
          goto NAVCHARLOOP
        }
        'y' -> {
          if main.MODE == mode.NAV {
            YYLOOP:
            void, char = cbm.GETIN()
            when char {
              $1b -> {       ; ESC key, throw into NAV mode from any other mode
                toggle_nav()
                goto NAVCHARLOOP
              }
              'y' -> {
                main.do_yy()
                goto NAVCHARLOOP
              }
            }
            goto YYLOOP
          }
        }
        'Z' -> {
          if main.MODE == mode.NAV {
            ; make sure we're not use editing a buffer
            if @(doc.filepath+1) == $20 {
              warn("No filename. Use :w filename")
              goto NAVCHARLOOP
            }
            ZZLOOP:
            void, char = cbm.GETIN()
            if char == $00 {
              goto ZZLOOP
            }
            when char {
             $1b -> {       ; ESC key, throw into NAV mode from any other mode
               toggle_nav()
               goto NAVCHARLOOP
             }
             'Z' -> {
                save_current_file()
                txt.clear_screenchars($20)
                txt.iso_off()
                sys.exit(0)
              }
            }
          }
        }
        'P' -> {
          if main.MODE == mode.NAV {
            main.paste_line_above()
          }
        }
        'p' -> {
          if main.MODE == mode.NAV {
            main.paste_line_below()
          }
        }

        ; E D I T I N G
        'r' -> { ; replace char
          if main.MODE == mode.NAV {
            RLOOP1:
            void, char = cbm.GETIN()
            ; go back to RLOOP1 if there's nothing input via keyboard
            if char == $00 {
              goto RLOOP1
            }
            when char {
              $1b -> {       ; ESC key, throw into NAV mode from any other mode
                toggle_nav()
                goto NAVCHARLOOP
              }
              else -> {
                goto REPLACECHAR
              }
            }
            goto RLOOP1
            REPLACECHAR:
            main.replace_char(char)
          }
        }
        'x', $7f -> {  ; delete char, shift left - 'x' and $7 (backspace in NAV mode)
          if main.MODE == mode.NAV {
            main.delete_xy_shift_left()
          }
        }
        's' -> {
          if main.MODE == mode.NAV {
            main.MODE = mode.INSERT
            main.update_tracker()
            main.insert_char_shift_right($20) ; initially just adds space, then drop to 'R'
            main.MODE = mode.NAV
            main.update_tracker()
          }
        }
        'a','i' -> { ; append after cursor (vim-like)
          if main.MODE == mode.NAV {
            ISTART:
            ; move one char right before inserting (append-after-cursor)
            ubyte ac = view.c()
            ubyte ar = view.r()
            if ac < view.LEFT_MARGIN {
              ac = view.LEFT_MARGIN
            }
            if ac < view.RIGHT_MARGIN-1 {
              if char == 'a' {
                cursor.place(ac+1, ar)
              }
              else if char == 'i' {
                cursor.place(ac, ar)
              }
            }
            else {
              cursor.place(view.RIGHT_MARGIN-1, ar)
            }

            main.MODE = mode.INSERT
            main.update_tracker()

            ILOOP:
            main.MODE = mode.INSERT
            void, char = cbm.GETIN()
            if char == $00 {
              goto ILOOP
            }

            when char {
              $1b -> {       ; <esc>
                toggle_nav()
                main.save_line_buffer()
                goto NAVCHARLOOP
              }
              $0d -> {       ; <return> == esc + 'o'
                toggle_nav()
                main.save_line_buffer()
                char = $6f ; 'o'
                goto SKIP_NAVCHARLOOP
              }
              $14, $08, $7f -> {  ; backspace variants (DEL/BS)
                goto IBACKSPACE
              }
              else -> {
                ; only accept printable ISO range
                if char < 32 or char > 126 {
                  goto ILOOP
                }
                goto IINSERTCHAR
              }
            }
            goto ILOOP

            IBACKSPACE:
            ; delete char to the left (vim-ish insert backspace)
            if view.c() <= view.LEFT_MARGIN {
              ; this preserves the behavior of vim when in insert mode
              ; and hitting backspace, runs into the left margin, nothing
              ; is done
              goto ILOOP
            }
            cursor.saved_char = $20
            cursor.restore_current_char();
            txt.plot(view.c()-1, view.r())
            cursor.place(view.c(), view.r())
            main.delete_xy_shift_left()
            main.update_tracker()
            goto ILOOP

            IINSERTCHAR:
            ; keep cursor within editable region
            if view.c() < view.LEFT_MARGIN {
              txt.plot(view.LEFT_MARGIN, view.r())
              cursor.place(view.c(),view.r())
              main.update_tracker()
              goto ILOOP
            }
            if view.c() == view.RIGHT_MARGIN {
              txt.plot(view.RIGHT_MARGIN-1, view.r())
              cursor.place(view.c(),view.r())
              main.update_tracker()
              goto ILOOP
            }
            main.insert_char_shift_right(char)
            cursor.place(view.c()+1,view.r())
            main.update_tracker()
            goto ILOOP
          }
        }
        'R' -> { ; replace mode
          if main.MODE == mode.NAV {
            main.MODE = mode.REPLACE
            main.update_tracker()

            RLOOP2:
            main.MODE = mode.REPLACE
            void, char = cbm.GETIN()
            if char == $00 {
              goto RLOOP2
            }

            when char {
              $1b -> {       ; <esc>
                toggle_nav()
                main.save_line_buffer()
                goto NAVCHARLOOP
              }
              $0d -> {       ; <return> == esc + 'o'
                toggle_nav()
                main.save_line_buffer()
                char = $6f ; 'o'
                goto SKIP_NAVCHARLOOP
              }
              $7f -> {                   ; <Delete> ($7f) in REPLACE mode acts like 'x' in NAV mode
                main.delete_xy_shift_left()
              }
              $9d, $14, $08 -> {         ; left arrow, backspace variants act like 'h' in NAV mode
                cursor_left_on_h()
              }
              else -> {
                ; only accept printable ISO range
                if char < 32 or char > 126 {
                  goto RLOOP2
                }
                ; clear quote mode before emitting a quote
                if char == $22 {
                  cbm.CHROUT($80)
                }
                flags.UNSAVED = true
                goto RPUTCHAR
              }
            }
            goto RLOOP2

            RPUTCHAR:
            if view.c() < view.LEFT_MARGIN {
              txt.plot(view.LEFT_MARGIN, view.r())
              cursor.place(view.c(),view.r())
              main.update_tracker()
              goto RLOOP2
            }
            else if view.c() == view.RIGHT_MARGIN {
              txt.plot(view.RIGHT_MARGIN-1, view.r())
              cursor.place(view.c(),view.r())
              main.update_tracker()
              goto RLOOP2
            }
            cursor.saved_char = txt.getchr(view.c()+1,view.r())
            cbm.CHROUT(char)
            flags.UNSAVED = true
            txt.plot(view.c(),view.r())
            cursor.place(view.c(),view.r())
            main.update_tracker()
            goto RLOOP2
          }
        }

        ; N A V I G A T I O N
        '^','0','I' -> { ; jump to start of line
          if main.MODE == mode.NAV {
            jump_to_left()
            if char == 'I' {
              char = 'i'
              goto ILOOP ; go now into insert mode
            }
          }
        }
        '$','A' -> { ; jump top end of line
          if main.MODE == mode.NAV {
            jump_to_right()
            if char == 'A' {
              char = 'a'
              goto ISTART ; go now into insert mode
            }
          }
        }
        '1' -> { ; 1G
          if main.MODE == mode.NAV {
            gLOOP:
            void, char = cbm.GETIN()
            when char {
              $1b -> {       ; ESC key, throw into NAV mode from any other mode
                toggle_nav()
                goto NAVCHARLOOP
              }
              'G' -> {
                jump_to_begin()
                goto NAVCHARLOOP
              }
            }
            goto gLOOP
          }
        }
        'g' -> {
          if main.MODE == mode.NAV {
            jump_to_begin()
          }
        }
        'G' -> {
          if main.MODE == mode.NAV {
            jump_to_end()
          }
        }
        'L' -> { ; redraw current screen
          if main.MODE == mode.NAV {
            ubyte c = view.c()
            ubyte r = view.r()
            draw_screen()
            txt.plot(c, r)
            cursor.replace(c, r)
            main.update_tracker()
          }
        }
        'k',$91 -> {       ;  UP
          if main.MODE == mode.NAV {
            cursor_up_on_k()
          }
        }
        'j', $11 -> {      ; DOWN
          if main.MODE == mode.NAV {
            cursor_down_on_j()
          }
        }
        'h', $9d, $14, $08 -> {     ; LEFT, h, left arrow, backspace variants (<Delete> acts like 'x')
          if main.MODE == mode.NAV {
            cursor_left_on_h()
          }
        }
        'l',$20,$1d -> {   ; RIGHT
          if main.MODE == mode.NAV {
            cursor_right_on_l()
          }
        }
        $06,$46 -> {  ; ctrl+f / shift+f
          if main.MODE == mode.NAV {
            page_forward()
          }
        }
        $02,$42 -> {  ; ctrl+b / shift+b
          if main.MODE == mode.NAV {
            page_backward()
          }
        }
      }
      goto NAVCHARLOOP
  }

  sub get_line_num(ubyte r) -> uword {
    const uword top = mkword(00,view.TOP_LINE)
    uword row       = mkword(00,r)
    uword curr_line = view.CURR_TOP_LINE + row - top
    return curr_line
  }

  sub get_Line_addr(ubyte r) -> uword {
    uword curr_line = main.get_line_num(r) ; 1-based
    ubyte idxw = (curr_line as ubyte) - 1  ; 0-based
    return view.INDEX[idxw]                ; only OK if you guarantee idxw <= 255
  }

  sub paste_line_above() {
    if view.CLIPBOARD == 0 {
      warn("Clipboard is empty ..")
      return
    }

    ubyte r = view.r()
    uword curr_line = main.get_line_num(r)

    ^^Line curr_addr = get_Line_addr(r)
    ^^Line old_prev  = 0
    ^^Line copy_addr = view.CLIPBOARD
    ^^Line new_prev  = main.allocNewLine(copy_addr.text)
    if new_prev == $0000 {
        warn("Out of memory!")
        return
    }

    if curr_line > 1 {
      old_prev = view.INDEX[(curr_line as ubyte) - 2]
    }

    new_prev.prev = old_prev
    new_prev.next = curr_addr

    curr_addr.prev = new_prev

    if old_prev != 0 {
      old_prev.next = new_prev
    }

    main.lineCount = view.insert_line_before(new_prev, curr_line, main.lineCount)

    void debug.assert(view.INDEX[curr_line as ubyte - 1], new_prev, debug.EQ, "INDEX[curr_line as ubyte - 1] == new_prev")
    void debug.assert(view.INDEX[curr_line as ubyte], curr_addr, debug.EQ, "INDEX[curr_line as ubyte] == curr_addr")

    flags.UNSAVED = true

    if r == view.TOP_LINE {
      draw_screen()
      txt.plot(view.LEFT_MARGIN, r)
      cursor.replace(view.LEFT_MARGIN, r)
    }
    else if r == view.BOTTOM_LINE {
      draw_screen()
      txt.plot(view.LEFT_MARGIN, r)
      cursor.replace(view.LEFT_MARGIN, r)
    }
    else {
      draw_screen()
      txt.plot(view.LEFT_MARGIN, r)
      cursor.replace(view.LEFT_MARGIN, r)
    }

    main.update_tracker()
  }

  sub paste_line_below() {
    if view.CLIPBOARD == 0 { ; indicates empty clipboard (nothing copied yet)
      warn("Clipboard is empty ..")
      return
    }

    ubyte r = view.r()

    uword curr_line = main.get_line_num(r) ; next_line is +1

    ^^Line curr_addr = get_Line_addr(r)        ; gets memory addr of current Line
    ^^Line copy_addr = view.CLIPBOARD
    ^^Line new_next  = main.allocNewLine(copy_addr.text) ; new line with text from copied address
    if new_next == $0000 {
        warn("Out of memory!")
        return
    }

    new_next.prev  = curr_addr
    new_next.next  = curr_addr.next
    curr_addr.next = new_next

    ;; call to update INDEX
    main.lineCount = view.insert_line_after(new_next, main.get_line_num(r), main.lineCount)

    ; need to assert new address got inserted into view.INDEX
    void debug.assert(view.INDEX[curr_line as ubyte - 1], curr_addr, debug.EQ, "INDEX[curr_line as ubyte - 1] == curr_addr")
    void debug.assert(view.INDEX[curr_line as ubyte], new_next, debug.EQ, "INDEX[curr_line as ubyte] == new_next")

    ;info("p ...")
    flags.UNSAVED = true

    if r == view.TOP_LINE {
      draw_screen()
      txt.plot(view.LEFT_MARGIN,r+1)
      cursor.replace(view.LEFT_MARGIN,r+1)
    }
    else if r == view.BOTTOM_LINE {
      void incr_top_line(1)
      draw_screen()
      txt.plot(view.LEFT_MARGIN,r)
      cursor.replace(view.LEFT_MARGIN,r)
    }
    else {
      draw_screen()
      txt.plot(view.LEFT_MARGIN,r+1)
      cursor.replace(view.LEFT_MARGIN,r+1)
    }

    main.update_tracker()
  }

  sub insert_line_above() {
    ubyte r = view.r()

    uword curr_line = main.get_line_num(r)

    ^^Line curr_addr = get_Line_addr(r)
    ^^Line old_prev  = 0
    ^^Line new_prev  = main.allocNewLine("  ")
    if new_prev == $0000 {
        warn("Out of memory!")
        return
    }

    if curr_line > 1 {
      old_prev = view.INDEX[(curr_line as ubyte) - 2]
    }

    new_prev.prev = old_prev
    new_prev.next = curr_addr

    curr_addr.prev = new_prev

    if old_prev != 0 {
      old_prev.next = new_prev
    }

    main.lineCount = view.insert_line_before(new_prev, curr_line, main.lineCount)

    flags.UNSAVED = true

    if r == view.TOP_LINE {
      draw_screen()
      txt.plot(view.LEFT_MARGIN, r)
      cursor.replace(view.LEFT_MARGIN, r)
    }
    else if r == view.BOTTOM_LINE {
      draw_screen()
      txt.plot(view.LEFT_MARGIN, r)
      cursor.replace(view.LEFT_MARGIN, r)
    }
    else {
      txt.scrolldown_nlast(r, view.LEFT_MARGIN)
      txt.plot(view.LEFT_MARGIN, r)
      prints(view.BLANK_LINE76)
      txt.plot(0, view.BOTTOM_LINE+1)
      prints(view.BLANK_LINE79)
      txt.plot(view.LEFT_MARGIN, r)
      cursor.hide()
      cursor.place(view.LEFT_MARGIN, r)
    }

    main.update_tracker()
  }

  sub insert_line_below() {
    ubyte r = view.r()

    cursor.hide()

    uword curr_line = main.get_line_num(r) ; next_line is +1

    ^^Line curr_addr = get_Line_addr(r)        ; gets memory addr of current Line
    ^^Line new_next  = main.allocNewLine("  ") ; creates new Line instance to insert
    if new_next == $0000 {
        warn("Out of memory!")
        return
    }

    new_next.prev  = curr_addr
    new_next.next  = curr_addr.next
    curr_addr.next = new_next

    ;; call to update INDEX
    main.lineCount = view.insert_line_after(new_next, main.get_line_num(r), main.lineCount)

    ; need to assert new address got inserted into view.INDEX
    void debug.assert(view.INDEX[curr_line as ubyte - 1], curr_addr, debug.EQ, "INDEX[curr_line as ubyte - 1] == curr_addr")
    void debug.assert(view.INDEX[curr_line as ubyte], new_next, debug.EQ, "INDEX[curr_line as ubyte] == new_next")

    ;info("o ...")
    flags.UNSAVED = true

    if r == view.BOTTOM_LINE {
      void incr_top_line(1)
      draw_screen()
      txt.plot(view.LEFT_MARGIN,r)
      cursor.replace(view.LEFT_MARGIN,r)
    }
    else {
      txt.scrolldown_nlast(r+1, view.LEFT_MARGIN)

      txt.plot(view.LEFT_MARGIN,r+1)
      prints(view.BLANK_LINE76)

      txt.plot(0,view.BOTTOM_LINE+1)
      prints(view.BLANK_LINE79)

      ; handle lines as they shift down if adding lines mid screen on a
      ; short document
      if main.lineCount <= view.HEIGHT and r != (main.lineCount+view.TOP_LINE) {
         ; prog8 will short circut here if the first condition is false, so it
         ; avoids lineCount (uword) overflowing "as ubyte"
         txt.plot(view.LEFT_MARGIN, (main.lineCount as ubyte)+view.TOP_LINE-1)
         main.printLineNum(main.lineCount)
      }

      txt.plot(view.LEFT_MARGIN,r+1)
      cursor.place(view.LEFT_MARGIN,r+1)
    }

    main.printLineNum(curr_line+1)

    main.update_tracker()
  }

  sub do_yy() {
    info("yank")

    ubyte c = view.c()
    ubyte r = view.r()

    ^^Line curr_addr = get_Line_addr(r) ; line being deleted

    view.CLIPBOARD = curr_addr

    cursor.replace(c, r)
    main.update_tracker()
  }

  sub clear_current_line() {
    ubyte c = view.c()
    ubyte r = view.r()

    ^^Line curr_addr = get_Line_addr(r) ; line being deleted

    ubyte i
    for i in (c-view.LEFT_MARGIN) to main.MaxLength-1 {
      @(curr_addr.text + i) = $20
    }

    void redraw_line(curr_addr, r)

    cursor.replace(c-1, r)
    main.update_tracker()
  }

  sub do_dd() {
    if main.lineCount < 2 {
      txt.plot(view.LEFT_MARGIN, view.TOP_LINE)
      prints(view.BLANK_LINE76)
      txt.plot(view.LEFT_MARGIN, view.TOP_LINE)
      return
    }

    info("cut")

    ubyte c = view.c()
    ubyte r = view.r()

    ; safety: if no lines, nothing to do
    if main.lineCount == 0 {
      cursor.replace(c, r)
      main.update_tracker()
      return
    }

    ; safety/vim-like: if only one line, clear it instead of deleting it
    if main.lineCount == 1 {
      ^^Line only_addr = get_Line_addr(r)
      view.CLIPBOARD = only_addr

      ubyte i
      for i in 0 to MaxLength-1 {
        @(only_addr.text + i) = $20
      }
      @(only_addr.text + MaxLength) = 0

      void redraw_line(only_addr, r)

      flags.UNSAVED = true

      txt.plot(view.LEFT_MARGIN, r)
      cursor.replace(view.LEFT_MARGIN, r)
      main.update_tracker()
    }

    ^^Line curr_addr = get_Line_addr(r) ; line being deleted
    ^^Line prev_addr = curr_addr.prev   ; line before line being deleted
    ^^Line next_addr = curr_addr.next   ; line after line being deleted

    ; short circuit curr_line out of links
    if prev_addr != 0 {
      prev_addr.next = next_addr
    }
    if next_addr != 0 {                   ; make sure curr_line is not last line of doc
      next_addr.prev = prev_addr
    }

    ; compute whether we just deleted the last document line
    uword deleted_line = main.get_line_num(r)

    main.lineCount = view.delete_item(deleted_line, main.lineCount)

    draw_screen()

    view.CLIPBOARD   = curr_addr ; save deleted address to clipboard for later pasting

    flags.UNSAVED = true

    ; If we deleted the last document line, move cursor up one screen row (if possible)
    if deleted_line > main.lineCount {
      if r > view.TOP_LINE {
        r = r - 1
      }
      c = view.LEFT_MARGIN
    }

    txt.plot(c, r)
    cursor.replace(c, r)
    main.update_tracker()
  }

  sub incr_top_line(uword value) -> uword {
    if  view.CURR_TOP_LINE + value <= main.lineCount {
      view.CURR_TOP_LINE += value
    }
    return view.CURR_TOP_LINE     ; stops ++'ing with the last HEIGHT lines in the document
  }

  sub decr_top_line(uword value) -> uword {
    if  view.CURR_TOP_LINE - value >= 1 {
      view.CURR_TOP_LINE -= value
    }
    return view.CURR_TOP_LINE     ; returns 1 at the minimum
  }

  sub printLineNum (uword number) {
    ubyte c = view.c()
    txt.plot(0, view.r())
    txt.color($f)
    prints("    ")
    txt.plot(0, view.r())
    printW(number)
    txt.color($1)
    txt.plot(c, view.r())
  }

  sub draw_screen () {               ; NOTE: assumes view.CURR_TOP_LINE is correct
      info_noblock("             ")
      ubyte idx = (view.CURR_TOP_LINE as ubyte) - 1
      ^^Line line = view.INDEX[idx]
      ubyte r
      txt.plot(view.LEFT_MARGIN, view.TOP_LINE)
      ubyte m,n
      uword remaining = main.lineCount - view.CURR_TOP_LINE + 1
      if remaining >= view.HEIGHT {
        m = view.HEIGHT
        n = 0
      }
      else {
        m = remaining as ubyte
        n = (view.HEIGHT - remaining) as ubyte
      }
      uword lineNum = idx + 1
      str tmp = " " *main.MaxLength
      repeat m {
        r = view.r()
        txt.plot(0, r)
        prints(view.BLANK_LINE79)
        txt.plot(0, r)
        if main.MODE != mode.INIT {      ; prevent line '1' from showing in splash on start
          main.printLineNum(lineNum)
        }
        txt.plot(view.LEFT_MARGIN, r)

        void strings.copy(line.text,tmp) ; also figure out why I have to do this to get rid of errant space in next line
        strings.rstrip(tmp)
        prints(tmp)
        txt.plot(view.LEFT_MARGIN, r+1)

        ; get next Line
        line = line.next
        lineNum++
      }
      repeat n {
        r = view.r()
        prints(view.BLANK_LINE79)
        txt.plot(0,r)
        prints("~   ")
        txt.plot(0,r+1)
      }
      info_noblock("             ")
  }

  sub draw_bottom_line (uword lineNum) {
      if lineNum > main.lineCount {
        return
      }
      ubyte idx = lineNum as ubyte - 1
      uword addr = view.INDEX[idx]
      ^^Line line = addr
      addr = line.next
      txt.plot(0, view.BOTTOM_LINE)
      prints(view.BLANK_LINE79)
      txt.plot(0, view.BOTTOM_LINE)
      main.printLineNum(lineNum)
      txt.plot(view.LEFT_MARGIN, view.BOTTOM_LINE)
      say(line.text)
  }

  sub draw_top_line (uword lineNum) {
      if lineNum < 1 {
        return
      }
      ubyte idx = lineNum as ubyte - 1
      uword addr = view.INDEX[idx]
      ^^Line line = addr
      addr = line.next
      txt.plot(view.LEFT_MARGIN, view.TOP_LINE)
      prints(line.text)
      txt.plot(0, view.TOP_LINE)
      main.printLineNum(lineNum)
  }

  sub page_forward() {
      ubyte c = view.c()
      uword last_page_start = main.lineCount - view.HEIGHT + 1
      if view.CURR_TOP_LINE + view.HEIGHT < last_page_start {
        void incr_top_line(view.HEIGHT)
      }
      else {
        view.CURR_TOP_LINE = last_page_start
      }
      draw_screen()
      cursor.replace(c, view.BOTTOM_LINE)
      main.update_tracker()
  }

  sub page_backward() {
      ubyte c = view.c()
      if view.CURR_TOP_LINE > view.HEIGHT {
        view.CURR_TOP_LINE = view.CURR_TOP_LINE - view.HEIGHT;
      }
      else {
        view.CURR_TOP_LINE = 1
      }
      draw_screen()
      cursor.replace(c, view.TOP_LINE)
      main.update_tracker()
  }

  ubyte default_col ; used by j & k to track the default column to feel more like what vim does

  ; ^
  sub jump_to_left() {
      cursor.restore_current_char()
      txt.plot(view.LEFT_MARGIN, view.r())
      default_col = view.c()
      cursor.replace(view.LEFT_MARGIN, view.r())
      main.update_tracker()
  }

  sub get_end_col(ubyte r) -> ubyte {
    ^^Line curr_addr = get_Line_addr(r)

    ; Find last printable ISO byte (32..126) in the line buffer.
    ; If none, return LEFT_MARGIN.
    ubyte last = 255
    ubyte i
    for i in 0 to main.MaxLength-1 {
      ubyte ch = @(curr_addr.text + i)
      if ch == 0 {
        break
      }
      if ch >= 32 and ch <= 126 and ch != $20 {  ; treat space as not “visible”
        last = i
      }
    }

    if last == 255 {
      return view.LEFT_MARGIN
    }

    uword col = view.LEFT_MARGIN + last
    if col > view.RIGHT_MARGIN {
      col = view.RIGHT_MARGIN
    }
    return col as ubyte
  }

  ; $
  sub jump_to_right() {
    ; don’t allow footer/top status lines to be treated as document rows
    ubyte r = view.r()
    if r < view.TOP_LINE or r > view.BOTTOM_LINE {
      return
    }

    ; empty document guard
    if main.lineCount == 0 {
      return
    }

    ubyte end_col = get_end_col(r)

    cursor.restore_current_char()
    txt.plot(end_col, r)
    default_col = view.c()
    cursor.replace(end_col, r)
    main.update_tracker()
  }

  ; g
  sub jump_to_begin() {
      if main.lineCount > view.HEIGHT {
        view.CURR_TOP_LINE = 1
        draw_screen()
      }
      cursor.place(view.LEFT_MARGIN, view.TOP_LINE)
      main.update_tracker()
  }

  ; G
  sub jump_to_end() {
      if main.lineCount > view.HEIGHT {
        view.CURR_TOP_LINE = main.lineCount - view.HEIGHT + 1
        draw_screen()
        cursor.replace(view.LEFT_MARGIN, view.BOTTOM_LINE)
      }
      else {
        cursor.place(view.LEFT_MARGIN, (main.lineCount as ubyte) + 1)
      }
      main.update_tracker()
  }

  sub cursor_up_on_k () {
    ; k (up) from going past line 1
    if view.CURR_TOP_LINE == 1 and view.r() == view.TOP_LINE {
      return
    }
    ubyte curr_line = view.r()
    ubyte curr_col  = view.c()
    ubyte next_line = curr_line-1;
    ubyte curr_end  = get_end_col(view.c())
    ubyte next_col  = curr_col
    ubyte next_end  = get_end_col(next_line)

    ; track end of line if at end of line in the curr_line
    if curr_col == curr_end or curr_col >= next_end {
      default_col = curr_col
      next_col = next_end
    }
    else {
      next_col = default_col
    }

    if next_col < view.LEFT_MARGIN {
      next_col = view.LEFT_MARGIN
    }

    if curr_line == view.TOP_LINE {
      cursor.hide()
      txt.scrolldown()
      void decr_top_line(1)
      txt.plot(view.LEFT_MARGIN, view.TOP_LINE)
      draw_top_line(view.CURR_TOP_LINE)
      txt.plot(0, view.BOTTOM_LINE+1) ; blank footer line
      prints(view.BLANK_LINE79)
      cursor.replace(next_col, curr_line)
    }
    else {
      cursor.place(next_col,next_line)
    }
    main.update_tracker()
  }

  sub cursor_down_on_j () {
    ; j (down) from going past main.lineCount

    ; compute last possible top line (clamp so it never underflows)
    uword lastTop
    if main.lineCount > view.HEIGHT {
      lastTop = main.lineCount - view.HEIGHT + 1
    } else {
      lastTop = 1
    }

    ; if we're already showing the last page and the cursor is on the bottom row, stop
    if view.CURR_TOP_LINE == lastTop and view.r() == view.BOTTOM_LINE {
      return
    }

    ubyte curr_line = view.r()
    ubyte curr_col  = view.c()
    ubyte next_line = curr_line + 1
    ubyte curr_end  = get_end_col(view.c())
    ubyte next_col  = curr_col
    ubyte next_end  = get_end_col(next_line)

    ; track end of line if at end of line in the curr_line
    if curr_col == curr_end or curr_col >= next_end {
      default_col = curr_col
      next_col = next_end
    }
    else {
      next_col = default_col
    }

    if next_col < view.LEFT_MARGIN {
      next_col = view.LEFT_MARGIN
    }

    if curr_line == view.BOTTOM_LINE {
      cursor.hide()
      void incr_top_line(1)          ; increment CURR_TOP_LINE

      txt.plot(0, view.FOOTER_LINE)  ; blank footer line
      prints(view.BLANK_LINE79)

      txt.plot(0, 1)                 ; blank top line
      say(view.BLANK_LINE79)
      prints(view.BLANK_LINE79)

      txt.scroll_up()
      draw_bottom_line(view.CURR_TOP_LINE + view.HEIGHT - 1)

      cursor.replace(next_col, curr_line)
    } else {
      ; Only move the cursor down if there is a real document line there.
      ; Map current screen row -> document line number:
      ; docLine = CURR_TOP_LINE + (screenRow - TOP_LINE)
      uword docLine = view.CURR_TOP_LINE + (curr_line - view.TOP_LINE)

      if docLine < main.lineCount {
        cursor.place(next_col, next_line)
      }
    }

    main.update_tracker()
  }

  ; prints address 'addr' at row 'r'
  sub redraw_line(^^Line addr, ubyte r) -> ubyte {
    ;info_noblock("line saved to buffer ...")

    txt.plot(view.LEFT_MARGIN,r)
    prints(view.BLANK_LINE76)
    txt.plot(view.LEFT_MARGIN,r)
    str tmp = " " * 76 ; main.MaxLength
    void strings.copy(addr.text, tmp)
    strings.rstrip(tmp) ; <- to get rid of straw CR or LF, but is this necessary?
    prints(tmp)
    return strings.length(tmp) ; <- still we can get length, and this can be helpful
  }

  sub save_line_buffer() {
    ubyte c = view.c()
    ubyte r = view.r()

    ^^Line curr_addr = get_Line_addr(r)

    ubyte i
    for i in 0 to MaxLength-1 {
      @(curr_addr.text + i) = txt.getchr(view.LEFT_MARGIN + i, r)
    }
    @(curr_addr.text + MaxLength) = 0      ; null terminate

    cursor.replace(c,r)
    txt.plot(c,r)
    main.update_tracker()
  }

  ; in NAV mode, `r <char>`
  sub replace_char(ubyte char) {
    ; accept only printable ISO
    if char < 32 or char > 126 {
      return
    }

    ubyte c = view.c()
    ubyte r = view.r()

    ; guard against cursor outside editable region
    if c < view.LEFT_MARGIN {
      c = view.LEFT_MARGIN
    }
    if c > view.RIGHT_MARGIN-1 {
      return
    }
    if r < view.TOP_LINE or r > view.BOTTOM_LINE {
      return
    }

    ^^Line curr_addr = get_Line_addr(r)    ; gets memory addr of current Line

    ; replace char at (c,r)
    @(curr_addr.text + (c - view.LEFT_MARGIN)) = char
    @(curr_addr.text + MaxLength) = 0       ; null terminate
    cursor.saved_char = char

    ; redraw line
    void redraw_line(curr_addr, r)

    cursor.replace(c,r)
    txt.plot(c,r)
    main.update_tracker()
  }

  sub insert_char_shift_right(ubyte char) {
    ; accept only printable ISO
    if char < 32 or char > 126 {
      return
    }

    ubyte c = view.c()
    ubyte r = view.r()

    ; hard guard: prevent out-of-range writes
    if c < view.LEFT_MARGIN {
      c = view.LEFT_MARGIN
    }
    if c > view.RIGHT_MARGIN-1 {
      return
    }

    ^^Line curr_addr = get_Line_addr(r)

    ubyte i
    for i in view.RIGHT_MARGIN-1 to c+1 step -1 {
      @(curr_addr.text + (i - view.LEFT_MARGIN)) = @(curr_addr.text + (i - view.LEFT_MARGIN - 1))
    }

    @(curr_addr.text + (c - view.LEFT_MARGIN)) = char
    @(curr_addr.text + MaxLength) = 0       ; null terminate
    flags.UNSAVED = true

    cursor.saved_char = char

    void redraw_line(curr_addr, r)

    cursor.replace(c,r)

    txt.plot(c,r)
    default_col = view.c()
    main.update_tracker()
  }

  sub delete_xy_shift_left() {
    ubyte c = view.c()
    ubyte r = view.r()

    ; guard against cursor outside editable region
    if c < view.LEFT_MARGIN {
      c = view.LEFT_MARGIN
    }
    if c > view.RIGHT_MARGIN-1 {
      return
    }
    if r < view.TOP_LINE or r > view.BOTTOM_LINE {
      return
    }

    ^^Line curr_addr = get_Line_addr(r)    ; gets memory addr of current Line

    ; remove char at (c,r) then shift everything to the left
    @(curr_addr.text + (c - view.LEFT_MARGIN)) = $20
    cursor.saved_char = $20

    ; shift left within the fixed-width buffer [0..MaxLength-1]
    ubyte i
    ubyte start = c - view.LEFT_MARGIN
    for i in start to MaxLength-2 {
      @(curr_addr.text + i) = @(curr_addr.text + i + 1)
    }
    @(curr_addr.text + (MaxLength - 1)) = $20
    @(curr_addr.text + MaxLength) = 0     ; null terminate

    ; redraw + get visible length from redraw_line()
    ubyte length = redraw_line(curr_addr, r)

    ; keep cursor in a sane spot
    if length == 0 {
      c = view.LEFT_MARGIN
    }
    else if c >= view.LEFT_MARGIN + length {
      c = view.LEFT_MARGIN + length - 1
    }

    if c < view.LEFT_MARGIN {
      c = view.LEFT_MARGIN
    }
    if c > view.RIGHT_MARGIN-1 {
      c = view.RIGHT_MARGIN-1
    }

    txt.plot(c,r)
    default_col = view.c()
    cursor.replace(c,r)

    flags.UNSAVED = true
    main.update_tracker()
  }

  sub cursor_left_on_h () {
    if view.c() > view.LEFT_MARGIN {
      cursor.place(view.c()-1,view.r())
    }
    default_col = view.c()
    main.update_tracker()
  }

  sub cursor_right_on_l () {
    if view.c() < view.RIGHT_MARGIN {
      cursor.place(view.c()+1,view.r())
    }
    default_col = view.c()
    main.update_tracker()
  }

  ; util functions
  sub update_tracker () {
    ubyte X = view.c()
    ubyte Y = view.r()

    ; Always draw tracker on the footer line only
    txt.plot(2, view.FOOTER_LINE)
    prints(view.BLANK_LINE76)

    ; Use a known color scheme for footer baseline (optional)
    ; If you don't want this, remove these two lines.
    txt.color2($1,$6)   ; white on blue (example), match your normal scheme

    txt.plot(1, view.FOOTER_LINE)

    if flags.VERBOSE_STATUS == false {
      txt.plot(0, view.FOOTER_LINE)
      prints(view.BLANK_LINE79)
      txt.plot(1, view.FOOTER_LINE)
      if @(doc.filepath+1) != $20 {
        cbm.CHROUT($22)
        prints(doc.filepath)
        cbm.CHROUT($22)
        if flags.UNSAVED == true {
          prints(" [modified]")
        }
        else {
          prints(" [saved]")
        }
      }
      else {
        prints("[unsaved buffer]")
      }
      txt.plot(79-12, view.FOOTER_LINE)
      printW(Y - view.TOP_LINE + 1)
      prints(",")
      printW(X - view.LEFT_MARGIN + 1)
      txt.plot(79-3, view.FOOTER_LINE)
      printW(main.lineCount)
    }
    else {
      printw(main.lineCount)
      prints(" lines, x: ")
      printw(X - view.LEFT_MARGIN + 1)
      prints(", y: ")
      printw(Y - view.TOP_LINE + 1)
      prints(" TOP: ")
      printw(view.CURR_TOP_LINE)
      prints(" BOT: ")
      printw(view.CURR_TOP_LINE + view.HEIGHT - 1)
      prints(" CNT: ")
      printw(main.NAVCHARCOUNT)

      ; Status badge MUST be on footer line (bugfix)
      txt.plot(79-9, view.FOOTER_LINE)
      if flags.UNSAVED == true {
        txt.color2($6,$1)
        prints("(UNSAVED)")
        txt.color2($1,$6)
      }
      else if main.MODE > mode.INIT {
        prints("( SAVED )")
      }
    }

    ; Mode indicator (upper left) — keep as you had it
    if main.MODE == mode.REPLACE {
      info_noblock_LEFT("-- REPLACE --")
    }
    else if main.MODE == mode.INSERT {
      info_noblock_LEFT("-- INSERT  --")
    }
    else if main.MODE == mode.NAV {
      info_noblock_LEFT("             ")
    }
    else {
      info_noblock_LEFT("             ")
    }

    ; Restore cursor position
    txt.plot(X, Y)
  }

  sub prints (str x) {
    cbm.CHROUT($80)
    txt.print(x)
  }

  sub say (str x) {
    txt.print(x)
    txt.nl()
  }

  sub printw (uword x) {
    txt.print_uw0(x)
  }

  sub printW (uword x) {
    txt.print_uw(x)
  }

  sub info_noblock_LEFT(str message) {
    alert_noblock_LEFT(message, $7, $6)
  }

  sub alert_noblock_LEFT(str message, ubyte color1, ubyte color2) {
    ubyte length = strings.length(message)
    txt.plot(1, 0)
    txt.color2(color1, color2)
    prints(message)
    txt.color2($1, $6) ; sets text back to default, white on blue
  }

  sub info_noblock(str message) {
    alert_noblock(message, $7, $6)
  }

  sub alert_noblock(str message, ubyte color1, ubyte color2) {
    ubyte length = strings.length(message)
    txt.plot(78-length, 0)
    txt.color2(color1, color2)
    prints(message)
    txt.color2($1, $6) ; sets text back to default, white on blue
  }

  sub info(str message) {
    alert(message, 15, $6, $1)
  }

  sub warn(str message) {
    alert(message, 50, $2, $1)
  }

  sub alert(str message, ubyte delay, ubyte color1, ubyte color2) {
    ubyte c = view.c()
    ubyte r = view.r()
    ubyte length = strings.length(message)
    txt.plot(78-length, 0)
    txt.color2(color1, color2)
    prints(message)
    sys.wait(delay)
    txt.plot(78-length, 0)
    txt.color2($1, $6) ; sets text back to default, white on blue
    txt.plot(view.LEFT_MARGIN, 0)
    prints(view.BLANK_LINE79)
    txt.plot(c,r)
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

  sub scrolldown_nlast(ubyte top_row, ubyte col_start) {
    ubyte columns, rows, j
    columns, rows = txt.size()
    rows--
    while rows>top_row {
        rows--
        uword vera_addr = lsw(txt.VERA_TEXTMATRIX) + 256*rows
        cx16.vaddr(msw(txt.VERA_TEXTMATRIX), vera_addr+col_start,     0 ,1) ; source row
        cx16.vaddr(msw(txt.VERA_TEXTMATRIX), vera_addr+col_start+256, 1, 1) ; target row
        for j in col_start to columns-1 {
            cx16.VERA_DATA1 = cx16.VERA_DATA0       ; copy tile
            cx16.VERA_DATA1 = cx16.VERA_DATA0       ; copy color
        }
    }
  }

  sub scrolldown() {
    ubyte columns, rows
    columns, rows = txt.size()
    rows--
    while rows>0 {
        rows--
        uword vera_addr = lsw(txt.VERA_TEXTMATRIX) + 256*rows
        cx16.vaddr(msw(txt.VERA_TEXTMATRIX), vera_addr, 0 ,1)       ; source row
        cx16.vaddr(msw(txt.VERA_TEXTMATRIX), vera_addr+256, 1, 1)   ; target row
        repeat columns {
            cx16.VERA_DATA1 = cx16.VERA_DATA0       ; copy tile
            cx16.VERA_DATA1 = cx16.VERA_DATA0       ; copy color
        }
    }
  }
}
