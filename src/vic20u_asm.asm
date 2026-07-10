; src/vic20u_asm.asm
;
; Unexpanded VIC-20 + 1541 Monte Carlo benchmark.
; One-file PRG: BASIC SYS stub + 6502 host/scheduler + local VIC worker
; + embedded compact 1541 drive image.
;
; Uses KERNAL I/O only.  No BASIC runtime is used after SYS.

.include "src/generated_vic20u_asm.inc"

SETLFS = $FFBA
SETNAM = $FFBD
OPEN   = $FFC0
CLOSE  = $FFC3
CHKIN  = $FFC6
CHKOUT = $FFC9
CLRCHN = $FFCC
CHRIN  = $FFCF
CHROUT = $FFD2

JIFFY_HI = $A1          ; low 16 bits of the 24-bit KERNAL jiffy clock
JIFFY_LO = $A2

ZP_PTR   = $FB
ZP_PTR_H = $FC

VIC20_SCREEN = $1E00
PI_SCALE     = 40000

.assert TOTAL_WORK > 0, error, "TOTAL_WORK must be positive"
.assert TOTAL_WORK <= $FFFF, error, "TOTAL_WORK must fit in the 16-bit drive protocol"
.assert JIFFIES_PER_SECOND > 0, error, "JIFFIES_PER_SECOND must be positive"
.assert JIFFIES_PER_SECOND <= $FFFF, error, "JIFFIES_PER_SECOND must fit in the 16-bit time divider"
.assert Q_OFFSET + 256 <= DRIVE_IMAGE_LEN, error, "Q table is outside the compact drive image"

.segment "LOADADDR"
.word $1001

.segment "STARTUP"
; 10 SYS 4112
.word $100B
.word 10
.byte $9E,"4112",0
.word 0
; The BASIC stub above is 12 bytes at $1001..$100c.
; Pad explicitly to $1010. ca65 does not accept `$1010-*`
; here as an absolute constant in .res.
.res 3

.segment "CODE"

asm_main:
        jsr cls
        lda #<title
        ldy #>title
        jsr print_str
        lda #<hdr1
        ldy #>hdr1
        jsr print_str
        lda #<hdr2
        ldy #>hdr2
        jsr print_str
        jsr print_cr

        jsr open_upload_all

        lda #0
        sta mode_idx
mode_loop:
        jsr load_mode
        jsr print_mode_line
        jsr run_mode
        inc mode_idx
        lda mode_idx
        cmp #5
        bne mode_loop

        jsr close_all
        lda #<done_msg
        ldy #>done_msg
        jsr print_str
        rts

; ---------------------------------------------------------------------------
; Screen / text output

cls:
        lda #147
        jmp CHROUT

print_cr:
        lda #13
        jmp CHROUT

print_sp:
        lda #' '
        jmp CHROUT

print_str:
        sta ZP_PTR
        sty ZP_PTR_H
        ldy #0
@loop:  lda (ZP_PTR),y
        beq @done
        jsr CHROUT
        iny
        bne @loop
@done:  rts

print_char_a:
        jmp CHROUT

; ---------------------------------------------------------------------------
; KERNAL IEC helpers.  Logical file number == device number.

open_upload_all:
        lda #8
        jsr open_upload_one
        lda #9
        jsr open_upload_one
        lda #10
        jsr open_upload_one
        rts

open_upload_one:
        sta curdev
        jsr open_cmd_channel
        jmp upload_drive_image

open_cmd_channel:
        lda #3
        ldx #<ui_name
        ldy #>ui_name
        jsr SETNAM
        lda curdev
        tax
        ldy #15
        jsr SETLFS
        jmp OPEN

close_all:
        lda #8
        jsr close_one
        lda #9
        jsr close_one
        lda #10
        jsr close_one
        rts

close_one:
        sta curdev
        jsr send_u4
        lda curdev
        jsr CLOSE
        jmp CLRCHN

checkout_cur:
        ldx curdev
        jmp CHKOUT

chkin_cur:
        ldx curdev
        jmp CHKIN

send_cr_clr:
        lda #13
        jsr CHROUT
        jmp CLRCHN

send_u3:
        jsr checkout_cur
        lda #'U'
        jsr CHROUT
        lda #'3'
        jsr CHROUT
        jmp send_cr_clr

send_u4:
        jsr checkout_cur
        lda #'U'
        jsr CHROUT
        lda #'4'
        jsr CHROUT
        jmp send_cr_clr

