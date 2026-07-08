TOTAL_WORK = 60000
DRIVE_CHUNK = 32

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
