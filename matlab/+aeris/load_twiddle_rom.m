function rom = load_twiddle_rom(filepath)
%LOAD_TWIDDLE_ROM Load quarter-wave cosine ROM (N/4 x 16-bit signed Q15).
rom = aeris.read_mem_hex(filepath, 16, true);
end
