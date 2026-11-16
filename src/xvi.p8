%import textio
%import conv
%import syslib
%import diskio
%import string
%option no_sysinit
%zeropage basicsafe

; started simple test program for the "VTUI" text user interface library
; see:  https://github.com/JimmyDansbo/VTUIlib

main {
    ubyte i,j
    const ubyte minCol            = 2
    const ubyte minLine           = 2
    const ubyte maxCol            = 77
    const ubyte maxLine           = 57
    const ubyte BASE_LINE_SIZE    = (maxCol-minCol)+1
    ubyte LINE                    = minLine
    ubyte COL                     = minCol
    str currFilename              = " " * (maxCol-minCol)
    ubyte CMDBUFFER_SIZE          = 50
    uword CLIPBOARD_VERA_ADDR     = $0006
    uword TMP_LINE_BUFF_VERA_ADDR = $6000

    sub vtg(ubyte col, ubyte line) {
      vtui.gotoxy(col, line)
    }

    sub init_canvas() {
      vtui.initialize()
      vtui.screen_set(0)
      vtui.clr_scr(' ', $50)
      vtg(minCol-1,minLine-1)
      vtui.fill_box(' ', maxCol, maxLine, $c6)
      vtg(minCol-1,minLine-1)
      vtui.border(1, maxCol+1, maxLine+1, $00)
    }

    sub blank_line(ubyte line)  {
      vtg(main.minCol, line)
      vtui.fill_box(' ', BASE_LINE_SIZE, 1, $c6) ; blank out line being moved in original position
    }

    sub blank_1x1(ubyte col, ubyte line)  {
      vtg(col, line)
      vtui.fill_box(' ', 1, 1, $c6)         ; blank out line being moved in original position
    }

    sub place_cursor(ubyte col, ubyte line) {
      vtg(col, line)
      uword fullChar = vtui.scan_char()     ; get screen code
      ubyte char     = lsb(fullChar)
      vtg(col, line)
      vtui.plot_char(char, $61)
    }

    sub cursor_presave(ubyte col, ubyte line) {
      vtg(col, line)
      vtui.save_rect($80, true, $0002, 1, 1)   ; save what is under cursor for save_rect
    }

    sub cursor_restore(ubyte col, ubyte line) {
      vtg(col, line)
      vtui.rest_rect($80, true, $0002, 1, 1)   ; restore what is under cursor for save_rect
    }

    sub copy_1x1(ubyte line) {
      vtg(main.minCol,line)
      vtui.save_rect($80, true, $0004, 1, 1)   ; save line so it's available to (P)aste
    }

    sub copy_line_to_clipboard(ubyte line) {
      vtg(main.minCol,line)
      vtui.save_rect($80, true, CLIPBOARD_VERA_ADDR, BASE_LINE_SIZE, 1)  ; save line so it's available to (P)aste
    }

    sub cut_line_and_copy_to_clipboard(ubyte line)  {
      copy_line_to_clipboard(line)                           ; copy
      vtg(main.minCol,line)                                  ; go to line again, for "cut"
      vtui.fill_box(' ', BASE_LINE_SIZE, 1, $c6)  ; blank out line being moved in original position
    }

    sub paste_line_from_clipboard(ubyte line) {
      vtg(main.minCol,line)
      vtui.rest_rect($80, true, CLIPBOARD_VERA_ADDR, BASE_LINE_SIZE, 1)  ; restore rectangle
    }

    sub updateXY_ticker() {
        ubyte x = main.COL  ;cx16.VERA_ADDR_L / 2   ; cursor X coordinate
        ubyte y = main.LINE ;cx16.VERA_ADDR_M - $b0 ; cursor Y coordinate

        vtg(68,main.maxLine+1)
        vtui.fill_box(' ', 7, 1, $00)
        vtg(68,main.maxLine+1)

        conv.str_ub0(x-2)
        vtui.print_str2(conv.string_out, $01, true)

        vtui.print_str2(" ", $01, true)

        conv.str_ub0(y-2)
        vtui.print_str2(",", $01, true)
        vtui.print_str2(conv.string_out, $01, true)

        vtg(main.COL,main.LINE)
    }

    sub draw_cursor(ubyte col, ubyte line) {
        vtg(col, line);
        vtui.fill_box(' ', 1, 1, $e1)
    }

    sub init_cursor(ubyte col, ubyte line) {; full initial set up of cursor
        cursor_presave(col, line);
        draw_cursor(col, line)
    }

    sub restore_border() {
        vtg(main.maxCol+1,main.LINE)
        vtui.fill_box(' ', 1, 1, $00)
        vtg(main.maxCol+2,main.LINE)
        vtui.fill_box(' ', 3, 1, $50)
        vtg(main.COL,main.LINE)
    }

    sub open_file(str filepath) {
        if diskio.f_open(filepath) {
          main.currFilename = filepath
          for j in main.minLine to main.maxLine   {
            str lineBuffer = " " *  100 
            uword size
            size, void = diskio.f_readline(lineBuffer)
            str lineToShow = " " * (main.maxCol - main.minCol)
            string.slice(lineBuffer, 0, (main.maxCol - main.minCol)-1, lineToShow) ; make sure line conforms to current view port
            string.rstrip(lineToShow)
            blank_line(j)
            vtg(main.minCol, j)
            vtui.print_str2(lineToShow, $c6, true)
          }
          diskio.f_close()
          init_move_cursor(main.minCol,main.LINE)
          vtg(main.minCol-1,main.maxLine+1);
          vtui.print_str2("opened file: ", $e1, true)
          vtui.print_str2(filepath, $e1, true)
          sys.wait(50)
          vtg(main.minCol-1,main.maxLine+1);
          vtui.fill_box(' ', string.length(filepath)+13, 1, $00)
        }
        else {
          vtg(main.minCol-1,main.maxLine+1);
          vtui.print_str2("error opening file: ", $21, true)
          vtui.print_str2(filepath, $21, true)
          sys.wait(50)
          vtg(main.minCol-1,main.maxLine+1);
          vtui.fill_box(' ', string.length(filepath)+21, 1, $00)
        }
    }

    sub save_file(str fname) {
      str filepath = " " * (main.maxCol - main.minCol) 
      filepath="@0:"
      string.append(filepath, fname)
      string.strip(filepath)

      ; show pre-command messages
      vtg(main.minCol-1,main.maxLine+1);
      vtui.print_str2("saving file: ", $f1, true)
      vtui.print_str2(fname, $f1, true)

      cursor_restore(main.COL, main.LINE)         ; restore what was under the cursor for saving
      diskio.f_open_w_seek(filepath)              ; open file for writing
      vtg(main.minCol, main.minLine)
      for j in main.minLine to main.maxLine {
        for i in main.minCol to main.maxCol {
          vtg(i, j)                               ; go to location of char to get
          uword fullChar = vtui.scan_char()       ; get screen code and color
          ubyte char = lsb(fullChar)              ; extract char from word
          vtg(i, j)                               ; go to next line
          ubyte petchar = vtui.scr2pet(char)      ; convert screen code to petscii, for writing to file
          diskio.f_write(&petchar, 1)             ; write to file (using reference to "petchar")
        }
       diskio.f_write("\x0d", 1)
      }
      diskio.f_close_w()
      vtg(main.minCol-1,main.maxLine+1);
      vtui.fill_box(' ', string.length(fname)+13, 1, $00)
      vtg(main.minCol-1,main.maxLine+1);
      vtui.print_str2(" saved", $e1, true)
      sys.wait(10)
      vtg(main.minCol-1,main.maxLine+1);
      vtui.fill_box(' ', string.length(fname)+13, 1, $00)
      init_move_cursor(main.minCol,main.minLine)
    }

    sub start() {
        init_canvas()
        init_cursor(main.minCol,main.minLine)

        str initfile = "readme.txt"
        open_file(initfile)

        move_cursor(main.minCol,main.minLine)

        navMode() ; start off in nav mode, which is expected
        bool cond = true
        while cond {
           vtg(main.COL,main.LINE)
           str inputbuffer = " " * BASE_LINE_SIZE ; this is the width of the inner box vtui box
           updateXY_ticker()

           ; if the last key is ESC, input_str will exit - we check to see
           ; if it was ESC (not RET), put in navMode if ESC, go to next line
           ; in "editMode" if not - getting very close to vi-like modalities

           vtg(main.COL, main.LINE)
           uword AX       = vtui.input_str_retboth(inputbuffer, main.BASE_LINE_SIZE, $c6)
           ubyte lastkey  = lsb(AX)
           ubyte inputLen = msb(AX)

           restore_border();

           if lastkey == $1b {                  ; $1b is <ESC>
             main.COL  = cx16.VERA_ADDR_L / 2   ; cursor X coordinate
             main.LINE = cx16.VERA_ADDR_M - $b0 ; cursor Y coordinate
             init_move_cursor(main.COL, main.LINE)
             updateXY_ticker()
             navMode()
           }

           main.COL  = main.minCol 
           main.LINE = main.LINE + 1
replace_mode:
           update_activity("--replace--")
        }
   }

   sub navMode() {
      update_activity("nav mode")
      updateXY_ticker()
navstart:
      vtui.fill_box(' ', 1, 1, $e1)
      ubyte    delN  = 0        ; dd (delete line) counter
      ubyte    cpyN  = 0        ; YY (copline) counter
      ubyte    nngN  = 0        ; NN SHIFT+g counter
      ubyte[2] numb  = [0] * 2  ; digit for "NN SHIFT+g"

navcharloop:
      ubyte char
      void, char = cbm.GETIN()

      ; catch leading numbers for "NN SHIFT+g"
      when char {
          $c7 -> { ; jump to the bottom (SHIFT+g)
            if nngN == 1 {
              nngN = 0          ; reset digit counter for "NN SHIFT+g"
              move_cursor(main.minCol,main.minLine-1+numb[0])
              goto navcharloop
            }
            if nngN == 2 {
              nngN = 0          ; reset digit counter for "NN SHIFT+g"
              move_cursor(main.minCol,main.minLine-1+(numb[0]*10+numb[1]))
              goto navcharloop
            }
          }
          $30 -> { ; bare '0' jumps to start of line
            when nngN {
              0 -> {
                ;; jump to start of the current line
                move_cursor(main.minCol,main.LINE)
              }
              1 -> {
                numb[nngN] = char - $30
                nngN++
              }
              else -> {
                nngN = 0
              }

            }
            goto navcharloop
          }
          $31,$32,$33,$34,$35,$36,$37,$38,$39 -> { ; digits 1-9
            if nngN < 2 {
              numb[nngN] = char - $30
              nngN++
            }
            else {
              nngN = 0
            }
            goto navcharloop
          }
      }

      when char {
          $1b -> { ; ESC key
            goto navcharloop
          }
;; i
;; shift+r
          $49, $D2 -> { ; (i) or (shift+r)
            ; NOTE: goes into "--REPLACE--" mode because the more useful
            ; and familiar "--INSERT--" mode is not yet supported
            goto main.start.replace_mode
          }
;; r
          $52 -> { ; r
            update_activity("pls ask 4: r") 
            sys.wait(20)
            update_activity("nave mode")
          }
;; k
;; cursor up 
          $4b, $91 -> { ; nav up (k)
            if main.LINE > minLine {
              move_cursor(main.COL,main.LINE-1)
            }
          }
;; j
;; cursor down
          $4a, $11 -> { ; nav down (j)
            if main.LINE < maxLine {
              move_cursor(main.COL,main.LINE+1)
            }
          }
;; h
;; cursor left
          $48, $9d -> { ; nav left (h)
            if main.COL > minCol {
              move_cursor(main.COL-1,main.LINE)
            }
          }
;; l
;; cursor right
          $4c, $1d -> { ; nav right (l)
            if main.COL < maxCol {
              move_cursor(main.COL+1,main.LINE)
            }
          }
;; shift+g
          $c7 -> { ; jump to the bottom (SHIFT+g)
            move_cursor(main.minCol,main.maxLine)
          }
;; <space>
;; not exactly what's in standard vi, due to the current limitation of only supporting "replace" mode 
          $20 -> {
            right_shift_spc()
          }
;; ^
;; jump to start of the current line
          $5E -> { ; ^ (SHIFT+6), jump to start of the line
            move_cursor(main.minCol,main.LINE)
          }
;; $
;; jump to the end of the current line
          $24 -> { ; $ (SHIFT+4), jump to start of the line
            move_cursor(main.maxCol,main.LINE)
          }
;; x
;; note - single character delete; unlike standard vi this doesn't place the character into the clipboard 
          $58 -> { ; delete, move left (x)
            left_shift_x()
          }
;; dd
;; note - full line "cut"
          $44 -> { ; cut (d+d) delete current line, shift all lines from main.LINE to main.maxLine up 1
            when delN {
              0 -> {
                delN++
                update_activity("d")
                goto navcharloop
              }
              1 -> {
                delN = 0
              }
            }
            update_activity("dd")
            if main.LINE+1 <= main.maxLine {         ; do delete
              cursor_restore(main.COL, main.LINE)    ; restore what is under cursor before moving lines
              copy_line_to_clipboard(main.LINE)      ; save line to paste buffer
              ; cut line, store in clipboard, shift lines up 1
              vtg(main.minCol, main.LINE+1)
              vtui.save_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)    ; save line to move up
              blank_line(main.LINE+1)
              vtg(main.minCol, main.LINE)
              vtui.rest_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)    ; restore line being moved up
              cursor_presave(main.COL, main.LINE)     ; save what's in the space the cursor is about to occupy 
              for j in main.LINE+1 to main.maxLine-1 {
                vtg(main.minCol, j+1)
                vtui.save_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)  ; save line to move up
                vtg(main.minCol, j)
                vtui.rest_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)  ; restore line being moved up
              }
              blank_line(main.maxLine)                ; enforces max line to main.maxLine, adds blank that moves up ...
              move_cursor(main.minCol, main.LINE)
            }
            sys.wait(2)                               ; so "DD" can be visible; too much?
            update_activity("nav mode")
          }
