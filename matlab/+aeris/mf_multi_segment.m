function res = mf_multi_segment(bb_i, bb_q, refs, use_long, cos_rom, opts)
%MF_MULTI_SEGMENT Bit-true model of matched_filter_multi_segment.v.
%   res = MF_MULTI_SEGMENT(bb_i, bb_q, refs, use_long, cos_rom)
%
%   bb_i/bb_q : baseband 16-bit I/Q stream at 100 MSPS, starting at the
%               sample where the FPGA begins collecting (chirp start).
%   refs      : from aeris.load_chirp_refs (segment references).
%   use_long  : true = long chirp (4 segments), false = short (1 segment).
%
%   Input conversion (RTL stores ddc_i[17:2] + ddc_i[1] where ddc_i is the
%   16-bit receiver word sign-extended to 18 bits): stored = wrap16(v>>>2 + v[1]).
%
%   Segmentation, per the current RTL ("overlap-save fix", full buffer):
%     segment 0: stream samples 1..1024
%     segment k: stream samples 896k+1 .. 896k+1024
%     collection stops at sample 3000 (chirp_complete); the rest of the
%     last buffer is zero-padded (ST_ZERO_PAD).
%   opts.framing = 'legacy' reproduces the older gen_multiseg_golden.py
%   layout (segment 0 = [896 samples | 128 zeros], segments 1+ =
%   [128 zeros | 768 samples | 128 zeros]) for golden-vector comparison.
%
%   Returns res.seg_re / res.seg_im : n_seg x 1024 pulse-compressed output,
%   res.buffers_i/q : what each segment's FFT actually consumed.
arguments
    bb_i (1,:) double
    bb_q (1,:) double
    refs struct
    use_long (1,1) logical
    cos_rom (:,1) double
    opts.framing (1,1) string = "rtl"
    opts.convert_input (1,1) logical = true
end
B   = 1024;            % BUFFER_SIZE
OV  = 128;             % OVERLAP_SAMPLES
ADV = B - OV;          % SEGMENT_ADVANCE = 896

% ---- input conversion: wrap16( (v sign-extended to 18) >>> 2 + bit1 ) ----
if opts.convert_input
    s_i = aeris.wrap_int(aeris.asr(bb_i, 2) + mod(aeris.asr(bb_i, 1), 2), 16);
    s_q = aeris.wrap_int(aeris.asr(bb_q, 2) + mod(aeris.asr(bb_q, 1), 2), 16);
else
    s_i = bb_i;  s_q = bb_q;
end

if use_long
    n_seg = 4;
    total = 3000;                       % LONG_CHIRP_SAMPLES
    % pad stream so indexing below never runs out
    need = 896*3 + 1024;
    if numel(s_i) < need
        s_i(end+1:need) = 0;  s_q(end+1:need) = 0;
    end
    ref_i = refs.long_i;  ref_q = refs.long_q;
else
    n_seg = 1;
    total = 50;                         % SHORT_CHIRP_SAMPLES
    if numel(s_i) < total
        s_i(end+1:total) = 0;  s_q(end+1:total) = 0;
    end
    ref_i = refs.short_i;  ref_q = refs.short_q;
end

res.seg_re = zeros(n_seg, B);
res.seg_im = zeros(n_seg, B);
res.buffers_i = zeros(n_seg, B);
res.buffers_q = zeros(n_seg, B);

for seg = 0:n_seg-1
    buf_i = zeros(1, B);
    buf_q = zeros(1, B);
    switch opts.framing
        case "rtl"
            % full-buffer overlap-save; samples beyond `total` are zero
            % (chirp_complete -> ST_ZERO_PAD)
            first = seg*ADV + 1;                       % 1-based stream index
            last  = min(first + B - 1, total);
            n_take = max(0, last - first + 1);
            if n_take > 0
                buf_i(1:n_take) = s_i(first:last);
                buf_q(1:n_take) = s_q(first:last);
            end
        case "legacy"
            % gen_multiseg_golden.py layout (pre-fix RTL behaviour)
            if seg == 0
                buf_i(1:ADV) = s_i(1:ADV);
                buf_q(1:ADV) = s_q(1:ADV);
            else
                first = ADV + (seg-1)*(ADV-OV) + 1;    % 896 + 768*(seg-1) + 1
                buf_i(OV+1:ADV) = s_i(first : first + (ADV-OV) - 1);
                buf_q(OV+1:ADV) = s_q(first : first + (ADV-OV) - 1);
            end
        otherwise
            error('Unknown framing "%s"', opts.framing);
    end
    if ~use_long
        buf_i(total+1:end) = 0;
        buf_q(total+1:end) = 0;
        buf_i(1:total) = s_i(1:total);
        buf_q(1:total) = s_q(1:total);
    end

    [pc_re, pc_im] = aeris.matched_filter_1024(buf_i, buf_q, ...
        ref_i(seg+1, :), ref_q(seg+1, :), cos_rom);
    res.seg_re(seg+1, :) = pc_re;
    res.seg_im(seg+1, :) = pc_im;
    res.buffers_i(seg+1, :) = buf_i;
    res.buffers_q(seg+1, :) = buf_q;
end
end
