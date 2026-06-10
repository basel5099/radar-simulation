function [mti_i, mti_q] = mti_canceller(dec_i, dec_q, enable)
%MTI_CANCELLER Bit-true 2-pulse canceller (mti_canceller.v).
%   Inputs are n_chirps x n_bins matrices of signed 16-bit values.
%   First chirp output is muted (zeros); afterwards out = cur - prev with
%   saturation to [-32768, 32767].  enable=false -> pass-through.
if nargin < 3, enable = true; end
if ~enable
    mti_i = dec_i;  mti_q = dec_q;
    return;
end
mti_i = zeros(size(dec_i));
mti_q = zeros(size(dec_q));
mti_i(2:end, :) = aeris.sat_int(dec_i(2:end, :) - dec_i(1:end-1, :), 16);
mti_q(2:end, :) = aeris.sat_int(dec_q(2:end, :) - dec_q(1:end-1, :), 16);
end
