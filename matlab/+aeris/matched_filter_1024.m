function [pc_re, pc_im] = matched_filter_1024(sig_re, sig_im, ref_re, ref_im, cos_rom)
%MATCHED_FILTER_1024 Bit-true pulse compression (matched_filter_processing_chain.v).
%   FFT(signal) .* conj(FFT(reference)) -> IFFT, all 1024-point fixed-point.
[sf_re, sf_im] = aeris.fft_fixed(sig_re, sig_im, cos_rom, false);
[rf_re, rf_im] = aeris.fft_fixed(ref_re, ref_im, cos_rom, false);
[mp_re, mp_im] = aeris.conj_mult_q15(sf_re, sf_im, rf_re, rf_im);
[pc_re, pc_im] = aeris.fft_fixed(mp_re, mp_im, cos_rom, true);
end
