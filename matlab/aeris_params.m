function p = aeris_params()
%AERIS_PARAMS Central parameter set for the AERIS-10 bit-true MATLAB model.
%
%   All values are extracted from the FPGA RTL of the upstream AERIS-10
%   project (see UPSTREAM.md for the exact provenance) and the verified
%   co-simulation reference models. Do not edit numbers here without
%   checking the RTL — these are bit-true constants, not tuning knobs.
%
%   The chirp tables, twiddle ROMs, Verilog sources and golden vectors
%   this suite needs are vendored under reference/fpga/ with the
%   directory structure of the upstream 9_Firmware/9_2_FPGA folder.

% ---- Repository paths (derived from this file's location) ----
here          = fileparts(mfilename('fullpath'));   % .../matlab
p.repo_root   = fileparts(here);                    % repo root
p.fpga_dir    = fullfile(p.repo_root, 'reference', 'fpga');
p.cosim_dir   = fullfile(p.fpga_dir, 'tb', 'cosim');
p.realdata_dir= fullfile(p.cosim_dir, 'real_data', 'hex');
p.tb_dir      = fullfile(p.fpga_dir, 'tb');
p.gen_dir     = fullfile(p.repo_root, 'generated');

% ---- RF / system (radar_scene.py, scenario_info.txt) ----
p.f_carrier   = 10.5e9;            % Hz, X-band carrier
p.c           = 3.0e8;             % m/s (value used by the cosim suite)
p.lambda      = p.c / p.f_carrier; % ~28.57 mm
p.f_if        = 120e6;             % Hz, receiver IF (NCO frequency)
p.chirp_bw    = 20e6;              % Hz  (30 MHz -> 10 MHz sweep)
p.fs_adc      = 400e6;             % ADC sample rate (AD9484, 8-bit)
p.fs_sys      = 100e6;             % post-CIC processing rate
p.adc_bits    = 8;

% ---- Chirp timing (plfm_chirp_controller.v:36-50, radar_mode_controller.v) ----
p.t_long_chirp   = 30e-6;          % 3000 samples @ 100 MHz
p.t_short_chirp  = 0.5e-6;         % 50 samples   @ 100 MHz
p.t_listen_long  = 137e-6;
p.t_listen_short = 174.5e-6;
p.t_guard        = 175.4e-6;
p.t_pri_long     = p.t_long_chirp  + p.t_listen_long;   % 167 us
p.t_pri_short    = p.t_short_chirp + p.t_listen_short;  % 175 us
p.long_chirp_samples  = 3000;      % @ fs_sys (matched_filter_multi_segment.v:43)
p.short_chirp_samples = 50;        % @ fs_sys (matched_filter_multi_segment.v:44)
p.chirp_rate_long  = p.chirp_bw / p.t_long_chirp;   % 6.6667e11 Hz/s
p.chirp_rate_short = p.chirp_bw / p.t_short_chirp;  % 4e13 Hz/s

% ---- Frame structure (doppler_processor.v:36-41, plfm_chirp_controller.v:48) ----
p.chirps_per_frame    = 32;        % 16 long-PRI + 16 short-PRI
p.chirps_per_subframe = 16;
p.range_bins          = 64;        % post range-bin-decimation
p.doppler_fft_size    = 16;        % per sub-frame
p.doppler_total_bins  = 32;

% ---- DDC (nco_400m_enhanced.v, ddc_400m.v, cic_*.v, fir_lowpass.v) ----
p.nco_ftw       = hex2dec('4CCCCCCD');  % 120 MHz @ 400 MSPS, 32-bit FTW
p.nco_phase_bits= 32;
p.cic_stages    = 5;
p.cic_decim     = 4;
p.cic_comb_bits = 28;
p.cic_gain_shift= 10;              % >>>10 normalises gain 4^5 = 1024
p.cic_out_bits  = 18;
p.mixer_shift   = 16;              % keep [33:16] of the 34-bit product
p.fir_accum_bits= 36;
p.fir_out_shift = 17;              % accumulator[34:17]
% 32-tap FIR coefficients, 18-bit signed (fir_lowpass.v:80-87)
fir_hex = { ...
 '000AD','000CE','3FD87','002A6','000E0','3F8C0','00A45','3FD82', ...
 '3F0B5','01CAD','3EE59','3E821','04841','3B340','3E299','1FFFF', ...
 '1FFFF','3E299','3B340','04841','3E821','3EE59','01CAD','3F0B5', ...
 '3FD82','00A45','3F8C0','000E0','002A6','3FD87','000CE','000AD'};
v = hex2dec(char(fir_hex));
v(v >= 2^17) = v(v >= 2^17) - 2^18;            % sign-extend 18-bit
p.fir_coeffs = v(:).';

% ---- NCO quarter-wave sine LUT, 64 x 16-bit (nco_400m_enhanced.v:83-99) ----
lut_hex = { ...
 '0000','0324','0648','096A','0C8C','0FAB','12C8','15E2', ...
 '18F9','1C0B','1F1A','2223','2528','2826','2B1F','2E11', ...
 '30FB','33DF','36BA','398C','3C56','3F17','41CE','447A', ...
 '471C','49B4','4C3F','4EBF','5133','539B','55F5','5842', ...
 '5A82','5CB3','5ED7','60EB','62F1','64E8','66CF','68A6', ...
 '6A6D','6C23','6DC9','6F5E','70E2','7254','73B5','7504', ...
 '7641','776B','7884','7989','7A7C','7B5C','7C29','7CE3', ...
 '7D89','7E1D','7E9C','7F09','7F61','7FA6','7FD8','7FF5'};
p.nco_lut = hex2dec(char(lut_hex)).';          % all positive, no sign fix

% ---- Matched filter (matched_filter_*.v, fft_engine.v) ----
p.fft_size        = 1024;
p.mf_buffer_size  = 1024;
p.mf_overlap      = 128;
p.mf_seg_advance  = 896;           % BUFFER_SIZE - OVERLAP
p.mf_long_segments= 4;
p.twiddle_1024_file = fullfile(p.fpga_dir, 'fft_twiddle_1024.mem');
p.twiddle_16_file   = fullfile(p.fpga_dir, 'fft_twiddle_16.mem');

% ---- Hamming window, 16 x Q15 (doppler_processor.v:82-106) ----
ham_hex = {'0A3D','0E5C','1B6D','3088','4B33','6573','7642','7F62', ...
           '7F62','7642','6573','4B33','3088','1B6D','0E5C','0A3D'};
p.hamming_q15 = hex2dec(char(ham_hex)).';

% ---- CFAR / MTI / DC-notch defaults (radar_system_top.v:929-936) ----
p.cfar_guard  = 2;                 % per side
p.cfar_train  = 8;                 % per side
p.cfar_alpha  = hex2dec('30');     % Q4.4 -> 3.0
p.cfar_mode   = 'CA';              % CA / GO / SO
p.mti_enable  = false;             % host default (0x26 = 0)
p.dc_notch_width = 0;              % host default (0x27 = 0)

% ---- Derived radar quantities ----
p.range_res_rf   = p.c / (2*p.chirp_bw);     % 7.5 m (RF resolution)
p.range_per_bin  = p.c / (2*p.fs_sys);       % 1.5 m per fast-time sample
p.range_per_dbin = p.range_per_bin * 16;     % 24 m per decimated bin
p.vel_res_long   = p.lambda / (2*p.chirps_per_subframe*p.t_pri_long);
p.vel_res_short  = p.lambda / (2*p.chirps_per_subframe*p.t_pri_short);

% ---- Chirp reference memory files (chirp_memory_loader_param.v) ----
p.chirp_mem.long_i = arrayfun(@(s) fullfile(p.fpga_dir, ...
    sprintf('long_chirp_seg%d_i.mem', s)), 0:3, 'UniformOutput', false);
p.chirp_mem.long_q = arrayfun(@(s) fullfile(p.fpga_dir, ...
    sprintf('long_chirp_seg%d_q.mem', s)), 0:3, 'UniformOutput', false);
p.chirp_mem.short_i = fullfile(p.fpga_dir, 'short_chirp_i.mem');
p.chirp_mem.short_q = fullfile(p.fpga_dir, 'short_chirp_q.mem');
end