;; yy
;; note - full line "yank", places line into clipboard for pasting
          $59 -> { ; copy (y+line), no cursor advancement
            when cpyN {
              0 -> {
                cpyN++
                update_activity("y")
                goto navcharloop
              }
              1 -> {
                cpyN = 0
              }
            }
            update_activity("yy")
            cursor_restore(main.COL, main.LINE)       ; restore what is under cursor before moving lines
            copy_line_to_clipboard(main.LINE)         ; yank (copline) line into clipboard buffer
            init_move_cursor(main.minCol, main.LINE)  ; get cursor visible
            update_activity("nav mode")
          }
;; p
;; note - paste what is in the clipboard to the line below current line 
          $50 -> { ; paste under current line (p)
            update_activity("p")
            if ( main.LINE < main.maxLine) {
              cursor_restore(main.COL, main.LINE)       ; restore what is under cursor before moving lines
              for i in main.maxLine downto main.LINE+2 {
                vtg(main.minCol, i-1)                   ; jump to line above
                vtui.save_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)    ; copy line above 
                vtg(main.minCol, i)                     ; jump to line below
                vtui.rest_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)    ; restore 2nd to line below
              }
              blank_line(main.LINE+1) 
              paste_line_from_clipboard(main.LINE+1)    ; paste from clipboard to line below initial line
              init_move_cursor(main.minCol, main.LINE+1)  ; get cursor visible
            }
            update_activity("nav mode")
          }
