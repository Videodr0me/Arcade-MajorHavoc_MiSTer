//============================================================================
//  Major Havoc vector video presentation
//
//  Written 2026 by Videodr0me
//
//  Maps signed AVG coordinates into the selected raster mode and connects the
//  native four-bit color stream to the sparse framebuffer and CRT pipeline.
//============================================================================

module major_havoc_video
(
	input  logic        clk_50,
	input  logic        clk_avg,
	input  logic        clk_125,
	input  logic        reset,
	input  logic        reset_source,

	input  logic        direct_video,
	input  logic        direct_video_31khz,
	input  logic [11:0] hdmi_height,
	input  logic        mode_120hz,
	input  logic  [1:0] aspect_ratio,
	input  logic  [1:0] buffer_mode,
	input  logic  [2:0] geometry_orientation,
	input  logic        geometry_zoom_far,

	input  logic  [2:0] profile,
	input  logic  [2:0] off_dot_mode,
	input  logic  [1:0] off_tone_mapping,
	input  logic  [1:0] off_inter_frame_decay,
	input  logic  [1:0] off_intra_frame_decay,
	input  logic [29:0] custom_1_settings,
	input  logic [29:0] custom_2_settings,

	input  logic signed [14:0] avg_x,
	input  logic signed [14:0] avg_y,
	input  logic         [7:0] avg_z,
	input  logic         [3:0] avg_color,
	input  logic               avg_beam_sample,
	input  logic               avg_is_dot,
	input  logic               avg_source_tick,
	input  logic               frame_done,

	output logic [12:0] video_arx,
	output logic [12:0] video_ary,
	output logic        ce_pixel,
	output logic        hblank,
	output logic        vblank,
	output logic  [7:0] video_r,
	output logic  [7:0] video_g,
	output logic  [7:0] video_b,
	output logic        hsync,
	output logic        vsync,
	output logic        mode_is_720p,
	output logic        fifo_full,

	output logic        ddram_clk,
	input  logic        ddram_busy,
	output logic  [7:0] ddram_burst_count,
	output logic [28:0] ddram_address,
	input  logic [63:0] ddram_data_out,
	input  logic        ddram_data_ready,
	output logic        ddram_read,
	output logic [63:0] ddram_data_in,
	output logic  [7:0] ddram_byte_enable,
	output logic        ddram_write,

	input  logic [15:0] sdram_data_in,
	output logic [15:0] sdram_data_out,
	output logic        sdram_data_oe,
	output logic        sdram_cke,
	output logic        sdram_ncs,
	output logic        sdram_nras,
	output logic        sdram_ncas,
	output logic        sdram_nwe,
	output logic  [1:0] sdram_dqm,
	output logic [12:0] sdram_address,
	output logic  [1:0] sdram_bank
);

	logic        direct_video_meta = 1'b0;
	logic        direct_video_sync = 1'b0;
	logic        scan_rate_meta = 1'b0;
	logic        scan_rate_sync = 1'b0;
	logic [11:0] requested_height_meta = 12'd0;
	logic [11:0] requested_height_sync = 12'd0;
	logic [11:0] height_candidate = 12'd0;
	logic [11:0] stable_height = 12'd0;
	logic [24:0] height_timer = 25'd0;

	logic        mode_120hz_meta = 1'b0;
	logic        mode_120hz_sync = 1'b0;
	logic        stable_120hz = 1'b0;
	logic [24:0] rate_timer = 25'd0;

	always_ff @(posedge clk_50) begin
		direct_video_meta <= direct_video;
		direct_video_sync <= direct_video_meta;
		scan_rate_meta <= direct_video_31khz;
		scan_rate_sync <= scan_rate_meta;

		requested_height_meta <= direct_video_sync ?
		                         (scan_rate_sync ? 12'd480 : 12'd240) :
		                         hdmi_height;
		requested_height_sync <= requested_height_meta;

		if ((requested_height_meta == requested_height_sync) &&
		    (requested_height_sync > 12'd200) &&
		    (requested_height_sync == height_candidate)) begin
			if (height_timer < 25'd25_000_000)
				height_timer <= height_timer + 1'd1;
			else
				stable_height <= height_candidate;
		end else begin
			height_candidate <= requested_height_sync;
			height_timer <= 25'd0;
			stable_height <= 12'd0;
		end

		mode_120hz_meta <= mode_120hz;
		mode_120hz_sync <= mode_120hz_meta;
		if (mode_120hz_meta == mode_120hz_sync) begin
			if (mode_120hz_sync != stable_120hz) begin
				if (rate_timer < 25'd25_000_000)
					rate_timer <= rate_timer + 1'd1;
				else begin
					stable_120hz <= mode_120hz_sync;
					rate_timer <= 25'd0;
				end
			end else begin
				rate_timer <= 25'd0;
			end
		end
	end

	logic [11:0] selected_height;
	logic        selected_120hz;

	always_comb begin
		selected_height = ((mode_120hz_sync != stable_120hz) ||
		                   (rate_timer != 25'd0)) ? 12'd0 : stable_height;
		selected_120hz = stable_120hz && (selected_height == 12'd720);
	end

	typedef struct packed {
		logic [11:0] fb_width;
		logic [11:0] fb_height;
		logic [11:0] x_center;
		logic [11:0] y_center;
		logic [12:0] optimized_arx;
		logic [12:0] optimized_ary;
		logic [11:0] h_total;
		logic [11:0] v_total;
		logic [11:0] hs_start;
		logic [11:0] hs_end;
		logic [11:0] vs_start;
		logic [11:0] vs_end;
		logic        is_1080p;
		logic        is_480p;
		logic        is_240p;
		logic        is_120hz;
	} video_mode_t;

	function automatic video_mode_t decode_video_mode(
		input logic [11:0] height,
		input logic        requested_120hz
	);
		video_mode_t mode;
		begin
			mode = '0;
			if ((height >= 12'd1080) && (height < 12'd1400)) begin
				mode.fb_width = 12'd1472;
				mode.fb_height = 12'd1080;
				mode.x_center = 12'd736;
				mode.y_center = 12'd540;
				mode.optimized_arx = 13'h1000 | 13'd1472;
				mode.optimized_ary = 13'h1000 | 13'd1080;
				mode.h_total = 12'd1851;
				mode.v_total = 12'd1124;
				mode.hs_start = 12'd1600;
				mode.hs_end = 12'd1688;
				mode.vs_start = 12'd1088;
				mode.vs_end = 12'd1093;
				mode.is_1080p = 1'b1;
			end else if (height < 12'd480) begin
				mode.fb_width = 12'd640;
				mode.fb_height = 12'd240;
				mode.x_center = 12'd320;
				mode.y_center = 12'd120;
				mode.optimized_arx = 13'h1000 | 13'd640;
				mode.optimized_ary = 13'h1000 | 13'd240;
				mode.h_total = 12'd993;
				mode.v_total = 12'd261;
				mode.hs_start = 12'd720;
				mode.hs_end = 12'd816;
				mode.vs_start = 12'd245;
				mode.vs_end = 12'd248;
				mode.is_240p = 1'b1;
			end else if (height < 12'd720) begin
				mode.fb_width = 12'd640;
				mode.fb_height = 12'd480;
				mode.x_center = 12'd320;
				mode.y_center = 12'd240;
				mode.optimized_arx = 13'h1000 | 13'd640;
				mode.optimized_ary = 13'h1000 | 13'd480;
				mode.h_total = 12'd992;
				mode.v_total = 12'd524;
				mode.hs_start = 12'd720;
				mode.hs_end = 12'd816;
				mode.vs_start = 12'd490;
				mode.vs_end = 12'd492;
				mode.is_480p = 1'b1;
			end else begin
				mode.fb_width = 12'd980;
				mode.fb_height = 12'd720;
				mode.x_center = 12'd490;
				mode.y_center = 12'd360;
				mode.optimized_arx = (height >= 12'd1440) ?
				                     (13'h1000 | 13'd1960) :
				                     (13'h1000 | 13'd980);
				mode.optimized_ary = (height >= 12'd1440) ?
				                     (13'h1000 | 13'd1440) :
				                     (13'h1000 | 13'd720);
				mode.h_total = 12'd1388;
				mode.v_total = 12'd748;
				mode.hs_start = 12'd1108;
				mode.hs_end = 12'd1196;
				mode.vs_start = 12'd728;
				mode.vs_end = 12'd733;
				mode.is_120hz = requested_120hz;
			end
			decode_video_mode = mode;
		end
	endfunction

	video_mode_t mode_q = decode_video_mode(12'd480, 1'b0);

	wire [11:0] fb_width = mode_q.fb_width;
	wire [11:0] fb_height = mode_q.fb_height;
	wire [11:0] x_center = mode_q.x_center;
	wire [11:0] y_center = mode_q.y_center;
	wire [12:0] optimized_arx = mode_q.optimized_arx;
	wire [12:0] optimized_ary = mode_q.optimized_ary;
	wire [11:0] h_total = mode_q.h_total;
	wire [11:0] v_total = mode_q.v_total;
	wire [11:0] hs_start = mode_q.hs_start;
	wire [11:0] hs_end = mode_q.hs_end;
	wire [11:0] vs_start = mode_q.vs_start;
	wire [11:0] vs_end = mode_q.vs_end;
	wire        is_1080p = mode_q.is_1080p;
	wire        is_480p = mode_q.is_480p;
	wire        is_240p = mode_q.is_240p;
	wire        is_120hz = mode_q.is_120hz;

	logic [2:0] effective_dot_mode;
	logic [1:0] effective_tone_mapping;
	logic [2:0] effective_bloom_width;
	logic [2:0] effective_bloom_curve;
	logic [2:0] effective_halo_filter;
	logic [2:0] effective_halo_curve;
	logic [1:0] effective_halo_spread;
	logic [1:0] effective_halo_knee;
	logic [1:0] effective_inter_frame_decay;
	logic [1:0] effective_intra_frame_decay;
	logic       effective_color_space;
	logic [2:0] effective_presentation_color;
	logic       effective_slot_mask;
	logic       effective_full_bypass;

	vfb_profile_resolver profile_resolver
	(
		.profile(profile),
		.fb_height(fb_height),
		.off_dot_mode(off_dot_mode),
		.off_tonemapping(off_tone_mapping),
		.off_inter_frame_decay(off_inter_frame_decay),
		.off_intra_frame_decay(off_intra_frame_decay),
		.custom1_settings(custom_1_settings),
		.custom2_settings(custom_2_settings),
		.dot_mode(effective_dot_mode),
		.tonemapping(effective_tone_mapping),
		.bloom_width(effective_bloom_width),
		.bloom_curve(effective_bloom_curve),
		.halo_filter(effective_halo_filter),
		.halo_curve(effective_halo_curve),
		.halo_spread(effective_halo_spread),
		.halo_knee(effective_halo_knee),
		.inter_frame_decay(effective_inter_frame_decay),
		.intra_frame_decay(effective_intra_frame_decay),
		.color_space(effective_color_space),
		.presentation_color(effective_presentation_color),
		.slot_mask(effective_slot_mask),
		.full_bypass(effective_full_bypass)
	);

	logic [11:0] height_meta = 12'd480;
	logic        rate_meta = 1'b0;
	logic        rate_sync = 1'b0;
	logic        mode_config_ready = 1'b0;
	logic        mode_ready = 1'b0;

	always_ff @(posedge clk_125) begin
		height_meta <= selected_height;
		rate_meta <= selected_120hz;
		rate_sync <= rate_meta;
		mode_config_ready <= (height_meta != 12'd0) &&
		                     (rate_meta == rate_sync);
		mode_ready <= mode_config_ready;

		if ((height_meta != 12'd0) && (rate_meta == rate_sync))
			mode_q <= decode_video_mode(height_meta, rate_sync);
	end

	always_comb begin
		case (aspect_ratio)
			2'd0: begin
				video_arx = optimized_arx;
				video_ary = optimized_ary;
			end
			2'd1: begin
				video_arx = 13'd0;
				video_ary = 13'd0;
			end
			default: begin
				video_arx = 13'h1000 | {1'b0, fb_width};
				video_ary = 13'h1000 | {1'b0, fb_height};
			end
		endcase
	end

	logic  [2:0] geometry_orientation_q = 3'd0;
	logic        geometry_zoom_far_q = 1'b0;
	logic        slot_mask_rows_q = 1'b0;
	logic  [2:0] geometry_orientation_meta_a = 3'd0;
	logic  [2:0] geometry_orientation_a = 3'd0;
	logic        geometry_zoom_far_meta_a = 1'b0;
	logic        geometry_zoom_far_a = 1'b0;
	logic [11:0] fb_width_meta_a = 12'd640;
	logic [11:0] fb_width_a = 12'd640;
	logic [11:0] fb_height_meta_a = 12'd480;
	logic [11:0] fb_height_a = 12'd480;
	logic [11:0] x_center_meta_a = 12'd320;
	logic [11:0] x_center_a = 12'd320;
	logic [11:0] y_center_meta_a = 12'd240;
	logic [11:0] y_center_a = 12'd240;
	logic        is_1080p_meta_a = 1'b0;
	logic        is_1080p_a = 1'b0;
	logic        is_480p_meta_a = 1'b1;
	logic        is_480p_a = 1'b1;
	logic        is_240p_meta_a = 1'b0;
	logic        is_240p_a = 1'b0;
	logic        mode_ready_meta_a = 1'b0;
	logic        mode_ready_a = 1'b0;
	logic  [1:0] tone_mapping_meta_a = 2'd0;
	logic  [1:0] tone_mapping_a = 2'd0;
	logic signed [23:0] raster_x;
	logic signed [23:0] raster_y;
	logic               beam_in_bounds;

	always_ff @(posedge clk_125) begin
		if (reset) begin
			geometry_orientation_q <= 3'd0;
			geometry_zoom_far_q <= 1'b0;
			slot_mask_rows_q <= 1'b0;
		end else begin
			geometry_orientation_q <= geometry_orientation;
			geometry_zoom_far_q <= geometry_zoom_far;
			slot_mask_rows_q <= (geometry_orientation == 3'd1) ||
			                    (geometry_orientation == 3'd3) ||
			                    (geometry_orientation == 3'd6) ||
			                    (geometry_orientation == 3'd7);
		end
	end

	always_ff @(posedge clk_avg) begin
		geometry_orientation_meta_a <= geometry_orientation_q;
		geometry_orientation_a <= geometry_orientation_meta_a;
		geometry_zoom_far_meta_a <= geometry_zoom_far_q;
		geometry_zoom_far_a <= geometry_zoom_far_meta_a;
		fb_width_meta_a <= fb_width;
		fb_width_a <= fb_width_meta_a;
		fb_height_meta_a <= fb_height;
		fb_height_a <= fb_height_meta_a;
		x_center_meta_a <= x_center;
		x_center_a <= x_center_meta_a;
		y_center_meta_a <= y_center;
		y_center_a <= y_center_meta_a;
		is_1080p_meta_a <= is_1080p;
		is_1080p_a <= is_1080p_meta_a;
		is_480p_meta_a <= is_480p;
		is_480p_a <= is_480p_meta_a;
		is_240p_meta_a <= is_240p;
		is_240p_a <= is_240p_meta_a;
		mode_ready_meta_a <= mode_ready;
		mode_ready_a <= mode_ready_meta_a;
		tone_mapping_meta_a <= effective_tone_mapping;
		tone_mapping_a <= tone_mapping_meta_a;
	end

	major_havoc_geometry geometry
	(
		.source_x(avg_x),
		.source_y(avg_y),
		.mode_1080p(is_1080p_a),
		.mode_480p(is_480p_a),
		.mode_240p(is_240p_a),
		.center_x(x_center_a),
		.center_y(y_center_a),
		.render_width(fb_width_a),
		.render_height(fb_height_a),
		.orientation(geometry_orientation_a),
		.zoom_far(geometry_zoom_far_a),
		.raster_x(raster_x),
		.raster_y(raster_y),
		.beam_in_bounds(beam_in_bounds)
	);

	logic       beam_level;
	logic [7:0] mapped_intensity;

	assign beam_level = (avg_z != 8'd0) && (avg_color != 4'd0);

	vfb_tone_mapper tone_mapper
	(
		.clk_source(clk_avg),
		.reset(reset_source),
		.beam_on(beam_level),
		.raw_intensity(avg_z),
		.tone_mapping(tone_mapping_a),
		.mapped_intensity(mapped_intensity)
	);

	logic source_reset;
	logic source_reset_a;
	assign source_reset = reset || !mode_ready;
	assign source_reset_a = reset_source || !mode_ready_a;

	logic [10:0] vector_x_q = 11'd0;
	logic [10:0] vector_y_q = 11'd0;
	logic  [7:0] vector_z_q = 8'd0;
	logic  [3:0] vector_color_q = 4'd0;
	logic        vector_is_dot_q = 1'b0;
	logic        vector_beam_on_q = 1'b0;
	logic        frame_done_q = 1'b0;

	always_ff @(posedge clk_avg) begin
		if (source_reset_a) begin
			vector_x_q <= 11'd0;
			vector_y_q <= 11'd0;
			vector_z_q <= 8'd0;
			vector_color_q <= 4'd0;
			vector_is_dot_q <= 1'b0;
			vector_beam_on_q <= 1'b0;
			frame_done_q <= 1'b0;
		end else begin
			vector_x_q <= raster_x[10:0];
			vector_y_q <= raster_y[10:0];
			vector_z_q <= mapped_intensity;
			vector_color_q <= avg_color;
			vector_is_dot_q <= avg_is_dot;
			vector_beam_on_q <= avg_beam_sample && beam_in_bounds;
			frame_done_q <= frame_done;
		end
	end

	logic  [2:0] clock_divider = 3'd0;
	logic [10:0] h_counter = 11'd0;
	logic [10:0] v_counter = 11'd0;
	logic        timing_reset;
	logic        h_end;
	logic        v_end;
	logic        raw_hsync;
	logic        raw_vsync;
	logic        raw_hblank;
	logic        raw_vblank;

	assign timing_reset = reset || !mode_ready;
	assign h_end = (h_counter >= h_total[10:0]);
	assign v_end = (v_counter >= v_total[10:0]);

	always_ff @(posedge clk_125) begin
		if (timing_reset)
			ce_pixel <= 1'b0;
		else if (is_1080p || is_120hz)
			ce_pixel <= 1'b1;
		else if (is_240p)
			ce_pixel <= (clock_divider == 3'd0);
		else if (is_480p)
			ce_pixel <= (clock_divider[1:0] == 2'd0);
		else
			ce_pixel <= !clock_divider[0];
	end

	always_ff @(posedge clk_125) begin
		if (timing_reset) begin
			clock_divider <= 3'd0;
			h_counter <= h_total[10:0];
			v_counter <= fb_height[10:0] + 11'd2;
		end else begin
			clock_divider <= clock_divider + 1'd1;
			if (ce_pixel) begin
				if (h_end) begin
					h_counter <= 11'd0;
					v_counter <= v_end ? 11'd0 : v_counter + 1'd1;
				end else begin
					h_counter <= h_counter + 1'd1;
				end
			end
		end
	end

	always_comb begin
		raw_hsync = !((h_counter >= hs_start[10:0]) &&
		              (h_counter < hs_end[10:0]));
		raw_vsync = !((v_counter >= vs_start[10:0]) &&
		              (v_counter < vs_end[10:0]));
		raw_hblank = (h_counter >= fb_width[10:0]);
		raw_vblank = (v_counter >= fb_height[10:0]);
	end

	vfb_top framebuffer
	(
		.clk_sys(clk_125),
		.clk_source(clk_avg),
		.source_tick(avg_source_tick),
		.reset(source_reset),
		.video_timing_reset(timing_reset),

		.X_VECTOR(vector_x_q),
		.Y_VECTOR(vector_y_q),
		.Z_VECTOR(vector_z_q),
		.COLOR(vector_color_q),
		.IS_DOT(vector_is_dot_q),
		.BEAM_ON(vector_beam_on_q),

		.DDRAM_CLK(ddram_clk),
		.DDRAM_BUSY(ddram_busy),
		.DDRAM_BURSTCNT(ddram_burst_count),
		.DDRAM_ADDR(ddram_address),
		.DDRAM_DOUT(ddram_data_out),
		.DDRAM_DOUT_READY(ddram_data_ready),
		.DDRAM_RD(ddram_read),
		.DDRAM_DIN(ddram_data_in),
		.DDRAM_BE(ddram_byte_enable),
		.DDRAM_WE(ddram_write),

		.SDRAM_DQ_IN(sdram_data_in),
		.SDRAM_DQ_OUT(sdram_data_out),
		.SDRAM_DQ_OE(sdram_data_oe),
		.SDRAM_CKE(sdram_cke),
		.SDRAM_nCS(sdram_ncs),
		.SDRAM_nRAS(sdram_nras),
		.SDRAM_nCAS(sdram_ncas),
		.SDRAM_nWE(sdram_nwe),
		.SDRAM_DQM(sdram_dqm),
		.SDRAM_A(sdram_address),
		.SDRAM_BA(sdram_bank),

		.RENDER_WIDTH(fb_width),
		.RENDER_HEIGHT(fb_height),
		.VGA_R(video_r),
		.VGA_G(video_g),
		.VGA_B(video_b),
		.VGA_HS(hsync),
		.VGA_VS(vsync),
		.VGA_HBLANK(hblank),
		.VGA_VBLANK(vblank),

		.h_cnt(h_counter),
		.v_cnt(v_counter),
		.ce_pix(ce_pixel),
		.hsync(raw_hsync),
		.vsync(raw_vsync),
		.hblank(raw_hblank),
		.vblank(raw_vblank),

		.FLASH_PARAM(8'd0),
		.OSD_120HZ(is_120hz),
		.FRAME_DONE(frame_done_q),
		.BUFFER_MODE(buffer_mode),
		.DOT_MODE(effective_dot_mode),
		.FIFO_FULL_LED(fifo_full),
		.osd_bloom_width(effective_bloom_width),
		.osd_bloom_curve(effective_bloom_curve),
		.osd_expand_highlights(effective_tone_mapping == 2'd2),
		.osd_halo_filter(effective_halo_filter),
		.osd_halo_curve(effective_halo_curve),
		.osd_halo_knee(effective_halo_knee),
		.osd_phosphor_mode(effective_intra_frame_decay),
		.osd_inter_frame_phosphor_mode(effective_inter_frame_decay),
		.osd_halo_spread(effective_halo_spread),
		.osd_color_space(effective_color_space),
		.osd_presentation_color(effective_presentation_color),
		.osd_slot_mask(effective_slot_mask),
		.osd_slot_mask_rows(slot_mask_rows_q),
		.osd_full_bypass(effective_full_bypass)
	);

	assign mode_is_720p =
		mode_ready && !is_1080p && !is_480p && !is_240p;

endmodule
