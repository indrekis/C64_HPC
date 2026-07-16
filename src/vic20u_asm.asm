; ============================================================
; vic20u_asm.asm
; ca65/ld65 version
; Unexpanded VIC-20 + 1541 Monte Carlo benchmark
;
; One-file PRG for an unexpanded VIC-20:
;   - tiny BASIC V2 loader stub: 10 SYS 4112
;   - 6502 host/scheduler code
;   - KERNAL IEC serial-bus routines
;   - local VIC-20 Monte Carlo worker
;   - embedded compact 1541 drive image
;
; BASIC is only used to start the machine-code program through the SYS stub.
;
; All generated constants, mode tables, seeds, and memory-layout values
; are produced by tools/make_vic20u_asm_inc.py from info in tools/config.py.
;
; I have commented commands I can forget or whatever.
; ============================================================

.include "src/generated_vic20u_asm.inc"

; ============================================================
; KERNAL entry points used by the host. All screen output and
; IEC communication with the 1541 drives goes through KERNAL routines.
; Logical file number is kept equal to device number: 8, 9, or 10.
; ============================================================

SETLFS = $FFBA ; Set up a logical file
SETNAM = $FFBD ; Set up file name: A -- filename length; X/Y -- string ptr. 
               ; Required before LOAD, SAVE, or OPEN
OPEN   = $FFC0 ; Open a logical file
CLOSE  = $FFC3 ; Close a logical file
CHKIN  = $FFC6 ; Open channel for input
CHKOUT = $FFC9 ; Open a channel for output
CLRCHN = $FFCC ; Clear all I/O channels
CHRIN  = $FFCF ; Get a character from the input channel
CHROUT = $FFD2 ; Output a character

; Low 16 bits of the 24-bit KERNAL jiffy clock.
; Used only for elapsed benchmark time, not for random generation.
JIFFY_HI = $A1
JIFFY_LO = $A2

; Temporary zero-page pointer used for strings and memory uploads.
; $FB/$FC is free scratch zero-page space on the VIC-20.
ZP_PTR   = $FB
ZP_PTR_H = $FC

VIC20_SCREEN = $1E00

; Build-time sanity checks.  The 1541 protocol uses 16-bit iteration
; counters, and the embedded drive image must contain the Q table used
; by the local VIC-20 worker.
.assert TOTAL_WORK > 0, error, "TOTAL_WORK must be positive"
.assert TOTAL_WORK <= $FFFF, error, "TOTAL_WORK must fit in the 16-bit drive protocol"
.assert JIFFIES_PER_SECOND > 0, error, "JIFFIES_PER_SECOND must be positive"
.assert JIFFIES_PER_SECOND <= $FFFF, error, "JIFFIES_PER_SECOND must fit in the 16-bit time divider"
.assert Q_OFFSET + 256 <= DRIVE_IMAGE_LEN, error, "Q table is outside the compact drive image"

.segment "LOADADDR"
        ; PRG load address.  On an unexpanded VIC-20, BASIC starts at $1001.
        .word $1001

.segment "STARTUP"

        ; Minimal tokenized BASIC line:
        ;   10 SYS 4112
        ;
        ; 4112 decimal is $1010, where the real assembly program starts.
        ; The stub lets the PRG be loaded and started like a normal BASIC
        ; program, while keeping the runtime code fully in machine language.
        .word $100B
        .word 10
        .byte $9E,"4112",0
        .word 0

        ; The BASIC stub above occupies $1001..$100C.
        ; Pad explicitly to $1010, reserving 3 bytes.
        .res 3

.segment "CODE"

; ============================================================
; Main benchmark driver.
;
; Flow:
;   1. print the compact header,
;   2. open drives 8/9/10 and upload the 1541 image to each,
;   3. run all five generated benchmark modes,
;   4. stop and close all drives.
; ============================================================

asm_main:
        jsr cls
        lda #<title  ; Lower byte of the title label address 
        ldy #>title  ; Upper byte of the title label address 
        jsr print_str
        lda #<hdr1
        ldy #>hdr1
        jsr print_str
        lda #<hdr2
        ldy #>hdr2
        jsr print_str
        jsr print_cr

        ; Upload the 1541 worker image to all drives.
        jsr open_upload_all

        ; mode_idx = 0..4 corresponds to printed modes M1..M5.
        ; The generated mode tables define work split for each mode.
        lda #0        ; Note: lda sets flags 
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
		
		jmp print_str
        ; jsr print_str ; To print "ASM" in the title, I need this byte 
        ; rts           ; spared by the tail-call optimization...

