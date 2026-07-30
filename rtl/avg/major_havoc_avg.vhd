--=============================================================================
--  Atari Major Havoc Analog Vector Generator integration
--
--  Written 2026 by Videodr0me
--
--  Alpha has priority when sharing vector memory with the AVG.
--  Requests and replies are synchronized between the independent 10.000 MHz
--  CPU, 12.096 MHz AVG, and 50 MHz memory clocks.
--=============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity major_havoc_avg is
	port (
		host_clk          : in  std_logic;
		cpu_clk           : in  std_logic;
		avg_clk           : in  std_logic;
		host_reset        : in  std_logic;
		cpu_reset         : in  std_logic;
		avg_reset         : in  std_logic;
		master_ce         : in  std_logic;
		sequencer_ce      : in  std_logic;
		cpu_avg_reset     : in  std_logic;
		cpu_avg_go        : in  std_logic;
		sparkle_seed      : in  std_logic_vector(2 downto 0);

		cpu_cycle         : in  std_logic;
		cpu_cs            : in  std_logic;
		cpu_rw            : in  std_logic;
		cpu_addr          : in  std_logic_vector(13 downto 0);
		cpu_data_in       : in  std_logic_vector(7 downto 0);
		cpu_data_out      : out std_logic_vector(7 downto 0);
		cpu_ready         : out std_logic;

		color_wr          : in  std_logic;
		color_addr        : in  std_logic_vector(4 downto 0);
		color_data        : in  std_logic_vector(7 downto 0);

		vector_rom_wr     : in  std_logic;
		vector_rom_addr   : in  std_logic_vector(12 downto 0);
		vector_rom_data   : in  std_logic_vector(7 downto 0);
		bank_rom_wr       : in  std_logic;
		bank_rom_addr     : in  std_logic_vector(14 downto 0);
		bank_rom_data     : in  std_logic_vector(7 downto 0);
		state_prom_wr     : in  std_logic;
		state_prom_addr   : in  std_logic_vector(7 downto 0);
		state_prom_data   : in  std_logic_vector(3 downto 0);

		halted            : out std_logic;
		halt_event        : out std_logic;
		x_out             : out std_logic_vector(14 downto 0);
		y_out             : out std_logic_vector(14 downto 0);
		z_out             : out std_logic_vector(7 downto 0);
		color_out         : out std_logic_vector(3 downto 0);
		is_dot_out        : out std_logic
	);
end entity;

