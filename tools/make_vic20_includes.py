# tools/make_vic20_includes.py
from pathlib import Path
import config

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"

DEFAULT_VIC20 = {
    "load": 0x1600,
    "params": 0x16A0,
    "table": 0x1700,
    "end": 0x1800,
}


def hex4(n: int) -> str:
    return f"${n:04X}"


def vic20_config() -> dict:
    c = dict(DEFAULT_VIC20)
    c.update(getattr(config, "VIC20", {}))
    return c


def write_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="ascii", newline="\n")


def make_vic20_inc() -> str:
    v = vic20_config()
    return f"""; generated_vic20.inc
; Auto-generated from tools/config.py by tools/make_vic20_includes.py.
; Do not edit by hand.

VIC20_LOAD   = {hex4(v["load"])}
VIC20_PARAMS = {hex4(v["params"])}
VIC20_TABLE  = {hex4(v["table"])}
VIC20_END    = {hex4(v["end"])}

ITERLO = VIC20_PARAMS + $00
ITERHI = VIC20_PARAMS + $01
SEEDLO = VIC20_PARAMS + $02
STATUS = VIC20_PARAMS + $03
INLO   = VIC20_PARAMS + $04
INHI   = VIC20_PARAMS + $05
SEEDHI = VIC20_PARAMS + $06
TMPX   = VIC20_PARAMS + $07
TMPF   = VIC20_PARAMS + $09
TABLE  = VIC20_TABLE
"""


def make_vic20_cfg() -> str:
    v = vic20_config()
    code_size = v["params"] - v["load"]
    params_size = v["table"] - v["params"]
    table_size = v["end"] - v["table"]
    return f"""MEMORY {{
    LOADADDR: start = $0000, size = $0002, file = %O;
    CODE:     start = {hex4(v["load"])}, size = ${code_size:04X}, file = %O, fill = yes;
    PARAMS:   start = {hex4(v["params"])}, size = ${params_size:04X}, file = %O, fill = yes;
    TABLE:    start = {hex4(v["table"])}, size = ${table_size:04X}, file = %O, fill = yes;
}}
SEGMENTS {{
    LOADADDR: load = LOADADDR, type = ro;
    CODE:     load = CODE, type = ro;
    PARAMS:   load = PARAMS, type = ro;
    TABLE:    load = TABLE, type = ro;
}}
"""


def main() -> None:
    write_text(SRC / "generated_vic20.inc", make_vic20_inc())
    write_text(SRC / "generated_vic20.cfg", make_vic20_cfg())


if __name__ == "__main__":
    main()
