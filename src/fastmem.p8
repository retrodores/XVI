; fastmem: byte scans and copies for the text stores, in 6502 assembler
; (the plain 6502: also the X16's 65C02).  A target imports it from its
; fastmem_platform.p8; the virtual target has Prog8 versions of the same
; routines (src/virtual/fastmem_platform.p8).
;
; Each loop is "lda (ptr),y" over 256 bytes at a time: about 15 cycles a
; byte, against about 75 for the Prog8 loops they replace.

fastmem {

    ; the offset of the first value in the n bytes at p, or n if none
    asmsub find(uword p @R0, uword n @R1, ubyte value @A) clobbers(X) -> uword @AY {
        %asm {{
            sta  P8ZP_SCRATCH_B1
            lda  cx16.r0
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r0+1
            sta  P8ZP_SCRATCH_W1+1
            ldy  #0
            ldx  cx16.r1+1          ; whole pages
            beq  _last
_page
            lda  (P8ZP_SCRATCH_W1),y
            cmp  P8ZP_SCRATCH_B1
            beq  _found
            iny
            bne  _page
            inc  P8ZP_SCRATCH_W1+1
            dex
            bne  _page
_last
            ldx  cx16.r1            ; the bytes left
            beq  _none
-           lda  (P8ZP_SCRATCH_W1),y
            cmp  P8ZP_SCRATCH_B1
            beq  _found
            iny
            dex
            bne  -
_none
            lda  cx16.r1
            ldy  cx16.r1+1
            rts
_found
            ; the offset: y, and the pages gone past
            tya
            pha
            sec
            lda  P8ZP_SCRATCH_W1+1
            sbc  cx16.r0+1
            tay
            pla
            rts
        }}
    }

    ; the offset of the last value in the n bytes at p, or $ffff if none
    asmsub find_back(uword p @R0, uword n @R1, ubyte value @A) clobbers(X) -> uword @AY {
        %asm {{
            sta  P8ZP_SCRATCH_B1
            ; start in the last (partial) page: p + (n & $ff00)
            lda  cx16.r0
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r0+1
            clc
            adc  cx16.r1+1
            sta  P8ZP_SCRATCH_W1+1
            ldx  cx16.r1+1          ; whole pages below it
            ldy  cx16.r1            ; bytes in it
            beq  _pages
-           dey
            lda  (P8ZP_SCRATCH_W1),y
            cmp  P8ZP_SCRATCH_B1
            beq  _found
            cpy  #0
            bne  -
_pages
            cpx  #0
            beq  _none
            dec  P8ZP_SCRATCH_W1+1
            dex
            ldy  #0
-           dey
            lda  (P8ZP_SCRATCH_W1),y
            cmp  P8ZP_SCRATCH_B1
            beq  _found
            cpy  #0
            bne  -
            beq  _pages
_none
            lda  #$ff
            tay
            rts
_found
            tya
            pha
            sec
            lda  P8ZP_SCRATCH_W1+1
            sbc  cx16.r0+1
            tay
            pla
            rts
        }}
    }

    ; how many times value is in the n bytes at p
    asmsub count(uword p @R0, uword n @R1, ubyte value @A) clobbers(X) -> uword @AY {
        %asm {{
            sta  P8ZP_SCRATCH_B1
            lda  cx16.r0
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r0+1
            sta  P8ZP_SCRATCH_W1+1
            lda  #0
            sta  P8ZP_SCRATCH_W2
            sta  P8ZP_SCRATCH_W2+1
            tay
            ldx  cx16.r1+1          ; whole pages
            beq  _last
_page
            lda  (P8ZP_SCRATCH_W1),y
            cmp  P8ZP_SCRATCH_B1
            bne  +
            inc  P8ZP_SCRATCH_W2
            bne  +
            inc  P8ZP_SCRATCH_W2+1
+           iny
            bne  _page
            inc  P8ZP_SCRATCH_W1+1
            dex
            bne  _page
_last
            ldx  cx16.r1            ; the bytes left
            beq  _done
-           lda  (P8ZP_SCRATCH_W1),y
            cmp  P8ZP_SCRATCH_B1
            bne  +
            inc  P8ZP_SCRATCH_W2
            bne  +
            inc  P8ZP_SCRATCH_W2+1
+           iny
            dex
            bne  -
_done
            lda  P8ZP_SCRATCH_W2
            ldy  P8ZP_SCRATCH_W2+1
            rts
        }}
    }

    ; copy n bytes from src to dest, also when they overlap
    ; (sys.memcopy can't do that)
    asmsub move(uword src @R0, uword dest @R1, uword n @R2) clobbers(A, X, Y) {
        %asm {{
            lda  cx16.r1+1
            cmp  cx16.r0+1
            bne  +
            lda  cx16.r1
            cmp  cx16.r0
            bne  +
            rts                     ; dest == src
+           bcs  _down
            ; dest below src: upwards, from the start
            lda  cx16.r0
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r0+1
            sta  P8ZP_SCRATCH_W1+1
            lda  cx16.r1
            sta  P8ZP_SCRATCH_W2
            lda  cx16.r1+1
            sta  P8ZP_SCRATCH_W2+1
            ldy  #0
            ldx  cx16.r2+1          ; whole pages
            beq  _up_last
_up_page
            lda  (P8ZP_SCRATCH_W1),y
            sta  (P8ZP_SCRATCH_W2),y
            iny
            bne  _up_page
            inc  P8ZP_SCRATCH_W1+1
            inc  P8ZP_SCRATCH_W2+1
            dex
            bne  _up_page
_up_last
            ldx  cx16.r2            ; the bytes left
            beq  _done
-           lda  (P8ZP_SCRATCH_W1),y
            sta  (P8ZP_SCRATCH_W2),y
            iny
            dex
            bne  -
_done
            rts
_down
            ; dest above src: downwards, from the end.  the last (partial)
            ; page first: src/dest + (n & $ff00)
            lda  cx16.r0
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r0+1
            clc
            adc  cx16.r2+1
            sta  P8ZP_SCRATCH_W1+1
            lda  cx16.r1
            sta  P8ZP_SCRATCH_W2
            lda  cx16.r1+1
            clc
            adc  cx16.r2+1
            sta  P8ZP_SCRATCH_W2+1
            ldx  cx16.r2+1          ; whole pages below it
            ldy  cx16.r2            ; bytes in it
            beq  _down_pages
-           dey
            lda  (P8ZP_SCRATCH_W1),y
            sta  (P8ZP_SCRATCH_W2),y
            cpy  #0
            bne  -
_down_pages
            cpx  #0
            beq  _done
            dec  P8ZP_SCRATCH_W1+1
            dec  P8ZP_SCRATCH_W2+1
            dex
            ldy  #0
-           dey
            lda  (P8ZP_SCRATCH_W1),y
            sta  (P8ZP_SCRATCH_W2),y
            cpy  #0
            bne  -
            beq  _down_pages
            ; !notreached!
        }}
    }
}
