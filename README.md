# C64 + 1541s Distributed Monte Carlo Benchmark


This project is a retrocomputing and computer architecture experiment: a Commodore 64 and up to three Commodore 1541 floppy disk drives are used as a tiny distributed system for estimating Pi with the Monte Carlo method.

> Maybe this project is the most perverted thing I have ever coded :=)

Generative AI helped a lot – the project took a lot of time, and I would not have had enough time to complete it without LLMs, though I believe I "own every line of code". Though this text and most comments are written by me (and checked by Grammarly).

- [C64 + 1541s Distributed Monte Carlo Benchmark](#c64--1541s-distributed-monte-carlo-benchmark)
  - [Idea](#idea)
  - [Results, TL;DR](#results-tldr)
  - [General review](#general-review)
  - [Testing](#testing)
  - [Theory](#theory)
    - [Working with disks](#working-with-disks)
      - [Bus and addressing](#bus-and-addressing)
      - [BASIC API](#basic-api)
    - [DOS commands](#dos-commands)
      - [M-R – memory-read](#m-r--memory-read)
      - [M-W -- memory-write](#m-w----memory-write)
      - [M-E – memory-execute](#m-e--memory-execute)
      - [User commands](#user-commands)
      - [Job queues](#job-queues)
  - [Note about the first attempt](#note-about-the-first-attempt)
  - [Final architecture](#final-architecture)
    - [Algorithm](#algorithm)
  - [Conclusions and future work](#conclusions-and-future-work)
  - [Sources](#sources)


## Idea

- Commodore 64 NTSC uses the MOS Technology 6510 CPU clocked at 1.023 MHz. 
- Commodore 1541 floppy disk drive (FDD) contains MOS 6502 with identical to 6510 ISA and instruction timing at 1 MHz.
- So, the CPU of the C64 and 1541 have almost the same computational power. 
- Additionally, 1541 is equipped with 2 KB RAM, which can be written, read by the C64, and executed by the 1541.  

So I decided to attempt to make a computational cluster from my C64, 1541, 1541-II, and Pi1541 cycle-accurate 1541 floppy emulator. 

> Note: Those computers are soooo slow that I am completely astonished and devastated -- how can developers make such great results with games and software for them! 

> Some photos of my C64 setup: [insta1](https://www.instagram.com/indrekis2/p/DVMok4ggt2Q/), [insta2](https://www.instagram.com/indrekis2/p/DVPPKpXAk93/).

## Results, TL;DR 

By the wall clock (it is important – see below):

**VICE Emulator** 

| Experiment         | Reported, s  | Efficiency | Wallclock, s | Efficiency |
| :----------------- | :----------- | ---------- | :----------- | ---------- |
| C64 only           | 26.71 ± 0.01 |            | 22.7 ± 0.6   |            |
| C64 + Drv 8        | 17.73 ± 0.05 | 0.75       | 17.00 ± 0.05 | 0.67       |
| C64 + Drv 8, 9     | 11.52 ± 0.05 | 0.77       | 11.7 ± 0.6   | 0.65       |
| C64 + Drv 8, 9, 10 | 9.36 ± 0.25  | 0.71       | 10.00 ± 0.05 | 0.57       |
| Drv 8, 9, 10       | 7.88 ± 0.57  | 1.13       | 12.7 ± 0.6   | 0.60       |

**Real hardware**

| Experiment         | Reported, s  | Efficiency | Wallclock, s | Efficiency |
| :----------------- | :----------- | ---------- | :----------- | ---------- |
| C64 only           | 26.71 ± 0.01 |            | 22.1 ± 0.1   |            |
| C64 + Drv 8        | 17.73 ± 0.07 | 0.75       | 16.9 ± 0.1   | 0.66       |
| C64 + Drv 8, 9     | 11.54 ± 0.05 | 0.77       | 11.8 ± 0.1   | 0.63       |
| C64 + Drv 8, 9, 10 | 9.04 ± 0.09  | 0.74       | 9.6 ± 0.2    | 0.57       |
| Drv 8, 9, 10       | 7.66 ± 0.26  | 1.16       | 12.2 ± 0.2   | 0.60       |

Efficiency is $E = t_{C64}/t/N$, where N is the number of workers. The expected value is 1, with performance scaling linearly as we add new workers, though we sometimes see superlinear improvements.

Reported -- by the C64 timer.

Compared to reality, emulators are very precise. 

Results, reported by the C64 timer, are rather imprecise, though relevant. Only for the drives, the only error is substantial -- the relative error is large.

Regarding the Pi, a value close to 3.147 is obtained most of the time. Though at least once I obtained the 2.8…

Run on real hardware (better quality [here](https://github.com/indrekis/C64_HPC/blob/master/media/real_C64.mp4)): 

https://github.com/user-attachments/assets/a8c6c950-32e8-4cf4-80d8-aea2f9fc1d78

Run on VICE:

https://github.com/user-attachments/assets/e179a4fb-d9a0-4907-a1b8-4af4ab77b3c2

Run on Denise:

https://github.com/user-attachments/assets/1468dc6a-c9f7-4963-8a32-2abcc066fb9c



## General review

- Problem selected for computation -- calculating the Pi number using the Monte-Carlo sampling method.  
- Circle quarter coordinates are precalculated before the start.
- Code and table are uploaded to the disk drives before the start. 
- Calculations on the C64 are performed by the assembly code, too. 

For each point, two pseudo-random 8-bit coordinates are generated. The point is tested against a quarter circle:

$x^2 + y^2 <= 256^2$

To avoid an expensive multiplication or square root in the inner loop, the program precomputes a threshold table:

```text
Q[x] = floor(sqrt(65536 - x*x))
```

Then the test becomes:

```text
inside if y <= Q[x]
```

After all workers finish, the final estimate is:

```text
pi ≈ 4 * inside_count / total_points
```

The algorithm is embarrassingly parallel: each worker can generate and test its own random points independently. Only the final counts must be combined.

## Testing 

Testing was performed using the VICE emulator 3.10, Denise 2.5 (their results are consistent), and a real C64. Both the datasette and the disk drive emulator were used to upload the code to the real C64. 

## Theory 

I had very limited experience with the C64 and never worked directly with Commodore 1541 DOS before. Here are some general notes for future me.

### Working with disks

#### Bus and addressing 

Disk drives are connected to the C64 via the [IEC Bus (Commodore serial bus)](https://www.pagetable.com/?p=1031), which is derived from a parallel IEEE-488 interface. Devices are addressed by device number and channel number.  Devices are chained serially. Global numbering is used for both local devices and devices connected via the IEC bus. Disk drive are assigned numbers 8,9,10,11. Example of the local device -- Datasette, type reader with number 1. 

Standard 1541 FDD is managed by Commodore DOS (CBM DOS) 2.6. There is a convention between the KERNAL -- C64 built-in OS and the 1541 DOS, about the channel number (secondary addresses):

- Channel 0 is used for loading PRG – programs, ch. 1 – for saving them.
- Ch. 2-14 are used for “ordinary” file data exchange. 
- Ch. 15 -- command/status channel. It is used to command the 1541 FDD; DOS interprets the commands and sends status through this channel. 

For the default 1541, the disk number is hardcoded to 8; changing it could be performed in two ways:

- Cut some traces on the board.
- Start as the default 8 and change the dedicated byte in the disk RAM ([requiring a dedicated dance of the powering drives and C64 on and off](https://forum.vcfed.org/index.php?threads/accessing-two-1541-drives.52744/post-639431)): 
``OPEN 15,8,15:PRINT#15,"M-W";CHR$(119);CHR$(0);CHR$(2);CHR$(41)+CHR$(73):CLOSE 15``. 

> Note: for many games, disk is hardcoded to 8 too – you start the game from the drive 10, and then it attempts to use drive 8 for its data… 

I have a standard (European edition) 1541-II (number 8), a user-modded 1541 (USA edition) with a switch to select 9 or 8, and Pi1541 is configured by the file on the SD card. 

| ![](media/MK_scr2.png) | 
| :----: |
| My setup with an early test on screen. Pi1541 is on C64, above the keyboard. TRS-80 under the TV is unrelated to this project, it just lives there :=)  |

#### BASIC API

Commodore BASIC relies on the KERNAL routines to communicate with devices. For example: 

```basic
LOAD "PROGRAM",8
```

Loads (typically – BASIC) program from disk 8 (first FDD) to ``$0801`` location,

```basic
LOAD "PROGRAM",8,1
```

Loads from disk 8, using the address set in the first two bytes of the PRG file -- primitive relocation instrument. Address is stored as a little-endian -- bytes ``$01 $08`` corresponding to the ``$0801``. Both commands use channel 0.

> Note: to get list of files, we use:
> ```basic
> LOAD "$",8
> LIST
> ```
> And it overwrites current program in memory…


To open a file, we can use the following command:

```basic
OPEN 2,8,3,"0:FILENAME,S,W"
```

Where:

-  2 – File number used in the following operations to refer to this opened file (we have made much progress with automatically assigning the file numbers since those times :=).
- 8 – FDD number.
- 3 – channel to use.
- ``0:FILENAME,S,W`` string is sent to 1541 and DOS interprets it like this: 
  - ``0:`` drive number inside the FDD -- legacy from the dual-drive Commodore 4040 device, for 1541 and their newer models, always 0. Can be skipped, though its presence is reported to avoid some early 1541 DOS firmware bugs. 
  - ``FILENAME`` is self-explanatory.
  - ``,S`` – file type, sequential.
  - ``,W`` – open for write.

Typical operations with the file:

```basic
PRINT#2,"HELLO"
CLOSE 2
```

Other operations, such as deleting a file, can be performed using the command channel, where S -- SCRATCH, 1541 DOS name for delete/erase:

```basic
OPEN 15,8,15
PRINT#15,"S:FILENAME"
CLOSE 15
``` 

One can check the status of the last command in the following way (channel should be opened): 

```basic
1230 INPUT#15, EM, EN$, ET, ES
``` 

Where:

- ``EM`` -- error code (0 – no error).
- ``EN$`` -- string with error description (can also describe the successful operation).
- ``ET`` -- track number where the error occurred.
- ``ES`` -- block (sector) number where the error occurred.
- ``EN$`` is always a string; the other three can be read as a string or as a number.

> Note: INPUT does not work from the interactive mode -- only from the program mode. 

> Note 2: Spaces and comments use the precise memory, so in practice, they were sometimes considered harmful (keywords, such as INPUT, are saved in tokenized form, taking mostly 1 byte plus their arguments). Though for clarity and without having strong limits on memory, I use them extensively. 

### DOS commands

1541 DOS supports many commands. Among them are mentioned above ``S``, many commands for general use, such as ``N``/``NEW`` -- format disk, ``R``/``RENAME``, ``I0`` -- initialize disk, reread the so-called ``BAM`` (Block Availability Map), and so on. They are listed in the corresponding manuals. Important for this problem are the following:

#### M-R – memory-read

```basic
PRINT#15,  "M-R"+CHR$(LO)+CHR$(HI)
GET#15,A$ 
``` 

Memory read: read byte from 1541 RAM or ROM at the HI*256+LO, get is used to read the command result. 

#### M-W -- memory-write

```basic
PRINT#15,  "M-W"+CHR$(LO)+CHR$(HI)+CHR$(N)+DATA$ 
```

N – data size, ``DATA$`` -- string of bytes. Maximal N size – 35 bytes (I use 32). 

> Note: Data length is limited by the command length limit – 42 bytes, 41 characters are allowed. The command itself uses 6 bytes, so limit for data is 41-6=35.  See also [Commodore 1541 drive memory map](https://sta.c64.org/cbm1541mem.html) for  ``$0200-$0229``.

> Note: Basically, the default C64-1541 transfer speed is about 400 bytes/s. It is so slow that the entire fast loaders and fast loader cartridge industry emerged.

#### M-E – memory-execute 

```basic
PRINT#15,"M-E"+CHR$(0)+CHR$(5): REM EXECUTE CODE AT $0500
```

Code executed should end with RTS. On the C64, the PRINT command is blocked until then. 

> **Important remark**: BASIC timer, available through the TI C64 BASIC variable, stops while waiting for the PRINT. It had an interesting adverse effect, see later. Books call this effect “Timers can be unreliable”. 

#### User commands 

- U3 (synonym UC) – user command, executes code at the ``$0500``. 
- U4 (UD) – same, for the code at ``$0503``, 
- and so on: U5-U8 (UE-UH). 

Three bytes reserved are just enough for the jump. 

Other relevant: 

- U0 -- reset user jump table.
- U9 (UI) -- soft drive reset. 
- U: (UJ) -- hard reset. 

#### Job queues 

1541 DOS has one more interesting mechanism -- job queues. Technically, it is a small buffer of 6 bytes at ``$0000-$0005`` -- job slots. Drive code scans through this table, and if it sees a job code (bit 7 = 1), executes it and puts the result code in the same slot (the result code is distinguished by the bit 7 = 0; ``$01``  means ``OK``). 

Main job codes: 

- ``$80``  ``READ`` (read sector into buffer), 
- ``$90``  ``WRITE``, 
- ``$A0``  ``VERIFY``, 
- ``$B0``  ``SEEK``, 
- ``$C0``  ``BUMP`` (bump head to track 1), 
- ``$D0``  ``JUMP`` -- execute code in buffer,
- ``$E0``  ``EXECUTE`` -- execute code in buffer after motor/head ready. 

For each job slot, two memory blocks are associated: the track/sector number (``$0006/$0007`` for slot 0, ``$0008/$0009`` for slot 1, and so on) and the 256 bytes buffers where sector data can be stored for disk operations or code for execution:

- ``$0300-$03FF``  for job 0,
- ``$0400-$04FF`` for job 1,
- ``$0500-$05FF`` for job 2 (is called “user buffer”, so, I hope it is not used by the DOS itself),
- ``$0600-$06FF`` for job 3,
- ``$0700-$07FF`` for job 4,
- Slot for job 5 does not have a real buffer – not enough RAM in the 1541. 

As one can see from the available operation codes, this mechanism is extremely flexible. 


## Note about the first attempt

The first attempt was straightforward. Blob of the binary code and its variables is written to the 1541s by the "M-W", executed by the "M-E," and the result is read by the “M-R”. Time was measured by the internal timer, accessible by the TI variable. Results looked promising -- the more 1541s were calculating, the faster the result was obtained. 

But something was wrong... Trying to fix it, I did the following. The C64 Monte-Carlo code was first written using BASIC and was too slow, so I replaced it with another blob, equivalent to the 1541 code, and added the ability to change C64 and 1541s weights -- because C64 is doing additional work. Then one thing started to be obvious. Times, printed by the program, showed rather good scaling with the number of 1541 workers, but it was clearly wrong. Using a manual stopwatch, I checked in the emulators and on real hardware -- calculation durations were practically the same regardless of the workers used.

To debug the problem, I added drive LED blinking while calculating the results. And the LED showed – drives are working sequentially. 

> Note: One should be extremely careful manipulating the LED state -- the same register is used for the motor control, and according to the books about the 1541, it can position the head in a position where it can be extracted only by disassembling the drive. Though the book says it is safe for the drive, I believe it can be damaged this way, or at least, I prefer not to test how much abuse a real 1541 mechanism can survive.
 
If I put ``RTS`` command in the calculation code, C64 can continue its work, but 1541 calculations are terminated. So, looked like my problem was impossible to solve. 

For two weeks of evenings, I tortured the AI and read the literature on the 1541 hardware and DOS to find a solution. All the AIs tried to persuade me that it is impossible. Only when I read about the work queue and U3 and friends user commands, AI believed me and helped to create a working code at last. 

**Takeout**: computers lied even decades before the LLM hallucinations -- it was unexpected to see correct results on the screen, while real results were totally wrong, as in a badly performed students' lab.

## Final architecture

> Note: I had an inclination to call this part “Proposed solution” – our alumni should get this:=) 

### Algorithm 

The table of circle quadrant is precalculated by the C64, and the code is uploaded onto 1541s before the time measurements start -- let us imagine that we run the code many times. In fact, I was more interested in parallel calculations, and uploading the code is slow and inherently sequential (I can imagine how it can be fixed by the custom fastloader, but it would be at least as difficult as the current project or even more). Additionally, though precalculating the table or, at least, moving its calculation to the drives can be useful at last from the total time required, I was too lazy to perform this refactoring for such an already long project. It also copies a blob of binary code for itself for uniformity.

| ![](media/IMG_20260706_234336_086.jpg) | 
| :---: |
| Photo of the real calculations. The error occurred because I unintentionally turned off one of the FDDs during the final cleanup and reinitialization. |

C64 uploads the code binary blob to 1541, starting from ``$0300``, including: 

- Common routines, including the Monte Carlo code at ``$0300``.
- Jumps for the U3 (``$0500``) and U4 (``$0503``) commands and their corresponding handler subroutines (start_worker and stop_worker). 
- Two almost identical jobs -- A and B to ``$0600`` and ``$0700`` buffers (be careful -- ``$0700`` is reserved for the BAM -- Block Availability Map, critical disk structure, so overwriting it is risky unless the drive is kept under tight control).
  - Note: Uploading is non-optimal because many parts of the blob (``$0400`` and part of the ``$0500`` block) can be skipped.
- C64 uploads the precomputed TABLE to ``$0400``.
- C64 uploads computation input data to ``$05D0`` -- different for each drive.
- C64 sends the U3 command using the ``PRINT#D,"U3"`` command for each drive.
  - ``U3`` calls ``start_worker``, which puts job A (``$D0`` -- ``JUMP``) into the у job queue and returns. Then C64 can continue.
  - At the end of the job A, it puts job B into the queue (and vice versa).
  - As a result, the drive, scanning the job table, calls job A and job B in turn, performing the calculations. 
   - > Note 1: Two jobs switching from one to another are used to avoid race conditions with the error code in the job slot. I’m not sure if it is the optimal solution, but it works. 
- After the C64 finishes its own work, it can query the results of the 1541s using the ``M-R`` command and send ``U4`` to stop workers. 

So the calculation looks like:

```text
start_worker -> queue A

A:
  step_chunk
  queue B
  RTS

B:
  step_chunk
  queue A
  RTS

A:
  ...
```

Every 256 chunks, the LED state is changed. This is done by directly manipulating the VIA port register (which corresponds to the second VIA 6522  -- Versatile Interface Adapter, I/O port controller, of the 1541, responsible for the):

```text
VIA PRB  = $1C00  -- Port Register B / DSKCNT
VIA DDRB = $1C02 -- Data Direction Register B
LED bit  = $08 – bit 3 mask 
Note: bits 0-1 control the stepper phase, and bit 2 controls the spindle motor.
```

Default C64 memory layout:

```text
$C000  C64 worker code
$C100  C64 worker parameters and result
$C200  C64 copy of the threshold table Q[0..255]
```
It is executed by the command “SYS 49152” (SYS 49152). 

1541 memory layout:

```text
$0300  common routines
$0400  threshold table Q[0..255]
$0500  U3/U4 entry stubs
$0520  start routine
$0560  stop routine
$05D0  parameters and result
$0600  job A
$0700  job B
```

The parameter block at `$05D0` contains:

```text
$05D0  iteration count low byte
$05D1  iteration count high byte
$05D2  seed low byte
$05D3  status
$05D4  result low byte
$05D5  result high byte
$05D6  seed high byte
$05D7  temporary x
$05D8  job counter
$05D9  stop flag
$05DA  temporary flag
$05DB  blink counter
```

The status byte is used as follows:

- 1 -- running,
- 2 -- finished,
- 3 -- stopped.

The C64 polls the drive status byte at `$05D3`. 


An important constant here is the DRIVE_CHUNK — the number of Monte-Carlo iterations for one job quantum. The more the better, but it looks like value 32 is optimal: for 16 calculations are too slow, and for 64 drives calculate almost sequentially. Looks like long jobs somehow starve the drives of returning control to the C64 (e.g., by not freeing the bus). Though here it is just a hypothesis.

> Note: In the emulators, for the current code, LEDs are blinking continuously since the moment the code started. On the real C64, they light up but don't blink until the C64 has finished its calculations. I am not sure what this means, because the timings are fairly consistent across the emulators and hardware. 

Project code structure:

```text
src/
  benchmark.bas.in       BASIC V2 template for the C64 benchmark
  c64_worker.asm         6510/6502 worker code executed on the C64
  drive_worker.asm       6502 worker code executed inside each 1541
  generated_*.inc        generated assembler constants
  generated_*.cfg        generated ld65 memory maps

tools/
  config.py              benchmark and memory-layout configuration
  make_includes.py       generates ca65 includes and ld65 configs
  make_basic.py          embeds worker binaries into BASIC DATA

Makefile                 build rules
seq3vis.bas              vibecoded Monte Carlo demo
```

- Code is generated from the templates, and blobs are created using Python 3. 
- Assembly code is compiled using the ca65 assembler and ld65 linker from the cc65 package for the 6502-based systems. https://cc65.github.io/ 
- A tokenized BASIC PRG-file is created using the petcat from the VICE emulator package, and disk images are created using the c1541 from the same package. 
- VICE and Denise emulators were used for testing.
- C64 Studio was used as an auxiliary but useful tool -- it allows one to check the generated BASIC code and run it in VICE with a single shortcut. 


The **Makefile** is used to generate the final PRG and C64 disk image. Targets: 

- make     --    build benchmark.prg
- make disk  --   build benchmark.d64
- make clean  -- remove generated files and build output


**src/benchmark.bas.in** -- template for the main C64 BASIC V2 program. This file contains the C64 code.

The file contains placeholders such as:

- {TOTAL_WORK}
- {DRIVE_CHUNK}
- {DRIVE_DATA}
- {C64_DATA}

These are replaced by **tools/make_basic.py**.

**src/c64_worker.asm** -- 6502/6510 assembly code executed on the C64 itself. Uses constants from the generated file "**generated_c64.inc**", with addresses to be used by the code.

**src/drive_worker.asm** -- 6502 assembly code executed inside each 1541 disk drive. Uses constants from the generated file "**generated_drive.inc**", with addresses and other constants to be used by the code.

Generated .inc-files are created by the **tools/make_includes.py**, based on the configuration from the **tools/config.py**. Other important generated files are the **generated_c64.cfg** and **generated_drive.cfg** -- configurations for the linker, describing the exact memory layouts. 

Among other things, **tools/config.py** contains TOTAL_WORK (total Monte-Carlo iterations – 16-bit value) and DRIVE_CHUNK, C64_WEIGHT and DRIVE_WEIGHT parameters. 

**tools/make_basic.py** builds the final BASIC file, reading build/drive_worker.prg, build/c64_worker.prg, and src/benchmark.bas.in and embedding the worker binaries into BASIC DATA statements. 

Final files, depending on requirement, are:

- build/benchmark.bas
- build/benchmark.prg
- build/benchmark.d64

> Note: not all values can be freely changed in configurations (some are partially hardcoded, directly or semantically, see sources) -- I have not addressed this deficiency yet.

To run the code, use: 

```basic
LOAD"BENCHMARK",8
RUN
```

## Conclusions and future work

Thanks to the intellectual disk drives, the C64 became a small heterogeneous computational cluster. 

The numerical problem is embarrassingly parallel -- each Monte Carlo sample is independent. No worker needs data from another worker during the computation. So, from the algorithmic point of view, it is the simplest possible problem to parallelize – most problems were technical. 

As a result, obtained scalability, with efficiency about 0.6-0.7, is "not great, not terrible" -- much worst than it should be in real parallel calculations, better than I expected from such an exotic setup.

Let’s align our terminology with the terminology commonly used in HPC:

- The total number of samples is split before the run -- we have static scheduling. There is no dynamic work stealing.
- The C64 acts as the host, scheduler, loader, and result collector. Also, it is used as a worker to some extent. 
- The 1541 drives behave as very small asynchronous coprocessors.
- System is heterogeneous to some extent. 
  - C64 worker is a local CPU kernel. 
  - 1541 workers -- asynchronous device kernels.
  - IEC bus -- slow control and data interconnect.
  - M-W/M-R -- API for explicit memory transfer.
  - U3/U4 -- kernel launch and stop API.
  - job queue – internal cooperative device scheduler.

Related "competencies":

- 6502/6510 assembly programming;
- C64 BASIC programming;
- memory-mapped I/O;
- device firmware as an execution environment;
- host-device communication;
- asynchronous accelerators;
- job queues and cooperative scheduling;
- message granularity;
- static load balancing;
- speedup and efficiency;
- why “more processors” does not automatically mean “proportionally faster”.
- Additionally, without the LLMs I would never have finished this project – possibly never even started it.

Though the system is ancient and extremely slow by current standards, the ideas are still relevant and important. 

Future work could include optimizations and generalization:

- Uploading into two or more drives simultaneously
- Optimizing blob for uploading 
- Developing parallel programming framework for the C64 
- Adding ability to communicate [between the drives](https://forum.vcfed.org/index.php?threads/accessing-two-1541-drives.52744/).


## Sources

[CBM DOS ROM disassembly and memory variables for Commodore 1541 drive](https://g3sl.github.io/c1541rom.html)

[Commodore Peripheral Bus: Part 3: Commodore DOS](https://www.pagetable.com/?p=1038)

[Commodore 1541 / OC-118 Disk Drive Memory Map](https://www.zimmers.net/anonftp/pub/cbm/maps/C1541ram.txt)

[The Complete Commodore Inner Space Anthology](https://www.zimmers.net/anonftp/pub/cbm/manuals/anthology/400/index.html)

["The Anatomy of the 1541 Disk Drive" by Lothar Englisch, Norbert Szczepanowski](https://archive.org/details/The_Anatomy_of_the_1541_Disk_Drive)

["Inside Commodore DOS: The Complete Guide to the 1541 Disk Operating System" by Richard Immers, Gerald Neufeld](https://www.pagetable.com/docs/Inside%20Commodore%20DOS.pdf)


[Commodore 1541 Disk Drive User’s Guide / VIC-1541 Disk Drive User’s Manual](https://archive.org/details/Commodore_1541_Disk_Drive_Users_Guide_1982-09_Commodore)

