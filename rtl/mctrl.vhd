---------------------------------------------------------------------------------------------------------
--
-- Name:            mctrl.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series Programmable Machine Control logic.
--                  This module forms the Programmable control of the emulation along with sync reset
--                  management.
--                  Configuration inputs (from the OSD) control each aspect of the emulation, such
--                  as video mode or cpu speed, and are decoded here into the CONFIG bus.
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



library IEEE;
library pkgs;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.numeric_std.all;
use pkgs.config_pkg.all;
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

        -- Machine configuration, driven from the OSD status bits (SharpMZ.sv). Same layout as the
        -- registers the legacy HPS driver wrote at 0x1000000+.
        CFG_MODEL            : in  std_logic_vector(7 downto 0);         -- 2:0 machine model.
        CFG_DISPLAY          : in  std_logic_vector(7 downto 0);         -- 2:0 display type, 4 VRAM off, 5 GRAM off, 6 VRAM wait, 7 PCG RAM.
        CFG_DISPLAY2         : in  std_logic_vector(7 downto 0);         -- 1:0 video timing, 7:3 GRAM I/O address.
        CFG_DISPLAY3         : in  std_logic_vector(7 downto 0);         -- 0 menu overlay, 1 status overlay, 2 MZ-800 mode switch.
        CFG_CPU              : in  std_logic_vector(7 downto 0);         -- 2:0 turbo, 7 boot reset.
        CFG_AUDIO            : in  std_logic_vector(7 downto 0);         -- 0 audio source (sound / tape).
        CFG_CMT              : in  std_logic_vector(7 downto 0);         -- 2:0 fast tape, 4:3 buttons, 5/6 Sharp ASCII conversion in/out.
        CFG_USERROM          : in  std_logic_vector(7 downto 0);         -- User ROM enable per machine.
        CFG_FDCROM           : in  std_logic_vector(7 downto 0);         -- FDC ROM enable per machine.

        -- Different operations modes.
        CONFIG               : out std_logic_vector(CONFIG_WIDTH);

        -- Cassette magnetic tape signals.
        CMT_BUS_OUT          : in  std_logic_vector(CMT_BUS_OUT_WIDTH);
        CMT_BUS_IN           : in  std_logic_vector(CMT_BUS_IN_WIDTH);

        -- MZ80B series can dynamically change the video frequency to attain 40/80 character display.
        CONFIG_CHAR80        : in  std_logic;

        -- Debug modes.
        DEBUG                : out std_logic_vector(DEBUG_WIDTH) 
    );
end mctrl;

architecture rtl of mctrl is

signal REGISTER_MODEL        : std_logic_vector(7 downto 0)     := "00000011";
signal REGISTER_DISPLAY      : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_DISPLAY2     : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_DISPLAY3     : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_CPU          : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_AUDIO        : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_CMT          : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_USERROM      : std_logic_vector(7 downto 0)     := "00000000";
signal REGISTER_FDCROM       : std_logic_vector(7 downto 0)     := "00000000";
constant REGISTER_DEBUG       : std_logic_vector(7 downto 0)     := "00000000";  -- Debug features off.
constant REGISTER_DEBUG2      : std_logic_vector(7 downto 0)     := "00000000";  -- Debug features off.
signal delay                 : integer range 0 to 63;
signal RESET_MACHINE         : std_logic;

