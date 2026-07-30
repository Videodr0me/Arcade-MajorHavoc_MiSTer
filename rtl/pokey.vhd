--
-- A simulation model of Asteroids Deluxe hardware
-- Copyright (c) MikeJ - May 2004
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--

-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS CODE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- You are responsible for any legal issues arising from your use of this code.
--
-- The latest version of this file can be found at: www.fpgaarcade.com
--
-- Email support@fpgaarcade.com
--
-- Changes by Videodr0me, 2026:
-- - Corrected the poly5 feedback tap
-- - Added the nonlinear four-bit POKEY output DAC
-- - Corrected polynomial reset, sequencing, and per-channel sampling
-- - Corrected timer borrow, linked-channel, and high-pass latch timing
-- - Passes the Tempest POKEY protection check
--
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.std_logic_arith.all;
  use ieee.std_logic_unsigned.all;


entity pokey is
  port (
  ADDR      : in  std_logic_vector(3 downto 0);
  DIN       : in  std_logic_vector(7 downto 0);
  DOUT      : out std_logic_vector(7 downto 0);
  DOUT_OE_L : out std_logic;
  RW_L      : in  std_logic;
  CS        : in  std_logic; -- used as enable
  CS_L      : in  std_logic;
  AUDIO_OUT : out std_logic_vector(7 downto 0);
  PIN       : in  std_logic_vector(7 downto 0);
  ENA       : in  std_logic;
  CLK       : in  std_logic
  );
end;

architecture RTL of pokey is
  type  array_8x8   is array (0 to 7) of std_logic_vector(7 downto 0);
  type  array_4x8   is array (1 to 4) of std_logic_vector(7 downto 0);
  type  array_4x4   is array (1 to 4) of std_logic_vector(3 downto 0);
  type  array_4x6   is array (1 to 4) of std_logic_vector(5 downto 0);
  type  array_4x3   is array (1 to 4) of std_logic_vector(2 downto 0);
  type  array_2x17  is array (1 to 2) of std_logic_vector(16 downto 0);

  signal we                   : std_logic;
  signal oe                   : std_logic;
  signal ena_64k_15k          : std_logic;
  signal cnt_64k              : std_logic_vector(4 downto 0) := (others => '0');
  signal ena_64k              : std_logic := '0';
  signal cnt_15k              : std_logic_vector(6 downto 0) := (others => '0');
  signal ena_15k              : std_logic := '0';
  signal poly4                : std_logic_vector(3 downto 0) := "0001";
  signal poly5                : std_logic_vector(4 downto 0) := "00001";
  signal poly9                : std_logic_vector(8 downto 0) := "011111111";
  signal poly17               : std_logic_vector(16 downto 0) := "11111111101111111";
  signal poly4_history        : std_logic_vector(2 downto 0) := (others => '0');
  signal poly5_history        : std_logic_vector(2 downto 0) := (others => '0');
  signal poly9_history        : std_logic_vector(2 downto 0) := (others => '0');
  signal poly17_history       : std_logic_vector(2 downto 0) := (others => '0');
  signal poly4_sample         : std_logic_vector(4 downto 1);
  signal poly5_sample         : std_logic_vector(4 downto 1);
  signal poly_large_sample    : std_logic_vector(4 downto 1);

  -- Audio registers.
  signal audf                 : array_4x8 := (x"00",x"00",x"00",x"00");
  signal audc                 : array_4x8 := (x"00",x"00",x"00",x"00");
  signal audctl               : std_logic_vector(7 downto 0) := "00000000";
  signal skres                : std_logic_vector(7 downto 0);
  signal potgo                : std_logic;
  signal serout               : std_logic_vector(7 downto 0);
  signal irqen                : std_logic_vector(7 downto 0);
  -- POKEY has no reset pin; let RANDOM run before software initializes SKCTL.
  signal skctls               : std_logic_vector(7 downto 0) := x"03";
  signal reset                : std_logic;
  signal kbcode               : std_logic_vector(7 downto 0);
  signal random               : std_logic_vector(7 downto 0);
  signal serin                : std_logic_vector(7 downto 0);
  signal irqst                : std_logic_vector(7 downto 0);
  signal skstat               : std_logic_vector(7 downto 0);
  signal pot_fin              : std_logic;
  signal pot_cnt              : std_logic_vector(7 downto 0);
  signal pot_val              : array_8x8;
  signal pin_reg              : std_logic_vector(7 downto 0);
  signal pin_reg_gated        : std_logic_vector(7 downto 0);
  signal timer_clock          : std_logic_vector(4 downto 1);
  signal timer_count          : array_4x8 := (others => (others => '0'));
  signal timer_borrow_pipe    : array_4x3 := (others => (others => '0'));
  signal timer_borrow         : std_logic_vector(4 downto 1);
  signal timer_pulse          : std_logic_vector(4 downto 1);
  signal stimer_write         : std_logic;
  signal stimer_pipe          : std_logic_vector(2 downto 0) := (others => '0');
  signal stimer_reload        : std_logic;
  signal audio_clock          : std_logic_vector(4 downto 1);
  signal audio_sample         : std_logic_vector(4 downto 1);
  signal high_pass_sample     : std_logic_vector(4 downto 1) := (others => '0');
  signal channel_output       : std_logic_vector(4 downto 1);
  signal tone_gen_final       : std_logic_vector(4 downto 1) := (others => '0');

  function pokey_dac(volume : std_logic_vector(3 downto 0))
    return std_logic_vector is
  begin
    -- Rounded conductance of the four hardware volume-control branches.
    case volume is
      when x"0" => return "000000";
      when x"1" => return "000001";
      when x"2" => return "000101";
      when x"3" => return "000110";
      when x"4" => return "010000";
      when x"5" => return "010001";
      when x"6" => return "010101";
      when x"7" => return "010110";
      when x"8" => return "100110";
      when x"9" => return "100111";
      when x"A" => return "101011";
      when x"B" => return "101100";
      when x"C" => return "110110";
      when x"D" => return "110111";
      when x"E" => return "111011";
      when x"F" => return "111100";
      when others => return "000000";
    end case;
  end function;
