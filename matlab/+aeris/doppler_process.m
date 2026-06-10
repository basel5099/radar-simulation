function [map_i, map_q] = doppler_process(frame_i, frame_q, p, cos_rom16)
%DOPPLER_PROCESS Bit-true dual 16-pt Doppler FFT (doppler_processor.v).
%   frame_i/q : 32 chirps x 64 range bins (signed 16-bit)
%   map_i/q   : 64 range bins x 32 Doppler bins
%               bins 0-15 = sub-frame 0 (long PRI, chirps 0-15)
%               bins 16-31 = sub-frame 1 (short PRI, chirps 16-31)
%   Window: 16-pt Hamming Q15, product rounded (+2^14) >>> 15.
[n_chirps, n_rbins] = size(frame_i);
assert(n_chirps == p.chirps_per_frame && n_rbins == p.range_bins);
nf = p.doppler_fft_size;
map_i = zeros(p.range_bins, p.doppler_total_bins);
map_q = zeros(p.range_bins, p.doppler_total_bins);
w = p.hamming_q15(:).';

for rb = 1:p.range_bins
    for sf = 0:1
        rows = sf*nf + (1:nf);
        wi = aeris.sat_int(aeris.asr(frame_i(rows, rb).' .* w + 2^14, 15), 16);
        wq = aeris.sat_int(aeris.asr(frame_q(rows, rb).' .* w + 2^14, 15), 16);
        [fr, fi] = aeris.fft_fixed(wi, wq, cos_rom16, false);
        map_i(rb, sf*nf + (1:nf)) = fr;
        map_q(rb, sf*nf + (1:nf)) = fi;
    end
end
end
