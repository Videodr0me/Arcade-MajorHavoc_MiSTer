-- Atari Analog Vector Generator (AVG) by Videodr0me 2026
--
-- The original 256x4 state PROM is loaded from the MRA.
-- The sequencer steps at 1.512 MHz once its requested byte is ready.
-- Normalization and binary scaling continue at 12.096 MHz.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity major_havoc_avg_core is
	Port (  avg_data_valid : in STD_LOGIC;
			vgrst : in STD_LOGIC;
			vggo : in STD_LOGIC;
			halted : out STD_LOGIC;
			halt_event : out STD_LOGIC;
			xout : out  STD_LOGIC_VECTOR (14 downto 0);
			yout : out  STD_LOGIC_VECTOR (14 downto 0);
        	zout : out  STD_LOGIC_VECTOR (7 downto 0);
	        color_index : out STD_LOGIC_VECTOR (4 downto 0);
	        color_data_in : in STD_LOGIC_VECTOR (3 downto 0);
	        colorout : out STD_LOGIC_VECTOR (3 downto 0);
	        map_select : out STD_LOGIC_VECTOR (1 downto 0);
	        sparkle_seed : in STD_LOGIC_VECTOR (2 downto 0);
        	is_dot : out STD_LOGIC;
			clken: in STD_LOGIC;
			master_ce: in STD_LOGIC;
        	clk : in  STD_LOGIC;

			avg_addr_out : out STD_LOGIC_VECTOR(13 downto 0);
			avg_data_in  : in  STD_LOGIC_VECTOR(7 downto 0);

			prom_clk  : in std_logic;
			prom_addr : in std_logic_vector(7 downto 0);
			prom_data : in std_logic_vector(3 downto 0);
			prom_wr   : in std_logic
		);
end major_havoc_avg_core;

-- The AVG reads each word high byte first. The wrapper swaps A0 so LATCH 1
-- receives D15:D8 and the opcode before LATCH 0 receives D7:D0.
--
--  Instruction               D15:D13   D12
--    VCTR  (draw long)          000
--    HALT                       001
--    SVEC  (draw short)         010
--    STAT                       011       0
--    SCALE                      011       1
--    CENTER                     100
--    JSRL  (call subroutine)    101
--    RTSL  (return)             110
--    JMPL  (jump)               111

