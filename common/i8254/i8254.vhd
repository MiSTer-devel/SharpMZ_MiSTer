---------------------------------------------------------------------------------------------------------
--
-- Name:            i8254.vhd
-- Created:         November 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series i8254 Timer
--                  This module emulates the Intel i8254 Programmable Interval Timer.
--
-- Credits:         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         November 2018 - Initial write.
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

entity i8254 is
    Port (
        RST                  : in  std_logic;
        CLK                  : in  std_logic;
        ENA                  : in  std_logic;
        A                    : in  std_logic_vector(1 downto 0);
        DI                   : in  std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        CS_n                 : in  std_logic;
        WR_n                 : in  std_logic;
        RD_n                 : in  std_logic;
        --
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
end i8254;

architecture Behavioral of i8254 is

signal WREN                  : std_logic;
signal RDEN                  : std_logic;
signal WRCTRLEN              : std_logic;
signal WR0                   : std_logic;
signal WR1                   : std_logic;
signal WR2                   : std_logic;
signal RD0                   : std_logic;
signal RD1                   : std_logic;
signal RD2                   : std_logic;
signal DO0                   : std_logic_vector(7 downto 0);
signal DO1                   : std_logic_vector(7 downto 0);
signal DO2                   : std_logic_vector(7 downto 0);
signal LDO0                  : std_logic_vector(7 downto 0);
signal LDO1                  : std_logic_vector(7 downto 0);
signal LDO2                  : std_logic_vector(7 downto 0);
signal READDATA_NEXT         : std_logic_vector(7 downto 0);
signal CTRLM0                : std_logic;
signal CTRLM1                : std_logic;
signal CTRLM2                : std_logic;
signal LATCNT0               : std_logic;
signal LATCNT1               : std_logic;
signal LATCNT2               : std_logic;
signal LATSTS0               : std_logic;
signal LATSTS1               : std_logic;
signal LATSTS2               : std_logic;

component i8254_counter
    Port (
        CLK                  : in  std_logic;
        RESET                : in  std_logic;
        --
        DATA_IN              : in  std_logic_vector(7 downto 0);
        DATA_OUT             : out std_logic_vector(7 downto 0);
        WRITE                : in  std_logic;
        READ                 : in  std_logic;
        CTRL_MODE_EN         : in  std_logic;
        LATCH_COUNT_EN       : in  std_logic;
        LATCH_STATUS_EN      : in  std_logic;
        --
        CTR_CLK              : in  std_logic;
        CTR_GATE             : in  std_logic;
        CTR_OUT              : out std_logic
    );
end component;

begin

    -- Create signals to select a given register for read or write.
    --
    WREN     <= '1' when ENA = '1' and CS_n = '0' and WR_n = '0'
                else '0';
    RDEN     <= '1' when ENA = '1' and CS_n = '0' and RD_n = '0'
                else '0';
    WRCTRLEN <= '1' when WREN = '1' and A    = "11"
                else '0';
    WR0      <= '1' when WREN = '1' and A = "00" 
                else '0';
    WR1      <= '1' when WREN = '1' and A = "01"
                else '0';
    WR2      <= '1' when WREN = '1' and A = "10"
                else '0';
    RD0      <= '1' when RDEN = '1' and A = "00"
                else '0';
    RD1      <= '1' when RDEN = '1' and A = "01"
                else '0';
    RD2      <= '1' when RDEN = '1' and A = "10"
                else '0';

    -- Create signals to enable setting of a command, a count value or latching status per counter.
    --
    CTRLM0   <= '1' when WRCTRLEN = '1' and   DI(7 downto 6) = "00" and DI(5 downto 4) /= "00"
                else '0';
    CTRLM1   <= '1' when WRCTRLEN = '1' and   DI(7 downto 6) = "01" and DI(5 downto 4) /= "00"
                else '0';
    CTRLM2   <= '1' when WRCTRLEN = '1' and   DI(7 downto 6) = "10" and DI(5 downto 4) /= "00"
                else '0';
    LATCNT0  <= '1' when WRCTRLEN = '1' and ((DI(7 downto 6) = "00" and DI(5 downto 4) = "00") or (DI(7 downto 5) = "110" and DI(1) = '1'))
                else '0';
    LATCNT1  <= '1' when WRCTRLEN = '1' and ((DI(7 downto 6) = "01" and DI(5 downto 4) = "00") or (DI(7 downto 5) = "110" and DI(2) = '1'))
                else '0';
    LATCNT2  <= '1' when WRCTRLEN = '1' and ((DI(7 downto 6) = "10" and DI(5 downto 4) = "00") or (DI(7 downto 5) = "110" and DI(3) = '1'))
                else '0';
    LATSTS0  <= '1' when WRCTRLEN = '1' and   DI(7 downto 6) = "11" and DI(4) = '0' and DI(1) = '1'
                else '0';
    LATSTS1  <= '1' when WRCTRLEN = '1' and   DI(7 downto 6) = "11" and DI(4) = '0' and DI(2) = '1'
                else '0';
    LATSTS2  <= '1' when WRCTRLEN = '1' and   DI(7 downto 6) = "11" and DI(4) = '0' and DI(3) = '1'
                else '0';
 
    -- Assign the counter whose address is active. Not permissible to read back control register.
    --
    DO       <= DO0 when A = "00"
                else
                DO1 when A = "01"
                else
                DO2 when A = "10"
                else
                (others => '0');


    -- Instantiate the 3 counters within the 8254.
    --
    CTR0 : i8254_counter port map (
        CLK                  => CLK,
        RESET                => RST,
        --
        DATA_IN              => DI,
        DATA_OUT             => DO0,
        WRITE                => WR0,
        READ                 => RD0,
        CTRL_MODE_EN         => CTRLM0,
        LATCH_COUNT_EN       => LATCNT0, 
        LATCH_STATUS_EN      => LATSTS0, 
        --
        CTR_CLK              => CLK0,
        CTR_GATE             => GATE0,
        CTR_OUT              => OUT0
    );

    CTR1 : i8254_counter port map (
        CLK                  => CLK,
        RESET                => RST,
        --
        DATA_IN              => DI,
        DATA_OUT             => DO1,
        WRITE                => WR1,
        READ                 => RD1,
        CTRL_MODE_EN         => CTRLM1, 
        LATCH_COUNT_EN       => LATCNT1,
        LATCH_STATUS_EN      => LATSTS1,
        --
        CTR_CLK              => CLK1,
        CTR_GATE             => GATE1,
        CTR_OUT              => OUT1
    );

    CTR2 : i8254_counter port map (
        CLK                  => CLK,
        RESET                => RST,
        --
        DATA_IN              => DI,
        DATA_OUT             => DO2,
        WRITE                => WR2,
        READ                 => RD2,
        CTRL_MODE_EN         => CTRLM2,
        LATCH_COUNT_EN       => LATCNT2,
        LATCH_STATUS_EN      => LATSTS2,
        --
        CTR_CLK              => CLK2,
        CTR_GATE             => GATE2,
        CTR_OUT              => OUT2
    );


end Behavioral;
