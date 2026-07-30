//============================================================================
//  Major Havoc watchdog
//
//  Written 2026 by Videodr0me
//
//  Models the cascaded counter and Alpha reset flip-flop on SP-252 sheet 4B.
//============================================================================

module major_havoc_watchdog
#(
	parameter integer COUNTER_BITS = 8
)
(
	input  logic clk,
	input  logic reset,
	input  logic pause,
	input  logic tick,
	input  logic clear,

	output logic alpha_reset = 1'b0
);

	logic [COUNTER_BITS-1:0] counter = '0;

	always_ff @(posedge clk) begin
		if (reset) begin
			counter <= '0;
			alpha_reset <= 1'b0;
		end else if (pause || clear) begin
			counter <= '0;
			alpha_reset <= 1'b0;
		end else if (tick) begin
			if (&counter) begin
				counter <= '0;
				alpha_reset <= !alpha_reset;
			end else begin
				counter <= counter + 1'd1;
			end
		end
	end

endmodule
