//============================================================================
//  Inferred true dual-port RAM with independent clocks
//
//  Written 2026 by Videodr0me
//============================================================================

module major_havoc_dpram #(
	parameter integer DATA_WIDTH = 8,
	parameter integer ADDR_WIDTH = 8,
	parameter logic [DATA_WIDTH-1:0] INITIAL_VALUE = '0,
	parameter bit INITIALIZE = 1'b0
) (
	input  logic                  clk_a,
	input  logic [ADDR_WIDTH-1:0] addr_a,
	input  logic [DATA_WIDTH-1:0] data_a,
	input  logic                  we_a,
	output logic [DATA_WIDTH-1:0] q_a,

	input  logic                  clk_b,
	input  logic [ADDR_WIDTH-1:0] addr_b,
	input  logic [DATA_WIDTH-1:0] data_b,
	input  logic                  we_b,
	output logic [DATA_WIDTH-1:0] q_b
);

	(* ramstyle = "M10K, no_rw_check" *)
	logic [DATA_WIDTH-1:0] memory [0:(1 << ADDR_WIDTH)-1];

	generate
		if (INITIALIZE) begin : g_initialize
			integer index;
			initial begin
				for (index = 0; index < (1 << ADDR_WIDTH); index = index + 1)
					memory[index] = INITIAL_VALUE;
			end
		end
	endgenerate

	always_ff @(posedge clk_a) begin
		if (we_a) begin
			memory[addr_a] <= data_a;
			q_a <= data_a;
		end else begin
			q_a <= memory[addr_a];
		end
	end

	always_ff @(posedge clk_b) begin
		if (we_b) begin
			memory[addr_b] <= data_b;
			q_b <= data_b;
		end else begin
			q_b <= memory[addr_b];
		end
	end

endmodule
