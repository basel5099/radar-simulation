# AERIS-10 Bit-True MATLAB Simulation (FPGA pipeline + end-to-end scenario)

This folder implements **Phase 3.3 ("bit-true DSP reference chain") and the
DSP part of Phase 5 ("end-to-end integration")** of `AERIS-10_Simulation_Plan.docx`:
a MATLAB model of the complete FPGA signal-processing pipeline
(vendored under `reference/fpga`, see ../UPSTREAM.md) that reproduces the Verilog fixed-point arithmetic
**bit-for-bit**, plus a full radar-scenario simulation that runs a 32-chirp
staggered-PRI frame through it.

```
scene (targets/clutter -> IF echoes) -> 8-bit ADC @ 400 MSPS
  -> NCO + mixer (DDC @ IF 120 MHz)          [nco_400m_enhanced.v, ddc_400m.v]
  -> CIC decimate-by-4 (5-stage)             [cic_decimator_4x_enhanced.v]
  -> 32-tap FIR + 18->16-bit rounding        [fir_lowpass.v, ddc_input_interface.v]
  -> digital gain (AGC stage)                [rx_gain_control.v]
  -> multi-segment matched filter, 1024-pt   [matched_filter_*.v, fft_engine.v]
  -> range-bin decimation 1024->64 (peak)    [range_bin_decimator.v]
  -> optional 2-pulse MTI                    [mti_canceller.v]
  -> dual 16-pt Hamming Doppler FFT          [doppler_processor.v]
  -> optional DC notch                       [radar_system_top.v]
  -> CA/GO/SO-CFAR                           [cfar_ca.v]
```

## Usage

```matlab
cd matlab
aeris_explorer       % interactive system explorer (start here!)
run_all              % golden validation + end-to-end sim
% or individually:
validate_against_golden();   % 25 bit-exact checks vs repo golden vectors
aeris_endtoend_sim();        % full scenario -> range-Doppler maps + CFAR
```

### Interactive radar lab (`aeris_explorer`)

A clickable block diagram of the whole radar â€” STM32 supervisor, chirp
generator, DAC, TX/RX RF chains, antenna, ADC, and every FPGA DSP block.
Clicking a block shows a one-line "what you're seeing" caption plus four
tabs:

- **Specification** â€” bit-true parameters, register defaults, source-file
  references and the findings the simulation surfaced for that block,
- **MATLAB model** â€” the `+aeris` source (with "Open in Editor"),
- **FPGA source (Verilog)** â€” the corresponding RTL file,
- **Signal view** â€” that stage's actual signal from the bit-true chain
  (chirp LUT, NCO, mixer/CIC/FIR outputs, FIR frequency response,
  matched-filter range profile, decimated bins, MTI before/after,
  range-Doppler maps, CFAR detections, USB detection list).

**Scenario Lab** (bottom left): edit the targets (range / velocity / RCS,
enable/disable), noise level, AGC gain, MTI on/off, DC-notch width and the
CFAR parameters (alpha, guard, training cells) â€” then press *Apply
scenario*. Detector-only changes (CFAR/notch/MTI) update **instantly**
from the cached Doppler maps; scene changes re-run the full 32-chirp frame
through the bit-true pipeline (~15 s with progress). Suggested
experiments: sweep CFAR alpha and watch detections vs. false alarms;
toggle MTI to unmask the mover hidden by clutter; set AGC gain to 0 and
watch FFT clipping destroy the compression.

**Guided tour** (top right): a 16-step plain-language walk through the
whole signal chain â€” what each block does physically and why it exists â€”
auto-selecting each block with its live signal view.

The other toolbar button runs the 25-check golden validation live.

Headless: `matlab -batch "cd('matlab'); run_all"`.
Outputs go to `generated/matlab_validation/` and
`generated/matlab_endtoend/` (gitignored, per repo file-placement policy).
No toolboxes are required (plain MATLAB; exact integer arithmetic in doubles).

## Files

