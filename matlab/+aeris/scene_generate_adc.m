function adc = scene_generate_adc(targets, n_samples, p, opts)
%SCENE_GENERATE_ADC Synthesize 8-bit ADC samples for a radar scene.
%   adc = SCENE_GENERATE_ADC(targets, n_samples, p, ...) models the RF path
%   the way the cosim scene generator (tb/cosim/radar_scene.py) does:
%   each target produces a delayed, attenuated copy of the TX chirp at the
%   120 MHz IF, plus AWGN, quantized to 8-bit unsigned centred at 128.
%
%   targets: struct array with fields
%     .range_m, .velocity_mps, .rcs_dbsm, .phase_deg
%   opts:
%     .chirp        "long" (default) or "short"
%     .slow_time_s  slow-time offset of this pulse (Doppler phase evolution)
%     .tx_start_samp ADC sample index at which the TX chirp starts (lead-in)
%     .noise_std    AWGN sigma in ADC LSB (default 2.0)
%     .chirp_sign   +1: up-chirp at IF (radar_scene.py convention)
%                   -1: down-chirp at IF (yields ref-matched baseband after
%                       the I=x*cos / Q=x*sin DDC; see README)
%     .clutter      struct array like targets (zero-velocity scatterers)
%
%   Amplitude model (radar_scene.py Target.amplitude):
%     amp = sqrt(10^(rcs/10)) / R^2 * 100^2 * 64   [ADC LSB]
arguments
    targets struct
    n_samples (1,1) double
    p struct
    opts.chirp (1,1) string = "long"
    opts.slow_time_s (1,1) double = 0
    opts.tx_start_samp (1,1) double = 0
    opts.noise_std (1,1) double = 2.0
    opts.chirp_sign (1,1) double = -1
    opts.clutter struct = struct([])
end
if opts.chirp == "long"
    chirp_rate = p.chirp_rate_long;
    n_chirp = round(p.t_long_chirp * p.fs_adc);     % 12000 @ 400 MSPS
else
    chirp_rate = p.chirp_rate_short;
    n_chirp = round(p.t_short_chirp * p.fs_adc);    % 200 @ 400 MSPS
end

t = (0:n_samples-1) / p.fs_adc;
x = zeros(1, n_samples);
all_t = targets(:);
if ~isempty(opts.clutter)
    all_t = [all_t; opts.clutter(:)];
end

for k = 1:numel(all_t)
    tg = all_t(k);
    delay_s    = 2 * tg.range_m / p.c;
    delay_samp = delay_s * p.fs_adc;
    doppler_hz = 2 * tg.velocity_mps * p.f_carrier / p.c;
    amp = sqrt(10^(tg.rcs_dbsm/10)) / tg.range_m^2 * 100^2 * 64;
    phase0 = tg.phase_deg * pi/180;

    nd = (0:n_samples-1) - opts.tx_start_samp - delay_samp;
    mask = (nd >= 0) & (nd < n_chirp);
    td = nd / p.fs_adc;
    ph = 2*pi*p.f_if*t ...
       + opts.chirp_sign * pi * chirp_rate * td.^2 ...
       + 2*pi*doppler_hz .* (t + opts.slow_time_s) ...
       + phase0;
    x = x + amp * (cos(ph) .* mask);
end

x = x + opts.noise_std * randn(1, n_samples);
adc = min(max(round(x + 128), 0), 255);
end
