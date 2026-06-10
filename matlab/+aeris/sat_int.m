function s = sat_int(v, bits)
%SAT_INT Saturate to signed two's-complement range [-2^(b-1), 2^(b-1)-1].
hi = 2^(bits-1) - 1;
lo = -2^(bits-1);
s = min(max(v, lo), hi);
end