; ============================================================
; Screen text output
;
; PETSCII is used. Sent through CHROUT.  Strings are zero-terminated.
; Address in A/Y pair: low/high byte of the string address.
; ============================================================

cls:
        ; PETSCII 147 clears the screen.
        lda #147
        jmp CHROUT

print_cr:
        lda #13
        jmp CHROUT

print_sp:
        lda #' '
        jmp CHROUT

print_str:
        ; Store input address in the zero-page pointer and print until NUL.
        sta ZP_PTR
        sty ZP_PTR_H
        ldy #0
@loop:  lda (ZP_PTR),y ; (...) -- dereferencing, *(ZP_PTR+y), uses 2 bytes at ZP_PTR
        beq @done
        jsr CHROUT
        iny            ; ++Y
        bne @loop
@done:  rts            ; Return from the subroutine call

; ============================================================
; KERNAL IEC helpers
;
; Logical file number == device number, same as in BASIC variant:
; e.g, drive 8 is opened as logical file 8, device 8, secondary address 15.
;
; The command channel is opened with option "UI-".  For a 1541 used
; with a VIC-20, this selects the faster 1540-compatible IEC timing.
; Option is set by using the filename "UI-" while opening the command channel.
; BASIC analog: OPEN 8,8,15,"UI-":CLOSE 15
; ============================================================

open_upload_all:
        ; Open command channels and upload the 1541 worker to drives 8, 9, 10.
        lda #8
        jsr open_upload_one
        lda #9
        jsr open_upload_one
        lda #10
        jsr open_upload_one
        rts

; Argument in A 
open_upload_one:
        ; curdev is both the IEC device number and the logical file number.
        sta curdev
        jsr open_cmd_channel
        jmp upload_drive_image

open_cmd_channel:
        ; SETNAM length=3, name="UI-".
        lda #3
        ldx #<ui_name
        ldy #>ui_name
        jsr SETNAM
        ; SETLFS file=curdev, device=curdev, secondary=15 command channel.
        lda curdev
        tax			; X = A. Sets Z & N flags 
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
        ; Stop possible background jobs first, then close the command channel.
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
        ; Finish command string and restore default I/O channels.
        lda #13
        jsr CHROUT
        jmp CLRCHN

send_u3:
        ; Start the already uploaded 1541 worker via custom DOS command U3.
        jsr checkout_cur
        lda #'U'
        jsr CHROUT
        lda #'3'
        jsr CHROUT
        jmp send_cr_clr

send_u4:
        ; Ask the 1541 worker to stop via custom DOS command U4.
        jsr checkout_cur
        lda #'U'
        jsr CHROUT
        lda #'4'
        jsr CHROUT
        jmp send_cr_clr

send_mw_header:
        ; Send "M-W" + low address + high address + byte count.
        ; Data bytes must be written by the caller immediately afterwards.
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
        jmp CHROUT        ; Recursive tail optimization

read_byte_addr:
        ; Read one byte from 1541 RAM using:
        ;   "M-R" + low address + high address
        ; Result is returned in A.
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
        pha            ; Push A to stack. 
        jsr CLRCHN
        pla            ; Pop A from stack, sets Z & N flags 
        rts

; ============================================================
; Upload 1541 image
;
; The embedded image contains the 1541 worker code and the Q table.
; It is copied from VIC-20 RAM to 1541 RAM at DRIVE_LOAD using M-W chunks.
; The chunk size is fixed at 32 bytes, safely below the practical command
; channel string limit.
; ============================================================

upload_drive_image:
        ; Source pointer in VIC-20 RAM: drive_image.
        lda #<drive_image
        sta ZP_PTR
        lda #>drive_image
        sta ZP_PTR_H
        ; Destination pointer in 1541 RAM: DRIVE_LOAD.
        lda #<DRIVE_LOAD
        sta addr_lo
        lda #>DRIVE_LOAD
        sta addr_hi
        ; Remaining byte count.
        lda #<DRIVE_IMAGE_LEN
        sta rem_lo
        lda #>DRIVE_IMAGE_LEN
        sta rem_hi
@next:  ; Stop when the remaining byte count reaches zero.
        lda rem_lo
        ora rem_hi        ; A OR [rem_hi]
        beq @done

        ; Use 32-byte chunks, except for the final shorter chunk.
        lda #32
        sta count
        lda rem_hi
        bne @have_count
        lda rem_lo
        cmp #32
        bcs @have_count    ; bcs - Branch if Carry Set
        sta count
