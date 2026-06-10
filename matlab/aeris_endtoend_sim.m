function out = aeris_endtoend_sim()
%AERIS_ENDTOEND_SIM Complete AERIS-10 radar simulation through the
%   bit-true FPGA pipeline (Simulation Plan phase 3.3 / 5).
%
%   Scene (IF echoes -> 8-bit 400 MSPS ADC)  ->  bit-true FPGA model:
%     NCO/mixer -> CIC x4 -> FIR -> 16-bit | multi-segment matched filter
%     -> range-bin decimation (peak) -> [MTI] -> dual 16-pt Doppler FFT
%     -> [DC notch] -> CA-CFAR
%   for a full 32-chirp staggered-PRI frame (16 long + 16 short).
%
%   Everything downstream of the ADC is the same arithmetic that was
%   validated bit-exactly by validate_against_golden.m.
%
%   Outputs plots and a detection report to
%   generated/matlab_endtoend/.

t_start = tic;
p    = aeris_params();
refs = aeris.load_chirp_refs(p);
rom1024 = aeris.load_twiddle_rom(p.twiddle_1024_file);
rom16   = aeris.load_twiddle_rom(p.twiddle_16_file);
outdir = fullfile(p.gen_dir, 'matlab_endtoend');
if ~exist(outdir, 'dir'), mkdir(outdir); end
rng(42, 'twister');

LEAD_ADC = 512;                     % warm-up samples before TX start
N_BB_LONG  = 3072;                  % baseband samples to collect (>=3000)
N_ADC_LONG = LEAD_ADC + 4*(N_BB_LONG + 64);
N_BB_SHORT = 128;
N_ADC_SHORT= LEAD_ADC + 4*(N_BB_SHORT + 64);

% ---------------------------------------------------------------------
% Scenario: AERIS-10N-style targets (ranges within segment-0 coverage)
% ---------------------------------------------------------------------
targets = struct( ...                     % amplitudes kept inside 8-bit ADC range
    'range_m',      {40,   440,   900}, ...
    'velocity_mps', {-8,   16,  -21.4}, ...
    'rcs_dbsm',     {-20,  10,    26}, ...
    'phase_deg',    {20,    0,   135});
clutter = struct( ...                     % stationary scatterer (MTI demo)
    'range_m',      {250}, ...
    'velocity_mps', {0}, ...
    'rcs_dbsm',     {12}, ...
    'phase_deg',    {60});
noise_std = 2.0;
alpha_tuned = hex2dec('08');              % Q4.4 = 0.5 -> threshold = 8x cell mean
% Digital gain (rx_gain_control.v, the stage the hybrid AGC drives).
% -4 = attenuate by 16: keeps the un-scaled 1024-pt forward FFT fully
% linear for this scene.  Without it ~5% of signal-FFT bins saturate;
% the per-bin I/Q clipping corrupts phase and collapses the compression
% of exactly the strongest scatterers (see endtoend_report.txt notes).
gc_shift = -4;

fprintf('=== AERIS-10 end-to-end bit-true simulation ===\n');
fprintf('Targets:\n');
for k = 1:numel(targets)
    fprintf('  T%d: R=%4.0f m  v=%+3.0f m/s  RCS=%+3.0f dBsm\n', k, ...
        targets(k).range_m, targets(k).velocity_mps, targets(k).rcs_dbsm);
end
fprintf('Clutter: R=%.0f m (stationary, %.0f dBsm)\n', clutter(1).range_m, clutter(1).rcs_dbsm);

% ---------------------------------------------------------------------
% Calibration: IF chirp sign + zero-range offset, from one noiseless run
% ---------------------------------------------------------------------
cal_tgt = struct('range_m', 300, 'velocity_mps', 0, 'rcs_dbsm', 10, 'phase_deg', 0);
best = struct('peak', -1, 'sign', -1, 'bin', NaN);
for sgn = [-1, 1]
    rng(1);
    adc = aeris.scene_generate_adc(cal_tgt, N_ADC_LONG, p, chirp="long", ...
        noise_std=0, chirp_sign=sgn, tx_start_samp=LEAD_ADC);
    bb = run_ddc_collect(adc, LEAD_ADC, N_BB_LONG, p, gc_shift);
    r = aeris.mf_multi_segment(bb.i, bb.q, refs, true, rom1024, framing="rtl");
    mag0 = abs(r.seg_re(1,:)) + abs(r.seg_im(1,:));
    [pk, bin] = max(mag0);
    if pk > best.peak, best = struct('peak', pk, 'sign', sgn, 'bin', bin); end
