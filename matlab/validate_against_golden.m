function results = validate_against_golden()
%VALIDATE_AGAINST_GOLDEN Check the MATLAB bit-true model against the
%   vendored golden vectors in reference/fpga/tb.
%
%   Pass/fail targets are the artifacts whose provenance is bit-true:
%     - tb/cosim python-model goldens (fpga_model.py), which the repo's
%       Icarus regression compares 1:1 against RTL (compare_mf_*.csv show
%       zero diff), and
%     - raw RTL block dumps (tb/nco_*, cic_*, fir_* CSVs).
%
%   Deliberately EXCLUDED (informational only):
%     - tb/mf_golden_*_case1-4: floating-point reference quantized at the
%       end (gen_mf_golden_ref.py), not bit-true fixed point.
%     - tb/cosim/compare_<scenario>.csv full-DDC dumps: their own py and
%       rtl columns disagree (stale artifacts from a pre-fix chain).
%     - multiseg goldens vs the *current* RTL framing: the committed
%       goldens encode the pre-"overlap-save fix" framing; the model
%       reproduces both (framing="legacy" matches the goldens exactly).
%
%   Writes generated/matlab_validation/validation_report.txt.

p = aeris_params();
rom1024 = aeris.load_twiddle_rom(p.twiddle_1024_file);
rom16   = aeris.load_twiddle_rom(p.twiddle_16_file);
results = struct('name', {}, 'pass', {}, 'detail', {});
info    = strings(0, 1);

    function add(name, pass, detail)
        results(end+1) = struct('name', name, 'pass', pass, 'detail', detail); %#ok<AGROW>
        fprintf('  [%s] %-46s %s\n', tern(pass, 'PASS', 'FAIL'), name, detail);
    end
    function note(msg)
        info(end+1) = msg; %#ok<AGROW>
        fprintf('  [info] %s\n', msg);
    end

fprintf('=== AERIS-10 MATLAB bit-true model vs repo golden vectors ===\n');

% =====================================================================
% 1. Matched filter core (FFT -> conj multiply -> IFFT), cosim goldens
% =====================================================================
for c = ["dc", "impulse", "tone5"]
    sig_i = aeris.read_mem_hex(fullfile(p.cosim_dir, sprintf('mf_sig_%s_i.hex', c)), 16);
    sig_q = aeris.read_mem_hex(fullfile(p.cosim_dir, sprintf('mf_sig_%s_q.hex', c)), 16);
    ref_i = aeris.read_mem_hex(fullfile(p.cosim_dir, sprintf('mf_ref_%s_i.hex', c)), 16);
    ref_q = aeris.read_mem_hex(fullfile(p.cosim_dir, sprintf('mf_ref_%s_q.hex', c)), 16);
    gld_i = aeris.read_mem_hex(fullfile(p.cosim_dir, sprintf('mf_golden_py_i_%s.hex', c)), 16);
    gld_q = aeris.read_mem_hex(fullfile(p.cosim_dir, sprintf('mf_golden_py_q_%s.hex', c)), 16);
    [pc_re, pc_im] = aeris.matched_filter_1024(sig_i, sig_q, ref_i, ref_q, rom1024);
    nerr = sum(pc_re(:) ~= gld_i(:)) + sum(pc_im(:) ~= gld_q(:));
    add(sprintf('MF core "%s"', c), nerr == 0, sprintf('%d/2048 samples differ', nerr));
end
sig_i = aeris.read_mem_hex(fullfile(p.cosim_dir, 'bb_mf_test_i.hex'), 16);
sig_q = aeris.read_mem_hex(fullfile(p.cosim_dir, 'bb_mf_test_q.hex'), 16);
ref_i = aeris.read_mem_hex(fullfile(p.cosim_dir, 'ref_chirp_i.hex'), 16);
ref_q = aeris.read_mem_hex(fullfile(p.cosim_dir, 'ref_chirp_q.hex'), 16);
gld_i = aeris.read_mem_hex(fullfile(p.cosim_dir, 'mf_golden_py_i_chirp.hex'), 16);
gld_q = aeris.read_mem_hex(fullfile(p.cosim_dir, 'mf_golden_py_q_chirp.hex'), 16);
[pc_re, pc_im] = aeris.matched_filter_1024(sig_i, sig_q, ref_i, ref_q, rom1024);
nerr = sum(pc_re(:) ~= gld_i(:)) + sum(pc_im(:) ~= gld_q(:));
add('MF core "chirp" (2-target baseband)', nerr == 0, sprintf('%d/2048 samples differ', nerr));