send_mw_header:
        jsr checkout_cur
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'W'
        jsr CHROUT
        lda addr_lo
        jsr CHROUT
        lda addr_hi
        jsr CHROUT
        lda count
        jmp CHROUT

read_byte_addr:
        jsr checkout_cur
        lda #'M'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        lda #'R'
        jsr CHROUT
        lda addr_lo
        jsr CHROUT
        lda addr_hi
        jsr CHROUT
        jsr send_cr_clr
        jsr chkin_cur
        jsr CHRIN
        pha
        jsr CLRCHN
        pla
        rts

; ---------------------------------------------------------------------------
; Upload compact 1541 image to drive RAM at DRIVE_LOAD via M-W chunks.

upload_drive_image:
        lda #<drive_image
        sta ZP_PTR
        lda #>drive_image
        sta ZP_PTR_H
        lda #<DRIVE_LOAD
        sta addr_lo
        lda #>DRIVE_LOAD
        sta addr_hi
        lda #<DRIVE_IMAGE_LEN
        sta rem_lo
        lda #>DRIVE_IMAGE_LEN
        sta rem_hi
@next:  lda rem_lo
        ora rem_hi
        beq @done
        lda #32
        sta count
        lda rem_hi
        bne @have_count
        lda rem_lo
        cmp #32
        bcs @have_count
        sta count
@have_count:
        jsr send_mw_header
        ldy #0
@data:  cpy count
        beq @sent
        lda (ZP_PTR),y
        jsr CHROUT
        iny
        bne @data
@sent:  jsr send_cr_clr

        clc
        lda ZP_PTR
        adc count
        sta ZP_PTR
        bcc @src_ok
        inc ZP_PTR_H
@src_ok:
        clc
        lda addr_lo
        adc count
        sta addr_lo
        bcc @addr_ok
        inc addr_hi
@addr_ok:
        sec
        lda rem_lo
        sbc count
        sta rem_lo
        bcs @next
        dec rem_hi
        jmp @next
@done:  rts

; ---------------------------------------------------------------------------
; Mode setup and printing

load_mode:
        lda mode_idx
        asl a
        tay
        lda mode_nv,y
        sta nv_lo
        lda mode_nv+1,y
        sta nv_hi
        lda mode_n8,y
        sta n8_lo
        lda mode_n8+1,y
        sta n8_hi
        lda mode_n9,y
        sta n9_lo
        lda mode_n9+1,y
        sta n9_hi
        lda mode_na,y
        sta na_lo
        lda mode_na+1,y
        sta na_hi
        ldx mode_idx
        lda mode_workers,x
        sta workers
        rts

print_mode_line:
        lda #'M'
        jsr CHROUT
        lda mode_idx
        clc
        adc #'1'
        jsr CHROUT
        jsr print_sp
        ldx mode_idx
        lda mode_kv,x
        jsr print_k
        ldx mode_idx
        lda mode_k8,x
        jsr print_k
        ldx mode_idx
        lda mode_k9,x
        jsr print_k
        ldx mode_idx
        lda mode_ka,x
        jsr print_k
        lda #<dots_msg
        ldy #>dots_msg
        jmp print_str

print_k:
        cmp #0
        bne @num
        lda #'-'
        jsr CHROUT
        lda #'-'
        jsr CHROUT
        jmp print_sp
@num:   sta tmp_lo
        lda #0
        sta digit
@tens:  lda tmp_lo
        cmp #10
        bcc @ones
        sec
        sbc #10
        sta tmp_lo
        inc digit
        jmp @tens
@ones:  lda digit
        beq @one_only
        clc
        adc #'0'
        jsr CHROUT
@one_only:
        lda tmp_lo
        clc
        adc #'0'
        jsr CHROUT
        jmp print_sp

; ---------------------------------------------------------------------------
; Benchmark mode execution

run_mode:
        lda #0
        sta inside_lo
        sta inside_hi
        lda #2
        sta s8
        sta s9
        sta sa

        jsr read_jiffy_start

        lda n8_lo
        ora n8_hi
        beq @skip8
        lda #8
        sta curdev
        lda n8_lo
        sta param_lo
        lda n8_hi
        sta param_hi
        lda #D8_SEED_LO
        sta seed_lo
        lda #D8_SEED_HI
        sta seed_hi
        jsr write_drive_params
        jsr send_u3
        lda #0
        sta s8