begin
    -- Synchronise the register update with the configuration signals according to the CPU clock.
    --
    process (COLD_RESET, CLKBUS(CKMASTER))
    begin
        if COLD_RESET = '1' then
            CONFIG(CONFIG_WIDTH) <= "00000000000000000000000000000000000011000000000000000000000011001000001000";
            DEBUG(DEBUG_WIDTH)   <= "0000000000000000";

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1' then

            if CLKBUS(CKENCPU) = '1' then

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
    
                if CMT_BUS_OUT(ACTIVE) = '1' then
                    if REGISTER_MODEL(2 downto 0) /= "100" and REGISTER_MODEL(2 downto 0) /= "101" and REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                        case REGISTER_CMT(2 downto 0) is
                            when "000" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                            when "001" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                            when "010" => CONFIG(CPUSPEED) <= "0100";   -- 8MHz
                            when "011" => CONFIG(CPUSPEED) <= "0110";   -- 16MHz
                            when "100" => CONFIG(CPUSPEED) <= "1000";   -- 32MHz
                            when "101" => CONFIG(CPUSPEED) <= "1010";   -- 64MHz
                            when "110" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                            when "111" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                            when others => null;
                        end case;
                    elsif REGISTER_MODEL(2 downto 0) = "100" or REGISTER_MODEL(2 downto 0) = "101" then
                        case REGISTER_CMT(2 downto 0) is
                            when "000" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                            when "001" => CONFIG(CPUSPEED) <= "0011";   -- 7MHz
                            when "010" => CONFIG(CPUSPEED) <= "0101";   -- 14MHz
                            when "011" => CONFIG(CPUSPEED) <= "0111";   -- 28MHz
                            when "100" => CONFIG(CPUSPEED) <= "1001";   -- 56MHz
                            when "101" => CONFIG(CPUSPEED) <= "1001";   -- 32x: the fastest (clkgen caps the CPU at clk_sys/2)
                            when "110" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                            when "111" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                            when others => null;
                        end case;
                    elsif REGISTER_MODEL(2 downto 0)  = "110" or  REGISTER_MODEL(2 downto 0)  = "111" then
                        case REGISTER_CMT(2 downto 0) is
                            when "000" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                            when "001" => CONFIG(CPUSPEED) <= "0100";   -- 8MHz
                            when "010" => CONFIG(CPUSPEED) <= "0110";   -- 16MHz
                            when "011" => CONFIG(CPUSPEED) <= "1000";   -- 32MHz
                            when "100" => CONFIG(CPUSPEED) <= "1010";   -- 64MHz
                            when "101" => CONFIG(CPUSPEED) <= "1010";   -- 32x: the fastest (capped)
                            when "110" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                            when "111" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                            when others => null;
                        end case;
                    else
                        CONFIG(CPUSPEED) <= "0000";    -- Default 2MHz
                    end if;
                else
                    if REGISTER_MODEL(2 downto 0) /= "100" and REGISTER_MODEL(2 downto 0) /= "101" and REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                        case REGISTER_CPU(2 downto 0) is
                            when "000" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                            when "001" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                            when "010" => CONFIG(CPUSPEED) <= "0100";   -- 8MHz
                            when "011" => CONFIG(CPUSPEED) <= "0110";   -- 16MHz
                            when "100" => CONFIG(CPUSPEED) <= "1000";   -- 32MHz
                            when "101" => CONFIG(CPUSPEED) <= "1010";   -- 64MHz
                            when "110" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                            when "111" => CONFIG(CPUSPEED) <= "0000";   -- 2MHz
                            when others => null;
                        end case;
                    elsif REGISTER_MODEL(2 downto 0) = "100" or REGISTER_MODEL(2 downto 0) = "101" then
                        case REGISTER_CPU(2 downto 0) is
                            when "000" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                            when "001" => CONFIG(CPUSPEED) <= "0011";   -- 7MHz
                            when "010" => CONFIG(CPUSPEED) <= "0101";   -- 14MHz
                            when "011" => CONFIG(CPUSPEED) <= "0111";   -- 28MHz
                            when "100" => CONFIG(CPUSPEED) <= "1001";   -- 56MHz
                            when "101" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                            when "110" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                            when "111" => CONFIG(CPUSPEED) <= "0001";   -- 3.5MHz
                            when others => null;
                        end case;
                    elsif REGISTER_MODEL(2 downto 0)  = "110" or  REGISTER_MODEL(2 downto 0)  = "111" then
                        case REGISTER_CPU(2 downto 0) is
                            when "000" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                            when "001" => CONFIG(CPUSPEED) <= "0100";   -- 8MHz
                            when "010" => CONFIG(CPUSPEED) <= "0110";   -- 16MHz
                            when "011" => CONFIG(CPUSPEED) <= "1000";   -- 32MHz
                            when "100" => CONFIG(CPUSPEED) <= "1010";   -- 64MHz
                            when "101" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                            when "110" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                            when "111" => CONFIG(CPUSPEED) <= "0010";   -- 4MHz
                            when others => null;
                        end case;
                    else
                        CONFIG(CPUSPEED) <= "0000";    -- Default 2MHz
                    end if;
                end if;
    
                -- Setup the video speed dependent upon model and graphics option. VGA OUT currently
                -- forces all pixel clocks to 25.175MHz, otherwise the original pixel clock is chosen.
                --
                case REGISTER_MODEL(2 downto 0) is

                    -- MZ80K/C/1200/A
                    when "000" | "001" | "010" | "011" =>

                        case REGISTER_DISPLAY2(1 downto 0) & REGISTER_DISPLAY(2 downto 0) is

                            -- 40x25 mode requires 8MHz clock, Mono and Colour.
                            when "11000" | "11010" | "11100" | "11101" | "11110" | "11111" =>
                                CONFIG(VIDSPEED) <= "000";

                            -- 80x25 mode requires 16MHz clock, Mono and Colour.
                            when "11001" | "11011" =>
                                CONFIG(VIDSPEED) <= "001";

                            -- VGA Timing 640x480 @ 60Hz
                            when "01000" | "01001" | "01010" | "01011" | "01100" | "01101" | "01110" | "01111" =>
                                CONFIG(VIDSPEED) <= "100";

                            -- VGA Timing 640x480 @ 75Hz
                            when "10000" | "10001" | "10010" | "10011" | "10100" | "10101" | "10110" | "10111" =>
                                CONFIG(VIDSPEED) <= "110";

                            -- VGA Timing 640x480 @ 85Hz
                            when "00000" | "00001" | "00010" | "00011" | "00100" | "00101" | "00110" | "00111" =>
                                CONFIG(VIDSPEED) <= "111";
                            when others => null;
                        end case;

                    -- MZ700/MZ800 Models.
                    when "100" | "101" =>
                        -- Currently all modes default to one speed!
                        case REGISTER_DISPLAY2(1 downto 0) & REGISTER_DISPLAY(2 downto 0) is

                            -- 40x25 mode requires 8.8MHz clock, Mono and Colour.
                            when "11000" | "11010" | "11100" | "11101" | "11110" | "11111" =>
                                CONFIG(VIDSPEED) <= "010";
    
                            -- 80x25 mode requires 17.7MHz clock, Mono and Colour.
                            when "11001" | "11011" =>
                                CONFIG(VIDSPEED) <= "011";

                            -- VGA Timing 640x480 @ 60Hz
                            when "01000" | "01001" | "01010" | "01011" | "01100" | "01101" | "01110" | "01111" =>
                                CONFIG(VIDSPEED) <= "100";

                            -- VGA Timing 640x480 @ 75Hz
                            when "10000" | "10001" | "10010" | "10011" | "10100" | "10101" | "10110" | "10111" =>
                                CONFIG(VIDSPEED) <= "110";

                            -- VGA Timing 640x480 @ 85Hz
                            when "00000" | "00001" | "00010" | "00011" | "00100" | "00101" | "00110" | "00111" =>
                                CONFIG(VIDSPEED) <= "111";
                            when others => null;
                        end case;

                    -- MZ80B or MZ2200
                    when "110" | "111" =>
                        case REGISTER_DISPLAY2(1 downto 0) & REGISTER_DISPLAY(2 downto 0) is

                            -- 80x25 mode requires 16MHz clock, 40x25 requires 8MHz, switched on the CHAR80 signal.
                            when "11000" | "11001" | "11010" | "11011" | "11100" | "11101" | "11110" | "11111" =>
                                if CONFIG_CHAR80 = '1' then
                                    CONFIG(VIDSPEED) <= "001";
                                else
                                    CONFIG(VIDSPEED) <= "000";
                                end if;

                            -- VGA Timing 640x480 @ 60Hz
                            when "01000" | "01001" | "01010" | "01011" | "01100" | "01101" | "01110" | "01111" =>
                                CONFIG(VIDSPEED) <= "100";

                            -- VGA Timing 640x480 @ 75Hz
                            when "10000" | "10001" | "10010" | "10011" | "10100" | "10101" | "10110" | "10111" =>
                                CONFIG(VIDSPEED) <= "110";

                            -- VGA Timing 640x480 @ 85Hz
                            when "00000" | "00001" | "00010" | "00011" | "00100" | "00101" | "00110" | "00111" =>
                                CONFIG(VIDSPEED) <= "111";
                            when others => null;
                        end case;
                    when others => null;
                end case;
    
                -- Setup RTC clock frequency dependent upon model.
                if REGISTER_MODEL(2 downto 0) = "110" or REGISTER_MODEL(2 downto 0) = "111" then
                    CONFIG(RTCSPEED) <= "01";
                elsif REGISTER_MODEL(2 downto 0)  = "100" or  REGISTER_MODEL(2 downto 0)  = "101" then
                    CONFIG(RTCSPEED) <= "10";
                else
                    CONFIG(RTCSPEED) <= "00";
                end if;
    
                if REGISTER_MODEL(2 downto 0)  = "100" or REGISTER_MODEL(2 downto 0)  = "101" then
                    CONFIG(SNDSPEED) <= "01";
                elsif REGISTER_MODEL(2 downto 0)  = "110" then
                    CONFIG(SNDSPEED) <= "00";
                elsif REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                    CONFIG(SNDSPEED) <= "00";
                else
                    CONFIG(SNDSPEED) <= "00";
                end if;
    
                -- Setup the peripheral speed.
                if REGISTER_MODEL(2 downto 0)  = "101" or  REGISTER_MODEL(2 downto 0)  = "110" then
                    CONFIG(PERSPEED) <= "00";
                elsif REGISTER_MODEL(2 downto 0)  = "100" then
                    CONFIG(PERSPEED) <= "00";
                elsif REGISTER_MODEL(2 downto 0) /= "110" and REGISTER_MODEL(2 downto 0) /= "111" then
                    CONFIG(PERSPEED) <= "00";
                else
                    CONFIG(PERSPEED) <= "00";
                end if;
    
                CONFIG(GRAMIOADDR)   <= REGISTER_DISPLAY2(7 downto 3);
                CONFIG(VRAMDISABLE)  <= REGISTER_DISPLAY(4);
                CONFIG(GRAMDISABLE)  <= REGISTER_DISPLAY(5);
                CONFIG(VRAMWAIT)     <= REGISTER_DISPLAY(6);
                CONFIG(PCGRAM)       <= REGISTER_DISPLAY(7);
                CONFIG(VGAMODE)      <= REGISTER_DISPLAY2(1 downto 0);
                CONFIG(MENUENABLE)   <= REGISTER_DISPLAY3(0);
                CONFIG(STATUSENABLE) <= REGISTER_DISPLAY3(1);
                CONFIG(MZ800_MODE)   <= REGISTER_DISPLAY3(2);
                if REGISTER_MODEL(2 downto 0) = "100" then
                    CONFIG(IS_MZ1500) <= REGISTER_DISPLAY3(3);
                    CONFIG(REGION_JAPAN) <= REGISTER_DISPLAY3(4);
                else
                    CONFIG(IS_MZ1500) <= '0';
                    CONFIG(REGION_JAPAN) <= '0';
                end if;
                CONFIG(TURBO)        <= REGISTER_CPU(2 downto 0);
                CONFIG(FASTTAPE)     <= REGISTER_CMT(2 downto 0);
                CONFIG(BUTTONS)      <= REGISTER_CMT(4 downto 3);
                CONFIG(CMTASCII_IN)  <= REGISTER_CMT(5);
                CONFIG(CMTASCII_OUT) <= REGISTER_CMT(6);
                CONFIG(AUDIOSRC)     <= REGISTER_AUDIO(0);
                CONFIG(USERROM)      <= REGISTER_USERROM;
                CONFIG(FDCROM)       <= REGISTER_FDCROM;
                CONFIG(BOOT_RESET)   <= REGISTER_CPU(7);
    
                DEBUG(LEDS_BANK)     <= REGISTER_DEBUG(2 downto 0);
                DEBUG(LEDS_SUBBANK)  <= REGISTER_DEBUG(5 downto 3);
                DEBUG(LEDS_ON)       <= REGISTER_DEBUG(6);
                DEBUG(ENABLED)       <= REGISTER_DEBUG(7);
                DEBUG(SMPFREQ)       <= REGISTER_DEBUG2(3 downto 0);
                DEBUG(CPUFREQ)       <= REGISTER_DEBUG2(7 downto 4);
            end if;
        end if;
    end process;

    -- Configuration registers follow the OSD inputs. A change of model, display type, or a CPU setting
    -- change with boot reset enabled resets the machine, as the legacy register writes did.
    --
    process (COLD_RESET, CLKBUS(CKMASTER))
    begin
        if COLD_RESET = '1' then
            REGISTER_MODEL   <= "00000011";
            REGISTER_DISPLAY <= "00000000";
            REGISTER_DISPLAY2<= "00000000";
            REGISTER_DISPLAY3<= "00000000";
            REGISTER_CPU     <= "00000000";
            REGISTER_AUDIO   <= "00000000";
            REGISTER_CMT     <= "00000000";
            REGISTER_USERROM <= "00000000";
            REGISTER_FDCROM  <= "00000000";
            RESET_MACHINE    <= '1';
        elsif rising_edge(CLKBUS(CKMASTER)) then
            RESET_MACHINE    <= '0';

            if CFG_MODEL /= REGISTER_MODEL then
                RESET_MACHINE <= '1';
            end if;
            if CFG_DISPLAY(2 downto 0) /= REGISTER_DISPLAY(2 downto 0) then
                RESET_MACHINE <= '1';
            end if;
            if CFG_DISPLAY3(4 downto 3) /= REGISTER_DISPLAY3(4 downto 3) then   -- MZ-700 <-> MZ-1500 (same model code), Region (the monitor).
                RESET_MACHINE <= '1';
            end if;
            if CFG_CPU /= REGISTER_CPU and REGISTER_CPU(7) = '1' then
                RESET_MACHINE <= '1';
            end if;

            REGISTER_MODEL   <= CFG_MODEL;
            REGISTER_DISPLAY <= CFG_DISPLAY;
            -- Certain GRAM I/O address ranges are blocked by the underlying machine.
            if CFG_DISPLAY2(7 downto 4) /= "1111" and CFG_DISPLAY2(7 downto 4) /= "1110" and CFG_DISPLAY2(7 downto 4) /= "1101" then
                REGISTER_DISPLAY2 <= CFG_DISPLAY2;
            end if;
            REGISTER_DISPLAY3<= CFG_DISPLAY3;
            REGISTER_CPU     <= CFG_CPU;
            REGISTER_AUDIO   <= CFG_AUDIO;
            REGISTER_CMT     <= CFG_CMT;
            REGISTER_USERROM <= CFG_USERROM;
            REGISTER_FDCROM  <= CFG_FDCROM;
        end if;
    end process;

    -- System reset oneshot, triggered on COLD/WARM reset or a status change.
    process (CLKBUS(CKMASTER), COLD_RESET, WARM_RESET, RESET_MACHINE)
    begin
        if COLD_RESET = '1' or WARM_RESET = '1' or RESET_MACHINE = '1' then
            if COLD_RESET = '1' then
                delay <= 15;
            elsif WARM_RESET = '1' then
                delay <= 31;
            else
                delay <= 31;
            end if;

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER) = '1' then
            if delay = 63 then
                delay <= 0;
            elsif delay /= 0 then
                delay <= delay + 1;
            end if;
        end if;
    end process;
    SYSTEM_RESET <= '1' when delay > 0
                    else '0';
end rtl;
