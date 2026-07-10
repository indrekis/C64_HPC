# tools/make_vic20u_basic.py
from __future__ import annotations

import argparse
from pathlib import Path
import config

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
BUILD = ROOT / "build"

DEFAULT_HOST = {
    "basic_load": 0x1001,
    "screen_start": 0x1E00,
}
DEFAULT_JIFFIES = 50


def get_host() -> dict[str, int]:
    host = dict(DEFAULT_HOST)
    host.update(getattr(config, "VIC20U_HOST", {}))
    return host


def low(n: int) -> int:
    return n & 0xFF


def high(n: int) -> int:
    return (n >> 8) & 0xFF



def checked_seed(seed: tuple[int, int], label: str) -> tuple[int, int]:
    lo, hi = seed
    if not 0 <= lo <= 255 or not 0 <= hi <= 255:
        raise ValueError(f"{label} seed bytes must be in 0..255: {seed!r}")
    return int(lo), int(hi)


def drive_seed(device: int, default: tuple[int, int]) -> tuple[int, int]:
    return checked_seed(
        getattr(config, "DRIVE_SEEDS", {}).get(device, default),
        f"drive {device}",
    )

def compact_drive_image() -> tuple[int, bytes]:
    """Return the unexpanded VIC-20 drive image address and compact body.

    The 3K VIC-20 build keeps a padded 1280-byte image.  An unexpanded VIC-20
    cannot afford that plus the BASIC host below the default screen at $1E00.
    For this drive-only target we trim trailing zero padding and place the image
    as high as possible, immediately below screen memory, unless VIC20U_HOST
    explicitly overrides drive_image.
    """
    host = get_host()
    raw = (BUILD / "vic20_drive.bin").read_bytes()
    body = raw.rstrip(b"\x00")
    if not body:
        raise ValueError("vic20_drive.bin is empty after trimming")

    if "drive_image" in host:
        addr = host["drive_image"]
    else:
        addr = host["screen_start"] - len(body)

    end = addr + len(body)
    if end > host["screen_start"]:
        raise ValueError(
            f"compact drive image ${addr:04X}-${end - 1:04X} overlaps screen "
            f"at ${host['screen_start']:04X}"
        )
    if addr < host["basic_load"]:
        raise ValueError(
            f"compact drive image is too large: {len(body)} bytes leaves start ${addr:04X}"
        )

    (BUILD / "vic20u_drive.bin").write_bytes(body)
    return addr, body


def generate_bas() -> None:
    h = get_host()
    d = config.DRIVE
    d8_seed = drive_seed(8, (37, 21))
    d9_seed = drive_seed(9, (91, 173))
    d10_seed = drive_seed(10, (211, 57))
    drive_addr, drive_image = compact_drive_image()
    memtop = drive_addr

    replacements = {
        "{TOTAL_WORK}": str(config.TOTAL_WORK),
        "{DRIVE_CHUNK}": str(config.DRIVE_CHUNK),
        "{DRIVE_IMAGE_ADDR}": str(drive_addr),
        "{DRIVE_IMAGE_LEN}": str(len(drive_image)),
        "{MEMTOP_LOW}": str(low(memtop)),
        "{MEMTOP_HIGH}": str(high(memtop)),
        "{JIFFIES_PER_SECOND}": str(getattr(config, "JIFFIES_PER_SECOND", DEFAULT_JIFFIES)),
        "{DRIVE_LOAD_DEC}": str(d["load"]),
        "{DRIVE_PARAMS_DEC}": str(d["params"]),
        "{DRIVE_STATUS_DEC}": str(d["params"] + 3),
        "{DRIVE_INLO_DEC}": str(d["params"] + 4),
        "{DRIVE8_SEED_LO_DEC}": str(d8_seed[0]),
        "{DRIVE8_SEED_HI_DEC}": str(d8_seed[1]),
        "{DRIVE9_SEED_LO_DEC}": str(d9_seed[0]),
        "{DRIVE9_SEED_HI_DEC}": str(d9_seed[1]),
        "{DRIVE10_SEED_LO_DEC}": str(d10_seed[0]),
        "{DRIVE10_SEED_HI_DEC}": str(d10_seed[1]),
    }

    text = (SRC / "vic20u_benchmark.bas.in").read_text(encoding="utf-8")
    for key, value in replacements.items():
        text = text.replace(key, value)
    unresolved = sorted({part for part in text.split() if "{" in part or "}" in part})
    if unresolved:
        raise ValueError(f"unresolved template placeholders: {unresolved[:20]}")

    # petcat BASIC V2 mode is happiest with lowercase keywords.
    text = text.lower().encode("ascii", "strict").decode("ascii")
    out = BUILD / "vic20u_bench.bas"
    out.write_text(text, encoding="ascii", newline="\n")
    print(f"wrote {out}")
    print(f"wrote {BUILD / 'vic20u_drive.bin'}: ${drive_addr:04X}-${drive_addr + len(drive_image) - 1:04X}")


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


def poke_decimal3(prg: bytearray, needle: bytes, value: int, label: str) -> None:
    if not 0 <= value <= 255:
        raise ValueError(f"{label}: byte value out of range: {value}")
    idx = prg.find(needle)
    if idx < 0:
        raise ValueError(f"could not find {label} placeholder in tokenized BASIC")
    repl = f"{value:03d}".encode("ascii")
    value_pos = idx + len(needle) - 3
    prg[value_pos:value_pos + 3] = repl


def set_basic_vartab_placeholder(prg: bytearray) -> None:
    load = prg[0] | (prg[1] << 8)
    basic_end = load + len(prg) - 2
    poke_decimal3(prg, b"45,000", basic_end & 0xFF, "POKE45/BASIC_END_LOW")
    poke_decimal3(prg, b"46,000", basic_end >> 8, "POKE46/BASIC_END_HIGH")


def append_blob(prg: bytearray, addr: int, blob: bytes, label: str) -> None:
    load = prg[0] | (prg[1] << 8)
    current_end = load + len(prg) - 2
    if current_end > addr:
        raise ValueError(
            f"BASIC image overlaps {label}: current end ${current_end:04X}, "
            f"target ${addr:04X}"
        )
    prg.extend(bytes(addr - current_end))
    prg.extend(blob)


def package_prg() -> None:
    h = get_host()
    drive_addr, drive_image = compact_drive_image()
    prg = bytearray(retarget_basic_prg((BUILD / "vic20u_bench_body.prg").read_bytes(), h["basic_load"]))
    set_basic_vartab_placeholder(prg)
    append_blob(prg, drive_addr, drive_image, "1541 drive image")
    out = BUILD / "vic20u_bench.prg"
    out.write_bytes(bytes(prg))
    print(f"wrote {out}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--package", action="store_true")
    args = ap.parse_args()
    if args.package:
        package_prg()
    else:
        generate_bas()


if __name__ == "__main__":
    main()
