//============================================================================
//  Major Havoc quad-POKEY output model
//
//  Written 2026 by Videodr0me
//
//  The measured mix gives all four POKEYs equal gain. The schematic mix
//  preserves the documented 22K/10K branch ratio, giving POKEY 4 2.2 times
//  the gain of each other POKEY. Both feed the same measured cabinet filter.
//============================================================================

module major_havoc_audio
(
	input  logic               clk,
	input  logic               reset,
	input  logic               ce_1m25,
	input  logic               schematic_mix,
	input  logic               filter_enable,
	input  logic         [7:0] pokey_0,
	input  logic         [7:0] pokey_1,
	input  logic         [7:0] pokey_2,
	input  logic         [7:0] pokey_3,
	output logic signed [15:0] audio
);

	localparam int STATE_WIDTH = 40;
	localparam int FRACTION_BITS = 20;

	localparam logic signed [STATE_WIDTH + 3:0] AUDIO_MAX = 32767;
	localparam logic signed [STATE_WIDTH + 3:0] AUDIO_MIN = -32768;

	logic [9:0] main_sum;
	logic [9:0] all_sum;

	logic signed [STATE_WIDTH - 1:0] main_target;
	logic signed [STATE_WIDTH - 1:0] out4_target;
	logic signed [STATE_WIDTH - 1:0] all_target;
	logic signed [STATE_WIDTH - 1:0] measured_mix_target;
	logic signed [STATE_WIDTH - 1:0] schematic_mix_target;
	logic signed [STATE_WIDTH - 1:0] mixed_target;
	logic signed [STATE_WIDTH - 1:0] dc_q = '0;
	logic signed [STATE_WIDTH - 1:0] filter_low_1_q = '0;
	logic signed [STATE_WIDTH - 1:0] filter_low_2_q = '0;

	logic signed [STATE_WIDTH - 1:0] dc_next;
	logic signed [STATE_WIDTH - 1:0] ac_signal;
	logic signed [STATE_WIDTH - 1:0] filter_low_1_next;
	logic signed [STATE_WIDTH - 1:0] filter_low_2_next;
	logic signed [STATE_WIDTH - 1:0] selected_output;

	logic signed [STATE_WIDTH + 3:0] selected_wide;
	logic signed [STATE_WIDTH + 3:0] gained_wide;
	logic signed [STATE_WIDTH + 3:0] scaled_sample;
	logic signed [15:0] audio_next;

	// Keep filter corrections at the state width.
	function automatic logic signed [STATE_WIDTH - 1:0]
		narrow_state(input logic signed [STATE_WIDTH + 7:0] value);
		begin
			narrow_state = value[STATE_WIDTH - 1:0];
		end
	endfunction

	// 67/1048576 gives the 0.22 uF coupling networks a 12.69 Hz corner.
	function automatic logic signed [STATE_WIDTH - 1:0]
		dc_correction(input logic signed [STATE_WIDTH - 1:0] value);
		logic signed [STATE_WIDTH + 7:0] wide;
		begin
			wide = {{8{value[STATE_WIDTH - 1]}}, value};
			wide = (wide <<< 6) + (wide <<< 1) + wide;
			dc_correction = narrow_state(wide >>> 20);
		end
	endfunction

	// Two matched 88/4096 stages model a 4.321 kHz two-pole response.
	function automatic logic signed [STATE_WIDTH - 1:0]
		filter_correction(input logic signed [STATE_WIDTH - 1:0] value);
		logic signed [STATE_WIDTH + 7:0] wide;
		begin
			wide = {{8{value[STATE_WIDTH - 1]}}, value};
			wide = (wide <<< 6) + (wide <<< 4) + (wide <<< 3);
			filter_correction = narrow_state(wide >>> 12);
		end
	endfunction

	function automatic logic signed [STATE_WIDTH - 1:0]
		measured_equal_mix(
			input logic signed [STATE_WIDTH - 1:0] all_value
		);
		logic signed [STATE_WIDTH + 3:0] all_wide;
		logic signed [STATE_WIDTH + 3:0] mix_wide;
		begin
			all_wide = {{4{all_value[STATE_WIDTH - 1]}}, all_value};
			mix_wide = ((all_wide <<< 3) + (all_wide <<< 2) +
			            all_wide) >>> 1;
			measured_equal_mix = mix_wide[STATE_WIDTH - 1:0];
		end
	endfunction

	function automatic logic signed [STATE_WIDTH - 1:0]
		schematic_weighted_mix(
			input logic signed [STATE_WIDTH - 1:0] main_value,
			input logic signed [STATE_WIDTH - 1:0] out4_value
		);
		logic signed [STATE_WIDTH + 3:0] main_wide;
		logic signed [STATE_WIDTH + 3:0] out4_wide;
		logic signed [STATE_WIDTH + 3:0] mix_wide;
		begin
			main_wide = {{4{main_value[STATE_WIDTH - 1]}}, main_value};
			out4_wide = {{4{out4_value[STATE_WIDTH - 1]}}, out4_value};
			mix_wide = (main_wide <<< 2) + main_wide +
			           (out4_wide <<< 3) + (out4_wide <<< 1) +
			           out4_wide;
			schematic_weighted_mix =
				mix_wide[STATE_WIDTH - 1:0];
		end
	endfunction

	always_comb begin
		main_sum = {2'b00, pokey_0} + {2'b00, pokey_1} +
		           {2'b00, pokey_2};
		all_sum = main_sum + {2'b00, pokey_3};

		main_target = $signed({1'b0, main_sum});
		main_target = main_target <<< FRACTION_BITS;
		out4_target = $signed({1'b0, pokey_3});
		out4_target = out4_target <<< FRACTION_BITS;
		all_target = $signed({1'b0, all_sum});
		all_target = all_target <<< FRACTION_BITS;

		measured_mix_target = measured_equal_mix(all_target);
		schematic_mix_target =
			schematic_weighted_mix(main_target, out4_target);
		mixed_target = schematic_mix ? schematic_mix_target :
		                              measured_mix_target;

		dc_next = dc_q +
		          dc_correction(mixed_target - dc_q);
		ac_signal = mixed_target - dc_next;
		filter_low_1_next = filter_low_1_q +
			filter_correction(ac_signal - filter_low_1_q);
		filter_low_2_next = filter_low_2_q +
			filter_correction(filter_low_1_q - filter_low_2_q);
		selected_output = filter_enable ? filter_low_2_next : ac_signal;

		// Apply 4.5x gain before clipping to 16 bits.
		selected_wide =
			{{4{selected_output[STATE_WIDTH - 1]}}, selected_output};
		gained_wide = ((selected_wide <<< 3) + selected_wide) >>> 1;
		scaled_sample = gained_wide >>> FRACTION_BITS;

		if (scaled_sample > AUDIO_MAX)
			audio_next = 16'sh7fff;
		else if (scaled_sample < AUDIO_MIN)
			audio_next = 16'sh8000;
		else
			audio_next = scaled_sample[15:0];
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			dc_q <= '0;
			filter_low_1_q <= '0;
			filter_low_2_q <= '0;
			audio <= 16'sd0;
		end else if (ce_1m25) begin
			dc_q <= dc_next;
			filter_low_1_q <= filter_low_1_next;
			filter_low_2_q <= filter_low_2_next;
			audio <= audio_next;
		end
	end

endmodule
