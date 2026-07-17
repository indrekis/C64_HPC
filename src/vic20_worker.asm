; ============================================================
; vic20_worker.asm
; ca65/ld65 version
; VIC-20-side Monte Carlo local worker.
;
; Mechanical port of c64_worker.asm to the VIC-20 + 3K memory map.
; The worker is blocking and returns to BASIC through RTS.
; Details -- see c64_worker.asm
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

        ; The all-zero LFSR state would remain zero forever.
        ; Check it once before entering the hot loop.
        lda SEEDLO
        ora SEEDHI
        bne seed_ready
        lda #$A5
        sta SEEDLO
        lda #$5A
        sta SEEDHI

seed_ready:
        ; Keep the low byte of the 16-bit iteration counter in Y.
        ldy ITERLO

main_loop:
        jsr rand8
        tax

        jsr rand8
        cmp TABLE,x
        bcc inside
        bne next_iter ; Equal also falls through to inside

inside:
        inc INLO
        bne next_iter
        inc INHI

next_iter:
        ; Decrement the 16-bit iteration counter ITERHI:Y.
        tya
        bne dec_lo
        dec ITERHI

dec_lo:
        dey             ; --Y
        tya
        ora ITERHI
        bne main_loop
        sty ITERLO      ; Preserve the externally visible zero counter

done:
        lda #$02
        sta STATUS
        rts

rand8:
        jsr rand16
        jmp rand16     ; Tail call: return directly after the second step

rand16:
        lsr SEEDHI     ; Shift high byte right; C gets its previous bit 0
        ror SEEDLO     ; Shift low byte through C; C gets the old LFSR bit 0
        bcc no_xor     ; Apply feedback only when the old bit 0 was 1
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