@have_count:               ; @ -- Local label 
        jsr send_mw_header

        ; Send exactly count bytes from (ZP_PTR),Y to the drive.
        ldy #0
@data:  cpy count           ; Compare Y and [count], sets flags as for Y - [count]
        beq @sent
        lda (ZP_PTR),y
        jsr CHROUT
        iny                 ; ++Y
        bne @data
@sent:  jsr send_cr_clr

        ; Advance both the VIC-20 source pointer and the 1541 destination
        ; address by the number of bytes just sent.
        clc
        lda ZP_PTR
        adc count
        sta ZP_PTR
        bcc @src_ok         ; bcc -- Branch if Carry Clear
        inc ZP_PTR_H
@src_ok:
        clc
        lda addr_lo
        adc count
        sta addr_lo
        bcc @addr_ok
        inc addr_hi
@addr_ok:
        sec                ; sec -- Set Carry Flag.
        lda rem_lo
        sbc count          ; Sub. with carry: A=A−count−(1−C)
        sta rem_lo
        bcs @next
        dec rem_hi
        jmp @next
@done:  rts

; ============================================================
; Mode setup and printing
;
; The mode tables are generated at build time.  Each mode contains:
;   nv -- number of local VIC-20 iterations,
;   n8/n9/na -- iteration counts for drives 8/9/10,
;   workers -- number of active workers, 
;   k-values -- compact printed work units.
; ============================================================

load_mode:
        ; mode_idx is 0-based, but the printed mode number is M1..M5.
        ; 16-bit mode arrays are indexed by mode_idx*2.
        lda mode_idx
        asl a				; Shift left by 1: A = 2*A
        tay                 ; Y = A 
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
        ; Print one compact work line, for example:
        ;   M3 20 20 20 -- ...
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
        ; Print one compact workload field.
        ; Zero work is shown as "--"; otherwise print a one- or two-digit K value.
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

; ============================================================
; Benchmark mode execution
;
; A mode is executed in this order:
;   1. clear total inside counter,
;   2. start active 1541 workers,
;   3. run the local VIC-20 worker, if this mode has one,
;   4. poll active drives until they report STATUS=2,
;   5. read drive results and print pi/time/efficiency.
; ============================================================

run_mode:
        ; inside_hi:inside_lo accumulates all local and drive hits.
        lda #0
        sta inside_lo
        sta inside_hi
        ; Drive status cache.  2 means "finished" or "not active".
        lda #2
        sta s8
        sta s9
        sta sa

        jsr read_jiffy_start

        ; Start drive 8 if this mode assigned work to it.
        lda n8_lo
        ora n8_hi
        beq @skip8          ; Checks if 16-bit value is zero 
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
        ; Start drive 9 if active.
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
        ; Start drive 10 if active.
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
        ; The local worker is blocking, so it runs after starting the drives.
        ; While it works, the 1541 jobs continue asynchronously.
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
        ; Write the 7-byte 1541 parameter block:
        ;   ITERLO, ITERHI, SEEDLO, STATUS=0, INLO=0, INHI=0, SEEDHI
        ; using one M-W command.
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
        ; Poll only drives that were started.  Inactive drives keep status=2,
        ; so they are treated as already finished.
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
        ; Return one drive worker STATUS byte in A.
        lda #<DRIVE_STATUS
        sta addr_lo
        lda #>DRIVE_STATUS
        sta addr_hi
        jmp read_byte_addr

read_drive_results:
        ; Read results only from drives that had non-zero work in this mode.
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
        ; Read 16-bit INLO/INHI result from the current drive and add it
        ; to the shared inside_hi:inside_lo counter.
        lda #<DRIVE_RESULT
        sta addr_lo
        lda #>DRIVE_RESULT
        sta addr_hi
        jsr read_byte_addr
        sta tmp_lo
        inc addr_lo
        bne @addr_ok
        inc addr_hi         ; ++ for the 16-bit address 
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

; ============================================================
; Local VIC-20 worker
;
; This is the same Monte Carlo inner loop idea as c64_worker.asm, but embedded
; directly in the unexpanded VIC-20 host program.  It uses the Q table stored
; inside the embedded 1541 image, so no second copy of the table is needed.
; ============================================================

run_local_worker:
        ; local_hi:local_lo is the remaining local iteration counter.
        lda nv_lo
        sta local_lo
        lda nv_hi
        sta local_hi
        lda #VIC_SEED_LO
        sta seed_lo
        lda #VIC_SEED_HI
        sta seed_hi
