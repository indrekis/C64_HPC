# tools/make_vic20_basic.py
from __future__ import annotations

import argparse
from math import sqrt
from pathlib import Path
import config

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
BUILD = ROOT / "build"
VBUILD = BUILD / "vic20"

DEFAULT_VIC20 = {
    "basic_load": 0x0401,
    "worker_load": 0x1600,
    "params": 0x16A0,
    "table": 0x1700,
    "worker_end": 0x1800,
    "drive_image": 0x1800,
    "spare": 0x1D00,
}
DEFAULT_VIC_WEIGHT = 100
DEFAULT_JIFFIES = 50


def get_vic20() -> dict:
    c = dict(DEFAULT_VIC20)
    # Accept either a compact VIC20 dict or explicit names if added later.
    v = getattr(config, "VIC20", {})
    if v:
        c["worker_load"] = v.get("load", c["worker_load"])
        c["params"] = v.get("params", c["params"])
        c["table"] = v.get("table", c["table"])
        c["worker_end"] = v.get("end", c["worker_end"])
    c.update(getattr(config, "VIC20_HOST", {}))
    return c


def hex4(n: int) -> str:
    return f"${n:04X}"


def read_prg(path: Path) -> tuple[int, bytes]:
    data = path.read_bytes()
    if len(data) < 2:
        raise ValueError(f"{path}: too short")
    return data[0] | (data[1] << 8), data[2:]


def q_table() -> bytes:
    q = []
    for x in range(256):
        v = int(sqrt(65536 - x * x))
        q.append(min(v, 255))
    return bytes(q)


def patch_worker_table(worker_body: bytes, worker_load: int, table_addr: int) -> bytes:
    body = bytearray(worker_body)
    off = table_addr - worker_load
    if off < 0 or off + 256 > len(body):
        raise ValueError("VIC-20 worker image does not contain the configured Q table area")
    body[off:off + 256] = q_table()
    return bytes(body)


def low(n: int) -> int:
    return n & 0xFF


def high(n: int) -> int:
    return (n >> 8) & 0xFF




def checked_seed(value, label: str) -> tuple[int, int]:
    if len(value) != 2:
        raise ValueError(f"{label} must be a pair: (low, high)")
    lo, hi = int(value[0]), int(value[1])
    if not 0 <= lo <= 0xFF or not 0 <= hi <= 0xFF:
        raise ValueError(f"{label} seed bytes must be in range 0..255")
    return lo, hi


def config_seed(name: str, default: tuple[int, int]) -> tuple[int, int]:
    return checked_seed(getattr(config, name, default), name)


def drive_seed(device: int, default: tuple[int, int]) -> tuple[int, int]:
    seeds = getattr(config, "DRIVE_SEEDS", {})
    if isinstance(seeds, dict):
        value = seeds.get(device, default)
    else:
        value = default
    return checked_seed(value, f"DRIVE_SEEDS[{device}]")


