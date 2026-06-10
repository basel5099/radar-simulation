# Upstream provenance

This project is a MATLAB bit-true simulation of the FPGA signal-processing
pipeline of the open-source **AERIS-10** radar:

- Upstream repository: <https://github.com/NawfalMotii79/PLFM_RADAR>
- Upstream version referenced: **`main` @ `caac68a1df`** (2026-05-29), the
  upstream HEAD at the time this project was built.
- The model was developed and validated against a local snapshot of the
  upstream project retrieved between April and June 2026. The data files
  vendored here (chirp tables, twiddle ROMs, golden detection vectors)
  were verified **byte-identical** to upstream `caac68a1df`. A few RTL /
  cosim source files in that snapshot carry minor differences from
  upstream HEAD; the vendored copies are exactly the files the 25/25
  bit-exact validation was performed against, so this repository is
  self-contained and reproducible regardless of upstream changes.

## What is vendored, and why

Everything under `reference/fpga/` keeps the directory structure of the
upstream `9_Firmware/9_2_FPGA/` folder:

| Files | Purpose here |
|---|---|
| `long_chirp_seg0..3_{i,q}.mem`, `short_chirp_{i,q}.mem`, `long_chirp_lut.mem` | the exact chirp tables the FPGA uses — the matched-filter reference and TX waveform |
| `fft_twiddle_1024.mem`, `fft_twiddle_16.mem` | FFT twiddle ROMs (quarter-wave Q15) |
| 21 Verilog source files (`*.v`) | shown in the explorer's "FPGA source" tab next to each MATLAB model |
| `tb/*.csv` | raw Icarus RTL simulation dumps (NCO / CIC / FIR) used as bit-exact validation targets |
| `tb/cosim/*` | golden vectors of the upstream co-simulation suite (matched filter, multi-segment, Doppler) |
| `tb/cosim/real_data/hex/*` | full-chain golden vectors (decimator → MTI → Doppler → DC notch → CFAR) from a real ADI CN0566 radar capture |

## Licenses

- The upstream project licenses its **software and FPGA code under MIT**
  (hardware design files, which are *not* included here, are CERN-OHL-P).
  All vendored files in `reference/fpga/` are FPGA code or test data and
  are therefore redistributed under the upstream MIT license,
  copyright the AERIS-10 / PLFM_RADAR authors.
- The MATLAB simulation suite (`matlab/`) is original work in this
  repository, MIT-licensed (see `LICENSE`).
