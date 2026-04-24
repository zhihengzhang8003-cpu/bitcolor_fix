# bitcolor_fix

`bitcolor_fix` is an FPGA implementation of a graph-coloring accelerator plus a Python benchmark script for comparing FPGA and CPU execution time on the same workload.

The design targets the `EP4CE10F17C8` and is configured for a Wildfire board variant labeled `野火征途Pro` in the Quartus pin assignments.

## What This Project Does

- Loads graph data over UART into on-chip memories.
- Runs an optimized graph-coloring flow on the FPGA.
- Sends results back over UART.
- Compares FPGA runtime against a Python CPU implementation using the same generated graph instances.

## Optimization Goal

This version is a resource-constrained fix/optimization for `EP4CE10`:

| Parameter | Original | Optimized |
|------|------|--------|
| Max vertices | 128 | 64 |
| Max edges | 1024 | 512 |
| Storage | Registers | Block RAM |
| Estimated LAB usage | >846 LAB | <500 LAB |

The Quartus project comments describe this as a fix for a multi-driver conflict while keeping the design within the device budget.

## Repository Layout

```text
bitcolor_fix/
├── bitcolor_top.v                       # Top-level FPGA design
├── first_one_detect.v                   # Bit scan / first available color helper
├── key_debounce.v                       # Button debounce logic
├── uart_rx.v                            # UART receiver
├── uart_tx.v                            # UART transmitter
├── performance_test.py                  # CPU vs FPGA benchmark script
├── bitcolor_fix.qpf                     # Quartus project file
├── bitcolor_fix.qsf                     # Quartus settings and pin assignments
├── bitcolor_fix_assignment_defaults.qdf # Quartus assignment defaults
└── README.md
```

Generated Quartus folders such as `db/`, `incremental_db/`, and `output_files/` are intentionally excluded from version control.

## Hardware Target

- FPGA: `Intel/Altera Cyclone IV E`
- Device: `EP4CE10F17C8`
- Default clock assumption in RTL: `50 MHz`
- UART baud rate in RTL: `115200`

Selected top-level signals from the design:

- `sys_clk`
- `sys_rst_n`
- `uart_rx`
- `uart_tx`
- `key_start`
- `led[3:0]`

## Toolchain

- Quartus project version metadata:
  - Original: `22.1`
  - Last saved: `24.1std.0 Lite Edition`
- Python 3 for benchmarking
- Python package: `pyserial`

Install the Python dependency with:

```bash
pip install pyserial
```

## Build And Program

1. Open `bitcolor_fix.qpf` in Quartus.
2. Compile the project.
3. Program the FPGA device.
4. Connect the UART interface used by the Python benchmark script.

## Run Benchmarks

Quick benchmark:

```bash
python performance_test.py COM3 quick
```

Extended benchmark:

```bash
python performance_test.py COM3 extended
```

## Benchmark Profiles

| Test | Vertices | Edges | Iterations | Expected CPU | Expected FPGA |
|------|------|------|------|---------|----------|
| quick | 50 | ~600 | 20000 | ~8s | ~2s |
| extended | 60 | ~1100 | 60000 | ~70s | ~15s |

The exact times depend on host CPU speed, serial stability, and whether the board is programmed with the matching bitstream.

## How The FPGA Side Is Structured

At a high level, the top-level design contains:

- Block RAM style storage for graph offsets, edges, and colors.
- UART command handling for loading graph data and requesting execution.
- A coloring engine that tracks used neighbor colors and selects the first available color.
- Timing counters for reporting FPGA runtime back to the host.

## Notes

- Ensure the UART wiring matches the board and host adapter.
- The benchmark script assumes a serial device such as `COM3`; change that to match your system.
- `LED3` is used as a completion indicator in the project notes.
- The extended benchmark takes noticeably longer than the quick profile.

## Suggested GitHub Description

`FPGA graph-coloring accelerator for EP4CE10 with Quartus project files and Python CPU-vs-FPGA benchmarks.`
