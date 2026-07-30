//============================================================================
//  Major Havoc clock enables
//
//  Written 2026 by Videodr0me
//
//  Generates the board timing pulses derived from the 10.000 MHz oscillator.
//============================================================================

module major_havoc_clock_enables
(
	input  logic clk_10,
	input  logic reset,

	output logic ce_alpha_2m5,
	output logic ce_gamma_1m25,
	output logic ce_irq_4k882,
	output logic ce_watchdog_2k441
);

	logic [11:0] cpu_phase = 12'd0;

	always_ff @(posedge clk_10) begin
		ce_alpha_2m5 <= 1'b0;
		ce_gamma_1m25 <= 1'b0;
		ce_irq_4k882  <= 1'b0;
		ce_watchdog_2k441 <= 1'b0;

		if (reset) begin
			cpu_phase <= 12'd0;
		end else begin
			cpu_phase <= cpu_phase + 1'd1;
			ce_alpha_2m5 <= &cpu_phase[1:0];
			ce_gamma_1m25 <= &cpu_phase[2:0];
			ce_irq_4k882 <= &cpu_phase[10:0];
			ce_watchdog_2k441 <= &cpu_phase;
		end
	end

endmodule
