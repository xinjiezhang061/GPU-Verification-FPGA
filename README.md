# GPU-Verification-FPGA

Verify a triangle rasterizer, the stage of a GPU that turns a screen-space
triangle into covered pixels. The project includes a small SystemVerilog DUT, a
Python oracle, and a self-checking SystemVerilog testbench. It runs in simulation
without an FPGA board or vendor IP.

## Run

Requires Python 3, Make, and Icarus Verilog (`iverilog` and `vvp`). On macOS,
install Icarus with `brew install icarus-verilog`. See the
[Homebrew formula](https://formulae.brew.sh/formula/icarus-verilog) and the
[Icarus simulator guide](https://steveicarus.github.io/iverilog/usage/index.html).

```sh
make test
make regression
make test SEED=2027 RANDOM_COUNT=500 WAVES=1
```

- `make test` uses a 32×24 viewport, 24 directed triangles and 200 seeded
  random triangles, plus a reset-abort scenario.
- `make regression` runs two default-size seeds and exercises 1×1 and 128×128
  viewports. Set `WIDTH` and `HEIGHT` on `make test` to try another size.
- `make vectors` checks the Python oracle against hand-derived cases and
  generates expected fragments without an HDL simulator.
- `WAVES=1` writes `build/<WIDTH>x<HEIGHT>/rasterizer.vcd` for waveform debugging.
  Each run overwrites that viewport's vector file and, if enabled, waveform.

## Interface contract

| Signal | Contract |
| --- | --- |
| `tri_valid`, `tri_ready` | A rising edge with both high captures the six signed 8-bit vertex coordinates. One triangle can be in flight. |
| `frag_valid`, `frag_ready` | A rising edge with both high transfers one fragment. The DUT holds valid and coordinates stable during a stall. |
| `frag_x`, `frag_y` | Unsigned pixel indices. Transfers arrive left to right, then top to bottom. |
| `tri_done` | A one-cycle pulse after scanning and transferring all covered pixels. Empty and degenerate triangles also complete. A new command can be accepted in the following cycle. |
| `rst` | Active high. A rising edge with reset high clears pending work. Interface control outputs are suppressed while reset is high. |

Screen-space X increases rightward and Y increases downward. Vertices are
integer coordinates in −128 through 127. The viewport origin is (0,0), its
dimensions are each in 1 through 128, and a sample is at
`(frag_x + 0.5, frag_y + 0.5)`. At dimension 128 the outermost sample on that
axis is 127.5, beyond the maximum vertex coordinate. Both vertex windings are
accepted. The top-left rule assigns samples on shared edges to one triangle.
[Direct3D rasterization rules](https://learn.microsoft.com/en-us/windows/win32/direct3d11/d3d10-graphics-programming-guide-rasterizer-stage-rules)

The DUT scans the viewport and evaluates integer edge functions. The Python
oracle computes exact rational intersections of each sample row with the
triangle and fills the interval from the left intersection, inclusive, to the
right intersection, exclusive. Integer vertex Y values put horizontal edges
between sample rows. The testbench compares every transfer against the oracle
in order, so extra, missing, duplicate, and reordered fragments fail the test.
A failure reports the triangle label and first mismatch.

## Verification matrix

| Scenario | Check |
| --- | --- |
| Two triangles forming a rectangle, using either diagonal | Exact pixel ownership on the shared edge, with no cracks or double hits |
| All six vertex permutations | Identical coverage and output order |
| Clipped and off-screen triangles | Exact in-viewport coverage and empty completion when applicable |
| Collinear, repeated vertices, and subpixel coverage | Completion with zero fragments where no centers are covered |
| Signed coordinate extremes and viewport corners | Correct signed arithmetic, bounds, and end-of-scan behavior |
| Always-ready, alternating, and seeded backpressure | Exact stream and stable output under stalls |
| Reset while a fragment is stalled | Pending fragment and completion are cleared, followed by normal operation |
| Busy and completion checks | No command ready while busy, one completion per command, and bounded completion under the test's ready patterns |

The regression checks that it observed empty and nonempty cases and at least
one stalled cycle. Its scoreboard checks pixel coordinates and ordering. Its
coverage counters describe observed scenarios.

## Project milestones

1. **Rasterizer baseline.** Run `make regression` and require every scenario
   above to pass. Open a VCD for a stalled triangle and follow the command,
   fragment transfers, and completion.
2. **Depth and color.** Add constant color and depth to each command and use
   a small framebuffer model. Compare final contents after overlapping
   triangles in both draw orders. Specify depth ties, clear values, and write
   enables before adding randomized sequences.
3. **FPGA-oriented scan path.** Replace full-viewport scanning with a clipped
   bounding box and incremental edge updates. Reuse the scoreboard as the
   equivalence gate, then measure cycles per triangle, DSP use and post-route
   clock frequency on the chosen FPGA.

The delivered implementation covers milestone 1. The full-viewport scan and
combinational cross products keep the starting RTL readable for waveform
debugging. FPGA resource usage and timing are future measurements.