end
expected_bin = cal_tgt.range_m / p.range_per_bin;             % 200
cal_offset = (best.bin - 1) - expected_bin;                   % fast-time bins
fprintf(['Calibration: IF chirp sign %+d compresses (peak %d); ', ...
         'zero-range offset = %.0f bins (%.1f m)\n'], ...
        best.sign, best.peak, cal_offset, cal_offset * p.range_per_bin);
chirp_sign = best.sign;

% ---------------------------------------------------------------------
% Frame simulation: 16 long-PRI chirps + 16 short-PRI chirps
% ---------------------------------------------------------------------
rng(42, 'twister');
frame_dec_i = zeros(p.chirps_per_frame, p.range_bins);
frame_dec_q = zeros(p.chirps_per_frame, p.range_bins);
profile_long = zeros(p.chirps_per_subframe, 4*1024);   % full 4-segment profiles
bb0 = [];  adc0 = [];

for c = 0:p.chirps_per_frame-1
    if c < p.chirps_per_subframe
        slow_t = c * p.t_pri_long;
        chirp_type = "long";  n_adc = N_ADC_LONG;  n_bb = N_BB_LONG;
    else
        slow_t = p.chirps_per_subframe * p.t_pri_long + p.t_guard ...
               + (c - p.chirps_per_subframe) * p.t_pri_short;
        chirp_type = "short"; n_adc = N_ADC_SHORT; n_bb = N_BB_SHORT;
    end

    adc = aeris.scene_generate_adc(targets, n_adc, p, chirp=chirp_type, ...
        slow_time_s=slow_t, noise_std=noise_std, chirp_sign=chirp_sign, ...
        clutter=clutter, tx_start_samp=LEAD_ADC);
    bb = run_ddc_collect(adc, LEAD_ADC, n_bb, p, gc_shift);

    r = aeris.mf_multi_segment(bb.i, bb.q, refs, chirp_type == "long", ...
                               rom1024, framing="rtl");
    % Per-chirp range row for the Doppler frame: the first 1024-bin block
    % the decimator sees (segment 0).  NOTE: the as-built RTL streams all
    % 4 long-chirp segments into the decimator (4 x 64 bins per chirp);
    % see README "framing" discussion.
    [frame_dec_i(c+1,:), frame_dec_q(c+1,:)] = ...
        aeris.range_bin_decimator(r.seg_re(1,:), r.seg_im(1,:), 1, 0);

    if chirp_type == "long"
        prof = zeros(1, 4*1024);
        for s = 1:4
            prof((s-1)*1024 + (1:1024)) = abs(r.seg_re(s,:)) + abs(r.seg_im(s,:));
        end
        profile_long(c+1, :) = prof;
    end
    if c == 0, bb0 = bb; adc0 = adc; end
    if mod(c+1, 8) == 0, fprintf('  processed chirp %2d/%d\n', c+1, p.chirps_per_frame); end
end

% ---------------------------------------------------------------------
% Doppler -> DC notch -> CFAR  (with and without MTI)
% ---------------------------------------------------------------------
[map_i, map_q] = aeris.doppler_process(frame_dec_i, frame_dec_q, p, rom16);
[mti_i, mti_q] = aeris.mti_canceller(frame_dec_i, frame_dec_q, true);
[mmap_i, mmap_q] = aeris.doppler_process(mti_i, mti_q, p, rom16);