architecture rtl of major_havoc_avg is
	type vector_ram_t is array (0 to 4095) of std_logic_vector(7 downto 0);
	type vector_rom_t is array (0 to 8191) of std_logic_vector(7 downto 0);
	type bank_rom_t is array (0 to 32767) of std_logic_vector(7 downto 0);
	type color_ram_t is array (0 to 31) of std_logic_vector(7 downto 0);

	signal vector_ram : vector_ram_t;
	signal vector_rom : vector_rom_t;
	signal bank_rom   : bank_rom_t;
	signal color_ram  : color_ram_t := (others => (others => '1'));

	attribute ramstyle : string;
	attribute ramstyle of vector_ram : signal is "M10K";
	attribute ramstyle of vector_rom : signal is "M10K";
	attribute ramstyle of bank_rom   : signal is "M10K";

	signal avg_addr       : std_logic_vector(13 downto 0);
	signal avg_fetch_addr : std_logic_vector(13 downto 0);
	signal avg_data       : std_logic_vector(7 downto 0);
	signal avg_data_valid : std_logic;
	signal map_select     : std_logic_vector(1 downto 0);
	signal color_index    : std_logic_vector(4 downto 0);
	signal color_ram_q    : std_logic_vector(3 downto 0);

	signal cpu_req_toggle       : std_logic := '0';
	signal cpu_req_addr_hold    : std_logic_vector(13 downto 0) := (others => '0');
	signal cpu_req_data_hold    : std_logic_vector(7 downto 0) := (others => '0');
	signal cpu_req_rw_hold      : std_logic := '1';
	signal cpu_req_inflight     : std_logic := '0';
	signal cpu_response_valid   : std_logic := '0';
	signal cpu_response_data    : std_logic_vector(7 downto 0) := (others => '0');
	signal cpu_resp_toggle_meta : std_logic := '0';
	signal cpu_resp_toggle_sync : std_logic := '0';
	signal cpu_resp_toggle_seen : std_logic := '0';
	signal cpu_resp_data_meta   : std_logic_vector(7 downto 0) := (others => '0');
	signal cpu_resp_data_sync   : std_logic_vector(7 downto 0) := (others => '0');

	signal color_req_toggle    : std_logic := '0';
	signal color_addr_hold     : std_logic_vector(4 downto 0) := (others => '0');
	signal color_data_hold     : std_logic_vector(7 downto 0) := (others => '0');
	signal go_req_toggle       : std_logic := '0';
	signal reset_req_toggle    : std_logic := '0';

	signal avg_req_toggle       : std_logic := '0';
	signal avg_req_key_hold     : std_logic_vector(15 downto 0) := (others => '0');
	signal avg_req_inflight     : std_logic := '0';
	signal avg_cached_valid     : std_logic := '0';
	signal avg_cached_key       : std_logic_vector(15 downto 0) := (others => '0');
	signal avg_cached_data      : std_logic_vector(7 downto 0) := (others => '0');
	signal avg_current_key      : std_logic_vector(15 downto 0);
	signal avg_resp_toggle_meta : std_logic := '0';
	signal avg_resp_toggle_sync : std_logic := '0';
	signal avg_resp_toggle_seen : std_logic := '0';
	signal avg_resp_data_meta   : std_logic_vector(7 downto 0) := (others => '0');
	signal avg_resp_data_sync   : std_logic_vector(7 downto 0) := (others => '0');
	signal avg_response_discard : std_logic := '0';
	signal avg_hold_active      : std_logic := '0';
	signal avg_refetch_delay    : std_logic := '0';
	signal core_sequencer_ce    : std_logic;

	signal cpu_req_toggle_meta_h : std_logic := '0';
	signal cpu_req_toggle_sync_h : std_logic := '0';
	signal cpu_req_toggle_stable_h : std_logic := '0';
	signal cpu_req_toggle_seen_h : std_logic := '0';
	signal cpu_req_addr_meta_h   : std_logic_vector(13 downto 0) := (others => '0');
	signal cpu_req_addr_sync_h   : std_logic_vector(13 downto 0) := (others => '0');
	signal cpu_req_data_meta_h   : std_logic_vector(7 downto 0) := (others => '0');
	signal cpu_req_data_sync_h   : std_logic_vector(7 downto 0) := (others => '0');
	signal cpu_req_rw_meta_h     : std_logic := '1';
	signal cpu_req_rw_sync_h     : std_logic := '1';
	signal cpu_resp_toggle_h     : std_logic := '0';
	signal cpu_resp_data_h       : std_logic_vector(7 downto 0) := (others => '0');
	signal cpu_cs_meta_h         : std_logic := '0';
	signal cpu_cs_sync_h         : std_logic := '0';
	signal cpu_owner_h           : std_logic := '0';
	signal cpu_owner_ack_meta_h  : std_logic := '0';
	signal cpu_owner_ack_sync_h  : std_logic := '0';

	signal avg_req_toggle_meta_h : std_logic := '0';
	signal avg_req_toggle_sync_h : std_logic := '0';
	signal avg_req_toggle_stable_h : std_logic := '0';
	signal avg_req_toggle_seen_h : std_logic := '0';
	signal avg_req_key_meta_h    : std_logic_vector(15 downto 0) := (others => '0');
	signal avg_req_key_sync_h    : std_logic_vector(15 downto 0) := (others => '0');
	signal avg_resp_toggle_h     : std_logic := '0';
	signal avg_resp_data_h       : std_logic_vector(7 downto 0) := (others => '0');

	constant SERVICE_RAM  : std_logic_vector(1 downto 0) := "00";
	constant SERVICE_ROM  : std_logic_vector(1 downto 0) := "01";
	constant SERVICE_BANK : std_logic_vector(1 downto 0) := "10";

	signal cpu_service_issue          : std_logic;
	signal avg_service_issue          : std_logic;
	signal service_ram_addr           : std_logic_vector(11 downto 0);
	signal service_rom_addr           : std_logic_vector(12 downto 0);
	signal service_bank_addr          : std_logic_vector(14 downto 0);
	signal vector_ram_q               : std_logic_vector(7 downto 0);
	signal vector_rom_q               : std_logic_vector(7 downto 0);
	signal bank_rom_q                 : std_logic_vector(7 downto 0);
	signal service_response_pending   : std_logic := '0';
	signal service_response_cpu       : std_logic := '0';
	signal service_response_write_ram : std_logic := '0';
	signal service_response_space     : std_logic_vector(1 downto 0) := SERVICE_RAM;
	signal service_response_write_data : std_logic_vector(7 downto 0) :=
		(others => '0');
	signal service_publish_pending : std_logic := '0';
	signal service_publish_cpu     : std_logic := '0';

	signal color_toggle_meta_a : std_logic := '0';
	signal color_toggle_sync_a : std_logic := '0';
	signal color_toggle_stable_a : std_logic := '0';
	signal color_toggle_seen_a : std_logic := '0';
	signal color_addr_meta_a   : std_logic_vector(4 downto 0) := (others => '0');
	signal color_addr_sync_a   : std_logic_vector(4 downto 0) := (others => '0');
	signal color_data_meta_a   : std_logic_vector(7 downto 0) := (others => '0');
	signal color_data_sync_a   : std_logic_vector(7 downto 0) := (others => '0');
	signal go_toggle_meta_a    : std_logic := '0';
	signal go_toggle_sync_a    : std_logic := '0';
	signal go_toggle_seen_a    : std_logic := '0';
	signal reset_toggle_meta_a : std_logic := '0';
	signal reset_toggle_sync_a : std_logic := '0';
	signal reset_toggle_seen_a : std_logic := '0';
	signal go_pending          : std_logic := '0';
	signal reset_pending       : std_logic := '0';
	signal avg_go_core         : std_logic;
	signal avg_reset_core      : std_logic;
	signal cpu_owner_meta_a    : std_logic := '0';
	signal cpu_owner_sync_a    : std_logic := '0';
	signal sparkle_seed_meta_a : std_logic_vector(2 downto 0) := (others => '0');
	signal sparkle_seed_sync_a : std_logic_vector(2 downto 0) := (others => '0');

	constant SYNCHRONIZER_ATTRIBUTE : string :=
		"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS";
	attribute altera_attribute : string;
	-- Request and reply values stay unchanged while crossing clock domains.
	attribute altera_attribute of
		cpu_resp_toggle_meta, cpu_resp_toggle_sync : signal is
		SYNCHRONIZER_ATTRIBUTE;
	attribute altera_attribute of
		avg_resp_toggle_meta, avg_resp_toggle_sync : signal is
		SYNCHRONIZER_ATTRIBUTE;
	attribute altera_attribute of
		cpu_req_toggle_meta_h, cpu_req_toggle_sync_h : signal is
		SYNCHRONIZER_ATTRIBUTE;
	attribute altera_attribute of
		avg_req_toggle_meta_h, avg_req_toggle_sync_h : signal is
		SYNCHRONIZER_ATTRIBUTE;
	attribute altera_attribute of
		color_toggle_meta_a, color_toggle_sync_a : signal is
		SYNCHRONIZER_ATTRIBUTE;
	attribute altera_attribute of
		cpu_cs_meta_h, cpu_cs_sync_h,
		cpu_owner_ack_meta_h, cpu_owner_ack_sync_h,
		go_toggle_meta_a, go_toggle_sync_a,
		reset_toggle_meta_a, reset_toggle_sync_a,
		cpu_owner_meta_a, cpu_owner_sync_a : signal is
		SYNCHRONIZER_ATTRIBUTE;
