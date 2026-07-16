; ============================================================
; vic20uc_startup.s
; Minimal cc65 startup for both VIC-20 C host variants.
;
; Build-time selection:
;   undefined VIC20UC_3K : unexpanded VIC-20, load $1001, SYS 4112
;   defined   VIC20UC_3K : VIC-20 +3K,        load $0401, SYS 1040
;
; BSS is placed in the cassette buffer by the linker config.
; The C software stack grows downward from __STACKTOP__ = $1E00.
; ============================================================

.include "zeropage.inc"

.import _main
.import __BSS_RUN__, __BSS_SIZE__
.import __STACKTOP__
.export __STARTUP__

.ifdef VIC20UC_3K
LOAD_ADDR = $0401
NEXT_PTR  = $040B
.else
LOAD_ADDR = $1001
NEXT_PTR  = $100B
.endif

.segment "LOADADDR"
        .word LOAD_ADDR

.segment "STARTUP"

__STARTUP__:

.ifdef VIC20UC_3K
; 10 SYS 1040
        .word NEXT_PTR
        .word 10
        .byte $9E,"1040",0
        .word 0
.else
; 10 SYS 4112
        .word NEXT_PTR
        .word 10
        .byte $9E,"4112",0
        .word 0
.endif

; The BASIC stub has identical length in both variants.  Pad to +$000F,
; so real startup begins at $0410 or $1010.
        .res 3

startup:
        lda #<__STACKTOP__
        sta c_sp
        lda #>__STACKTOP__
        sta c_sp+1

        lda #<__BSS_RUN__
        sta ptr1
        lda #>__BSS_RUN__
        sta ptr1+1
        lda #$00

; Compact one-page BSS clear.
;
; WARNING: This intentionally handles only __BSS_SIZE__ < 256.  The current
; linker configs place BSS in the VIC-20 cassette buffer, so it must remain a
; small single-page block.  If BSS is moved to normal RAM or grows beyond one
; page, restore the generic page-loop clear code instead of silently wrapping.
;
; The assertion is here to make that constraint fail at build/link time rather
; than become a hard-to-debug startup memory corruption.
        .assert __BSS_SIZE__ < $0100, error, "vic20uc_startup compact BSS clear requires __BSS_SIZE__ < 256"

        ldy #<__BSS_SIZE__
        beq bss_done
bss_byte_loop:
        dey
        sta (ptr1),y
        bne bss_byte_loop
bss_done:
        jsr _main

startup_done:
        rts
