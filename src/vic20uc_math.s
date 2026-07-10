; ============================================================
; vic20uc_math.s
; Compact arithmetic helper for the experimental cc65 VIC-20 C host.
;
; C prototype:
;     unsigned int mul_div_round(unsigned int value,
;                                unsigned int factor,
;                                unsigned int den);
;
; cc65 default calling convention for a three-argument function:
;   - den, the rightmost argument, arrives in A/X.
;   - factor is at (c_sp)+0/1.
;   - value  is at (c_sp)+2/3.
; The callee removes the two stacked 16-bit arguments before returning.
;
; Computes: round(value * factor / den)
;          = (value * factor + den / 2) / den
;
; This keeps arbitrary TOTAL_WORK support without pulling the large C-generated
; 32-bit multiply/divide helper code into the unexpanded VIC-20 build.
; ============================================================

.importzp c_sp
.export _mul_div_round

.segment "BSS"

factor_lo: .res 1
factor_hi: .res 1
den_lo:    .res 1
den_hi:    .res 1
num0:      .res 1
num1:      .res 1
num2:      .res 1
num3:      .res 1
mul0:      .res 1
mul1:      .res 1
mul2:      .res 1
mul3:      .res 1
rem_lo:    .res 1
rem_hi:    .res 1
q_lo:      .res 1
q_hi:      .res 1
ret_lo:    .res 1
ret_hi:    .res 1

.segment "CODE"

.proc _mul_div_round
        ; Save den from A/X and load the other two arguments from cc65's
        ; software stack.
        sta den_lo
        stx den_hi

        ldy #0
        lda (c_sp),y
        sta factor_lo
        iny
        lda (c_sp),y
        sta factor_hi
        iny
        lda (c_sp),y
        sta mul0
        iny
        lda (c_sp),y
        sta mul1

        lda #0
        sta num0
        sta num1
        sta num2
        sta num3
        sta mul2
        sta mul3

        ; num = value * factor, 16x16 -> 32, shift-and-add.
        ldx #16
@mul_loop:
        lda factor_lo
        and #1
        beq @no_add

        clc
        lda num0
        adc mul0
        sta num0
        lda num1
        adc mul1
        sta num1
        lda num2
        adc mul2
        sta num2
        lda num3
        adc mul3
        sta num3

@no_add:
        lsr factor_hi
        ror factor_lo

        asl mul0
        rol mul1
        rol mul2
        rol mul3

        dex
        bne @mul_loop

        ; Add den/2 for nearest-integer rounding.
        lda den_hi
        lsr a
        tax                     ; X = high byte of den/2
        lda den_lo
        ror a                   ; A = low byte of den/2

        clc
        adc num0
        sta num0
        txa
        adc num1
        sta num1
        lda num2
        adc #0
        sta num2
        lda num3
        adc #0
        sta num3

        ; q = num / den, 32-bit numerator by 16-bit denominator.
        ; The returned quotient is 16-bit; all current benchmark formulae keep
        ; it in range, matching the old C helper's u16 return type.
        lda #0
        sta rem_lo
        sta rem_hi
        sta q_lo
        sta q_hi

        ldx #32
@div_loop:
        ; Shift next numerator bit into the 16-bit remainder.
        asl num0
        rol num1
        rol num2
        rol num3
        rol rem_lo
        rol rem_hi
        bcs @shift_q_and_sub    ; remainder overflow => definitely >= den

        ; Shift quotient left for this output bit.
        asl q_lo
        rol q_hi

        ; If rem < den, quotient bit remains zero.
        lda rem_hi
        cmp den_hi
        bcc @div_next
        bne @do_sub
        lda rem_lo
        cmp den_lo
        bcc @div_next

@do_sub:
        sec
        lda rem_lo
        sbc den_lo
        sta rem_lo
        lda rem_hi
        sbc den_hi
        sta rem_hi
        lda q_lo
        ora #1
        sta q_lo

@div_next:
        dex
        bne @div_loop
        beq @return_q

@shift_q_and_sub:
        asl q_lo
        rol q_hi
        jmp @do_sub

@return_q:
        lda q_lo
        ldx q_hi

        ; Remove the two stacked 16-bit arguments. The rightmost den argument
        ; was passed in A/X and was not pushed by this assembly routine.
        sta ret_lo
        stx ret_hi
        clc
        lda c_sp
        adc #4
        sta c_sp
        bcc @sp_done
        inc c_sp+1
@sp_done:
        lda ret_lo
        ldx ret_hi
        rts
.endproc
