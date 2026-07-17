TOTAL_WORK = 60000
DRIVE_CHUNK = 58

# Work distribution weights.
# Higher value means larger share of total work.
# For example, CW=80, DW=100 means C64 gets less work than each 1541.
C64_WEIGHT = 80
DRIVE_WEIGHT = 100

DRIVE = {
    "load": 0x0300,

    "common": 0x0300,
    "table": 0x0400,
    "ucmd": 0x0500,
    "start": 0x0520,
    "stop": 0x0560,
    "params": 0x05D0,
    "job_a": 0x0600,
    "job_b": 0x0700,
    "end": 0x0800,

    "job_a_code": 0x0003,
    "job_b_code": 0x0004,
    "job_jump": 0xD0,

    "via_prb": 0x1C00,
    "via_ddrb": 0x1C02,
    "led_bit": 0x08,
}

C64 = {
    "load": 0xC000,
    "params": 0xC100,
    "table": 0xC200,
    "end": 0xC300,
}
# VIC-20 + 3K expansion platform configuration.
# The original C64 configuration remains unchanged.
VIC_WEIGHT = 100
JIFFIES_PER_SECOND = 50

# Deterministic seed for the local C64 worker.
C64_SEED = (123, 45)

# Deterministic Monte-Carlo seeds used by VIC-20 hosts and 1541 workers.
# Values are stored as (low byte, high byte). Keeping these here makes the
# BASIC and assembly VIC-20 variants use the same streams by default.
VIC_SEED = (123, 45)
DRIVE_SEEDS = {
    8: (37, 21),
    9: (91, 173),
    10: (211, 57),
}
VIC20 = {
    "load": 0x1600,
    "params": 0x16A0,
    "table": 0x1700,
    "end": 0x1800,
}
VIC20_HOST = {
    "basic_load": 0x0401,
    "worker_load": 0x1600,
    "drive_image": 0x1800,
    "spare": 0x1D00,
}
