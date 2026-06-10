function y = asr(v, shift)
%ASR Arithmetic shift right (Verilog >>>) on exact-integer doubles.
%   floor division == arithmetic right shift for two's-complement values.
y = floor(v / 2^shift);
end
