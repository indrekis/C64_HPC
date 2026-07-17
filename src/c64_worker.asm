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
        ; Returns 8-bit random in A -- X coord
        jsr rand8  ; jsr -- Jump to SubRoutine, abs. addr only
        tax        ; "Transfer Accumulator to X": A->X

        ; Random Y coord 
        jsr rand8

        ; Check if within circle quarter, using the precomputed table
        cmp TABLE,x
        bcc inside ; "Branch if Carry is Clear"
        bne next_iter ; Equal also falls through to inside

inside:
        ; Increment 16-bit inside counter INHI:INLO.
        inc INLO
        bne next_iter ; ; If low byte overflowed from $FF to $00, increment high byte.
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
; A zero seed is replaced with $5AA5 once before the main loop.
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

; Expected by the BASIC C64 worker body size: 112 bytes.
.assert * = C64_LOAD + 112, error, "c64_worker size mismatch: expected 112 bytes"
