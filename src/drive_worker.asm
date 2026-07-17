; ============================================================
; drive_worker.asm
; ca65/ld65 version
; 1541-side Monte Carlo worker using U3 + job queue
; Comments from the c64_worker.asm are not repeated
;
; General idea:
;   Note: exact constants are set in generated_drive.inc, 
;   created by the make_includes.py, based on config.py. 
;
; C64 uploads the code binary blob to 1541, starting from $0300, including:
;   - Common routines at $0300, 
;   - Jumps for the U3 ($0500) and U4 ($0503) commands and their corresponding 
;     handler subroutines (start_worker and stop_worker), 
;   - two (almost identical) jobs – A and B to $0600 and $0700 buffers  
;     (be careful – $0700 is reserved for the BAM -- Block Availability Map, 
;     critical disk structure).
;   - Uploading is non-optimal because many parts of the blob ($0400 and part 
;     of the $0500 block can be skipped)
;
; C64 uploads the precomputed TABLE to $0400.
;
; C64 uploads computation data to $05D0 – different for each drive.
; 
; C64 sends the U3 command using the PRINT#D,"U3" command for each drive.
; 
; U3 calls start_worker, which puts job A into the у job queue and returns. 
; Then C64 can continue. 
; 
; At the end of the job A, it puts job B into the queue (and vice versa).
; 
; As a result, the driver, scanning the job table, calls job A and job B in turn, 
; performing the calculations. 
;
; After the C64 finishes its work, it can query the STATUS using the M-R command 
; and send U4 to stop. 
;
; More details are in readme. 
; ============================================================

.include "generated_drive.inc"

.assert DRIVE_CHUNK > 0, error, "DRIVE_CHUNK must be positive"
.assert DRIVE_CHUNK <= $FF, error, "DRIVE_CHUNK must fit in Y"

.export drive_common_start
.export drive_table_start
.export drive_ucmd_start
.export drive_params_start
.export drive_job_a_start
.export drive_job_b_start

.segment "LOADADDR"
        .word DRIVE_LOAD

; ============================================================
; $0300 COMMON

.segment "COMMON"

drive_common_start:

step_chunk:
        ; If the stop flag is set, do not continue computation.
        ; This is a cooperative soft stop -- current job looks at STOPFLAG in step_chunk.
        lda STOPFLAG
        bne stopped

        ; STATUS must be 1 = running.
        ; If STATUS is already 2 or 3, return immediately.
        lda STATUS
        cmp #$01
        bne step_return

        ; If ITERLO:ITERHI == 0, there is no work left.
        lda ITERLO
        ora ITERHI
        beq done
        
        ; Y = DRIVE_CHUNK.
        ; Y is the local counter for the number of Monte Carlo
        ; iterations performed by one job quantum.
        ldy #DRIVE_CHUNK

chunk_loop:
        ; Check before each iteration whether the total work is finished.
        lda ITERLO
        ora ITERHI
        beq done
        
        ; Generate X
        jsr rand8
        tax

        ; Generate Y
        jsr rand8

       ; Check if within circle quarter, using the precomputed table
        cmp TABLE,x
        bcc inside
        bne next_iter

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
        
        ; Increment the LED blink counter once per Monte Carlo iteration.
        ; When the 8-bit BLINKCNT overflows, toggle the LED.
        ; This gives one LED toggle approximately every 256 iterations.
        inc BLINKCNT
        bne no_blink

        jsr blink

no_blink:
        ; One job quantum performs at most DRIVE_CHUNK iterations.
        ; When Y reaches zero, return to the caller job.
        ; This is required for not blocking the driver for too long.
        dey             ; --Y
        bne chunk_loop

step_return:
        ; Return to job A or job B.
        rts

done:
        ; STATUS = 2 means finished.
        lda #$02
        sta STATUS
        rts

stopped:
        ; STATUS = 3 means stopped.
        lda #$03
        sta STATUS
        rts

; rand8/16 -- same as for C64 worker
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

; Replace the all-zero LFSR state with $5AA5.
; Called once from start_worker, outside the hot PRNG path.
normalize_seed:
        lda SEEDLO
        ora SEEDHI
        bne @done
        lda #$A5
        sta SEEDLO
        lda #$5A
        sta SEEDHI
@done:
        rts


; ============================================================
; ============================================================
; ============================================================

; Toggle the LED bit in VIA port B.
;
; Current configuration:
;   VIA_PRB  = $1C00
;   VIA_DDRB = $1C02
;   LED_BIT  = $08
;
; This is direct access to a drive hardware register, 
; the same one that controls the driver motor, 
; which requires extreme accuracy in operating, 
; or can damage the driver.
;

blink:
        lda VIA_PRB
        eor #LED_BIT ;  "Exclusive OR" 
        sta VIA_PRB
        rts

