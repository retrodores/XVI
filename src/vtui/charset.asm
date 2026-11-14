; Project extension for the archived VTUI-C1C7 binary, fixed base $8800.
; Preserve X and Y. A is input and output; arithmetic flags are volatile.
* = $8bcc
pet_to_screen:
    cmp #$20
    bcc control_low
    cmp #$40
    bcc done
    cmp #$60
    bcc subtract_40
    cmp #$80
    bcc subtract_20
    cmp #$a0
    bcc control_high
    cmp #$c0
    bcc subtract_40
    cmp #$ff
    beq pi
    and #$7f
    rts
control_low:
    ora #$80
    rts
control_high:
    ora #$40
    rts
subtract_40:
    sec
    sbc #$40
    rts
subtract_20:
    sec
    sbc #$20
done:
    rts
pi:
    lda #$5e
    rts

; Ignore the reverse screen bit; return canonical PETSCII glyph spelling.
screen_to_pet:
    and #$7f
    cmp #$20
    bcc add_40
    cmp #$40
    bcc screen_done
    cmp #$60
    bcc add_80
    clc
    adc #$40
    rts
add_40:
    clc
    adc #$40
    rts
add_80:
    ora #$80
screen_done:
    rts
