-- Digital AVG timer and integrator.
-- Converts normalized DVX/DVY, timer, and linear scale into 15-bit coordinates.
-- (C) 2012 Jeroen Domburg (jeroen AT spritesmods.com)
--
-- Modified by Videodr0me for MiSTer vector rendering, 2026.
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity vector_drawer is
    Port ( clk : in  STD_LOGIC;
           master_ce: in STD_LOGIC;
           hw_timer : in  STD_LOGIC_VECTOR (14 downto 0);
           is_svec : in STD_LOGIC;
           linear_scale : in STD_LOGIC_VECTOR (7 downto 0);
           rel_x : in  STD_LOGIC_VECTOR (12 downto 0);
           rel_y : in  STD_LOGIC_VECTOR (12 downto 0);
           zero: in STD_LOGIC;
           abort_draw: in STD_LOGIC;
           draw : in  STD_LOGIC;
           done : out STD_LOGIC;
           is_dot : out STD_LOGIC;
           xout: out STD_LOGIC_VECTOR(14 downto 0);
           yout: out STD_LOGIC_VECTOR(14 downto 0)
     );
end vector_drawer;

architecture Behavioral of vector_drawer is
    -- Signed positions with 18 fractional bits and one guard bit.
    signal xpos: STD_LOGIC_VECTOR(33 downto 0);
    signal ypos: STD_LOGIC_VECTOR(33 downto 0);
    signal normrel_x : STD_LOGIC_VECTOR (12 downto 0);
    signal normrel_y : STD_LOGIC_VECTOR (12 downto 0);
    -- Draw duration in 12.096 MHz master-clock cycles.
    -- VCTR (OP1=0): (0x8000 - hw_timer), up to 32768 master clocks
    -- SVEC (OP1=1): (0x100 - hw_timer[7:0]), up to 256 master clocks
    signal draw_target : STD_LOGIC_VECTOR (15 downto 0);
    signal itsdone: std_logic;
    signal draw_counter: STD_LOGIC_VECTOR(15 downto 0);
    -- Linear scale changes each step without changing draw duration.
    signal scale_factor : STD_LOGIC_VECTOR(8 downto 0);

    signal step_x_full : STD_LOGIC_VECTOR(22 downto 0);
    signal step_y_full : STD_LOGIC_VECTOR(22 downto 0);
begin

    is_dot <= '1' when (rel_x = "0000000000000" and rel_y = "0000000000000") else '0';

    -- The scale factor is 256 at 0x00 and 1 at 0xFF.
    scale_factor <= (('0' & (linear_scale xor x"FF")) + 1);

    step_x_full <= SIGNED(normrel_x) * UNSIGNED(scale_factor);
    step_y_full <= SIGNED(normrel_y) * UNSIGNED(scale_factor);

    -- Abort or center first, then start or continue a draw.
    process(clk)
    begin
        if clk'event and clk='1' then
            if master_ce='1' then
                -- VGGO stops the current vector without changing beam position.
                if abort_draw='1' then
                    draw_counter<=(others=>'0');
                    draw_target<=(others=>'0');
                    itsdone<='1';
                -- Zero clears the position; CENTER still runs its timer.
                elsif zero='1' then
                    xpos<=(others=>'0');
                    ypos<=(others=>'0');
                    if draw='1' then
                        normrel_x<=rel_x;
                        normrel_y<=rel_y;
                        if is_svec='1' then
                            draw_target <= x"0100" - (x"00" & hw_timer(7 downto 0));
                        else
                            draw_target <= x"8000" - ('0' & hw_timer);
                        end if;
                        draw_counter<=(others=>'0');
                        itsdone<='0';
                    else
                        normrel_x<=(others=>'0');
                        normrel_y<=(others=>'0');
                        draw_counter<=(others=>'0');
                        draw_target<=(others=>'0');
                        itsdone<='0';
                    end if;
                -- Accept a new vector while idle.
                elsif itsdone='1' then
                    if draw='1' then
                        itsdone<='0';
                        normrel_x<=rel_x;
                        normrel_y<=rel_y;
                        if is_svec='1' then
                            draw_target <= x"0100" - (x"00" & hw_timer(7 downto 0));
                        else
                            draw_target <= x"8000" - ('0' & hw_timer);
                        end if;
                        draw_counter<=(others=>'0');
                    end if;
                -- Integrate until the timer expires.
                else
                    if draw_counter >= draw_target then
                        itsdone<='1';
                    else
                        xpos<=xpos+sxt(step_x_full, xpos'length);
                        ypos<=ypos+sxt(step_y_full, ypos'length);
                    end if;
                    draw_counter <= draw_counter + 1;
                end if;
            end if;
        end if;
    end process;
    done <= itsdone;

    -- Return 12 integer bits and three fractional bits. Use the guard bit
    -- to saturate overflow.
    xout <= "011111111111000" when (xpos(33)='0' and xpos(32)='1') else
            "100000000000000" when (xpos(33)='1' and xpos(32)='0') else
            xpos(32 downto 18);

    yout <= "011111111111000" when (ypos(33)='0' and ypos(32)='1') else
            "100000000000000" when (ypos(33)='1' and ypos(32)='0') else
            ypos(32 downto 18);
end Behavioral;
