/*
 * src/vic20uc.c
 *
 * Unexpanded VIC-20 + 1541 Monte Carlo benchmark host, written in C for cc65.
 *
 * This is a C counterpart of src/vic20u_asm.asm.  The 1541 worker still stays
 * in hand-written 6502 assembly.  The VIC-20 host opens drive command channels,
 * uploads the compact 1541 image with M-W, starts workers with U3, polls status
 * with M-R, runs an optional local VIC-20 worker, and prints the same compact
 * five-mode report.
 *
 * No stdio, printf, malloc, or heap-heavy helpers are used.  Output and
 * IEC command-channel traffic goes through very small assembly wrappers for
 * the KERNAL jump table.  This avoids pulling in the larger cc65 CBM helper
 * wrappers for this memory-constrained target.
 */

#include "generated_vic20uc.h"

typedef unsigned char u8;
typedef unsigned int  u16;

extern void __fastcall__ k_open_ui_minus(u8 dev);
#define open_cmd_channel(dev) k_open_ui_minus((u8)(dev))
extern void __fastcall__ k_close(u8 lfn);
extern void __fastcall__ k_ckout(u8 lfn);
extern void __fastcall__ k_chkin(u8 lfn);
extern void k_clrch(void);
extern u8 k_basin(void);
extern void __fastcall__ k_bsout(u8 c);
extern void k_read_vic20ucdrv(void);

extern u16 mul_div_round(u16 value, u16 factor, u16 den);

#define CBM_CMD_M ((u8)0x4Du)
#define CBM_CMD_R ((u8)0x52u)
#define CBM_CMD_U ((u8)0x55u)
#define CBM_CMD_W ((u8)0x57u)

#define JIFFY_HI_ADDR 0x00A1u
#define JIFFY_LO_ADDR 0x00A2u
#define JIFFY_HI (*(volatile u8*)JIFFY_HI_ADDR)
#define JIFFY_LO (*(volatile u8*)JIFFY_LO_ADDR)


static u8 mode_idx;
static u8 workers;
static u8 curdev;
static u8 s8;
static u8 s9;
static u8 sa;

static u16 nv;
static u16 n8;
static u16 n9;
static u16 na;
static u16 inside;
static u16 start_jiffy;
static u16 elapsed;
static u16 t10;
static u16 t1;
static u16 pi10000;
static u16 eff100;
static u16 rnd_seed;

/* Shared scratch values for compact decimal formatting.
 *
 * cc65 generates smaller code when the compact formatting primitives work on
 * globals instead of passing several 16-bit values and local arrays through the
 * software stack.  These variables are used only while printing one line.
 */
static u16 print_val;
static u16 print_div;

/* ------------------------------------------------------------------------- */
/* Screen and compact decimal output. */


static void __fastcall__ print_str(const char* s)
{
    while (*s) {
        k_bsout((u8)*s++);
    }
}

static void print_cr(void)
{
    k_bsout(13);
}

static void print_sp(void)
{
    k_bsout(' ');
}

static void __fastcall__ print_2digits(u8 v)
{
    u8 tens;

    tens = 0;
    while (v >= 10) {
        v -= 10;
        ++tens;
    }
    k_bsout((u8)('0' + tens));
    k_bsout((u8)('0' + v));
}

static void print_dec_0_999(void)
{
    u8 printed;
    u8 digit;

    printed = 0;
    digit = 0;
    while (print_val >= 100) {
        print_val -= 100;
        ++digit;
    }
    if (digit) {
        k_bsout((u8)('0' + digit));
        printed = 1;
    }

    digit = 0;
    while (print_val >= 10) {
        print_val -= 10;
        ++digit;
    }
    if (digit || printed) {
        k_bsout((u8)('0' + digit));
    }

    k_bsout((u8)('0' + (u8)print_val));
}

static void __fastcall__ print_k(u8 k)
{
    u8 tens;

    if (k == 0) {
        k_bsout('-');
        k_bsout('-');
        print_sp();
        return;
    }

    tens = 0;
    while (k >= 10) {
        k -= 10;
        ++tens;
    }
    if (tens) {
        k_bsout((u8)('0' + tens));
    }
    k_bsout((u8)('0' + k));
    print_sp();
}

static void print_digit_by_div(void)
{
    u8 digit;

    digit = 0;
    while (print_val >= print_div) {
        print_val -= print_div;
        ++digit;
    }
    k_bsout((u8)('0' + digit));
}

static void print_pi(void)
{
    print_val = pi10000;

    print_div = 10000u;
    print_digit_by_div();
    k_bsout('.');
    print_div = 1000u;
    print_digit_by_div();
    print_div = 100u;
    print_digit_by_div();
    print_div = 10u;
    print_digit_by_div();
    print_div = 1u;
    print_digit_by_div();
}

static void print_time(void)
{
    u16 whole;
    u8 tenths;

    print_val = t10;
    whole = 0;
    while (print_val >= 10) {
        print_val -= 10;
        ++whole;
    }
    tenths = (u8)print_val;

    print_val = whole;
    print_dec_0_999();
    if (tenths) {
        k_bsout('.');
        k_bsout((u8)('0' + tenths));
    }
}

