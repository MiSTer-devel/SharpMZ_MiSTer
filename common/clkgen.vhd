---------------------------------------------------------------------------------------------------------
--
-- Name:            clkgen.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     A programmable Clock Generate module.
--                  This module is the heart of the emulator, providing all required frequencies
--                  from a given input clock (ie. DE10 Nano 50MHz).
--
--                  Based on input control signals from the MCTRL block, it changes the core frequencies
--                  according to requirements and adjusts delays (such as memory) accordingly.
--
--                  The module also has debugging logic to create debug frequencies (in the FPGA, static
--                  is quite possible). The debug frequencies can range from CPU down to 1/10 Hz.
--                  
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

package clkgen_pkg is

    -- Clock bus, various clocks on a single bus construct.
    --
    subtype  CLKBUS_WIDTH is integer range 9 downto 0;

    -- Indexes to the various clocks on the bus.
    --
    constant CKSYS            : integer := 0;                            -- Master Clock (Out)
    constant CKHPS            : integer := 1;                            -- HPS clock.
    constant CKMEM            : integer := 2;                            -- Memory Clock, running 2x the CPU clock.
    constant CKVIDEO          : integer := 3;                            -- Video base frequency.
    constant CKSOUND          : integer := 4;                            -- Sound base frequency.
    constant CKRTC            : integer := 5;                            -- RTC base frequency.
    constant CKLEDS           : integer := 6;                            -- Debug leds time base.
    constant CKCPU            : integer := 7;                            -- Variable CPU clock
    constant CKPERIPH         : integer := 8;                            -- Peripheral clock
    constant CKRESET          : integer := 9;
end clkgen_pkg;

library IEEE;
library pkgs;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;

entity clkgen is
    Port (
        RST                  : in  std_logic;                            -- Reset

        -- Clocks
        CKBASE               : in  std_logic;                            -- Base system main clock.
        CLKBUS               : out std_logic_vector(CLKBUS_WIDTH);       -- Clock signals created by this module.

        -- Different operations modes.
        CONFIG               : in  std_logic_vector(CONFIG_WIDTH);    

        -- Debug modes.
        DEBUG                : in std_logic_vector(DEBUG_WIDTH)
    );
end clkgen;

architecture RTL of clkgen is

--
-- Selectable output Clocks
--
signal PLLLOCKED             : std_logic;           
signal SYSFREQLOCKED         : std_logic;                                -- System clock is locked and running.
signal CK448Mi               : std_logic;                                -- 448MHz
signal CK224Mi               : std_logic;                                -- 224MHz
signal CK112Mi               : std_logic;                                -- 112MHz
signal CK64Mi                : std_logic;                                -- 64MHz
signal CK56Mi                : std_logic;                                -- 56MHz
signal CK32Mi                : std_logic;                                -- 32MHz
signal CK28Mi                : std_logic;                                -- 28MHz
signal CK17M7i               : std_logic;                                -- 17.7MHz
signal CK16Mi                : std_logic;                                -- 16MHz
signal CK14Mi                : std_logic;                                -- 14MHz
signal CK8M8i                : std_logic;                                -- 8.8MHz
signal CK8Mi                 : std_logic;                                -- 8MHz
signal CK7Mi                 : std_logic;                                -- 7MHz
signal CK4Mi                 : std_logic;                                -- 4MHz
signal CK3M5i                : std_logic;                                -- 3.5MHz
signal CK2Mi                 : std_logic;                                -- 2MHz
signal CK1Mi                 : std_logic;                                -- 1MHz
signal CK895Ki               : std_logic;                                -- 895KHz Sound frequency.
signal CK100Ki               : std_logic;                                -- Debug frequency.
signal CK31500i              : std_logic;                                -- Clock base frequency,
signal CK31250i              : std_logic;                                -- Clock base frequency.
signal CK15611i              : std_logic;                                -- Clock base frequency.
signal CK10Ki                : std_logic;                                -- 10KHz debug CPU frequency.
signal CK5Ki                 : std_logic;                                -- 5KHz debug CPU frequency.
signal CK1Ki                 : std_logic;                                -- 1KHz debug CPU frequency.
signal CK500i                : std_logic;                                -- 500Hz debug CPU frequency.
signal CK100i                : std_logic;                                -- 100Hz debug CPU frequency.
signal CK50i                 : std_logic;                                -- 50Hz debug CPU frequency.
signal CK10i                 : std_logic;                                -- 10Hz debug CPU frequency.
signal CK5i                  : std_logic;                                -- 5Hz debug CPU frequency.
signal CK2i                  : std_logic;                                -- 2Hz debug CPU frequency.
signal CK1i                  : std_logic;                                -- 1Hz debug CPU frequency.
signal CK0_5i                : std_logic;                                -- 0.5Hz debug CPU frequency.
signal CK0_2i                : std_logic;                                -- 0.2Hz debug CPU frequency.
signal CK0_1i                : std_logic;                                -- 0.1Hz debug CPU frequency.
--
-- Functional clocks.
--
signal CKLEDSi               : std_logic;                                -- Debug Leds base clock.
signal CKCPUi                : std_logic;
signal CKMEMd                : std_logic_vector(64 downto 0);            -- Delay line for the CPU clock to create the memory clock.
signal CKSOUNDi              : std_logic;
signal CKVIDEOi              : std_logic;
signal CKRTCi                : std_logic;
signal CKPERIPHi             : std_logic;
--