;; shift+p
;; note - paste what is in the clipboard to the current line, shifts everything below it down 
          $D0 -> { ; paste above (SHIFT+p)
            update_activity("shift+p")
            if ( main.LINE < main.maxLine) {
              cursor_restore(main.COL, main.LINE)        ; restore what is under cursor before moving lines
              for i in main.maxLine downto main.LINE+1 {
                vtg(main.minCol, i-1)                    ; jump to line above
                vtui.save_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)     ; copy line above 
                vtg(main.minCol, i)                      ; jump to line below
                vtui.rest_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)     ; restore 2nd to line below
              }
              blank_line(main.LINE)
              paste_line_from_clipboard(main.LINE)       ; paste from clipboard to line below initial line
              vtg(main.minCol, main.LINE)
              init_move_cursor(main.minCol, main.LINE)
            }
            update_activity("nav mode")
          }
;; o
;; note - basically same implementation as "paste" for $50, but without actually pasting what's in the clipboard
          $4f -> { ; lowercase "oh" (o), insert line below; switch to INSERT mode
            update_activity("o")
            if ( main.LINE < main.maxLine) {
              cursor_restore(main.COL, main.LINE)       ; restore what is under cursor before moving lines
              for i in main.maxLine downto main.LINE+2 {
                vtg(main.minCol, i-1)                   ; jump to line above
                vtui.save_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)    ; copy line above 
                vtg(main.minCol, i)                     ; jump to line below
                vtui.rest_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)    ; restore 2nd to line below
              }
              blank_line(main.LINE+1) 
              init_move_cursor(main.minCol, main.LINE+1)  ; get cursor visible
            }
            update_activity("nav mode")
            goto main.start.replace_mode
          }