static void print_eff(void)
{
    u16 whole;
    u8 frac;

    print_val = eff100;
    if (print_val < 100) {
        k_bsout('.');
        print_2digits((u8)print_val);
        return;
    }
    if (print_val == 100) {
        k_bsout('1');
        return;
    }

    whole = 0;
    while (print_val >= 100) {
        print_val -= 100;
        ++whole;
    }
    frac = (u8)print_val;
    print_val = whole;
    print_dec_0_999();
    if (frac) {
        k_bsout('.');
        print_2digits(frac);
    }
}

static void print_result(void)
{
    print_sp();
    print_pi();
    print_sp();
    print_time();
    print_sp();
    print_eff();
    print_cr();
}

/* ------------------------------------------------------------------------- */
/* 32-bit arithmetic helper.
 *
 * The generic expression round(value * factor / den) is implemented in
 * src/vic20uc_math.s.  Keeping it in assembly preserves arbitrary TOTAL_WORK
 * values while avoiding the very large cc65 output generated for the same
 * 32-bit multiply/divide code in C.
 */

/* ------------------------------------------------------------------------- */
/* KERNAL IEC helpers.  Logical file number == device number. */


static void __fastcall__ close_one(u8 dev)
{
    curdev = dev;
    k_ckout(curdev);
    k_bsout(CBM_CMD_U);
    k_bsout('4');
    k_bsout(13);
    k_clrch();
    k_close(curdev);
    k_clrch();
}

static void send_u3(void)
{
    k_ckout(curdev);
    k_bsout(CBM_CMD_U);
    k_bsout('3');
    k_bsout(13);
    k_clrch();
}

static void send_mw_header(u16 addr, u8 count)
{
    k_ckout(curdev);
    k_bsout(CBM_CMD_M);
    k_bsout('-');
    k_bsout(CBM_CMD_W);
    k_bsout((u8)addr);
    k_bsout((u8)(addr >> 8));
    k_bsout(count);
}

static u8 __fastcall__ read_byte_addr(u16 addr)
{
    u8 v;

    k_ckout(curdev);
    k_bsout(CBM_CMD_M);
    k_bsout('-');
    k_bsout(CBM_CMD_R);
    k_bsout((u8)addr);
    k_bsout((u8)(addr >> 8));
    k_bsout(13);
    k_clrch();

    k_chkin(curdev);
    v = k_basin();
    k_clrch();
    return v;
}

/* Upload one non-contiguous 1541 RAM segment via M-W chunks. */
static void upload_segment(u16 addr, const u8* src, u16 rem)
{
    u8 count;
    u8 i;

    while (rem) {
        count = (rem > 32u) ? 32u : (u8)rem;
        send_mw_header(addr, count);
        for (i = 0; i != count; ++i) {
            k_bsout(src[i]);
        }
        k_bsout(13);
        k_clrch();

        src += count;
        addr += count;
        rem -= count;
    }
}

/* Upload the generated non-contiguous 1541 image.
 *
 * For the +3K full-overlay build, VIC20UCDRV is loaded at $1900 as a
 * sparse/contiguous view of the 1541 address space.  DRIVE_SEGx_PTR values
 * are therefore $1900 + (DRIVE_SEGx_ADDR - DRIVE_LOAD), except for q_table.
 */
static void upload_drive_image(void)
{
    upload_segment(DRIVE_SEG0_ADDR, DRIVE_SEG0_PTR, DRIVE_SEG0_LEN);
    upload_segment(DRIVE_SEG1_ADDR, DRIVE_SEG1_PTR, DRIVE_SEG1_LEN);
    upload_segment(DRIVE_SEG2_ADDR, DRIVE_SEG2_PTR, DRIVE_SEG2_LEN);
    upload_segment(DRIVE_SEG3_ADDR, DRIVE_SEG3_PTR, DRIVE_SEG3_LEN);
    upload_segment(DRIVE_SEG4_ADDR, DRIVE_SEG4_PTR, DRIVE_SEG4_LEN);
}

static void open_upload_all(void)
{
    for (curdev = 8; curdev != 11; ++curdev) {
        open_cmd_channel(curdev);
        upload_drive_image();
    }
}



static void close_all(void)
{
    close_one(8);
    close_one(9);
    close_one(10);
}

/* ------------------------------------------------------------------------- */
/* Mode setup, 1541 parameter block handling, and polling. */

static void load_mode(void)
{
    nv = mode_nv[mode_idx];
    n8 = mode_n8[mode_idx];
    n9 = mode_n9[mode_idx];
    na = mode_na[mode_idx];
    workers = mode_workers[mode_idx];
}

static void print_mode_line(void)
{
    k_bsout('m');
    k_bsout((u8)('1' + mode_idx));
    print_sp();
    print_k(mode_kv[mode_idx]);
    print_k(mode_k8[mode_idx]);
    print_k(mode_k9[mode_idx]);
    print_k(mode_ka[mode_idx]);
    print_str("...");
    print_cr();
}