@skip8:
        lda n9_lo
        ora n9_hi
        beq @skip9
        lda #9
        sta curdev
        lda n9_lo
        sta param_lo
        lda n9_hi
        sta param_hi
        lda #D9_SEED_LO
        sta seed_lo
        lda #D9_SEED_HI
        sta seed_hi
        jsr write_drive_params
        jsr send_u3
        lda #0
        sta s9
@skip9:
        lda na_lo
        ora na_hi
        beq @skip10
        lda #10
        sta curdev
        lda na_lo
        sta param_lo
        lda na_hi
        sta param_hi
        lda #D10_SEED_LO
        sta seed_lo
        lda #D10_SEED_HI
        sta seed_hi
        jsr write_drive_params
        jsr send_u3
        lda #0
        sta sa
@skip10:
        lda nv_lo
        ora nv_hi
        beq @no_local
        jsr run_local_worker
@no_local:
        jsr poll_drives
        jsr read_drive_results
        jsr read_jiffy_elapsed
        jsr compute_numbers
        jsr print_result
        rts

write_drive_params:
        lda #<DRIVE_PARAMS
        sta addr_lo
        lda #>DRIVE_PARAMS
        sta addr_hi
        lda #7
        sta count
        jsr send_mw_header
        lda param_lo
        jsr CHROUT
        lda param_hi
        jsr CHROUT
        lda seed_lo
        jsr CHROUT
        lda #0
        jsr CHROUT
        lda #0
        jsr CHROUT
        lda #0
        jsr CHROUT
        lda seed_hi
        jsr CHROUT
        jmp send_cr_clr

poll_drives:
@loop:  lda s8
        cmp #2
        beq @p9
        lda #8
        sta curdev
        jsr read_drive_status
        sta s8
@p9:    lda s9
        cmp #2
        beq @p10
        lda #9
        sta curdev
        jsr read_drive_status
        sta s9
@p10:   lda sa
        cmp #2
        beq @test
        lda #10
        sta curdev
        jsr read_drive_status
        sta sa
@test:  lda s8
        cmp #2
        bne @loop
        lda s9
        cmp #2
        bne @loop
        lda sa
        cmp #2
        bne @loop
        rts

read_drive_status:
        lda #<DRIVE_STATUS
        sta addr_lo
        lda #>DRIVE_STATUS
        sta addr_hi
        jmp read_byte_addr

read_drive_results:
        lda n8_lo
        ora n8_hi
        beq @skip8
        lda #8
        sta curdev
        jsr read_one_result
@skip8: lda n9_lo
        ora n9_hi
        beq @skip9
        lda #9
        sta curdev
        jsr read_one_result
@skip9: lda na_lo
        ora na_hi
        beq @done
        lda #10
        sta curdev
        jsr read_one_result
@done:  rts

read_one_result:
        lda #<DRIVE_RESULT
        sta addr_lo
        lda #>DRIVE_RESULT
        sta addr_hi
        jsr read_byte_addr
        sta tmp_lo
        inc addr_lo
        bne @addr_ok
        inc addr_hi
@addr_ok:
        jsr read_byte_addr
        sta tmp_hi
        clc
        lda inside_lo
        adc tmp_lo
        sta inside_lo
        lda inside_hi
        adc tmp_hi
        sta inside_hi
        rts

; ---------------------------------------------------------------------------
; Local VIC worker.  Uses the Q table embedded in the 1541 image.

run_local_worker:
        lda nv_lo
        sta local_lo
        lda nv_hi
        sta local_hi
        lda #VIC_SEED_LO
        sta seed_lo
        lda #VIC_SEED_HI
        sta seed_hi
@loop:  lda local_lo
        ora local_hi
        beq @done
        jsr rand8
        tax
        jsr rand8
        cmp drive_image+Q_OFFSET,x
        bcc @inside
        beq @inside
        jmp @dec
@inside:
        inc inside_lo
        bne @dec
        inc inside_hi
@dec:   lda local_lo
        bne @dec_lo
        dec local_hi
@dec_lo:
        dec local_lo
        jmp @loop
@done:  rts

; Same PRNG as the existing C64/1541 workers: rand8 calls
; rand16 twice and returns the high seed byte in A.
rand8:
        jsr rand16
        jsr rand16
        rts

rand16:
        lda seed_lo
        bne @seed_ok
        lda seed_hi
        bne @seed_ok
        lda #$A5
        sta seed_lo
        lda #$5A
        sta seed_hi
