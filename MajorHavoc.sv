//============================================================================
//  Major Havoc for MiSTer
//
//  Written 2026 by Videodr0me
//
//  Original arcade hardware by Atari, 1983.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

	`include "build_id.v"

	logic [127:0] status;
	logic  [31:0] joystick_0;
	logic  [31:0] joystick_1;
	logic  [31:0] joystick;
	logic  [15:0] analog_0;
	logic   [8:0] spinner_0;
	logic  [24:0] ps2_mouse;
	logic   [1:0] buttons;
	logic         direct_video;
	wire   [21:0] gamma_bus;

	logic        ioctl_download;
	logic        ioctl_upload;
	logic        ioctl_upload_req;
	logic        ioctl_wr;
	logic [26:0] ioctl_addr;
	logic  [7:0] ioctl_dout;
	logic  [7:0] ioctl_din;
	logic [15:0] ioctl_index;

	localparam logic [15:0] IOCTL_ROM_INDEX   = 16'd0;
	localparam logic [15:0] IOCTL_NVRAM_INDEX = 16'd4;
	localparam logic [15:0] IOCTL_DIP_INDEX   = 16'd254;

	logic rom_selected;
	logic nvram_selected;
	logic dip_selected;
	logic rom_download;
	logic nvram_download;
	logic nvram_upload;
	logic dip_download;
	logic rom_write;
	logic nvram_write;
	logic dip_write;

	logic clk_50;
	logic clk_125;
	logic clk_10;
	logic clk_avg;
	logic core_clocks_locked;
	logic avg_clock_locked;
	logic machine_clocks_locked;

	logic [2:0] profile;
	logic       profile_off;
	logic       profile_touch;
	logic       profile_typical;
	logic       profile_overdriven;
	logic       profile_neon;
	logic       profile_stranger;
	logic       profile_custom_1;
	logic       profile_custom_2;
	logic [2:0] custom_bloom_width;
	logic [2:0] custom_halo;
	logic       custom_active;
	logic       custom_bloom_off;
	logic       custom_halo_off;
	logic [1:0] off_tone_mapping;
	logic [1:0] custom_1_tone_mapping;
	logic [1:0] custom_2_tone_mapping;
	logic [29:0] custom_1_settings;
	logic [29:0] custom_2_settings;
	logic        video_is_720p;

	assign profile = status[68:66] + 3'd2;
	assign profile_off        = (profile == 3'd0);
	assign profile_touch      = (profile == 3'd1);
	assign profile_typical    = (profile == 3'd2);
	assign profile_overdriven = (profile == 3'd3);
	assign profile_neon       = (profile == 3'd4);
	assign profile_stranger   = (profile == 3'd5);
	assign profile_custom_1   = (profile == 3'd6);
	assign profile_custom_2   = (profile == 3'd7);

	assign custom_bloom_width =
		profile_custom_2 ? status[99:97] : status[76:74];
	assign custom_halo =
		profile_custom_2 ? status[105:103] : status[82:80];
	assign custom_active = profile_custom_1 || profile_custom_2;
	assign custom_bloom_off =
		custom_active && (custom_bloom_width == 3'd0);
	assign custom_halo_off =
		custom_active && (custom_halo == 3'd0);

	// Remap menu order so Off uses internal tone-map code 3.
	assign off_tone_mapping = status[38:37] + 2'd3;
	assign custom_1_tone_mapping = status[73:72] + 2'd3;
	assign custom_2_tone_mapping = status[96:95] + 2'd3;

	assign custom_1_settings = {
		status[42:41],
		status[59:57],
		status[71:69], custom_1_tone_mapping,
		status[76:74], status[79:77], status[82:80], status[84:83],
		status[86:85], status[88:87], status[121], status[91:89],
		status[122]
	};

	assign custom_2_settings = {
		status[44:43],
		status[62:60],
		status[94:92], custom_2_tone_mapping,
		status[99:97], status[102:100], status[105:103], status[107:106],
		status[109:108], status[111:110], status[123], status[114:112],
		status[124]
	};

	localparam CONF_STR = {
		"Major Havoc;;",
		"-;",
		"P3,Video Profiles & Effects;",
		"P3-;",
		"P3O[68:66],Profile,80s Cruise Control,80s Overdrive,Neon Fever Dream,Plasma Storm,Custom 1,Custom 2,Off,A Touch of CRT;",
		"h7P3-;",
		"h7P3O[30:28],Dot Scale,2x,2.5x,3x,1x;",
		"h7P3O[38:37],Tone Mapping,Off,Linear 1,Linear 2,Bright;",
		"h7P3O[119:118],Inter-Frame Decay,Off,Short,Medium,Long;",
		"h7P3O[56:55],Intra-Frame Decay,Off,LUT A,LUT B,LUT C;",
		"h7P3-;",
		"h7P3-, For advanced settings;",
		"h7P3-, select Custom Profiles 1/2;",
		"h8P3-;",
		"h8P3-,Modern clarity with a touch;",
		"h8P3-,of old. Subtle halo & bloom;",
		"h8P3-,while vectors stay crisp.;",
		"h8P3-;",
		"h8P3-, For advanced settings;",
		"h8P3-, select Custom Profiles 1/2;",
		"h9P3-;",
		"h9P3-,Even richer glow and;",
		"h9P3-,stronger bloom. A restrained;",
		"h9P3-,color vector CRT look.;",
		"h9P3-;",
		"h9P3-, For advanced settings;",
		"h9P3-, select Custom Profiles 1/2;",
		"hAP3-;",
		"hAP3-,The arcade look you remember;",
		"hAP3-,hot vectors and heavy bloom;",
		"hAP3-,phosphor trails linger.;",
		"hAP3-;",
		"hAP3-, For advanced settings;",
		"hAP3-, select Custom Profiles 1/2;",
		"hBP3-;",
		"hBP3-,Midnight arcade. Voltage up.;",
		"hBP3-,Neon color & vector flicker.;",
		"hBP3-,Restless phosphor trails.;",
		"hBP3-;",
		"hBP3-,      Epilepsy warning;",
		"hBP3-,    excessive flashing;",
		"hBP3-,       bright lights;",
		"hCP3-;",
		"hCP3-,Reality leaves the cabinet;",
		"hCP3-,fast sparks and long trails;",
		"hCP3-,collide in a plasma storm.;",
		"hCP3-;",
		"hCP3-,      Epilepsy warning;",
		"hCP3-,    excessive flashing;",
		"hCP3-,       bright lights;",
		"hDP3O[71:69],> Dot Scale,2x,2.5x,3x,1x;",
		"hDP3O[73:72],> Tone Mapping,Off,Linear 1,Linear 2,Bright;",
		"hDP3O[76:74],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
		"hDD5P3O[79:77],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hDP3O[82:80],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
		"hDD6P3O[59:57],> Halo Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hDD6P3O[84:83],> Halo Spread,Original,Wide 1,Wide 2,Focus;",
		"hDD6P3O[42:41],> Halo Compression,16,32,64,24;",
		"hDP3O[86:85],> Inter-Frame Decay,Off,Short,Medium,Long;",
		"hDP3O[88:87],> Intra-Frame Decay,Off,LUT A,LUT B,LUT C;",
		"hDP3O[121],> Color Space,Off,Amp709;",
		"hDP3O[91:89],> Color Effect,Original,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
		"hDP3O[122],> Slot Mask,Off,On;",
		"hEP3O[94:92],> Dot Scale,2x,2.5x,3x,1x;",
		"hEP3O[96:95],> Tone Mapping,Off,Linear 1,Linear 2,Bright;",
		"hEP3O[99:97],> Bloom Width,Off,Thin,Tight,Soft,Normal,Broad,Wide-,Wide;",
		"hED5P3O[102:100],> Bloom Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hEP3O[105:103],> Halo,Off,0.25x,0.33x,0.5x,0.75x,1.0x,1.25x,1.5x;",
		"hED6P3O[62:60],> Halo Curve,Minimal,Min+,Mild,Mild+,Moderate,Mod+,Strong-,Strong;",
		"hED6P3O[107:106],> Halo Spread,Original,Wide 1,Wide 2,Focus;",
		"hED6P3O[44:43],> Halo Compression,16,32,64,24;",
		"hEP3O[109:108],> Inter-Frame Decay,Off,Short,Medium,Long;",
		"hEP3O[111:110],> Intra-Frame Decay,Off,LUT A,LUT B,LUT C;",
		"hEP3O[123],> Color Space,Off,Amp709;",
		"hEP3O[114:112],> Color Effect,Original,RBG,GRB,GBR,BRG,BGR,B/W,Negative;",
		"hEP3O[124],> Slot Mask,Off,On;",
		"P6,Video Timing & Geometry;",
		"P6-;",
		"P6O[7:5],Orientation,Normal,Rotate 90 CW,Rotate 180,Rotate 90 CCW,Mirror Horizontal,Mirror Vertical,Mirror H + 90 CW,Mirror H + 90 CCW;",
		"P6O[3],Zoom,Near,Far;",
		"P6-;",
		"P6O[40:39],Buffer Mode,EOF + VBL,VBL,EOF;",
		"D3P6O[25],120Hz (720p only),Off,On;",
		"h0P6O[115],Direct Video Scan Rate,15 kHz,31 kHz;",
		"P6-;",
		"P6-,Best left at default:;",
		"P6O[15:14],Aspect Ratio,Optimized,Stretched,Pixel Perfect;",
		"-;",
		"P2,Cabinet Audio Hardware;",
		"P2-;",
		"P2O[125],Audio Mixing,Measured,Schematics;",
		"P2O[120],Cabinet Filter,Measured,Off;",
		"-;",
		"P4,Input Controls;",
		"P4-;",
		"P4O[2],Direction,Normal,Reversed;",
		"P4O[10:8],Sensitivity,1.0x,0.75x,0.5x,0.25x,0.125x,1.25x,1.5x,2.0x;",
		"P4-;",
		"P4-,Sensitivity applies to all;",
		"P4-,roller input methods.;",
		"-;",
		"DIP;",
		"-;",
		"P5,Core Info;",
		"P5-;",
		"P5-,Atari Major Havoc Core;",
		"P5-,  by Videodr0me 2026;",
		"P5-;",
		"P5-,If you enjoy reliving the;",
		"P5-,golden age of arcade games,;",
		"P5-,please support my work and;",
		"P5-,future updates:;",
		"P5-;",
		"P5-,buymeacoffee.com/videodr0me;",
		"-;",
		"OR,Autosave NVRAM,Off,On;",
		"T4,Save NVRAM;",
		"-;",
		"P1,Pause Options;",
		"P1O[116],Pause when OSD is open,Off,On;",
		"P1O[117],Dim video after 10s,On,Off;",
		"-;",
		"R[0],Reset;",
		"J1,Jump / Fire / Start 1P,Shield / Start 2P,Coin Left,Coin Right,Pause;",
		"jn,A,B,R,L,Select;",
		"V,v1.0.", `BUILD_DATE
	};

	hps_io #(.CONF_STR(CONF_STR)) hps_io_inst
	(
		.clk_sys(clk_50),
		.HPS_BUS(HPS_BUS),
		.joystick_0(joystick_0),
		.joystick_1(joystick_1),
		.joystick_l_analog_0(analog_0),
		.spinner_0(spinner_0),
		.ps2_mouse(ps2_mouse),
		.buttons(buttons),
		.forced_scandoubler(),
		.direct_video(direct_video),
		.gamma_bus(gamma_bus),
		.status(status),
		.status_menumask({
			1'b0, profile_custom_2, profile_custom_1, profile_stranger,
			profile_neon, profile_overdriven, profile_typical, profile_touch,
			profile_off, custom_halo_off, custom_bloom_off, 1'b0,
			!video_is_720p, 1'b0, 1'b0, direct_video
		}),
		.ioctl_download(ioctl_download),
		.ioctl_upload(ioctl_upload),
		.ioctl_upload_req(ioctl_upload_req),
		.ioctl_upload_index(IOCTL_NVRAM_INDEX[7:0]),
		.ioctl_wr(ioctl_wr),
		.ioctl_rd(),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout),
		.ioctl_din(ioctl_din),
		.ioctl_index(ioctl_index)
	);

	assign rom_selected   = (ioctl_index == IOCTL_ROM_INDEX);
	assign nvram_selected = (ioctl_index == IOCTL_NVRAM_INDEX);
	assign dip_selected   = (ioctl_index == IOCTL_DIP_INDEX);

	assign rom_download   = ioctl_download && rom_selected;
	assign nvram_download = ioctl_download && nvram_selected;
	assign nvram_upload   = ioctl_upload && nvram_selected;
	assign dip_download   = ioctl_download && dip_selected;

	assign rom_write   = ioctl_wr && rom_download;
	assign nvram_write = ioctl_wr && nvram_download;
	assign dip_write   = ioctl_wr && dip_download;

	pll pll
	(
		.refclk(CLK_50M),
		.rst(1'b0),
		.outclk_0(clk_125),
		.outclk_1(clk_10),
		.outclk_2(clk_50),
		.locked(core_clocks_locked)
	);

	major_havoc_clocks machine_clocks
	(
		.refclk(CLK_50M),
		.reset(1'b0),
		.clk_avg(clk_avg),
		.locked(avg_clock_locked)
	);

	assign machine_clocks_locked = core_clocks_locked && avg_clock_locked;

	logic [7:0] dip_switch [0:7];
	initial begin
		dip_switch[0] = 8'h00;
		dip_switch[1] = 8'hff;
		dip_switch[2] = 8'h00;
		dip_switch[3] = 8'hff;
		dip_switch[4] = 8'hff;
		dip_switch[5] = 8'hff;
		dip_switch[6] = 8'hff;
		dip_switch[7] = 8'hff;
	end

	always @(posedge clk_50) begin
		if (dip_write && !ioctl_addr[26:3])
			dip_switch[ioctl_addr[2:0]] <= ioctl_dout;
	end

	assign joystick = joystick_0 | joystick_1;

	logic reset_request_50;
	logic reset_50;
	logic reset_10;
	logic reset_avg;
	logic reset_125;

	assign reset_request_50 = RESET || status[0] || buttons[1] ||
	                          rom_download || nvram_download ||
	                          !machine_clocks_locked;

	major_havoc_reset_sync reset_sync_50
	(
		.clk(clk_50),
		.reset_async(reset_request_50),
		.reset(reset_50)
	);

	major_havoc_reset_sync reset_sync_10
	(
		.clk(clk_10),
		.reset_async(reset_request_50),
		.reset(reset_10)
	);

	major_havoc_reset_sync reset_sync_avg
	(
		.clk(clk_avg),
		.reset_async(reset_request_50),
		.reset(reset_avg)
	);

	major_havoc_reset_sync reset_sync_125
	(
		.clk(clk_125),
		.reset_async(reset_request_50),
		.reset(reset_125)
	);

	logic [23:0] paused_rgb;
	logic  [7:0] raw_video_r;
	logic  [7:0] raw_video_g;
	logic  [7:0] raw_video_b;
	logic        pause_cpu_50;
	logic        pause_source_50 = 1'b0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic        pause_10_meta = 1'b0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic        pause_10 = 1'b0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic        pause_avg_meta = 1'b0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic        pause_avg = 1'b0;

	pause #(8, 8, 8, 50) pause_inst
	(
		.clk_sys(clk_50),
		.reset(reset_50),
		.user_button(joystick[8]),
		.pause_request(1'b0),
		.options({~status[117], status[116]}),
		.OSD_STATUS(OSD_STATUS),
		.r(raw_video_r),
		.g(raw_video_g),
		.b(raw_video_b),
		.pause_cpu(pause_cpu_50),
		.rgb_out(paused_rgb)
	);

	always_ff @(posedge clk_50) begin
		if (reset_50)
			pause_source_50 <= 1'b0;
		else
			pause_source_50 <= pause_cpu_50;
	end

	always_ff @(posedge clk_10) begin
		pause_10_meta <= pause_source_50;
		pause_10 <= pause_10_meta;
	end

	always_ff @(posedge clk_avg) begin
		pause_avg_meta <= pause_source_50;
		pause_avg <= pause_avg_meta;
	end

	logic       roller_read;
	logic [7:0] roller_position;

	major_havoc_roller roller
	(
		.clk(clk_10),
		.reset(reset_10),
		.roller_read(roller_read),
		.move_left(joystick[1]),
		.move_right(joystick[0]),
		.analog_x(analog_0[7:0]),
		.spinner(spinner_0),
		.mouse(ps2_mouse),
		.reverse(status[2]),
		.sensitivity(status[10:8]),
		.position(roller_position)
	);

	logic [7:0] nvram_data_out;
	logic       nvram_modified;
	logic       nvram_dirty = 1'b0;
	logic       nvram_dirty_meta = 1'b0;
	logic       nvram_dirty_sync = 1'b0;
	logic       nvram_dirty_sync_q = 1'b0;

	always_ff @(posedge clk_50) begin
		nvram_dirty_meta <= nvram_modified;
		nvram_dirty_sync <= nvram_dirty_meta;
		nvram_dirty_sync_q <= nvram_dirty_sync;

		if (!machine_clocks_locked || nvram_download || nvram_upload)
			nvram_dirty <= 1'b0;
		else if (nvram_dirty_sync && !nvram_dirty_sync_q)
			nvram_dirty <= 1'b1;
	end

	assign ioctl_upload_req =
		(status[27] && nvram_dirty) || status[4];
	assign ioctl_din =
		nvram_selected ? nvram_data_out : 8'h00;

	logic signed [15:0] machine_audio;
	logic [14:0] avg_x;
	logic [14:0] avg_y;
	logic  [7:0] avg_z;
	logic  [3:0] avg_color;
	logic        avg_beam_sample;
	logic        avg_is_dot;
	logic        avg_frame_done;
	logic        avg_halted;
	logic        avg_source_tick;
	logic        roller_light;

	major_havoc_core machine
	(
		.clk_cpu(clk_10),
		.clk_avg(clk_avg),
		.clk_host(clk_50),
		.reset_host(reset_request_50),
		.reset_cpu(reset_10),
		.reset_avg(reset_avg),
		.pause_cpu(pause_10),
		.pause_avg(pause_avg),
		.audio_schematic_mix(status[125]),
		.audio_filter_enable(!status[120]),
		.coin_left(joystick[6]),
		.coin_right(joystick[7]),
		.service(dip_switch[2][0]),
		.aux_coin_step(dip_switch[2][1]),
		.credit_to_start_two(dip_switch[2][2]),
		.fire_1(joystick_0[4] || ps2_mouse[0]),
		.shield_1(joystick_0[5] || ps2_mouse[1]),
		.fire_2(joystick_1[4]),
		.shield_2(joystick_1[5]),
		.roller(roller_position),
		.dsw_1(dip_switch[0]),
		.dsw_2(dip_switch[1]),
		.rom_write(rom_write),
		.rom_address(ioctl_addr[16:0]),
		.rom_data(ioctl_dout),
		.nvram_address(ioctl_addr[8:0]),
		.nvram_data_in(ioctl_dout),
		.nvram_write(nvram_write),
		.nvram_data_out(nvram_data_out),
		.nvram_modified(nvram_modified),
		.audio(machine_audio),
		.x_out(avg_x),
		.y_out(avg_y),
		.z_out(avg_z),
		.color_out(avg_color),
		.beam_on(avg_beam_sample),
		.is_dot(avg_is_dot),
		.frame_done(avg_frame_done),
		.avg_halted(avg_halted),
		.avg_source_tick(avg_source_tick),
		.roller_read(roller_read),
		.roller_light(roller_light)
	);

	logic        sdram_data_oe;
	logic [15:0] sdram_data_out;
	logic  [1:0] sdram_dqm;
	logic        video_hblank;
	logic        video_vblank;
	logic        fifo_full;

	assign SDRAM_CLK = ~clk_125;
	assign SDRAM_DQ = sdram_data_oe ? sdram_data_out : 16'hzzzz;
	assign SDRAM_DQML = sdram_dqm[0];
	assign SDRAM_DQMH = sdram_dqm[1];

	major_havoc_video video
	(
		.clk_50(clk_50),
		.clk_avg(clk_avg),
		.clk_125(clk_125),
		.reset(reset_125),
		.reset_source(reset_avg),
		.direct_video(direct_video),
		.direct_video_31khz(status[115]),
		.hdmi_height(HDMI_HEIGHT),
		.mode_120hz(status[25]),
		.aspect_ratio(status[15:14]),
		.buffer_mode(status[40:39]),
		.geometry_orientation(status[7:5]),
		.geometry_zoom_far(status[3]),
		.profile(profile),
		.off_dot_mode(status[30:28]),
		.off_tone_mapping(off_tone_mapping),
		.off_inter_frame_decay(status[119:118]),
		.off_intra_frame_decay(status[56:55]),
		.custom_1_settings(custom_1_settings),
		.custom_2_settings(custom_2_settings),
		.avg_x($signed(avg_x)),
		.avg_y($signed(avg_y)),
		.avg_z(avg_z),
		.avg_color(avg_color),
		.avg_beam_sample(avg_beam_sample),
		.avg_is_dot(avg_is_dot),
		.avg_source_tick(avg_source_tick),
		.frame_done(avg_frame_done),
		.video_arx(VIDEO_ARX),
		.video_ary(VIDEO_ARY),
		.ce_pixel(CE_PIXEL),
		.hblank(video_hblank),
		.vblank(video_vblank),
		.video_r(raw_video_r),
		.video_g(raw_video_g),
		.video_b(raw_video_b),
		.hsync(VGA_HS),
		.vsync(VGA_VS),
		.mode_is_720p(video_is_720p),
		.fifo_full(fifo_full),
		.ddram_clk(DDRAM_CLK),
		.ddram_busy(DDRAM_BUSY),
		.ddram_burst_count(DDRAM_BURSTCNT),
		.ddram_address(DDRAM_ADDR),
		.ddram_data_out(DDRAM_DOUT),
		.ddram_data_ready(DDRAM_DOUT_READY),
		.ddram_read(DDRAM_RD),
		.ddram_data_in(DDRAM_DIN),
		.ddram_byte_enable(DDRAM_BE),
		.ddram_write(DDRAM_WE),
		.sdram_data_in(SDRAM_DQ),
		.sdram_data_out(sdram_data_out),
		.sdram_data_oe(sdram_data_oe),
		.sdram_cke(SDRAM_CKE),
		.sdram_ncs(SDRAM_nCS),
		.sdram_nras(SDRAM_nRAS),
		.sdram_ncas(SDRAM_nCAS),
		.sdram_nwe(SDRAM_nWE),
		.sdram_dqm(sdram_dqm),
		.sdram_address(SDRAM_A),
		.sdram_bank(SDRAM_BA)
	);

	assign CLK_VIDEO = clk_125;
	assign VGA_R = paused_rgb[23:16];
	assign VGA_G = paused_rgb[15:8];
	assign VGA_B = paused_rgb[7:0];
	assign VGA_DE = !(video_hblank || video_vblank);
	assign VGA_F1 = 1'b0;
	assign VGA_SL = 2'b00;
	assign VGA_SCALER = 1'b0;
	assign VGA_DISABLE = 1'b0;
	assign HDMI_FREEZE = 1'b0;
	assign HDMI_BLACKOUT = 1'b0;
	assign HDMI_BOB_DEINT = 1'b0;

	assign AUDIO_L = machine_audio;
	assign AUDIO_R = AUDIO_L;
	assign AUDIO_S = 1'b1;
	assign AUDIO_MIX = 2'b00;

	assign LED_USER = fifo_full || ioctl_download;
	assign LED_DISK = {1'b0, roller_light};
	assign LED_POWER = 2'b00;
	assign BUTTONS = 2'b00;

	assign ADC_BUS = 4'bzzzz;
	assign USER_OUT = 7'h7f;
	assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
	assign {SD_SCK, SD_MOSI, SD_CS} = 3'bzzz;

`ifdef MISTER_FB
	assign FB_EN = 1'b0;
	assign FB_FORMAT = 5'd0;
	assign FB_WIDTH = 12'd0;
	assign FB_HEIGHT = 12'd0;
	assign FB_BASE = 32'd0;
	assign FB_STRIDE = 14'd0;
	assign FB_FORCE_BLANK = 1'b0;
`ifdef MISTER_FB_PALETTE
	assign FB_PAL_CLK = 1'b0;
	assign FB_PAL_ADDR = 8'd0;
	assign FB_PAL_DOUT = 24'd0;
	assign FB_PAL_WR = 1'b0;
`endif
`endif

`ifdef MISTER_DUAL_SDRAM
	assign SDRAM2_CLK = 1'bz;
	assign SDRAM2_A = 13'hzzz;
	assign SDRAM2_BA = 2'bzz;
	assign SDRAM2_DQ = 16'hzzzz;
	assign {SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE} = 4'hf;
`endif

endmodule
