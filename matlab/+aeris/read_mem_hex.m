function vals = read_mem_hex(filepath, bits, signed)
%READ_MEM_HEX Read a Verilog $readmemh-style hex file (one value per line).
%   vals = READ_MEM_HEX(file, bits, signed) returns a column vector of
%   exact-integer doubles.  Lines starting with '//' and blanks are skipped.
%   If signed (default true), values are sign-extended from `bits` width.
if nargin < 3, signed = true; end
txt = readlines(filepath);
txt = strtrim(txt);
txt = txt(strlength(txt) > 0 & ~startsWith(txt, '//'));
vals = hex2dec(char(txt));
if signed
    m = 2^bits;
    vals(vals >= m/2) = vals(vals >= m/2) - m;
end
vals = vals(:);
end