% =====================================================================
% 2. Multi-segment matched filter wrapper
% =====================================================================
in_i = aeris.read_mem_hex(fullfile(p.cosim_dir, 'multiseg_input_i.hex'), 18);
in_q = aeris.read_mem_hex(fullfile(p.cosim_dir, 'multiseg_input_q.hex'), 18);
refs_ms.long_i = zeros(4, 1024);  refs_ms.long_q = zeros(4, 1024);
gld_ms_i = zeros(4, 1024);        gld_ms_q = zeros(4, 1024);
for s = 0:3
    refs_ms.long_i(s+1,:) = aeris.read_mem_hex(fullfile(p.cosim_dir, sprintf('multiseg_ref_seg%d_i.hex', s)), 16).';
    refs_ms.long_q(s+1,:) = aeris.read_mem_hex(fullfile(p.cosim_dir, sprintf('multiseg_ref_seg%d_q.hex', s)), 16).';
    gld_ms_i(s+1,:) = aeris.read_mem_hex(fullfile(p.cosim_dir, sprintf('multiseg_golden_seg%d_i.hex', s)), 16).';
    gld_ms_q(s+1,:) = aeris.read_mem_hex(fullfile(p.cosim_dir, sprintf('multiseg_golden_seg%d_q.hex', s)), 16).';
end
refs_ms.short_i = zeros(1, 1024);  refs_ms.short_q = zeros(1, 1024);
r = aeris.mf_multi_segment(in_i.', in_q.', refs_ms, true, rom1024, framing="legacy");
nerr = sum(r.seg_re(:) ~= gld_ms_i(:)) + sum(r.seg_im(:) ~= gld_ms_q(:));
add('Multi-segment long (golden framing)', nerr == 0, sprintf('%d/8192 samples differ', nerr));
r2 = aeris.mf_multi_segment(in_i.', in_q.', refs_ms, true, rom1024, framing="rtl");
note(sprintf(['multiseg goldens encode the pre-fix framing; current-RTL framing ', ...
    'differs in %d/8192 samples as expected'], ...
    sum(r2.seg_re(:) ~= gld_ms_i(:)) + sum(r2.seg_im(:) ~= gld_ms_q(:))));

in_i = aeris.read_mem_hex(fullfile(p.cosim_dir, 'multiseg_short_input_i.hex'), 18);
in_q = aeris.read_mem_hex(fullfile(p.cosim_dir, 'multiseg_short_input_q.hex'), 18);
refs_s.short_i = aeris.read_mem_hex(fullfile(p.cosim_dir, 'multiseg_short_ref_i.hex'), 16).';
refs_s.short_q = aeris.read_mem_hex(fullfile(p.cosim_dir, 'multiseg_short_ref_q.hex'), 16).';
gld_i = aeris.read_mem_hex(fullfile(p.cosim_dir, 'multiseg_short_golden_i.hex'), 16);
gld_q = aeris.read_mem_hex(fullfile(p.cosim_dir, 'multiseg_short_golden_q.hex'), 16);
r = aeris.mf_multi_segment(in_i.', in_q.', refs_s, false, rom1024);
nerr = sum(r.seg_re(:) ~= gld_i(:)) + sum(r.seg_im(:) ~= gld_q(:));
add('Multi-segment short (50 + zero-pad)', nerr == 0, sprintf('%d/2048 samples differ', nerr));

