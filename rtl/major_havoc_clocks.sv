//============================================================================
//  Major Havoc AVG clock
//
//  Written 2026 by Videodr0me
//
//  The original main board uses a 12.096 MHz vector-generator oscillator
//  independent of the 10.000 MHz CPU/audio clock.
//============================================================================

module major_havoc_clocks
(
	input  logic refclk,
	input  logic reset,
	output logic clk_avg,
	output logic locked
);

	altera_pll #(
		.fractional_vco_multiplier("true"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("12.096000 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.pll_type("General"),
		.pll_subtype("General")
	) avg_pll (
		.refclk(refclk),
		.rst(reset),
		.outclk(clk_avg),
		.locked(locked),
		.fboutclk(),
		.fbclk(1'b0)
	);

endmodule
