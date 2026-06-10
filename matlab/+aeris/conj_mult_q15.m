function [out_re, out_im] = conj_mult_q15(a, b, c, d)
%CONJ_MULT_Q15 Bit-true conjugate multiply (frequency_matched_filter.v).
%   (a + jb) * conj(c + jd) = (ac + bd) + j(bc - ad), Q15 inputs.
%   Round-to-nearest (+2^14), saturate at +/-0x3FFF8000, extract [30:15].
real_sum = a .* c + b .* d;
imag_sum = b .* c - a .* d;
out_re = round_sat(real_sum);
out_im = round_sat(imag_sum);
end

function y = round_sat(v)
r = v + 2^14;
y = aeris.wrap_int(aeris.asr(r, 15), 16);
y(r >  hex2dec('3FFF8000')) =  32767;
y(r < -hex2dec('3FFF8000')) = -32768;
end
