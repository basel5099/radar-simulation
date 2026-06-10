function s = wrap_int(v, bits)
%WRAP_INT Wrap to signed two's-complement range (Verilog truncation).
%   Exact for |v| < 2^53 (all chain values qualify).
m = 2^bits;
u = mod(v, m);
s = u - m .* (u >= m/2);
end