--
-- Components
--
component pll
    Port (
       refclk                : in  std_logic;                            -- Reference clock
       rst                   : in  std_logic;                            -- Reset
       outclk_0              : out std_logic;                            -- 895MHz
       locked                : out std_logic                             -- PLL locked.
    );
end component;

begin
    PLLMAIN : pll
        port map (
            refclk           => CKBASE,                                  -- Reference clock
            rst              => RST,                                     -- Reset
            outclk_0         => CK448Mi,                                 -- 448MHz
            locked           => PLLLOCKED                                -- PLL locked.
        );

    --
    -- Clock Generator - Basic divide circuit for higher end frequencies.
    --
    process (RST, PLLLOCKED, CK448Mi) 
        --
        variable counter224M : unsigned(1 downto 0);                     -- Binary divider to create 224MHz clock.
        variable counter112M : unsigned(2 downto 0);                     -- Binary divider to create 112MHz clock.
        variable counter64M  : unsigned(2 downto 0);                     -- Binary divider to create 64MHz clock.
        variable counter56M  : unsigned(3 downto 0);                     -- Binary divider to create 56MHz clock.
        variable counter32M  : unsigned(3 downto 0);                     -- Binary divider to create 32MHz clock.
        variable counter28M  : unsigned(4 downto 0);                     -- Binary divider to create 28MHz clock.
        variable counter17M7 : unsigned(5 downto 0);                     -- Binary divider to create 17.734475MHz clock.
        variable counter16M  : unsigned(4 downto 0);                     -- Binary divider to create 16MHz clock.
        variable counter14M  : unsigned(5 downto 0);                     -- Binary divider to create 16MHz clock.
        variable counter8M8  : unsigned(5 downto 0);                     -- Binary divider to create 8.8672375MHz clock.
        variable counter8M   : unsigned(5 downto 0);                     -- Binary divider to create 8MHz clock.
        variable counter7M   : unsigned(6 downto 0);                     -- Binary divider to create 7MHz clock.
        variable counter4M   : unsigned(6 downto 0);                     -- Binary divider to create 4MHz clock.
        variable counter3M5  : unsigned(6 downto 0);                     -- Binary divider to create 3.5MHz clock.
        variable counter2M   : unsigned(7 downto 0);                     -- Binary divider to create 2MHz clock.
        variable counter1M   : unsigned(8 downto 0);                     -- Binary divider to create 1MHz clock.
        variable counter895K : unsigned(8 downto 0);                     -- Binary divider to create 895K clock.
        variable waittosync  : integer range 0 to 5;                     -- Counter which waits until the main clock stabilizes.

    begin
        if RST = '1' or PLLLOCKED = '0' then
            counter224M      := (others => '0');
            counter112M      := (others => '0');
            counter64M       := (others => '0');
            counter56M       := (others => '0');
            counter32M       := (others => '0');
            counter28M       := (others => '0');
            counter17M7      := (others => '0');
            counter16M       := (others => '0');
            counter14M       := (others => '0');
            counter8M8       := (others => '0');
            counter8M        := (others => '0');
            counter7M        := (others => '0');
            counter4M        := (others => '0');
            counter3M5       := (others => '0');
            counter2M        := (others => '0');
            counter1M        := (others => '0');
            counter895K      := (others => '0');
            CK224Mi          <= '0';
            CK112Mi          <= '0';
            CK64Mi           <= '0';
            CK56Mi           <= '0';
            CK32Mi           <= '0';
            CK28Mi           <= '0';
            CK17M7i          <= '0';
            CK16Mi           <= '0';
            CK14Mi           <= '0';
            CK8M8i           <= '0';
            CK8Mi            <= '0';
            CK7Mi            <= '0';
            CK4Mi            <= '0';
            CK3M5i           <= '0';
            CK2Mi            <= '0';
            CK1Mi            <= '0';
            CK895Ki          <= '0';
            SYSFREQLOCKED    <= '0';
            waittosync       := 5;

        elsif rising_edge(CK448Mi) then

            -- If the main system frequency has stabilized and locked, commence oscillation of sub-frequencies.
            if SYSFREQLOCKED = '1' then

                -- 224MHz
                if counter224M = 2 then
                    counter224M  := (others => '0');
                    CK224Mi      <= not CK224Mi;
                else
                    counter224M  := counter224M   + 1;
                end if;
    
                -- 112MHz
                if counter112M = 2 then
                    counter112M  := (others => '0');
                    CK112Mi      <= not CK112Mi;
                else
                    counter112M  := counter112M   + 1;
                end if;
    
                -- 64MHz
                if counter64M = 3 or counter64M = 7 then
                    CK64Mi       <= not CK64Mi;
    
                    if counter64M = 7 then
                        counter64M   := (others => '0');
                    else
                        counter64M   := counter64M   + 1;
                    end if;
                else
                    counter64M   := counter64M   + 1;
                end if;
    
                -- 56MHz
                if counter56M = 4 then
                    CK56Mi       <= not CK56Mi;
                    counter56M   := (others => '0');
                else
                    counter56M   := counter56M   + 1;
                end if;
    
                -- 32MHz
                if counter32M = 7 then
                    counter32M   := (others => '0');
                    CK32Mi       <= not CK32Mi;
                else
                    counter32M   := counter32M   + 1;
                end if;
    
                -- 28MHz
                if counter28M = 8 then
                    counter28M   := (others => '0');
                    CK28Mi       <= not CK28Mi;
                else
                    counter28M   := counter28M   + 1;
                end if;
    
                -- 17.734475MHz
                if counter17M7 = 13 or counter17M7 = 25 then
                    CK17M7i      <= not CK17M7i;
    
                    if counter17M7 = 25 then
                        counter17M7 := (others => '0');
                    else
                        counter17M7 := counter17M7 + 1;
                    end if;
                else
                    counter17M7   := counter17M7 + 1;
                end if;
    
                -- 16MHz
                if counter16M = 14 then
                    counter16M   := (others => '0');
                    CK16Mi       <= not CK16Mi;
                else
                    counter16M   := counter16M   + 1;
                end if;
    
                -- 14MHz
                if counter14M = 16 then
                    counter14M   := (others => '0');
                    CK14Mi       <= not CK14Mi;
                else
                    counter14M   := counter14M   + 1;
                end if;
    
                -- 8.8672375MHz
                if counter8M8 = 25 then
                    counter8M8   := (others => '0');
                    CK8M8i       <= not CK8M8i;
                else
                    counter8M8   := counter8M8    + 1;
                end if;
    
                -- 8MHz
                if counter8M = 28 then
                    counter8M    := (others => '0');
                    CK8Mi        <= not CK8Mi;
                else
                    counter8M    := counter8M    + 1;
                end if;
    
                -- 7MHz
                if counter7M = 32 then
                    counter7M    := (others => '0');
                    CK7Mi        <= not CK7Mi;
                else
                    counter7M    := counter7M    + 1;
                end if;
    
                -- 4MHz
                if counter4M = 56 then
                    counter4M    := (others => '0');
                    CK4Mi        <= not CK4Mi;
                else
                    counter4M    := counter4M    + 1;
                end if;
    
                -- 3.546875MHz
                if counter3M5 = 63 then
                    counter3M5   := (others => '0');
                    CK3M5i       <= not CK3M5i;
                else
                    counter3M5   := counter3M5   + 1;
                end if;
    
                -- 2MHz
                if counter2M = 112 then
                    counter2M    := (others => '0');
                    CK2Mi        <= not CK2Mi;
                else
                    counter2M    := counter2M    + 1;
                end if;
    
                -- 1MHz
                if counter1M = 224 then
                    counter1M    := (others => '0');
                    CK1Mi        <= not CK1Mi;
                else
                    counter1M    := counter1M    + 1;
                end if;
    
                -- 895K
                if counter895K = 250 then
                    counter895K  := (others => '0');
                    CK895Ki      <= not CK895Ki;
                else
                    counter895K  := counter895K  + 1;
                end if;
            else
                waittosync := waittosync -1;
                if waittosync = 0 then
                    SYSFREQLOCKED <= '1';
                end if;
            end if;
        end if;
    end process;

    --
    -- Clock Generator - Basic divide circuit for middle end frequencies.
    --
    process (RST, PLLLOCKED, CK1Mi) 
        --
        variable counter100K : unsigned(5 downto 0);                     -- Binary divider to create 100K clock.
        variable counter31250: unsigned(6 downto 0);                     -- Binary divider to create 31.250KHz clock.
        variable counter15611: unsigned(7 downto 0);                     -- Binary divider to create 15.611KHz clock.

    begin
        if RST = '1' or PLLLOCKED = '0' then
            counter100K      := (others => '0'); 
            counter31250     := (others => '0');
            counter15611     := (others => '0');
            CK100Ki          <= '0';
            CK31250i         <= '0';
            CK15611i         <= '0';

        elsif rising_edge(CK1Mi) then

            -- 100K
            if counter100K = 5 then
                counter100K  := (others => '0');
                CK100Ki      <= not CK100Ki;
            else
                counter100K  := counter100K  + 1;
            end if;

            -- 31,250KHz
            if counter31250 = 16 then
                counter31250 := (others => '0');
                CK31250i     <= not CK31250i;
            else
                counter31250 := counter31250 + 1;
            end if;

            -- 15.611KHz
            if counter15611 = 32 then
                counter15611 := (others => '0');
                CK15611i     <= not CK15611i;
            else
                counter15611 := counter15611 + 1;
            end if;
        end if;
    end process;

    --
    -- Clock Generator - Basic divide circuit for middle end frequencies.
    --
    process (RST, PLLLOCKED, CK17M7i) 
        --
        variable counter31500: unsigned(9 downto 0);                     -- Binary divider to create 31.500KHz clock.
    begin
        if RST = '1' or PLLLOCKED = '0' then
            counter31500     := (others => '0');
            CK31500i         <= '0';

        elsif rising_edge(CK17M7i) then

            -- 31.5KHz
            if counter31500 = 281 or counter31500=563 then
                CK31500i     <= not CK31500i;
                counter31500 := (others => '0');
                if counter31500 = 563 then
                    counter31500 := (others => '0');
                else
                    counter31500 := counter31500 + 1;
                end if;
            else
                counter31500 := counter31500 + 1;
            end if;

        end if;
    end process;

    --
    -- Clock Generator - Basic divide circuit for middle end frequencies.
    --
    process (RST, PLLLOCKED, CK100Ki) 
        --
        variable counter10K  : unsigned(3 downto 0);                    -- Binary divider to create 10KHz clock.
        variable counter5K   : unsigned(4 downto 0);                    -- Binary divider to create 5KHz clock.
        variable counter1K   : unsigned(6 downto 0);                    -- Binary divider to create 1KHz clock.
        variable counter500  : unsigned(7 downto 0);                    -- Binary divider to create 500Hz clock.
    begin
        if RST = '1' or PLLLOCKED = '0' then
            counter10K       := (others => '0');
            counter5K        := (others => '0');
            counter1K        := (others => '0');
            counter500       := (others => '0');
            CK10Ki           <= '0';
            CK5Ki            <= '0';
            CK1Ki            <= '0';
            CK500i           <= '0';

        elsif rising_edge(CK100Ki) then

            -- 10KHz
            if counter10K = 5 then
                counter10K := (others => '0');
                CK10Ki     <= not CK10Ki;
            else
                counter10K := counter10K + 1;
            end if;

            -- 5KHz
            if counter5K = 10 then
                counter5K := (others => '0');
                CK5Ki     <= not CK5Ki;
            else
                counter5K := counter5K + 1;
            end if;

            -- 1KHz
            if counter1K = 50 then
                counter1K := (others => '0');
                CK1Ki     <= not CK1Ki;
            else
                counter1K := counter1K + 1;
            end if;

            -- 500Hz
            if counter500 = 100 then
                counter500 := (others => '0');
                CK500i     <= not CK500i;
            else
                counter500 := counter500 + 1;
            end if;

        end if;
    end process;

    --
    -- Clock Generator - Basic divide circuit for middle end frequencies.
    --
    process (RST, PLLLOCKED, CK1Ki) 
        --
        variable counter100  : unsigned(3 downto 0);                    -- Binary divider to create 100Hz clock.
        variable counter50   : unsigned(4 downto 0);                    -- Binary divider to create 50Hz clock.
        variable counter10   : unsigned(6 downto 0);                    -- Binary divider to create 10Hz clock.
        variable counter5    : unsigned(7 downto 0);                    -- Binary divider to create 5Hz clock.
    begin
        if RST = '1' or PLLLOCKED = '0' then
            counter100       := (others => '0');
            counter50        := (others => '0');
            counter10        := (others => '0');
            counter5         := (others => '0');
            CK100i           <= '0';
            CK50i            <= '0';
            CK10i            <= '0';
            CK5i             <= '0';

        elsif rising_edge(CK1Ki) then

            -- 100Hz
            if counter100 = 5 then
                counter100 := (others => '0');
                CK100i     <= not CK100i;
            else
                counter100 := counter100 + 1;
            end if;

            -- 50Hz
            if counter50 = 10 then
                counter50 := (others => '0');
                CK50i     <= not CK50i;
            else
                counter50 := counter50 + 1;
            end if;

            -- 10Hz
            if counter10 = 50 then
                counter10 := (others => '0');
                CK10i     <= not CK10i;
            else
                counter10 := counter10 + 1;
            end if;

            -- 5Hz
            if counter5 = 100 then
                counter5 := (others => '0');
                CK5i     <= not CK5i;
            else
                counter5 := counter5 + 1;
            end if;
        end if;
    end process;

    --
    -- Clock Generator - Basic divide circuit for low end frequencies.
    --
    process (RST, PLLLOCKED, CK100i) 
        --
        variable counter2    : unsigned(5 downto 0);                     -- Binary divider to create 2Hz clock.
        variable counter1    : unsigned(6 downto 0);                     -- Binary divider to create 1Hz clock.
        variable counter0_5  : unsigned(7 downto 0);                     -- Binary divider to create 0.5Hz clock.
        variable counter0_2  : unsigned(8 downto 0);                     -- Binary divider to create 0.2Hz clock.
        variable counter0_1  : unsigned(9 downto 0);                     -- Binary divider to create 0.1Hz clock.
    begin
        if RST = '1' or PLLLOCKED = '0' then
            counter2         := (others => '0');
            counter1         := (others => '0');
            counter0_5       := (others => '0');
            counter0_2       := (others => '0');
            counter0_1       := (others => '0');
            CK2i             <= '0';
            CK1i             <= '0';
            CK0_5i           <= '0';
            CK0_2i           <= '0';
            CK0_1i           <= '0';

        elsif rising_edge(CK100i) then

            -- 2Hz
            if counter2 = 25 then
                counter2 := (others => '0');
                CK2i     <= not CK2i;
            else
                counter2 := counter2 + 1;
            end if;

            -- 1Hz
            if counter1 = 50 then
                counter1 := (others => '0');
                CK1i     <= not CK1i;
            else
                counter1 := counter1 + 1;
            end if;

            -- 0.5Hz
            if counter0_5 = 100 then
                counter0_5 := (others => '0');
                CK0_5i     <= not CK0_5i;
            else
                counter0_5 := counter0_5 + 1;
            end if;

            -- 0.2Hz
            if counter0_2 = 250 then
                counter0_2 := (others => '0');
                CK0_2i     <= not CK0_5i;
            else
                counter0_2 := counter0_2 + 1;
            end if;

            -- 0.1Hz
            if counter0_1 = 500 then
                counter0_1 := (others => '0');
                CK0_1i     <= not CK0_5i;
            else
                counter0_1 := counter0_1 + 1;
            end if;
        end if;
    end process;

    --
    -- Clock Generator - Basic divide circuit based on a 18 bit counter.
    --
    process (RST, PLLLOCKED, CK448Mi, CK224Mi, CK112Mi, CK64Mi, CK56Mi, CK32Mi, CK28Mi, CK17M7i, CK16Mi, CK14Mi, CK8M8i, CK8Mi, CK7Mi, CK4Mi, CK3M5i, CK2Mi,
             CK1Mi, CK895Ki, CK100Ki, CK31500i, CK31250i, CK15611i, CK10Ki, CK5Ki, CK1Ki, CK500i, CK100i, CK50i, CK10i, CK5i, CK2i, CK1i, CK0_5i, CK0_2i, CK0_1i,
             SYSFREQLOCKED, CKCPUi, CKMEMd, CKSOUNDi, CKVIDEOi, CKRTCi, CKPERIPHi, CKLEDSi)
        --
        variable mdelay      : integer range 0 to 64;                    -- Memory clock delay line index.

    begin
        if RST = '1' or PLLLOCKED = '0' then
            mdelay           := 32;
            CKCPUi           <= '0';
            CKMEMd           <= (others => '0');
            CKSOUNDi         <= '0';
            CKVIDEOi         <= '0';
            CKRTCi           <= '0';
            CKPERIPHi        <= '0';
            CKLEDSi          <= '0';

        elsif rising_edge(CK448Mi) then

            -- Only start meaningful assignment once the main clock frequency is locked.
            --
            if SYSFREQLOCKED = '1' then
                -- Delay line, different CPU frequencies require different memory delays.
                CKMEMd(64 downto 1) <= CKMEMd(63 downto 0);
                CKMEMd(0)           <= CKCPUi;
    
                -- If debugging has been enabled and the debug cpu frequency set to a valid value, change cpu clock accordingly.
                if DEBUG(ENABLED) = '0' or DEBUG(CPUFREQ) = "0000" then
    
                    -- The CPU speed is configured by the CMT register and CMT state or the CPU register. Select the right
                    -- frequency and form the clock by flipping on the right flip flag.
                    --
                    case CONFIG(CPUSPEED) is
                        when "0001" => -- 3.5MHz
                            mdelay := 20;
                            CKCPUi <= CK3M5i;
                        when "0010" => -- 4MHz
                            mdelay := 16;
                            CKCPUi <= CK4Mi;
                        when "0011" => -- 7MHz
                            mdelay := 10;
                            CKCPUi <= CK7Mi;
                        when "0100" => -- 8MHz
                            mdelay := 8;
                            CKCPUi <= CK8Mi;
                        when "0101" => -- 14MHz
                            mdelay := 4;
                            CKCPUi <= CK14Mi;
                        when "0110" => -- 16MHz
                            mdelay := 4;
                            CKCPUi <= CK16Mi;
                        when "0111" => -- 28MHz
                            mdelay := 2;
                            CKCPUi <= CK28Mi;
                        when "1000" => -- 32MHz
                            mdelay := 4;          -- was 2
                            CKCPUi <= CK32Mi;
                        when "1001" => -- 56MHz
                            mdelay := 4;     -- was 3;
                            CKCPUi <= CK56Mi;
                        when "1010" => -- 64MHz
                            mdelay := 2;       -- was 2;
                            CKCPUi <= CK64Mi;
                        when "1011" => -- 112MHz
                            mdelay := 1; -- was2;
                            CKCPUi <= CK112Mi;
        
                        -- Unallocated frequencies, use default.
                        when "0000"| "1100" | "1101" | "1110" | "1111" => -- 2MHz
                            mdelay := 32;
                            CKCPUi <= CK2Mi;
                    end case;
                else
                    case DEBUG(CPUFREQ) is
                        when "0000" => -- Use normal cpu frequency, so this choice shouldnt be selected.
                            mdelay := 32;
                            CKCPUi <= CK2Mi;
                        when "0001" => -- 1MHz
                            mdelay := 64;
                            CKCPUi <= CK1Mi;
                        when "0010" => -- 100KHz
                            mdelay := 12;
                            CKCPUi <= CK100Ki;
                        when "0011" => -- 10KHz
                            mdelay := 24;
                            CKCPUi <= CK10Ki;
                        when "0100" => -- 5KHz
                            mdelay := 32;
                            CKCPUi <= CK5Ki;
                        when "0101" => -- 1KHz
                            mdelay := 36;
                            CKCPUi <= CK1Ki;
                        when "0110" => -- 500Hz
                            mdelay := 40;
                            CKCPUi <= CK500i;
                        when "0111" => -- 100Hz
                            mdelay := 44;
                            CKCPUi <= CK100i;
                        when "1000" => -- 50Hz
                            mdelay := 48;
                            CKCPUi <= CK50i;
                        when "1001" => -- 10Hz
                            mdelay := 52;
                            CKCPUi <= CK10i;
                        when "1010" => -- 5Hz
                            mdelay := 56;
                            CKCPUi <= CK5i;
                        when "1011" => -- 2Hz
                            mdelay := 58;
                            CKCPUi <= CK2i;
                        when "1100" => -- 1Hz
                            mdelay := 60;
                            CKCPUi <= CK1i;
                        when "1101" => -- 0.5Hz
                            mdelay := 60;
                            CKCPUi <= CK0_5i;
                        when "1110" => -- 0.2Hz
                            mdelay := 60;
                            CKCPUi <= CK0_2i;
                        when "1111" => -- 0.1Hz
                            mdelay := 60;
                            CKCPUi <= CK0_1i;
                    end case;
                end if;
    
                -- Form the video frequency according to the user selection.
                --
                case CONFIG(VIDSPEED) is
                    when "000" => -- 8MHz
                        CKVIDEOi <= CK8Mi;
    
                    when "001" => -- 16MHz
                        CKVIDEOi <= CK16Mi;
    
                    when "010" => -- 8.8672375MHz
                        CKVIDEOi <= CK8M8i;
    
                    when "011" => -- 17.734475MHz
                        CKVIDEOi <= CK17M7i;
    
                    when "100" | "101" | "110" | "111" => -- Unassigned default to 8MHz
                        CKVIDEOi <= CK8Mi;
                end case;
    
                -- Form the RTC frequency according to the user selection.
                --
                case CONFIG(RTCSPEED) is
                    when "01" => -- 31,250KHz
                        CKRTCi <= CK31250i;
                    when "10" => -- 15.611KHz
                        CKRTCi <= CK15611i;
                    when "00" | "11" => -- 31.5KHz
                        CKRTCi <= CK31500i;
                end case;
    
                -- Form the peripheral frequency according to the user selection.
                --
                case CONFIG(PERSPEED) is
                    when "00" | "01" | "10" | "11" =>
                        CKPERIPHi <= CK2Mi;
                end case;
    
                -- Form the sound frequency according to the user selection.
                --
                case CONFIG(SNDSPEED) is
                    when "01" => -- 895K
                        CKSOUNDi <= CK895Ki;
    
                    when "00" | "10" | "11" =>
                        CKSOUNDi <= CK2Mi;
                end case;
    
                -- Sampling frequency of signals, typically used to drive LED outputs but could easily be read by an oscilloscope.
                --
                case DEBUG(SMPFREQ) is
                    when "0000" => -- Use normal cpu frequency.
                        CKLEDSi <= CKCPUi;
                    when "0001" => -- 1MHz
                        CKLEDSi <= CK1Mi;
                    when "0010" => -- 100KHz
                        CKLEDSi <= CK100Ki;
                    when "0011" => -- 10KHz
                        CKLEDSi <= CK10Ki;
                    when "0100" => -- 5KHz
                        CKLEDSi <= CK5Ki;
                    when "0101" => -- 1KHz
                        CKLEDSi <= CK1Ki;
                    when "0110" => -- 500Hz
                        CKLEDSi <= CK500i;
                    when "0111" => -- 100Hz
                        CKLEDSi <= CK100i;
                    when "1000" => -- 50Hz
                        CKLEDSi <= CK50i;
                    when "1001" => -- 10Hz
                        CKLEDSi <= CK10i;
                    when "1010" => -- 5Hz
                        CKLEDSi <= CK5i;
                    when "1011" => -- 2Hz
                        CKLEDSi <= CK2i;
                    when "1100" => -- 1Hz
                        CKLEDSi <= CK1i;
                    when "1101" => -- 0.5Hz
                        CKLEDSi <= CK0_5i;
                    when "1110" => -- 0.2Hz
                        CKLEDSi <= CK0_2i;
                    when "1111" => -- 0.1Hz
                        CKLEDSi <= CK0_1i;
                end case;
            end if;
        end if;

        -- Until the clock generator is programmed and locked to the initial
        -- frequency as determined by mctrl, default to a fixed speed set.
        --
        if SYSFREQLOCKED = '0' then
            CLKBUS(CKCPU)     <= CK2Mi;
            CLKBUS(CKMEM)     <= CKMEMd(32);
            CLKBUS(pkgs.clkgen_pkg.CKSYS) <= CK224Mi;
            CLKBUS(CKHPS)     <= CK32Mi;
            CLKBUS(CKSOUND)   <= CK2Mi;
            CLKBUS(CKRTC)     <= CK31500i;
            CLKBUS(CKVIDEO)   <= CK8Mi;
            CLKBUS(CKPERIPH)  <= CK2Mi;
            CLKBUS(CKLEDS)    <= CK100Ki;
            CLKBUS(CKRESET)   <= CK224Mi;
        else
            CLKBUS(CKCPU)     <= CKCPUi;                             -- CPU clock.
            CLKBUS(CKMEM)     <= CKMEMd(mdelay);                 -- Synchronous Memory clock.
            CLKBUS(pkgs.clkgen_pkg.CKSYS) <= CK224Mi;                -- System clock.
            CLKBUS(CKHPS)     <= CK32Mi;                             -- HPS Sysyem clock.
            CLKBUS(CKSOUND)   <= CKSOUNDi;                           -- Clock for the sound generator, 
            CLKBUS(CKRTC)     <= CKRTCi;                             -- Clock for the RTC generator, 
            CLKBUS(CKVIDEO)   <= CKVIDEOi;                           -- Video base clock.
            CLKBUS(CKPERIPH)  <= CKPERIPHi;                          -- Peripheral base clock.
            CLKBUS(CKLEDS)    <= CKLEDSi;                            -- Output sampling base frequency.
            CLKBUS(CKRESET)   <= CK224Mi;
        --
        end if;
    end process;

end RTL;