@seed_ok:
        lda seed_lo
        and #$01
        sta tmp_hi
        lda seed_hi
        lsr
        sta seed_hi
        lda seed_lo
        ror
        sta seed_lo
        lda tmp_hi
        beq @no_xor
        lda seed_hi
        eor #$B4
        sta seed_hi
@no_xor:
        lda seed_hi
        rts

; ---------------------------------------------------------------------------
; Time and arithmetic

read_jiffy_start:
        lda JIFFY_LO
        sta start_lo
        lda JIFFY_HI
        sta start_hi
        rts

read_jiffy_elapsed:
        sec
        lda JIFFY_LO
        sbc start_lo
        sta elapsed_lo
        lda JIFFY_HI
        sbc start_hi
        sta elapsed_hi
        rts

compute_numbers:
        jsr compute_time10
        lda mode_idx
        bne @not_first
        lda t10_lo
        sta t1_lo
        lda t10_hi
        sta t1_hi
@not_first:
        jsr compute_pi10000
        jsr compute_eff100
        rts

compute_time10:
        lda elapsed_lo
        sta val_lo
        lda elapsed_hi
        sta val_hi
        lda #<10
        sta dividend_lo
        lda #>10
        sta dividend_hi
        jsr mul_val_by_dividend_to_num

        ; t10 = round(elapsed_jiffies * 10 / JIFFIES_PER_SECOND)
        clc
        lda num0
        adc #<(JIFFIES_PER_SECOND / 2)
        sta num0
        lda num1
        adc #>(JIFFIES_PER_SECOND / 2)
        sta num1
        lda num2
        adc #0
        sta num2
        lda num3
        adc #0
        sta num3

        lda #<JIFFIES_PER_SECOND
        sta den_lo
        lda #>JIFFIES_PER_SECOND
        sta den_hi
        jsr div32_by_den
        lda num0
        sta t10_lo
        lda num1
        sta t10_hi
        rts

compute_pi10000:
        lda inside_lo
        sta val_lo
        lda inside_hi
        sta val_hi
        lda #<40000
        sta dividend_lo
        lda #>40000
        sta dividend_hi
        jsr mul_val_by_dividend_to_num

        ; pi10000 = round(inside * 40000 / TOTAL_WORK)
        clc
        lda num0
        adc #<(TOTAL_WORK / 2)
        sta num0
        lda num1
        adc #>(TOTAL_WORK / 2)
        sta num1
        lda num2
        adc #0
        sta num2
        lda num3
        adc #0
        sta num3

        lda #<TOTAL_WORK
        sta den_lo
        lda #>TOTAL_WORK
        sta den_hi
        jsr div32_by_den
        lda num0
        sta pi_lo
        lda num1
        sta pi_hi
        rts

; num0..num3 = val_lo/hi * dividend_lo/hi.
mul_val_by_dividend_to_num:
        lda #0
        sta num0
        sta num1
        sta num2
        sta num3
        lda val_lo
        sta mul0
        lda val_hi
        sta mul1
        lda #0
        sta mul2
        sta mul3
        ldx #16
@loop:  lda dividend_lo
        and #1
        beq @skip_add
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
@skip_add:
        lsr dividend_hi
        ror dividend_lo
        asl mul0
        rol mul1
        rol mul2
        rol mul3
        dex
        bne @loop
        rts

; num0..num3 /= den_lo/hi, quotient left in num0..num3.
; The benchmark uses only num0/num1; values are chosen so the quotient fits.
div32_by_den:
        lda #0
        sta rem_lo
        sta rem_hi
        ldx #32
@loop:  asl num0
        rol num1
        rol num2
        rol num3
        rol rem_lo
        rol rem_hi
        bcs @sub
        lda rem_hi
        cmp den_hi
        bcc @skip
        bne @sub
        lda rem_lo
        cmp den_lo
        bcc @skip
@sub:   sec
        lda rem_lo
        sbc den_lo
        sta rem_lo
        lda rem_hi
        sbc den_hi
        sta rem_hi
        inc num0
@skip:  dex
        bne @loop
        rts

compute_eff100:
        lda t10_lo
        ora t10_hi
        bne @ok
        lda #0
        sta eff_lo
        sta eff_hi
        rts
@ok:    lda #0
        sta den_lo
        sta den_hi
        ldx workers
@den:   clc
        lda den_lo
        adc t10_lo
        sta den_lo
        lda den_hi
        adc t10_hi
        sta den_hi
        dex
        bne @den

        lda #0
        sta dividend_lo
        sta dividend_hi
        ldy #100