;; shift+o
;; note - basically same implementation as "paste" for $D0, but without actually pasting what's in the clipboard
          $cf -> { ; uppercase "oh" (SHIFT+o), insert line above
            update_activity("shift+o")
            if ( main.LINE < main.maxLine) {
              cursor_restore(main.COL, main.LINE)        ; restore what is under cursor before moving lines
              for i in main.maxLine downto main.LINE+1 {
                vtg(main.minCol, i-1)                    ; jump to line above
                vtui.save_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)     ; copy line above 
                vtg(main.minCol, i)                      ; jump to line below
                vtui.rest_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, BASE_LINE_SIZE, 1)     ; restore 2nd to line below
              }
              blank_line(main.LINE)
              vtg(main.minCol, main.LINE)
              init_move_cursor(main.minCol, main.LINE)
            }
            update_activity("nav mode")
            goto main.start.replace_mode
          }
; start of command mode handling
          $3a -> { ; colon (:)
            vtg(main.minCol-1,main.maxLine+1);
            vtui.fill_box(' ', 50, 1, $06)
            vtg(main.minCol-1,main.maxLine+1);
            vtui.print_str2(": ", $01, true);
            str cmdbuffer = " " * main.CMDBUFFER_SIZE 
            vtg(3,main.maxLine+1);
            ubyte retval = vtui.input_str(cmdbuffer, 50, $01)
            if (cmdbuffer[0] == 'q') {
              ;if (cmdbuffer[1] == '!') {
                vtg(1,1)
                txt.clear_screen()
                txt.print("thank you for using xvi, the vi clone for the x16!\n\n")
                txt.print("for updates, please visit\n\n")
                txt.print("https://github.com/oodler577/xvi\n")
                sys.exit(0)
              ;}
            }
            else if (cmdbuffer[0] == 'e') {
              str fn1 = " " * main.CMDBUFFER_SIZE 
              string.slice(cmdbuffer, 2, string.length(cmdbuffer), fn1)
              string.strip(fn1)
              open_file(fn1)
              ; show post-command messages
              ;; ** look in "open_file" subroutine above
            }
            else if (cmdbuffer[0] == 'w') {
              str fn2 = " " * main.CMDBUFFER_SIZE 
              string.slice(cmdbuffer, 2, string.length(cmdbuffer), fn2)
              string.strip(fn2)
              if (string.length(fn2) == 0) {
                fn2 = main.currFilename
              }
              else {
                main.currFilename = fn2
              }
              save_file(fn2)
              ; show post-command messages
              ;; ** look in "save_file" subroutine above
              if (cmdbuffer[1] == 'q') {
                vtg(1,1)
                txt.clear_screen()
                txt.print("thank you for using xvi, the vi clone for the x16!\n\n")
                txt.print("for updates, please visit\n\n")
                txt.print("https://github.com/oodler577/xvi\n")
                sys.exit(0)
              }
            }
            else {
              vtg(main.minCol-1,main.maxLine+1);
              vtui.fill_box(' ', 50, 1, $21)

              ; show post-command messages
              vtg(main.minCol-1,main.maxLine+1);
              vtui.print_str2("not an editor command ", $21, true)
              string.strip(cmdbuffer)
              vtui.print_str2(cmdbuffer, $21, true)
              sys.wait(50)
              vtg(main.minCol-1,main.maxLine+1);
              vtui.fill_box(' ', 50+string.length(cmdbuffer), 1, $50)
            }
            cmdbuffer = " " * main.CMDBUFFER_SIZE 
          }
     }
     goto navcharloop
   }

   sub update_activity(str activity) {
     vtg(65, main.minLine-1) 
     vtui.fill_box(' ', 12, 1, $00)
     vtg(65, main.minLine-1)
     vtui.print_str2(activity, $01, true)
     vtg(main.COL,main.LINE)
   } 

   sub right_shift_spc()  {
     for i in main.maxCol-1 downto main.COL {
       vtg(i,main.LINE)
       vtui.save_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, 1, 1); save line so it's available to (P)aste
       blank_1x1(main.COL,main.LINE)
       vtg(i+1,main.LINE)
       vtui.rest_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, 1, 1); restore line so it's available to (P)aste
     }

     vtg(main.COL,main.LINE)
     vtui.rest_rect($80, true, $0002, 1, 1)  ; save line so it's available to (P)aste
     vtg(main.COL,main.LINE)
     vtui.save_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, 1, 1)  ; save line so it's available to (P)aste

     blank_1x1(main.COL,main.LINE)
     cursor_presave(main.COL,main.LINE)
     move_cursor(main.COL,main.LINE)

     ; mind RHS text area bounds
     if (main.COL < main.maxCol) {
       vtg(main.COL+1,main.LINE)
       vtui.rest_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, 1, 1)  ; restore line so it's available to (P)aste
       cursor_restore(main.COL, main.LINE)   ; restore what is under cursor for save_rect
       move_cursor(main.COL+1, main.LINE)
     }
   }

   sub left_shift_x()  {
     blank_1x1(main.maxCol, main.LINE)
     for i in main.COL to main.maxCol-1 {  ; 
       vtg(i+1,main.LINE)
       vtui.save_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, 1, 1); save line so it's available to (P)aste
       vtg(i,main.LINE)
       vtui.rest_rect($80, true, TMP_LINE_BUFF_VERA_ADDR, 1, 1); save line so it's available to (P)aste
     }
     blank_1x1(main.maxCol,main.LINE)
     cursor_presave(main.COL,main.LINE)
     move_cursor(main.COL,main.LINE)
   }

   sub move_cursor(ubyte col, ubyte line) {
     cursor_restore(main.COL, main.LINE)   ; restore what was under the cursor
     cursor_presave(col, line)             ; save what's current in the new position
     place_cursor(col, line)               ; place cursor in new position
     main.COL  = col 
     main.LINE = line 
     updateXY_ticker()
   }

   ; use when cursor has been ignored for a while, e.g., see case for handling "shift+p"
   sub init_move_cursor(ubyte col, ubyte line) {
     cursor_presave(col, line)             ; save what's current in the new position
     place_cursor(col, line)               ; place cursor in new position
     main.COL  = col 
     main.LINE = line 
     updateXY_ticker()
   }
}

;
; Below this line is the bindings using for the VTUI library via Prog8's "extsub" keyword
;

vtui $8800 {

    %option no_symbol_prefixing
    %asmbinary "VTUI-C1C7.BIN", 2     ; skip the 2 dummy load address bytes

    ; NOTE: base address $1000 here must be the same as the block's memory address, for obvious reasons!
    ; The routines below are for VTUI 1.0
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

    ; -- helper function to do string length counting for you internally, and turn the convertchars flag into a boolean again
    asmsub print_str2(str txtstring @R0, ubyte colors @X, bool convertchars @Pc) clobbers(A, Y) {
        %asm {{
            lda  #0
            bcs  +
            lda  #$80
+           pha
            lda  cx16.r0
            ldy  cx16.r0+1
            jsr  prog8_lib.strlen
            pla
            jmp  print_str
        }}
    }
}
