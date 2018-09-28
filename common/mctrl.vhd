---------------------------------------------------------------------------------------------------------
--
-- Name:            mctrl.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series Programmable Machine Control logic.
--                  This module forms the Programmable control of the emulation along with sync reset
--                  management.
--                  A set of 16 addressable registers is presented on the external IOCTL interface.
--                  Each register controls an aspect of the emulation, such as video mode or cpu speed.
--
--                  Reset to all components is managed by this module, taking cold, warm and internally
--                  generated reset signals and creating a unified system reset output.
--
--                  Please see the docs/SharpMZ_Notes.xlsx spreadsheet for details on these registers
--                  and the values they take.
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

package mctrl_pkg is

    -- Config Bus
    --
    subtype  CONFIG_WIDTH is integer range 58 downto 0;


    -- Mode signals indicating type of machine we are emulating.
    --
    constant MZ80K           : integer := 0;                             -- Machine is an MZ80K
    constant MZ80C           : integer := 1;                             -- Machine is an MZ80C
    constant MZ1200          : integer := 2;                             -- Machine is an MZ1200
    constant MZ80A           : integer := 3;                             -- Machine is an MZ80A
    constant MZ700           : integer := 4;                             -- Machine is an MZ700
    constant MZ800           : integer := 5;                             -- Machine is an MZ800
    constant MZ80B           : integer := 6;                             -- Machine is an MZ80B
    constant MZ2000          : integer := 7;                             -- Machine is an MZ2000
    subtype  CURRENTMACHINE  is integer range 7 downto 0;                -- Range of bits to indicate current machine, only 1 bit is set at a time.
    constant MZ_KC           : integer := 8;                             -- Machine is an MZ80K/MZ80C
    constant MZ_A            : integer := 9;                             -- Machine is an MZ1200/MZ80A
    constant MZ_B            : integer := 10;                            -- Machine is an MZ2000/MZ80B
    constant MZ_80B          : integer := 11;                            -- Machine is an MZ2000/MZ80B
    constant MZ_80C          : integer := 12;                            -- Machine is an MZ80K/MZ80C/MZ1200/MZ80A

    -- Type of display to emulate.
    --
    constant NORMAL          : integer := 13;                            -- Normal 40 x 25 character monochrome display.
    constant NORMAL80        : integer := 14;                            -- Normal 80 x 25 character monochrome display.
    constant COLOUR          : integer := 15;                            -- Colour 40 x 25 character display.
    constant COLOUR80        : integer := 16;                            -- Colour 80 x 25 character display.

    -- Option Roms Enable (some machines by design dont have them, but this emulation allows them to be enabled if needed).
    --
    subtype  USERROM         is integer range 24 downto 17;              -- User ROM E800 - EFFF enable per machine.
    subtype  FDCROM          is integer range 32 downto 25;              -- FDC ROM F000 - FFFF enable per machine.

    -- Various configurable settings.
    --
    constant AUDIOSRC        : integer := 33;                            -- Audio source, 0 = sound generator, 1 = tape audio.
    subtype  TURBO           is integer range 36 downto 34;              -- 2MHz/4MHz/8MHz/16MHz/32MHz switch (various).
    subtype  FASTTAPE        is integer range 39 downto 37;              -- Speed of tape read/write.
    subtype  BUTTONS         is integer range 41 downto 40;              -- Various external buttons, such as CMT play/record.
    constant PCGRAM          : integer := 42;                            -- PCG ROM(0) or RAM(1) based.
    constant VRAMWAIT        : integer := 43;                            -- Insert video wait states on CPU access as per original design.
    constant VRAMDISABLE     : integer := 44;                            -- Disable the Video RAM from display output.
    constant GRAMDISABLE     : integer := 45;                            -- Disable the graphics RAM from display output.

    -- Derivative settings to program the clock generator.
    --
    subtype  CPUSPEED        is integer range 49 downto 46;              -- Active CPU Speed.
    subtype  VIDSPEED        is integer range 52 downto 50;              -- Active Video Speed.
    subtype  PERSPEED        is integer range 54 downto 53;              -- Active Peripheral Speed.
    subtype  RTCSPEED        is integer range 56 downto 55;              -- Active RTC Speed.
    subtype  SNDSPEED        is integer range 58 downto 57;              -- Active Sound Speed.

    -- CMT Bus
    --
    subtype  CMTBUS_WIDTH  is integer range 8 downto 0;

    -- CMT Signals.
    --
    constant PLAY_READY      : integer := 0;                             -- Tape play back buffer, 0 = empty, 1 = full.
    constant PLAYING         : integer := 1;                             -- Tape playback, 0 = stopped, 1 = in progress.
    constant RECORD_READY    : integer := 2;                             -- Tape record buffer full.
    constant RECORDING       : integer := 3;                             -- Tape recording, 0 = stopped, 1 = in progress.
    constant ACTIVE          : integer := 4;                             -- Tape transfer in progress, 0 = no activity, 1 = activity.
    constant SENSE           : integer := 5;                             -- Tape state Sense out.
    constant WRITEBIT        : integer := 6;                             -- Write bit to MZ.
    constant READBIT         : integer := 7;                             -- Receive bit from MZ.
    constant MOTOR           : integer := 8;                             -- Motor on/off.

    -- Debug Bus
    --
    subtype  DEBUG_WIDTH is integer range 15 downto 0;

    -- Debugging signals.
    --
    subtype  LEDS_BANK       is integer range 2 downto 0;
    subtype  LEDS_SUBBANK    is integer range 5 downto 3;
    constant LEDS_ON         : integer := 6;
    constant ENABLED         : integer := 7;
    subtype  SMPFREQ         is integer range 11 downto 8;
    subtype  CPUFREQ         is integer range 15 downto 12;
