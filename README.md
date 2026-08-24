# Parameterized Synchronous FIFO (Verilog)

Single-clock FIFO with configurable data width and depth, self-checking testbench, verified with Icarus Verilog.

## Specification

| Parameter | Value |
|---|---|
| `DATA_WIDTH` | configurable (default 8) |
| `DEPTH` | configurable, **must be a power of 2** (default 16) |
| Reset | active-low, asynchronous |
| Read latency | 1 cycle (registered output) |
| Flags | `full`, `empty`, `count` |

## Design notes

**Pointers are `ADDR_WIDTH+1` bits wide.** With plain address-width pointers, `wr_ptr == rd_ptr` is ambiguous — it means *empty* after a drain and *full* when the writer has lapped the reader exactly once. The extra MSB acts as a wrap bit:

- all bits equal → same lap → **empty**
- low bits equal, MSB differs → writer one lap ahead → **full**

This is why `DEPTH` must be a power of two — the low bits have to wrap exactly at the array boundary.

**Occupancy** is `wr_ptr - rd_ptr`; two's-complement subtraction handles the wrap case with no conditional logic.

**Illegal accesses are guarded internally.** A write while `full` or a read while `empty` is dropped rather than corrupting the pointers.

**Read is synchronous** — `rd_data` is valid the cycle *after* `rd_en`. This is not a first-word-fall-through FIFO.

## Verification

| Test | Covers |
|---|---|
| 1 | Flag state after reset |
| 2 | Fill to `full` |
| 3 | Write-while-full is ignored |
| 4 | Drain in FIFO order, data integrity |
| 5 | Read-while-empty is ignored |
| 6 | Simultaneous read + write, steady occupancy |
| 7 | Pointer wraparound over 2.5×`DEPTH` transactions |

The testbench keeps a software scoreboard queue alongside the DUT — every value read out is compared against the queue, so data integrity is checked on every single pop, not just at test boundaries.

```bash
iverilog -o fifo_sim sync_fifo.v tb_sync_fifo.v
vvp fifo_sim
```

### Simulation output

```
VCD info: dumpfile fifo.vcd opened for output.
Test 1 (reset flags)           : PASS
Test 2 (fill to full)          : PASS
Test 3 (write-while-full)      : PASS
Test 4 (drain, data integrity) : PASS
Test 5 (read-while-empty)      : PASS
Test 6 (simultaneous rd+wr)    : PASS
Test 7 (pointer wraparound)    : PASS
ALL TESTS PASSED
```

The run also dumps `fifo.vcd` for waveform inspection in GTKWave.

## Synthesis (Yosys, `synth_xilinx`, default 16×8 config)

| Resource | Count |
|---|---|
| Estimated logic cells | 67 |
| LUTs (LUT2–LUT6) | 78 |
| Flip-flops | 146 (128 FDRE memory + 18 FDCE pointers/output reg) |
| CARRY4 | 6 |
| MUXF7/F8 | 9 |

Yosys maps the 16×8 memory array to registers rather than block RAM at this depth (`Warning: Replacing memory \mem with list of registers`) — expected for a FIFO this small; larger depths would infer distributed or block RAM in Vivado.

## Future work

- Almost-full / almost-empty programmable threshold flags
- Asynchronous (dual-clock) variant with Gray-code pointers and 2-flop synchronizers
- Formal property checks (no overflow, no underflow, `full && empty` never both asserted)

## Author

Ashakirana V — B.E. Electronics and Communication Engineering, CMR Institute of Technology (VTU), Bengaluru