% =====================================================================
% 3. Doppler processor â€” three synthetic scenarios
% =====================================================================
for sc = ["stationary", "moving", "two_targets"]
    [di, dq] = aeris.read_packed_hex32(fullfile(p.cosim_dir, sprintf('doppler_input_%s.hex', sc)));
    frame_i = reshape(di, 64, 32).';
    frame_q = reshape(dq, 64, 32).';
    [mi, mq] = aeris.doppler_process(frame_i, frame_q, p, rom16);
    g = readmatrix(fullfile(p.cosim_dir, sprintf('doppler_golden_py_%s.csv', sc)));
    gi = reshape(g(:,3), 32, 64).';
    gq = reshape(g(:,4), 32, 64).';
    nerr = sum(mi(:) ~= gi(:)) + sum(mq(:) ~= gq(:));
    add(sprintf('Doppler "%s"', sc), nerr == 0, sprintf('%d/4096 samples differ', nerr));
end

% =====================================================================
% 4. Full chain on real radar data (ADI CN0566 capture):
%    decimate -> MTI -> Doppler -> DC notch -> CA-CFAR
% =====================================================================
[ri, rq] = aeris.read_packed_hex32(fullfile(p.realdata_dir, 'fullchain_range_input.hex'));
rfft_i = reshape(ri, 1024, 32).';
rfft_q = reshape(rq, 1024, 32).';
dec_i = zeros(32, 64);  dec_q = zeros(32, 64);
for c = 1:32
    [dec_i(c,:), dec_q(c,:)] = aeris.range_bin_decimator(rfft_i(c,:), rfft_q(c,:), 1, 0);
end
gd_i = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'decimated_range_i.hex'), 16), 64, 32).';
gd_q = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'decimated_range_q.hex'), 16), 64, 32).';
nerr = sum(dec_i(:) ~= gd_i(:)) + sum(dec_q(:) ~= gd_q(:));
add('Range-bin decimator (peak mode)', nerr == 0, sprintf('%d/4096 samples differ', nerr));

[dm_i, dm_q] = aeris.doppler_process(dec_i, dec_q, p, rom16);
gi = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_doppler_ref_i.hex'), 16), 32, 64).';
gq = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_doppler_ref_q.hex'), 16), 32, 64).';
nerr = sum(dm_i(:) ~= gi(:)) + sum(dm_q(:) ~= gq(:));
add('Doppler (real data, no MTI)', nerr == 0, sprintf('%d/4096 samples differ', nerr));

[mti_i, mti_q] = aeris.mti_canceller(dec_i, dec_q, true);
gi = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_mti_ref_i.hex'), 16), 64, 32).';
gq = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_mti_ref_q.hex'), 16), 64, 32).';
nerr = sum(mti_i(:) ~= gi(:)) + sum(mti_q(:) ~= gq(:));
add('MTI canceller', nerr == 0, sprintf('%d/4096 samples differ', nerr));

[md_i, md_q] = aeris.doppler_process(mti_i, mti_q, p, rom16);
gi = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_mti_doppler_ref_i.hex'), 16), 32, 64).';
gq = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_mti_doppler_ref_q.hex'), 16), 32, 64).';
nerr = sum(md_i(:) ~= gi(:)) + sum(md_q(:) ~= gq(:));
add('Doppler after MTI', nerr == 0, sprintf('%d/4096 samples differ', nerr));

[nt_i, nt_q] = aeris.dc_notch(md_i, md_q, 2);
gi = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_notched_ref_i.hex'), 16), 32, 64).';
gq = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_notched_ref_q.hex'), 16), 32, 64).';
nerr = sum(nt_i(:) ~= gi(:)) + sum(nt_q(:) ~= gq(:));
add('DC notch (width 2)', nerr == 0, sprintf('%d/4096 samples differ', nerr));

[flags, mags, thrs] = aeris.cfar_ca(nt_i, nt_q, 2, 8, hex2dec('30'), 'CA');
gm = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_cfar_mag.hex'), 17, false), 32, 64).';
gt = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_cfar_thr.hex'), 17, false), 32, 64).';
gf = reshape(aeris.read_mem_hex(fullfile(p.realdata_dir, 'fullchain_cfar_det.hex'), 1, false), 32, 64).';
add('CFAR magnitudes', isequal(mags, gm), sprintf('%d/2048 differ', sum(mags(:) ~= gm(:))));
add('CFAR thresholds', isequal(thrs, gt), sprintf('%d/2048 differ', sum(thrs(:) ~= gt(:))));
add('CFAR detection flags', isequal(flags, gf ~= 0), sprintf('%d/2048 differ', sum(flags(:) ~= (gf(:) ~= 0))));

