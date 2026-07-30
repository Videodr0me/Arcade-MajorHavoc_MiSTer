//============================================================================
//  Atari 2804 EEPROM
//
//  Written 2026 by Videodr0me
//
//  Major Havoc maps the 512-byte parallel EEPROM directly into Gamma's
//  address space. The second RAM port provides MiSTer save-data access.
//============================================================================

module major_havoc_eeprom
(
	input  logic       cpu_clk,
	input  logic       host_clk,
	input  logic       cpu_reset,

	input  logic [8:0] cpu_address,
	input  logic [7:0] cpu_data_in,
	input  logic       cpu_write,
	output logic [7:0] cpu_data_out,
	output logic       modified,

	input  logic [8:0] host_address,
	input  logic [7:0] host_data_in,
	input  logic       host_write,
	output logic [7:0] host_data_out
);

	major_havoc_dpram #(
		.DATA_WIDTH(8),
		.ADDR_WIDTH(9),
		.INITIAL_VALUE(8'hff),
		.INITIALIZE(1'b1)
	) memory (
		.clk_a(cpu_clk),
		.addr_a(cpu_address),
		.data_a(cpu_data_in),
		.we_a(cpu_write && !cpu_reset),
		.q_a(cpu_data_out),
		.clk_b(host_clk),
		.addr_b(host_address),
		.data_b(host_data_in),
		.we_b(host_write),
		.q_b(host_data_out)
	);

	always_ff @(posedge cpu_clk) begin
		if (cpu_reset)
			modified <= 1'b0;
		else
			modified <= cpu_write;
	end

endmodule
