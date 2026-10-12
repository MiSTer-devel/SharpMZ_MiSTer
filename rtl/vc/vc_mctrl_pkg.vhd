---------------------------------------------------------------------------------------------------------
--
-- Name:            mctrl.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series Programmable Machine Control logic.
--                  This module forms the Programmable control of the emulation along with sync reset
--                  management.
--                  A set of 16 addressable registers is presented on the external IO Processor
--                  interface. Each register controls an aspect of the emulation, such as video mode or
--                  cpu speed.
--
--                  Reset to all components is managed by this module, taking cold, warm and internally
--                  generated reset signals and creating a unified system reset output.
--
--                  Please see the docs/SharpMZ_Notes.xlsx spreadsheet for details on these registers
--                  and the values they take.
--
-- Credits:         
-- Copyright:       (c) 2018-21 Philip Smart <philip.smart@net2net.org>
--
-- History:         July 2018   - Initial module written.
--                  May 2021    - Port and major change for use within the coreMZ tranZPUter emuMZ module.
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


library ieee;
library pkgs;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- vc_mctrl_pkg: the v2 (tranZPUter emuMZ) mctrl_pkg CONFIG bit layout, which the v2 VideoController
-- is written against. Copied from refs/tranZPUter/FPGA/SW700/v1.3/MZ700/emuMZ/mctrl.vhd and renamed so
-- it can coexist with the core's own mctrl_pkg; rtl/vc/video_vc.vhd translates between the two.

