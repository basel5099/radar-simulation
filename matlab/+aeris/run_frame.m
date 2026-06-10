function R = run_frame(scn, p, refs, rom1024, rom16, progress_cb)
%RUN_FRAME Run a full 32-chirp staggered-PRI frame through the bit-true chain.
%   R = RUN_FRAME(scn, p, refs, rom1024, rom16, progress_cb)
%
%   scn fields:
%     .targets   struct array: range_m, velocity_mps, rcs_dbsm, phase_deg
%     .clutter   same form (may be empty struct([]))
%     .noise_std AWGN sigma in ADC LSB
%     .gc_shift  digital gain (rx_gain_control), e.g. -4 = divide by 16
%   progress_cb: optional @(frac, msg) for UI progress.
%
%   Returns R with: frame_dec_i/q (32x64 decimated range rows),
%   map_i/q (Doppler, MTI off), mmap_i/q (Doppler, MTI on),
%   range_axis_dec, vel_axis (physical sign), cal_offset, chirp_sign.
%
%   Same processing as aeris_endtoend_sim, packaged for interactive use.
if nargin < 6 || isempty(progress_cb), progress_cb = @(varargin) []; end
CHIRP_SIGN = -1;      % compressing IF convention (auto-calibrated in the sim)
CAL_OFFSET = 20;      % DDC+MF group delay, fast-time bins (= 30 m)
LEAD  = 512;
NBB_L = 3072;  NADC_L = LEAD + 4*(NBB_L + 64);
NBB_S = 128;   NADC_S = LEAD + 4*(NBB_S + 64);

rng(42, 'twister');
fd_i = zeros(p.chirps_per_frame, p.range_bins);
fd_q = zeros(p.chirps_per_frame, p.range_bins);
for c = 0:p.chirps_per_frame-1
    if c < p.chirps_per_subframe
        slow_t = c * p.t_pri_long;
        ct = "long";  na = NADC_L;  nb = NBB_L;
    else
        slow_t = p.chirps_per_subframe*p.t_pri_long + p.t_guard + ...
                 (c - p.chirps_per_subframe)*p.t_pri_short;
        ct = "short";  na = NADC_S;  nb = NBB_S;
    end
    adc = aeris.scene_generate_adc(scn.targets, na, p, chirp=ct, ...
        slow_time_s=slow_t, noise_std=scn.noise_std, chirp_sign=CHIRP_SIGN, ...
        clutter=scn.clutter, tx_start_samp=LEAD);
    d = aeris.ddc_chain(adc, p);
    i0 = LEAD/4;
    bi = aeris.rx_gain_control(d.bb_i(i0+1:i0+nb), scn.gc_shift);
    bq = aeris.rx_gain_control(d.bb_q(i0+1:i0+nb), scn.gc_shift);
    r = aeris.mf_multi_segment(bi, bq, refs, ct == "long", rom1024, framing="rtl");
    [fd_i(c+1,:), fd_q(c+1,:)] = ...
        aeris.range_bin_decimator(r.seg_re(1,:), r.seg_im(1,:), 1, 0);
    progress_cb((c+1)/p.chirps_per_frame, sprintf('chirp %d / %d', c+1, p.chirps_per_frame));
end

[map_i, map_q]   = aeris.doppler_process(fd_i, fd_q, p, rom16);
[mti_i, mti_q]   = aeris.mti_canceller(fd_i, fd_q, true);
[mmap_i, mmap_q] = aeris.doppler_process(mti_i, mti_q, p, rom16);

d16 = 0:15;
ds = d16 - 16*(d16 >= 8);
vel = CHIRP_SIGN * ds / (16 * p.t_pri_long) * p.lambda / 2;

R = struct('frame_dec_i', fd_i, 'frame_dec_q', fd_q, ...
           'map_i', map_i, 'map_q', map_q, 'mmap_i', mmap_i, 'mmap_q', mmap_q, ...
           'cal_offset', CAL_OFFSET, 'chirp_sign', CHIRP_SIGN, ...
           'range_axis_dec', ((0:p.range_bins-1)*16 + 8 - CAL_OFFSET) * p.range_per_bin, ...
           'vel_axis', vel);
end
