# tools/make_includes.py

from pathlib import Path
import config


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


def hex4(n: int) -> str:
    return f"${n:04X}"


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="ascii", newline="\n")


def make_drive_inc() -> str:
    d = config.DRIVE

    return f"""; generated_drive.inc
; Auto-generated from tools/config.py. Do not edit by hand.

DRIVE_CHUNK = {config.DRIVE_CHUNK}

DRIVE_LOAD  = {hex4(d["load"])}

DRIVE_COMMON = {hex4(d["common"])}
DRIVE_TABLE  = {hex4(d["table"])}
DRIVE_UCMD   = {hex4(d["ucmd"])}
DRIVE_START  = {hex4(d["start"])}
DRIVE_STOP   = {hex4(d["stop"])}
DRIVE_PARAMS = {hex4(d["params"])}
DRIVE_JOB_A  = {hex4(d["job_a"])}
DRIVE_JOB_B  = {hex4(d["job_b"])}

JOB_A_CODE = {hex4(d["job_a_code"])}
JOB_B_CODE = {hex4(d["job_b_code"])}
JOB_JUMP   = ${d["job_jump"]:02X}

ITERLO    = DRIVE_PARAMS + $00
ITERHI    = DRIVE_PARAMS + $01
SEEDLO    = DRIVE_PARAMS + $02
STATUS    = DRIVE_PARAMS + $03
INLO      = DRIVE_PARAMS + $04
INHI      = DRIVE_PARAMS + $05
SEEDHI    = DRIVE_PARAMS + $06
TMPX      = DRIVE_PARAMS + $07
JOBCNT    = DRIVE_PARAMS + $08
STOPFLAG  = DRIVE_PARAMS + $09
TMPF      = DRIVE_PARAMS + $0A
BLINKCNT  = DRIVE_PARAMS + $0B

TABLE     = DRIVE_TABLE

VIA_PRB   = {hex4(d["via_prb"])}
VIA_DDRB  = {hex4(d["via_ddrb"])}
LED_BIT   = ${d["led_bit"]:02X}
"""


def make_c64_inc() -> str:
    c = config.C64

    return f"""; generated_c64.inc
; Auto-generated from tools/config.py. Do not edit by hand.

C64_LOAD   = {hex4(c["load"])}
C64_PARAMS = {hex4(c["params"])}
C64_TABLE  = {hex4(c["table"])}

ITERLO  = C64_PARAMS + $00
ITERHI  = C64_PARAMS + $01
SEEDLO  = C64_PARAMS + $02
STATUS  = C64_PARAMS + $03
INLO    = C64_PARAMS + $04
INHI    = C64_PARAMS + $05
SEEDHI  = C64_PARAMS + $06
TMPX    = C64_PARAMS + $07
TMPF    = C64_PARAMS + $09

TABLE   = C64_TABLE
"""


def make_drive_cfg() -> str:
    d = config.DRIVE

    common_size = d["table"] - d["common"]
    table_size = d["ucmd"] - d["table"]
    ustub_size = d["start"] - d["ucmd"]
    start_size = d["stop"] - d["start"]
    stop_size = d["params"] - d["stop"]
    params_size = d["job_a"] - d["params"]
    job_a_size = d["job_b"] - d["job_a"]
    job_b_size = d["end"] - d["job_b"]

    return f"""MEMORY {{
    LOADADDR: start = $0000, size = $0002, file = %O;
    COMMON:   start = {hex4(d["common"])}, size = ${common_size:04X}, file = %O, fill = yes;
    TABLE:    start = {hex4(d["table"])}, size = ${table_size:04X}, file = %O, fill = yes;
    USTUB:    start = {hex4(d["ucmd"])}, size = ${ustub_size:04X}, file = %O, fill = yes;
    START:    start = {hex4(d["start"])}, size = ${start_size:04X}, file = %O, fill = yes;
    STOP:     start = {hex4(d["stop"])}, size = ${stop_size:04X}, file = %O, fill = yes;
    PARAMS:   start = {hex4(d["params"])}, size = ${params_size:04X}, file = %O, fill = yes;
    JOBA:     start = {hex4(d["job_a"])}, size = ${job_a_size:04X}, file = %O, fill = yes;
    JOBB:     start = {hex4(d["job_b"])}, size = ${job_b_size:04X}, file = %O, fill = yes;
}}

SEGMENTS {{
    LOADADDR: load = LOADADDR, type = ro;
    COMMON:   load = COMMON,   type = ro;
    TABLE:    load = TABLE,    type = ro;
    USTUB:    load = USTUB,    type = ro;
    START:    load = START,    type = ro;
    STOP:     load = STOP,     type = ro;
    PARAMS:   load = PARAMS,   type = ro;
    JOBA:     load = JOBA,     type = ro;
    JOBB:     load = JOBB,     type = ro;
}}
"""


def make_c64_cfg() -> str:
    c = config.C64
    code_size = c["end"] - c["load"]

    return f"""MEMORY {{
    LOADADDR: start = $0000, size = $0002, file = %O;
    CODE:     start = {hex4(c["load"])}, size = ${code_size:04X}, file = %O;
}}

SEGMENTS {{
    LOADADDR: load = LOADADDR, type = ro;
    CODE:     load = CODE,     type = ro;
}}
"""


def main() -> None:
    write_text(SRC / "generated_drive.inc", make_drive_inc())
    write_text(SRC / "generated_c64.inc", make_c64_inc())
    write_text(SRC / "generated_drive.cfg", make_drive_cfg())
    write_text(SRC / "generated_c64.cfg", make_c64_cfg())


if __name__ == "__main__":
    main()
	