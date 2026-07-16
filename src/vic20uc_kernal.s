; ============================================================
; vic20uc_kernal.s
; Tiny KERNAL I/O wrappers for the experimental cc65 C host.
; Shared by unexpanded and +3K screen-overlay variants.
; ============================================================

SETLFS = $FFBA
SETNAM = $FFBD
OPEN   = $FFC0
CLOSE  = $FFC3
CHKIN  = $FFC6
CHKOUT = $FFC9
CLRCHN = $FFCC
CHRIN  = $FFCF
CHROUT = $FFD2
LOAD   = $FFD5

.export _k_open_ui_minus
.export _k_close
.export _k_ckout
.export _k_chkin
.export _k_clrch
.export _k_basin
.export _k_bsout
.export _k_read_vic20ucdrv

.segment "CODE"

_k_open_ui_minus:
        pha
        lda #3
        ldx #<ui_minus
        ldy #>ui_minus
        jsr SETNAM
        pla
        tax
        ldy #15
        jsr SETLFS
        jmp OPEN

_k_close:
        jmp CLOSE

_k_ckout:
        tax
        jmp CHKOUT

_k_chkin:
        tax
        jmp CHKIN

_k_clrch:
        jmp CLRCHN

_k_basin:
        jmp CHRIN

_k_bsout:
        jmp CHROUT

DRIVE_OVERLAY_LOAD = $1E20

; Load vic20ucdrv as a PRG into screen RAM.  The lowercase filename is required:
; c1541 writes the D64 entry as "vic20ucdrv".
_k_read_vic20ucdrv:
        lda #10
        ldx #<drv_name
        ldy #>drv_name
        jsr SETNAM

        lda #1
        ldx #8
        ldy #1
        jsr SETLFS

        lda #0
        ldx #<DRIVE_OVERLAY_LOAD
        ldy #>DRIVE_OVERLAY_LOAD
        jsr LOAD
        jmp CLRCHN

.segment "RODATA"

ui_minus:
        .byte "UI-"

drv_name:
        .byte "vic20ucdrv"