end mctrl_pkg;


library IEEE;
library pkgs;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use pkgs.mctrl_pkg.all;
use pkgs.clkgen_pkg.all;

entity mctrl is
    Port (
        -- Clock signals used by this module.
        CLKBUS               : in  std_logic_vector(CLKBUS_WIDTH);

        -- Reset's
        COLD_RESET           : in  std_logic;
        WARM_RESET           : in  std_logic;
        SYSTEM_RESET         : out std_logic;

        -- HPS Interface
        IOCTL_CLK            : in  std_logic;                            -- HPS I/O Clock.
        IOCTL_WR             : in  std_logic;                            -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                            -- HPS Read Enable from FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.

        -- Different operations modes.
        CONFIG               : out std_logic_vector(CONFIG_WIDTH);

        -- Cassette magnetic tape signals.
        CMTBUS               : in  std_logic_vector(CMTBUS_WIDTH);

        -- Debug modes.
        DEBUG                : out std_logic_vector(DEBUG_WIDTH) 
    );
end mctrl;

architecture rtl of mctrl is

signal REGISTER_MODEL        : std_logic_vector(7 downto 0)     := "00000011";
signal REGISTER_DISPLAY      : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_CPU          : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_AUDIO        : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_CMT          : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_CMT2         : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_USERROM      : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_FDCROM       : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_8            : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_9            : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_10           : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_11           : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_12           : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_13           : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_DEBUG        : std_logic_vector(7 downto 0)     := "00001000";
signal REGISTER_DEBUG2       : std_logic_vector(7 downto 0)     := "00000000";
signal delay                 : integer range 0 to 31;
signal REGISTER_RESET        : std_logic;

