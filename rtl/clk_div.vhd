---------------------------------------------------------------------------------------------------------
--
-- Name:            clk_div.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     A basic frequency divider module.
--                  This module takes an input frequency and divides it based on a provided divider.
-- Credits:         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         July 2018   - Initial module written.
--
---------------------------------------------------------------------------------------------------------
-- This source file is free software: you can redistribute it and-or modify
-- it under the terms of the GNU General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This source file is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http:--www.gnu.org-licenses->.
---------------------------------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity clk_div is
    GENERIC (
        divider : natural
    );
    PORT (
        clk_in  : in  std_logic;
        reset   : in  std_logic;
        clk_out : out std_logic
    );
end clk_div;

architecture Behavioral of clk_div is
    signal temporal: std_logic;
    signal counter : integer range 0 to divider-1 := 0;
begin
    process (reset, clk_in) begin
        if (reset = '1') then
            temporal     <= '0';
            counter      <= 0;

        elsif rising_edge(clk_in) then
            if (counter = divider-1) then
                temporal <= NOT(temporal);
                counter  <= 0;
            else
                counter  <= counter + 1;
            end if;
        end if;
    end process;
    
    clk_out <= temporal;
end Behavioral;