det_txt = readlines(fullfile(p.realdata_dir, 'fullchain_cfar_detections.txt'));
det_txt = det_txt(~startsWith(strtrim(det_txt), '#') & strlength(strtrim(det_txt)) > 0);
gold_det = zeros(numel(det_txt), 4);
for k = 1:numel(det_txt)
    gold_det(k, :) = sscanf(det_txt(k), '%d %d %d %d').';
end
[rr, dd] = find(flags);
mine = sortrows([rr-1, dd-1, mags(flags), thrs(flags)], [2 1]);
gold = sortrows(gold_det, [2 1]);
ok = isequal(size(mine), size(gold)) && isequal(mine, gold);
add('CFAR detection list', ok, sprintf('%d detections (golden %d)', size(mine,1), size(gold,1)));

% =====================================================================
% 5. DDC blocks vs raw RTL simulation dumps (tb/*.csv)
% =====================================================================
% --- NCO, 1 MHz FTW (first test after reset; accumulator starts at 0) ---
nco = readmatrix(fullfile(p.tb_dir, 'nco_1mhz_output.csv'));
rdy = nco(:, 4) ~= 0;
ref_sin = nco(rdy, 2);  ref_cos = nco(rdy, 3);
[my_sin, my_cos] = aeris.nco_sincos(0:numel(ref_sin)+63, hex2dec('00A3D70A'), p.nco_lut);
[fs_, lag_s] = best_lag(my_sin, ref_sin, 0, 12);
[fc_, ~]     = best_lag(my_cos, ref_cos, 0, 12, lag_s);
add('NCO vs RTL dump (1 MHz)', fs_ == 1 && fc_ == 1, ...
    sprintf('match sin=%.4f cos=%.4f (lag %d)', fs_, fc_, lag_s));

% --- CIC: impulse 10000, DC 1000, passband sine (tb_cic_decimator.v) ---
cic_imp_ref = readmatrix(fullfile(p.tb_dir, 'cic_impulse_output.csv'));
x = [10000, zeros(1, 4*numel(cic_imp_ref(:,2)) + 64)];
ok_any = false;
for dpz = 0:3
    y = cic_apply(x, p, dpz);
    [f, ~] = best_lag(y, cic_imp_ref(:,2), 0, 10);
    if f == 1, ok_any = true; break; end
end
add('CIC vs RTL dump (impulse)', ok_any, tern(ok_any, 'exact at some decim phase', 'no phase matches'));

cic_dc_ref = readmatrix(fullfile(p.tb_dir, 'cic_dc_output.csv'));
x = 1000 * ones(1, 4*size(cic_dc_ref,1) + 64);
ok_any = false;
for dpz = 0:3
    y = cic_apply(x, p, dpz);
    [f, ~] = best_lag(y, cic_dc_ref(:,3), 0, 10);
    if f == 1, ok_any = true; break; end
end
add('CIC vs RTL dump (DC 1000)', ok_any, tern(ok_any, 'exact at some decim phase', 'no phase matches'));

% CSV logs one row per decimated output; rebuild the full-rate input from
% the testbench formula data_in = $rtoi(5000*sin(2*pi*n/400)).
cic_sin = readmatrix(fullfile(p.tb_dir, 'cic_sine_passband.csv'));   % input_n,data_in,output_n,data_out
nmax = max(cic_sin(:, 1)) + 16;
x = fix(5000 * sin(2*pi*(0:nmax)/400));
ref_y = cic_sin(:, 4);
ok_any = false;  best_f = 0;
for dpz = 0:3
    y = cic_apply(x, p, dpz);
    [f, ~] = best_lag(y, ref_y, 12, 10);              % skip carry-over from prior tb tests
    best_f = max(best_f, f);
    if f >= 0.99, ok_any = true; break; end
end
add('CIC vs RTL dump (passband sine)', ok_any, sprintf('settled match %.4f', best_f));

% --- FIR: impulse 1000, DC 5000, passband sine (tb_fir_lowpass.v) ---
fir_imp = readmatrix(fullfile(p.tb_dir, 'fir_impulse_output.csv'));
x = [1000, zeros(1, numel(fir_imp(:,2)) + 8)];
y = fir_apply(x, p);
[f, lg] = best_lag(y, fir_imp(:,2), 0, 8);
add('FIR vs RTL dump (impulse)', f == 1, sprintf('match %.4f (lag %d)', f, lg));

fir_dc = readmatrix(fullfile(p.tb_dir, 'fir_dc_output.csv'));
x = 5000 * ones(1, size(fir_dc,1) + 8);
y = fir_apply(x, p);
[f, lg] = best_lag(y, fir_dc(:,2), 0, 8);
add('FIR vs RTL dump (DC 5000)', f == 1, sprintf('match %.4f (lag %d)', f, lg));

fir_sin = readmatrix(fullfile(p.tb_dir, 'fir_sine_passband.csv'));   % sample,data_in,data_out
y = fir_apply(fir_sin(:,2).', p);
[f, lg] = best_lag(y, fir_sin(:,3), 40, 10);          % skip pipeline-latency rows
add('FIR vs RTL dump (passband sine)', f >= 0.99, sprintf('settled match %.4f (lag %d)', f, lg));

% =====================================================================
% Report
% =====================================================================
n_pass = sum([results.pass]);
fprintf('=== %d/%d checks passed ===\n', n_pass, numel(results));

outdir = fullfile(p.gen_dir, 'matlab_validation');
if ~exist(outdir, 'dir'), mkdir(outdir); end
fid = fopen(fullfile(outdir, 'validation_report.txt'), 'w');
fprintf(fid, 'AERIS-10 MATLAB bit-true model â€” golden-vector validation\n');
fprintf(fid, 'Generated by matlab/validate_against_golden.m\n\n');
for k = 1:numel(results)
    fprintf(fid, '[%s] %-46s %s\n', tern(results(k).pass, 'PASS', 'FAIL'), ...
            results(k).name, results(k).detail);
end
fprintf(fid, '\nInformational notes:\n');
for k = 1:numel(info)
    fprintf(fid, '  - %s\n', info(k));
end
fprintf(fid, ['  - tb/mf_golden_*_case1-4 are floating-point references ', ...
    '(gen_mf_golden_ref.py), not bit-true targets.\n']);
fprintf(fid, ['  - tb/cosim/compare_<scenario>.csv full-DDC dumps are stale ', ...
    '(their own py and rtl columns disagree) and are not used.\n']);
fprintf(fid, '\n%d/%d checks passed\n', n_pass, numel(results));
fclose(fid);
fprintf('Report written to %s\n', fullfile(outdir, 'validation_report.txt'));
end

% ---------------------------------------------------------------------
function y = cic_apply(x, p, decim_phase)
h = 1;
for k = 1:p.cic_stages, h = conv(h, ones(1, p.cic_decim)); end
yf = filter(h, 1, x);
sel = (1 + decim_phase):p.cic_decim:numel(x);
y = aeris.sat_int(aeris.asr(aeris.wrap_int(yf(sel), p.cic_comb_bits), ...
                            p.cic_gain_shift), p.cic_out_bits);
end

function y = fir_apply(x, p)
acc = filter(p.fir_coeffs, 1, x);
y = aeris.wrap_int(aeris.asr(acc, 17), 18);
y(acc >  2^34 - 1) =  2^17 - 1;
y(acc < -2^34)     = -2^17;
end

function [frac, lag] = best_lag(x, ref, skip, max_lag, fixed_lag)
% Best exact-match fraction of x against ref after integer lag alignment;
% comparison starts `skip` samples into the reference.
x = x(:);  ref = ref(:);
if nargin >= 5, lags = fixed_lag; else, lags = -max_lag:max_lag; end
frac = -1;  lag = 0;
for L = lags
    i0 = skip + max(0, -L);
    n = min(numel(ref) - i0, numel(x) - i0 - L);
    if n < 16, continue; end
    f = mean(x(i0 + L + (1:n)) == ref(i0 + (1:n)));
    if f > frac, frac = f; lag = L; end
end
end

function s = tern(c, a, b)
if c, s = a; else, s = b; end
end
