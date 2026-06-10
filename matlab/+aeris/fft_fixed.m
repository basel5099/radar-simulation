function [out_re, out_im] = fft_fixed(in_re, in_im, cos_rom, inverse)
%FFT_FIXED Bit-true radix-2 DIT FFT/IFFT (fft_engine.v).
%   [re, im] = FFT_FIXED(in_re, in_im, cos_rom, inverse)
%   N is taken from numel(in_re); cos_rom holds N/4 quarter-wave Q15
%   cosines.  Arithmetic per the RTL:
%     - inputs sign-extended to 32-bit work memory at bit-reversed addresses
%     - per butterfly: 32x16 product, arithmetic >>>15, add/sub (no clip)
%     - forward output: saturate to 16 bits (NO 1/N scaling)
%     - inverse: extra >>>log2(N) before the 16-bit saturation
in_re = in_re(:).';  in_im = in_im(:).';
N = numel(in_re);
L = round(log2(N));
assert(2^L == N, 'FFT size must be a power of two');

% Bit-reversed load
idx  = 0:N-1;
brid = bin2dec(fliplr(dec2bin(idx, L))).';
mem_re = zeros(1, N);  mem_im = zeros(1, N);
mem_re(brid + 1) = in_re;
mem_im(brid + 1) = in_im;

for stage = 0:L-1
    half  = 2^stage;
    bfly  = 0:(N/2 - 1);
    k     = mod(bfly, half);          % idx within group
    grp   = bfly - k;
    even  = 2*grp + k;
    odd   = even + half;
    tw_idx = mod(k * 2^(L-1-stage), N/2);
    [tw_cos, tw_sin] = twiddle_lookup(tw_idx, N, cos_rom);

    a_re = mem_re(even + 1);  a_im = mem_im(even + 1);
    b_re = mem_re(odd + 1);   b_im = mem_im(odd + 1);

    if ~inverse
        pr = b_re .* tw_cos + b_im .* tw_sin;
        pi_ = b_im .* tw_cos - b_re .* tw_sin;
    else
        pr = b_re .* tw_cos - b_im .* tw_sin;
        pi_ = b_im .* tw_cos + b_re .* tw_sin;
    end
    tr = aeris.asr(pr, 15);
    ti = aeris.asr(pi_, 15);

    mem_re(even + 1) = a_re + tr;
    mem_im(even + 1) = a_im + ti;
    mem_re(odd + 1)  = a_re - tr;
    mem_im(odd + 1)  = a_im - ti;
end

if inverse
    mem_re = aeris.asr(mem_re, L);
    mem_im = aeris.asr(mem_im, L);
end
out_re = aeris.sat_int(mem_re, 16);
out_im = aeris.sat_int(mem_im, 16);
end

function [tw_cos, tw_sin] = twiddle_lookup(k, N, cos_rom)
% Quarter-wave reconstruction (fft_engine.v tw_lookup):
%   k=0:    cos=rom[0], sin=0          k=N/4:  cos=0, sin=rom[0]
%   k<N/4:  cos=rom[k], sin=rom[N/4-k] k>N/4:  cos=-rom[N/2-k], sin=rom[k-N/4]
n4 = N/4;  n2 = N/2;
k = mod(k, n2);
tw_cos = zeros(size(k));  tw_sin = zeros(size(k));
m = (k == 0);
tw_cos(m) = cos_rom(1);   tw_sin(m) = 0;
m = (k == n4);
tw_cos(m) = 0;            tw_sin(m) = cos_rom(1);
m = (k > 0 & k < n4);
tw_cos(m) = cos_rom(k(m) + 1);
tw_sin(m) = cos_rom(n4 - k(m) + 1);
m = (k > n4);
tw_cos(m) = -cos_rom(n2 - k(m) + 1);
tw_sin(m) = cos_rom(k(m) - n4 + 1);
end
