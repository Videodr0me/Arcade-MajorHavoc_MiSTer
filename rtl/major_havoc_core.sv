//============================================================================
//  Atari Major Havoc machine
//
//  Written 2026 by Videodr0me
//
//  Implements the production dual-6502 main board from Atari drawing package
//  SP-252 with its independent 10.000 MHz CPU/audio and 12.096 MHz AVG clocks.
//============================================================================

module major_havoc_core
(
	input  logic        clk_cpu,
	input  logic        clk_avg,
	input  logic        clk_host,
	input  logic        reset_host,
	input  logic        reset_cpu,
	input  logic        reset_avg,
	input  logic        pause_cpu,
	input  logic        pause_avg,
	input  logic        audio_schematic_mix,
	input  logic        audio_filter_enable,

	input  logic        coin_left,
	input  logic        coin_right,
	input  logic        service,
	input  logic        aux_coin_step,
	input  logic        credit_to_start_two,
	input  logic        fire_1,
	input  logic        shield_1,
	input  logic        fire_2,
	input  logic        shield_2,
	input  logic  [7:0] roller,
	input  logic  [7:0] dsw_1,
	input  logic  [7:0] dsw_2,

	input  logic        rom_write,
	input  logic [16:0] rom_address,
	input  logic  [7:0] rom_data,

	input  logic  [8:0] nvram_address,
	input  logic  [7:0] nvram_data_in,
	input  logic        nvram_write,
	output logic  [7:0] nvram_data_out,
	output logic        nvram_modified,

	output logic signed [15:0] audio,
	output logic [14:0] x_out,
	output logic [14:0] y_out,
	output logic  [7:0] z_out,
	output logic  [3:0] color_out,
	output logic        beam_on,
	output logic        is_dot,
	output logic        frame_done,
	output logic        avg_halted,
	output logic        avg_source_tick,
	output logic        roller_read,
	output logic        roller_light
);

	localparam logic [16:0] ROM_ALPHA_FIXED_BASE = 17'h00000;
	localparam logic [16:0] ROM_ALPHA_BANK_BASE  = 17'h08000;
	localparam logic [16:0] ROM_GAMMA_BASE       = 17'h10000;
	localparam logic [16:0] ROM_VECTOR_BASE      = 17'h14000;
	localparam logic [16:0] ROM_VECTOR_BANK_BASE = 17'h16000;
	localparam logic [16:0] ROM_STATE_BASE       = 17'h1e000;
	localparam logic [16:0] ROM_STATE_END        = 17'h1e100;

	logic [16:0] bank_rom_download_offset;
	logic [14:0] bank_rom_download_address;
	assign bank_rom_download_offset =
		rom_address - ROM_VECTOR_BANK_BASE;
	assign bank_rom_download_address = bank_rom_download_offset[14:0];

	logic ce_alpha_2m5;
	logic ce_gamma_1m25;
	logic ce_irq_4k882;
	logic ce_watchdog_2k441;
	logic watchdog_reset;
	logic alpha_reset;
	logic alpha_cycle_request;
	logic alpha_cycle;
	logic gamma_cycle;
	logic avg_master_cycle;
	logic avg_sequencer_cycle;
	logic [2:0] avg_phase = 3'd0;

	major_havoc_clock_enables clocks
	(
		.clk_10(clk_cpu),
		.reset(reset_cpu),
		.ce_alpha_2m5(ce_alpha_2m5),
		.ce_gamma_1m25(ce_gamma_1m25),
		.ce_irq_4k882(ce_irq_4k882),
		.ce_watchdog_2k441(ce_watchdog_2k441)
	);

	assign alpha_reset = reset_cpu || watchdog_reset;
	assign alpha_cycle_request = ce_alpha_2m5 && !pause_cpu;
	assign gamma_cycle = ce_gamma_1m25 && !pause_cpu;
	assign avg_master_cycle = !pause_avg || reset_avg;
	assign avg_sequencer_cycle = (&avg_phase) && avg_master_cycle;

	always_ff @(posedge clk_avg) begin
		if (reset_avg)
			avg_phase <= 3'd0;
		else
			avg_phase <= avg_phase + 1'd1;
	end

	logic [15:0] alpha_address;
	logic  [7:0] alpha_data_in;
	logic  [7:0] alpha_data_out;
	logic        alpha_rw_n;
	logic        alpha_sync;
	logic        alpha_irq_n;

	logic [15:0] gamma_address;
	logic  [7:0] gamma_data_in;
	logic  [7:0] gamma_data_out;
	logic        gamma_rw_n;
	logic        gamma_sync;
	logic        gamma_irq_n;
	logic        gamma_nmi_n;
	logic        gamma_run;
	logic        alpha_ready;

	logic [8:0] controls_meta = 9'd0;
	logic [8:0] controls_q = 9'd0;
	logic [15:0] dsw_meta = 16'hffff;
	logic [15:0] dsw_q = 16'hffff;
	logic        audio_schematic_mix_meta = 1'b0;
	logic        audio_schematic_mix_q = 1'b0;
	logic        audio_filter_meta = 1'b1;
	logic        audio_filter_q = 1'b1;
	logic        avg_halted_cpu_meta = 1'b1;
	logic        avg_halted_cpu = 1'b1;

	wire coin_left_q = controls_q[8];
	wire coin_right_q = controls_q[7];
	wire service_q = controls_q[6];
	wire aux_coin_step_q = controls_q[5];
	wire credit_to_start_two_q = controls_q[4];
	wire fire_1_q = controls_q[3];
	wire shield_1_q = controls_q[2];
	wire fire_2_q = controls_q[1];
	wire shield_2_q = controls_q[0];

	always_ff @(posedge clk_cpu) begin
		controls_meta <= {
			coin_left, coin_right, service, aux_coin_step,
			credit_to_start_two, fire_1, shield_1, fire_2, shield_2
		};
		controls_q <= controls_meta;
		dsw_meta <= {dsw_1, dsw_2};
		dsw_q <= dsw_meta;
		audio_schematic_mix_meta <= audio_schematic_mix;
		audio_schematic_mix_q <= audio_schematic_mix_meta;
		audio_filter_meta <= audio_filter_enable;
		audio_filter_q <= audio_filter_meta;
		avg_halted_cpu_meta <= avg_halted;
		avg_halted_cpu <= avg_halted_cpu_meta;
	end

	major_havoc_cpu alpha_cpu
	(
		.clk(clk_cpu),
		.reset_n(!alpha_reset),
		.enable(alpha_cycle),
		.ready(alpha_ready),
		.irq_n(alpha_irq_n),
		.nmi_n(1'b1),
		.data_in(alpha_data_in),
		.address(alpha_address),
		.data_out(alpha_data_out),
		.rw_n(alpha_rw_n),
		.sync(alpha_sync)
	);

	major_havoc_cpu gamma_cpu
	(
		.clk(clk_cpu),
		.reset_n(!alpha_reset && gamma_run),
		.enable(gamma_cycle),
		.ready(1'b1),
		.irq_n(gamma_irq_n),
		.nmi_n(gamma_nmi_n),
		.data_in(gamma_data_in),
		.address(gamma_address),
		.data_out(gamma_data_out),
		.rw_n(gamma_rw_n),
		.sync(gamma_sync)
	);

	logic alpha_ram_a_select;
	logic alpha_ram_b_select;
	logic alpha_bank_ram_select;
	logic beta_ram_select;
	logic alpha_bank_rom_select;
	logic alpha_fixed_rom_select;
	logic vector_memory_select;
	logic gamma_ram_select;
	logic gamma_pokey_select;
	logic gamma_input_select;
	logic gamma_alpha_read_select;
	logic gamma_roller_select;
	logic gamma_dsw_select;
	logic gamma_eeprom_select;
	logic gamma_rom_select;
	logic alpha_write;
	logic gamma_write;

	assign alpha_ram_a_select = (alpha_address[15:9] == 7'b0000000);
	assign alpha_ram_b_select = (alpha_address[15:9] == 7'b0000100);
	assign alpha_bank_ram_select =
		(alpha_address >= 16'h0200 && alpha_address <= 16'h07ff) ||
		(alpha_address >= 16'h0a00 && alpha_address <= 16'h0fff);
	assign beta_ram_select = (alpha_address[15:11] == 5'b00011);
	assign alpha_bank_rom_select = (alpha_address[15:13] == 3'b001);
	assign alpha_fixed_rom_select = alpha_address[15];
	assign vector_memory_select = (alpha_address[15:14] == 2'b01);

	// SP-252 sheet 4B stretches Alpha's 400 ns cycle while /VMEM is active.
	// Here Alpha waits until the vector-memory access finishes. Synchronization
	// can add one Alpha period but never releases the CPU early.
	assign alpha_cycle = alpha_cycle_request &&
	                     (!vector_memory_select || alpha_ready);

	assign gamma_ram_select = (gamma_address[15:13] == 3'b000);
	assign gamma_pokey_select = (gamma_address[15:11] == 5'b00100);
	assign gamma_input_select = (gamma_address[15:11] == 5'b00101);
	assign gamma_alpha_read_select = (gamma_address[15:11] == 5'b00110);
	assign gamma_roller_select = (gamma_address[15:11] == 5'b00111);
	assign gamma_dsw_select = (gamma_address[15:11] == 5'b01000);
	assign gamma_eeprom_select = (gamma_address[15:13] == 3'b011);
	assign gamma_rom_select = gamma_address[15];

	assign alpha_write = alpha_cycle && !alpha_rw_n;
	assign gamma_write = gamma_cycle && !gamma_rw_n;
	assign roller_read =
		gamma_cycle && gamma_run && gamma_rw_n && gamma_roller_select;

	// SP-252 sheet 4B clocks the watchdog at 10 MHz / 4096. Its /256
	// counter asserts /RESET Alpha after 104.8576 ms and the following
	// terminal count releases it after the same interval.
	major_havoc_watchdog watchdog
	(
		.clk(clk_cpu),
		.reset(reset_cpu),
		.pause(pause_cpu),
		.tick(ce_watchdog_2k441),
		.clear(alpha_write && alpha_address == 16'h1680),
		.alpha_reset(watchdog_reset)
	);

	(* ramstyle = "M10K" *) logic [7:0] alpha_ram_a [0:511];
	(* ramstyle = "M10K" *) logic [7:0] alpha_ram_b [0:511];
	(* ramstyle = "M10K" *) logic [7:0] alpha_bank_ram [0:4095];
	(* ramstyle = "M10K" *) logic [7:0] beta_ram [0:2047];
	(* ramstyle = "M10K" *) logic [7:0] gamma_ram [0:2047];

	logic [7:0] alpha_fixed_rom_q;
	logic [7:0] alpha_bank_rom_q;
	logic [7:0] gamma_rom_q;
	logic [7:0] alpha_ram_a_q;
	logic [7:0] alpha_ram_b_q;
	logic [7:0] alpha_bank_ram_q;
	logic [7:0] beta_ram_q;
	logic [7:0] gamma_ram_q;
	logic [1:0] alpha_rom_bank;
	logic       alpha_ram_bank;
	integer ram_index;

	major_havoc_dpram #(
		.DATA_WIDTH(8),
		.ADDR_WIDTH(15)
	) alpha_fixed_rom (
		.clk_a(clk_cpu),
		.addr_a(alpha_address[14:0]),
		.data_a(8'd0),
		.we_a(1'b0),
		.q_a(alpha_fixed_rom_q),
		.clk_b(clk_host),
		.addr_b(rom_address[14:0]),
		.data_b(rom_data),
		.we_b(rom_write &&
		      rom_address >= ROM_ALPHA_FIXED_BASE &&
		      rom_address < ROM_ALPHA_BANK_BASE),
		.q_b()
	);

	major_havoc_dpram #(
		.DATA_WIDTH(8),
		.ADDR_WIDTH(15)
	) alpha_bank_rom (
		.clk_a(clk_cpu),
		.addr_a({alpha_rom_bank, alpha_address[12:0]}),
		.data_a(8'd0),
		.we_a(1'b0),
		.q_a(alpha_bank_rom_q),
		.clk_b(clk_host),
		.addr_b(rom_address[14:0]),
		.data_b(rom_data),
		.we_b(rom_write &&
		      rom_address >= ROM_ALPHA_BANK_BASE &&
		      rom_address < ROM_GAMMA_BASE),
		.q_b()
	);

	major_havoc_dpram #(
		.DATA_WIDTH(8),
		.ADDR_WIDTH(14)
	) gamma_rom (
		.clk_a(clk_cpu),
		.addr_a(gamma_address[13:0]),
		.data_a(8'd0),
		.we_a(1'b0),
		.q_a(gamma_rom_q),
		.clk_b(clk_host),
		.addr_b(rom_address[13:0]),
		.data_b(rom_data),
		.we_b(rom_write &&
		      rom_address >= ROM_GAMMA_BASE &&
		      rom_address < ROM_VECTOR_BASE),
		.q_b()
	);

	initial begin
		for (ram_index = 0; ram_index < 512; ram_index = ram_index + 1) begin
			alpha_ram_a[ram_index] = 8'h00;
			alpha_ram_b[ram_index] = 8'h00;
		end
		for (ram_index = 0; ram_index < 4096; ram_index = ram_index + 1)
			alpha_bank_ram[ram_index] = 8'h00;
		for (ram_index = 0; ram_index < 2048; ram_index = ram_index + 1) begin
			beta_ram[ram_index] = 8'h00;
			gamma_ram[ram_index] = 8'h00;
		end
	end

	always @(posedge clk_cpu) begin
		alpha_ram_a_q <= alpha_ram_a[alpha_address[8:0]];
		alpha_ram_b_q <= alpha_ram_b[alpha_address[8:0]];
		alpha_bank_ram_q <= alpha_bank_ram[
			{alpha_ram_bank, alpha_address[10:0]}];
		beta_ram_q <= beta_ram[alpha_address[10:0]];
		gamma_ram_q <= gamma_ram[gamma_address[10:0]];

		if (alpha_write && alpha_ram_a_select)
			alpha_ram_a[alpha_address[8:0]] <= alpha_data_out;
		if (alpha_write && alpha_ram_b_select)
			alpha_ram_b[alpha_address[8:0]] <= alpha_data_out;
		if (alpha_write && alpha_bank_ram_select)
			alpha_bank_ram[{alpha_ram_bank, alpha_address[10:0]}] <=
				alpha_data_out;
		if (alpha_write && beta_ram_select)
			beta_ram[alpha_address[10:0]] <= alpha_data_out;
		if (gamma_write && gamma_ram_select)
			gamma_ram[gamma_address[10:0]] <= gamma_data_out;
	end

	logic  [7:0] alpha_to_gamma;
	logic  [7:0] gamma_to_alpha;
	logic        alpha_xmtd;
	logic        alpha_rcvd;
	logic        gamma_xmtd;
	logic        gamma_rcvd;
	logic        gamma_nmi_pending;
	logic  [7:0] output_0;
	logic [10:0] alpha_cycle_count;

	assign gamma_run = output_0[3];
	assign roller_light = output_0[0];
	assign gamma_nmi_n = !gamma_nmi_pending;

	always_ff @(posedge clk_cpu) begin
		if (alpha_reset) begin
			alpha_to_gamma <= 8'h00;
			gamma_to_alpha <= 8'h00;
			alpha_xmtd <= 1'b0;
			alpha_rcvd <= 1'b0;
			gamma_xmtd <= 1'b0;
			gamma_rcvd <= 1'b0;
			gamma_nmi_pending <= 1'b0;
			output_0 <= 8'h00;
			alpha_rom_bank <= 2'b00;
			alpha_ram_bank <= 1'b0;
			alpha_cycle_count <= 11'd0;
		end else begin
			if (alpha_cycle)
				alpha_cycle_count <= alpha_cycle_count + 1'd1;

			if (alpha_write && alpha_address == 16'h1600) begin
				output_0 <= alpha_data_out;
				if (!alpha_data_out[3]) begin
					alpha_xmtd <= 1'b0;
					alpha_rcvd <= 1'b0;
					gamma_xmtd <= 1'b0;
					gamma_rcvd <= 1'b0;
					gamma_nmi_pending <= 1'b0;
				end
			end

			if (alpha_write && alpha_address == 16'h1740)
				alpha_rom_bank <= alpha_data_out[1:0];
			if (alpha_write && alpha_address == 16'h1780)
				alpha_ram_bank <= alpha_data_out[0];

			if (alpha_write && alpha_address == 16'h17c0) begin
				alpha_to_gamma <= alpha_data_out;
				alpha_xmtd <= 1'b1;
				gamma_rcvd <= 1'b0;
				gamma_nmi_pending <= 1'b1;
			end else if (gamma_cycle && gamma_nmi_pending) begin
				gamma_nmi_pending <= 1'b0;
			end

			if (gamma_cycle && gamma_rw_n && gamma_alpha_read_select) begin
				gamma_rcvd <= 1'b1;
				alpha_xmtd <= 1'b0;
			end

			if (gamma_write && gamma_address[15:11] == 5'b01010) begin
				gamma_to_alpha <= gamma_data_out;
				gamma_xmtd <= 1'b1;
				alpha_rcvd <= 1'b0;
			end

			if (alpha_cycle && alpha_rw_n &&
			    alpha_address[15:8] == 8'h10) begin
				alpha_rcvd <= 1'b1;
				gamma_xmtd <= 1'b0;
			end
		end
	end

	logic [3:0] alpha_irq_counter;
	logic       alpha_irq_enabled;
	logic       alpha_irq_pending;
	logic [3:0] gamma_irq_counter;

	assign alpha_irq_n = !alpha_irq_pending;
	assign gamma_irq_n = !gamma_irq_counter[3];

	always_ff @(posedge clk_cpu) begin
		if (alpha_reset) begin
			alpha_irq_counter <= 4'd0;
			alpha_irq_enabled <= 1'b1;
			alpha_irq_pending <= 1'b0;
			gamma_irq_counter <= 4'd0;
		end else begin
			if (ce_irq_4k882 && !pause_cpu) begin
				if (alpha_irq_enabled) begin
					alpha_irq_counter <= alpha_irq_counter + 1'd1;
					if ((alpha_irq_counter + 1'd1) >= 4'd12) begin
						alpha_irq_pending <= 1'b1;
						alpha_irq_enabled <= 1'b0;
					end
				end
				gamma_irq_counter <= gamma_irq_counter + 1'd1;
			end

			if (alpha_write && alpha_address == 16'h1700) begin
				alpha_irq_counter <= 4'd0;
				alpha_irq_enabled <= 1'b1;
				alpha_irq_pending <= 1'b0;
			end
			if (gamma_write && gamma_dsw_select)
				gamma_irq_counter <= 4'd0;
		end
	end

	logic [7:0] alpha_input;
	logic [7:0] gamma_input;
	logic [7:0] vector_data_out;
	logic [7:0] eeprom_data_out;
	logic [3:0] pokey_address;
	logic [7:0] pokey_data [0:3];
	logic [7:0] pokey_audio [0:3];
	logic [7:0] pokey_data_out;
	logic [7:0] pokey_0_pins;
	logic [3:0] pokey_select_n;

	always_comb begin
		alpha_input = {
			output_0[5] ? !service_q : !coin_right_q,
			output_0[5] ? !credit_to_start_two_q : !coin_left_q,
			!aux_coin_step_q,
			1'b1,
			gamma_rcvd,
			gamma_xmtd,
			!alpha_cycle_count[10],
			avg_halted_cpu
		};

		gamma_input = {
			!fire_1_q,
			!shield_1_q,
			!fire_2_q,
			!shield_2_q,
			2'b11,
			alpha_rcvd,
			alpha_xmtd
		};

		alpha_data_in = 8'hff;
		if (alpha_ram_a_select)
			alpha_data_in = alpha_ram_a_q;
		else if (alpha_ram_b_select)
			alpha_data_in = alpha_ram_b_q;
		else if (alpha_bank_ram_select)
			alpha_data_in = alpha_bank_ram_q;
		else if (alpha_address[15:8] == 8'h10)
			alpha_data_in = gamma_to_alpha;
		else if (alpha_address[15:8] == 8'h12)
			alpha_data_in = alpha_input;
		else if (beta_ram_select)
			alpha_data_in = beta_ram_q;
		else if (alpha_bank_rom_select)
			alpha_data_in = alpha_bank_rom_q;
		else if (vector_memory_select)
			alpha_data_in = vector_data_out;
		else if (alpha_fixed_rom_select)
			alpha_data_in = alpha_fixed_rom_q;

		gamma_data_in = 8'hff;
		if (gamma_ram_select)
			gamma_data_in = gamma_ram_q;
		else if (gamma_pokey_select)
			gamma_data_in = pokey_data_out;
		else if (gamma_input_select)
			gamma_data_in = gamma_input;
		else if (gamma_alpha_read_select)
			gamma_data_in = alpha_to_gamma;
		else if (gamma_roller_select)
			gamma_data_in = roller;
		else if (gamma_dsw_select)
			gamma_data_in = dsw_q[7:0];
		else if (gamma_eeprom_select)
			gamma_data_in = eeprom_data_out;
		else if (gamma_rom_select)
			gamma_data_in = gamma_rom_q;
	end

	major_havoc_eeprom eeprom
	(
		.cpu_clk(clk_cpu),
		.host_clk(clk_host),
		.cpu_reset(reset_cpu),
		.cpu_address(gamma_address[8:0]),
		.cpu_data_in(gamma_data_out),
		.cpu_write(gamma_write && gamma_eeprom_select),
		.cpu_data_out(eeprom_data_out),
		.modified(nvram_modified),
		.host_address(nvram_address),
		.host_data_in(nvram_data_in),
		.host_write(nvram_write),
		.host_data_out(nvram_data_out)
	);

	// Invert the MRA DIP byte because POKEY ALLPOT inverts its input pins.
	assign pokey_0_pins = ~dsw_q[15:8];
	assign pokey_address = {gamma_address[5], gamma_address[2:0]};
	assign pokey_select_n[0] =
		!(gamma_pokey_select && gamma_address[4:3] == 2'b00);
	assign pokey_select_n[1] =
		!(gamma_pokey_select && gamma_address[4:3] == 2'b01);
	assign pokey_select_n[2] =
		!(gamma_pokey_select && gamma_address[4:3] == 2'b10);
	assign pokey_select_n[3] =
		!(gamma_pokey_select && gamma_address[4:3] == 2'b11);
	assign pokey_data_out = pokey_data[gamma_address[4:3]];

	pokey pokey_0
	(
		.ADDR(pokey_address), .DIN(gamma_data_out), .DOUT(pokey_data[0]),
		.DOUT_OE_L(), .RW_L(gamma_rw_n), .CS(1'b1),
		.CS_L(pokey_select_n[0]), .AUDIO_OUT(pokey_audio[0]),
		.PIN(pokey_0_pins), .ENA(gamma_cycle && gamma_run), .CLK(clk_cpu)
	);

	pokey pokey_1
	(
		.ADDR(pokey_address), .DIN(gamma_data_out), .DOUT(pokey_data[1]),
		.DOUT_OE_L(), .RW_L(gamma_rw_n), .CS(1'b1),
		.CS_L(pokey_select_n[1]), .AUDIO_OUT(pokey_audio[1]),
		.PIN(8'h00), .ENA(gamma_cycle && gamma_run), .CLK(clk_cpu)
	);

	pokey pokey_2
	(
		.ADDR(pokey_address), .DIN(gamma_data_out), .DOUT(pokey_data[2]),
		.DOUT_OE_L(), .RW_L(gamma_rw_n), .CS(1'b1),
		.CS_L(pokey_select_n[2]), .AUDIO_OUT(pokey_audio[2]),
		.PIN(8'h00), .ENA(gamma_cycle && gamma_run), .CLK(clk_cpu)
	);

	pokey pokey_3
	(
		.ADDR(pokey_address), .DIN(gamma_data_out), .DOUT(pokey_data[3]),
		.DOUT_OE_L(), .RW_L(gamma_rw_n), .CS(1'b1),
		.CS_L(pokey_select_n[3]), .AUDIO_OUT(pokey_audio[3]),
		.PIN(8'h00), .ENA(gamma_cycle && gamma_run), .CLK(clk_cpu)
	);

	major_havoc_audio audio_stage
	(
		.clk(clk_cpu),
		.reset(reset_cpu),
		.ce_1m25(gamma_cycle && gamma_run),
		.schematic_mix(audio_schematic_mix_q),
		.filter_enable(audio_filter_q),
		.pokey_0(pokey_audio[0]),
		.pokey_1(pokey_audio[1]),
		.pokey_2(pokey_audio[2]),
		.pokey_3(pokey_audio[3]),
		.audio(audio)
	);

	logic color_write;
	logic avg_go_request;
	logic avg_reset_request;
	logic [14:0] avg_x;
	logic [14:0] avg_y;
	logic  [7:0] avg_z;
	logic  [3:0] avg_color;
	logic        avg_dot;
	logic        avg_halt_event;
	logic        avg_frame_visible = 1'b0;
	logic  [1:0] axis_invert_meta = 2'b00;
	logic  [1:0] axis_invert_q = 2'b00;
	wire         avg_visible_sample =
		avg_master_cycle && (|avg_color) && (|avg_z);

	assign color_write = alpha_write &&
	                     (alpha_address[15:5] == 11'b00010100000);
	assign avg_go_request =
		alpha_write && (alpha_address == 16'h1640);
	assign avg_reset_request =
		alpha_write && (alpha_address == 16'h16c0);

	always_ff @(posedge clk_avg) begin
		axis_invert_meta <= output_0[7:6];
		axis_invert_q <= axis_invert_meta;
		if (reset_avg || avg_halted)
			avg_frame_visible <= 1'b0;
		else if (avg_visible_sample)
			avg_frame_visible <= 1'b1;
	end

	// The watchdog resets Alpha and its control latches without resetting the AVG.
	major_havoc_avg avg
	(
		.host_clk(clk_host),
		.cpu_clk(clk_cpu),
		.avg_clk(clk_avg),
		.host_reset(reset_host),
		.cpu_reset(reset_cpu),
		.avg_reset(reset_avg),
		.master_ce(avg_master_cycle),
		.sequencer_ce(avg_sequencer_cycle),
		.cpu_avg_reset(avg_reset_request),
		.cpu_avg_go(avg_go_request),
		.sparkle_seed(alpha_address[2:0]),
		.cpu_cycle(alpha_cycle),
		.cpu_cs(vector_memory_select),
		.cpu_rw(alpha_rw_n),
		.cpu_addr(alpha_address[13:0]),
		.cpu_data_in(alpha_data_out),
		.cpu_data_out(vector_data_out),
		.cpu_ready(alpha_ready),
		.color_wr(color_write),
		.color_addr(alpha_address[4:0]),
		.color_data(alpha_data_out),
		.vector_rom_wr(rom_write &&
			rom_address >= ROM_VECTOR_BASE &&
			rom_address < ROM_VECTOR_BANK_BASE),
		.vector_rom_addr(rom_address[12:0]),
		.vector_rom_data(rom_data),
		.bank_rom_wr(rom_write &&
			rom_address >= ROM_VECTOR_BANK_BASE &&
			rom_address < ROM_STATE_BASE),
		.bank_rom_addr(bank_rom_download_address),
		.bank_rom_data(rom_data),
		.state_prom_wr(rom_write &&
			rom_address >= ROM_STATE_BASE &&
			rom_address < ROM_STATE_END),
		.state_prom_addr(rom_address[7:0]),
		.state_prom_data(rom_data[3:0]),
		.halted(avg_halted),
		.halt_event(avg_halt_event),
		.x_out(avg_x),
		.y_out(avg_y),
		.z_out(avg_z),
		.color_out(avg_color),
		.is_dot_out(avg_dot)
	);

	assign x_out = axis_invert_q[0] ? (~avg_x + 1'd1) : avg_x;
	assign y_out = axis_invert_q[1] ? (~avg_y + 1'd1) : avg_y;
	assign z_out = avg_z;
	assign color_out = avg_color;
	assign is_dot = avg_dot;
	assign avg_source_tick = avg_master_cycle;
	assign beam_on = avg_visible_sample;
	assign frame_done =
		avg_halt_event && (avg_frame_visible || avg_visible_sample);

endmodule
