function [sin_out, cos_out] = nco_sincos(sample_idx, ftw, lut, phase0)
%NCO_SINCOS Bit-true NCO lookup (nco_400m_enhanced.v / golden_reference.py).
%   [s, c] = NCO_SINCOS(n, ftw, lut, phase0) returns signed 16-bit sin/cos
%   for phase accumulator values  phase = (phase0 + n*ftw) mod 2^32.
%   n may be a vector of sample indices (0-based).  Block-level alignment:
%   ADC sample n is mixed with NCO phase n*ftw (golden_reference.py:299).
%
%   Quarter-wave LUT reconstruction (RTL nco_400m_enhanced.v):
%     lut_address = phase[31:24]; quadrant = addr[7:6];
%     idx = (quadrant[0]^quadrant[1]) ? ~addr[5:0] : addr[5:0]
%     sin_abs = lut[idx]; cos_abs = lut[63-idx]; quadrant sign mux.
%
%   NOTE: the RTL mirror condition q[0]^q[1] selects quadrants 1 AND 2
%   (a textbook quarter-wave DDS mirrors 1 and 3).  In quadrants 2/3 the
%   produced sin/cos are therefore swapped relative to an ideal NCO.
%   This model replicates the RTL exactly (verified against
%   tb/nco_1mhz_output.csv); see the validation report for discussion.
if nargin < 4, phase0 = 0; end
phase = mod(phase0 + sample_idx .* ftw, 2^32);
lut_address = floor(phase / 2^24);            % top 8 bits, 0..255
quadrant = floor(lut_address / 64);           % 0..3
raw_idx  = mod(lut_address, 64);
mirror   = (quadrant == 1) | (quadrant == 2); % RTL: q[0] XOR q[1]
idx = raw_idx;
idx(mirror) = 63 - raw_idx(mirror);

sin_abs = lut(idx + 1);
cos_abs = lut(63 - idx + 1);

% Quadrant signs: Q0:(+,+)  Q1:(+,-)  Q2:(-,-)  Q3:(-,+)
sin_sign = ones(size(quadrant));  sin_sign(quadrant >= 2) = -1;
cos_sign = ones(size(quadrant));  cos_sign(quadrant == 1 | quadrant == 2) = -1;
sin_out = sin_sign .* sin_abs;
cos_out = cos_sign .* cos_abs;
end
