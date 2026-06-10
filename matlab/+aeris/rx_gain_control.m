function y = rx_gain_control(x, gain)
%RX_GAIN_CONTROL Bit-true digital gain stage (rx_gain_control.v).
%   y = RX_GAIN_CONTROL(x, gain) applies a power-of-two gain to 16-bit
%   data with saturation to [-32768, 32767]:
%     gain >= 0 : left shift by gain  (amplify)
%     gain <  0 : arithmetic right shift by |gain| (attenuate)
%   This is the stage the hybrid FPGA/STM32/GUI AGC drives (USB opcode
%   0x16); RTL encodes it as {direction, amount[2:0]}, range -7..+7.
if gain >= 0
    y = aeris.sat_int(x * 2^gain, 16);
else
    y = aeris.sat_int(aeris.asr(x, -gain), 16);
end
end