@num:   clc
        lda dividend_lo
        adc t1_lo
        sta dividend_lo
        lda dividend_hi
        adc t1_hi
        sta dividend_hi
        dey
        bne @num

        ; rounding: numerator += denominator / 2
        lda den_hi
        lsr a
        sta tmp_hi
        lda den_lo
        ror a
        sta tmp_lo
        clc
        lda dividend_lo
        adc tmp_lo
        sta dividend_lo
        lda dividend_hi
        adc tmp_hi
        sta dividend_hi

        jsr div16_by_den
        lda dividend_lo
        sta eff_lo
        lda dividend_hi
        sta eff_hi
        rts

; dividend_lo/hi /= den_lo/hi, quotient left in dividend_lo/hi.
div16_by_den:
        lda #0
        sta rem_lo
        sta rem_hi
        ldx #16
@loop:  asl dividend_lo
        rol dividend_hi
        rol rem_lo
        rol rem_hi
        sec
        lda rem_lo
        sbc den_lo
        sta tmp_lo
        lda rem_hi
        sbc den_hi
        sta tmp_hi
        bcc @skip
        lda tmp_lo
        sta rem_lo
        lda tmp_hi
        sta rem_hi
        inc dividend_lo
@skip:  dex
        bne @loop
        rts

; ---------------------------------------------------------------------------
; Result formatting: " pi time eff"

print_result:
        jsr print_sp
        jsr print_pi
        jsr print_sp
        jsr print_time
        jsr print_sp
        jsr print_eff
        jmp print_cr

print_pi:
        lda pi_lo
        sta val_lo
        lda pi_hi
        sta val_hi
        lda #<10000
        sta divisor_lo
        lda #>10000
        sta divisor_hi
        jsr print_digit_sub
        lda #'.'
        jsr CHROUT
        lda #<1000
        sta divisor_lo
        lda #>1000
        sta divisor_hi
        jsr print_digit_sub
        lda #<100
        sta divisor_lo
        lda #>100
        sta divisor_hi
        jsr print_digit_sub
        lda #<10
        sta divisor_lo
        lda #>10
        sta divisor_hi
        jsr print_digit_sub
        lda #<1
        sta divisor_lo
        lda #>1
        sta divisor_hi
        jmp print_digit_sub

print_digit_sub:
        lda #0
        sta digit
@loop:  jsr val_ge_divisor
        bcc @done
        sec
        lda val_lo
        sbc divisor_lo
        sta val_lo
        lda val_hi
        sbc divisor_hi
        sta val_hi
        inc digit
        jmp @loop
@done:  lda digit
        clc
        adc #'0'
        jmp CHROUT

val_ge_divisor:
        lda val_hi
        cmp divisor_hi
        bne @hi
        lda val_lo
        cmp divisor_lo
        rts
@hi:    rts

print_time:
        lda t10_lo
        sta val_lo
        lda t10_hi
        sta val_hi
        lda #0
        sta int_lo
        sta int_hi
@loop:  lda val_hi
        bne @sub
        lda val_lo
        cmp #10
        bcc @done
@sub:   sec
        lda val_lo
        sbc #10
        sta val_lo
        lda val_hi
        sbc #0
        sta val_hi
        inc int_lo
        bne @loop
        inc int_hi
        jmp @loop
@done:  lda val_lo            ; save tenths digit
        sta tmp_lo
        lda int_lo
        sta val_lo
        lda int_hi
        sta val_hi
        jsr print_dec_0_999
        lda tmp_lo
        beq @ret_time
        lda #'.'
        jsr CHROUT
        lda tmp_lo
        clc
        adc #'0'
        jmp CHROUT
@ret_time:
        rts

print_eff:
        lda eff_lo
        sta val_lo
        lda eff_hi
        sta val_hi
        lda val_hi
        bne @gt100
        lda val_lo
        cmp #100
        beq @one
        bcs @gt100
        lda #'.'
        jsr CHROUT
        lda val_lo
        jmp print_2digits_a
@one:   lda #'1'
        jmp CHROUT
@gt100: lda #0
        sta int_lo
        sta int_hi
@e_loop:
        lda val_hi
        bne @e_sub
        lda val_lo
        cmp #100
        bcc @e_done
@e_sub: sec
        lda val_lo
        sbc #100
        sta val_lo
        lda val_hi
        sbc #0
        sta val_hi
        inc int_lo
        bne @e_loop
        inc int_hi
        jmp @e_loop
