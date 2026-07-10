; ============================================================
; vic20uc_startup.s
; Minimal cc65 startup for both VIC-20 C host variants.
;
; Build-time selection:
;   undefined VIC20UC_3K : unexpanded VIC-20, load $1001, SYS 4112
;   defined   VIC20UC_3K : VIC-20 +3K,     load $0401, SYS 1040
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

        ldx #>__BSS_SIZE__
        beq bss_remainder

bss_page_loop:
        ldy #$00
bss_page_byte:
        sta (ptr1),y
        iny
        bne bss_page_byte
        inc ptr1+1
        dex
        bne bss_page_loop

bss_remainder:
        ldy #<__BSS_SIZE__
        beq bss_done
bss_rem_byte:
        dey
        sta (ptr1),y
        bne bss_rem_byte

bss_done:
        jsr _main

startup_done:
        rts
