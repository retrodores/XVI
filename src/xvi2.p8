;
; vim:set softtabstop=2 shiftwidth=2 expandtab:
;
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
; - do not write contiguous spaces (fully blank line, trim when writing)
; -- this might be an optimization that is needed when we increase line
; -- support > 140
; - stack based "undo" (p/P, o/O, dd)

; DONE:
; - added <ESC> as cancel when in command mode
; - adding a non-supported command in command mode messed up the bottom footer,
; - this is fixed
; - verify as part of that, "~" is not present at the start in some cases, fix that
; - wq! - force save, force save and quit
; - add checks around wq, wq! (buffer, first command?)
; See CHANGELOG for the rest

%zeropage basicsafe
%encoding iso

%import textio
%import strings
%import conv
%import syslib
%import diskio
%import xvi_platform
%import xvitext
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
  const ubyte LEFT_MARGIN     = plat.LEFT_MARGIN
  const ubyte RIGHT_MARGIN    = plat.RIGHT_MARGIN
  const ubyte HEIGHT          = plat.HEIGHT      ; absolute height of the edit/view area
  const ubyte TOP_LINE        = plat.TOP_LINE    ; row of the first line of the document (FIRST_LINE_IDX)
  const ubyte BOTTOM_LINE     = plat.BOTTOM_LINE ; row of the last line of the view port (LAST_LINE_IDX)
  const ubyte FOOTER_LINE     = plat.FOOTER_LINE
  str         BLANK_ROW       = " " * plat.ROW_LEN    ; a whole row, from column 0
  str         BLANK_TEXT      = " " * plat.TEXT_WIDTH ; the text part of a row
  uword       CURR_TOP_LINE   = 1  ; tracks which actual doc line is at TOP_LINE

  sub r() -> ubyte {
    return txt.get_row()
  }

  sub c() -> ubyte {
    return txt.get_column()
  }
}

command {
  str cmdBuffer = " " * 60
  ubyte col, row

  sub prompt () {
    ubyte cmdchar
    ubyte cmdlen = 0
    cursor.hide()
    txt.plot(0, view.FOOTER_LINE) ; move cursor to the starting position for writing
    main.prints(view.BLANK_ROW)
    txt.plot(0, view.FOOTER_LINE)
    plat.putc(':')
  CMDINPUT:
    cmdchar = plat.getkey()
    if cmdchar == $1b {  ; ESC key, get out of command mode
      txt.plot(0, view.FOOTER_LINE) ; move cursor to the starting position for writing
      main.prints(view.BLANK_ROW)
      txt.plot(0, view.FOOTER_LINE)
      main.update_tracker()
      goto main.start.NAVCHARLOOP  ; start main loop
    }
    when cmdchar {
      $00 -> {}
      $0d -> {
        cmdBuffer[cmdlen] = 0
        strings.strip(command.cmdBuffer)
        return
      }
      $14, $08, $7f -> {   ; backspace variants, the ':' stays
        if cmdlen != 0 {
          cmdlen--
          txt.plot(cmdlen+1, view.FOOTER_LINE)
          plat.putc($20)
          txt.plot(cmdlen+1, view.FOOTER_LINE)
        }
      }
      else -> {
        if cmdchar >= 32 and cmdchar <= 126 and cmdlen < len(cmdBuffer)-2 and cmdlen < plat.COLS-2 {
          cmdBuffer[cmdlen] = cmdchar
          cmdlen++
          plat.putc(cmdchar)
        }
      }
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
      plat.quit()
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
        main.char = 'R'
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
          plat.quit()
        }
      }
      'w' -> {
        if flags.FIRST_COMMAND == true and flags.UNSAVED == false and not force {
          main.warn("Nothing to save!")
          goto main.start.FIRST_OPEN  ; start main loop
        }
        flags.FIRST_COMMAND = false
        ; 'w' is for "write" - fn1 is the filename
        if strings.length(fn1) > 0 {
          if plat.exists(fn1) and not force {
            main.warn("File Exists. Use w! to override ...")
          }
          else {
            plat.delete(fn1)
            if main.save_as(fn1) {
              void strings.copy(fn1, main.doc.filepath)
            }
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
        main.warn("Not an editor command!")
        txt.plot(0, view.FOOTER_LINE) ; move cursor to the starting position for writing
        main.prints(view.BLANK_ROW)
        txt.plot(0, view.FOOTER_LINE)
        main.update_tracker()
        goto main.start.NAVCHARLOOP  ; start main loop
      }
    }
  }
}

