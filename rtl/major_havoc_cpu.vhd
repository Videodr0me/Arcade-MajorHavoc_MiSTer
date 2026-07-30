--=============================================================================
--  MOS 6502 interface for Atari Major Havoc
--
--  Written 2026 by Videodr0me
--=============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity major_havoc_cpu is
	port (
		clk      : in  std_logic;
		reset_n  : in  std_logic;
		enable   : in  std_logic;
		ready    : in  std_logic;
		irq_n    : in  std_logic;
		nmi_n    : in  std_logic;
		data_in  : in  std_logic_vector(7 downto 0);
		address  : out std_logic_vector(15 downto 0);
		data_out : out std_logic_vector(7 downto 0);
		rw_n     : out std_logic;
		sync     : out std_logic
	);
end entity;

architecture rtl of major_havoc_cpu is
	signal address_full      : std_logic_vector(23 downto 0);
	signal data_in_internal  : std_logic_vector(7 downto 0);
	signal data_out_internal : std_logic_vector(7 downto 0);
	signal rw_n_internal     : std_logic;
begin
	data_in_internal <= data_out_internal when rw_n_internal = '0' else data_in;
	data_out <= data_out_internal;
	rw_n <= rw_n_internal;

	cpu : entity work.T65
		port map (
			Mode    => "00",
			BCD_en  => '1',
			Res_n   => reset_n,
			Enable  => enable,
			Clk     => clk,
			Rdy     => ready,
			Abort_n => '1',
			IRQ_n   => irq_n,
			NMI_n   => nmi_n,
			SO_n    => '1',
			R_W_n   => rw_n_internal,
			Sync    => sync,
			EF      => open,
			MF      => open,
			XF      => open,
			ML_n    => open,
			VP_n    => open,
			VDA     => open,
			VPA     => open,
			A       => address_full,
			DI      => data_in_internal,
			DO      => data_out_internal,
			Regs    => open,
			DEBUG   => open,
			NMI_ack => open
		);

	address <= address_full(15 downto 0);
end architecture;
