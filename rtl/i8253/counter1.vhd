---------------------------------------------------------------------------------------------------------
--
-- Name:            counter1.vhd
-- Created:         July 2018
-- Author(s):       Nibbles Lab (C) 2005 - 2012, Refactored and ported for this emulation by Philip Smart
-- Description:     Sharp MZ series i8253 PIT - Counter 1
--                  This module emulates Counter 1 of the Intel i8253 Programmable Interval Timer.
--
-- Credits:         
-- Copyright:       (c) 2005-2012 Nibbles Lab, 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         July 2018   - Initial module refactored and updated for this emulation.
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
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity counter1 is
    Port (
        DI                   : in std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        WRM                  : in std_logic;
        WRD                  : in std_logic;
        KCLK                 : in std_logic;
        CLK                  : in std_logic;
        GATE                 : in std_logic;
        POUT                 : out std_logic
    );
end counter1;

architecture Behavioral of counter1 is

-- counter
--
signal CREG                  : std_logic_vector(15 downto 0);
--
-- initialize
--
signal INIV                  : std_logic_vector(15 downto 0);
signal RL                    : std_logic_vector(1 downto 0);
signal PO                    : std_logic;
signal UL                    : std_logic;
signal NEWM                  : std_logic;
--
-- count control
--
signal CEN                   : std_logic;
signal GT                    : std_logic;

begin

    -- Default for unused bus.
    DO  <= "00000000";

    --
    -- Counter access mode
    --
    process( KCLK, WRM ) begin
        if( KCLK'event and KCLK='1' and WRM='0' ) then
            RL<=DI(5 downto 4);
        end if;
    end process;

    --
    -- Counter initialize
    --
    process( KCLK ) begin
        if( KCLK'event and KCLK='1' ) then
            if( WRM='0' ) then
                NEWM<='1';
                UL<='0';
            elsif( WRD='0' ) then
                if( RL="01" ) then
                    INIV(7 downto 0)<=DI;
                    NEWM<='0';
                elsif( RL="10" ) then
                    INIV(15 downto 8)<=DI;
                    NEWM<='0';
                elsif( RL="11" ) then
                    if( UL='0' ) then
                        INIV(7 downto 0)<=DI;
                        UL<='1';
                    else
                        INIV(15 downto 8)<=DI;
                        UL<='0';
                        NEWM<='0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    --
    -- Count enable
    --
    CEN<='1' when NEWM='0' and GATE='1' else '0';

    --
    -- Count (mode 2)
    --
    process( CLK ) begin
        if( CLK'event and CLK='0' ) then
            GT<=GATE;
            if( WRM='0' ) then
                PO<='1';
            elsif( (GT='0' and GATE='1') or CREG=1 ) then
                CREG<=INIV;
                PO<='1';
            elsif( CREG=2 ) then
                PO<='0';
                CREG<=CREG-1;
            elsif( CEN='1' ) then
                CREG<=CREG-1;
            end if;
        end if;
    end process;

    POUT<=PO when GATE='1' else '1';

end Behavioral;