begin
	-- The AVG reads each word high byte first, so swap A0 only for AVG fetches.
	avg_fetch_addr <= avg_addr(13 downto 1) & not avg_addr(0);
	avg_current_key <= map_select & avg_fetch_addr;
	avg_data <= avg_cached_data;
	avg_data_valid <= '1' when avg_cached_valid='1'
	                             and avg_cached_key=avg_current_key
	                             and avg_hold_active='0'
	                             and cpu_owner_sync_a='0'
	                             and avg_reset_core='0'
	                  else '0';

	cpu_service_issue <= '1'
		when host_reset='0'
		  and service_response_pending='0'
		  and service_publish_pending='0'
		  and vector_rom_wr='0'
		  and bank_rom_wr='0'
		  and cpu_owner_h='1'
		  and cpu_owner_ack_sync_h='1'
		  and avg_req_toggle_stable_h = avg_req_toggle_seen_h
		  and cpu_req_toggle_stable_h /= cpu_req_toggle_seen_h
		else '0';

	avg_service_issue <= '1'
		when host_reset='0'
		  and service_response_pending='0'
		  and service_publish_pending='0'
		  and vector_rom_wr='0'
		  and bank_rom_wr='0'
		  and avg_req_toggle_stable_h /= avg_req_toggle_seen_h
		  and ((cpu_owner_h='0'
		        and cpu_req_toggle_stable_h=cpu_req_toggle_seen_h)
		       or cpu_owner_h='1')
		else '0';

	service_ram_addr <= cpu_req_addr_sync_h(11 downto 0)
		when cpu_service_issue='1'
		else avg_req_key_sync_h(11 downto 0);

	service_rom_addr <= '0' & cpu_req_addr_sync_h(11 downto 0)
		when cpu_service_issue='1'
		  and cpu_req_addr_sync_h(13 downto 12)="01"
		else '1' & cpu_req_addr_sync_h(11 downto 0)
		when cpu_service_issue='1'
		else '0' & avg_req_key_sync_h(11 downto 0);

	service_bank_addr <=
		avg_req_key_sync_h(15 downto 14) & avg_req_key_sync_h(12 downto 0);

	cpu_data_out <= cpu_response_data;
	cpu_ready <= '1' when cpu_cs='0' else cpu_response_valid;
	color_ram_q <= color_ram(to_integer(unsigned(color_index)))(3 downto 0);

	-- Alpha ownership pauses the PROM sequencer. Normalization, scaling,
	-- and an active draw continue on the master clock.
	core_sequencer_ce <= '1' when avg_reset='1' else
		sequencer_ce and not cpu_owner_sync_a and
		(not avg_hold_active or go_pending or reset_pending);
	avg_go_core <= go_pending and core_sequencer_ce;
	avg_reset_core <= avg_reset or (reset_pending and core_sequencer_ce);

	core : entity work.major_havoc_avg_core
		port map (
			clk             => avg_clk,
			master_ce       => master_ce,
			clken           => core_sequencer_ce,
			avg_data_valid  => avg_data_valid,
			vgrst           => avg_reset_core,
			vggo            => avg_go_core,
			halted          => halted,
			halt_event      => halt_event,
			xout            => x_out,
			yout            => y_out,
			zout            => z_out,
			color_index     => color_index,
			color_data_in   => color_ram_q,
			colorout        => color_out,
			map_select      => map_select,
			sparkle_seed    => sparkle_seed_sync_a,
			is_dot          => is_dot_out,
			avg_addr_out    => avg_addr,
			avg_data_in     => avg_data,
			prom_clk        => host_clk,
			prom_addr       => state_prom_addr,
			prom_data       => state_prom_data,
			prom_wr         => state_prom_wr
		);

	-- Alpha requests and control pulses.
	process (cpu_clk)
	begin
		if rising_edge(cpu_clk) then
			cpu_resp_toggle_meta <= cpu_resp_toggle_h;
			cpu_resp_toggle_sync <= cpu_resp_toggle_meta;
			cpu_resp_data_meta <= cpu_resp_data_h;
			cpu_resp_data_sync <= cpu_resp_data_meta;

			if cpu_reset='1' then
				cpu_req_toggle <= '0';
				cpu_req_inflight <= '0';
				cpu_response_valid <= '0';
				cpu_response_data <= (others => '0');
				cpu_resp_toggle_seen <= '0';
				color_req_toggle <= '0';
				go_req_toggle <= '0';
				reset_req_toggle <= '0';
			else
				if cpu_resp_toggle_sync /= cpu_resp_toggle_seen then
					cpu_resp_toggle_seen <= cpu_resp_toggle_sync;
					cpu_response_data <= cpu_resp_data_sync;
					cpu_response_valid <= '1';
					cpu_req_inflight <= '0';
				end if;

				if cpu_cs='0' then
					cpu_response_valid <= '0';
				elsif cpu_cycle='1' and cpu_response_valid='1' then
					cpu_response_valid <= '0';
				end if;

				if cpu_cs='1' and cpu_req_inflight='0'
				   and cpu_response_valid='0' then
					cpu_req_addr_hold <= cpu_addr;
					cpu_req_data_hold <= cpu_data_in;
					cpu_req_rw_hold <= cpu_rw;
					cpu_req_toggle <= not cpu_req_toggle;
					cpu_req_inflight <= '1';
				end if;

				if color_wr='1' then
					color_addr_hold <= color_addr;
					color_data_hold <= color_data;
					color_req_toggle <= not color_req_toggle;
				end if;
				if cpu_avg_go='1' then
					go_req_toggle <= not go_req_toggle;
				end if;
				if cpu_avg_reset='1' then
					reset_req_toggle <= not reset_req_toggle;
				end if;
			end if;
		end if;
	end process;

	-- AVG requests, cached replies, and synchronized controls.
	process (avg_clk)
		variable response_arrived : boolean;
	begin
		if rising_edge(avg_clk) then
			response_arrived :=
				avg_resp_toggle_sync /= avg_resp_toggle_seen;

			avg_resp_toggle_meta <= avg_resp_toggle_h;
			avg_resp_toggle_sync <= avg_resp_toggle_meta;
			avg_resp_data_meta <= avg_resp_data_h;
			avg_resp_data_sync <= avg_resp_data_meta;

			color_toggle_meta_a <= color_req_toggle;
			color_toggle_sync_a <= color_toggle_meta_a;
			color_addr_meta_a <= color_addr_hold;
			color_addr_sync_a <= color_addr_meta_a;
			color_data_meta_a <= color_data_hold;
			color_data_sync_a <= color_data_meta_a;
			if color_toggle_meta_a=color_toggle_sync_a then
				color_toggle_stable_a <= color_toggle_sync_a;
			end if;
			go_toggle_meta_a <= go_req_toggle;
			go_toggle_sync_a <= go_toggle_meta_a;
			reset_toggle_meta_a <= reset_req_toggle;
			reset_toggle_sync_a <= reset_toggle_meta_a;
			cpu_owner_meta_a <= cpu_owner_h;
			cpu_owner_sync_a <= cpu_owner_meta_a;
			sparkle_seed_meta_a <= sparkle_seed;
			sparkle_seed_sync_a <= sparkle_seed_meta_a;

			if avg_reset='1' then
				avg_req_toggle <= '0';
				avg_req_inflight <= '0';
				avg_cached_valid <= '0';
				avg_cached_key <= (others => '0');
				avg_cached_data <= (others => '0');
				avg_resp_toggle_seen <= '0';
				avg_response_discard <= '0';
				avg_hold_active <= '0';
				avg_refetch_delay <= '0';
				color_toggle_stable_a <= '0';
				color_toggle_seen_a <= '0';
				go_toggle_seen_a <= '0';
				reset_toggle_seen_a <= '0';
				go_pending <= '0';
				reset_pending <= '0';
				cpu_owner_meta_a <= '0';
				cpu_owner_sync_a <= '0';
			else
				if color_toggle_stable_a /= color_toggle_seen_a then
					color_toggle_seen_a <= color_toggle_stable_a;
					color_ram(to_integer(unsigned(color_addr_sync_a))) <=
						color_data_sync_a;
				end if;

				if go_toggle_sync_a /= go_toggle_seen_a then
					go_toggle_seen_a <= go_toggle_sync_a;
					go_pending <= '1';
				elsif core_sequencer_ce='1' and go_pending='1' then
					go_pending <= '0';
				end if;

				if reset_toggle_sync_a /= reset_toggle_seen_a then
					reset_toggle_seen_a <= reset_toggle_sync_a;
					reset_pending <= '1';
				elsif core_sequencer_ce='1' and reset_pending='1' then
					reset_pending <= '0';
				end if;

				if response_arrived then
					avg_resp_toggle_seen <= avg_resp_toggle_sync;
					avg_req_inflight <= '0';
					avg_response_discard <= '0';
				end if;

				if cpu_owner_sync_a='1' or go_pending='1'
				   or reset_pending='1' then
					avg_cached_valid <= '0';
					avg_hold_active <= '1';

					if avg_req_inflight='1' and not response_arrived then
						avg_response_discard <= '1';
					end if;
					if go_pending='1' or reset_pending='1' then
						-- Wait one master tick before fetching again after
						-- VGGO or VGRST.
						avg_refetch_delay <= '1';
					end if;
				else
					if avg_refetch_delay='1' then
						avg_refetch_delay <= '0';
					end if;

					if response_arrived then
						if avg_response_discard='0' then
							avg_cached_key <= avg_req_key_hold;
							avg_cached_data <= avg_resp_data_sync;
							avg_cached_valid <= '1';
						else
							avg_cached_valid <= '0';
						end if;
					elsif avg_cached_valid='1'
					      and avg_cached_key /= avg_current_key then
						avg_cached_valid <= '0';
					end if;

					if avg_hold_active='1'
					   and avg_refetch_delay='0'
					   and avg_req_inflight='0'
					   and avg_cached_valid='1'
					   and avg_cached_key=avg_current_key then
						avg_hold_active <= '0';
					end if;
				end if;

				if cpu_owner_sync_a='0'
				   and go_pending='0'
				   and reset_pending='0'
				   and avg_refetch_delay='0'
				   and avg_req_inflight='0'
				   and (avg_cached_valid='0'
				        or avg_cached_key /= avg_current_key) then
					avg_req_key_hold <= avg_current_key;
					avg_req_toggle <= not avg_req_toggle;
					avg_req_inflight <= '1';
				end if;
			end if;
		end if;
	end process;

	process (host_clk)
	begin
		if rising_edge(host_clk) then
			vector_ram_q <= vector_ram(to_integer(unsigned(service_ram_addr)));
			vector_rom_q <= vector_rom(to_integer(unsigned(service_rom_addr)));
			bank_rom_q <= bank_rom(to_integer(unsigned(service_bank_addr)));

			if vector_rom_wr='1' then
				vector_rom(to_integer(unsigned(vector_rom_addr))) <=
					vector_rom_data;
			end if;

			if bank_rom_wr='1' then
				bank_rom(to_integer(unsigned(bank_rom_addr))) <= bank_rom_data;
			end if;

			if cpu_service_issue='1'
			   and cpu_req_rw_sync_h='0'
			   and cpu_req_addr_sync_h(13 downto 12)="00" then
				vector_ram(to_integer(unsigned(
					cpu_req_addr_sync_h(11 downto 0)))) <=
					cpu_req_data_sync_h;
			end if;
		end if;
	end process;

	-- Alpha has priority over new AVG reads from shared vector memory.
	process (host_clk)
	begin
		if rising_edge(host_clk) then
			cpu_req_toggle_meta_h <= cpu_req_toggle;
			cpu_req_toggle_sync_h <= cpu_req_toggle_meta_h;
			cpu_req_addr_meta_h <= cpu_req_addr_hold;
			cpu_req_addr_sync_h <= cpu_req_addr_meta_h;
			cpu_req_data_meta_h <= cpu_req_data_hold;
			cpu_req_data_sync_h <= cpu_req_data_meta_h;
			cpu_req_rw_meta_h <= cpu_req_rw_hold;
			cpu_req_rw_sync_h <= cpu_req_rw_meta_h;
			cpu_cs_meta_h <= cpu_cs;
			cpu_cs_sync_h <= cpu_cs_meta_h;
			cpu_owner_ack_meta_h <= cpu_owner_sync_a;
			cpu_owner_ack_sync_h <= cpu_owner_ack_meta_h;
			if cpu_req_toggle_meta_h=cpu_req_toggle_sync_h then
				cpu_req_toggle_stable_h <= cpu_req_toggle_sync_h;
			end if;

			avg_req_toggle_meta_h <= avg_req_toggle;
			avg_req_toggle_sync_h <= avg_req_toggle_meta_h;
			avg_req_key_meta_h <= avg_req_key_hold;
			avg_req_key_sync_h <= avg_req_key_meta_h;
			if avg_req_toggle_meta_h=avg_req_toggle_sync_h then
				avg_req_toggle_stable_h <= avg_req_toggle_sync_h;
			end if;

			if host_reset='1' then
				cpu_req_toggle_meta_h <= '0';
				cpu_req_toggle_sync_h <= '0';
				cpu_req_toggle_stable_h <= '0';
				cpu_req_toggle_seen_h <= '0';
				cpu_resp_toggle_h <= '0';
				cpu_resp_data_h <= (others => '0');
				cpu_cs_meta_h <= '0';
				cpu_cs_sync_h <= '0';
				cpu_owner_h <= '0';
				cpu_owner_ack_meta_h <= '0';
				cpu_owner_ack_sync_h <= '0';
				avg_req_toggle_meta_h <= '0';
				avg_req_toggle_sync_h <= '0';
				avg_req_toggle_stable_h <= '0';
				avg_req_toggle_seen_h <= '0';
				avg_resp_toggle_h <= '0';
				avg_resp_data_h <= (others => '0');
				service_response_pending <= '0';
				service_response_cpu <= '0';
				service_response_write_ram <= '0';
				service_response_space <= SERVICE_RAM;
				service_response_write_data <= (others => '0');
				service_publish_pending <= '0';
				service_publish_cpu <= '0';
			else
				-- Finish an outstanding AVG read before serving Alpha.
				if cpu_owner_h='0' then
					if cpu_owner_ack_sync_h='0'
					   and cpu_req_toggle_stable_h /=
					       cpu_req_toggle_seen_h then
						cpu_owner_h <= '1';
					end if;
				elsif cpu_cs_sync_h='0'
				      and cpu_req_toggle_stable_h =
				          cpu_req_toggle_seen_h
				      and not (service_response_pending='1'
				               and service_response_cpu='1')
				      and not (service_publish_pending='1'
				               and service_publish_cpu='1') then
					cpu_owner_h <= '0';
				end if;

				-- Hold reply data for one host clock before signaling ready.
				if service_publish_pending='1' then
					if service_publish_cpu='1' then
						cpu_resp_toggle_h <= not cpu_resp_toggle_h;
					else
						avg_resp_toggle_h <= not avg_resp_toggle_h;
					end if;
					service_publish_pending <= '0';
				elsif service_response_pending='1' then
					if service_response_cpu='1' then
						if service_response_write_ram='1' then
							cpu_resp_data_h <= service_response_write_data;
						elsif service_response_space=SERVICE_RAM then
							cpu_resp_data_h <= vector_ram_q;
						else
							cpu_resp_data_h <= vector_rom_q;
						end if;
					else
						case service_response_space is
							when SERVICE_RAM =>
								avg_resp_data_h <= vector_ram_q;
							when SERVICE_ROM =>
								avg_resp_data_h <= vector_rom_q;
							when others =>
								avg_resp_data_h <= bank_rom_q;
						end case;
					end if;
					service_response_pending <= '0';
					service_publish_pending <= '1';
					service_publish_cpu <= service_response_cpu;
				elsif cpu_service_issue='1' then
					cpu_req_toggle_seen_h <= cpu_req_toggle_stable_h;
					service_response_pending <= '1';
					service_response_cpu <= '1';
					service_response_write_data <= cpu_req_data_sync_h;

					if cpu_req_addr_sync_h(13 downto 12)="00" then
						service_response_space <= SERVICE_RAM;
						if cpu_req_rw_sync_h='0' then
							service_response_write_ram <= '1';
						else
							service_response_write_ram <= '0';
						end if;
					else
						service_response_space <= SERVICE_ROM;
						service_response_write_ram <= '0';
					end if;
				elsif avg_service_issue='1' then
					avg_req_toggle_seen_h <= avg_req_toggle_stable_h;
					service_response_pending <= '1';
					service_response_cpu <= '0';
					service_response_write_ram <= '0';

					if avg_req_key_sync_h(13 downto 12)="00" then
						service_response_space <= SERVICE_RAM;
					elsif avg_req_key_sync_h(13 downto 12)="01" then
						service_response_space <= SERVICE_ROM;
					else
						service_response_space <= SERVICE_BANK;
					end if;
				end if;
			end if;
		end if;
	end process;
end architecture;
