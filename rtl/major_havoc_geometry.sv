//============================================================================
//  Major Havoc vector geometry
//
//  Written 2026 by Videodr0me
//
//  Scales signed AVG coordinates for the selected framing, then applies the
//  selected orientation around the exact raster center.
//============================================================================

module major_havoc_geometry
(
	input  logic signed [14:0] source_x,
	input  logic signed [14:0] source_y,
	input  logic               mode_1080p,
	input  logic               mode_480p,
	input  logic               mode_240p,
	input  logic        [11:0] center_x,
	input  logic        [11:0] center_y,
	input  logic        [11:0] render_width,
	input  logic        [11:0] render_height,
	input  logic         [2:0] orientation,
	input  logic               zoom_far,
	output logic signed [23:0] raster_x,
	output logic signed [23:0] raster_y,
	output logic               beam_in_bounds
);

	logic signed [23:0] source_x_w;
	logic signed [23:0] source_y_w;
	logic signed [23:0] scaled_x;
	logic signed [23:0] scaled_y;
	logic signed [23:0] selected_x;
	logic signed [23:0] selected_y;
	logic signed [23:0] presented_y;
	logic signed [23:0] oriented_x;
	logic signed [23:0] oriented_y;
	logic               quarter_turn;
	logic               output_x_negative;
	logic               output_y_negative;

	always_comb begin
		source_x_w = {{9{source_x[14]}}, source_x};
		source_y_w = {{9{source_y[14]}}, source_y};
		quarter_turn = (orientation == 3'd1) ||
		               (orientation == 3'd3) ||
		               (orientation == 3'd6) ||
		               (orientation == 3'd7);

		scaled_x = 24'sd0;
		scaled_y = 24'sd0;

		if (mode_1080p) begin
			if (!zoom_far && quarter_turn) begin
				// 115/1024.
				scaled_x = ((source_x_w << 7) - (source_x_w << 4) +
				            (source_x_w << 2) - source_x_w) >>> 10;
				scaled_y = ((source_y_w << 7) - (source_y_w << 4) +
				            (source_y_w << 2) - source_y_w) >>> 10;
			end else if (!zoom_far) begin
				// 531/4096, split into two sums to stay within 24 bits.
				scaled_x = (((source_x_w << 8) + (source_x_w << 3)) +
				            (source_x_w + (source_x_w >>> 1))) >>> 11;
				scaled_y = (((source_y_w << 8) + (source_y_w << 3)) +
				            (source_y_w + (source_y_w >>> 1))) >>> 11;
			end else if (quarter_turn) begin
				// 389/4096, centered on AVG (0,0).
				scaled_x = ((source_x_w << 8) + (source_x_w << 7) +
				            (source_x_w << 2) + source_x_w) >>> 12;
				scaled_y = ((source_y_w << 8) + (source_y_w << 7) +
				            (source_y_w << 2) + source_y_w) >>> 12;
			end else begin
				// 107/1024, centered on AVG (0,0).
				scaled_x = ((source_x_w << 7) - (source_x_w << 4) -
				            (source_x_w << 2) - source_x_w) >>> 10;
				scaled_y = ((source_y_w << 7) - (source_y_w << 4) -
				            (source_y_w << 2) - source_y_w) >>> 10;
			end
		end else if (mode_480p || mode_240p) begin
			if (!zoom_far && quarter_turn) begin
				// 51/1024.
				scaled_x = ((source_x_w << 6) - (source_x_w << 4) +
				            (source_x_w << 2) - source_x_w) >>> 10;
				scaled_y = ((source_y_w << 6) - (source_y_w << 4) +
				            (source_y_w << 2) - source_y_w) >>> 10;
			end else if (!zoom_far) begin
				// 269/4096.
				scaled_x = ((source_x_w << 8) + (source_x_w << 4) -
				            (source_x_w << 2) + source_x_w) >>> 12;
				scaled_y = ((source_y_w << 8) + (source_y_w << 4) -
				            (source_y_w << 2) + source_y_w) >>> 12;
			end else if (quarter_turn) begin
				// 3/64, centered on AVG (0,0).
				scaled_x = ((source_x_w << 1) + source_x_w) >>> 6;
				scaled_y = ((source_y_w << 1) + source_y_w) >>> 6;
			end else begin
				// 93/2048, centered on AVG (0,0).
				scaled_x = ((source_x_w << 6) + (source_x_w << 5) -
				            (source_x_w << 1) - source_x_w) >>> 11;
				scaled_y = ((source_y_w << 6) + (source_y_w << 5) -
				            (source_y_w << 1) - source_y_w) >>> 11;
			end
		end else begin
			if (!zoom_far && quarter_turn) begin
				// 153/2048.
				scaled_x = ((source_x_w << 7) + (source_x_w << 4) +
				            (source_x_w << 3) + source_x_w) >>> 11;
				scaled_y = ((source_y_w << 7) + (source_y_w << 4) +
				            (source_y_w << 3) + source_y_w) >>> 11;
			end else if (!zoom_far) begin
				// 177/2048.
				scaled_x = ((source_x_w << 7) + (source_x_w << 5) +
				            (source_x_w << 4) + source_x_w) >>> 11;
				scaled_y = ((source_y_w << 7) + (source_y_w << 5) +
				            (source_y_w << 4) + source_y_w) >>> 11;
			end else if (quarter_turn) begin
				// 65/1024, centered on AVG (0,0).
				scaled_x = ((source_x_w << 6) + source_x_w) >>> 10;
				scaled_y = ((source_y_w << 6) + source_y_w) >>> 10;
			end else begin
				// 143/2048, centered on AVG (0,0).
				scaled_x = ((source_x_w << 7) + (source_x_w << 4) -
				            source_x_w) >>> 11;
				scaled_y = ((source_y_w << 7) + (source_y_w << 4) -
				            source_y_w) >>> 11;
			end
		end

		case (orientation)
			3'd0: begin
				selected_x = scaled_x;
				selected_y = scaled_y;
				output_x_negative = 1'b0;
				output_y_negative = 1'b1;
			end
			3'd1: begin
				selected_x = scaled_y;
				selected_y = scaled_x;
				output_x_negative = 1'b0;
				output_y_negative = 1'b0;
			end
			3'd2: begin
				selected_x = scaled_x;
				selected_y = scaled_y;
				output_x_negative = 1'b1;
				output_y_negative = 1'b0;
			end
			3'd3: begin
				selected_x = scaled_y;
				selected_y = scaled_x;
				output_x_negative = 1'b1;
				output_y_negative = 1'b1;
			end
			3'd4: begin
				selected_x = scaled_x;
				selected_y = scaled_y;
				output_x_negative = 1'b1;
				output_y_negative = 1'b1;
			end
			3'd5: begin
				selected_x = scaled_x;
				selected_y = scaled_y;
				output_x_negative = 1'b0;
				output_y_negative = 1'b0;
			end
			3'd6: begin
				selected_x = scaled_y;
				selected_y = scaled_x;
				output_x_negative = 1'b0;
				output_y_negative = 1'b1;
			end
			default: begin
				selected_x = scaled_y;
				selected_y = scaled_x;
				output_x_negative = 1'b1;
				output_y_negative = 1'b0;
			end
		endcase

		oriented_x = output_x_negative ? -selected_x : selected_x;
		presented_y = mode_240p ? (selected_y >>> 1) : selected_y;
		oriented_y = output_y_negative ? -presented_y : presented_y;

		raster_x = $signed({12'd0, center_x}) -
		           (output_x_negative ? 24'sd1 : 24'sd0) + oriented_x;
		raster_y = $signed({12'd0, center_y}) -
		           (output_y_negative ? 24'sd1 : 24'sd0) + oriented_y;

		beam_in_bounds = (raster_x >= 24'sd0) &&
		                 (raster_x < $signed({12'd0, render_width})) &&
		                 (raster_y >= 24'sd0) &&
		                 (raster_y < $signed({12'd0, render_height}));
	end

endmodule
