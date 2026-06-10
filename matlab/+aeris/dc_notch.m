function [out_i, out_q] = dc_notch(map_i, map_q, width)
%DC_NOTCH Bit-true post-Doppler DC notch (radar_system_top.v).
%   Zeros Doppler bins around DC in BOTH sub-frames:
%     bin_within_sf < width  OR  bin_within_sf > (15 - width + 1)
%   width = 0 -> pass-through.  width = 2 zeros bins {0,1,15,16,17,31}.
out_i = map_i;  out_q = map_q;
if width == 0, return; end
dbin = 0:size(map_i, 2)-1;
bin_in_sf = mod(dbin, 16);
active = (bin_in_sf < width) | (bin_in_sf > (15 - width + 1));
out_i(:, active) = 0;
out_q(:, active) = 0;
end