| File | Models | Source of truth |
|---|---|---|
| `aeris_params.m` | every bit-true constant (FIR taps, NCO LUT, Hamming, CFAR defaults, timing) | RTL parameter blocks |
| `+aeris/nco_sincos.m` | 32-bit phase acc + 64-entry quarter-wave LUT | `nco_400m_enhanced.v:83-99` |
| `+aeris/ddc_chain.m` | ADC sign conv, mixer truncation, CIC (5,4), FIR, 18â†’16 rounding | `ddc_400m.v`, `cic_*.v`, `fir_lowpass.v`, `ddc_input_interface.v` |
| `+aeris/rx_gain_control.m` | power-of-two digital gain + saturation | `rx_gain_control.v:119-126` |
| `+aeris/fft_fixed.m` | radix-2 DIT FFT/IFFT, quarter-wave twiddles, >>>15 butterflies, IFFT >>>log2N | `fft_engine.v` |
| `+aeris/conj_mult_q15.m` | conjugate multiply, round +2^14, sat, [30:15] | `frequency_matched_filter.v` |
| `+aeris/matched_filter_1024.m` | FFT â†’ conj-mult â†’ IFFT | `matched_filter_processing_chain.v` |
| `+aeris/mf_multi_segment.m` | input rounding, segmentation, zero-pad (both framings, see below) | `matched_filter_multi_segment.v` |
| `+aeris/range_bin_decimator.m` | centre/peak/average 16:1 | `range_bin_decimator.v` |
| `+aeris/mti_canceller.m` | 2-pulse canceller, first-chirp mute | `mti_canceller.v` |
| `+aeris/doppler_process.m` | dual 16-pt Hamming-windowed FFT | `doppler_processor.v` |
| `+aeris/dc_notch.m` | post-Doppler DC notch | `radar_system_top.v` |
| `+aeris/cfar_ca.m` | CA/GO/SO CFAR, Q4.4 alpha, |I|+|Q| | `cfar_ca.v` |
| `+aeris/scene_generate_adc.m` | IF echo synthesis (radar_scene.py model) | `tb/cosim/radar_scene.py` |
| `+aeris/load_chirp_refs.m`, `read_mem_hex.m`, ... | .mem/.hex I/O (reads the FPGA chirp LUTs and twiddle ROMs directly) | `*.mem` |

## Validation status (validate_against_golden.m)

**25/25 bit-exact** against the artifacts in `reference/fpga/tb` (vendored from the upstream repo):

- Matched-filter core: 4 cosim cases (dc/impulse/tone5/chirp) â€” 0 differing samples
  (these goldens equal the Icarus RTL dumps, see `compare_mf_*.csv`).
- Multi-segment wrapper: long (4 segments) + short â€” 0 differing samples.
- Doppler: 3 scenarios â€” 0 differing samples.
- Real-data full chain (ADI CN0566 capture): decimator, MTI, Doppler (with and
  without MTI), DC notch, CFAR magnitudes/thresholds/flags and the exact
  4-entry detection list â€” all 0 differing.
- Raw RTL block dumps: NCO (1 MHz), CIC (impulse/DC/passband sine),
  FIR (impulse/DC/passband sine) â€” exact after pipeline-latency alignment.

Deliberately not used as targets: `tb/mf_golden_*_case1-4` (floating-point
reference, not bit-true) and `tb/cosim/compare_<scenario>.csv` (stale: their
own `py` and `rtl` columns disagree).

## Findings (things the simulation surfaced about the RTL as-built)

1. **NCO quadrant mapping**: the quarter-wave mirror condition is
   `quadrant[0] ^ quadrant[1]` (mirrors quadrants 1 and 2). A textbook DDS
   mirrors 1 and 3; in quadrants 2/3 the produced sin/cos are swapped, so the
   NCO output is discontinuous at 180Â°. Verified against
   `tb/nco_1mhz_output.csv` â€” the model replicates it exactly. The 120 MHz
   FTW makes the dwell per quadrant < 1 cycle so the DDC still works, but
   fixing the mirror would lower mixer spurs.