begin

  p_we : process(RW_L, CS_L, CS, ENA)
  begin
    we <= (not CS_L) and CS and (not RW_L) and ENA;
  end process;

  p_oe : process(RW_L, CS_L, CS)
  begin
    oe <= (not CS_L) and CS and RW_L;
  end process;
  DOUT_OE_L <= not oe;

  p_ipreg : process
  begin
    wait until rising_edge(CLK);
    pin_reg <= PIN;
  end process;

  p_dividers : process
  begin
    wait until rising_edge(CLK);
    if (ENA = '1') then
      ena_64k <= '0';
      ena_15k <= '0';

      if reset = '1' then
        cnt_64k <= "11011"; -- 28 - 1
        cnt_15k <= "1110001"; -- 114 - 1
      else
        if cnt_64k = "00000" then
          cnt_64k <= "11011";
          ena_64k <= '1';
        else
          cnt_64k <= cnt_64k - "1";
        end if;

        if cnt_15k = "0000000" then
          cnt_15k <= "1110001";
          ena_15k <= '1';
        else
          cnt_15k <= cnt_15k - "1";
        end if;
      end if;
    end if;
  end process;

  p_ena_64k_15k : process(ena_64k, ena_15k, audctl)
  begin
    if (audctl(0) = '1') then
      ena_64k_15k <= ena_15k;
    else
      ena_64k_15k <= ena_64k;
    end if;
  end process;

  p_poly : process
  begin
    wait until rising_edge(CLK);
    if (ENA = '1') then
      if reset = '1' then
        -- Initialize the hardware-equivalent polynomial sequences.
        poly4  <= "0001";
        poly5  <= "00001";
        poly9  <= "011111111";
        poly17 <= "11111111101111111";
        poly4_history  <= (others => '0');
        poly5_history  <= (others => '0');
        poly9_history  <= (others => '0');
        poly17_history <= (others => '0');
      else
        poly4_history  <= poly4_history(1 downto 0) & poly4(0);
        poly5_history  <= poly5_history(1 downto 0) & poly5(0);
        poly9_history  <= poly9_history(1 downto 0) & poly9(0);
        poly17_history <= poly17_history(1 downto 0) & poly17(0);

        poly4 <= poly4(2 downto 0) & not (poly4(3) xor poly4(2));
        poly5 <= poly5(3 downto 0) & not (poly5(4) xor poly5(2));
        poly9 <= (poly9(0) xor poly9(5)) & poly9(8 downto 1);

        poly17(16) <= poly17(0);
        poly17(15 downto 8) <= poly17(16 downto 9);
        poly17(7) <= poly17(8) xor poly17(13);
        poly17(6 downto 0) <= poly17(7 downto 1);
      end if;
    end if;
  end process;

  p_random_mux : process(audctl, poly9, poly17)
  begin
    if (audctl(7) = '1') then
      random <= poly9(7 downto 0);
    else
      random <= poly17(15 downto 8);
    end if;
  end process;

  -- A noise bit reaches channels 1 through 4 one master clock apart.
  poly4_sample  <= poly4_history(2) & poly4_history(1) &
                   poly4_history(0) & poly4(0);
  poly5_sample  <= poly5_history(2) & poly5_history(1) &
                   poly5_history(0) & poly5(0);
  poly_large_sample <=
    poly9_history(2) & poly9_history(1) &
    poly9_history(0) & poly9(0) when audctl(7) = '1' else
    poly17_history(2) & poly17_history(1) &
    poly17_history(0) & poly17(0);

  p_wdata : process
  begin
    wait until rising_edge(CLK);
    potgo <= '0';

    if (we = '1') then
        case ADDR is
          when x"0" => audf(1)  <= DIN;
          when x"1" => audc(1)  <= DIN;
          when x"2" => audf(2)  <= DIN;
          when x"3" => audc(2)  <= DIN;
          when x"4" => audf(3)  <= DIN;
          when x"5" => audc(3)  <= DIN;
          when x"6" => audf(4)  <= DIN;
          when x"7" => audc(4)  <= DIN;
          when x"8" => audctl   <= DIN;
          when x"B" => potgo    <= '1';
          when x"F" => skctls   <= DIN;
          when others => null;
        end case;
    end if;
  end process;

  p_reset : process(skctls)
  begin
    -- SKCTL bits 1:0 both clear reset.
    reset <= '0';
    if (skctls(1 downto 0) = "00") then
      reset <= '1';
    end if;
  end process;

  p_rdata : process(oe, ADDR, pot_val, pin_reg_gated, kbcode, random, serin, irqst, skstat)
  begin
    DOUT <= x"00";
    if (oe = '1') then
      case ADDR IS
        when x"0" => DOUT <= pot_val(0);   -- pot 0
        when x"1" => DOUT <= pot_val(1);   -- pot 1
        when x"2" => DOUT <= pot_val(2);   -- pot 2
        when x"3" => DOUT <= pot_val(3);   -- pot 3
        when x"4" => DOUT <= pot_val(4);   -- pot 4
        when x"5" => DOUT <= pot_val(5);   -- pot 5
        when x"6" => DOUT <= pot_val(6);   -- pot 6
        when x"7" => DOUT <= pot_val(7);   -- pot 7
        when x"8" => DOUT <= pin_reg_gated;-- allpot
        when x"9" => DOUT <= (others => '0');
        when x"A" => DOUT <= random;
        when x"B" => DOUT <= x"FF";
        when x"C" => DOUT <= x"FF";
        when x"D" => DOUT <= (others => '0');
        when x"E" => DOUT <= (others => '0');
        when x"F" => DOUT <= (others => '0');
        when others => null;
      end case;
    end if;
  end process;

  p_pot_cnt : process
  begin
    wait until rising_edge(CLK);
    if (potgo = '1') then
      pot_cnt <= x"00";
    -- SKCTL bit 2 selects master-rate POT scanning.
    elsif ((ena_15k = '1') or (skctls(2) = '1')) and (ENA = '1') then
      pot_cnt <= pot_cnt + "1";
    end if;
  end process;

  p_pot_comp : process
  begin
    wait until rising_edge(CLK);
    if (reset = '1') then
      pot_fin <= '1';
    else
      if (potgo = '1') then
        pot_fin <= '0';
      elsif (pot_cnt = x"E4") then
        pot_fin <= '1';
      end if;
    end if;
  end process;

  p_pot_val : process
  begin
    wait until rising_edge(CLK);
    for i in 0 to 7 loop
      if pin_reg(i) = '1' then
        pot_val(i) <= x"00";
      else
        pot_val(i) <= x"E4";
      end if;
    end loop;
  end process;

  p_in_gate : process(pin_reg, reset, pot_fin)
  begin
    pin_reg_gated <= not pin_reg;
    if (reset = '1') or (pot_fin = '1') then
      pin_reg_gated <= x"00";
    end if;
  end process;

  timer_borrow(1) <= timer_borrow_pipe(1)(2);
  timer_borrow(2) <= timer_borrow_pipe(2)(2);
  timer_borrow(3) <= timer_borrow_pipe(3)(2);
  timer_borrow(4) <= timer_borrow_pipe(4)(2);

  stimer_write <= '1' when
    we = '1' and ADDR = x"9" else '0';
  stimer_reload <= stimer_pipe(2);
  timer_pulse <= timer_borrow when stimer_reload = '0' else "0000";

  p_timer_clocks : process(audctl, ena_64k_15k, timer_pulse)
  begin
    timer_clock <= (others => ena_64k_15k);

    if (audctl(6) = '1') then
      timer_clock(1) <= '1';
    end if;
    if (audctl(4) = '1') then
      timer_clock(2) <= timer_pulse(1);
    end if;

    if (audctl(5) = '1') then
      timer_clock(3) <= '1';
    end if;
    if (audctl(3) = '1') then
      timer_clock(4) <= timer_pulse(3);
    end if;
  end process;

  -- Each counter underflow takes three master clocks to reach the timer
  -- output. Linked low counters keep running and clock the high counter on
  -- every borrow; both counters reload only when the high counter borrows.
  p_tone_generators : process
    variable borrow_next : array_4x3;
    variable reload_timer : std_logic_vector(4 downto 1);
  begin
    wait until rising_edge(CLK);
    if (ENA = '1') then
      stimer_pipe <= stimer_pipe(1 downto 0) & stimer_write;

      for i in 1 to 4 loop
        borrow_next(i) := timer_borrow_pipe(i)(1 downto 0) & '0';
        reload_timer(i) := stimer_reload;
      end loop;

      if (audctl(4) = '0') then
        reload_timer(1) := reload_timer(1) or timer_pulse(1);
      else
        reload_timer(1) := reload_timer(1) or timer_pulse(2);
      end if;
      reload_timer(2) := reload_timer(2) or timer_pulse(2);

      if (audctl(3) = '0') then
        reload_timer(3) := reload_timer(3) or timer_pulse(3);
      else
        reload_timer(3) := reload_timer(3) or timer_pulse(4);
      end if;
      reload_timer(4) := reload_timer(4) or timer_pulse(4);

      for i in 1 to 4 loop
        if (reload_timer(i) = '1') then
          timer_count(i) <= audf(i);
        elsif (timer_clock(i) = '1') then
          if (timer_count(i) = x"00") then
            borrow_next(i)(0) := '1';
          end if;
          timer_count(i) <= timer_count(i) - "1";
        end if;

        if (stimer_reload = '1') then
          borrow_next(i) := (others => '0');
        end if;
      end loop;

      timer_borrow_pipe <= borrow_next;
    end if;
  end process;

  p_poly_gating : process(
    audc, poly4_sample, poly5_sample, poly_large_sample, timer_pulse)
  begin
    for i in 1 to 4 loop
      if (audc(i)(7) = '0') then
        audio_clock(i) <= poly5_sample(i) and timer_pulse(i);
      else
        audio_clock(i) <= timer_pulse(i);
      end if;

      if (audc(i)(6) = '1') then
        audio_sample(i) <= poly4_sample(i);
      else
        audio_sample(i) <= poly_large_sample(i);
      end if;
    end loop;
  end process;

  p_high_pass_filters : process(tone_gen_final, high_pass_sample)
  begin
    channel_output <= tone_gen_final;
    channel_output(1) <= tone_gen_final(1) xor high_pass_sample(1);
    channel_output(2) <= tone_gen_final(2) xor high_pass_sample(2);
  end process;

  p_audio_out : process
  begin
    wait until rising_edge(CLK);
    if (ENA = '1') then
      if (audctl(2) = '0') then
        high_pass_sample(1) <= '1';
      elsif (timer_pulse(3) = '1') then
        high_pass_sample(1) <= tone_gen_final(1);
      end if;

      if (audctl(1) = '0') then
        high_pass_sample(2) <= '1';
      elsif (timer_pulse(4) = '1') then
        high_pass_sample(2) <= tone_gen_final(2);
      end if;

      for i in 1 to 4 loop
        if audio_clock(i) = '1' then
          if audc(i)(5) = '1' then
            tone_gen_final(i) <= not tone_gen_final(i);
          else
            tone_gen_final(i) <= audio_sample(i);
          end if;
        end if;
      end loop;
    end if;
  end process;

  p_op_mixer : process
    variable vol : array_4x4;
    variable dac : array_4x6;
    variable sum12 : std_logic_vector(6 downto 0);
    variable sum34 : std_logic_vector(6 downto 0);
    variable sum : std_logic_vector(7 downto 0);
  begin
    wait until rising_edge(CLK);
    if (ENA = '1') then
      for i in 1 to 4 loop
        if (audc(i)(4) = '1') then -- Volume-only mode.
          vol(i) := audc(i)(3 downto 0);
        elsif (channel_output(i) = '1') then
          vol(i) := audc(i)(3 downto 0);
        else
          vol(i) := "0000";
        end if;
        dac(i) := pokey_dac(vol(i));
      end loop;

      sum12 := ('0' & dac(1)) + ('0' & dac(2));
      sum34 := ('0' & dac(3)) + ('0' & dac(4));
      sum := ('0' & sum12) + ('0' & sum34);
      AUDIO_OUT <= sum;
    end if;
  end process;

  -- Keyboard, serial, and IRQ functions are not implemented.
end architecture RTL;