@loop:  ; Generate X and Y, then test Y <= Q[X].
        lda local_lo
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
        dec local_hi   ; -- for the 16-bit 
@dec_lo:
        dec local_lo
        jmp @loop
@done:  rts

; Returns one pseudo-random byte in A.
; Same PRNG as the existing C64/1541 workers:
;   - 16-bit right-shifting Galois LFSR,
;   - seed stored as seed_hi:seed_lo,
;   - rand8 calls rand16 twice and returns the high seed byte.
; The all-zero LFSR state would remain zero forever, so it is replaced
; with $5AA5.
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
        ror           ; ROR shifts A right through the C flag
        sta seed_lo
        lda tmp_hi
        beq @no_xor
        lda seed_hi
        eor #$B4      ; A = A XOR $B4
        sta seed_hi
@no_xor:
        lda seed_hi
        rts

; ============================================================
; Time and arithmetic
;
; Internally the benchmark avoids floating point.  It computes:
;   t10     = round(elapsed_jiffies * 10 / JIFFIES_PER_SECOND)
;   pi10000 = round(inside * 40000 / TOTAL_WORK)
;   eff100  = round(t1 * 100 / (current_time * workers))
;
; Printing routines later insert decimal points where needed.
; ============================================================

read_jiffy_start:
        ; Save the low 16 bits of the KERNAL jiffy clock.
        lda JIFFY_LO
        sta start_lo
        lda JIFFY_HI
        sta start_hi
        rts

read_jiffy_elapsed:
        ; elapsed = current jiffy value - saved start value.
        ; 16-bit wrap-around is acceptable for these short benchmark runs.
        sec
        lda JIFFY_LO
        sbc start_lo
        sta elapsed_lo
        lda JIFFY_HI
        sbc start_hi
        sta elapsed_hi
        rts

compute_numbers:
        ; Mode 1 is the reference time t1 for scaling efficiency.
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
        ; Convert elapsed jiffies to tenths of a second.
        lda elapsed_lo
        sta val_lo
        lda elapsed_hi
        sta val_hi
        lda #<10
        sta factor_lo
        lda #>10              ; Just 0 
        sta factor_hi
        jsr mul16x16_to_num32

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
        ; Compute pi scaled by 10000:
        ;   pi10000 = inside * 4 * 10000 / TOTAL_WORK.
        lda inside_lo
        sta val_lo
        lda inside_hi
        sta val_hi
        lda #<40000
        sta factor_lo
        lda #>40000
        sta factor_hi
        jsr mul16x16_to_num32

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

; 16x16 -> 32-bit unsigned multiply.
; Input:
;   val_hi:val_lo and factor_hi:factor_lo
; Output:
;   num3:num2:num1:num0
; Clobbers:
;   mul0..mul3, factor_lo/hi
mul16x16_to_num32:
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
@loop:  lda factor_lo
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
        lsr factor_hi
        ror factor_lo
        asl mul0
        rol mul1
        rol mul2
        rol mul3
        dex
        bne @loop
        rts

; 32/16-bit unsigned division.
; Input/output:
;   num3:num2:num1:num0 is divided by den_hi:den_lo.
; The quotient is left in num0..num3.  The benchmark uses only num0/num1,
; and generated constants are chosen so that the visible result fits there.
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
        ; Compute scaling efficiency in hundredths:
        ;   eff100 = round(t1 * 100 / (t * workers)).
        ; If current time is zero, print efficiency as zero instead of dividing.
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
		; Multiply by workers using addition 
@den:   clc
        lda den_lo
        adc t10_lo
        sta den_lo
        lda den_hi
        adc t10_hi
        sta den_hi
        dex
        bne @den

		; Inefficient multiply by 100. But it is used only 
		; several times at the end, after the time measurements,
        ; and is rather compact. And we cannot spare a single byte...
        lda #0
        sta factor_lo
        sta factor_hi
        ldy #100
@num:   clc
        lda factor_lo
        adc t1_lo
        sta factor_lo
        lda factor_hi
        adc t1_hi
        sta factor_hi
        dey             ; --Y
        bne @num

        ; rounding: numerator += denominator / 2
        lda den_hi
        lsr a
        sta tmp_hi
        lda den_lo
        ror a
        sta tmp_lo
        clc
        lda factor_lo
        adc tmp_lo
        sta factor_lo
        lda factor_hi
        adc tmp_hi
        sta factor_hi

        jsr div16_by_den
        lda factor_lo
        sta eff_lo
        lda factor_hi
        sta eff_hi
        rts