main {
  ubyte MODE         = mode.NAV ; initial mode is NAV
  uword NAVCHARCOUNT = 0        ; the main "clock"

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

  ; the working copy of one line: see get_Line_addr()
  struct Line {
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

  ^^Document doc = memory("doc", sizeof(Document), 1)

  const uword MaxLength  = doctext.WIDTH

  ^^Line scratch = memory("scratch", sizeof(Line), 1)

  alias lineCount = doctext.count

  ; initiates initial buffer without a file, jumps to REPLACEMODE
  ; so user can start typing right away
  sub init_empty_buffer(ubyte lines) {
    doctext.clear()
    txt.plot(view.LEFT_MARGIN, view.TOP_LINE)
    flags.UNSAVED = true
    main.draw_screen()
    cursor.place(view.LEFT_MARGIN, view.TOP_LINE)
    main.printLineNum(1)
  }

  sub load_file(str filepath) -> bool {
    strings.strip(filepath)
    txt.plot(view.LEFT_MARGIN, view.TOP_LINE)

    if not plat.exists(filepath) {
      warn("File does not exist!")
      return false
    }

    info("Loading file ...")

    if not doctext.load(filepath) {
      warn("Can't open file!")
      return false
    }
    flags.UNSAVED = false
    if doctext.truncated {
      warn("File too big!")
    }
    txt.clear_screen()
    void strings.copy(filepath,doc.filepath)
    return true
  }

  sub splash() {
    txt.clear_screen()
    txt.plot(0,view.TOP_LINE)
    init_empty_buffer(1)
    plat.splash_text()
  }

  sub clear_splash() {
    txt.clear_screen()
    txt.plot(0,view.TOP_LINE+1)
    repeat view.HEIGHT-1 {
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
     if plat.exists(oldback) {
       plat.delete(oldback)
     }
     plat.rename(doc.filepath, oldback)
     if save_as(doc.filepath) {
       plat.delete(oldback)
     }
  }

  sub save_as(str filepath) -> bool {
    info_noblock("saving ...")

    bool ok = doctext.save(filepath)
    if ok {
      flags.UNSAVED = false
    }
    else {
      warn("Write failed!")
    }

    info_noblock("          ")
    return ok
  }

  sub navchar_start() {
    main.NAVCHARCOUNT++
  }

  sub toggle_nav() {
    main.MODE = mode.NAV
    main.update_tracker()
  }

  ubyte char
  ubyte last_char
  ubyte col
  ubyte row
  uword numbers

  sub start () {
    plat.init()
    doc.tabNum               = 0 ; for future proofing
    doc.charset              = 0 ; for future proofing
    doc.startBank            = 1 ; for future proofing
    doc.filepath             = " " * 80
    @(doc.filepath+80)       = 0

    scratch.text             = &scratch.data00
    @(scratch.text+MaxLength) = 0
    doctext.init(sys.progend(), plat.TEXT_TOP)
    main.MODE = mode.INIT

    sys.wait(20)

    ;txt.plot(0,1)
    ;cursor.place(view.LEFT_MARGIN, view.TOP_LINE)

    FIRST_OPEN: 
    flags.FIRST_COMMAND = true

    splash()

    repeat {
    NAVCHARLOOP:
        char = plat.getkey()
        navchar_start()
        if char == $00 continue
    SKIP_NAVCHARLOOP:
        col = view.c()
        row = view.r()
        when main.MODE {
            mode.INIT -> key_mode_init()
            mode.NAV -> key_mode_nav()
            mode.INSERT -> key_mode_insert()
            mode.REPLACE -> key_mode_replace()
            mode.COMMAND -> key_mode_command()
        }
        last_char = char
    }
    ; only reachable via a break in the above repeat {} loop
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
    }
  }

  sub key_mode_init() {
    ; On splash/INIT: treat ESC as a prefix so ESC+R / ESC+i is instant.
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
          goto main.key_mode_nav.PROCESS_COMMAND
        }
      }

      ; "goto" dispatcher on edit or command modes
      when char {
        'R'  -> { goto main.key_mode_nav.RLOOP2 }
        'i'  -> { goto main.key_mode_nav.ILOOP  }
        'a'  -> { goto main.key_mode_nav.ILOOP  }
      }

  }

  sub key_mode_nav() {
    when char {
      '0' to '9' -> {
        if char == '0' {
          if last_char < '0' or last_char > '9' {
            jump_to_left()
            return
          }
        }
        numbers = (numbers * 10) + (char - '0')
      }
      ; N A V I G A T I O N
      '^','I' -> { ; jump to start of line
        jump_to_left()
        if char == 'I' {
          char = 'i'
          goto ILOOP ; go now into insert mode
        }
      }
      '$','A' -> { ; jump top end of line
        jump_to_right()
        if char == 'A' {
          char = 'a'
          goto ISTART ; go now into insert mode
        }
      }
      ':' -> {                       ; command line
        command.prompt()             ; populates command.cmdBuffer

        PROCESS_COMMAND:
        ; clear command line
        txt.plot(0, view.FOOTER_LINE)
        prints(view.BLANK_ROW)
        main.update_tracker()
        command.process()

        ;debug.assert(main.lineCount, 93, debug.EQ, "ln 515 ... main.lineCount == 93")
        toggle_nav()
        cursor.replace(col, row)
        main.update_tracker()
      }
      'D' -> {
        main.clear_current_line()
      }
      'd' -> {
        ; do_dd() should handle numbers
        if last_char == 'd' {
          char = 0
          if numbers == 0 {
            main.do_dd()
          } else {
            repeat numbers {
              main.do_dd()
            }
            numbers = 0
          }
          return
        }
      }
      'O' -> {
        main.insert_line_above()
        goto RLOOP2 ; REPLACE mode, start editing blank line immediately
      }
      'o' -> {
        main.insert_line_below()
        goto RLOOP2 ; REPLACE mode, start editing blank line immediately
      }
      'Y' -> {
        main.do_yy()
        return
      }
      'y' -> {
        if last_char == 'y' {
          char = 0
          main.do_yy()
          return
        }
      }
      'Z' -> {
        if last_char == 'Z' {
          char = 0
          ; make sure we're not use editing a buffer
          if @(doc.filepath+1) == $20 {
            warn("No filename. Use :w filename")
            return
          }
          save_current_file()
          plat.quit()
        }
      }
      'P' -> {
        main.paste_line_above()
      }
      'p' -> {
        main.paste_line_below()
      }
      ; E D I T I N G
      'r' -> { ; replace char
        RLOOP1:
        char = plat.getkey()
        ; go back to RLOOP1 if there's nothing input via keyboard
        if char == $00 {
          goto RLOOP1
        }
        when char {
          $1b -> {       ; ESC key, throw into NAV mode from any other mode
            toggle_nav()
            return
          }
          else -> {
            goto REPLACECHAR
          }
        }
        goto RLOOP1
        REPLACECHAR:
        main.replace_char(char)
      }
      'x', $7f -> {  ; delete char, shift left - 'x' and $7 (backspace in NAV mode)
        main.delete_xy_shift_left()
      }
      'R' -> { ; replace mode
        main.MODE = mode.REPLACE
        main.update_tracker()

        RLOOP2:
        main.MODE = mode.REPLACE
        char = plat.getkey()
        if char == $00 {
          goto RLOOP2
        }
        when char {
          $1b -> {       ; <esc>
            toggle_nav()
            main.end_line_edit()
            return
          }
          $0d -> {       ; <return> == esc + 'o'
            toggle_nav()
            main.end_line_edit()
            char = $6f ; 'o'
            goto main.start.SKIP_NAVCHARLOOP
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
        main.replace_char(char)
        flags.UNSAVED = true
        advance()
        main.update_tracker()
        goto RLOOP2
      }
      's' -> {
        main.MODE = mode.INSERT
        main.update_tracker()
        main.insert_char_shift_right($20) ; initially just adds space, then drop to 'R'
        main.MODE = mode.NAV
        main.update_tracker()
      }
      'L' -> { ; redraw current screen
        ubyte c = view.c()
        ubyte r = view.r()
        draw_screen()
        txt.plot(c, r)
        cursor.replace(c, r)
        main.update_tracker()
      }
      'a','i' -> { ; append after cursor (vim-like)
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
        else if char == 'a' {
          pan_right()
        }
        else {
          cursor.place(view.RIGHT_MARGIN-1, ar)
        }

        main.MODE = mode.INSERT
        main.update_tracker()

        ILOOP:
        main.MODE = mode.INSERT
        char = plat.getkey()
        if char == $00 {
          goto ILOOP
        }
        when char {
          $1b -> {       ; <esc>
            toggle_nav()
            main.end_line_edit()
            return
          }
          $0d -> {       ; <return> == esc + 'o'
            toggle_nav()
            main.end_line_edit()
            char = $6f ; 'o'
            goto main.start.SKIP_NAVCHARLOOP
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
          if doctext.first_col == 0 {
            goto ILOOP
          }
          pan_left(0)
        }
        cursor.saved_char = $20
        cursor.restore_current_char();
        txt.plot(view.c()-1, view.r())
        cursor.place(view.c(), view.r())
        ubyte bc = view.c()
        main.delete_xy_shift_left()
        cursor.place(bc, view.r())   ; (it moves back at the end of a line)
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
        advance()
        main.update_tracker()
        goto ILOOP
      }
      'g' -> {
        jump_to_begin()
      }
      'G' -> {
        jump_to_line(numbers)
        numbers = 0
      }
      'k',$91 -> cursor_up_on_k()                 ; UP
      'j', $11 -> cursor_down_on_j()              ; DOWN
      'h', $9d, $14, $08 -> cursor_left_on_h()    ; LEFT, h, left arrow, backspace variants (<Delete> acts like 'x')
      'l',$20,$1d -> cursor_right_on_l()          ; RIGHT

      $06,$46 -> page_forward()                   ; ctrl+f / shift+f
      $02,$42 -> page_backward()                  ; ctrl+b / shift+b
    }
  }

  sub key_mode_insert() {
  }

  sub key_mode_replace() {
  }

  sub key_mode_command() {
  }

  sub get_line_num(ubyte r) -> uword {
    const uword top = mkword(00,view.TOP_LINE)
    uword trow       = mkword(00,r)
    uword curr_line = view.CURR_TOP_LINE + trow - top
    return curr_line
  }

  ; fills the working copy with the line at screen row r and returns it.
  ; there is only one copy: a change to it needs commit_line() before the
  ; next line is looked at.
  sub get_Line_addr(ubyte r) -> uword {
    doctext.fetch(main.get_line_num(r), scratch.text)
    return scratch
  }

  sub commit_line(ubyte r) {
    if not doctext.commit(main.get_line_num(r), scratch.text) {
      warn("Out of memory!")
    }
  }

  sub paste_line_above() {
    if not doctext.has_yank() {
      warn("Clipboard is empty ..")
      return
    }

    doctext.first_col = 0
    ubyte r = view.r()

    if not doctext.put(main.get_line_num(r)) {
      warn("Out of memory!")
      return
    }

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
    if not doctext.has_yank() { ; indicates empty clipboard (nothing copied yet)
      warn("Clipboard is empty ..")
      return
    }

    doctext.first_col = 0
    ubyte r = view.r()

    if not doctext.put(main.get_line_num(r) + 1) {
      warn("Out of memory!")
      return
    }

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
    pan_home()
    ubyte r = view.r()

    if not doctext.insert_empty(main.get_line_num(r)) {
      warn("Out of memory!")
      return
    }

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
      plat.scroll_down_from(r)
      txt.plot(view.LEFT_MARGIN, r)
      prints(view.BLANK_TEXT)
      txt.plot(0, view.BOTTOM_LINE+1)
      prints(view.BLANK_ROW)
      txt.plot(view.LEFT_MARGIN, r)
      cursor.hide()
      cursor.place(view.LEFT_MARGIN, r)
    }

    main.update_tracker()
  }

  sub insert_line_below() {
    pan_home()
    ubyte r = view.r()

    cursor.hide()

    uword curr_line = main.get_line_num(r) ; next_line is +1

    if not doctext.insert_empty(curr_line + 1) {
      warn("Out of memory!")
      return
    }

    ;info("o ...")
    flags.UNSAVED = true

    if r == view.BOTTOM_LINE {
      void incr_top_line(1)
      draw_screen()
      txt.plot(view.LEFT_MARGIN,r)
      cursor.replace(view.LEFT_MARGIN,r)
    }
    else {
      plat.scroll_down_from(r+1)

      txt.plot(view.LEFT_MARGIN,r+1)
      prints(view.BLANK_TEXT)

      txt.plot(0,view.BOTTOM_LINE+1)
      prints(view.BLANK_ROW)

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

    if not doctext.yank(main.get_line_num(r)) {
      warn("Line too long to yank!")
    }

    cursor.replace(c, r)
    main.update_tracker()
  }

  sub clear_current_line() {
    ubyte c = view.c()
    ubyte r = view.r()

    doctext.delete_to_end(main.get_line_num(r), c-view.LEFT_MARGIN)
    flags.UNSAVED = true

    void redraw_line(get_Line_addr(r), r)

    if c > view.LEFT_MARGIN {
      c--
    }
    cursor.replace(c, r)
    main.update_tracker()
  }

  sub do_dd() {
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
      void doctext.yank(1)
      doctext.delete(1)
      ^^Line only_addr = get_Line_addr(r)

      void redraw_line(only_addr, r)

      flags.UNSAVED = true

      txt.plot(view.LEFT_MARGIN, r)
      cursor.replace(view.LEFT_MARGIN, r)
      main.update_tracker()
      return
    }

    info("cut")

    ; compute whether we just deleted the last document line
    uword deleted_line = main.get_line_num(r)

    if not doctext.yank(deleted_line) {
      warn("Line too long to yank!")
    }
    doctext.delete(deleted_line)

    draw_screen()

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
    if not plat.LINE_NUMBERS {
      return
    }
    ubyte c = view.c()
    txt.plot(0, view.r())
    plat.color($f)
    prints("    ")
    txt.plot(0, view.r())
    printW(number)
    plat.color($1)
    txt.plot(c, view.r())
  }

  sub draw_screen () {               ; NOTE: assumes view.CURR_TOP_LINE is correct
      info_noblock("             ")
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
      uword lineNum = view.CURR_TOP_LINE
      str tmp = " " *main.MaxLength
      repeat m {
        r = view.r()
        txt.plot(0, r)
        prints(view.BLANK_ROW)
        txt.plot(0, r)
        if main.MODE != mode.INIT {      ; prevent line '1' from showing in splash on start
          main.printLineNum(lineNum)
        }
        txt.plot(view.LEFT_MARGIN, r)

        doctext.fetch(lineNum, tmp)
        strings.rstrip(tmp)
        prints(tmp)
        txt.plot(view.LEFT_MARGIN, r+1)

        lineNum++
      }
      repeat n {
        r = view.r()
        prints(view.BLANK_ROW)
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
      doctext.fetch(lineNum, scratch.text)
      txt.plot(0, view.BOTTOM_LINE)
      prints(view.BLANK_ROW)
      txt.plot(0, view.BOTTOM_LINE)
      main.printLineNum(lineNum)
      txt.plot(view.LEFT_MARGIN, view.BOTTOM_LINE)
      say(scratch.text)
  }

  sub draw_top_line (uword lineNum) {
      if lineNum < 1 {
        return
      }
      doctext.fetch(lineNum, scratch.text)
      txt.plot(view.LEFT_MARGIN, view.TOP_LINE)
      prints(scratch.text)
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
      pan_home()
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

    uword tcol = view.LEFT_MARGIN + last
    if tcol > view.RIGHT_MARGIN {
      tcol = view.RIGHT_MARGIN
    }
    return tcol as ubyte
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

    ; the end of the line must be in the window, but not on its last columns
    uword length = doctext.length(main.get_line_num(r))
    if length <= doctext.first_col or length >= doctext.first_col + doctext.WIDTH - 1 {
      if length < doctext.WIDTH - 1 {
        pan_home()
      }
      else {
        pan_to(length - doctext.PAN)
      }
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
      pan_home()
      if main.lineCount > view.HEIGHT {
        view.CURR_TOP_LINE = 1
        draw_screen()
      }
      cursor.place(view.LEFT_MARGIN, view.TOP_LINE)
      main.update_tracker()
  }

  ; G
  sub jump_to_end() {
      pan_home()
      if main.lineCount > view.HEIGHT {
        view.CURR_TOP_LINE = main.lineCount - view.HEIGHT + 1
        draw_screen()
        cursor.replace(view.LEFT_MARGIN, view.BOTTOM_LINE)
      }
      else {
        cursor.place(view.LEFT_MARGIN, (main.lineCount as ubyte) + view.TOP_LINE - 1)
      }
      main.update_tracker()
  }

  sub jump_to_line(uword tline) {
    pan_home()
    if tline == 0 or tline > main.lineCount {
      jump_to_end()
      return
    }
    if tline == 1 {
      jump_to_begin()
      return
    }
    ; destination is on the screen
    if tline > view.CURR_TOP_LINE and tline < (view.CURR_TOP_LINE + view.HEIGHT) {
      cursor.place(view.LEFT_MARGIN, (tline - view.CURR_TOP_LINE) as ubyte + view.TOP_LINE)
      main.update_tracker()
      return
    }
    if tline < view.CURR_TOP_LINE or tline > (view.CURR_TOP_LINE + view.TOP_LINE + view.HEIGHT) {
      view.CURR_TOP_LINE = tline
      draw_screen()
      cursor.replace(view.LEFT_MARGIN, view.TOP_LINE)
    }
    main.update_tracker()
  }

  sub cursor_up_on_k () {
    ; k (up) from going past line 1
    if view.CURR_TOP_LINE == 1 and view.r() == view.TOP_LINE {
      return
    }
    pan_for_row(view.r()-1)
    ubyte curr_line = view.r()
    ubyte curr_col  = view.c()
    ubyte next_line = curr_line-1;
    ubyte curr_end  = get_end_col(curr_line)
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
      plat.scroll_view_down()
      void decr_top_line(1)
      txt.plot(view.LEFT_MARGIN, view.TOP_LINE)
      draw_top_line(view.CURR_TOP_LINE)
      txt.plot(0, view.BOTTOM_LINE+1) ; blank footer line
      prints(view.BLANK_ROW)
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
    pan_for_row(view.r()+1)

    ubyte curr_line = view.r()
    ubyte curr_col  = view.c()
    ubyte next_line = curr_line + 1
    ubyte curr_end  = get_end_col(curr_line)
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

      plat.scroll_view_up()
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
    txt.plot(view.LEFT_MARGIN,r)
    prints(view.BLANK_TEXT)
    txt.plot(view.LEFT_MARGIN,r)

    if addr == 0 {
      return 0
    }

    str tmp = " " * 76 ; main.MaxLength
    void strings.copy(addr.text, tmp)
    strings.rstrip(tmp) ; <- to get rid of straw CR or LF, but is this necessary?
    prints(tmp)
    return strings.length(tmp) ; <- still we can get length, and this can be helpful
  }

  ; leaving insert or replace mode: the text is up to date already, what's
  ; left is the cursor
  sub end_line_edit() {
    ubyte c = view.c()
    ubyte r = view.r()

    cursor.replace(c,r)
    txt.plot(c,r)
    main.update_tracker()
  }

  ; in NAV mode, `r <char>`
  sub replace_char(ubyte tchar) {
    ; accept only printable ISO
    if tchar < 32 or tchar > 126 {
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
    @(curr_addr.text + (c - view.LEFT_MARGIN)) = tchar
    @(curr_addr.text + MaxLength) = 0       ; null terminate
    commit_line(r)
    flags.UNSAVED = true
    cursor.saved_char = tchar

    ; redraw line
    void redraw_line(curr_addr, r)

    cursor.replace(c,r)
    txt.plot(c,r)
    main.update_tracker()
  }

  sub insert_char_shift_right(ubyte tchar) {
    ; accept only printable ISO
    if tchar < 32 or tchar > 126 {
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

    if not doctext.insert_at(main.get_line_num(r), c-view.LEFT_MARGIN, tchar) {
      warn("Out of memory!")
      return
    }
    ^^Line curr_addr = get_Line_addr(r)
    flags.UNSAVED = true

    cursor.saved_char = tchar

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

    ; remove char at (c,r), the rest of the line closes up
    doctext.delete_at(main.get_line_num(r), c-view.LEFT_MARGIN)
    cursor.saved_char = $20

    ; redraw + get visible length from redraw_line()
    ubyte length = redraw_line(get_Line_addr(r), r)

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
    else if doctext.first_col != 0 {
      pan_left(1)
    }
    default_col = view.c()
    main.update_tracker()
  }

  sub cursor_right_on_l () {
    ubyte c = view.c()
    if c >= view.RIGHT_MARGIN-1 and doctext.length(main.get_line_num(view.r())) > doctext.first_col + (c - view.LEFT_MARGIN) + 1 {
      pan_right()
    }
    else if c < view.RIGHT_MARGIN {
      cursor.place(c+1,view.r())
    }
    default_col = view.c()
    main.update_tracker()
  }

  ; the cursor to the next column while typing
  sub advance() {
    if view.c() >= view.RIGHT_MARGIN-1 {
      pan_right()
    }
    else {
      cursor.place(view.c()+1,view.r())
    }
  }

  ; show the text from column first, the cursor stays where it is on screen
  ; (so on another character, the caller moves it)
  sub pan_to(uword first) {
    ubyte c = view.c()
    ubyte r = view.r()
    doctext.first_col = first
    draw_screen()
    txt.plot(c, r)
    cursor.replace(c, r)
  }

  ; pan the window and put the cursor on the column after the one it is on
  sub pan_right() {
    ubyte c = view.c()
    pan_to(doctext.first_col + doctext.PAN)
    cursor.place(c - doctext.PAN + 1, view.r())
  }

  ; pan the window left and put the cursor on the column it is on, or the
  ; number of columns back
  sub pan_left(ubyte back) {
    ubyte c = view.c()
    ubyte shift = doctext.PAN
    if doctext.first_col < shift {
      shift = doctext.first_col as ubyte
    }
    pan_to(doctext.first_col - shift)
    cursor.place(c + shift - back, view.r())
  }

  sub pan_home() {
    if doctext.first_col != 0 {
      pan_to(0)
    }
  }

  ; going to the line at this row: it may end before the window
  sub pan_for_row(ubyte row) {
    if doctext.first_col != 0 and doctext.length(main.get_line_num(row)) <= doctext.first_col {
      pan_to(0)
    }
  }

  ; util functions
  sub update_tracker () {
    ubyte X = view.c()
    ubyte Y = view.r()

    ; Always draw tracker on the footer line only
    ; Use a known color scheme for footer baseline (optional)
    ; If you don't want this, remove these two lines.
    plat.colors($1,$6)   ; white on blue (example), match your normal scheme

    txt.plot(0, view.FOOTER_LINE)
    prints(view.BLANK_ROW)
    txt.plot(1, view.FOOTER_LINE)

    if flags.VERBOSE_STATUS == false {
      if @(doc.filepath+1) != $20 {
        plat.putc($22)
        prints(doc.filepath)
        plat.putc($22)
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
      txt.plot(plat.COLS-13, view.FOOTER_LINE)
      printW(Y - view.TOP_LINE + 1)
      prints(",")
      printW(doctext.first_col + (X - view.LEFT_MARGIN) + 1)
      txt.plot(plat.COLS-4, view.FOOTER_LINE)
      printW(main.lineCount)
    }
    else {
      printw(main.lineCount)
      prints(" lines, x: ")
      printw(doctext.first_col + (X - view.LEFT_MARGIN) + 1)
      prints(", y: ")
      printw(Y - view.TOP_LINE + 1)
      prints(" TOP: ")
      printw(view.CURR_TOP_LINE)
      prints(" BOT: ")
      printw(view.CURR_TOP_LINE + view.HEIGHT - 1)
      prints(" CNT: ")
      printw(main.NAVCHARCOUNT)

      ; Status badge MUST be on footer line (bugfix)
      txt.plot(plat.COLS-10, view.FOOTER_LINE)
      if flags.UNSAVED == true {
        plat.colors($6,$1)
        prints("(UNSAVED)")
        plat.colors($1,$6)
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
    plat.print(x)
  }

  sub say (str x) {
    plat.print(x)
    plat.nl()
  }

  sub printw (uword x) {
    plat.print(conv.str_uw0(x))
  }

  sub printW (uword x) {
    plat.print(conv.str_uw(x))
  }

  sub info_noblock_LEFT(str message) {
    alert_noblock_LEFT(message, $7, $6)
  }

  sub alert_noblock_LEFT(str message, ubyte color1, ubyte color2) {
    ubyte length = strings.length(message)
    txt.plot(1, 0)
    plat.colors(color1, color2)
    prints(message)
    plat.colors($1, $6) ; sets text back to default, white on blue
  }

  sub info_noblock(str message) {
    alert_noblock(message, $7, $6)
  }

  sub alert_noblock(str message, ubyte color1, ubyte color2) {
    ubyte length = strings.length(message)
    txt.plot(right_col(length), 0)
    plat.colors(color1, color2)
    prints(message)
    plat.colors($1, $6) ; sets text back to default, white on blue
  }

  ; the column of a message that ends at the right side of the top row
  sub right_col(ubyte length) -> ubyte {
    if length >= plat.COLS-2 {
      return 0
    }
    return plat.COLS-2-length
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
    txt.plot(right_col(length), 0)
    plat.colors(color1, color2)
    prints(message)
    sys.wait(delay)
    txt.plot(right_col(length), 0)
    plat.colors($1, $6) ; sets text back to default, white on blue
    txt.plot(view.LEFT_MARGIN, 0)
    prints(view.BLANK_ROW)
    txt.plot(c,r)
  }
}

