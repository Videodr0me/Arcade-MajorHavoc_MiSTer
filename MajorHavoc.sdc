derive_pll_clocks
derive_clock_uncertainty

# Clock-domain crossings remain isolated even where clocks share the main PLL.
# All crossings use synchronizers, stable-data mailboxes, or the renderer's
# asynchronous source FIFO.
set emu_clk_50  [get_clocks {emu|pll|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}]
set emu_clk_125 [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set emu_clk_10  [get_clocks {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}]
set emu_clk_avg [get_clocks {emu|machine_clocks|avg_pll|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set emu_clk_hps [get_clocks {*|h2f_user0_clk}]
set board_clk_50 [get_clocks {FPGA_CLK2_50}]

set_clock_groups -asynchronous \
	-group $emu_clk_50 \
	-group $emu_clk_125 \
	-group $emu_clk_10 \
	-group $emu_clk_avg

# The standalone AVG PLL is outside the framework PLL hierarchy.
set_clock_groups -asynchronous \
	-group $emu_clk_hps \
	-group $emu_clk_avg

set_clock_groups -asynchronous \
	-group $board_clk_50 \
	-group $emu_clk_avg
