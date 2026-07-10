; ============================================================
; vic20_worker.asm
; VIC-20-side Monte Carlo local worker.
;
; Mechanical port of c64_worker.asm to the VIC-20 + 3K memory map.
; The worker is blocking and returns to BASIC through RTS.
; ============================================================

.include "generated_vic20.inc"

.export _start

.segment "LOADADDR"
.word VIC20_LOAD

.segment "CODE"
_start:
        lda #$01
        sta STATUS

        lda #$00
        sta INLO
        sta INHI

        lda ITERLO
        ora ITERHI
        beq done

main_loop:
        jsr rand8
        sta TMPX
        tax

        jsr rand8
        cmp TABLE,x
        bcc inside
        beq inside
        jmp next_iter

inside:
        inc INLO
        bne next_iter
        inc INHI

next_iter:
        lda ITERLO
        bne dec_lo
        lda ITERHI
        beq done
        dec ITERHI

dec_lo:
        dec ITERLO
        lda ITERLO
        ora ITERHI
        bne main_loop

done:
        lda #$02
        sta STATUS
        rts

rand8:
        jsr rand16
        jsr rand16
        rts

rand16:
        lda SEEDLO
        beq seedlo_zero
        jmp seed_ok

seedlo_zero:
        lda SEEDHI
        bne seed_ok
        lda #$A5
        sta SEEDLO
        lda #$5A
        sta SEEDHI

seed_ok:
        lda SEEDLO
        and #$01
        sta TMPF
        lda SEEDHI
        lsr
        sta SEEDHI
        lda SEEDLO
        ror
        sta SEEDLO
        lda TMPF
        beq no_xor
        lda SEEDHI
        eor #$B4
        sta SEEDHI

no_xor:
        lda SEEDHI
        rts

.assert * <= VIC20_PARAMS, error, "vic20_worker code overlaps parameter block"

.segment "PARAMS"
        .res $60, $00

.segment "TABLE"
        .res 256, $00