package vc_mctrl_pkg is

    -- Config Bus
    --
    subtype  CONFIG_WIDTH is integer range 90 downto 0;


    -- Mode signals indicating type of machine we are emulating.
    --
    constant MZ80K           : integer := 0;                             -- Machine is an MZ80K
    constant MZ80C           : integer := 1;                             -- Machine is an MZ80C
    constant MZ1200          : integer := 2;                             -- Machine is an MZ1200
    constant MZ80A           : integer := 3;                             -- Machine is an MZ80A
    constant MZ700           : integer := 4;                             -- Machine is an MZ700
    constant MZ800           : integer := 5;                             -- Machine is an MZ800
    constant MZ1500          : integer := 6;                             -- Machine is an MZ1500
    constant MZ80B           : integer := 7;                             -- Machine is an MZ80B
    constant MZ2000          : integer := 8;                             -- Machine is an MZ2000
    constant MZ2200          : integer := 9;                             -- Machine is an MZ2200
    constant MZ2500          : integer := 10;                            -- Machine is an MZ2500
    subtype  CURRENTMACHINE  is integer range 10 downto 0;               -- Range of bits to indicate current machine class, only 1 bit is set at a time.
    constant MZ_KC           : integer := 11;                            -- Machine is an MZ80K/MZ80C Series
    constant MZ_A            : integer := 12;                            -- Machine is an MZ1200/MZ80A Series
    constant MZ_B            : integer := 13;                            -- Machine is an MZ2000/MZ80B Series
  --constant MZ_80B          : integer := 14;                            -- Machine is an MZ2000/MZ80B Series
    constant MZ_K            : integer := 15;                            -- Machine is an MZ80K/MZ80C/MZ1200/MZ80A/MZ700/MZ800/MZ1500 Series

    -- Type of display to emulate.
    --
    constant NORMAL          : integer := 16;                            -- Normal 40 x 25 character monochrome display.
    constant NORMAL80        : integer := 17;                            -- Normal 80 x 25 character monochrome display.
    constant COLOUR          : integer := 18;                            -- Colour 40 x 25 character display.
    constant COLOUR80        : integer := 19;                            -- Colour 80 x 25 character display.
    subtype  CURRENTDISPLAY  is integer range 19 downto 16;              -- Range of bits which indicate the display output mode.
    subtype  VGAMODE         is integer range 23 downto 20;              -- Output display ie. 640x400 or 640x480, double up pixels as required.

    -- Option Roms Enable (some machines by design dont have them, but this emulation allows them to be enabled if needed).
    --
    constant USERROM         : integer := 24;                            -- User ROM E800 - EFFF enable.
    constant FDCROM          : integer := 25;                            -- FDC ROM F000 - FFFF enable.

    -- Floppy drive/interface options.
    constant FDDENABLE       : integer := 26;                            -- Enable the Floppy Disk Controller.
    constant FDDINTEN        : integer := 27;                            -- Enable the interrupt request from the FDC controller (non standard).
    subtype  FDDDISKREADY    is integer range 31 downto 28;              -- Drive data polarity.
    subtype  FDDPOLARITY     is integer range 35 downto 32;              -- Drive data polarity.
    subtype  FDDWRPROTECT    is integer range 39 downto 36;              -- Drive write protect/readonly.
    constant FDDDISKREADY_0  : integer := 28;                            -- Drive 0 disk loaded and drive ready.
    constant FDDDISKREADY_1  : integer := 29;                            -- Drive 1 disk loaded and drive ready.
    constant FDDDISKREADY_2  : integer := 30;                            -- Drive 2 disk loaded and drive ready.
    constant FDDDISKREADY_3  : integer := 31;                            -- Drive 3 disk loaded and drive ready.
    constant FDDPOLARITY_0   : integer := 32;                            -- Drive 0 data polarity.
    constant FDDPOLARITY_1   : integer := 33;                            -- Drive 1 data polarity.
    constant FDDPOLARITY_2   : integer := 34;                            -- Drive 2 data polarity.
    constant FDDPOLARITY_3   : integer := 35;                            -- Drive 3 data polarity.
    constant FDDWRPROTECT_0  : integer := 36;                            -- Drive 0 write protect/readonly.
    constant FDDWRPROTECT_1  : integer := 37;                            -- Drive 1 write protect/readonly.
    constant FDDWRPROTECT_2  : integer := 38;                            -- Drive 2 write protect/readonly.
    constant FDDWRPROTECT_3  : integer := 39;                            -- Drive 3 write protect/readonly.

    -- RAM options installed.
    subtype  RAMINSTALLED    is integer range 42 downto 40;              -- RAM installed in machine.
    subtype  GRAPHICSOPTION  is integer range 50 downto 43;              -- GRAM installed in machine.

    -- RAM options.
    constant OPT_MINRAM      : std_logic_vector(2 downto 0) := "000";    -- Minimum RAM installed on machine.
    constant OPT_STDRAM      : std_logic_vector(2 downto 0) := "001";    -- Standard (considered Normal, but upgraded for early machines) RAM installed on machine.

    -- GRAM options.
    constant OPT_GRAMI       : integer := 43;                            -- MZ80B GRAMI   / MZ2000 GRAM BLUE installed.
    constant OPT_GRAMII      : integer := 44;                            -- MZ80B GRAMII  / MZ2000 GRAM RED installed.
    constant OPT_GRAMIII     : integer := 45;                            -- MZ2000 GRAM GREEN installed.
    constant OPT_PCG         : integer := 46;                            -- PCG installed.
    constant OPT_MZ1R25      : integer := 47;                            -- 16K Video RAM installed

    -- Various configurable settings.
    --
    constant AUDIOSRC        : integer := 51;                            -- Audio source, 0 = sound generator, 1 = tape audio.
    subtype  AUDIOVOL        is integer range 55 downto 52;              -- Audio volume, 3:0 = 16 level volume.
    subtype  AUDIOMIX        is integer range 57 downto 56;              -- Audio mixer, blend left and right channels.
    constant AUDIOHW         : integer := 58;                            -- Audio hardware to use, host or fpga.
    subtype  TURBO           is integer range 61 downto 59;              -- 2MHz/4MHz/8MHz/16MHz/32MHz switch (various).
    subtype  FASTTAPE        is integer range 64 downto 62;              -- Speed of tape read/write.
    subtype  BUTTONS         is integer range 66 downto 65;              -- Various external buttons, such as CMT play/record.
    constant PCGRAM          : integer := 67;                            -- PCG ROM(0) or RAM(1) based.
    constant VRAMWAIT        : integer := 68;                            -- Insert video wait states on CPU access as per original design.
    constant VRAMDISABLE     : integer := 69;                            -- Disable the Video RAM from display output.
    constant GRAMDISABLE     : integer := 70;                            -- Disable the graphics RAM from display output.
    constant MENUENABLE      : integer := 71;                            -- Enable the OSD menu on display output.
    constant STATUSENABLE    : integer := 72;                            -- Enable the OSD menu on display output.
    constant BOOT_RESET      : integer := 73;                            -- MZ80B/2000 Boot IPL Reset Enable.
    constant CMTASCII_IN     : integer := 74;                            -- Enable CMT conversion of Sharp Ascii <-> Ascii on receipt of data from Sharp.
    constant CMTASCII_OUT    : integer := 75;                            -- Enable CMT conversion of Sharp Ascii <-> Ascii on sending data to Sharp.
    constant CMT_HWMODE      : integer := 76;                            -- Select the hardware CMT drive (1) or the emulation (0).
    subtype  MZ800_SWITCH    is integer range 80 downto 77;              -- MZ800 Hardware selection switch bank.

    -- MZ-800 Switches.
    constant SWITCH_MZ800    : integer := 77;                            -- Machine set to MZ800 mode.
    constant SWITCH_PRINTER1 : integer := 78;                            -- MZ/Centronics Printer.
    constant SWITCH_PRINTER2 : integer := 79;                            -- MZ/Centronics Printer.
    constant SWITCH_TAPEIN   : integer := 80;                            -- Enable external data recorder input.

    -- Derivative settings to program the clock generator.
    --
    subtype  CPUSPEED        is integer range 84 downto 81;              -- Active CPU Speed.
    subtype  PERSPEED        is integer range 86 downto 85;              -- Active Peripheral Speed.
    subtype  RTCSPEED        is integer range 88 downto 87;              -- Active RTC Speed.
    subtype  SNDSPEED        is integer range 90 downto 89;              -- Active Sound Speed.

    -- CMT Bus
    --
    subtype  CMT_BUS_OUT_WIDTH  is integer range 16 downto 0;
    subtype  CMT_BUS_IN_WIDTH   is integer range 12 downto 0;

    -- CMT exported Signals.
    --
    constant PLAY_READY      : integer := 0;                             -- Tape play back buffer, 0 = empty, 1 = full.
    constant PLAYING         : integer := 1;                             -- Tape playback, 0 = stopped, 1 = in progress.
    constant RECORD_READY    : integer := 2;                             -- Tape record buffer full, 0 = empty, 1 = full.
    constant RECORDING       : integer := 3;                             -- Tape recording, 0 = stopped, 1 = in progress.
    constant ACTIVE          : integer := 4;                             -- Tape transfer in progress, 0 = no activity, 1 = activity.
    constant SENSE           : integer := 5;                             -- Tape state Sense out.
    constant WRITEBIT        : integer := 6;                             -- Write bit to MZ.
    constant TAPEREADY       : integer := 7;                             -- Tape is loaded in deck when L = 0.
    constant WRITEREADY      : integer := 8;                             -- Write is prohibited when L = 0.
    constant APSS_SEEK       : integer := 9;                             -- Start to seek the next program according to APSS_DIR
    constant APSS_DIR        : integer := 10;                            -- Direction for APSS Seek, 0 = Rewind, 1 = Forward.
    constant APSS_EJECT      : integer := 11;                            -- Eject cassette.
    constant APSS_PLAY       : integer := 12;                            -- Play cassette.
    constant APSS_STOP       : integer := 13;                            -- Stop playing/rwd/ff of cassette.
    constant APSS_AUTOREW    : integer := 14;                            -- Deck set to auto rewind at tape end.
    constant APSS_AUTOPLAY   : integer := 15;                            -- Deck set to auto play after APSS action.
    constant ENDOFTAPE       : integer := 16;                            -- End of tape detected.

    -- CMT imported Signals.
    --
    constant READBIT         : integer := 0;                             -- Receive bit from MZ.
    constant REEL_MOTOR      : integer := 1;                             -- APSS Reel Motor on/off.
    constant STOP            : integer := 2;                             -- Stop the motor.
    constant PLAY            : integer := 3;                             -- Play cassette.
    constant SEEK            : integer := 4;                             -- Seek cassette using DIRECTION (L = Rewind, H = FF).
    constant DIRECTION       : integer := 5;                             -- Seek direction, L = Rewind, H = Fast Forward.
    constant EJECT           : integer := 6;                             -- Eject the cassette.
    constant WRITEENABLE     : integer := 7;                             -- Enable writing to cassette.
    constant AUTOPLAY        : integer := 8;                             -- Enable playback at end of rewind.
    constant AUTOREW         : integer := 9;                             -- Enable playback at end of rewind.
    constant CMTFF           : integer := 10;                            -- Fast Forward cassette.
    constant CMTREW          : integer := 11;                            -- Rewind cassette.
    constant KINH            : integer := 12;                            -- Keyboard inhibit, stops FF,REW,STOP and EJECT from being pressed.
end vc_mctrl_pkg;
