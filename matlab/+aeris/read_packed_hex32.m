function [i16, q16] = read_packed_hex32(filepath)
%READ_PACKED_HEX32 Read packed {Q[31:16], I[15:0]} 32-bit hex lines.
%   Returns signed 16-bit I and Q column vectors (cosim packing convention,
%   see gen_doppler_golden.py / STALE_NOTICE.md).
raw = aeris.read_mem_hex(filepath, 32, false);
i16 = mod(raw, 2^16);
q16 = floor(raw / 2^16);
i16(i16 >= 2^15) = i16(i16 >= 2^15) - 2^16;
q16(q16 >= 2^15) = q16(q16 >= 2^15) - 2^16;
end