% Default host configuration (alpha = 0x30 -> threshold = 3.0 * SUM of the
% training cells, i.e. ~48x the cell mean â€” very conservative) plus a
% tuned setting alpha = 0x0C (0.75 * sum = 12x cell mean).
[flags0, mags,  ~    ] = aeris.cfar_ca(map_i,  map_q,  p.cfar_guard, p.cfar_train, p.cfar_alpha, p.cfar_mode);
[flags,  ~,     thrs ] = aeris.cfar_ca(map_i,  map_q,  p.cfar_guard, p.cfar_train, alpha_tuned, p.cfar_mode);
[mflags, mmags, ~    ] = aeris.cfar_ca(mmap_i, mmap_q, p.cfar_guard, p.cfar_train, alpha_tuned, p.cfar_mode);

% ---------------------------------------------------------------------
% Detection clustering + truth association
% ---------------------------------------------------------------------
fprintf('\nCFAR, default alpha=0x30 (3.0*sum = 48x mean): %d raw cells\n', sum(flags0(:)));
det = summarize_detections(flags, mags, p, cal_offset, chirp_sign);
fprintf('CFAR tuned alpha=0x08 (0.5*sum = 8x mean), no MTI: %d raw cells -> %d clusters\n', ...
        sum(flags(:)), numel(det));
print_detections(det, targets, clutter, p);

det_mti = summarize_detections(mflags, mmags, p, cal_offset, chirp_sign);
fprintf('CFAR tuned, MTI on: %d raw cells -> %d clusters\n', ...
        sum(mflags(:)), numel(det_mti));
print_detections(det_mti, targets, clutter, p);

% ---------------------------------------------------------------------
% Plots
% ---------------------------------------------------------------------
range_axis_dec = ((0:p.range_bins-1)*16 + 8 - cal_offset) * p.range_per_bin;
vel_axis = chirp_sign * doppler_velocity_axis(p);   % physical sign convention

f = figure('Visible', fig_vis(), 'Position', [50 50 1100 700]);
tiledlayout(f, 2, 1);
nexttile;
tt = (0:2999)/p.fs_adc*1e6;
plot(tt, adc0(1:3000)); grid on;
xlabel('time [\mus]'); ylabel('ADC code');
title('Chirp 0: 8-bit ADC samples (400 MSPS, IF = 120 MHz)');
nexttile;
nfft = 2^floor(log2(numel(adc0)));
w = 0.5 - 0.5*cos(2*pi*(0:nfft-1)/(nfft-1));
spec = 20*log10(abs(fft((adc0(1:nfft)-128) .* w, nfft)) + 1);
fax = (0:nfft-1)/nfft*p.fs_adc/1e6;
plot(fax(1:nfft/2), spec(1:nfft/2)); grid on; xlim([0 200]);
xlabel('frequency [MHz]'); ylabel('|X| [dB]');
title('ADC spectrum: chirp around 120 MHz IF');
exportgraphics(f, fullfile(outdir, '01_adc_if_signal.png'), 'Resolution', 130);

f = figure('Visible', fig_vis(), 'Position', [50 50 1100 500]);
plot(bb0.i(1:1200)); hold on; plot(bb0.q(1:1200)); grid on;
legend('I', 'Q'); xlabel('baseband sample (100 MSPS)'); ylabel('amplitude (16-bit)');
title('Chirp 0: DDC output (bit-true NCO \rightarrow mixer \rightarrow CIC \rightarrow FIR \rightarrow 16-bit)');
exportgraphics(f, fullfile(outdir, '02_ddc_baseband.png'), 'Resolution', 130);

f = figure('Visible', fig_vis(), 'Position', [50 50 1100 540]);
prof = mean(profile_long, 1);
seg_bin_range = ((0:4*1024-1) - cal_offset);
semilogy(seg_bin_range(1:1024) * p.range_per_bin, prof(1:1024) + 1, 'LineWidth', 1.0); hold on;
semilogy(seg_bin_range(1025:end) * p.range_per_bin, prof(1025:end) + 1, ':');
for k = 1:numel(targets)
    xline(targets(k).range_m, 'r--', sprintf('T%d', k));
