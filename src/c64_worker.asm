; ============================================================
; c64_worker.asm
; ca65/ld65 version
; C64-side Monte Carlo worker
; Iteration counter is 16-bit -- max 65535
; Is blocking so STATUS variable is not that useful
; ============================================================

.include "generated_c64.inc"

.export _start

.segment "LOADADDR"
        .word C64_LOAD ; make_basic.py removes this

.segment "CODE"

_start:
        lda #$01
        sta STATUS ; Status flag, 1 -- worker is running. More important for the FDD

        ; INLO:INHI -- 16-bit counter of how many random points were inside the quarter circle. 
        lda #$00
        sta INLO
        sta INHI

        ; If ITERLO:ITERHI == 0, there is no work to do.
        lda ITERLO
        ora ITERHI
        beq done

main_loop:
        ; Returns 8-bit random in A -- X coord
        jsr rand8  ; jsr -- Jump to SubRoutine, abs. addr only
        sta TMPX   ; A->TMPX
        tax        ; "Transfer Accumulator to X": A->X

        ; Random Y coord 
        jsr rand8

        ; Check if within circle quarter, using the precomputed table
        cmp TABLE,x 
        bcc inside ; "Branch if Carry is Clear"
        beq inside ; "Branch if EQual"
        jmp next_iter

inside:
        ; Increment 16-bit inside counter INHI:INLO.
        inc INLO
        bne next_iter ; ; If low byte overflowed from $FF to $00, increment high byte.
        inc INHI

next_iter:
        ; Decrement 16-bit iteration counter ITERHI:ITERLO.
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
        ; STATUS = 2 means "finished".
        lda #$02
        sta STATUS
        rts

; Returns one pseudo-random byte in A
; 16-bit right-shifting Galois LFSR
; Seed is stored as:
;     SEEDHI:SEEDLO
;
; The routine updates the 16-bit seed and returns SEEDHI in A.
; The all-zero LFSR state would remain zero forever,
; so the code replaces zero seed with $5AA5
rand8:
        jsr rand16
        jsr rand16
        rts ; "ReTurn from Subroutine"

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

; Expected by the BASIC C64 worker body size: 148 bytes.
.assert * = C64_LOAD + 148, error, "c64_worker size mismatch: expected 148 bytes"
