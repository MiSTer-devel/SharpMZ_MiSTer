---------------------------------------------------------------------------------------------------------
--
-- Name:            i8253.vhd
-- Created:         July 2018
-- Author(s):       Nibbles Lab (C) 2005 - 2012, Refactored and ported for this emulation by Philip Smart
-- Description:     Sharp MZ series i8253 PIT
--                  This module emulates the Intel i8253 Programmable Interval Timer.
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

entity i8253 is
    Port (
        RST                  : in  std_logic;
        CLK                  : in  std_logic;
        A                    : in  std_logic_vector(1 downto 0);
        DI                   : in  std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        CS_n                 : in  std_logic;
        WR_n                 : in  std_logic;
        RD_n                 : in  std_logic;
        CLK0                 : in  std_logic;
        GATE0                : in  std_logic;
        OUT0                 : out std_logic;
        CLK1                 : in  std_logic;
        GATE1                : in  std_logic;
        OUT1                 : out std_logic;
        CLK2                 : in  std_logic;
        GATE2                : in  std_logic;
        OUT2                 : out std_logic
    );
end i8253;

architecture Behavioral of i8253 is

signal WRD0                  : std_logic;
signal WRD1                  : std_logic;
signal WRD2                  : std_logic;
signal WRM0                  : std_logic;
signal WRM1                  : std_logic;
signal WRM2                  : std_logic;
--signal RD0 : std_logic;
signal RD1                   : std_logic;
signal RD2                   : std_logic;
signal DO0                   : std_logic_vector(7 downto 0);
signal DO1                   : std_logic_vector(7 downto 0);
signal DO2                   : std_logic_vector(7 downto 0);

component counter0
    Port (
        DI                   : in  std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        WRD                  : in  std_logic;
        WRM                  : in  std_logic;
        KCLK                 : in  std_logic;
        CLK                  : in  std_logic;
        GATE                 : in  std_logic;
        POUT                 : out std_logic
    );
end component;

component counter1
    Port (
        DI                   : in  std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        WRD                  : in  std_logic;
        WRM                  : in  std_logic;
        KCLK                 : in  std_logic;
        CLK                  : in  std_logic;
        GATE                 : in  std_logic;
        POUT                 : out std_logic
    );
end component;

component counter2
    Port (
        DI                   : in  std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        WRD                  : in  std_logic;
        WRM                  : in  std_logic;
        KCLK                 : in  std_logic;
        RD                   : in  std_logic;
        CLK                  : in  std_logic;
        GATE                 : in  std_logic;
        POUT                 : out std_logic
    );
end component;

begin

    WRD0  <= WR_n when CS_n='0' and A="00" else '1';
    WRD1  <= WR_n when CS_n='0' and A="01" else '1';
    WRD2  <= WR_n when CS_n='0' and A="10" else '1';
    WRM0  <= WR_n when CS_n='0' and A="11" and DI(7 downto 6)="00" else '1';
    WRM1  <= WR_n when CS_n='0' and A="11" and DI(7 downto 6)="01" else '1';
    WRM2  <= WR_n when CS_n='0' and A="11" and DI(7 downto 6)="10" else '1';
--  RD0   <= RD_n when CS_n='0' and A="00" else '1';
    RD1   <= RD_n when CS_n='0' and A="01" else '1';
    RD2   <= RD_n when CS_n='0' and A="10" else '1';

    DO <= DO0 when CS_n='0' and A="00" else
          DO1 when CS_n='0' and A="01" else
          DO2 when CS_n='0' and A="10" else (others=>'1');

    CTR0 : counter0 port map (
        DI   => DI,
        DO   => DO0,
        WRD  => WRD0,
        WRM  => WRM0,
        KCLK => CLK,
        CLK  => CLK0,
        GATE => GATE0,
        POUT => OUT0
    );

    CTR1 : counter1 port map (
        DI   => DI,
        DO   => DO1,
        WRD  => WRD1,
        WRM  => WRM1,
        KCLK => CLK,
        CLK  => CLK1,
        GATE => GATE1,
        POUT => OUT1
    );

    CTR2 : counter2 port map (
        DI   => DI,
        DO   => DO2,
        WRD  => WRD2,
        WRM  => WRM2,
        KCLK => CLK,
        RD   => RD2,
        CLK  => CLK2,
        GATE => GATE2,
        POUT => OUT2
    );

end Behavioral;
