function out = ddc_chain(adc_u8, p, opts)
%DDC_CHAIN Bit-true digital down-converter: ADC -> NCO/mixer -> CIC -> FIR -> 16-bit.
%   out = DDC_CHAIN(adc_u8, p) processes 8-bit unsigned ADC samples
%   (400 MSPS) and returns baseband I/Q at 100 MSPS.
%
%   Replicates the RTL arithmetic exactly (block-level alignment of
%   golden_reference.py: NCO phase n*ftw at ADC sample n, CIC output k
%   taken after inputs 0..4k+3, causal FIR):
%     adc_signed = (adc<<9) - 0xFF00                        (18-bit)
%     I = adc_signed*cos, Q = adc_signed*sin; keep [33:16]  (18-bit wrap)
%     CIC: 5-stage, R=4  == FIR (ones(1,4) conv ^5) -> >>>10 -> sat 18
%     FIR: 32-tap, sat to 2^34 bounds else accum[34:17]     (18-bit wrap)
%     Interface: 16-bit = wrap16( v[17:2] + v[1] )          (rounding)
%
%   out fields: .bb_i/.bb_q (16-bit), .fir_i/q, .cic_i/q (18-bit),
%               .mix_i/q (18-bit), plus .sin/.cos for debugging.
%
%   opts.phase0     initial NCO phase accumulator value (default 0)
%   opts.ftw        NCO tuning word (default p.nco_ftw)
%   opts.decim_phase 0..3, which 400 MHz sample within each group of 4 the
%               CIC output is sampled at (default 3 = golden_reference.py)
arguments
    adc_u8 (1,:) double
    p struct
    opts.phase0 (1,1) double = 0
    opts.ftw (1,1) double = 0
    opts.decim_phase (1,1) double = 3
end
if opts.ftw == 0, opts.ftw = p.nco_ftw; end
n = numel(adc_u8);

% ---- ADC offset-binary -> 18-bit signed (ddc_400m.v:228) ----
adc_signed = adc_u8 * 512 - 65280;     % (adc<<9) - 0xFF00, range fits 18 bits

% ---- NCO + mixer ----
[s16, c16] = aeris.nco_sincos(0:n-1, opts.ftw, p.nco_lut, opts.phase0);
mix_i = aeris.wrap_int(aeris.asr(adc_signed .* c16, p.mixer_shift), 18);
mix_q = aeris.wrap_int(aeris.asr(adc_signed .* s16, p.mixer_shift), 18);

% ---- CIC: integrator/comb cascade == conv with (ones(1,4))^*5, decimate ----
% Exact equivalence holds because |output| stays inside the 28-bit comb
% range (max 2^17 * 1024 = 2^27), so the 48-bit modular integrators cancel.
h_cic = 1;
for k = 1:p.cic_stages
    h_cic = conv(h_cic, ones(1, p.cic_decim));
end
cic_i_full = filter(h_cic, 1, mix_i);
cic_q_full = filter(h_cic, 1, mix_q);
sel = (1 + opts.decim_phase) : p.cic_decim : n;     % sample at 4k+decim_phase
cic_i = aeris.sat_int(aeris.asr(aeris.wrap_int(cic_i_full(sel), p.cic_comb_bits), ...
                                p.cic_gain_shift), p.cic_out_bits);
cic_q = aeris.sat_int(aeris.asr(aeris.wrap_int(cic_q_full(sel), p.cic_comb_bits), ...
                                p.cic_gain_shift), p.cic_out_bits);

% ---- FIR lowpass (fir_lowpass.v): 36-bit accum, sat at +/-2^34, [34:17] ----
acc_i = filter(p.fir_coeffs, 1, cic_i);
acc_q = filter(p.fir_coeffs, 1, cic_q);
fir_i = fir_round(acc_i);
fir_q = fir_round(acc_q);

% ---- DDC input interface: 18 -> 16 bit with round-half-up, wrap ----
bb_i = round18to16(fir_i);
bb_q = round18to16(fir_q);

out = struct('bb_i', bb_i, 'bb_q', bb_q, 'fir_i', fir_i, 'fir_q', fir_q, ...
             'cic_i', cic_i, 'cic_q', cic_q, 'mix_i', mix_i, 'mix_q', mix_q, ...
             'sin', s16, 'cos', c16);
end

function y = fir_round(acc)
% fir_lowpass.v output stage: saturate vs +/-2^34, else wrap18(acc[34:17])
y = aeris.wrap_int(aeris.asr(acc, 17), 18);
y(acc >  2^34 - 1) =  2^17 - 1;
y(acc < -2^34)     = -2^17;
end

function y = round18to16(v)
% ddc_input_interface.v: adc_i = ddc_i[17:2] + ddc_i[1]  (16-bit wrap)
t  = aeris.asr(v, 2);
b1 = mod(aeris.asr(v, 1), 2);
y  = aeris.wrap_int(t + b1, 16);
end
