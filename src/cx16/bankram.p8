; X16 banked RAM transport. Banks 0..3 belong to the system/other services.
; All transfers restore both the bank selector and processor interrupt flags.
%import syslib
bankram {
    const uword RESERVED = 4
    sub banks() -> uword { return cx16.numbanks() }
    sub read(long offset, pointer dest, uword count) {
        long bank_index = offset
        bank_index >>= 13
        ubyte bank = bank_index as ubyte + RESERVED as ubyte
        uword address = $a000 + (offset & $1fff) as uword
        transfer(bank, address, dest as uword, count)
    }
    sub write(long offset, pointer source, uword count) {
        long bank_index = offset
        bank_index >>= 13
        ubyte bank = bank_index as ubyte + RESERVED as ubyte
        uword address = $a000 + (offset & $1fff) as uword
        transfer(bank, source as uword, address, count)
    }
    ; count must stay within the selected 8 KiB bank; callers split transfers.
    asmsub transfer(ubyte bank @A, uword source @R0, uword dest @R1, uword count @R2) clobbers(A,X,Y) {
        %asm {{
            php
            sei
            sta P8ZP_SCRATCH_B1
            lda $00
            pha
            lda P8ZP_SCRATCH_B1
            sta $00
            lda cx16.r0
            sta P8ZP_SCRATCH_W1
            lda cx16.r0+1
            sta P8ZP_SCRATCH_W1+1
            lda cx16.r1
            sta P8ZP_SCRATCH_W2
            lda cx16.r1+1
            sta P8ZP_SCRATCH_W2+1
            ldy #0
            ldx cx16.r2+1
            beq _tail
_page
            lda (P8ZP_SCRATCH_W1),y
            sta (P8ZP_SCRATCH_W2),y
            iny
            bne _page
            inc P8ZP_SCRATCH_W1+1
            inc P8ZP_SCRATCH_W2+1
            dex
            bne _page
_tail
            ldx cx16.r2
            beq _done
_copy
            lda (P8ZP_SCRATCH_W1),y
            sta (P8ZP_SCRATCH_W2),y
            iny
            dex
            bne _copy
_done
            pla
            sta $00
            plp
            rts
        }}
    }
}
