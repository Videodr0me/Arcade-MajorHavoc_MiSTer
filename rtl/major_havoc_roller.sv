//============================================================================
//  Major Havoc roller controller
//
//  Written 2026 by Videodr0me
//
//  Combines spinner, mouse, analog-stick, and digital movement into the
//  modulo-8-bit position read by the Gamma CPU.
//============================================================================

module major_havoc_roller
(
	input  logic        clk,
	input  logic        reset,
	input  logic        roller_read,
	input  logic        move_left,
	input  logic        move_right,
	input  logic  [7:0] analog_x,
	input  logic  [8:0] spinner,
	input  logic [24:0] mouse,
	input  logic        reverse,
	input  logic  [2:0] sensitivity,
	output logic  [7:0] position
);

	localparam logic        [8:0] PACE_RELOAD = 9'd399;
	localparam logic signed [17:0] PENDING_LIMIT_Q3 = 18'sd4_088;
	localparam logic signed  [8:0] READ_LIMIT = 9'sd120;

	function automatic logic signed [17:0] apply_gain;
		input logic signed [17:0] value_q3;
		input logic        [2:0] gain;
		begin
			case (gain)
				3'd0: apply_gain = value_q3;
				3'd1: apply_gain = value_q3 - (value_q3 >>> 2);
				3'd2: apply_gain = value_q3 >>> 1;
				3'd3: apply_gain = value_q3 >>> 2;
				3'd4: apply_gain = value_q3 >>> 3;
				3'd5: apply_gain = value_q3 + (value_q3 >>> 2);
				3'd6: apply_gain = value_q3 + (value_q3 >>> 1);
				default: apply_gain = value_q3 <<< 1;
			endcase
		end
	endfunction

	function automatic logic signed [17:0] saturate_pending;
		input logic signed [18:0] value_q3;
		begin
			if (value_q3 > PENDING_LIMIT_Q3)
				saturate_pending = PENDING_LIMIT_Q3;
			else if (value_q3 < -PENDING_LIMIT_Q3)
				saturate_pending = -PENDING_LIMIT_Q3;
			else
				saturate_pending = value_q3[17:0];
		end
	endfunction

	logic        left_meta;
	logic        left_q;
	logic        right_meta;
	logic        right_q;
	logic  [7:0] analog_meta;
	logic  [7:0] analog_q;
	logic  [8:0] spinner_meta;
	logic  [8:0] spinner_q;
	logic [24:0] mouse_meta;
	logic [24:0] mouse_q;
	logic        reverse_meta;
	logic        reverse_q;
	logic  [2:0] sensitivity_meta;
	logic  [2:0] sensitivity_q;

	logic  [1:0] arm_count;
	logic        input_armed;
	logic        spinner_toggle_seen;
	logic        mouse_toggle_seen;
	logic [13:0] rate_counter;
	logic        rate_tick;
	logic  [8:0] pace_counter;
	logic        pace_tick;
	logic        reverse_previous;

	logic signed [17:0] event_q3;
	logic signed [17:0] directed_q3;
	logic signed [17:0] scaled_q3;
	logic signed [18:0] pending_sum_q3;
	logic signed [17:0] pending_after_event_q3;
	logic signed [17:0] pending_next_q3;
	logic signed [17:0] pending_q3;
	logic signed  [1:0] position_step;
	logic signed  [8:0] movement_since_read;
	logic signed  [8:0] analog_signed;
	logic        [8:0] analog_magnitude;
	logic              analog_negative;

	always_comb begin
		rate_tick = (rate_counter == 14'd9_999);
		pace_tick = (pace_counter == PACE_RELOAD);
		event_q3 = 18'sd0;

		if (input_armed &&
		    (spinner_q[8] != spinner_toggle_seen))
			event_q3 = event_q3 +
				($signed({{10{spinner_q[7]}}, spinner_q[7:0]}) <<< 3);

		if (input_armed && (mouse_q[24] != mouse_toggle_seen))
			event_q3 = event_q3 +
				($signed({{10{mouse_q[4]}}, mouse_q[15:8]}) <<< 3);

		analog_signed = $signed({analog_q[7], analog_q});
		analog_magnitude = 9'd0;
		analog_negative = 1'b0;
		if (analog_signed > 9'sd16) begin
			analog_magnitude = analog_signed - 9'sd16;
		end else if (analog_signed < -9'sd16) begin
			analog_magnitude = -(analog_signed + 9'sd16);
			analog_negative = 1'b1;
		end

		if (input_armed && rate_tick) begin
			if (left_q != right_q)
				event_q3 = event_q3 +
					(left_q ? -18'sd16 : 18'sd16);
			else if (analog_negative)
				event_q3 = event_q3 -
					$signed({13'd0, analog_magnitude[8:4]});
			else
				event_q3 = event_q3 +
					$signed({13'd0, analog_magnitude[8:4]});
		end

		// Rightward motion decrements the hardware LETA count.
		directed_q3 = reverse_q ? event_q3 : -event_q3;
		scaled_q3 = apply_gain(directed_q3, sensitivity_q);
		pending_sum_q3 =
			$signed({pending_q3[17], pending_q3}) +
			$signed({scaled_q3[17], scaled_q3});
		pending_after_event_q3 = saturate_pending(pending_sum_q3);

		// Mouse and spinner reports can contain several steps. Release them one
		// at a time and limit movement between Gamma reads to preserve direction.
		position_step = 2'sd0;
		if (pace_tick && !roller_read &&
		    (reverse_q == reverse_previous)) begin
			if ((pending_after_event_q3 >= 18'sd8) &&
			    (movement_since_read < READ_LIMIT))
				position_step = 2'sd1;
			else if ((pending_after_event_q3 <= -18'sd8) &&
			         (movement_since_read > -READ_LIMIT))
				position_step = -2'sd1;
		end

		pending_next_q3 = pending_after_event_q3;
		if (position_step > 0)
			pending_next_q3 = pending_after_event_q3 - 18'sd8;
		else if (position_step < 0)
			pending_next_q3 = pending_after_event_q3 + 18'sd8;
	end

	always_ff @(posedge clk) begin
		left_meta <= move_left;
		left_q <= left_meta;
		right_meta <= move_right;
		right_q <= right_meta;
		analog_meta <= analog_x;
		analog_q <= analog_meta;
		spinner_meta <= spinner;
		spinner_q <= spinner_meta;
		mouse_meta <= mouse;
		mouse_q <= mouse_meta;
		reverse_meta <= reverse;
		reverse_q <= reverse_meta;
		sensitivity_meta <= sensitivity;
		sensitivity_q <= sensitivity_meta;

		if (reset) begin
			arm_count <= 2'd0;
			input_armed <= 1'b0;
			spinner_toggle_seen <= 1'b0;
			mouse_toggle_seen <= 1'b0;
			rate_counter <= 14'd0;
			pace_counter <= 9'd0;
			reverse_previous <= 1'b0;
			pending_q3 <= 18'sd0;
			movement_since_read <= 9'sd0;
			position <= 8'd0;
		end else begin
			rate_counter <= rate_tick ? 14'd0 : rate_counter + 1'd1;
			pace_counter <= pace_tick ? 9'd0 : pace_counter + 1'd1;
			reverse_previous <= reverse_q;

			if (!input_armed) begin
				arm_count <= arm_count + 1'd1;
				if (&arm_count) begin
					input_armed <= 1'b1;
					spinner_toggle_seen <= spinner_q[8];
					mouse_toggle_seen <= mouse_q[24];
				end
			end else begin
				spinner_toggle_seen <= spinner_q[8];
				mouse_toggle_seen <= mouse_q[24];

				if (reverse_q != reverse_previous)
					pending_q3 <= 18'sd0;
				else
					pending_q3 <= pending_next_q3;

				if (roller_read)
					movement_since_read <= 9'sd0;
				else if (position_step > 0)
					movement_since_read <= movement_since_read + 1'd1;
				else if (position_step < 0)
					movement_since_read <= movement_since_read - 1'd1;

				if (position_step > 0)
					position <= position + 1'd1;
				else if (position_step < 0)
					position <= position - 1'd1;
			end
		end
	end

endmodule
