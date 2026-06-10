function [flags, mags, thrs] = cfar_ca(map_i, map_q, guard, train, alpha_q44, mode)
%CFAR_CA Bit-true CA/GO/SO-CFAR detector (cfar_ca.v).
%   Operates down range (per Doppler column) on |I|+|Q| magnitudes (17-bit).
%   threshold = (alpha_q44 * noise_sum) >>> 4, saturated to 131071.
%   Detection: magnitude > threshold (strict).
%   Edge handling: out-of-range training cells contribute zero.
if nargin < 6, mode = 'CA'; end
[n_range, n_dopp] = size(map_i);
mags = abs(map_i) + abs(map_q);       % |-32768| = 32768, matches RTL unsigned abs
flags = false(n_range, n_dopp);
thrs  = zeros(n_range, n_dopp);
MAX_MAG = 2^17 - 1;
if train == 0, train = 1; end          % RTL clamps

for d = 1:n_dopp
    col = mags(:, d);
    for cut = 1:n_range
        lead_idx = cut - guard - (1:train);
        lag_idx  = cut + guard + (1:train);
        lead_idx = lead_idx(lead_idx >= 1 & lead_idx <= n_range);
        lag_idx  = lag_idx(lag_idx >= 1 & lag_idx <= n_range);
        lead_sum = sum(col(lead_idx));   lead_cnt = numel(lead_idx);
        lag_sum  = sum(col(lag_idx));    lag_cnt  = numel(lag_idx);

        switch upper(mode)
            case 'GO'
                if lead_cnt > 0 && lag_cnt > 0
                    if lead_sum * lag_cnt > lag_sum * lead_cnt
                        noise = lead_sum;
                    else
                        noise = lag_sum;
                    end
                elseif lead_cnt > 0
                    noise = lead_sum;
                else
                    noise = lag_sum;
                end
            case 'SO'
                if lead_cnt > 0 && lag_cnt > 0
                    if lead_sum * lag_cnt < lag_sum * lead_cnt
                        noise = lead_sum;
                    else
                        noise = lag_sum;
                    end
                elseif lead_cnt > 0
                    noise = lead_sum;
                else
                    noise = lag_sum;
                end
            otherwise   % CA
                noise = lead_sum + lag_sum;
        end

        thr = aeris.asr(alpha_q44 * noise, 4);
        thr = min(thr, MAX_MAG);
        thrs(cut, d) = thr;
        flags(cut, d) = col(cut) > thr;
    end
end
end