def generate_bas(mode: str) -> None:
    v = get_vic20()
    d = config.DRIVE
    drive_image = (VBUILD / "drive_image.bin").read_bytes()

    if mode == "driveonly":
        has_worker = 0
        mode_count = 3
        memtop = v["drive_image"]
        out = VBUILD / "driveonly.bas"
    elif mode == "local":
        has_worker = 1
        mode_count = 5
        memtop = v["worker_load"]
        out = VBUILD / "vic20.bas"
    else:
        raise ValueError(mode)

    vic_seed = config_seed("VIC_SEED", (123, 45))
    d8_seed = drive_seed(8, (37, 21))
    d9_seed = drive_seed(9, (91, 173))
    d10_seed = drive_seed(10, (211, 57))

    replacements = {
        "{VIC20_BASIC_UPLOAD_CHUNK}": str(vic20_basic_upload_chunk()),
        "{TITLE}": "V20+1541 3 BAS PI UI-",
        "{TOTAL_WORK}": str(config.TOTAL_WORK),
        "{VIC_WEIGHT}": str(getattr(config, "VIC_WEIGHT", DEFAULT_VIC_WEIGHT)),
        "{DRIVE_WEIGHT}": str(config.DRIVE_WEIGHT),
        "{VIC_WORKER_ADDR}": str(v["worker_load"]),
        "{DRIVE_IMAGE_ADDR}": str(v["drive_image"]),
        "{DRIVE_IMAGE_LEN}": str(len(drive_image)),
        "{MEMTOP_LOW}": str(low(memtop)),
        "{MEMTOP_HIGH}": str(high(memtop)),
        "{HAS_VIC_WORKER}": str(has_worker),
        "{MODE_COUNT}": str(mode_count),
        "{JIFFIES_PER_SECOND}": str(getattr(config, "JIFFIES_PER_SECOND", DEFAULT_JIFFIES)),
        "{DRIVE_LOAD_DEC}": str(d["load"]),
        "{DRIVE_PARAMS_DEC}": str(d["params"]),
        "{DRIVE_STATUS_DEC}": str(d["params"] + 3),
        "{DRIVE_INLO_DEC}": str(d["params"] + 4),
        "{VIC_ITERLO_DEC}": str(v["params"] + 0),
        "{VIC_ITERHI_DEC}": str(v["params"] + 1),
        "{VIC_SEEDLO_DEC}": str(v["params"] + 2),
        "{VIC_STATUS_DEC}": str(v["params"] + 3),
        "{VIC_INLO_DEC}": str(v["params"] + 4),
        "{VIC_INHI_DEC}": str(v["params"] + 5),
        "{VIC_SEEDHI_DEC}": str(v["params"] + 6),
        "{VIC_SEED_LO_DEC}": str(vic_seed[0]),
        "{VIC_SEED_HI_DEC}": str(vic_seed[1]),
        "{DRIVE8_SEED_LO_DEC}": str(d8_seed[0]),
        "{DRIVE8_SEED_HI_DEC}": str(d8_seed[1]),
        "{DRIVE9_SEED_LO_DEC}": str(d9_seed[0]),
        "{DRIVE9_SEED_HI_DEC}": str(d9_seed[1]),
        "{DRIVE10_SEED_LO_DEC}": str(d10_seed[0]),
        "{DRIVE10_SEED_HI_DEC}": str(d10_seed[1]),
    }

    tpl = (SRC / "vic20_benchmark.bas.in").read_text(encoding="utf-8")
    text = tpl
    for key, value in replacements.items():
        text = text.replace(key, value)
    unresolved = sorted({part for part in text.split() if "{" in part or "}" in part})
    if unresolved:
        raise ValueError(f"unresolved template placeholders: {unresolved[:20]}")

    # petcat BASIC V2 mode is happiest with lowercase keywords.
    text = text.lower().encode("ascii", "strict").decode("ascii")
    VBUILD.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="ascii", newline="\n")
    print(f"wrote {out}")


def retarget_basic_prg(prg: bytes, new_load: int) -> bytes:
    if len(prg) < 4:
        raise ValueError("tokenized BASIC PRG is too short")
    old_load = prg[0] | (prg[1] << 8)
    body = bytearray(prg[2:])
    out = bytearray([new_load & 0xFF, new_load >> 8]) + body

    off = 0
    while True:
        if off + 2 > len(body):
            raise ValueError("unterminated BASIC program")
        old_next = body[off] | (body[off + 1] << 8)
        if old_next == 0:
            break
        current_old = old_load + off
        line_len = old_next - current_old
        if line_len <= 0 or off + line_len > len(body):
            raise ValueError("invalid BASIC line link structure")
        new_next = new_load + off + line_len
        out[2 + off] = new_next & 0xFF
        out[2 + off + 1] = (new_next >> 8) & 0xFF
        off += line_len
    return bytes(out)