architecture Behavioral of major_havoc_avg_core is
	type stackarraytype is array (natural range <>) of std_logic_vector(13 downto 0);

	-- State PROM 136002-125 at 6C (SP-252 sheet 6B).
	--
	-- Address: A7=NORMAL_A7, A6..A4=OP2..OP0, A3..A0=F3..F0.
	-- Data: O4..O1. O4=1 selects a latch/strobe action and O3..O1
	-- select the action number:
	--
	--   $8 = LATCH 0  (load DVY low byte)
	--   $9 = LATCH 1  (load DVY high byte + opcode)
	--   $A = LATCH 2  (load DVX low byte)
	--   $B = LATCH 3  (load DVX high byte + intensity)
	--   $C = STROBE 0 (normalize / push PC)
	--   $D = STROBE 1 (scale / SP adjust)
	--   $E = STROBE 2 (load STAT or PC for JMP/JSR/RTS)
	--   $F = STROBE 3 (GO draw / HALT / CENTER)
	--
	-- O4=0 performs no latch or strobe action.
	type prom_array_t is array (0 to 255) of std_logic_vector(3 downto 0);
	signal avg_prom : prom_array_t;

	signal pc: STD_LOGIC_VECTOR(13 downto 0);
	signal instruction: STD_LOGIC_VECTOR(15 downto 0);
	signal operand: STD_LOGIC_VECTOR(15 downto 0);
	signal stack: stackarraytype(3 downto 0);
	signal sp: STD_LOGIC_VECTOR(1 downto 0);
	signal memory_din: STD_LOGIC_VECTOR(7 downto 0);
	signal memory_addr: STD_LOGIC_VECTOR(13 downto 0);

	signal vec_dx: STD_LOGIC_VECTOR(12 downto 0);
	signal vec_dx_drawer: STD_LOGIC_VECTOR(12 downto 0);
	signal vec_dy: STD_LOGIC_VECTOR(12 downto 0);
	signal vec_zero: STD_LOGIC;
	signal vec_abort: STD_LOGIC;
	signal vec_draw: STD_LOGIC;
	signal vec_done: STD_LOGIC;
	signal intensity: STD_LOGIC_VECTOR(7 downto 0);
	signal intens_mod: STD_LOGIC_VECTOR(2 downto 0);
	signal color_index_reg: STD_LOGIC_VECTOR(3 downto 0);
	signal active_color: STD_LOGIC_VECTOR(3 downto 0);
	signal map_reg: STD_LOGIC_VECTOR(1 downto 0);
	signal xflip_reg: STD_LOGIC;
	signal sparkle_reg: STD_LOGIC;
	signal sparkle_shift: STD_LOGIC_VECTOR(7 downto 0);
	signal sparkle_palette: STD_LOGIC_VECTOR(3 downto 0);
	signal halt_event_reg: STD_LOGIC;
	-- Linear scale changes the distance moved per master clock without
	-- changing the vector timer.
	signal linear_scale_reg: STD_LOGIC_VECTOR(7 downto 0);
	-- Binary scale selects how many timer-fill shifts run before drawing.
	signal bin_scale: STD_LOGIC_VECTOR(2 downto 0);

	signal prom_state: STD_LOGIC_VECTOR(3 downto 0);
	signal op: STD_LOGIC_VECTOR(2 downto 0);
	signal halt_flag: STD_LOGIC;
	signal go_flag: STD_LOGIC;

	-- Normalization stops at a sign change, after 15 shifts, or when
	-- scaling or drawing starts.
	signal norm_active: STD_LOGIC;
	signal norm_count: STD_LOGIC_VECTOR(3 downto 0);
	-- VCTR uses the full timer; SVEC uses its low eight bits.
	signal hw_timer: STD_LOGIC_VECTOR(14 downto 0);
	signal is_svec: STD_LOGIC;
	signal binscale_active: STD_LOGIC;
	signal binscale_count: STD_LOGIC_VECTOR(2 downto 0);

