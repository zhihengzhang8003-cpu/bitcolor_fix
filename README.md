# bitcolor_fix

BitColor FPGA project and Python benchmark script for comparing CPU and FPGA graph coloring performance on an `EP4CE10F17C8` target.

## Overview

This version is optimized for the `EP4CE10` resource budget:

| Parameter | Original | Optimized |
|------|------|--------|
| Max vertices | 128 | 64 |
| Max edges | 1024 | 512 |
| Storage | Registers | Block RAM |
| Estimated LAB usage | >846 LAB | <500 LAB |

## Files

```text
bitcolor_fix/
├── bitcolor_top.v
├── key_debounce.v
├── uart_rx.v
├── uart_tx.v
├── first_one_detect.v
├── bitcolor_fix.qpf
├── bitcolor_fix.qsf
├── bitcolor_fix_assignment_defaults.qdf
├── performance_test.py
└── README.md
```

Generated Quartus folders such as `db/`, `incremental_db/`, and `output_files/` are intentionally excluded from version control.

## Usage

### 1. Build and program

Open `bitcolor_fix.qpf` in Quartus, compile the project, then program the FPGA.

### 2. Quick benchmark

```bash
python performance_test.py COM3 quick
```

### 3. Extended benchmark

```bash
python performance_test.py COM3 extended
```

## Benchmark profiles

| Test | Vertices | Edges | Iterations | Expected CPU | Expected FPGA |
|------|------|------|------|---------|----------|
| quick | 50 | ~600 | 20000 | ~8s | ~2s |
| extended | 60 | ~1100 | 60000 | ~70s | ~15s |

## Notes

- Ensure the serial connection is wired correctly.
- The extended benchmark takes noticeably longer.
- `LED3` indicates FPGA completion.
- `performance_test.py` requires `pyserial`.