def append_blob(prg: bytearray, addr: int, blob: bytes, label: str) -> None:
    load = prg[0] | (prg[1] << 8)
    current_end = load + len(prg) - 2
    if current_end > addr:
        raise ValueError(f"BASIC image overlaps {label}: current end ${current_end:04X}, target ${addr:04X}")
    prg.extend(bytes(addr - current_end))
    prg.extend(blob)


def poke_decimal3(prg: bytearray, needle: bytes, value: int, label: str) -> None:
    """Patch a fixed-width decimal literal in tokenized BASIC.

    petcat tokenizes the POKE keyword but leaves numeric literals as PETSCII/ASCII
    digits.  The BASIC source deliberately uses POKE45,000 and POKE46,000 so
    these three bytes can be replaced without changing line lengths or link
    pointers.
    """
    if not 0 <= value <= 255:
        raise ValueError(f"{label}: byte value out of range: {value}")
    repl = f"{value:03d}".encode("ascii")
    idx = prg.find(needle)
    if idx < 0:
        raise ValueError(f"could not find {label} placeholder in tokenized BASIC")
    value_pos = idx + len(needle) - 3
    prg[value_pos:value_pos + 3] = repl


def set_basic_vartab_placeholder(prg: bytearray) -> None:
    """Make embedded-binary PRGs safe for BASIC CLR.

    Loading a PRG with worker/image bytes appended after the BASIC program makes
    the KERNAL set BASIC's variable-start pointer to the physical load end.
    After we lower MEMTOP to protect $1600/$1800 buffers, CLR would otherwise see
    VARTAB above MEMTOP and the first variable assignment fails with OUT OF
    MEMORY.  Patch line 10 so it restores VARTAB to the real end of the tokenized
    BASIC body before CLR executes.
    """
    load = prg[0] | (prg[1] << 8)
    basic_end = load + len(prg) - 2
    poke_decimal3(prg, b"45,000", basic_end & 0xFF, "POKE45/BASIC_END_LOW")
    poke_decimal3(prg, b"46,000", basic_end >> 8, "POKE46/BASIC_END_HIGH")


def package_prg(mode: str) -> None:
    v = get_vic20()
    basic_load = v["basic_load"]

    if mode == "driveonly":
        body_prg = VBUILD / "driveonly_body.prg"
        out_prg = VBUILD / "driveonly.prg"
        include_worker = False
    elif mode == "local":
        body_prg = VBUILD / "benchmark_body.prg"
        out_prg = VBUILD / "benchmark.prg"
        include_worker = True
    else:
        raise ValueError(mode)

    prg = bytearray(retarget_basic_prg(body_prg.read_bytes(), basic_load))
    set_basic_vartab_placeholder(prg)

    if include_worker:
        wload, wbody = read_prg(BUILD / "vic20_worker.prg")
        if wload != v["worker_load"]:
            raise ValueError(f"vic20_worker.prg load ${wload:04X}, expected ${v['worker_load']:04X}")
        wbody = patch_worker_table(wbody, v["worker_load"], v["table"])
        append_blob(prg, v["worker_load"], wbody, "VIC-20 local worker")

    drive_image = (VBUILD / "drive_image.bin").read_bytes()
    append_blob(prg, v["drive_image"], drive_image, "1541 drive image")
    out_prg.write_bytes(bytes(prg))
    print(f"wrote {out_prg}")


def vic20_basic_upload_chunk() -> int:
    value = int(getattr(config, "VIC20_BASIC_UPLOAD_CHUNK", 32))
    if not 1 <= value <= 32:
        raise ValueError(
            "VIC20_BASIC_UPLOAD_CHUNK must be in range 1..32; "
            "it is independent of DRIVE_CHUNK"
        )
    return value

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=("driveonly", "local"), required=True)
    ap.add_argument("--package", action="store_true")
    args = ap.parse_args()
    if args.package:
        package_prg(args.mode)
    else:
        generate_bas(args.mode)


if __name__ == "__main__":
    main()