end
xline(clutter(1).range_m, 'm--', 'clutter');
grid on; xlim([-50, 1600]);
xlabel('range [m] (segment-0 axis)'); ylabel('|I|+|Q| (mean over 16 long chirps)');
title('Matched-filter range profile â€” segment 0 solid, segments 1-3 dotted (own ambiguity axes)');
exportgraphics(f, fullfile(outdir, '03_range_profile.png'), 'Resolution', 130);

plot_rd_map(map_i, map_q, flags, range_axis_dec, vel_axis, targets, clutter, ...
    'Range-Doppler map (MTI off) + CFAR detections', ...
    fullfile(outdir, '04_range_doppler_no_mti.png'), p);
plot_rd_map(mmap_i, mmap_q, mflags, range_axis_dec, vel_axis, targets, clutter, ...
    'Range-Doppler map (MTI on) â€” stationary clutter suppressed', ...
    fullfile(outdir, '05_range_doppler_mti.png'), p);

% CFAR threshold cut through the strongest detection column
[~, peak_lin] = max(mags(:) .* flags(:));
[~, pk_d] = ind2sub(size(mags), peak_lin);
f = figure('Visible', fig_vis(), 'Position', [50 50 1100 480]);
semilogy(range_axis_dec, mags(:, pk_d) + 1, '-o', 'MarkerSize', 3); hold on;
semilogy(range_axis_dec, thrs(:, pk_d) + 1, 'r-', 'LineWidth', 1.2);
grid on; legend('cell magnitude |I|+|Q|', 'CA-CFAR threshold');
xlabel('range [m]'); ylabel('magnitude');
title(sprintf('CFAR cut along Doppler bin %d (guard=%d, train=%d, tuned \\alpha=%.2f)', ...
      pk_d-1, p.cfar_guard, p.cfar_train, alpha_tuned/16));
exportgraphics(f, fullfile(outdir, '06_cfar_threshold_cut.png'), 'Resolution', 130);

% ---------------------------------------------------------------------
% Save results + report
% ---------------------------------------------------------------------
save(fullfile(outdir, 'endtoend_results.mat'), 'p', 'targets', 'clutter', ...
     'frame_dec_i', 'frame_dec_q', 'map_i', 'map_q', 'mmap_i', 'mmap_q', ...
     'flags0', 'flags', 'mflags', 'mags', 'mmags', 'thrs', 'det', 'det_mti', ...
     'cal_offset', 'chirp_sign', 'alpha_tuned', 'range_axis_dec', 'vel_axis');

fid = fopen(fullfile(outdir, 'endtoend_report.txt'), 'w');
fprintf(fid, 'AERIS-10 end-to-end bit-true simulation report\n');
fprintf(fid, 'Generated by aeris_endtoend_sim.m\n\n');
fprintf(fid, 'Chain: scene -> 8-bit ADC @400MSPS -> NCO/mixer -> CIC4 -> FIR32 -> 16-bit\n');
fprintf(fid, '       -> multi-segment matched filter (1024-pt FFT, RTL framing)\n');
fprintf(fid, '       -> range decimation (peak,16:1) -> [MTI] -> dual 16-pt Doppler\n');
fprintf(fid, '       -> CA-CFAR (guard=%d, train=%d)\n\n', p.cfar_guard, p.cfar_train);
fprintf(fid, ['CFAR alpha: host default 0x30 (threshold = 3.0*sum of %d training\n' ...
              'cells = ~48x cell mean) yields no detections at these target levels;\n' ...
              'detections below use tuned alpha 0x08 (0.5*sum = 8x cell mean).\n\n'], ...
              2*p.cfar_train);
fprintf(fid, 'IF chirp sign: %+d (auto-calibrated)\n', chirp_sign);
fprintf(fid, 'Zero-range offset: %.0f fast-time bins (%.1f m, DDC+MF group delay)\n\n', ...
        cal_offset, cal_offset*p.range_per_bin);
fprintf(fid, 'Targets (truth):\n');
for k = 1:numel(targets)
    fprintf(fid, '  T%d: R=%6.1f m  v=%+5.1f m/s  RCS=%+4.0f dBsm\n', k, ...
        targets(k).range_m, targets(k).velocity_mps, targets(k).rcs_dbsm);
