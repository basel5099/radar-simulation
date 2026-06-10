function det = cluster_detections(flags, mags, p, cal_offset, chirp_sign)
%CLUSTER_DETECTIONS Group CFAR hits (8-connected, per sub-frame) and convert
%   to physical units. Reported velocity applies the IF sign convention
%   (measured Doppler = chirp_sign * physical).
det = struct('range_m', {}, 'vel_mps', {}, 'subframe', {}, 'mag', {}, ...
             'rbin', {}, 'dbin', {});
for sf = 0:1
    sub    = flags(:, sf*16 + (1:16));
    submag = mags(:,  sf*16 + (1:16));
    comps = connected_components(sub);
    for k = 1:numel(comps)
        cells = comps{k};
        [~, im] = max(submag(cells));
        [rb, db] = ind2sub(size(sub), cells(im));
        rng_m = ((rb-1)*16 + 8 - cal_offset) * p.range_per_bin;
        db0 = db - 1;
        db_signed = db0 - 16*(db0 >= 8);
        pri = p.t_pri_long;  if sf == 1, pri = p.t_pri_short; end
        vel = chirp_sign * db_signed / (16 * pri) * p.lambda / 2;
        det(end+1) = struct('range_m', rng_m, 'vel_mps', vel, 'subframe', sf, ...
            'mag', submag(cells(im)), 'rbin', rb-1, 'dbin', sf*16 + db0); %#ok<AGROW>
    end
end
end

function cc = connected_components(mask)
% Minimal 8-connected labelling (no toolbox dependency).
cc = {};
visited = false(size(mask));
[nr, nc] = size(mask);
for idx = find(mask(:)).'
    if visited(idx), continue; end
    stack = idx;  comp = [];
    visited(idx) = true;
    while ~isempty(stack)
        cur = stack(end);  stack(end) = [];
        comp(end+1) = cur; %#ok<AGROW>
        [r, c] = ind2sub([nr nc], cur);
        for dr = -1:1
            for dc2 = -1:1
                rr = r + dr;  cc2 = c + dc2;
                if rr >= 1 && rr <= nr && cc2 >= 1 && cc2 <= nc
                    j = sub2ind([nr nc], rr, cc2);
                    if mask(j) && ~visited(j)
                        visited(j) = true;
                        stack(end+1) = j; %#ok<AGROW>
                    end
                end
            end
        end
    end
    cc{end+1} = comp; %#ok<AGROW>
end
end