begin
	avg_addr_out <= memory_addr;
	memory_din <= avg_data_in;

	-- Color RAM is active-low: strong red, fine red, green, blue.
	active_color <= not color_data_in;
	sparkle_palette <= sparkle_shift(0) & sparkle_shift(2)
	                  & sparkle_shift(4) & sparkle_shift(6);
	color_index <= ("01111" + ("0" & sparkle_palette))
	               when sparkle_reg='1' else ("0" & color_index_reg);
	colorout <= "0000" when halt_flag='1' else active_color;
	map_select <= map_reg;
	halt_event <= halt_event_reg;
	-- The board complements ten X bits, giving -X-1. With three extra
	-- fractional bits, the same operation is -X-8.
	vec_dx_drawer <= (not vec_dx) - "0000000000111"
	                 when xflip_reg='1' else vec_dx;

	process (prom_clk) begin
		if prom_clk'event and prom_clk='1' then
			if prom_wr='1' then
				avg_prom(conv_integer(prom_addr)) <= prom_data;
			end if;
		end if;
	end process;

	vectordrawer: entity work.vector_drawer port map (
		clk => clk,
		master_ce => master_ce,
		hw_timer => hw_timer,
		is_svec => is_svec,
		linear_scale => linear_scale_reg,
		rel_x => vec_dx_drawer,
		rel_y => vec_dy,
		zero => vec_zero,
		abort_draw => vec_abort,
		draw => vec_draw,
		done => vec_done,
		is_dot => is_dot,
		xout => xout,
		yout => yout
	);

	-- State-PROM sequencer.
	process (clk)
		variable prom_addr : std_logic_vector(7 downto 0);
		variable next_state : std_logic_vector(3 downto 0);
		variable running : std_logic;
	begin
		if clk'event and clk='1' then
			-- Commands remain asserted until the next drawer tick.
			if master_ce='1' then
				vec_zero<='0';
				vec_abort<='0';
				vec_draw<='0';
			end if;
			halt_event_reg<='0';

			if clken='1' then
				if vgrst='1' then
					pc<="00000000000000";
					instruction<=x"0000";
					operand<=x"0000";
					prom_state<=x"0";
					op<="000";
					halt_flag<='1';
					go_flag<='0';
					norm_active<='0';
					norm_count<="0000";
					sp<="00";
					color_index_reg<="0000";
					map_reg<="00";
					xflip_reg<='0';
					sparkle_reg<='0';
					sparkle_shift<=(others=>'0');
					intensity<=(others=>'0');
					intens_mod<=(others=>'0');
					linear_scale_reg<=(others=>'0');
					bin_scale<="000";
					vec_dx<=(others=>'0');
					vec_dy<=(others=>'0');
					hw_timer<=(others=>'0');
					is_svec<='0';
					binscale_active<='0';
					binscale_count<="000";
					vec_zero<='1';
					vec_abort<='0';
					vec_draw<='0';
				elsif vggo='1' then
					-- VGGO aborts the current list and restarts at byte zero.
					pc<=(others=>'0');
					sp<="00";
					halt_flag<='0';
					go_flag<='0';
					prom_state<=x"0";
					norm_active<='0';
					binscale_active<='0';
					intens_mod<="000";
					vec_abort<='1';
				elsif halt_flag='1' then
					pc<=(others=>'0');
					vec_zero<='1';

				elsif avg_data_valid='0' then
					-- Wait until the requested byte is ready.
					null;

				else
					if sparkle_reg='1' and go_flag='1' then
						if sparkle_shift(6 downto 0)="1111111" then
							sparkle_shift<=(others=>'0');
						else
							sparkle_shift<=sparkle_shift(6 downto 0)
							               & (sparkle_shift(6) xor
							                  sparkle_shift(5) xor '1');
						end if;
					end if;

					if go_flag='1' and vec_done='1' then
						go_flag <= '0';
					end if;

					-- A7 is high only while neither halted nor drawing.
					running := not halt_flag and not go_flag;
					prom_addr := running & op & prom_state;

					next_state := avg_prom(conv_integer(prom_addr));

					if next_state(3)='1' then
						case next_state(2 downto 0) is

							when "001" =>
								-- LATCH 1 also clears the second word and modifier.
								instruction(15 downto 8) <= memory_din;
								op <= memory_din(7 downto 5);
								instruction(7 downto 0) <= (others => '0');
								operand(11 downto 0) <= (others => '0');
								operand(12) <= '0';
								intens_mod <= "000";
								pc <= pc + "00000000000001";

							when "000" =>
								-- LATCH 0
								instruction(7 downto 0) <= memory_din;
								pc <= pc + "00000000000001";

							when "011" =>
								-- LATCH 3
								operand(15 downto 8) <= memory_din;
								pc <= pc + "00000000000001";

							when "010" =>
								-- LATCH 2
								operand(7 downto 0) <= memory_din;
								pc <= pc + "00000000000001";

							when "100" =>
								-- STROBE 0
								if op="101" then -- JSRL: push PC
									if (sp="00") then stack(0)<=pc; end if;
									if (sp="01") then stack(1)<=pc; end if;
									if (sp="10") then stack(2)<=pc; end if;
									if (sp="11") then stack(3)<=pc; end if;
								else
									-- VCTR, SVEC, and CENTER start normalization.
									if op="000" or op="010" or op="100" then
										norm_active <= '1';
										norm_count <= "0000";
										hw_timer <= (others => '0');
										is_svec <= op(1);
									end if;
								end if;

							when "101" =>
								-- STROBE 1
								if op="101" then    -- JSRL: sp++
									sp <= sp + "01";
								elsif op="110" then -- RTSL: sp--
									sp <= sp - "01";
								elsif op="000" or op="010" then
									-- VCTR and SVEC stop normalization and apply
									-- binary scale.
									norm_active <= '0';
									if bin_scale /= "000" then
										binscale_active <= '1';
										binscale_count <= "000";
									end if;
								end if;

							when "110" =>
								-- STROBE 2
								if op="011" then
									-- D12 selects STAT or SCALE.
									if instruction(12)='0' then
										color_index_reg <= instruction(3 downto 0);
										intensity <= instruction(7 downto 4) & "0000";
										map_reg <= instruction(9 downto 8);
										xflip_reg <= instruction(10);
										sparkle_reg <= instruction(11);
										if instruction(11)='1' then
											sparkle_shift <= '0' & sparkle_seed
											                 & instruction(0)
											                 & instruction(1)
											                 & instruction(2)
											                 & instruction(3);
										end if;
									else
										linear_scale_reg <= instruction(7 downto 0);
										bin_scale <= instruction(10 downto 8);
									end if;

								elsif op="101" or op="111" then
									-- JSRL and JMPL use all 13 word-address bits.
									pc(13 downto 1) <= instruction(12 downto 0);
									pc(0) <= '0';
								elsif op="110" then
									-- STROBE 1 already decremented SP, so this is
									-- the return entry.
									if (sp="00") then pc<=stack(0); end if;
									if (sp="01") then pc<=stack(1); end if;
									if (sp="10") then pc<=stack(2); end if;
									if (sp="11") then pc<=stack(3); end if;
								end if;

							when "111" =>
								-- STROBE 3
								if op="000" or op="010" then
									-- Start VCTR or SVEC.
									norm_active <= '0';
									vec_dy <= instruction(12 downto 0);
									vec_dx <= operand(12 downto 0);
									intens_mod <= operand(15 downto 13);
									vec_draw <= '1';
									go_flag <= '1';
								elsif op="001" then
									halt_flag <= '1';
									halt_event_reg <= '1';
								elsif op="100" then
									-- CENTER starts a zero-motion draw so its
									-- timer still runs.
									norm_active <= '0';
									vec_dx <= (others => '0');
									vec_dy <= (others => '0');
									intens_mod <= "000";
									vec_zero <= '1';
									vec_draw <= '1';
									go_flag <= '1';
								end if;

							when others => null;
						end case;
					end if;
					prom_state <= next_state;

				end if;
			end if;

			-- Normalization runs at 12.096 MHz, independent of the sequencer.
			if master_ce='1' and norm_active='1' then
				-- Stop when either displacement changes sign or after 15 shifts.
				if instruction(12) /= instruction(11)
				   or operand(12) /= operand(11)
				   or norm_count >= "1111" then
					norm_active <= '0';
					if is_svec='1' then
						hw_timer(14 downto 8) <= (others => '0');
					end if;
				else
					instruction(12 downto 1) <= instruction(11 downto 0);
					instruction(0) <= '0';
					operand(12 downto 1) <= operand(11 downto 0);
					operand(0) <= '0';
					-- Shift ones into the timer; SVEC also forces bit 7 high.
					hw_timer(14) <= '1';
					hw_timer(13 downto 8) <= hw_timer(14 downto 9);
					if is_svec='1' then
						hw_timer(7) <= '1';
					else
						hw_timer(7) <= hw_timer(8);
					end if;
					hw_timer(6 downto 0) <= hw_timer(7 downto 1);
					norm_count <= norm_count + "0001";
				end if;
			end if;

			-- Binary scaling also runs independently at 12.096 MHz.
			if master_ce='1' and binscale_active='1' then
				if binscale_count >= bin_scale then
					binscale_active <= '0';
					if is_svec='1' then
						hw_timer(14 downto 8) <= (others => '0');
					end if;
				else
					-- Use the same timer fill as normalization.
					hw_timer(14) <= '1';
					hw_timer(13 downto 8) <= hw_timer(14 downto 9);
					if is_svec='1' then
						hw_timer(7) <= '1';
					else
						hw_timer(7) <= hw_timer(8);
					end if;
					hw_timer(6 downto 0) <= hw_timer(7 downto 1);
					binscale_count <= binscale_count + "001";
				end if;
			end if;

		end if;
	end process;

	-- Register PC as the next memory address.
	process (clk) begin
		if clk'event and clk='1' then
			memory_addr <= pc;
		end if;
	end process;

	halted <= halt_flag;

	-- Modifier 1 uses STAT intensity; other values select multiples of 32.
	zout <= intensity when intens_mod="001" else intens_mod & "00000";

end Behavioral;