end
fprintf(fid, '  C1: R=%6.1f m  v=  0.0 m/s  RCS=%+4.0f dBsm (clutter)\n\n', ...
        clutter(1).range_m, clutter(1).rcs_dbsm);
fprintf(fid, 'Detections, MTI off (%d clusters):\n', numel(det));
write_det(fid, det);
fprintf(fid, '\nDetections, MTI on (%d clusters):\n', numel(det_mti));
write_det(fid, det_mti);
fprintf(fid, '\nNotes:\n');
fprintf(fid, ' - Sub-frame 1 (Doppler bins 16-31) is fed by the short chirps; the RTL\n');
fprintf(fid, '   collects only %d baseband samples per short chirp, so only targets\n', p.short_chirp_samples);
fprintf(fid, '   within ~%.0f m can appear there (T1 at %.0f m does).\n', ...
        p.short_chirp_samples * p.range_per_bin, targets(1).range_m);
fprintf(fid, ' - The as-built RTL streams all 4 long-chirp MF segments into the range\n');
fprintf(fid, '   decimator (4x64 bins per chirp); this frame uses the segment-0 block\n');
fprintf(fid, '   per chirp, the framing the repo golden vectors validate.\n');
fclose(fid);

out = struct('det', det, 'det_mti', det_mti, 'cal_offset', cal_offset, ...
             'chirp_sign', chirp_sign, 'map_i', map_i, 'map_q', map_q);
fprintf('\nDone in %.1f s. Plots + report in %s\n', toc(t_start), outdir);
end

% =====================================================================
function bb = run_ddc_collect(adc, lead_adc, n_bb, p, gc_shift)
% DDC the ADC stream, apply the digital gain stage, and return the
% collection window starting at TX start.
d = aeris.ddc_chain(adc, p);
i0 = lead_adc / 4;                          % baseband index of TX start
bb.i = aeris.rx_gain_control(d.bb_i(i0 + 1 : min(end, i0 + n_bb)), gc_shift);
bb.q = aeris.rx_gain_control(d.bb_q(i0 + 1 : min(end, i0 + n_bb)), gc_shift);
end

function vel = doppler_velocity_axis(p)
% Velocity for sub-frame-0 Doppler bins 0..15 (long PRI), FFT-wrapped.
d = 0:15;
d_signed = d - 16*(d >= 8);
fd = d_signed / (16 * p.t_pri_long);
vel = fd * p.lambda / 2;
end

function det = summarize_detections(flags, mags, p, cal_offset, chirp_sign)
% Cluster CFAR hits (per sub-frame, 8-connected) and convert to physical units.
% The reported velocity applies the IF sign convention: with the compressing
% chirp sign the DDC conjugates the echo, so measured Doppler = -physical.
det = struct('range_m', {}, 'vel_mps', {}, 'subframe', {}, 'mag', {}, ...
             'rbin', {}, 'dbin', {});
for sf = 0:1
    sub = flags(:, sf*16 + (1:16));
    submag = mags(:, sf*16 + (1:16));
    cc = bwconncomp_simple(sub);
    for k = 1:numel(cc)
        cells = cc{k};
        [~, im] = max(submag(cells));
        [rb, db] = ind2sub(size(sub), cells(im));
        rng_m = ((rb-1)*16 + 8 - cal_offset) * p.range_per_bin;
        db0 = db - 1;
        db_signed = db0 - 16*(db0 >= 8);
        pri = p.t_pri_long;  if sf == 1, pri = p.t_pri_short; end
        vel = chirp_sign * db_signed / (16 * pri) * p.lambda / 2;
        det(end+1) = struct('range_m', rng_m, 'vel_mps', vel, 'subframe', sf, ...
            'mag', submag(cells(im)), 'rbin', rb-1, 'dbin', sf*16 + db0); %#ok<AGROW>
    end
end
end