@e_done:
        lda val_lo            ; save percent remainder before printing integer part
        sta rem_eff
        lda val_hi
        sta rem_eff+1
        lda int_lo
        sta val_lo
        lda int_hi
        sta val_hi
        jsr print_dec_0_999
        lda rem_eff
        ora rem_eff+1
        beq @ret
        lda #'.'
        jsr CHROUT
        lda rem_eff
        jsr print_2digits_a
@ret:   rts

; Print A as two decimal digits, leading zero.
print_2digits_a:
        sta tmp_lo
        lda #0
        sta digit
@tens:  lda tmp_lo
        cmp #10
        bcc @ones
        sec
        sbc #10
        sta tmp_lo
        inc digit
        jmp @tens
@ones:  lda digit
        clc
        adc #'0'
        jsr CHROUT
        lda tmp_lo
        clc
        adc #'0'
        jmp CHROUT

; Print val_lo/hi as unsigned 0..999.
print_dec_0_999:
        lda #0
        sta printed
        lda #<100
        sta divisor_lo
        lda #>100
        sta divisor_hi
        jsr digit_sub_optional
        lda #<10
        sta divisor_lo
        lda #>10
        sta divisor_hi
        jsr digit_sub_optional
        lda #<1
        sta divisor_lo
        lda #>1
        sta divisor_hi
        lda #1
        sta printed
        jmp print_digit_sub

digit_sub_optional:
        lda #0
        sta digit
@loop:  jsr val_ge_divisor
        bcc @done
        sec
        lda val_lo
        sbc divisor_lo
        sta val_lo
        lda val_hi
        sbc divisor_hi
        sta val_hi
        inc digit
        jmp @loop
@done:  lda digit
        ora printed
        beq @ret
        lda #1
        sta printed
        lda digit
        clc
        adc #'0'
        jsr CHROUT
@ret:   rts

; ---------------------------------------------------------------------------
; Data

.segment "RODATA"

title:    .byte "VIC20+1541 PI UI-",13,0
hdr1:     .byte "K: V 8 9 10",13,0
hdr2:     .byte " P T EFF",13,0
dots_msg: .byte "...",13,0
done_msg: .byte "DONE",13,0
ui_name:  .byte "UI-"

; Generated mode tables follow from src/generated_vic20u_asm.inc.
; The embedded drive image contains both the 1541 code and the Q table.
drive_image:
        .incbin "build/vic20u_asm_drive.bin"
drive_image_end:
        .assert drive_image_end - drive_image = DRIVE_IMAGE_LEN, error, "bad VIC20U ASM drive image length"

.segment "BSS"

curdev:       .res 1
mode_idx:     .res 1
workers:      .res 1
count:        .res 1

nv_lo:        .res 1
nv_hi:        .res 1
n8_lo:        .res 1
n8_hi:        .res 1
n9_lo:        .res 1
n9_hi:        .res 1
na_lo:        .res 1
na_hi:        .res 1

s8:           .res 1
s9:           .res 1
sa:           .res 1

param_lo:     .res 1
param_hi:     .res 1
seed_lo:      .res 1
seed_hi:      .res 1
local_lo:     .res 1
local_hi:     .res 1

inside_lo:    .res 1
inside_hi:    .res 1

addr_lo:      .res 1
addr_hi:      .res 1
rem_lo:       .res 1
rem_hi:       .res 1

start_lo:     .res 1
start_hi:     .res 1
elapsed_lo:   .res 1
elapsed_hi:   .res 1
t10_lo:       .res 1
t10_hi:       .res 1
t1_lo:        .res 1
t1_hi:        .res 1
pi_lo:        .res 1
pi_hi:        .res 1
eff_lo:       .res 1
eff_hi:       .res 1

val_lo:       .res 1
val_hi:       .res 1
int_lo:       .res 1
int_hi:       .res 1
divisor_lo:   .res 1
divisor_hi:   .res 1
digit:        .res 1
printed:      .res 1

tmp_lo:       .res 1
tmp_hi:       .res 1
num0:         .res 1
num1:         .res 1
num2:         .res 1
num3:         .res 1
mul0:         .res 1
mul1:         .res 1
mul2:         .res 1
mul3:         .res 1

dividend_lo:  .res 1
dividend_hi:  .res 1
den_lo:       .res 1
den_hi:       .res 1

rem_eff:      .res 2