begin
    -- Synchronise the register update with the configuration signals according to the CPU clock.
    --
    process (COLD_RESET, CLKBUS(CKCPU))
    begin
        if COLD_RESET = '1' then
            CONFIG(CONFIG_WIDTH) <= "00000000000000000000000000000000000000000000011001000001000";

        elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU)='0' then

            if REGISTER_MODEL(2 downto 0)  = "000" then
                CONFIG(MZ80K)     <= '1';
            else
                CONFIG(MZ80K)     <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "001" then
                CONFIG(MZ80C)     <= '1';
            else
                CONFIG(MZ80C)     <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "010" then
                CONFIG(MZ1200)    <= '1';
            else
                CONFIG(MZ1200)    <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "011" then
                CONFIG(MZ80A)     <= '1';
            else
                CONFIG(MZ80A)     <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "100" then
                CONFIG(MZ700)     <= '1';
            else
                CONFIG(MZ700)     <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "101" then
                CONFIG(MZ800)     <= '1';
            else
                CONFIG(MZ800)     <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "110" then
                CONFIG(MZ80B)     <= '1';
            else
                CONFIG(MZ80B)     <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "111" then
                CONFIG(MZ2000)    <= '1';
            else
                CONFIG(MZ2000)    <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "000" or  REGISTER_MODEL(2 downto 0)  = "001" then
                CONFIG(MZ_KC)     <= '1';
            else
                CONFIG(MZ_KC)     <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "010" or  REGISTER_MODEL(2 downto 0)  = "011" then
                CONFIG(MZ_A)      <= '1';
            else
                CONFIG(MZ_A)      <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "110" or  REGISTER_MODEL(2 downto 0)  = "111" then
                CONFIG(MZ_B)      <= '1';
            else
                CONFIG(MZ_B)      <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                CONFIG(MZ_80C)    <= '1';
            else
                CONFIG(MZ_80C)    <= '0';
            end if;

            if REGISTER_MODEL(2 downto 0)  = "110" or  REGISTER_MODEL(2 downto 0)  = "111" then
                CONFIG(MZ_80B)    <= '1';
            else
                CONFIG(MZ_80B)    <= '0';
            end if;

            if REGISTER_DISPLAY(2 downto 0)  = "000" then
                CONFIG(NORMAL)    <= '1';
            else
                CONFIG(NORMAL)    <= '0';
            end if;

            if REGISTER_DISPLAY(2 downto 0)  = "001" then
                CONFIG(NORMAL80)  <= '1';
            else
                CONFIG(NORMAL80)  <= '0';
            end if;

            if REGISTER_DISPLAY(2 downto 0)  = "010" then
                CONFIG(COLOUR)    <= '1';
            else
                CONFIG(COLOUR)    <= '0';
            end if;

            if REGISTER_DISPLAY(2 downto 0)  = "011" then
                CONFIG(COLOUR80)  <= '1';
            else
                CONFIG(COLOUR80)  <= '0';
            end if;

            -- Convert CPU/CMT and Debug speed selections to actual CPU speed.
            -- If debugging enabled and Debug freq not 0, select otherwise CMT if CMT is active, otherwise CPU speed as required.
            --
            -- Mapping could be made in software or 1-1 with the register, but setting restrictions and mapping in hw preferred, it
            -- limits frequencies belonging to a given machine and makes it easier to change the frequency by NIOS or other controller if 
            -- MiSTer not used.

            if CMTBUS(ACTIVE) = '1' then
                if REGISTER_MODEL /= "100" and REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                    case REGISTER_CMT(2 downto 0) is
                        when "000" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                        when "001" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                        when "010" => CONFIG(CPUSPEED) <= "0100";   -- 8MHz
                        when "011" => CONFIG(CPUSPEED) <= "0110";   -- 16MHz
                        when "100" => CONFIG(CPUSPEED) <= "1000";   -- 32MHz
                        when "101" => CONFIG(CPUSPEED) <= "1010";   -- 64MHz
                        when "110" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                        when "111" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                    end case;
                elsif REGISTER_MODEL(2 downto 0)  = "100" then
                    case REGISTER_CMT(2 downto 0) is
                        when "000" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                        when "001" => CONFIG(CPUSPEED) <= "0011";   -- 7MHz
                        when "010" => CONFIG(CPUSPEED) <= "0101";   -- 14MHz
                        when "011" => CONFIG(CPUSPEED) <= "0111";   -- 28MHz
                        when "100" => CONFIG(CPUSPEED) <= "1001";   -- 56MHz
                        when "101" => CONFIG(CPUSPEED) <= "1011";   -- 112MHz
                        when "110" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                        when "111" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                    end case;
                elsif REGISTER_MODEL(2 downto 0)  = "110" or  REGISTER_MODEL(2 downto 0)  = "110" then
                    case REGISTER_CMT(2 downto 0) is
                        when "000" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                        when "001" => CONFIG(CPUSPEED) <= "0100";   -- 8MHz
                        when "010" => CONFIG(CPUSPEED) <= "0110";   -- 16MHz
                        when "011" => CONFIG(CPUSPEED) <= "1000";   -- 32MHz
                        when "100" => CONFIG(CPUSPEED) <= "1010";   -- 64MHz
                        when "101" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                        when "110" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                        when "111" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                    end case;
                else
                    CONFIG(CPUSPEED) <= "0000";    -- Default 2MHz
                end if;
            else
                if REGISTER_MODEL /= "100" and REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                    case REGISTER_CPU(2 downto 0) is
                        when "000" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                        when "001" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                        when "010" => CONFIG(CPUSPEED) <= "0100";   -- 8MHz
                        when "011" => CONFIG(CPUSPEED) <= "0110";   -- 16MHz
                        when "100" => CONFIG(CPUSPEED) <= "1000";   -- 32MHz
                        when "101" => CONFIG(CPUSPEED) <= "1010";   -- 64MHz
                        when "110" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                        when "111" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                    end case;
                elsif REGISTER_MODEL(2 downto 0)  = "100" then
                    case REGISTER_CPU(2 downto 0) is
                        when "000" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                        when "001" => CONFIG(CPUSPEED) <= "0011";   -- 7MHz
                        when "010" => CONFIG(CPUSPEED) <= "0101";   -- 14MHz
                        when "011" => CONFIG(CPUSPEED) <= "0111";   -- 28MHz
                        when "100" => CONFIG(CPUSPEED) <= "1001";   -- 56MHz
                        when "101" => CONFIG(CPUSPEED) <= "1011";   -- 112MHz
                        when "110" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                        when "111" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                    end case;
                elsif REGISTER_MODEL(2 downto 0)  = "110" or  REGISTER_MODEL(2 downto 0)  = "110" then
                    case REGISTER_CPU(2 downto 0) is
                        when "000" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                        when "001" => CONFIG(CPUSPEED) <= "0100";   -- 8MHz
                        when "010" => CONFIG(CPUSPEED) <= "0110";   -- 16MHz
                        when "011" => CONFIG(CPUSPEED) <= "1000";   -- 32MHz
                        when "100" => CONFIG(CPUSPEED) <= "1010";   -- 64MHz
                        when "101" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                        when "110" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                        when "111" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                    end case;
                else
                    CONFIG(CPUSPEED) <= "0000";    -- Default 2MHz
                end if;
            end if;

            -- Setup the video speed dependent upon model and graphics option.
            --
            -- MZ700/MZ800 Models.
            if REGISTER_MODEL(2 downto 0)  = "100" or REGISTER_MODEL(2 downto 0)  = "101" then
                -- Currently all modes default to one speed!
                case REGISTER_DISPLAY(2 downto 0) is
                    -- 40x25 mode requires 8.8MHz clock, Mono and Colour.
                    when "000" | "010" | "100" | "101" | "110" | "111" =>
                        CONFIG(VIDSPEED) <= "010";

                    -- 80x25 mode requires 17.7MHz clock, Mono and Colour.
                    when "001" | "011" =>
                        CONFIG(VIDSPEED) <= "011";
                end case;
            -- MZ80K/C/1200/A
            elsif REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                case REGISTER_DISPLAY(2 downto 0) is
                    -- 40x25 mode requires 8MHz clock, Mono and Colour.
                    when "000" | "010" | "100" | "101" | "110" | "111" =>
                        CONFIG(VIDSPEED) <= "000";
                    -- 80x25 mode requires 16MHz clock, Mono and Colour.
                    when "001" | "011" =>
                        CONFIG(VIDSPEED) <= "001";
                end case;
            -- MZ80B or MZ2200
            elsif REGISTER_MODEL(2 downto 0)  = "110" or  REGISTER_MODEL(2 downto 0)  = "111" then
                case REGISTER_DISPLAY(2 downto 0) is
                    -- 40x25 mode requires 16MHz clock
                    when "000" | "001" | "010" | "011" | "100" | "101" | "110" | "111" =>
                        CONFIG(VIDSPEED) <= "001";
                end case;
            else
                CONFIG(VIDSPEED) <= "000";
            end if;

            -- Setup RTC clock frequency dependent upon model.
            if REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                CONFIG(RTCSPEED) <= "00";
            elsif REGISTER_MODEL(2 downto 0)  = "101" or  REGISTER_MODEL(2 downto 0)  = "110" then
                CONFIG(RTCSPEED) <= "01";
            elsif REGISTER_MODEL(2 downto 0)  = "100" then
                CONFIG(RTCSPEED) <= "10";
            else
                CONFIG(RTCSPEED) <= "00";
            end if;

            if REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                CONFIG(SNDSPEED) <= "00";
            elsif REGISTER_MODEL(2 downto 0)  = "101" or  REGISTER_MODEL(2 downto 0)  = "110" then
                CONFIG(SNDSPEED) <= "00";
            elsif REGISTER_MODEL(2 downto 0)  = "100" then
                CONFIG(SNDSPEED) <= "01";
            else
                CONFIG(SNDSPEED) <= "00";
            end if;

            -- Setup the peripheral speed.
            if REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                CONFIG(PERSPEED) <= "00";
            elsif REGISTER_MODEL(2 downto 0)  = "101" or  REGISTER_MODEL(2 downto 0)  = "110" then
                CONFIG(PERSPEED) <= "00";
            elsif REGISTER_MODEL(2 downto 0)  = "100" then
                CONFIG(PERSPEED) <= "00";
            else
                CONFIG(PERSPEED) <= "00";
            end if;

            CONFIG(VRAMDISABLE)<= REGISTER_DISPLAY(4);
            CONFIG(GRAMDISABLE)<= REGISTER_DISPLAY(5);
            CONFIG(VRAMWAIT)   <= REGISTER_DISPLAY(6);
            CONFIG(PCGRAM)     <= REGISTER_DISPLAY(7);
            CONFIG(TURBO)      <= REGISTER_CPU(2 downto 0);
            CONFIG(FASTTAPE)   <= REGISTER_CMT(2 downto 0);
            CONFIG(BUTTONS)    <= REGISTER_CMT(4 downto 3);
            CONFIG(AUDIOSRC)   <= REGISTER_AUDIO(0);
            DEBUG(LEDS_BANK)   <= REGISTER_DEBUG(2 downto 0);
            DEBUG(LEDS_SUBBANK)<= REGISTER_DEBUG(5 downto 3);
            DEBUG(LEDS_ON)     <= REGISTER_DEBUG(6);
            DEBUG(ENABLED)     <= REGISTER_DEBUG(7);
            DEBUG(SMPFREQ)     <= REGISTER_DEBUG2(3 downto 0);
            DEBUG(CPUFREQ)     <= REGISTER_DEBUG2(7 downto 4);
        end if;
    end process;

    -- Machine control is just a set of registers holding latched signals to configure machine components.
    -- A write is made on address 100000000000000000000AAAA to read/write the registers, direction is via the
    -- RD/WR signals.
    -- AAAA specifies which register to read/write.
    --
    process (COLD_RESET, IOCTL_CLK)
    begin
        if COLD_RESET = '1' then
            REGISTER_MODEL   <= "00000011";   
            REGISTER_DISPLAY <= "00000000";
            REGISTER_CPU     <= "00000000";
            REGISTER_AUDIO   <= "00000000";
            REGISTER_CMT     <= "00000000";
            REGISTER_CMT2    <= "00000000";
            REGISTER_USERROM <= "00000000";
            REGISTER_FDCROM  <= "00000000";
            REGISTER_8       <= "00000000";
            REGISTER_9       <= "00000000";
            REGISTER_10      <= "00000000";
            REGISTER_11      <= "00000000";
            REGISTER_12      <= "00000000";
            REGISTER_13      <= "00000000";
            REGISTER_DEBUG   <= "00000000";
            REGISTER_DEBUG2  <= "00000000";
            REGISTER_RESET   <= '1';
        elsif IOCTL_CLK'event and IOCTL_CLK='1' then
            -- For reading of registers, if no specific signal is required, just read back the output latch.
            --
            if IOCTL_ADDR(24) = '1' and IOCTL_RD = '1' then
                case IOCTL_ADDR(3 downto 0) is
                    when "0000" => IOCTL_DIN        <= X"00" & REGISTER_MODEL;
                    when "0001" => IOCTL_DIN        <= X"00" & REGISTER_DISPLAY;
                    when "0010" => IOCTL_DIN        <= X"00" & REGISTER_CPU;
                    when "0011" => IOCTL_DIN        <= X"00" & REGISTER_AUDIO;
                    when "0100" => IOCTL_DIN        <= X"00" & CMTBUS(7 downto 0);
                    when "0101" => IOCTL_DIN        <= X"00" & REGISTER_CMT2(7 downto 1) & CMTBUS(8 downto 8);
                    when "0110" => IOCTL_DIN        <= X"00" & REGISTER_USERROM;
                    when "0111" => IOCTL_DIN        <= X"00" & REGISTER_FDCROM;
                    when "1000" => IOCTL_DIN        <= X"00" & REGISTER_8;
                    when "1001" => IOCTL_DIN        <= X"00" & REGISTER_9;
                    when "1010" => IOCTL_DIN        <= X"00" & REGISTER_10;
                    when "1011" => IOCTL_DIN        <= X"00" & REGISTER_11;
                    when "1100" => IOCTL_DIN        <= X"00" & REGISTER_12;
                    when "1101" => IOCTL_DIN        <= X"00" & REGISTER_13;
                    when "1110" => IOCTL_DIN        <= X"00" & REGISTER_DEBUG;
                    when "1111" => IOCTL_DIN        <= X"00" & REGISTER_DEBUG2;
                end case;
            end if;
            -- For writing of registers, just assign the input bus to the register.
            if IOCTL_ADDR(24) = '1' and IOCTL_WR = '1' then
                case IOCTL_ADDR(3 downto 0) is
                    when "0000" => 
                        -- Assign the model data to the register and preset the default display hardware.
                        REGISTER_MODEL   <= IOCTL_DOUT(7 downto 0);
                        case IOCTL_DOUT(2 downto 0) is
                            when "000" | "001" | "010" | "011" =>
                                 REGISTER_DISPLAY   <= REGISTER_DISPLAY(7 downto 3) & "000";
                            when "100" | "101" =>
                                 REGISTER_DISPLAY   <= REGISTER_DISPLAY(7 downto 3) & "010";
                            when "110" | "111" =>
                                 REGISTER_DISPLAY   <= REGISTER_DISPLAY(7 downto 3) & "000";
                        end case;
                        REGISTER_RESET <= '1';
                    when "0001" =>
                        REGISTER_DISPLAY            <= IOCTL_DOUT(7 downto 0);

                        -- Reset display if the mode changes.
                        if REGISTER_DISPLAY(2 downto 0) /= IOCTL_DOUT(2 downto 0) then
                            REGISTER_RESET          <= '1';
                        end if;
                    when "0010" => REGISTER_CPU     <= IOCTL_DOUT(7 downto 0);
                    when "0011" => REGISTER_AUDIO   <= IOCTL_DOUT(7 downto 0);
                    when "0100" => REGISTER_CMT     <= IOCTL_DOUT(7 downto 0);
                    when "0101" => REGISTER_CMT2    <= IOCTL_DOUT(7 downto 0);
                    when "0110" => REGISTER_USERROM <= IOCTL_DOUT(7 downto 0);
                    when "0111" => REGISTER_FDCROM  <= IOCTL_DOUT(7 downto 0);
                    when "1000" => REGISTER_8       <= IOCTL_DOUT(7 downto 0);
                    when "1001" => REGISTER_9       <= IOCTL_DOUT(7 downto 0);
                    when "1010" => REGISTER_10      <= IOCTL_DOUT(7 downto 0);
                    when "1011" => REGISTER_11      <= IOCTL_DOUT(7 downto 0);
                    when "1100" => REGISTER_12      <= IOCTL_DOUT(7 downto 0);
                    when "1101" => REGISTER_13      <= IOCTL_DOUT(7 downto 0);
                    when "1110" => REGISTER_DEBUG   <= IOCTL_DOUT(7 downto 0);
                    when "1111" => REGISTER_DEBUG2  <= IOCTL_DOUT(7 downto 0);
                end case;
            end if;

            -- Only allow reset signal to be active for 1 clock cycle, just enough to trigger a system reset.
            --
            if REGISTER_RESET = '1' then
                REGISTER_RESET <= '0';
            end if;
        end if;
    end process;

    -- System reset oneshot, triggered on COLD/WARM reset or a status change.
    process (CLKBUS(CKRESET), COLD_RESET, WARM_RESET, REGISTER_RESET)
    begin
        if COLD_RESET = '1' or WARM_RESET = '1' or REGISTER_RESET = '1' then
            if COLD_RESET = '1' then
                delay <= 1;
            elsif WARM_RESET = '1' then
                delay <= 16;
            else
                delay <= 16;
            end if;

        elsif CLKBUS(CKRESET)'event and CLKBUS(CKRESET) = '1' then
            if delay /= 0 then
                delay <= delay + 1;
            elsif delay >= 31 then
                delay <= 0;
            end if;
        end if;
    end process;
    SYSTEM_RESET <= '1' when delay > 0
                    else '0';
end rtl;