function cc = bwconncomp_simple(mask)
% Minimal 8-connected component labelling (avoids toolbox dependency).
cc = {};
visited = false(size(mask));
[nr, nc] = size(mask);
for idx = find(mask(:)).'
    if visited(idx), continue; end
    stack = idx;  comp = [];
    visited(idx) = true;
    while ~isempty(stack)
        cur = stack(end);  stack(end) = [];
        comp(end+1) = cur; %#ok<AGROW>
        [r, c] = ind2sub([nr nc], cur);
        for dr = -1:1
            for dc2 = -1:1
                rr = r + dr;  cc2 = c + dc2;
                if rr >= 1 && rr <= nr && cc2 >= 1 && cc2 <= nc
                    j = sub2ind([nr nc], rr, cc2);
                    if mask(j) && ~visited(j)
                        visited(j) = true;
                        stack(end+1) = j; %#ok<AGROW>
                    end
                end
            end
        end
    end
    cc{end+1} = comp; %#ok<AGROW>
end
end

function print_detections(det, targets, clutter, ~)
truth_r = [ [targets.range_m], clutter.range_m ];
truth_v = [ [targets.velocity_mps], 0 ];
names = [arrayfun(@(k) sprintf("T%d", k), 1:numel(targets)), "C1"];
for k = 1:numel(det)
    [err, j] = min(abs(det(k).range_m - truth_r));
    assoc = "?";
    if err < 50, assoc = names(j); end
    fprintf(['   det %d: R=%6.1f m  v=%+6.1f m/s  (sub-frame %d, mag %6.0f)', ...
             '  -> %s'], k, det(k).range_m, det(k).vel_mps, det(k).subframe, ...
             det(k).mag, assoc);
    if assoc ~= "?"
        fprintf('  [dR=%+5.1f m, dv=%+5.1f m/s]', det(k).range_m - truth_r(j), ...
                det(k).vel_mps - truth_v(j));
    end
    fprintf('\n');
end
end

function write_det(fid, det)
for k = 1:numel(det)
    fprintf(fid, '  R=%7.1f m  v=%+6.1f m/s  sub-frame %d  rbin %2d  dbin %2d  mag %7.0f\n', ...
        det(k).range_m, det(k).vel_mps, det(k).subframe, det(k).rbin, det(k).dbin, det(k).mag);
end
end

function vis = fig_vis()
% Figures on screen when MATLAB runs interactively, hidden in -batch mode.
if batchStartupOptionUsed
    vis = 'off';
else
    vis = 'on';
end
end

function plot_rd_map(mi, mq, flags, range_axis, vel_axis, targets, clutter, ttl, fname, p)
f = figure('Visible', fig_vis(), 'Position', [50 50 1150 620]);
tiledlayout(f, 1, 2, 'TileSpacing', 'compact');
mag_db = 20*log10(abs(mi) + abs(mq) + 1);
for sf = 0:1
    nexttile;
    cols = sf*16 + (1:16);
    [~, order] = sort(vel_axis);
    imagesc(vel_axis(order), range_axis, mag_db(:, cols(order)));
    axis xy; colormap(jet); colorbar;
    hold on;
    sub = flags(:, cols);
    [rr, dd] = find(sub(:, order));
    plot(vel_axis(order(dd)), range_axis(rr), 'ws', 'MarkerSize', 10, 'LineWidth', 1.4);
    for k = 1:numel(targets)
        plot(targets(k).velocity_mps, targets(k).range_m, 'k+', 'MarkerSize', 12, 'LineWidth', 1.6);
    end
    plot(0, clutter(1).range_m, 'kx', 'MarkerSize', 12, 'LineWidth', 1.6);
    xlabel('velocity [m/s]'); ylabel('range [m]');
    if sf == 0
        title(sprintf('sub-frame 0 (long PRI %.0f \\mus)', p.t_pri_long*1e6));
    else
        title(sprintf('sub-frame 1 (short PRI %.0f \\mus, %d-sample window)', ...
              p.t_pri_short*1e6, p.short_chirp_samples));
    end
    ylim([0 1600]);
end
sgtitle(sprintf('%s   (+ = truth, x = clutter, square = CFAR)', ttl), ...
        'Interpreter', 'none');
exportgraphics(f, fname, 'Resolution', 130);
end