; 16/16-bit unsigned division.
; Used by compute_eff100 after building a 16-bit numerator and denominator.
; Quotient is left in factor_hi:factor_lo.
div16_by_den:
        lda #0
        sta rem_lo
        sta rem_hi
        ldx #16
@loop:  asl factor_lo
        rol factor_hi     ; Shift left through the C 
        rol rem_lo
        rol rem_hi
        sec              ; set C = 1
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
        inc factor_lo
@skip:  dex
        bne @loop
        rts

; ============================================================
; Result formatting
;
; Printed result line format:
;   " pi time eff"
;
; pi is printed as fixed 1.4 decimal digits, time as seconds with optional
; tenths, and efficiency as either ".xx", "1", or a larger fixed value.
; ============================================================

print_result:
        jsr print_sp
        jsr print_pi
        jsr print_sp
        jsr print_time
        jsr print_sp
        jsr print_eff
        jmp print_cr

print_pi:
        ; pi_lo/hi stores pi * 10000.
        ; Print it as D.DDDD using repeated subtraction.
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
        ; Print one decimal digit by repeatedly subtracting divisor_hi:divisor_lo
        ; from val_hi:val_lo.
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
        ; Carry is set if val >= divisor, clear otherwise.
        lda val_hi
        cmp divisor_hi
        bne @hi
        lda val_lo
        cmp divisor_lo
        rts
@hi:    rts

print_time:
        ; t10 is elapsed time in tenths of a second.
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
        ; eff100 is efficiency * 100.
        ; Values below 1 are printed as .xx; exactly 1 as "1".
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

; ============================================================
; Read-only data
;
; Strings are stored in PETSCII-compatible uppercase text.
; The embedded 1541 image follows the strings and generated mode tables.
; ============================================================

.segment "RODATA"

title:    .byte "VIC20+1541 ASM PI UI-",13,0
hdr1:     .byte "K: V 8 9 10",13,0
hdr2:     .byte " P T EFF",13,0
dots_msg: .byte "...",13,0
done_msg: .byte "DONE",13,0
ui_name:  .byte "UI-"

; Generated mode tables are included earlier from src/generated_vic20u_asm.inc.
; The embedded drive image contains both the 1541 code and the Q table.
; It is uploaded to each real/simulated 1541 at startup.
drive_image:
        .incbin "build/vic20u_asm_drive.bin"
drive_image_end:
        .assert drive_image_end - drive_image = DRIVE_IMAGE_LEN, error, "bad VIC20U ASM drive image length"

.segment "BSS"

; ============================================================
; Runtime variables
;
; Kept in BSS by the linker.  The whole program, including these variables,
; must still fit below the unexpanded VIC-20 screen at $1E00.
; ============================================================

; Current IEC device and benchmark mode state.
curdev:       .res 1
mode_idx:     .res 1
workers:      .res 1
count:        .res 1

; Work distribution for the current mode:
;   nv -- local VIC-20 work,
;   n8/n9/na -- drive 8/9/10 work.
nv_lo:        .res 1
nv_hi:        .res 1
n8_lo:        .res 1
n8_hi:        .res 1
n9_lo:        .res 1
n9_hi:        .res 1
na_lo:        .res 1
na_hi:        .res 1

; Cached drive statuses.  2 means finished or inactive.
s8:           .res 1
s9:           .res 1
sa:           .res 1

; Parameter block fields used before writing to a 1541.
param_lo:     .res 1
param_hi:     .res 1
seed_lo:      .res 1
seed_hi:      .res 1
local_lo:     .res 1
local_hi:     .res 1

; Total number of random points inside the quarter circle.
inside_lo:    .res 1
inside_hi:    .res 1

; Generic 16-bit address and remaining-size counters.
addr_lo:      .res 1
addr_hi:      .res 1
rem_lo:       .res 1
rem_hi:       .res 1

; Timing and computed benchmark results.
start_lo:     .res 1
start_hi:     .res 1
elapsed_lo:   .res 1
elapsed_hi:   .res 1
; Elapsed times in seconds*10 for the current mode 
t10_lo:       .res 1
t10_hi:       .res 1
; Elapsed times in seconds*10 for the M1 -- first mode 
t1_lo:        .res 1
t1_hi:        .res 1
pi_lo:        .res 1
pi_hi:        .res 1
eff_lo:       .res 1
eff_hi:       .res 1

; Formatting and arithmetic scratch variables.
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

factor_lo:    .res 1
factor_hi:    .res 1
den_lo:       .res 1
den_hi:       .res 1

rem_eff:      .res 2
