function [out_re, out_im] = range_bin_decimator(in_re, in_im, mode, start_bin)
%RANGE_BIN_DECIMATOR Bit-true model of range_bin_decimator.v (1024 -> 64).
%   mode: 0 = centre sample of each group of 16
%         1 = peak |I|+|Q| within each group (receiver default)
%         2 = average (sum >>> 4, truncation)
%   start_bin: number of leading input bins to skip (default 0).
if nargin < 3, mode = 1; end
if nargin < 4, start_bin = 0; end
DF = 16;  NOUT = 64;
in_re = in_re(:).';  in_im = in_im(:).';
out_re = zeros(1, NOUT);  out_im = zeros(1, NOUT);
n_in = numel(in_re);

for b = 0:NOUT-1
    base = start_bin + b*DF;                  % 0-based
    switch mode
        case 0
            idx = base + DF/2;
            if idx < n_in
                out_re(b+1) = in_re(idx+1);
                out_im(b+1) = in_im(idx+1);
            end
        case 1
            best_mag = -1;
            for s = 0:DF-1
                idx = base + s;
                if idx >= n_in, break; end
                mag = abs(in_re(idx+1)) + abs(in_im(idx+1));   % 17-bit L1
                if mag > best_mag                              % first max wins
                    best_mag = mag;
                    out_re(b+1) = in_re(idx+1);
                    out_im(b+1) = in_im(idx+1);
                end
            end
        case 2
            idx = base + (0:DF-1);
            idx = idx(idx < n_in);
            out_re(b+1) = aeris.asr(sum(in_re(idx+1)), 4);
            out_im(b+1) = aeris.asr(sum(in_im(idx+1)), 4);
        otherwise
            % reserved -> zeros
    end
end
end