2. **Committed multiseg goldens predate the RTL "overlap-save fix"**: the
   goldens match the legacy framing (segment 0 = 896 samples + 128 zeros);
   the current RTL fills the full 1024-sample buffer. `mf_multi_segment`
   implements both (`framing="legacy"|"rtl"`); the goldens should be
   regenerated from the fixed RTL at some point.
3. **Per-segment pulse compression limits resolution**: segments are
   matched-filtered independently against 1/4 of the chirp (â‰ˆ6.8 MHz of the
   20 MHz), so the compressed peak is ~15 samples wide (â‰ˆ22 m), not the
   7.5 m the full bandwidth would give, and a target reappears in each
   segment's output shifted by +128 bins/segment (window advance 896 vs
   reference advance 1024). Recombining segments coherently would recover
   the full-BW resolution.
4. **Forward FFTs have no stage scaling**: the 0.9-full-scale reference chirp
   saturates ~230/1024 bins of its own FFT, and moderate composite scenes
   saturate the signal FFT. Saturation clips I/Q per bin, corrupting phase â€”
   in the scenario sim this collapsed the compression of exactly the
   strongest scatterer until the `rx_gain_control` stage backed off
   (gain âˆ’4 â‡’ Ã·16). This is what the hybrid AGC must manage in hardware;
   the default `agc_target=200` still leaves distributed scenes saturating.
5. **Short-chirp collection window**: the matched filter collects only 50
   baseband samples per short chirp starting at TX, so sub-frame 1
   (Doppler bins 16-31) can only see targets within â‰ˆ50-75 m. Near-empty
   sub-frame-1 columns also produce CFAR false alarms at the top range bins
   (tiny noise estimates). 
6. **CFAR default `alpha=0x30`** means threshold = 3.0 Ã— the *sum* of the 16
   training cells â‰ˆ 48Ã— the cell mean â€” no detections at realistic levels;
   `0x08` (8Ã— mean) behaves sensibly.
7. **DC ridge in Doppler bins 0-2**: the ADC offset convention
   `(adc<<9) - 0xFF00` leaves a half-LSB DC bias (mid-scale 128 maps to
   +256), which after the DDC shows up as an elevated near-DC Doppler
   column. The host-side DC removal / `dc_notch` / MTI all mitigate it.
8. **As-built decimator framing**: the RTL streams all 4 long-chirp segments
   into the range-bin decimator (4Ã—64 bins per chirp), while the Doppler
   corner-turn counts each 64-bin group as one chirp. The end-to-end sim
   uses the segment-0 block per chirp (the framing the golden vectors
   validate); the RTL integration should gate which segment feeds Doppler.

## End-to-end scenario results (aeris_endtoend_sim.m)

Scene: T1 40 m/âˆ’8 m/s/âˆ’20 dBsm, T2 440 m/+16 m/s/+10 dBsm,
T3 900 m/âˆ’21.4 m/s/+26 dBsm, stationary clutter 250 m/+12 dBsm,
Ïƒ_noise = 2 LSB, gain âˆ’4, CFAR Î±=0x08.

- MTI off: clutter detected at 246 m/0.0 m/s (âˆ’4 m), T1 and T3 detected;
  T2 masked by the clutter's Doppler-adjacent leakage.
- MTI on: clutter fully suppressed, **T2 revealed at 438 m/+16.0 m/s
  (âˆ’2 m, 0.0 m/s error)**; T1, T3 still detected.
- Range errors â‰¤ 10 m (within the 24 m decimated bin), bin-centred
  velocity errors 0.0 m/s.

Plots: ADC/IF spectrum, DDC baseband, MF range profile, range-Doppler maps
(MTI off/on) with truth + CFAR overlays, CFAR threshold cut.

## Conventions

- Velocity sign: the compressing IF convention conjugates the baseband, so
  measured Doppler = âˆ’physical; the sim reports physically-signed velocity
  (calibrated automatically, see `chirp_sign` in the report).
- Zero-range offset: DDC + MF group delay â‰ˆ 20 fast-time bins (30 m),
  measured by the built-in calibration run and removed from reported ranges.
