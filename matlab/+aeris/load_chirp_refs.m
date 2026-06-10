function refs = load_chirp_refs(p)
%LOAD_CHIRP_REFS Load matched-filter reference chirps from the FPGA .mem files.
%   refs.long_i / refs.long_q : 4 x 1024 (segment-major, as the RTL memory
%                               loader addresses them: {segment, sample})
%   refs.short_i / refs.short_q : 1 x 1024 (50 real samples, zero-padded —
%                               chirp_memory_loader_param.v:81-84)
refs.long_i = zeros(4, 1024);
refs.long_q = zeros(4, 1024);
for s = 1:4
    refs.long_i(s, :) = aeris.read_mem_hex(p.chirp_mem.long_i{s}, 16, true).';
    refs.long_q(s, :) = aeris.read_mem_hex(p.chirp_mem.long_q{s}, 16, true).';
end
si = aeris.read_mem_hex(p.chirp_mem.short_i, 16, true).';
sq = aeris.read_mem_hex(p.chirp_mem.short_q, 16, true).';
refs.short_i = [si, zeros(1, 1024 - numel(si))];
refs.short_q = [sq, zeros(1, 1024 - numel(sq))];
end