static void write_drive_params(u16 n, u8 seed_lo, u8 seed_hi)
{
    send_mw_header(DRIVE_PARAMS, 7);
    k_bsout((u8)n);
    k_bsout((u8)(n >> 8));
    k_bsout(seed_lo);
    k_bsout(0);
    k_bsout(0);
    k_bsout(0);
    k_bsout(seed_hi);
    k_bsout(13);
    k_clrch();
}


static u8 read_drive_status(void)
{
    return read_byte_addr(DRIVE_STATUS);
}

static void read_one_result(void)
{
    u8 lo;
    u8 hi;

    lo = read_byte_addr(DRIVE_RESULT);
    hi = read_byte_addr(DRIVE_RESULT + 1u);
    inside += (u16)lo | ((u16)hi << 8);
}

static void poll_drives(void)
{
    for (;;) {
        if (s8 != 2) {
            curdev = 8;
            s8 = read_drive_status();
        }
        if (s9 != 2) {
            curdev = 9;
            s9 = read_drive_status();
        }
        if (sa != 2) {
            curdev = 10;
            sa = read_drive_status();
        }
        if (s8 == 2 && s9 == 2 && sa == 2) {
            return;
        }
    }
}

static void read_drive_results(void)
{
    if (n8) {
        curdev = 8;
        read_one_result();
    }
    if (n9) {
        curdev = 9;
        read_one_result();
    }
    if (na) {
        curdev = 10;
        read_one_result();
    }
}

/* ------------------------------------------------------------------------- */
/* Local VIC-20 Monte Carlo worker.  Same PRNG semantics as assembly workers. */

static u8 rand16(void)
{
    u8 lo;
    u8 hi;
    u8 carry;

    if (rnd_seed == 0) {
        rnd_seed = 0x5AA5u;
    }

    lo = (u8)rnd_seed;
    hi = (u8)(rnd_seed >> 8);
    carry = (u8)(lo & 1u);

    lo = (u8)((lo >> 1) | (hi << 7));
    hi = (u8)(hi >> 1);
    if (carry) {
        hi ^= 0xB4u;
    }

    rnd_seed = (u16)lo | ((u16)hi << 8);
    return hi;
}

static u8 rand8(void)
{
    rand16();
    return rand16();
}

static void run_local_worker(void)
{
    u16 left;
    u8 x;
    u8 y;

    left = nv;
    rnd_seed = (u16)VIC_SEED_LO | ((u16)VIC_SEED_HI << 8);

    while (left) {
        x = rand8();
        y = rand8();
        if (y <= q_table[x]) {
            ++inside;
        }
        --left;
    }
}

/* ------------------------------------------------------------------------- */
/* Time, pi, and efficiency calculations. */

static u16 read_jiffy16(void)
{
    return ((u16)JIFFY_HI << 8) | JIFFY_LO;
}

static void compute_numbers(void)
{
    t10 = mul_div_round(elapsed, 10u, JIFFIES_PER_SECOND);
    if (mode_idx == 0) {
        t1 = t10;
    }
    pi10000 = mul_div_round(inside, 40000u, TOTAL_WORK);
    if (t10 == 0 || workers == 0) {
        eff100 = 0;
    } else {
        /* Avoid cc65's mul8 runtime helper for t10 * workers.
         * workers is not used after compute_numbers(); the next mode reloads
         * it in load_mode(), so it can safely serve as a small loop counter.
         */
        eff100 = 0;
        do {
            eff100 = (u16)(eff100 + t10);
        } while (--workers);
        eff100 = mul_div_round(t1, 100u, eff100);
    }
}

/* ------------------------------------------------------------------------- */
/* One benchmark mode. */

static void run_mode(void)
{
    inside = 0;
    s8 = 2;
    s9 = 2;
    sa = 2;

    start_jiffy = read_jiffy16();

    if (n8) {
        curdev = 8;
        write_drive_params(n8, D8_SEED_LO, D8_SEED_HI);
        send_u3();
        s8 = 0;
    }
    if (n9) {
        curdev = 9;
        write_drive_params(n9, D9_SEED_LO, D9_SEED_HI);
        send_u3();
        s9 = 0;
    }
    if (na) {
        curdev = 10;
        write_drive_params(na, D10_SEED_LO, D10_SEED_HI);
        send_u3();
        sa = 0;
    }

    if (nv) {
        run_local_worker();
    }

    poll_drives();
    read_drive_results();
    elapsed = (u16)(read_jiffy16() - start_jiffy);
    compute_numbers();
    print_result();
}


int main(void)
{
    /* Load the external 1541 payload into screen RAM at $1E20.
     * It is copied to each 1541 before the benchmark starts, then the screen
     * is cleared for normal output.
     */
    k_bsout(147);
    k_read_vic20ucdrv();
    open_upload_all();

    k_bsout(147);
    print_str("k: v 8 9 10");
    print_cr();
    print_str(" p t eff");
    print_cr();
    print_cr();

    for (mode_idx = 0; mode_idx != 5; ++mode_idx) {
        load_mode();
        print_mode_line();
        run_mode();
    }

    close_all();
    print_str("done");
    print_cr();
    return 0;
}