; Reserved for the $0400 TABLE
; BASIC overwrites this with Q(0)..Q(255) using M-W.

.segment "TABLE"

drive_table_start:
        .res 256, $00 ; Placeholder for the 256-byte threshold table.

; $0500 U3/U4 entry stubs

.segment "USTUB"

drive_ucmd_start:

u3_entry:
        ; Commodore DOS command U3 enters here.
        ; Jump to the actual start routine.
        jmp start_worker

u4_entry:
        ; Commodore DOS command U4 enters here.
        ; Jump to the stop routine.
        jmp stop_worker

; ============================================================

; $0520 START
; Called through U3.

.segment "START"

start_worker:
        ; Configure the LED bit as output in VIA DDRB, 
        ; required for blink to control the LED.
        lda VIA_DDRB
        ora #LED_BIT ; XOR
        sta VIA_DDRB

        ; Clear result counter, stop flag, and blink counter.
        lda #$00
        sta INLO
        sta INHI
        sta STOPFLAG
        sta BLINKCNT

        ; Clear job queue entries for job A and job B.
        ; JOB_A_CODE and JOB_B_CODE are drive DOS job code bytes,
        ; usually $0003 and $0004.
        ; Zero means no pending job.
        sta JOB_A_CODE
        sta JOB_B_CODE

        ; The all-zero LFSR state would remain zero forever.
        ; Check it once before queueing the first job, rather than in rand16.
        jsr normalize_seed

        ; STATUS = 1 means running.
        lda #$01
        sta STATUS

        ; If ITERLO:ITERHI == 0, there is no work to do.
        lda ITERLO
        ora ITERHI
        beq start_no_work

        ; Queue job A.
        ;
        ; JOB_JUMP = $D0.
        ; In the 1541 job mechanism this means a JUMP job for
        ; the corresponding buffer slot.
        ;
        ; Since job A code is placed at $0600, writing $D0 to
        ; JOB_A_CODE schedules execution of job_a.

        lda #JOB_JUMP
        sta JOB_A_CODE
        
        ; start_worker returns quickly to DOS, 
        ; computation continues later in background jobs.
        rts

start_no_work:
        ; If there is no work, mark the worker as finished immediately.
        lda #$02
        sta STATUS
        rts

; ============================================================

; $0560 STOP
; Called through U4.

.segment "STOP"

stop_worker:
        ; Request worker termination.
        ; If a job is already executing a chunk, it may finish
        ; that chunk before observing STOPFLAG again.
        lda #$01
        sta STOPFLAG

        ; Remove pending jobs from the queue.
        lda #$00
        sta JOB_A_CODE
        sta JOB_B_CODE

        ; Force the LED off.
        ; In this wiring, OR LED_BIT corresponds to LED off
        ; because the LED line is active-low.
        lda VIA_PRB
        ora #LED_BIT
        sta VIA_PRB

        rts

; ============================================================

; $05D0 PARAMS

.segment "PARAMS"

        ; Parameter and result block.
        ; BASIC writes ITER, seed, and other values here using M-W.
        ;
        ; Layout example, see generated_drive.inc:
        ;   $05D0 ITERLO
        ;   $05D1 ITERHI
        ;   $05D2 SEEDLO
        ;   $05D3 STATUS
        ;   $05D4 INLO
        ;   $05D5 INHI
        ;   $05D6 SEEDHI
        ;   $05D7 reserved (formerly TMPX)
        ;   $05D8 reserved (formerly JOBCNT)
        ;   $05D9 STOPFLAG
        ;   $05DA reserved (formerly TMPF)
        ;   $05DB BLINKCNT
        ;
        
drive_params_start:
        .res $30, $00

; ============================================================

; $0600 job A

.segment "JOBA"

drive_job_a_start:

job_a:
        ; Perform one Monte Carlo chunk.
        jsr step_chunk

        ; If the worker is no longer running, do not queue another job.
        lda STATUS
        cmp #$01
        bne job_a_return

        ; If a stop was requested, do not queue another job.
        lda STOPFLAG
        bne job_a_return

        ; Queue job B.
        ; This passes execution from A to B.
        lda #JOB_JUMP
        sta JOB_B_CODE

job_a_return:
        ; Return to the Commodore DOS job machinery.
        rts

; $0700 job B

.segment "JOBB"

drive_job_b_start:

job_b:
        jsr step_chunk

        ; If the worker is no longer running, do not queue another job.
        lda STATUS
        cmp #$01
        bne job_b_return
        
        ; If a stop was requested, do not queue another job.
        lda STOPFLAG
        bne job_b_return

        ; Queue job A.
        ; This passes execution from B back to A.
        lda #JOB_JUMP
        sta JOB_A_CODE

job_b_return:
        ; Return to the Commodore DOS job machinery.
        rts
    