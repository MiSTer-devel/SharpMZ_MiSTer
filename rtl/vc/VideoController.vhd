---------------------------------------------------------------------------------------------------------
--
-- Name:            VideoController.vhd
-- Created:         June 2020
-- Author(s):       Philip Smart
-- Description:     Sharp MZ Series Video Module FPGA logic definition file.
--                  This module contains the definition of the video controller used in tranZPUter FPGA
--                  core whicch appears on the tranZPUter and tranZPUter SW 700 boards. The controller
--                  emulates the video logic of the Sharp MZ80A, MZ-700 and MZ80B including pixel graphics.
--                  The design needs 64KB of memory, so using a smaller FPGA would require the addition
--                  of an external SRAM and like most developments, more is better until the design is
--                  finalised as it gives you more options. This is especially true as the core FPGA will
--                  also instantiate Soft-CPU's for the Sharp MZ series, either the T80 clocking at 50-100MHz
--                  or other processors as time deems feasible to incorporate.
--
--                  One aim of this module is to maintain a degree of compatibility with the Sharp MZ
--                  emulator hardware I wrote, backporting enhancements made here and potentially making a
--                  single design shared by both.
--
-- Credits:         
-- Copyright:       (c) 2018-21 Philip Smart <philip.smart@net2net.org>
--
-- History:         June 2020 - Initial creation.
--                  Sep 2020  - Working first version. Slight sync issues on the VGA modes 1 & 2 as
--                              they use a seperate PLL so sometimes switching to these modes causes
--                              flicker which can be resolved by just reswitching to the same mode.
--                              All the MZ80B logic etc has been ported from my Emulator but not yet
--                              tested as I need to finish implementing the MZ80B mode on the MZ80A
--                              via the tranZPUter. Will feed back the video output generation into the
--                              Emulator as the original emulator design has bugs!
--                              A nice to have would be a seperate video output stream to the internal
--                              monitor when using VGA modes on the external display but this requires
--                              another framebuffer and the FPGA hasnt got the resources. Maybe v2.1
--                              will contain a bigger FPGA (or external RAM)!!!!
--                  Oct 2020  - Split off from the Sharp MZ80A Video Module, the Video Module for the 
--                              Sharp MZ700 has the same roots but different control functionality. The
--                              MZ700 version resides within the tranZPUter memory and not the mainboard
--                              allowing for generally easier control. The MZ80A and MZ700 graphics logic
--                              should be pretty much identical.
--                  Nov 2020 -  A further split from the SW700 board v1.2 logic, this time as part of 
--                              a reorganisation where the larger v1.3 FPGA will not only incorporate
--                              video logic but also soft-cpu's.
--                  Dec 2020 -  Added logic to accommodate direct addressing of the various internal
--                              memory devices to allow soft CPU's to avoid using the Sharp MZ register
--                              selection and 8K address space window.
--                  Jan-Sep 21- Numerous evolutions and changes of the logic to accommodate the FPGA 
--                              series emulator, ZPU and embedding in the MZ-80A/700/800 machines.
--                  Oct 2021 -  Updates to allow embedding inside an MZ-2000 and also to complete the
--                              MZ-2000 GRAM logic. Removed rendering of a full frame buffer and now
--                              just render on a just in time basis.
--                              I/O Port reassignment was necessary as the MZ-800 and MZ-2000 use not
--                              just the E0:EF and F4:F7 area but the entire block from C0:FF. Thus all
--                              non-sharp specific controller configuration is made in the region
--                              A0:BF and the CPLD region 60:6F.
--                              Updates to the rendering and frame generation to resolve bugs and make
--                              the output fully functioning on both the MZ-700/MZ-2000 and the emulation.
--                              Removed the 1024x768 mode as it wasnt necessary, max resolution will be
--                              640x200 or whatever 16K per plane can provide and expansion to this
--                              resolution isnt linear to ending up with a display which isnt as good
--                              as the other resolutions.
--                  Nov 2021 -  Further updates as the emulation progresses and changes to accommodate
--                              the graphics modes of the MZ80B/MZ2000, seperating the character, graphics
--                              and OSD to seperate planes, blended just before the palette registers.
--                              The MZ-2000 graphics are 649x200 regardless of character mode, likewise
--                              the MZ80B is 320x20 regardless of 40/80 column mode.
--                              Split the lookup tables into timing information which is common amongst
--                              different modes and mode specific settings.
--                              Removed the display parameter update capability as it added a lot of 
--                              logic and didnt add to useability, more a debugging option and wasnt
--                              needed.
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
use     ieee.std_logic_1164.all;
use     ieee.std_logic_unsigned.all;
use     ieee.numeric_std.all;
use     work.VideoController_pkg.all;
use     work.vc_mctrl_pkg.all;
use     work.vc_rams_pkg.all;
use     pkgs.clkgen_pkg.all;

entity VideoController is
    --generic (
    --);
    generic (
        CLK_HZ                   : natural := CLK_SYS_HZ                           -- SYS_CLK frequency; the video runs on it with clock enables.
    );
    port (    
        -- Primary FPGA clock for generation of video clocks.
        CLOCK_50                 : in    std_logic;                                      -- 50MHz main FPGA clock.

        -- System wide primary logic clock.
        SYS_CLK                  : in    std_logic;                                      -- Master timing clock.

        -- Reset.
        VRESETn                  : in    std_logic;                                      -- Internal reset.

        -- MZ-1500 PCG (SharpMZ MiSTer): the planes live in video_vc; the character renderer composites them.
        M15_PCGON                : in    std_logic := '0';                               -- MZ-1500 with port F0 bit 0 set.
        M15_PRIO                 : in    std_logic := '0';                               -- Port F0 bit 1: 0 = BPF (characters over PCG), 1 = BFP.
        M15_PAL                  : in    std_logic_vector(23 downto 0) := (others => '0'); -- Port F1: colour of PCG index i in bits 3i+2..3i (b0 B, b1 R, b2 G).
        BCOL_O                   : out   std_logic_vector(3 downto 0);                   -- MZ-800 border colour (BCOL: I, G, R, B), for the border outside.
        PCG_RD_ADDR              : out   std_logic_vector(12 downto 0);                  -- PCG character row address (char * 8 + row).
        PCG_RD_DATA              : in    std_logic_vector(23 downto 0) := (others => '0'); -- Planes 2, 1, 0.

        -- Direct addressing Bus. Normally this is set to 0 during standard Sharp MZ operation, when 23:19 > 0 then direct addressing of the various video
        -- memory's is enabled.
        -- Address    A23 -A16
        -- 0x000000   00000000 - Normal Sharp MZ behaviour
        -- 0x200000   00100000 - Memory and I/O ports mapped into direct addressable memory location.
        --
        --                       A15 - A8 A7 -  A0
        --                       I/O registers are mapped to the bottom 256 bytes mirroring the I/O address.
        -- 0x2000A0              00000000 10100000 - 0xA0 - 
        --                       00000000 10100001 - 0xA1 - 
        --                       00000000 10100010 - 0xA2 - 
        --                       00000000 10100011 - 0xA3 - set the palette slot Off position to be adjusted.
        --                       00000000 10100100 - 0xA4 - set the palette slot On position to be adjusted.
        --                       00000000 10100101 - 0xA5 - set the red palette value according to the PALETTE_PARAM_SEL address.
        --                       00000000 10100110 - 0xA6 - set the green palette value according to the PALETTE_PARAM_SEL address.
        -- 0x2000A7              00000000 10100111 - 0xA7 - set the blue palette value according to the PALETTE_PARAM_SEL address.
        --                       00000000 10101000 - 0xA8 - Get OSD Menu Horizontal Size (X).
        --                       00000000 10101001 - 0xA9 - Get OSD Menu Vertical Size (Y).
        --                       00000000 10101010 - 0xAA - Get OSD Status Header Horizontal Size (X).
        --                       00000000 10101011 - 0xAB - Get OSD Status Header Vertical Size (Y).
        --                       00000000 10101100 - 0xAC - Get OSD Status Footer Horizontal Size (X).
        --                       00000000 10101101 - 0xAD - Get OSD Status Footer Vertical Size (Y).
        --                       00000000 10101110 - 0xAE - Configuration byte 1.
        --                       00000000 10101111 - 0xAF - Configuration byte 2.
        -- 0x2000B0              00000000 10110000 - 0xB0 - sets the active palette.
        -- 0x2000B1              00000000 10110001 - 0xB1 - 
        --                       00000000 10110010 - 0xB2 - set the GPU parameters.
        --                       00000000 10110011 - 0xB3 - set the graphics processor unit commands.
        --                       00000000 10111000 - 0xB8 - set the video mode. 
        --                       00000000 10111001 - 0xB9 - set the graphics mode.
        --                       00000000 10111010 - 0xBA - set the Red bit mask
        --                       00000000 10111011 - 0xBB - set the Green bit mask
        --                       00000000 10111100 - 0xBC - set the Blue bit mask
        -- 0x2000BD              00000000 10111101 - 0xBD - set the Video memory page in block C000:FFFF 
        --                       00000000 10111110 - 0xBE - set the VGA border colour and attributes.
        -- 0x2000BF              00000000 10111111 - 0xBF - set the VGA mode.
        --
        -- 0x2000CC              00000000 11001100 - 0xCC - MZ800 CRTC GWF    Write format Register
        -- 0x2000CD              00000000 11001101 - 0xCD - MZ800 CRTC GRF   Read format Register
        -- 0x2000CE              00000000 11001110 - 0xCE - MZ800 CRTC GDMD  Mode Register
        -- 0x2000CF              00000000 11001111 - 0xCF - MZ800 CRTC GCRTC Control Register
        --                       00000XXX                 - Upper 16 bits can be set betweeen 0 and 7 to accommodate CRTC programming.
        --
        -- 0x2000D0              00000000 11010000 - 0xD0 - MZ800 PPI
        --                       00000000 11010100 - 0xD4 - MZ800 PIT
        --
        -- 0x2000E0              00000000 11100000 - 0xE0 - MZ80B PPI
        --                       00000000 11100100 - 0xE4 - MZ80B PIT
        -- 0x2000E8              00000000 11101000 - 0xE8 - MZ80B PIO
        --
        --                       00000000 11110000 - 0xF0 - MZ800 Pallet write / Joystick 1 input
        --                       00000000 11110001 - 0xF1 - MZ800 Joystick 2 input
        --                       00000000 11110010 - 0xF2 - MZ800 PSG output port
        -- 0x2000F3              00000000 11110011 - 0xF3 
        --                       00000000 11110100 - 0xF4 set the MZ80B video in/out mode or MZ2000 Colour CRT Background Colour Selection.
        --                       00000000 11110101 - 0xF5 MZ2000 Priority, Bit 3 = 0, Character comes to foreground, = 1, Graphics comes to foreground. 2:0 = Colour
        --                       00000000 11110110 - 0xF6 MZ2000 Bit 4 Graphics Display on CRT (H), 2:0 colour VRAM enable to Colour CRT / CRT (if enabled).
        --                       00000000 11110111 - 0xF7 MZ2000 Selection of VRAM bank in memory map when enabled, 0 = None, 1 = Blue, 2 = Red, 3 = Green
        --
        --                       Memory registers are mapped to the E000 region as per base machines.
        -- 0x20E010              11100000 00010010 - Program Character Generator RAM. E010 - Write cycle (Read cycle = reset memory swap).
        --                       11100000 00010100 - Normal display select.
        --                       11100000 00010101 - Inverted display select.
        --                       11100010 00000000 - Scroll display register. E200 - E2FF
        -- 0x20E2FF              11111111
        --
        -- 0x210000   00100001 - Video/Attribute RAM / MZ800 Graphics RAM . 64K Window.
        -- 0x218000              10000000 00000000 - MZ800 Graphics RAM Window Start lower 16K
        -- 0x219FFF              10011111 11111111
        -- 0x21A000              10100000 00000000 - MZ800 Graphics RAM Window Start upper 16K
        -- 0x21BFFF              10111111 11111111
        -- 0x21D000              11010000 00000000 - Video RAM
        -- 0x21D7FF              11010111 11111111
        -- 0x21D800              11011000 00000000 - Attribute RAM
        -- 0x21DFFF              11011111 11111111
        --
        -- 0x220000   00100010 - Character Generator ROM/RAM
        -- 0x220000              00000000 00000000 - CGROM
        -- 0x220FFF              00001111 11111111 
        -- 0x221000              00010000 00000000 - CGRAM
        -- 0x221FFF              00011111 11111111
        --
        -- 0x240000   00100100 - Red framebuffer.
        --                       00000000 00000000 - Red pixel addressed framebuffer. Also MZ-80B GRAM I memory in lower 8K
        -- 0x243FFF              00111111 11111111
        -- 0x250000   00100101 - Blue framebuffer.
        --                       00000000 00000000 - Blue pixel addressed framebuffer. Also MZ-80B GRAM II memory in lower 8K
        -- 0x253FFF              00111111 11111111
        -- 0x260000   00100110 - Green framebuffer.
        --                       00000000 00000000 - Green pixel addressed framebuffer.
        -- 0x263FFF              00111111 11111111
        -- 0x270000   00010111 - Blue Menu/Status framebuffer.
        -- 0x271FFF              00011111 11111111
        -- 0x280000   00011000 - Red Menu/Status framebuffer.
        -- 0x281FFF              00011111 11111111
        -- 0x290000   00011001 - Green Menu/Status framebuffer.
        -- 0x291FFF              00011111 11111111
        -- 0x2A0000   00011010 - Red/Green/Blue Menu/Status framebuffer write only.
        -- 0x291FFF              00011111 11111111
        VIDEO_ADDR               : in    std_logic_vector(23 downto 0);                  -- CPU Address bus. Upper byte is for direct addressing (ie /= 0) and used by external systems or a soft CPU.

        -- Data Bus
        VIDEO_DATA_IN            : in    std_logic_vector(31 downto 0);                  -- Data bus into video module.
        VIDEO_DATA_OUT           : out   std_logic_vector(31 downto 0);                  -- Data bus out from video module to CPU.

        -- Control signals.
        VIDEO_MREQn              : in    std_logic;                                      -- MREQ signal, active low.
        VIDEO_IORQn              : in    std_logic;                                      -- IORQ signal, active low.
        VIDEO_RDn                : in    std_logic;                                      -- Video RDn from the CPLD, decoded via memory manager.
        VIDEO_WRn                : in    std_logic;                                      -- Video WRn from the CPLD, decoded via memory manager.
        VIDEO_WR_BYTE            : in    std_logic;                                      -- Signal to indicate a byte should be written not a 32bit word.
        VIDEO_WR_HWORD           : in    std_logic;                                      -- Signal to indicate a 16bit half word should be written not a 32bit word.
        VIDEO_DATA_AVAILn        : out   std_logic;                                      -- Signal to indicate data is available for reading.

        -- VGA & Composite output signals.
        VGA_R                    : out   std_logic_vector(3 downto 0);                   -- 16 level Red output.
        VGA_G                    : out   std_logic_vector(3 downto 0);                   -- 16 level Green output.
        VGA_B                    : out   std_logic_vector(3 downto 0);                   -- 16 level Blue output.
        VGA_R_COMPOSITE          : inout std_logic;                                      -- RGB Red override for composite output.
        VGA_G_COMPOSITE          : inout std_logic;                                      -- RGB Green override for composite output.
        VGA_B_COMPOSITE          : inout std_logic;                                      -- RGB Blue override for composite output.
        HSYNC_OUTn               : out   std_logic;                                      -- Horizontal sync.
        VSYNC_OUTn               : out   std_logic;                                      -- Vertical sync.
        HBLANK_OUT               : out   std_logic;                                      -- Horizontal blanking.
        VBLANK_OUT               : out   std_logic;                                      -- Vertical blanking.
        COLR_OUT                 : out   std_logic;                                      -- Composite and RF base frequency.
        CSYNC_OUTn               : out   std_logic;                                      -- Composite sync (negative).
        CSYNC_OUT                : out   std_logic;                                      -- Composite sync (positive).

        -- RGB & Composite input signals.
        -- V[name] = Voltage translated signals which mirror the mainboard signals but at a lower voltage.
        VWAITn_V_CSYNC           : inout std_logic;                                      -- Wait signal to the CPU when accessing FPGA video RAM / Composite sync from mainboard.
        V_HSYNCn                 : in    std_logic;                                      -- Horizontal sync (negative) from mainboard.
        V_VSYNCn                 : in    std_logic;                                      -- Vertical sync (negative) from mainboard.
        V_COLR                   : in    std_logic;                                      -- Soft CPU NMIn / Composite and RF base frequency from mainboard.
        V_G                      : in    std_logic;                                      -- Soft CPU BUSRQn / Digital Green (on/off) from mainboard.
        V_B                      : in    std_logic;                                      -- Soft CPU WAITn / Digital Blue (on/off) from mainboard.
        V_R                      : in    std_logic;                                      -- Soft CPU INTn / Digital Red (on/off) from mainboard.
 
        -- Configuration.
        HW_HOST                  : in    std_logic_vector(2 downto 0);                   -- Underlying hardware on which the Video Controller is running.
        HW_MODE                  : in    std_logic_vector(1 downto 0);                   -- Mode of the hardware, 00 = host controlled, 01 = I/O Processor controlled, 10 = emuMZ controlled.
        MB_VIDEO_ENABLEn         : in    std_logic;                                      -- Mainboard Video (=0) or FPGA Video (=1).
        CONFIG                   : in    std_logic_vector(CONFIG_WIDTH);                 -- Configuration string, used by the Sharp MZ Series Emulator to configure video settings rather than register writes.
        CE_PIXEL                 : out   std_logic;                                      -- Pixel clock enable on SYS_CLK: RGB/syncs are valid at each SYS_CLK edge where it is high.

        -- Character generator ROM: 32 KB of 2 KB banks (rtl/software/mif/combined_cgrom.mif). The bank
        -- is chosen per machine; CG_4K machines (MZ-700/800) use two banks selected by CG_ADDR(11).
        VIDEO_50HZ               : in    std_logic;                                      -- PAL 50Hz native timing (MZ-700/800) instead of 60Hz.
        CG_BANK                  : in    std_logic_vector(3 downto 0);
        CG_4K                    : in    std_logic;
        CG_IOCTL_ADDR            : in    std_logic_vector(14 downto 0);                  -- ioctl access to the CG ROM.
        CG_IOCTL_WR              : in    std_logic;
        CG_IOCTL_DOUT            : in    std_logic_vector(7 downto 0);
        CG_IOCTL_DIN             : out   std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of VideoController is


    -- Constants
    --
    constant MAX_SUBROW              : integer := 8;
    constant VIDEO_DEBUG             : std_logic := '0';
    constant OSD_FG_RED              : integer := 15;
    constant OSD_FG_GREEN            : integer := 14;
    constant OSD_FG_BLUE             : integer := 13;
    constant OSD_BG_RED              : integer := 12;
    constant OSD_BG_GREEN            : integer := 11;
    constant OSD_BG_BLUE             : integer := 10;

    -- Clock selection definitions for video timing.
    constant SEL_CLOCK_8MHZ          : integer := 0;
    constant SEL_CLOCK_8_8MHZ        : integer := 1;
    constant SEL_CLOCK_16MHZ         : integer := 2;
    constant SEL_CLOCK_17_7MHZ       : integer := 3;
    constant SEL_CLOCK_25MHZ         : integer := 4;
    constant SEL_CLOCK_40MHZ         : integer := 5;

    -- Timing definition constants for better readability. These are mapped to the VIDEOTIMINGLUT position so changing the LUT table will need these constants updating.
    --
    constant TIMING_MONO40_60HZ      : integer := 0;
    constant TIMING_MONO80_60HZ      : integer := 1;
    constant TIMING_COLOUR40_60HZ    : integer := 2;
    constant TIMING_COLOUR80_60HZ    : integer := 3;
    constant TIMING_VGA640X480_60HZ  : integer := 4;
    constant TIMING_VGA800X600_60HZ  : integer := 5;
  --constant TIMING_VGA1024X768_60HZ : integer := 6;
    constant TIMING_COLOUR40_50HZ    : integer := 6;
    constant TIMING_COLOUR80_50HZ    : integer := 7;
    constant TIMING_INT40_60HZ       : integer := 8;
    constant TIMING_INT80_60HZ       : integer := 9;

    -- MZ800 Graphics Display Controller constants.
    -- The GRAM is 32 bits wide for 320x200 mode, each byte representing one of four planes.
    -- The GRAM is 16 bits wide for 640x200 mode, each byte representing one of two planes.
    subtype  GD_320_PLANE_I_RANGE    is natural range  7 downto 0;
    subtype  GD_320_PLANE_II_RANGE   is natural range 15 downto 8;
    subtype  GD_320_PLANE_III_RANGE  is natural range 23 downto 16;
    subtype  GD_320_PLANE_IV_RANGE   is natural range 31 downto 24;
    subtype  GD_640_PLANE_I_RANGE    is natural range  7 downto 0;
    subtype  GD_640_PLANE_III_RANGE  is natural range 15 downto 8;
    subtype  GD_320_DISPLAY_RANGE    is natural range 12 downto 0;
    subtype  GD_640_DISPLAY_RANGE    is natural range 13 downto 0;
    subtype  GD_320_MZ1R25_RANGE     is natural range 31 downto 16;
    subtype  GD_640_MZ1R25_RANGE     is natural range 15 downto 8;
    constant GD_320_PLANE_I_BIT7     : integer := 7;
    constant GD_320_PLANE_I_BIT6     : integer := 6;
    constant GD_320_PLANE_I_BIT5     : integer := 5;
    constant GD_320_PLANE_I_BIT4     : integer := 4;
    constant GD_320_PLANE_I_BIT3     : integer := 3;
    constant GD_320_PLANE_I_BIT2     : integer := 2;
    constant GD_320_PLANE_I_BIT1     : integer := 1;
    constant GD_320_PLANE_I_BIT0     : integer := 0;
    constant GD_320_PLANE_II_BIT7    : integer := 15;
    constant GD_320_PLANE_II_BIT6    : integer := 14;
    constant GD_320_PLANE_II_BIT5    : integer := 13;
    constant GD_320_PLANE_II_BIT4    : integer := 12;
    constant GD_320_PLANE_II_BIT3    : integer := 11;
    constant GD_320_PLANE_II_BIT2    : integer := 10;
    constant GD_320_PLANE_II_BIT1    : integer := 9;
    constant GD_320_PLANE_II_BIT0    : integer := 8;
    constant GD_320_PLANE_III_BIT7   : integer := 23;
    constant GD_320_PLANE_III_BIT6   : integer := 22;
    constant GD_320_PLANE_III_BIT5   : integer := 21;
    constant GD_320_PLANE_III_BIT4   : integer := 20;
    constant GD_320_PLANE_III_BIT3   : integer := 19;
    constant GD_320_PLANE_III_BIT2   : integer := 18;
    constant GD_320_PLANE_III_BIT1   : integer := 17;
    constant GD_320_PLANE_III_BIT0   : integer := 16;
    constant GD_320_PLANE_IV_BIT7    : integer := 31;
    constant GD_320_PLANE_IV_BIT6    : integer := 30;
    constant GD_320_PLANE_IV_BIT5    : integer := 29;
    constant GD_320_PLANE_IV_BIT4    : integer := 28;
    constant GD_320_PLANE_IV_BIT3    : integer := 27;
    constant GD_320_PLANE_IV_BIT2    : integer := 26;
    constant GD_320_PLANE_IV_BIT1    : integer := 25;
    constant GD_320_PLANE_IV_BIT0    : integer := 24;
    constant GD_640_PLANE_I_BIT7     : integer := 7;
    constant GD_640_PLANE_I_BIT6     : integer := 6;
    constant GD_640_PLANE_I_BIT5     : integer := 5;
    constant GD_640_PLANE_I_BIT4     : integer := 4;
    constant GD_640_PLANE_I_BIT3     : integer := 3;
    constant GD_640_PLANE_I_BIT2     : integer := 2;
    constant GD_640_PLANE_I_BIT1     : integer := 1;
    constant GD_640_PLANE_I_BIT0     : integer := 0;
    constant GD_640_PLANE_III_BIT7   : integer := 15;
    constant GD_640_PLANE_III_BIT6   : integer := 14;
    constant GD_640_PLANE_III_BIT5   : integer := 13;
    constant GD_640_PLANE_III_BIT4   : integer := 12;
    constant GD_640_PLANE_III_BIT3   : integer := 11;
    constant GD_640_PLANE_III_BIT2   : integer := 10;
    constant GD_640_PLANE_III_BIT1   : integer := 9;
    constant GD_640_PLANE_III_BIT0   : integer := 8;

    -- 
    -- Video Timings for different machines and display configuration.
    --
    type VIDEOTIMINGLUT is array (integer range 0 to 9, integer range 0 to 32) of integer range 0 to 2047;

    -- Video mode parameters. Each MZ mode is based on an original or selected (VGA) video timing and within this timing are specific paramters to fit the generated video planes.
    -- This is considered the Video Mode and it is based on the current selected machine compatibility, underlying hardware and option registers.
    --
    type VIDEOMODELUT is array (integer range 0 to 45, integer range 0 to 7) of integer range 0 to 2047;


--  -- Display window variables: -
--  -- Front porch is included in the <X>_SYNC_START parameters. Back porch is included in the <X>_LINE_END, ie. <X>_LINE_END - <X>_SYNC_END = Back Porch.
--  constant FB_TIMING           : VIDEOLUT := (
--  --         0            1          2             3               4            5           6          7          8            9           10         11             12            13            14            15         16           17          18           19         20            21        22             23              24                 25               26         27          28        29     30     31     32     33     34
--  --   H_DSP_START, H_DSP_END, H_DSP_WND_START, H_DSP_WND_END, H_MNU_START, H_MNU_END, H_HDR_START, H_HDR_END, H_FTR_START, H_FTR_END, V_DSP_START, V_DSP_END, V_DSP_WND_START, V_DSP_WND_END, V_MNU_START, V_MNU_END, V_HDR_START, V_HDR_END, V_FTR_START, V_FTR_END, H_LINE_END, V_LINE_END, MAX_COLUMNS,   H_SYNC_START,    H_SYNC_END,     V_SYNC_START,      V_SYNC_END,  H_POLARITY, V_POLARITY, H_CPX, V_CPX, H_GPX, V_GPX, H_OPX, V_OPX      			
--    -- MZ-700 60Hz Display
--    (        0,          320,        0,           320,            32,          288,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,       511,         259,       40,          320  + 43,     320 + 43  + 45,    200 + 19,      200 + 19 + 4,     0,         0,        0,     0,     0,     0,     0,     1),      -- 0  MZ80K/C/1200/A machines have a monochrome 60Hz display with scan of 512 x 260 for a 320x200 viewable area.               
--    (        0,          640,        0,           640,           192,          448,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,      1023,         259,       80,          640  + 106,    640 + 106 + 90,    200 + 19,      200 + 19 + 4,     0,         0,        0,     0,     0,     0,     0,     1),      -- 1  MZ80K/C/1200/A machines with an adapted monochrome 60Hz display with scan of 1024 x 260 for a 640x200 viewable area.			
--    (        0,          320,        0,           320,            32,          288,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,       567,         259,       40,          320  + 80,     320 + 80  + 40,    200 + 19,      200 + 19 + 4,     0,         0,        0,     0,     0,     0,     0,     1),      -- 2  MZ80K/C/1200/A machines with MZ700 style colour @ 60Hz display with scan of 512 x 260 for a 320x200 viewable area.			
--    (        0,          640,        0,           640,           192,          448,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,      1135,         259,       80,          640  + 160,    640 + 160 + 80,    200 + 19,      200 + 19 + 4,     0,         0,        0,     0,     0,     0,     0,     1),      -- 3  MZ80K/C/1200/A machines with MZ700 style colour @ 60Hz display with scan of 1024 x 260 for a 640x200 viewable area.			
--    -- 640 x 480 @ 60Hz
--    (        0,          640,        0,           640,            64,          576,         0,        640,         0,         640,           0,       480,           48,           448,         111,          367,         0,          39,        440,          479,       799,         524,       40,          640  + 16,     640 + 16  + 96,    480 + 8,       480 +  8 + 2,     0,         0,        1,     1,     1,     1,     0,     1),      -- 4  Mode 0 upscaled as 640x480 @ 60Hz timings for 40Char mode monochrome. 			
--    (        0,          640,        0,           640,            64,          576,         0,        640,         0,         640,           0,       480,           48,           448,         111,          367,         0,          39,        440,          479,       799,         524,       80,          640  + 16,     640 + 16  + 96,    480 + 8,       480 +  8 + 2,     0,         0,        0,     1,     1,     1,     0,     1),      -- 5  Mode 1 upscaled as 640x480 @ 60Hz timings for 80Char mode monochrome.
--    (        0,          640,        0,           640,            64,          576,         0,        640,         0,         640,           0,       480,           48,           448,         111,          367,         0,          39,        440,          479,       799,         524,       40,          640  + 16,     640 + 16  + 96,    480 + 11,      480 + 11 + 2,     0,         0,        1,     1,     0,     1,     0,     1),      -- 6  Mode 2 upscaled as 640x480 @ 60Hz timings for 40Char mode colour. 			
--    (        0,          640,        0,           640,            64,          576,         0,        640,         0,         640,           0,       480,           48,           448,         111,          367,         0,          39,        440,          479,       799,         524,       80,          640  + 16,     640 + 16  + 96,    480 + 8,       480 +  8 + 2,     0,         0,        0,     1,     0,     1,     0,     1),      -- 7  Mode 3 upscaled as 640x480 @ 60Hz timings for 80Char mode colour.
--    -- 800 x 600 @ 60Hz
--    (        0,          800,       80,           720,            64,          576,         0,          0,         0,           0,           0,       600,            0,           600,         111,          367,         0,           0,          0,            0,      1055,         627,       40,          800  + 40,    800 + 40  + 128,    600 + 1,       600 +  1 + 4,     1,         1,        1,     2,     0,     0,     0,     1),      -- 8  Mode 0 upscaled as 800x600 @ 60Hz timings for 40Char mode monochrome. 			
--    (        0,          800,       80,           720,            64,          576,         0,          0,         0,           0,           0,       600,            0,           600,         111,          367,         0,           0,          0,            0,      1055,         627,       80,          800  + 40,    800 + 40  + 128,    600 + 1,       600 +  1 + 4,     1,         1,        0,     2,     0,     0,     0,     1),      -- 9  Mode 1 upscaled as 800x600 @ 60Hz timings for 80Char mode monochrome.
--    (        0,          800,       80,           720,            64,          576,         0,          0,         0,           0,           0,       600,            0,           600,         111,          367,         0,           0,          0,            0,      1055,         627,       40,          800  + 40,    800 + 40  + 128,    600 + 1,       600 +  1 + 4,     1,         1,        1,     2,     0,     0,     0,     1),      -- 10 Mode 2 upscaled as 800x600 @ 60Hz timings for 40Char mode colour. 			
--    (        0,          800,       80,           720,            64,          576,         0,          0,         0,           0,           0,       600,            0,           600,         111,          367,         0,           0,          0,            0,      1055,         627,       80,          800  + 40,    800 + 40  + 128,    600 + 1,       600 +  1 + 4,     1,         1,        0,     2,     0,     0,     0,     1),      -- 11 Mode 3 upscaled as 800x600 @ 60Hz timings for 80Char mode colour.
--    -- MZ-700 50Hz Display
--    (        0,          320,        0,           320,            32,          288,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,       511,         259,       40,          320  + 43,     320 + 43  + 45,    200 + 19,      200 + 19 + 4,     0,         0,        0,     0,     0,     0,     0,     1),      -- 12 MZ80K/C/1200/A machines have a monochrome 60Hz display with scan of 512 x 260 for a 320x200 viewable area.               
--    (        0,          640,        0,           640,           192,          448,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,      1023,         259,       80,          640  + 106,    640 + 106 + 90,    200 + 19,      200 + 19 + 4,     0,         0,        0,     0,     0,     0,     0,     1),      -- 13 MZ80K/C/1200/A machines with an adapted monochrome 60Hz display with scan of 1024 x 260 for a 640x200 viewable area.			
--    (        0,          320,        0,           320,            32,          288,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,       567,         311,       40,          320  + 80,     320 + 80  + 40,    200 + 50,      200 + 50 + 3,     0,         0,        0,     0,     0,     0,     0,     1),      -- 14 MZ80K/C/1200/A machines with MZ700 style colour @ 50Hz display with scan of 568 x 312 for a 320x200 viewable area.
--    (        0,          640,        0,           640,           192,          448,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,      1135,         311,       80,          640  + 160,    640 + 160 + 80,    200 + 50,      200 + 50 + 3,     0,         0,        0,     0,     0,     0,     0,     1),      -- 15 MZ80K/C/1200/A machines with MZ700 style colour @ 50Hz display with scan of 1136 x 312 for a 640x200 viewable area.			
--    -- Deprecated: 1024 x 768 @ 60Hz
--  --(        0,         1024,       32,           992,            64,          576,         0,          0,         0,           0,           0,       768,           79,           679,         111,          367,         0,           0,          0,            0,      1343,         805,       40,         1024  + 24,   1024 + 24  + 136,    768 + 3,       768 +  3 + 6,     0,         0,        2,     2,     0,     0,     0,     0),      -- 12 Mode 0 upscaled as 1024x768 @ 60Hz timings for 40Char mode monochrome. 			
--  --(        0,         1024,      192,           832,            64,          576,         0,          0,         0,           0,           0,       768,           79,           679,         111,          367,         0,           0,          0,            0,      1343,         805,       80,         1024  + 24,   1024 + 24  + 136,    768 + 3,       768 +  3 + 6,     0,         0,        0,     2,     0,     0,     0,     0),      -- 13 Mode 1 upscaled as 1024x768 @ 60Hz timings for 80Char mode monochrome.
--  --(        0,         1024,       32,           992,            64,          576,         0,          0,         0,           0,           0,       768,           79,           679,         111,          367,         0,           0,          0,            0,      1343,         805,       40,         1024  + 24,   1024 + 24  + 136,    768 + 3,       768 +  3 + 6,     0,         0,        2,     2,     0,     0,     0,     0),      -- 14 Mode 2 upscaled as 1024x768 @ 60Hz timings for 40Char mode colour. 			
--  --(        0,         1024,      192,           832,            64,          576,         0,          0,         0,           0,           0,       768,           79,           679,         111,          367,         0,           0,          0,            0,      1343,         805,       80,         1024  + 24,   1024 + 24  + 136,    768 + 3,       768 +  3 + 6,     0,         0,        0,     2,     0,     0,     0,     0),      -- 15 Mode 3 upscaled as 1024x768 @ 60Hz timings for 80Char mode colour.
--    -- MZ-2000 40/80 internal/external modes.
--    (        0,          320,        0,           320,            32,          288,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,       511,         259,       40,          320  + 43,     320 + 43  + 45,    200 + 19,      200 + 19 + 4,     0,         0,        0,     0,     0,     0,     0,     0),      -- 16 MZ-2000 Internal monitor 40 column mode.
--    (        0,          640,        0,           640,           192,          448,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,      1023,         259,       80,          640  + 106,    640 + 106 + 90,    200 + 19,      200 + 19 + 4,     0,         0,        0,     0,     0,     0,     0,     0)       -- 17 MZ-2000 Internal monitor 80 column mode.                                                                                   
--  );

    -- Base Video Timing parameters.
    -- These parameters describe a base video mode with the available windows for Display, Header, Footer and OSD Menu. The parameters are referenced by a video mode which maps directly with an MZ series video capability.
    --
    -- Front porch is included in the <X>_SYNC_START parameters. Back porch is included in the <X>_LINE_END, ie. <X>_LINE_END - <X>_SYNC_END = Back Porch.
    --
    --                                 0            1              2                3               4            5           6          7           8            9           10         11             12            13            14            15         16           17          18           19         20            21        22                  23               24                 25               26          27             28           29             30            31          32
    --                                H_DSP_START, H_DSP_END,  H_DSP_WND_START, H_DSP_WND_END, H_MNU_START, H_MNU_END, H_HDR_START, H_HDR_END, H_FTR_START, H_FTR_END, V_DSP_START, V_DSP_END, V_DSP_WND_START, V_DSP_WND_END, V_MNU_START, V_MNU_END, V_HDR_START, V_HDR_END, V_FTR_START, V_FTR_END, H_LINE_END, V_LINE_END,      CLOCK,            H_SYNC_START,    H_SYNC_END,      V_SYNC_START,    V_SYNC_END,   H_BLANK_START, H_BLANK_END, V_BLANK_START, V_BLANK_END,  H_POLARITY, V_POLARITY    			
    constant FB_TIMING           : VIDEOTIMINGLUT := (
      -- MZ-700 60Hz Display
      /* TIMING_MONO40_60HZ */       ( 0,          320,            0,               320,             0,          320,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,       567,         259,    SEL_CLOCK_8_8MHZ,   320  + 80,       320 + 80  + 40,    200 + 19,      200 + 19 + 4,        0,          320,          0,           200,        0,         0),         -- MZ80K/C/1200/A monochrome 60Hz: 568 x 260 at 8.8672 MHz (clk_sys / 8, like the MZ-700; 8 MHz is no whole divider of clk_sys and its uneven pixel enables upset the scandoubler), 15.61 kHz, 60.04 Hz.               
      /* TIMING_MONO80_60HZ */       ( 0,          640,            0,               640,            64,          576,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,      1135,         259,    SEL_CLOCK_17_7MHZ,  640  + 160,      640 + 160 + 80,    200 + 19,      200 + 19 + 4,        0,          640,          0,           200,        0,         0),         -- MZ80K/C/1200/A 80 columns: 1136 x 260 at 17.7344 MHz (clk_sys / 4), 15.61 kHz, 60.04 Hz.			
      /* TIMING_COLOUR40_60HZ */     ( 0,          320,            0,               320,             0,          320,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,       567,         259,    SEL_CLOCK_8_8MHZ,   320  + 80,       320 + 80  + 40,    200 + 19,      200 + 19 + 4,        0,          320,          0,           200,        0,         0),         -- MZ80K/C/1200/A machines with MZ700 style colour @ 60Hz display with scan of 512 x 260 for a 320x200 viewable area.			
      /* TIMING_COLOUR80_60HZ */     ( 0,          640,            0,               640,            64,          576,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,      1135,         259,    SEL_CLOCK_17_7MHZ,  640  + 160,      640 + 160 + 80,    200 + 19,      200 + 19 + 4,        0,          640,          0,           200,        0,         0),         -- MZ80K/C/1200/A machines with MZ700 style colour @ 60Hz display with scan of 1024 x 260 for a 640x200 viewable area.			

      -- 640 x 480 @ 60Hz
      /* TIMING_VGA640X480_60HZ */   ( 0,          640,            0,               640,            64,          576,         0,        640,         0,         640,           0,       480,           48,           448,         112,          368,         0,          39,        440,          479,       799,         524,    SEL_CLOCK_25MHZ,    640  + 10,       640 + 10  + 96,    480 + 8,       480 +  8 + 2,        1,          640,          0,           480,        0,         0),         -- Mode 0 upscaled as 640x480 @ 60Hz timings for 40Char mode monochrome. 			

      -- 800 x 600 @ 60Hz
      /* TIMING_VGA800X600_60HZ */   ( 0,          800,           80,               720,           144,          656,         0,         80,       720,         800,           0,       600,            0,           600,         112,          368,         0,         600,          0,          600,      1055,         627,    SEL_CLOCK_40MHZ,    800  + 40,      800 + 40  + 128,    600 + 1,       600 +  1 + 4,        0,          800,          0,           600,        1,         1),         -- Mode 0 upscaled as 800x600 @ 60Hz timings for 40Char mode monochrome. 			

      -- MZ-700 50Hz Display
      /* TIMING_COLOUR40_50HZ */     ( 0,          320,            0,               320,             0,          320,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,       567,         311,    SEL_CLOCK_8_8MHZ,   320  + 80,       320 + 80  + 40,    200 + 50,      200 + 50 + 3,        0,          320,          0,           200,        0,         0),         -- MZ-700/800 PAL colour @ 50Hz: scan of 568 x 312.
      /* TIMING_COLOUR80_50HZ */     ( 0,          640,            0,               640,            64,          576,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,      1135,         311,    SEL_CLOCK_17_7MHZ,  640  + 160,      640 + 160 + 80,    200 + 50,      200 + 50 + 3,        0,          640,          0,           200,        0,         0),         -- MZ-700/800 PAL colour @ 50Hz: scan of 1136 x 312.

      -- Deprecated: 1024 x 768 @ 60Hz
    --/* TIMING_VGA1024X768_60HZ */  ( 0,         1024,           32,               992,            64,          576,         0,          0,         0,           0,           0,       768,           79,           679,         111,          367,         0,           0,          0,            0,      1343,         805,    SEL_CLOCK_8MHZ,     1024  + 24,     1024 + 24  + 136,    768 + 3,       768 +  3 + 6,       0,          640,          0,           200,         0,         0),        -- Mode 0 upscaled as 1024x768 @ 60Hz timings for 40Char mode monochrome. 			

      -- MZ-80A/MZ-2000 40/80 internal/external modes.
      /* TIMING_INT40_60HZ */        ( 0,          320,            0,               320,             0,          320,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,       567,         259,    SEL_CLOCK_8_8MHZ,   320  + 80,       320 + 80  + 40,    200 + 19,      200 + 19 + 4,        0,          320,          0,           200,        0,         0),         -- MZ-80A Internal monitor 40 column mode.
      /* TIMING_INT80_60HZ */        ( 0,          640,            0,               640,            64,          576,         0,          0,         0,           0,           0,       200,            0,           200,          36,          164,         0,           0,          0,            0,      1135,         259,    SEL_CLOCK_17_7MHZ,  640  + 160,      640 + 160 + 80,    200 + 19,      200 + 19 + 4,        0,          640,          0,           200,        0,         0)          -- MZ-80A Internal monitor 80 column mode.                                                                                   
    );

    -- Video mode LUT. Links a timing with specific parameters for a given video mode.
    --
    --         0                      1           2      3      4      5      6      7
    --      VIDEOTIMING,              MAX_COLUMN, H_CPX, V_CPX, H_GPX, V_GPX, H_OPX, V_OPX        -- Mode | Description
    constant FB_VIDEOMODE        : VIDEOMODELUT := (
      (  TIMING_MONO40_60HZ,          40,         0,     0,     0,     0,     0,     0       ),   -- 0    | MZ80K/C/1200/A machines have a monochrome 60Hz display with scan of 512 x 260 for a 320x200 viewable area.               
      (  TIMING_MONO80_60HZ,          80,         0,     0,     0,     0,     0,     0       ),   -- 1    | MZ80K/C/1200/A machines with an adapted monochrome 60Hz display with scan of 1024 x 260 for a 640x200 viewable area.		
      (  TIMING_COLOUR40_60HZ,        40,         0,     0,     0,     0,     0,     0       ),   -- 2    | MZ80A/MZ700 machines with colour @ 60Hz display with scan of 512 x 260 for a 320x200 viewable area.			
      (  TIMING_COLOUR80_60HZ,        80,         0,     0,     0,     0,     0,     0       ),   -- 3    | MZ80A/MZ700 machines with colour @ 60Hz display with scan of 1024 x 260 for a 640x200 viewable area.			
                                      
      (  TIMING_VGA640X480_60HZ,      40,         1,     1,     0,     1,     0,     1       ),   -- 4    | Mode 0 upscaled as 640x480 @ 60Hz timings for 40Char mode monochrome. 			
      (  TIMING_VGA640X480_60HZ,      80,         0,     1,     0,     1,     0,     1       ),   -- 5    | Mode 1 upscaled as 640x480 @ 60Hz timings for 80Char mode monochrome.
      (  TIMING_VGA640X480_60HZ,      40,         1,     1,     0,     1,     0,     1       ),   -- 6    | Mode 2 upscaled as 640x480 @ 60Hz timings for 40Char mode colour. 			
      (  TIMING_VGA640X480_60HZ,      80,         0,     1,     0,     1,     0,     1       ),   -- 7    | Mode 3 upscaled as 640x480 @ 60Hz timings for 80Char mode colour.
                                      
      (  TIMING_VGA800X600_60HZ,      40,         1,     2,     0,     1,     0,     1       ),   -- 8    | Mode 0 upscaled as 800x600 @ 60Hz timings for 40Char mode monochrome. 			
      (  TIMING_VGA800X600_60HZ,      80,         0,     2,     0,     1,     0,     1       ),   -- 9    | Mode 1 upscaled as 800x600 @ 60Hz timings for 80Char mode monochrome.
      (  TIMING_VGA800X600_60HZ,      40,         1,     2,     0,     1,     0,     1       ),   -- 10   | Mode 2 upscaled as 800x600 @ 60Hz timings for 40Char mode colour. 			
      (  TIMING_VGA800X600_60HZ,      80,         0,     2,     0,     1,     0,     1       ),   -- 11   | Mode 3 upscaled as 800x600 @ 60Hz timings for 80Char mode colour.
                                      
      (  TIMING_MONO40_60HZ,          40,         0,     0,     0,     0,     0,     0       ),   -- 12   | MZ80K/C/1200/A machines have a monochrome 60Hz display with scan of 512 x 260 for a 320x200 viewable area.               
      (  TIMING_MONO80_60HZ,          80,         0,     0,     0,     0,     0,     0       ),   -- 13   | MZ80K/C/1200/A machines with an adapted monochrome 60Hz display with scan of 1024 x 260 for a 640x200 viewable area.		
      (  TIMING_COLOUR40_50HZ,        40,         0,     0,     0,     0,     0,     0       ),   -- 14   | MZ80A/MZ700 machines with colour @ 50Hz display with scan of 568 x 312 for a 320x200 viewable area.
      (  TIMING_COLOUR80_50HZ,        80,         0,     0,     0,     0,     0,     0       ),   -- 15   | MZ80A/MZ700 machines with colour @ 50Hz display with scan of 1136 x 312 for a 640x200 viewable area.			
                                      
  --  (  TIMING_VGA1024X768_60HZ,     40,         2,     2,     0,     0,     0,     0       ),   -- 12   | Mode 0 upscaled as 1024x768 @ 60Hz timings for 40Char mode monochrome. 			
  --  (  TIMING_VGA1024X768_60HZ,     80,         0,     2,     0,     0,     0,     0       ),   -- 13   | Mode 1 upscaled as 1024x768 @ 60Hz timings for 80Char mode monochrome.
  --  (  TIMING_VGA1024X768_60HZ,     40,         2,     2,     0,     0,     0,     0       ),   -- 14   | Mode 2 upscaled as 1024x768 @ 60Hz timings for 40Char mode colour. 			
  --  (  TIMING_VGA1024X768_60HZ,     80,         0,     2,     0,     0,     0,     0       ),   -- 15   | Mode 3 upscaled as 1024x768 @ 60Hz timings for 80Char mode colour.
                                      
      -- MZ-2000/MZ-2200 modes.
      (  TIMING_INT80_60HZ,           40,         1,     0,     0,     0,     0,     0       ),   -- 16   | MZ-2000 Internal monitor 40 column mode. Using the 80 column timing to allow greater number of pixels for the OSD.
      (  TIMING_INT80_60HZ,           80,         0,     0,     0,     0,     0,     0       ),   -- 17   | MZ-2000 Internal monitor 80 column mode.                                                                                   
      (  TIMING_MONO80_60HZ,          40,         1,     0,     0,     0,     0,     0       ),   -- 18   | MZ-2000 40 column mode, 60Hz standard timing.
      (  TIMING_MONO80_60HZ,          80,         0,     0,     0,     0,     0,     0       ),   -- 19   | MZ-2000 80 column mode, 60Hz standard timing.
      (  TIMING_VGA640X480_60HZ,      40,         1,     1,     0,     1,     0,     1       ),   -- 20   | MZ-2000 40 column mode, 60Hz VGA 640x480 timing.
      (  TIMING_VGA640X480_60HZ,      80,         0,     1,     0,     1,     0,     1       ),   -- 21   | MZ-2000 80 column mode, 60Hz VGA 640x480 timing.
      (  TIMING_VGA800X600_60HZ,      40,         1,     2,     0,     2,     0,     1       ),   -- 22   | MZ-2000 40 column mode, 60Hz VGA 800x600 timing.
      (  TIMING_VGA800X600_60HZ,      80,         0,     2,     0,     2,     0,     1       ),   -- 23   | MZ-2000 80 column mode, 60Hz VGA 800x600 timing.

      -- MZ-80B modes.
      (  TIMING_MONO40_60HZ,          40,         0,     0,     0,     0,     0,     0       ),   -- 24   | MZ-80B 40 column mode, 60Hz standard timing.
      (  TIMING_MONO80_60HZ,          80,         0,     0,     0,     0,     0,     0       ),   -- 25   | MZ-80B 80 column mode, 60Hz standard timing.
      (  TIMING_VGA640X480_60HZ,      40,         1,     1,     1,     1,     0,     1       ),   -- 26   | MZ-80B 80 column mode, 60Hz VGA 640x480 timing.
      (  TIMING_VGA640X480_60HZ,      80,         0,     1,     1,     1,     0,     1       ),   -- 27   | MZ-80B 80 column mode, 60Hz VGA 640x480 timing.
      (  TIMING_VGA800X600_60HZ,      40,         1,     2,     1,     2,     0,     1       ),   -- 28   | MZ-80B 80 column mode, 60Hz VGA 800x600 timing.
      (  TIMING_VGA800X600_60HZ,      80,         0,     2,     1,     2,     0,     1       ),   -- 29   | MZ-80B 80 column mode, 60Hz VGA 800x600 timing.

      -- MZ800 modes.
      (  TIMING_COLOUR40_60HZ,        40,         0,     0,     0,     0,     0,     0       ),   -- 30   | MZ-800 40 column mode, 60Hz standard setting.
      (  TIMING_COLOUR80_60HZ,        80,         0,     0,     0,     0,     0,     0       ),   -- 31   | MZ-800 80 column mode, 60Hz standard setting
      (  TIMING_COLOUR40_50HZ,        40,         0,     0,     0,     0,     0,     0       ),   -- 32   | MZ-800 40 column mode, 50Hz standard timing.
      (  TIMING_COLOUR80_50HZ,        80,         0,     0,     0,     0,     0,     0       ),   -- 33   | MZ-800 80 column mode, 50Hz standard timing.
      (  TIMING_VGA640X480_60HZ,      40,         1,     1,     1,     1,     0,     1       ),   -- 34   | MZ-800 40 column mode, 60Hz VGA 640x480 timing.
      (  TIMING_VGA640X480_60HZ,      80,         0,     1,     0,     1,     0,     1       ),   -- 35   | MZ-800 80 column mode, 60Hz VGA 640x480 timing.
      (  TIMING_VGA800X600_60HZ,      40,         1,     2,     1,     2,     0,     1       ),   -- 36   | MZ-800 40 column mode, 60Hz VGA 800x600 timing.
      (  TIMING_VGA800X600_60HZ,      80,         0,     2,     0,     2,     0,     1       ),   -- 37   | MZ-800 80 column mode, 60Hz VGA 800x600 timing.

      -- MZ-80A modes.
      (  TIMING_INT80_60HZ,           40,         1,     0,     0,     0,     0,     0       ),   -- 38   | MZ-80A Internal monitor 40 column mode. Using the 80 column timing to allow greater number of pixels for the OSD.
      (  TIMING_INT80_60HZ,           80,         0,     0,     0,     0,     0,     0       ),   -- 39   | MZ-80A Internal monitor 80 column mode.                                                                                   
      (  TIMING_MONO80_60HZ,          40,         1,     0,     0,     0,     0,     0       ),   -- 40   | MZ-80A 40 column mode, 60Hz standard timing.
      (  TIMING_MONO80_60HZ,          80,         0,     0,     0,     0,     0,     0       ),   -- 41   | MZ-80A 80 column mode, 60Hz standard timing.
      (  TIMING_VGA640X480_60HZ,      40,         1,     1,     0,     1,     0,     1       ),   -- 42   | MZ-80A 40 column mode, 60Hz VGA 640x480 timing.
      (  TIMING_VGA640X480_60HZ,      80,         0,     1,     0,     1,     0,     1       ),   -- 43   | MZ-80A 80 column mode, 60Hz VGA 640x480 timing.
      (  TIMING_VGA800X600_60HZ,      40,         1,     2,     0,     2,     0,     1       ),   -- 44   | MZ-80A 40 column mode, 60Hz VGA 800x600 timing.
      (  TIMING_VGA800X600_60HZ,      80,         0,     2,     0,     2,     0,     1       )    -- 45   | MZ-80A 80 column mode, 60Hz VGA 800x600 timing.

    );

    -- State machine states for the Graphics Processing Unit.
    --
    type GPUStateType is 
    (
        GPU_State_Idle,
        GPU_FB_Clear,
        GPU_FB_Clear_Param,
        GPU_FB_Clear_Start,
        GPU_FB_Clear_1,
        GPU_FB_Clear_2,
        GPU_FB_Clear_3,
        GPU_VRAM_Clear,
        GPU_VRAM_Clear_Attr,
        GPU_VRAM_Clear_Param,
        GPU_VRAM_Clear_Start,
        GPU_VRAM_Clear_1,
        GPU_VRAM_Clear_2,
        GPU_VRAM_Clear_3
    );
    --
    -- Registers
    --
    signal VIDEOMODE             :     integer;                              -- Active video mode, used to index the VIDEOLUT array to select required parameters.
    signal VIDEOMODE_NEXT        :     integer;                              -- Next video mode set when video mode is being changed.
    signal VIDEOMODE_SWITCH      :     std_logic;                            -- Video mode change detected, waiting for current display to complete before change.
    signal VIDEOMODE_RESET_TIMER :     unsigned(7 downto 0);                 -- Video mode changed timer, when not 0 the mode is being changed.
    signal MENUENABLE_LAST       :     std_logic;                            -- Detect change of menu buffer status.
    signal STATUSENABLE_LAST     :     std_logic;                            -- Detect change of status buffer status.
    signal VIDCLK_8MHZ           :     std_logic;                            -- 2x 8MHz base clock for video timing and gate clocking.
    signal VIDCLK_16MHZ          :     std_logic;                            -- 2x 16MHz base clock for video timing and gate clocking.
  --signal VIDCLK_65MHZ          :     std_logic;                            -- 2x 65MHz base clock for video timing and gate clocking.
    signal VIDCLK_25_175MHZ      :     std_logic;                            -- 2x 25.175MHz base clock for video timing and gate clocking.
    signal VIDCLK_40MHZ          :     std_logic;                            -- 2x 40MHz base clock for video timing and gate clocking.
    signal VIDCLK_8_86719MHZ     :     std_logic;                            -- 2x original MZ700 video clock.
    signal VIDCLK_17_7344MHZ     :     std_logic;                            -- 2x original MZ700 colour modulator clock.
    signal VIDCLK_8MHZ_Q         :     std_logic;                            -- D-Type flip flop Q output used to enable a clock, active state is '0'.
    signal VIDCLK_16MHZ_Q        :     std_logic;
    signal VIDCLK_8_86719MHZ_Q   :     std_logic;
    signal VIDCLK_17_7344MHZ_Q   :     std_logic;
    signal VIDCLK_25_175MHZ_Q    :     std_logic;
    signal VIDCLK_40MHZ_Q        :     std_logic;
    signal CLOCKSEL              :     integer range 0 to 5;                 -- Clock for selected video timing parameters.
  --signal VIDCLK_65MHZ_Q        :     std_logic;
    signal VIDCLK_DIV            :     std_logic;                            -- Video clock divisor, video clock runs at 2x frequency of display.
    signal PLL_LOCKED1           :     std_logic;
    signal PLL_LOCKED2           :     std_logic;
  --signal PLL_LOCKED3           :     std_logic;
    signal MAX_COLUMN            :     unsigned(7 downto 0);
    signal FB_GFX_ADDR           :     std_logic_vector(13 downto 0);        -- Graphics Frame buffer actual address
    signal FB_GFX_MUXADDR        :     std_logic_vector(14 downto 0);        -- Graphics Frame buffer multiplexed address
    signal FB_GFX_LOADDR         :     std_logic_vector(1 downto 0);         -- In MZ800 mode a 32bit word needs to be read, 8 bits at a time, this address component performs byte addressing.
    signal OFFSET_ADDR           :     std_logic_vector(7 downto 0);         -- Display Offset - for MZ1200/80A machines with 2K VRAM
    signal SR_G_CHR              :     std_logic_vector(7 downto 0);         -- Shift Register to serialise character Green pixels.
    signal SR_R_CHR              :     std_logic_vector(7 downto 0);         -- Shift Register to serialise character Red pixels.
    signal SR_B_CHR              :     std_logic_vector(7 downto 0);         -- Shift Register to serialise character Blue pixels.
    signal SR_G_GFX              :     std_logic_vector(7 downto 0);         -- Shift Register to serialise graphics Green pixels.
    signal SR_R_GFX              :     std_logic_vector(7 downto 0);         -- Shift Register to serialise graphics Red pixels.
    signal SR_B_GFX              :     std_logic_vector(7 downto 0);         -- Shift Register to serialise graphics Blue pixels.
    signal SR_I_GFX              :     std_logic_vector(7 downto 0);         -- Shift Register to serialise graphics Intensity pixels.
    signal SR_G_OSD              :     std_logic_vector(7 downto 0);         -- Shift Register to serialise Menu/Status pixels.
    signal SR_R_OSD              :     std_logic_vector(7 downto 0);         -- Shift Register to serialise Menu/Status pixels.
    signal SR_B_OSD              :     std_logic_vector(7 downto 0);         -- Shift Register to serialise Menu/Status pixels.
    signal SR_G_MUX              :     std_logic;                            -- Multipled display bit from the 3 planes, character, graphic and OSD.
    signal SR_R_MUX              :     std_logic;                            -- Multipled display bit from the 3 planes, character, graphic and OSD.
    signal SR_B_MUX              :     std_logic;                            -- Multipled display bit from the 3 planes, character, graphic and OSD.
    signal SR_PLANE_I            :     std_logic;                            -- Output signal for the MZ800 Graphics Display Generator.
    signal SR_PLANE_II           :     std_logic;                            -- Output signal for the MZ800 Graphics Display Generator.
    signal SR_PLANE_III          :     std_logic;                            -- Output signal for the MZ800 Graphics Display Generator.
    signal SR_PLANE_IV           :     std_logic;                            -- Output signal for the MZ800 Graphics Display Generator.
    signal PALETTE_R_MUX         :     std_logic_vector(8 downto 0);         -- Multiplexed Palette register to apply mapping to the digital RGB output according to mode.
    signal PALETTE_G_MUX         :     std_logic_vector(8 downto 0);         -- 
    signal PALETTE_B_MUX         :     std_logic_vector(8 downto 0);         -- 
    signal FB_OSD_ADDR           :     std_logic_vector(12 downto 0);        -- OSD Menu/Status display frame buffer actual address
    signal FB_OSD_DATA           :     std_logic_vector(23 downto 0);
    signal FB_CHR_DATA           :     std_logic_vector(23 downto 0);        --
    signal FB_GFX_DATA           :     std_logic_vector(31 downto 0);        --
    signal FB_RED_BG             :     std_logic_vector(7 downto 0);         -- MZ-2000 graphics background colour.
    signal FB_GREEN_BG           :     std_logic_vector(7 downto 0);         --
    signal FB_BLUE_BG            :     std_logic_vector(7 downto 0);         --
    signal FB_RED_PRIO           :     std_logic_vector(7 downto 0);         -- MZ-2000 character/graphics priority.
    signal FB_GREEN_PRIO         :     std_logic_vector(7 downto 0);         --
    signal FB_BLUE_PRIO          :     std_logic_vector(7 downto 0);         --
    signal FB_RED_PIXEL          :     std_logic_vector(7 downto 0);         -- MZ-2000 active pixel select.
    signal FB_GREEN_PIXEL        :     std_logic_vector(7 downto 0);         --
    signal FB_BLUE_PIXEL         :     std_logic_vector(7 downto 0);         --
    signal RENDR_SUB_ADDR        :     std_logic_vector(2 downto 0);
    signal RENDR_VRAM_DATA       :     std_logic_vector(15 downto 0);
    signal RENDR_GRAM_DATA       :     std_logic_vector(23 downto 0);
    signal RENDR_VRAM_ADDR       :     std_logic_vector(10 downto 0);
    signal RENDR_VRAM_BADDR      :     std_logic_vector(10 downto 0);         -- VRAM read address: the character, or its MZ-1500 PCG word (+400h).
    signal RENDR_PCG_PHASE       :     std_logic := '0';
    signal RENDR_CHR_WORD        :     std_logic_vector(15 downto 0);         -- Character and attribute of the cell being rendered.
    signal RENDR_PCG_CELL        :     std_logic := '0';                      -- MZ-1500: PCG enabled on this cell (PCG high byte bit 3).
    signal RENDR_CGROM_ADDR      :     std_logic_vector(11 downto 0);
    signal RENDR_CHR_NEXT        :     std_logic;                            -- Render next 8 bit character segment for display.
    signal RENDR_GFX_NEXT        :     std_logic;                            -- Render next 8 bit graphics segment for display.
    signal CGROM_DATA            :     std_logic_vector(7 downto 0);         -- Font Data To Display
    signal DISPLAY_INVERT        :     std_logic;                            -- Invert display Mode of MZ80A/1200
    signal H_CHR_SHIFT_CNT       :     integer range 0 to 7;
    signal H_GFX_SHIFT_CNT       :     integer range 0 to 7;
    signal H_OSD_SHIFT_CNT       :     integer range 0 to 7;

    signal H_CPX                 :     unsigned(7 downto 0);                 -- Variable to indicate if horizontal pixels in characters should be multiplied (for conversion to alternate formats).
    signal H_CPX_CNT             :     integer range 0 to 3;           
    signal V_CPX                 :     unsigned(7 downto 0);                 -- Variable to indicate if vertical pixels in characters should be multiplied (for conversion to alternate formats).

    signal H_GPX                 :     unsigned(7 downto 0);                 -- Variable to indicate if horizontal pixels in pixel graphics should be multiplied (for conversion to alternate formats).
    signal H_GPX_CNT             :     integer range 0 to 3;           
    signal V_GPX                 :     unsigned(7 downto 0);                 -- Variable to indicate if vertical pixels in pixel graphics should be multiplied (for conversion to alternate formats).
    signal V_GPX_CNT             :     integer range 0 to 3;                 -- Variable to indicate if vertical pixels in pixel graphics should be multiplied (for conversion to alternate formats).

    signal H_OPX                 :     unsigned(7 downto 0);                 -- Variable to indicate if horizontal pixels in OSD pixel graphics should be multiplied (for conversion to alternate formats).
    signal H_OPX_CNT             :     integer range 0 to 3;           
    signal V_OPX                 :     unsigned(7 downto 0);                 -- Variable to indicate if vertical pixels in OSD pixel graphics should be multiplied (for conversion to alternate formats).
    signal V_OPX_CNT             :     integer range 0 to 3;                 -- Variable to indicate if vertical pixels in OSD pixel graphics should be multiplied (for conversion to alternate formats).

    signal VPARAM_DO             :     std_logic_vector(7 downto 0);         -- Video Parameter register read signal.
    signal PCG_RAM_SEL           :     std_logic := '0';                     -- PCG RAM select, allow access to the programmable character generator memory.
    signal MODE_VIDEO_BASE       :     integer range 0 to 15;                -- Base video mode the Video Module is running in, ie. MZ-800. The Video Controller could temporarily be running as an MZ-700 whilst in base mode of MZ-800.
    signal MODE_VIDEO_MZ80K      :     std_logic := '0';                     -- The Video Module is running in MZ80K mode.
    signal MODE_VIDEO_MZ80C      :     std_logic := '0';                     -- The Video Module is running in MZ80C mode.
    signal MODE_VIDEO_MZ1200     :     std_logic := '0';                     -- The Video Module is running in MZ1200 mode.
    signal MODE_VIDEO_MZ80A      :     std_logic := '0';                     -- The Video Module is running in MZ80A mode.
    signal MODE_VIDEO_MZ700      :     std_logic := '1';                     -- The Video Module is running in MZ700 mode.
    signal MODE_VIDEO_MZ1500     :     std_logic := '0';                     -- The Video Module is running in MZ1500 mode.
    signal MODE_VIDEO_MZ800      :     std_logic := '0';                     -- The Video Module is running in MZ800 mode.
    signal MODE_VIDEO_MZ80B      :     std_logic := '0';                     -- The Video Module is running in MZ80B mode.
    signal MODE_VIDEO_MZ2000     :     std_logic := '0';                     -- The Video Module is running in MZ2000 mode.
    signal MODE_VIDEO_MZ2200     :     std_logic := '0';                     -- The Video Module is running in MZ2200 mode.
    signal MODE_VIDEO_MZ2500     :     std_logic := '0';                     -- The Video Module is running in MZ2500 mode.
    signal MODE_VIDEO_MONO       :     std_logic := '0';                     -- The Video Module is running in monochrome 40 character mode.
    signal MODE_VIDEO_MONO80     :     std_logic := '0';                     -- The Video Module is running in monochrome 80 character mode.
    signal MODE_VIDEO_COLOUR     :     std_logic := '1';                     -- The Video Module is running in colour 40 character mode.
    signal MODE_VIDEO_COLOUR80   :     std_logic := '0';                     -- The Video Module is running in colour 80 character mode.
    signal HOST_HW_MZ80A         :     std_logic := '0';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ80A hardware or emulated hardware.
    signal HOST_HW_MZ700         :     std_logic := '1';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ700 hardware or emulated hardware.
    signal HOST_HW_MZ800         :     std_logic := '0';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ800 hardware or emulated hardware.
    signal HOST_HW_MZ80B         :     std_logic := '0';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ80B hardware or emulated hardware.
    signal HOST_HW_MZ80K         :     std_logic := '0';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ80K hardware or emulated hardware.
    signal HOST_HW_MZ80C         :     std_logic := '0';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ80C hardware or emulated hardware.
    signal HOST_HW_MZ1200        :     std_logic := '0';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ1200 hardware or emulated hardware.
    signal HOST_HW_MZ2000        :     std_logic := '0';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ2000 hardware or emulated hardware.
    signal HOST_HW_MZ1500        :     std_logic := '0';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ1500 hardware or emulated hardware.
    signal HOST_HW_MZ2200        :     std_logic := '0';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ2200 hardware or emulated hardware.
    signal HOST_HW_MZ2500        :     std_logic := '0';                     -- Machine configuration (memory map, I/O etc) set in the CPLD. When this flag is set, it is running under MZ2500 hardware or emulated hardware.
    signal MODE_HOST             :     std_logic := '0';                     -- Machine configuration is such that the underlying controlling hardware is the host machine.
    signal MODE_IOP              :     std_logic := '0';                     -- Machine configuration is such that the underlying controlling hardware is the I/O Processor.
    signal MODE_EMUMZ            :     std_logic := '0';                     -- Machine configuration is such that the underlying hardware is the FPGA based MZ emulator.
    signal PALETTE_PARAM_SEL     :     std_logic_vector(8 downto 0);         -- Palette parameter selection register.
    signal PALETTE_DO_R          :     std_logic_vector(4 downto 0);         -- Read Red palette output.
    signal PALETTE_DO_G          :     std_logic_vector(4 downto 0);         -- Read Green palette output.
    signal PALETTE_DO_B          :     std_logic_vector(4 downto 0);         -- Read Blue palette output.
    signal PALETTE_WEN_R         :     std_logic;                            -- Write enable for Red palette map.
    signal PALETTE_WEN_G         :     std_logic;                            -- Write enable for Green palette map.
    signal PALETTE_WEN_B         :     std_logic;                            -- Write enable for Blue palette map.
    signal FB_PALETTE_R          :     std_logic_vector(4 downto 0);         -- Current palette map value for given video state input.
    signal FB_PALETTE_G          :     std_logic_vector(4 downto 0);         -- Current palette map value for given video state input.
    signal FB_PALETTE_B          :     std_logic_vector(4 downto 0);         -- Current palette map value for given video state input.
    signal CONFIG_LAST           :     std_logic_vector(CONFIG_WIDTH);       -- Configuration string change detection, used by the Sharp MZ Series Emulator to configure video settings rather than register writes.

    signal VIDEO_ADDRi           :     std_logic_vector(23 downto 0);        -- CPU Address bus. Upper byte is for direct addressing (ie /= 0) and used by external systems or a soft CPU.
    signal VIDEO_DATA_INi        :     std_logic_vector(31 downto 0);        -- Data bus into video module.
    signal VIDEO_DATA_OUTi       :     std_logic_vector(31 downto 0);        -- Data bus out from video module to CPU.
    signal VIDEO_MREQni          :     std_logic;                            -- MREQ signal, active low.
    signal VIDEO_IORQni          :     std_logic;                            -- IORQ signal, active low.
    signal VIDEO_RDni            :     std_logic;                            -- Video RDn from the CPLD, decoded via memory manager.
    signal VIDEO_WRni            :     std_logic;                            -- Video WRn from the CPLD, decoded via memory manager.
    signal VIDEO_WR_BYTEi        :     std_logic;                            -- Signal to indicate a byte should be written not a 32bit word.
    signal VIDEO_WR_HWORDi       :     std_logic;                            -- Signal to indicate a 16bit half word should be written not a 32bit word.

    --
    -- Options
    --
    signal GRAMI_ENABLED         :     std_logic;                            -- Signal to indicate Graphics RAM I   is available and enabled.
    signal GRAMII_ENABLED        :     std_logic;                            -- Signal to indicate Graphics RAM II  is available and enabled.
    signal GRAMIII_ENABLED       :     std_logic;                            -- Signal to indicate Graphics RAM III is available and enabled.
    signal PCG_ENABLED           :     std_logic;                            -- Signal to indicate if the PCG is available and enabled.

    --
    -- CPU/Video Access
    --
    signal VRAM_VIDEO_DATA       :     std_logic_vector(31 downto 0);        -- Display data output to CPU.
    signal VRAM_WEN              :     std_logic;                            -- VRAM Write enable signal.
    signal VRAM_WEN_BYTE         :     std_logic;                            -- VRAM Write byte enable signal.
    signal VRAM_WEN_HWORD        :     std_logic;                            -- VRAM Write 16bit half word enable signal.
    signal VRAM_GPU_WEN          :     std_logic;                            -- VRAM Write enable signal from the GPU.
    signal VRAM_GPU_ADDR         :     std_logic_vector(12 downto 0);        -- VRAM RAM Address from the GPU.
    signal VRAM_ADDR             :     std_logic_vector(11 downto 0);        -- VRAM RAM Address.
    signal VRAM_GPU_ENABLE       :     std_logic;                            -- Enable GPU VRAM access.
    signal VRAM_DI               :     std_logic_vector(31 downto 0);        -- VRAM Data input.
    signal VRAM_GPU_DI           :     std_logic_vector(7 downto 0);         -- VRAM Data input from the GPU.
    signal GRAM_ADDR             :     std_logic_vector(13 downto 0);        -- Graphics RAM Address.
    signal GRAM_GPU_ADDR         :     std_logic_vector(13 downto 0);        -- Graphics RAM Address.
    signal GRAM_DI_R_GI          :     std_logic_vector(31 downto 0);        -- Graphics Red RAM Data or Graphics RAM I for MZ80B.
    signal GRAM_DI_B_GII         :     std_logic_vector(31 downto 0);        -- Graphics Green RAM Data or Graphics RAM II for MZ80B
    signal GRAM_DI_G_GIII        :     std_logic_vector(31 downto 0);        -- Graphics Blue RAM Data.
    signal GRAM_GPU_DI_R         :     std_logic_vector(7 downto 0);         -- Graphics Red RAM Data generated by GPU.
    signal GRAM_GPU_DI_B         :     std_logic_vector(7 downto 0);         -- Graphics Blue RAM Data generated by GPU.
    signal GRAM_GPU_DI_G         :     std_logic_vector(7 downto 0);         -- Graphics Green RAM Data generated by GPU.
    signal GRAM_DO_R_GI          :     std_logic_vector(31 downto 0);        -- Graphics Option GRAM I Data out for MZ80B, Red for other modes.
    signal GRAM_DO_B_GII         :     std_logic_vector(31 downto 0);        -- Graphics Option GRAM II Data out for MZ80B, Blue for other modes.
    signal GRAM_DO_G_GIII        :     std_logic_vector(31 downto 0);        -- Graphics Option GRAM III Data out RGB mode, Green for other modes..
    signal GRAM_WEN_R_GI         :     std_logic;                            -- Graphics Option GRAM I Write enable signal for MZ80B, Red for other modes.
    signal GRAM_WEN_B_GII        :     std_logic;                            -- Graphics Option GRAM II Write enable signal for MZ80B, Blue for other modes.
    signal GRAM_WEN_G_GIII       :     std_logic;                            -- Graphics Option GRAM III Write enable signal RGB mode, Green for other modes.
    signal GRAM_WEN_BYTE         :     std_logic;                            -- Graphics GRAM Write byte enable signal.
    signal GRAM_WEN_HWORD        :     std_logic;                            -- Graphics GRAM Write 16bit half word enable signal.
    signal GRAM_GPU_ENABLE       :     std_logic;                            -- Enable GPU GRAM access.
    signal GWEN_GPU_R            :     std_logic;                            -- Write enable to Red GRAM by GPU.
    signal GWEN_GPU_G            :     std_logic;                            -- Write enable to Green GRAM by GPU.
    signal GWEN_GPU_B            :     std_logic;                            -- Write enable to Blue GRAM by GPU.
    signal GRAM_MODE_REG         :     std_logic_vector(7 downto 0);         -- Programmable mode register to control GRAM operations.
    signal GRAM_R_FILTER         :     std_logic_vector(7 downto 0);         -- Red pixel writer filter.
    signal GRAM_G_FILTER         :     std_logic_vector(7 downto 0);         -- Green pixel writer filter.
    signal GRAM_B_FILTER         :     std_logic_vector(7 downto 0);         -- Blue pixel writer filter.
    signal GRAM_OPT_PAGE         :     std_logic;                            -- Graphics read/write to GRAMI (0) or GRAMII (1) for MZ80B
    signal GRAM_OPT_OUT1         :     std_logic;                            -- Graphics enable GRAMI output to display
    signal GRAM_OPT_OUT2         :     std_logic;                            -- Graphics enable GRAMII output to display
    signal FBRAM_PAGE_ENABLE     :     std_logic;                            -- Custom frame buffer graphics mode page enable.
    signal VIDEO_MODE_REG        :     std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(MODE_MZ700, 8)); -- Programmable mode register to control video mode.
    signal PAGE_MODE_REG         :     std_logic_vector(7 downto 0);         -- Current value of the Page register.
    signal VGA_ATTR_REG          :     std_logic_vector(7 downto 0);         -- VGA Border and attribute register to apply VGA settings.
    signal VGA_MODE_REG          :     std_logic_vector(7 downto 0) := (others => '0'); -- VGA Mode settings.
    signal PALETTE_REG           :     std_logic_vector(7 downto 0);         -- Palette register to apply mapping to the digital RGB output.
    signal OPTION_REG            :     std_logic_vector(15 downto 0) := "0000000000001111"; -- Video Controller option configuration register.
    signal GPU_PARAMS            :     std_logic_vector(127 downto 0);       -- GPU parameter register.
    signal GPU_COMMAND           :     std_logic_vector(7 downto 0);         -- GPU command register.
    signal GPU_STATUS            :     std_logic_vector(7 downto 0);         -- GPU Status register.
    signal GPU_STATE             :     GPUStateType;                         -- GPU FSM State.
    signal GPU_START_ADDR        :     std_logic_vector(13 downto 0);        -- Address being worked on by the GPU.
    signal VIDEO_LAST_RDni       :     std_logic_vector(3 downto 0);         -- Edge detect on the external read signal.
    signal VIDEO_LAST_WRni       :     std_logic_vector(3 downto 0);         -- Edge detect on the external write signal.
    signal Z80_MA                :     std_logic_vector(11 downto 0);        -- CPU Address Masked according to machine model.
    signal CS_INVERTn            :     std_logic;                            -- Chip Select to enable Inverse mode.
    signal CS_SCROLLn            :     std_logic;                            -- Chip Select to perform a hardware scroll.
    signal CS_80K_PPIn           :     std_logic;                            -- Chip select for the MZ-80K series 8255 PPI at 0xE000:0xE003.
    signal CS_FB_VGATTRn         :     std_logic;                            -- Chip Select for setting the VGA attributes.
    signal CS_FB_VGAMODEn        :     std_logic;                            -- Chip Select for setting the VGA mode.
    signal CS_FB_PALETTEn        :     std_logic;                            -- Chip Select for setting the active pallette.
    signal CS_FB_PARAMSn         :     std_logic;                            -- Chip Select for storing GPU parameters in a FILO stack.
    signal CS_FB_GPUn            :     std_logic;                            -- Chip Select for GPU command register.
    signal CS_FB_VMn             :     std_logic;                            -- Chip Select for the Video Mode register.
    signal CS_FB_PAGEn           :     std_logic;                            -- Chip Select for the Page select register.
    signal CS_FB_CTLn            :     std_logic;                            -- Chip Select to write to the Graphics mode register.
    signal CS_FB_REDn            :     std_logic;                            -- Chip Select to write to the Red pixel per byte indirect write register.
    signal CS_FB_GREENn          :     std_logic;                            -- Chip Select to write to the Green pixel per byte indirect write register.
    signal CS_FB_BLUEn           :     std_logic;                            -- Chip Select to write to the Blue pixel per byte indirect write register.
    signal CS_PCGn               :     std_logic;                            -- Chip select for the programmable character generator.
    signal CS_5XXXn              :     std_logic;                            -- Chip select range for the lower MZ80B VRAM.
    signal CS_CXXXn              :     std_logic;                            -- Chip select range for the MZ800 CGRAM.
    signal CS_DXXXn              :     std_logic;                            -- Chip select range for the VRAM/ARAM.
    signal CS_EXXXn              :     std_logic;                            -- Chip select range for the memory mapped I/O.
    signal CS_80B_GRAMn          :     std_logic;                            -- Chip select for the MZ80B Graphics Mode RAM.
    signal CS_MZ2K_GRAMn         :     std_logic;                            -- Chip select for the MZ2000 Graphics Mode RAM.
    signal CS_FBRAMn             :     std_logic;                            -- Chip select for the Graphics Framebuffer RAM.
    signal CS_IO_AXXn            :     std_logic;                            -- Chip select for block A0:AF  - Video controller dedicated ports
    signal CS_IO_BXXn            :     std_logic;                            -- Chip select for block B0:BF  - Video controller dedicated ports
    signal CS_IO_CXXn            :     std_logic;                            -- Chip select for block C0:CF  - Typically allocated within Sharp hardware.
    signal CS_IO_DXXn            :     std_logic;                            -- Chip select for block D0:DF  - Typically allocated within Sharp hardware.
    signal CS_IO_EXXn            :     std_logic;                            -- Chip select for block E0:EF  - Typically allocated within Sharp hardware.
    signal CS_IO_FXXn            :     std_logic;                            -- Chip select for block F0:FF  - Typically allocated within Sharp hardware.
    signal CS_VIDEO_LEGACYn      :     std_logic;                            -- Legacy video (Z80 access through 64K address space and paging registers).
    signal CS_VIDEO_IO_DIRECTn   :     std_logic;                            -- Direct access to the memory mapped and I/O registers.
    signal CS_VIDEO_VRAM_DIRECTn :     std_logic;                            -- Direct access to the video ram.
    signal CS_VIDEO_CGROM_DIRECTn:     std_logic;                            -- Direct access to the character generator rom.
    signal CS_VIDEO_CGRAM_DIRECTn:     std_logic;                            -- Direct access to the character generator ram.
    signal CS_VIDEO_R_FB_DIRECTn :     std_logic;                            -- Direct access to the red framebuffer ram.
    signal CS_VIDEO_B_FB_DIRECTn :     std_logic;                            -- Direct access to the blue framebuffer ram.
    signal CS_VIDEO_G_FB_DIRECTn :     std_logic;                            -- Direct access to the green framebuffer ram.
    signal CS_VIDEO_FB_DIRECTn   :     std_logic;                            -- Merged signal for direct access to any framebuffer ram.
    signal CS_VIDEO_R_OSD_DIRn   :     std_logic;
    signal CS_VIDEO_G_OSD_DIRn   :     std_logic;
    signal CS_VIDEO_B_OSD_DIRn   :     std_logic;
    signal OSD_ADDR              :     std_logic_vector(12 downto 0);
    signal OSD_WEN_R             :     std_logic;
    signal OSD_WEN_G             :     std_logic;
    signal OSD_WEN_B             :     std_logic;
    signal OSD_WEN_BYTE          :     std_logic;
    signal OSD_WEN_HWORD         :     std_logic;
    signal OSD_DI_R              :     std_logic_vector(31 downto 0);
    signal OSD_DI_G              :     std_logic_vector(31 downto 0);
    signal OSD_DI_B              :     std_logic_vector(31 downto 0);
    signal OSD_DO_R              :     std_logic_vector(31 downto 0);
    signal OSD_DO_G              :     std_logic_vector(31 downto 0);
    signal OSD_DO_B              :     std_logic_vector(31 downto 0);

    -- MZ80B Signals.
    --
    signal DISPLAY_VGATE         :     std_logic;                            -- Video Gate signal, blocks video signal when high.
    signal MZ80B_IPL             :     std_logic;                            -- MZ80B Initial Program Load taking place.
    signal MZ80B_BOOT            :     std_logic;                            -- MZ80B Boot process taking place, memory in default setting of $0000.
    signal MZ80B_VRAM_ENABLE     :     std_logic := '0';                     -- Enable Video RAM.
    signal MZ80B_VRAM_LO_ADDR    :     std_logic := '0';                     -- Video RAM located at 5000:7FFF when high, D000:FFFF when low.
    signal MZ80B_VMODE_REG       :     std_logic_vector(7 downto 0);         -- MZ80B Input/Output mode to combine the VRAM/GRAM.
    signal CS_80B_PPIn           :     std_logic;                            -- Chip select for MZ80B PPI when in MZ80B mode.
    signal CS_80B_PITn           :     std_logic;                            -- Chip select for MZ80B PIT when in MZ80B mode.
    signal CS_80B_PIOn           :     std_logic;                            -- Chip select for MZ80B PIO when in MZ80B mode.
    signal CS_80B_VMODEn         :     std_logic;                            -- Chip select for MZ80B to set the video mode for VRAM/GRAM I/II.

    -- MZ2000 Signals.
    signal CS_CRTBKCOLRn         :     std_logic;                            -- Graphics priority register, character or a graphics colour has front display priority.
    signal CS_CRTGRPHPRIOn       :     std_logic;                            -- Graphics output select on CRT or external CRT
    signal CS_CRTGRPHSELn        :     std_logic;                            -- Graphics RAM colour bank select.
    signal CS_GRAMCOLRSELn       :     std_logic;                            -- Graphics RAM colour bank select.
    signal MZ2K_VRAM_ENABLE      :     std_logic := '0';                     -- Enable graphics RAM in Z80 space, either 0xD000:0xDFFF (Character) or 0xC000:0xFFFF (Graphics)
    signal MZ2K_CHAR_ENABLE      :     std_logic := '0';                     -- Select Character (1) or Graphics (0) RAM.
    signal MZ2K_CRTBKCOLR_REG    :     std_logic_vector(7 downto 0);         -- CRT background colour register.
    signal MZ2K_CRTGRPHPRIO_REG  :     std_logic_vector(7 downto 0);         -- CRT graphics priority register.
    signal MZ2K_CRTGRPHSEL_REG   :     std_logic_vector(7 downto 0);         -- CRT graphics select register.
    signal MZ2K_GRAMCOLRSEL_REG  :     std_logic_vector(7 downto 0);         -- Graphics VRAM select register.

    -- MZ800 Signals.
    type GDPLT is array(natural range 0 to 3) of std_logic_vector(3 downto 0);   
    signal CS_GCRTCn             :     std_logic;                            -- MZ-800 CRT Control Register select.
    signal CS_GDMDn              :     std_logic;                            -- MZ-800 CRT Mode Register select.
    signal CS_GRFn               :     std_logic;                            -- MZ-800 CRT Read Format Register select.
    signal CS_GWFn               :     std_logic;                            -- MZ-800 CRT Write Format Register select.
    signal CS_GPALLETn           :     std_logic;                            -- MZ-800 CRT Pallet Register select.
    signal CS_800_GRAMn          :     std_logic;                            -- Chip select to access Graphics RAM.
    signal GD_SOF                :     std_logic_vector(9 downto 0);         -- Scroll offset regiser (SOF) 10 bits.
    signal GD_SW                 :     std_logic_vector(6 downto 0);         -- Scroll width regiser (SW), 7 bits
    signal GD_SSA                :     std_logic_vector(6 downto 0);         -- Scroll start address register (SSA), 7 bits
    signal GD_SEA                :     std_logic_vector(6 downto 0);         -- Scroll end address register (SEA), 7 bits
    signal GD_SOF_DISPLAY        :     std_logic_vector(13 downto 0);        -- Scroll offset regiser (SOF) expanded to display address width.
    signal GD_SW_DISPLAY         :     std_logic_vector(13 downto 0);        -- Scroll width regiser (SW) expanded to display address width. 
    signal GD_SSA_DISPLAY        :     std_logic_vector(13 downto 0);        -- Scroll start address register (SSA) expanded to display address width.
    signal GD_SEA_DISPLAY        :     std_logic_vector(13 downto 0);        -- Scroll end address register (SEA) expanded to display address width.
    signal GD_FB_ADDR_SOFSW      :     std_logic_vector(14 downto 0);        -- Rendering framebuffer address adjusted for SOF and SW.
    signal GD_FB_ADDR_SOF        :     std_logic_vector(14 downto 0);        -- Rendering framebuffer address adjusted for SOF.
    signal GD_ADDR_SOFSW         :     std_logic_vector(14 downto 0);        -- CPU GRAM address adjusted for SOF and SW.
    signal GD_ADDR_SOF           :     std_logic_vector(14 downto 0);        -- CPU GRAM address adjusted for SOF.
    signal GD_BCOL               :     std_logic_vector(3 downto 0);         -- Border colour regiser (BCOL), 4 bits
    signal GD_CKSW               :     std_logic;                            -- Superimpose bit (D7)(CKSW), 1 bit
    signal GD_CPUADDR            :     std_logic_vector(15 downto 0);        -- Register to store the CPU address for a read/write operation.
    signal GD_CPUWRDATA          :     std_logic_vector(7 downto 0);         -- Register to store data for writing into the graphics RAM.
    signal GD_CPURDDATA          :     std_logic_vector(7 downto 0);         -- Register to store data read from the graphics RAM.
    signal GD_DMA_ADDR           :     std_logic_vector(13 downto 0);        -- Register to store calculated address for read/write operations.
    signal GD_O_DATA             :     std_logic_vector(31 downto 0);        -- Register for storing data to be written to GRAM.
    signal GD_WEN_GI             :     std_logic;                            -- Signal to indicate a write operation needed into GRAM Bank 1.
    signal GD_WEN_GII            :     std_logic;                            -- Signal to indicate a write operation needed into GRAM Bank 2.
    signal GDMD_REG              :     std_logic_vector(7 downto 0);         -- Graphics Display LSI Command Register.
    signal GRF_REG               :     std_logic_vector(7 downto 0);         -- Graphics Display LSI Read Format Register.
    signal GWF_REG               :     std_logic_vector(7 downto 0);         -- Graphics Display LSI Write Format Register.
    signal GPALLET_REG           :     GDPLT;                                -- Graphics Display LSI Pallet Register.
    signal GPALLET_IDX           :     std_logic_vector(2 downto 0);         -- Pallet index according to programmed mode and bit stream.
    signal GD_PALLETSW           :     std_logic_vector(1 downto 0);         -- Pallet switch select.
    signal GD_FSM                :     integer range 0 to 6;                 -- Graphics Display Controller Finite State Machine state.
    signal GD_WR_FRAME_A         :     std_logic;                            -- Signal to make logic more readable.
    signal GD_WR_FRAME_B         :     std_logic;                            -- 
    signal GD_WR_FRAME_AB        :     std_logic;                            -- 
    signal GD_WR_PLANE_I         :     std_logic;                            -- 
    signal GD_WR_PLANE_II        :     std_logic;                            -- 
    signal GD_WR_PLANE_III       :     std_logic;                            -- 
    signal GD_WR_PLANE_IV        :     std_logic;                            -- 
    signal GD_RD_FRAME_A         :     std_logic;                            -- 
    signal GD_RD_FRAME_B         :     std_logic;                            -- 
    signal GD_RD_FRAME_AB        :     std_logic;                            -- 
    signal GD_RD_PLANE_I         :     std_logic;                            -- 
    signal GD_RD_PLANE_II        :     std_logic;                            -- 
    signal GD_RD_PLANE_III       :     std_logic;                            -- 
    signal GD_RD_PLANE_IV        :     std_logic;                            -- 
    signal GD_WMD_SWRITE         :     std_logic;                            --
    signal GD_WMD_EXOR           :     std_logic;                            --
    signal GD_WMD_OR             :     std_logic;                            --
    signal GD_WMD_RESET          :     std_logic;                            --
    signal GD_WMD_REPLACE        :     std_logic;                            --
    signal GD_WMD_PSET           :     std_logic;                            --
    signal GD_RD_SEARCH          :     std_logic;                            --
    signal GD_RD_SINGLE          :     std_logic;                            --
    signal GD_DMD_FRAME_A        :     std_logic;                            --
    signal GD_DMD_FRAME_B        :     std_logic;                            --
    signal GD_DMD_FRAME_AB       :     std_logic;                            --
    signal GD_DMD_320X200        :     std_logic;                            --
    signal GD_DMD_640X200        :     std_logic;                            --
    signal GD_DMD_MODE700        :     std_logic;                            --
    signal GD_SRC_DATA           :     std_logic_vector(31 downto 0);
    signal VGA_R_800             :     std_logic_vector(4 downto 0);         -- 16 level Red output for MZ800, albeit only 2 bits per colour are used..
    signal VGA_G_800             :     std_logic_vector(4 downto 0);         -- 16 level Green output.
    signal VGA_B_800             :     std_logic_vector(4 downto 0);         -- 16 level Blue output.

    --
    -- Display Signals
    --
    signal H_COUNT               :     unsigned(10 downto 0);                -- Horizontal pixel counter
    signal H_BLANKi              :     std_logic;                            -- Horizontal Blanking
    signal H_SYNCni              :     std_logic;                            -- Horizontal Blanking
    signal H_DSP_START           :     unsigned(10 downto 0); 
    signal H_DSP_END             :     unsigned(10 downto 0); 
    signal H_DSP_WND_START       :     unsigned(10 downto 0);                -- Window within the horizontal display when data is output.
    signal H_DSP_WND_END         :     unsigned(10 downto 0); 
    signal H_MNU_START           :     unsigned(10 downto 0);
    signal H_MNU_END             :     unsigned(10 downto 0); 
    signal H_HDR_START           :     unsigned(10 downto 0); 
    signal H_HDR_END             :     unsigned(10 downto 0); 
    signal H_FTR_START           :     unsigned(10 downto 0); 
    signal H_FTR_END             :     unsigned(10 downto 0); 
    signal H_SYNC_START          :     unsigned(10 downto 0); 
    signal H_SYNC_END            :     unsigned(10 downto 0); 
    signal H_LINE_END            :     unsigned(10 downto 0); 
    signal H_POLARITY            :     unsigned( 0 downto 0);                -- Horizontal polarity.
    signal V_POLARITY            :     unsigned( 0 downto 0);                -- Vertical polarity.
    signal V_COUNT               :     unsigned(10 downto 0);                -- Vertical pixel counter
    signal V_BLANKi              :     std_logic;                            -- Vertical Blanking
    signal V_SYNCni              :     std_logic;                            -- Horizontal Blanking
    signal V_DSP_START           :     unsigned(10 downto 0);
    signal V_DSP_END             :     unsigned(10 downto 0);
    signal V_MNU_START           :     unsigned(10 downto 0);
    signal V_MNU_END             :     unsigned(10 downto 0);
    signal V_HDR_START           :     unsigned(10 downto 0);
    signal V_HDR_END             :     unsigned(10 downto 0);
    signal V_FTR_START           :     unsigned(10 downto 0);
    signal V_FTR_END             :     unsigned(10 downto 0);

    signal V_DSP_WND_START       :     unsigned(10 downto 0);                -- Window within the vertical display when data is output.
    signal V_DSP_WND_END         :     unsigned(10 downto 0); 
    signal V_SYNC_START          :     unsigned(10 downto 0); 
    signal V_SYNC_END            :     unsigned(10 downto 0); 
    signal V_LINE_END            :     unsigned(10 downto 0); 
    signal H_BLANK_START         :     unsigned(10 downto 0); 
    signal H_BLANK_END           :     unsigned(10 downto 0); 
    signal V_BLANK_START         :     unsigned(10 downto 0); 
    signal V_BLANK_END           :     unsigned(10 downto 0); 
    --
    -- CG-ROM
    --
    signal CGROM_BIT_DO          :     std_logic_vector(7 downto 0);
    signal CGROM_DO              :     std_logic_vector(31 downto 0);
    signal CG_CPU_SEL            :     std_logic;                            -- CPU access to the CG ROM (MZ-800 CG-RAM at C000 in 700 mode).
    signal CG_B_ADDR             :     std_logic_vector(14 downto 0);
    signal CG_B_DI               :     std_logic_vector(7 downto 0);
    signal CG_B_DO               :     std_logic_vector(7 downto 0);
    signal CGROM_PAGE            :     std_logic;
    signal CGROM_WEN             :     std_logic;
    signal CGROM_WEN_BYTE        :     std_logic;                            -- CGROM Write byte enable signal.
    signal CGROM_WEN_HWORD       :     std_logic;                            -- CGROM Write 16bit half word enable signal.
    --
    -- PCG
    --
    signal CGRAM_DO              :     std_logic_vector(31 downto 0);
    signal CGRAM_BIT_DO          :     std_logic_vector(7 downto 0);
    signal CG_ADDR               :     std_logic_vector(11 downto 0);
    signal CG_ROM_ADDR           :     std_logic_vector(14 downto 0);
    signal VGA_MODE_SEL          :     std_logic_vector(3 downto 0);         -- Native timing select: 0000 = 60Hz, 0001 = 50Hz.
    signal CGRAM_ADDR            :     std_logic_vector(11 downto 0);
    signal PCG_DATA              :     std_logic_vector(7 downto 0);
    signal CGRAM_DI              :     std_logic_vector(31 downto 0);
    signal CGRAM_WEn             :     std_logic;
    signal CGRAM_WREN            :     std_logic;
    signal CGRAM_WEN_BYTE        :     std_logic;                            -- CGRAM Write byte enable signal.
    signal CGRAM_WEN_HWORD       :     std_logic;                            -- CGRAM Write 16bit half word enable signal.
    signal CGRAM_SEL             :     std_logic;
    --
    -- Clocks
    --
    signal VID_CE                :     std_logic := '0';                     -- Video clock enable (2x dot clock) on SYS_CLK.
    signal VID_CE_ACC            :     natural range 0 to 2**30 := 0;

    function to_std_logic(L: boolean) return std_logic is
    begin
        if L then
            return('1');
        else
            return('0');
        end if;
    end function to_std_logic;
begin

    ------------------------------------------------------------------------------------
    -- PLL Video clock and Video frequency generation.
    ------------------------------------------------------------------------------------    

    -- The video clocks are clock enables on SYS_CLK (see VIDEO_CLOCK_ENABLE below); no PLLs.

    --
    -- Instantiation
    --
    -- Palette. The original held 5-bit per channel palettes in RAM, loaded by the tranZPUter I/O
    -- processor. On MiSTer only the fixed mappings are needed: a plane bit gives full intensity,
    -- and the MZ-800 16 colour IRGB set sits at index 1111_IRGB_1, using mz800emu's colours.
    PALETTE_LUT: process( SYS_CLK )
        -- Bit 4 is the digital level, 3:0 the 16 level output.
        type pal16_t is array(0 to 15) of std_logic_vector(4 downto 0);
        constant MZ800_R : pal16_t := ("00000", "00100", "11101", "11011", "00100", "00010", "11110", "11101", "11000", "00000", "11111", "11111", "00101", "11000", "11111", "11111");
        constant MZ800_G : pal16_t := ("00000", "00100", "00011", "00000", "00110", "11100", "11101", "11101", "11000", "11000", "00000", "00101", "11111", "11111", "11111", "11111");
        constant MZ800_B : pal16_t := ("00000", "11010", "00000", "11000", "00000", "11111", "00011", "11101", "11000", "11110", "00000", "11100", "00101", "11111", "00010", "11111");
        function pal(idx : std_logic_vector(8 downto 0); ch : natural) return std_logic_vector is
            variable c : integer range 0 to 15;
        begin
            if idx(8 downto 5) = "1111" and idx(0) = '1' then
                c := to_integer(unsigned(idx(4 downto 1)));                   -- I, G (III), R (II), B (I).
                case ch is
                    when 0      => return MZ800_R(c);
                    when 1      => return MZ800_G(c);
                    when others => return MZ800_B(c);
                end case;
            elsif idx(0) = '1' then
                return "11111";
            else
                return "00000";
            end if;
        end function;
    begin
        if rising_edge(SYS_CLK) then
            FB_PALETTE_R <= pal(PALETTE_R_MUX, 0);
            FB_PALETTE_G <= pal(PALETTE_G_MUX, 1);
            FB_PALETTE_B <= pal(PALETTE_B_MUX, 2);
        end if;
    end process;
    BCOL_O       <= GD_BCOL;
    PALETTE_DO_R <= (others => '0');
    PALETTE_DO_G <= (others => '0');
    PALETTE_DO_B <= (others => '0');

    -- Pixel blending according to mode the controller is running in and the OSD state.
    --
    SR_R_MUX                 <= SR_R_OSD(7)                                    when VGA_ATTR_REG(6) = '1' and ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT < H_MNU_END))
                                else
                                (SR_R_CHR(7)   or SR_R_GFX(7)) xor SR_R_OSD(7) when MODE_VIDEO_MZ80B = '1'
                                else                                           
                                (SR_R_CHR(7)   or SR_R_GFX(7)) xor SR_R_OSD(7) when MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1'
                                else                                           
                                (SR_R_CHR(7)   or SR_R_GFX(7)) xor SR_R_OSD(7) when GRAM_MODE_REG(7 downto 6) = "00"
                                else                                           
                                (SR_R_CHR(7)  and SR_R_GFX(7)) xor SR_R_OSD(7) when GRAM_MODE_REG(7 downto 6) = "01"
                                else                                           
                                (SR_R_CHR(7) nand SR_R_GFX(7)) xor SR_R_OSD(7) when GRAM_MODE_REG(7 downto 6) = "10"
                                else                                           
                                (SR_R_CHR(7)  xor SR_R_GFX(7)) xor SR_R_OSD(7) when GRAM_MODE_REG(7 downto 6) = "11"
                                else '0';                                      
                                                                               
    SR_G_MUX                 <= SR_G_OSD(7)                                    when VGA_ATTR_REG(6) = '1' and ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT < H_MNU_END))
                                else
                                (SR_G_CHR(7)   or SR_G_GFX(7)) xor SR_G_OSD(7) when MODE_VIDEO_MZ80B = '1'
                                else                                           
                                (SR_G_CHR(7)   or SR_G_GFX(7)) xor SR_G_OSD(7) when MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1'
                                else                                           
                                (SR_G_CHR(7)   or SR_G_GFX(7)) xor SR_G_OSD(7) when GRAM_MODE_REG(7 downto 6) = "00"
                                else                                           
                                (SR_G_CHR(7)  and SR_G_GFX(7)) xor SR_G_OSD(7) when GRAM_MODE_REG(7 downto 6) = "01"
                                else                                           
                                (SR_G_CHR(7) nand SR_G_GFX(7)) xor SR_G_OSD(7) when GRAM_MODE_REG(7 downto 6) = "10"
                                else                                           
                                (SR_G_CHR(7)  xor SR_G_GFX(7)) xor SR_G_OSD(7) when GRAM_MODE_REG(7 downto 6) = "11"
                                else '0';                                      
                                                                               
    SR_B_MUX                 <= SR_B_OSD(7)                                    when VGA_ATTR_REG(6) = '1' and ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT < H_MNU_END))
                                else
                                (SR_B_CHR(7)   or SR_B_GFX(7)) xor SR_B_OSD(7) when MODE_VIDEO_MZ80B = '1'
                                else                                           
                                (SR_B_CHR(7)   or SR_B_GFX(7)) xor SR_B_OSD(7) when MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1'
                                else                                           
                                (SR_B_CHR(7)   or SR_B_GFX(7)) xor SR_B_OSD(7) when GRAM_MODE_REG(7 downto 6) = "00"
                                else                                           
                                (SR_B_CHR(7)  and SR_B_GFX(7)) xor SR_B_OSD(7) when GRAM_MODE_REG(7 downto 6) = "01"
                                else                                           
                                (SR_B_CHR(7) nand SR_B_GFX(7)) xor SR_B_OSD(7) when GRAM_MODE_REG(7 downto 6) = "10"
                                else                                           
                                (SR_B_CHR(7)  xor SR_B_GFX(7)) xor SR_B_OSD(7) when GRAM_MODE_REG(7 downto 6) = "11"
                                else '0';

    -- Map planes to digitised bit.
    SR_PLANE_I               <= SR_B_GFX(7);
    SR_PLANE_II              <= SR_R_GFX(7);
    SR_PLANE_III             <= SR_G_GFX(7);
    SR_PLANE_IV              <= SR_I_GFX(7);

    -- Mux the pallet address, top end 0xF0-0xFF is reserved for the MZ800, 16 colours, selected by the GPALLET register
    -- or direct plane drive, I = Blue, II = Red, III = Green, IV = Intensity.
    PALETTE_R_MUX            <= "1111" & (SR_G_MUX or SR_R_MUX or SR_B_MUX) & SR_G_MUX & SR_R_MUX & SR_B_MUX & '1' when CONFIG(MZ800) = '1' and MODE_VIDEO_MZ800 = '0'    -- MZ-800 in 700 mode: colours 1-7 are the bright half of the MZ-800 colours, black stays black (mz800emu's {0, 9..15}).
                                else
                                PALETTE_REG & SR_R_MUX                                                    when MODE_VIDEO_MZ800 = '0' or (VGA_ATTR_REG(6) = '1' and ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT <= H_MNU_END)))
                                else
                                "1111" & GPALLET_REG(to_integer(unsigned(GPALLET_IDX(1 downto 0)))) & '1' when MODE_VIDEO_MZ800 = '1' and GPALLET_IDX(2) = '0'
                                else
                                "1111" & SR_PLANE_IV & SR_PLANE_III & SR_PLANE_II & SR_PLANE_I & '1';
    PALETTE_G_MUX            <= "1111" & (SR_G_MUX or SR_R_MUX or SR_B_MUX) & SR_G_MUX & SR_R_MUX & SR_B_MUX & '1' when CONFIG(MZ800) = '1' and MODE_VIDEO_MZ800 = '0'    -- MZ-800 in 700 mode: colours 1-7 are the bright half of the MZ-800 colours, black stays black (mz800emu's {0, 9..15}).
                                else
                                PALETTE_REG & SR_G_MUX                                                    when MODE_VIDEO_MZ800 = '0' or (VGA_ATTR_REG(6) = '1' and ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT <= H_MNU_END)))
                                else
                                "1111" & GPALLET_REG(to_integer(unsigned(GPALLET_IDX(1 downto 0)))) & '1' when MODE_VIDEO_MZ800 = '1' and GPALLET_IDX(2) = '0'
                                else
                                "1111" & SR_PLANE_IV & SR_PLANE_III & SR_PLANE_II & SR_PLANE_I & '1';
    PALETTE_B_MUX            <= "1111" & (SR_G_MUX or SR_R_MUX or SR_B_MUX) & SR_G_MUX & SR_R_MUX & SR_B_MUX & '1' when CONFIG(MZ800) = '1' and MODE_VIDEO_MZ800 = '0'    -- MZ-800 in 700 mode: colours 1-7 are the bright half of the MZ-800 colours, black stays black (mz800emu's {0, 9..15}).
                                else
                                PALETTE_REG & SR_B_MUX                                                    when MODE_VIDEO_MZ800 = '0' or (VGA_ATTR_REG(6) = '1' and ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT <= H_MNU_END)))
                                else
                                "1111" & GPALLET_REG(to_integer(unsigned(GPALLET_IDX(1 downto 0)))) & '1' when MODE_VIDEO_MZ800 = '1' and GPALLET_IDX(2) = '0'
                                else
                                "1111" & SR_PLANE_IV & SR_PLANE_III & SR_PLANE_II & SR_PLANE_I & '1';

    -- GPALLET index based on the bit stream of the 4 planes and programmed mode.
    GPALLET_IDX              <= '0' & SR_PLANE_II & SR_PLANE_I                 when GD_DMD_320X200 = '1' and GD_DMD_FRAME_A = '1'
                                else
                                '0' & SR_PLANE_IV & SR_PLANE_III               when GD_DMD_320X200 = '1' and GD_DMD_FRAME_B = '1'  and CONFIG(OPT_MZ1R25) = '1'
                                else
                                '0' & SR_PLANE_II & SR_PLANE_I                 when GD_DMD_320X200 = '1' and GD_DMD_FRAME_AB = '1' and CONFIG(OPT_MZ1R25) = '1'  and GD_PALLETSW(0) = SR_PLANE_III and GD_PALLETSW(1) = SR_PLANE_IV  -- 16 colours: palette group IV/III selects the palette, II/I index it (mz800emu).
                                else
                                "100"                                          when GD_DMD_320X200 = '1' and GD_DMD_FRAME_AB = '1' and CONFIG(OPT_MZ1R25) = '1'  and (GD_PALLETSW(0) /= SR_PLANE_III or GD_PALLETSW(1) /= SR_PLANE_IV)
                                else
                                "00" & SR_PLANE_I                              when GD_DMD_640X200 = '1' and GD_DMD_FRAME_A = '1'
                                else
                                "00" & SR_PLANE_III                            when GD_DMD_640X200 = '1' and GD_DMD_FRAME_B = '1'  and CONFIG(OPT_MZ1R25) = '1'
                                else
                                '0' & SR_PLANE_III&SR_PLANE_I                  when GD_DMD_640X200 = '1' and GD_DMD_FRAME_AB = '1' and CONFIG(OPT_MZ1R25) = '1' 
                                else "100";


    -- Video memory as seen by the MZ Series. This is a 1K or 2K or 2K + 2K Attribute RAM
    -- organised as 4K x 8 on the CPU side and 2K x 16 on the display side, top bits are not used for MZ80K/C/1200/A.
    --
    VRAM0 : entity work.VideoRAM_DP_3216
    GENERIC MAP (
        addrbits             => 12                                                  -- Max address bit of total size in bytes. ie. 12 = 4096 bytes.
    )
    PORT MAP (
        clkA                 => SYS_CLK,
        memAAddr             => VRAM_ADDR(10 downto 0) & VRAM_ADDR(11),
        memAWriteEnable      => VRAM_WEN,
        memAWriteByte        => VRAM_WEN_BYTE,
        memAWriteHalfWord    => VRAM_WEN_HWORD,
        memAWrite            => VRAM_DI,
        memARead             => VRAM_VIDEO_DATA,

        clkB                 => SYS_CLK,
        memBAddr             => RENDR_VRAM_BADDR,
        memBWriteEnable      => '0',
        memBWrite            => (others => '0'),
        memBRead             => RENDR_VRAM_DATA
    );

    -- MZ80B Graphics RAM Option I and Red Framebuffer. The top 8K is used as GRAM I during MZ80B mode, 16K is used as Red frame/pixel
    -- buffer in 640x200.
    -- MZ800 mode this represents the top 16K of the 640x200 frame memory. In 320x200 mode there are 4 planes so this block represents
    -- (at least whilst it is 16K in size) the top memory block. In 640x200 mode there are 2 planes so this block represents the top half
    -- of the memory.
    --
    GRAMI : entity work.VideoRAM_DP_3208
    GENERIC MAP (
        addrbits             => 14                                                  -- Max address bit of total size in bytes. ie. 12 = 4096 bytes.
    )
    PORT MAP (
        clkA                 => SYS_CLK,
        memAAddr             => GRAM_ADDR,
        memAWriteEnable      => GRAM_WEN_R_GI,
        memAWriteByte        => GRAM_WEN_BYTE,
        memAWriteHalfWord    => GRAM_WEN_HWORD,
        memAWrite            => GRAM_DI_R_GI,
        memARead             => GRAM_DO_R_GI,

        clkB                 => SYS_CLK,
        memBAddr             => FB_GFX_MUXADDR(13 downto 0),                        -- FB Destination address is used as GRAM is on a 1:1 mapping with FB.
        memBWriteEnable      => '0',
        memBWrite            => (others => '0'),
        memBRead             => RENDR_GRAM_DATA(7 downto 0)
    );

    -- MZ80B Graphics RAM Option II and Blue Framebuffer. The top 8K is used as GRAM II during MZ80B mode, 16K is used as Blue frame/pixel
    -- buffer in 640x200.
    -- MZ800 mode this represents the lower 16K of the 640x200 frame memory. In 320x200 mode there are 4 planes so this block represents
    -- (at least whilst it is 16K in size) the lower memory block. In 640x200 mode there are 2 planes so this block represents the lower half
    -- of the memory.
    --
    GRAMII : entity work.VideoRAM_DP_3208
    GENERIC MAP (
        addrbits             => 14                                                  -- Max address bit of total size in bytes. ie. 12 = 4096 bytes.
    )
    PORT MAP (
        clkA                 => SYS_CLK,
        memAAddr             => GRAM_ADDR,
        memAWriteEnable      => GRAM_WEN_B_GII,
        memAWriteByte        => GRAM_WEN_BYTE,
        memAWriteHalfWord    => GRAM_WEN_HWORD,
        memAWrite            => GRAM_DI_B_GII,
        memARead             => GRAM_DO_B_GII,

        clkB                 => SYS_CLK,
        memBAddr             => FB_GFX_MUXADDR(13 downto 0),                        -- FB Destination address is used as GRAM is on a 1:1 mapping with FB.
        memBWriteEnable      => '0',
        memBWrite            => (others => '0'),
        memBRead             => RENDR_GRAM_DATA(15 downto 8)
    );

    -- MZ80B Graphics RAM Option III and Green Framebuffer.
    -- This memory is not present on the MZ80B but is instantiated as Graphics RAM III and the Green Framebuffer.
    -- In normal use, 16K is used as Green frame/pixel buffer in 640x200.
    --
    GRAMIII : entity work.VideoRAM_DP_3208
    GENERIC MAP (
        addrbits             => 14                                                  -- Max address bit of total size in bytes. ie. 12 = 4096 bytes.
    )
    PORT MAP (
        clkA                 => SYS_CLK,
        memAAddr             => GRAM_ADDR,
        memAWriteEnable      => GRAM_WEN_G_GIII,
        memAWriteByte        => GRAM_WEN_BYTE,
        memAWriteHalfWord    => GRAM_WEN_HWORD,
        memAWrite            => GRAM_DI_G_GIII,
        memARead             => GRAM_DO_G_GIII,

        clkB                 => SYS_CLK,
        memBAddr             => FB_GFX_ADDR(13 downto 0),                          -- FB Destination address is used as GRAM is on a 1:1 mapping with FB.
        memBWriteEnable      => '0',
        memBWrite            => (others => '0'),
        memBRead             => RENDR_GRAM_DATA(23 downto 16)
    );

    -- Scroll register expansion according to display mode.
    GD_SSA_DISPLAY           <= '0' & (GD_SSA&"000000")    when GD_DMD_320X200 = '1'
                                else
                                (GD_SSA&"0000000");
    GD_SEA_DISPLAY           <= '0' & (GD_SEA&"000000")    when GD_DMD_320X200 = '1'
                                else
                                (GD_SEA&"0000000");
    GD_SW_DISPLAY            <= '0' & (GD_SW&"000000")     when GD_DMD_320X200 = '1'
                                else
                                (GD_SW&"0000000");
    GD_SOF_DISPLAY           <= '0' & (GD_SOF&"000")       when GD_DMD_320X200 = '1'
                                else
                                (GD_SOF&"0000");

    -- Scroll register offsets.
    -- 15 bits: in 640x200 mode the byte address (up to 3FFF) plus SOF (up to 3E80) overflows 14 bits, which
    -- skipped the wrap at SEA near the end of the scroll (CP/M 4.1 text drawn over itself after scrolling).
    GD_FB_ADDR_SOFSW         <= GD_FB_ADDR_SOF - ('0' & GD_SW_DISPLAY);
    GD_FB_ADDR_SOF           <= ('0' & FB_GFX_ADDR(13 downto 0)) + ('0' & GD_SOF_DISPLAY);
    GD_ADDR_SOFSW            <= GD_ADDR_SOF - ('0' & GD_SW_DISPLAY);
    GD_ADDR_SOF              <= ('0' & GD_CPUADDR(13 downto 0)) + ('0' & GD_SOF_DISPLAY);


    -- Frame buffer graphics rendering address multiplexed to accommodate the MZ800 address mechanism.
    -- The addressing range is for a single GRAM bank, ie. 16K at the moment.
    FB_GFX_MUXADDR           <= GD_FB_ADDR_SOFSW(12 downto 0) & FB_GFX_LOADDR    when MODE_VIDEO_MZ800 = '1' and GD_DMD_320X200 = '1' and GD_SSA_DISPLAY <= FB_GFX_ADDR(13 downto 0) and FB_GFX_ADDR(13 downto 0) < GD_SEA_DISPLAY and GD_FB_ADDR_SOF >= GD_SEA_DISPLAY
                                else
                                GD_FB_ADDR_SOF(12 downto 0) & FB_GFX_LOADDR      when MODE_VIDEO_MZ800 = '1' and GD_DMD_320X200 = '1' and GD_SSA_DISPLAY <= FB_GFX_ADDR(13 downto 0) and FB_GFX_ADDR(13 downto 0) < GD_SEA_DISPLAY 
                                else
                                GD_FB_ADDR_SOFSW(13 downto 0) & FB_GFX_LOADDR(0) when MODE_VIDEO_MZ800 = '1' and GD_DMD_640X200 = '1' and GD_SSA_DISPLAY <= FB_GFX_ADDR(13 downto 0) and FB_GFX_ADDR(13 downto 0) < GD_SEA_DISPLAY and GD_FB_ADDR_SOF >= GD_SEA_DISPLAY
                                else
                                GD_FB_ADDR_SOF(13 downto 0) & FB_GFX_LOADDR(0)   when MODE_VIDEO_MZ800 = '1' and GD_DMD_640X200 = '1' and GD_SSA_DISPLAY <= FB_GFX_ADDR(13 downto 0) and FB_GFX_ADDR(13 downto 0) < GD_SEA_DISPLAY 
                                else
                                FB_GFX_ADDR(12 downto 0) & FB_GFX_LOADDR         when MODE_VIDEO_MZ800 = '1' and GD_DMD_320X200 = '1'
                                else
                                FB_GFX_ADDR(13 downto 0) & FB_GFX_LOADDR(0)      when MODE_VIDEO_MZ800 = '1' and GD_DMD_640X200 = '1'
                                else
                                '0' & FB_GFX_ADDR;

    -- CPU to frame buffer address.
    GD_DMA_ADDR              <= '0' & GD_ADDR_SOFSW(12 downto 0)                 when GD_DMD_320X200 = '1' and GD_SSA_DISPLAY <= GD_CPUADDR(13 downto 0) and GD_CPUADDR(13 downto 0) < GD_SEA_DISPLAY and GD_ADDR_SOF >= GD_SEA_DISPLAY
                                else
                                '0' & GD_ADDR_SOF(12 downto 0)                   when GD_DMD_320X200 = '1' and GD_SSA_DISPLAY <= GD_CPUADDR(13 downto 0) and GD_CPUADDR(13 downto 0) < GD_SEA_DISPLAY  
                                else
                                GD_ADDR_SOFSW(13 downto 0)                       when GD_DMD_640X200 = '1' and GD_SSA_DISPLAY <= GD_CPUADDR(13 downto 0) and GD_CPUADDR(13 downto 0) < GD_SEA_DISPLAY and GD_ADDR_SOF >= GD_SEA_DISPLAY
                                else
                                GD_ADDR_SOF(13 downto 0)                         when GD_DMD_640X200 = '1' and GD_SSA_DISPLAY <= GD_CPUADDR(13 downto 0) and GD_CPUADDR(13 downto 0) < GD_SEA_DISPLAY  
                                else
                                '0' & GD_CPUADDR(12 downto 0)                    when GD_DMD_320X200 = '1'
                                else
                                GD_CPUADDR(13 downto 0);


    -- On Screen Display - Menu. This is an overlay buffer which is layed ontop of the main MZ screen for use with menu systems to select options/change settings.
    -- 3 primary colours planes are provided allowing upto 8 colours.
    MENUBUFR : entity work.VideoRAM_DP_3208
    GENERIC MAP (
        addrbits             => 13                                                  -- Max address bit of total size in bytes. ie. 12 = 4096 bytes.
    )
    PORT MAP (
        clkA                 => SYS_CLK,
        memAAddr             => OSD_ADDR(12 downto 0),
        memAWriteEnable      => OSD_WEN_R,
        memAWriteByte        => OSD_WEN_BYTE,
        memAWriteHalfWord    => OSD_WEN_HWORD,
        memAWrite            => OSD_DI_R,
        memARead             => OSD_DO_R,

        clkB                 => SYS_CLK,
        memBAddr             => FB_OSD_ADDR,        
        memBWriteEnable      => '0',
        memBWrite            => (others => '0'),
        memBRead             => FB_OSD_DATA(15 downto 8)
    );
    MENUBUFG : entity work.VideoRAM_DP_3208
    GENERIC MAP (
        addrbits             => 13                                                  -- Max address bit of total size in bytes. ie. 12 = 4096 bytes.
    )
    PORT MAP (
        clkA                 => SYS_CLK,
        memAAddr             => OSD_ADDR(12 downto 0),
        memAWriteEnable      => OSD_WEN_G,
        memAWriteByte        => OSD_WEN_BYTE,
        memAWriteHalfWord    => OSD_WEN_HWORD,
        memAWrite            => OSD_DI_G,
        memARead             => OSD_DO_G,

        clkB                 => SYS_CLK,
        memBAddr             => FB_OSD_ADDR,        
        memBWriteEnable      => '0',
        memBWrite            => (others => '0'),
        memBRead             => FB_OSD_DATA(7 downto 0)
    );
    MENUBUFB : entity work.VideoRAM_DP_3208
    GENERIC MAP (
        addrbits             => 13                                                  -- Max address bit of total size in bytes. ie. 12 = 4096 bytes.
    )
    PORT MAP (
        clkA                 => SYS_CLK,
        memAAddr             => OSD_ADDR(12 downto 0),
        memAWriteEnable      => OSD_WEN_B,
        memAWriteByte        => OSD_WEN_BYTE,
        memAWriteHalfWord    => OSD_WEN_HWORD,
        memAWrite            => OSD_DI_B,
        memARead             => OSD_DO_B,

        clkB                 => SYS_CLK,
        memBAddr             => FB_OSD_ADDR,        
        memBWriteEnable      => '0',
        memBWrite            => (others => '0'),
        memBRead             => FB_OSD_DATA(23 downto 16)
    );

    -- CGROM - 4K allocated. Default ROM is for the MZ-80A.
    -- For other machines, the ROM needs to be uploaded by enabling the CGROM_PAGE, writing the ROM to D000:DFFF and then clearing the bit.
    --
    CGROM0 : dpram
    GENERIC MAP (
        init_file            => "./software/mif/combined_cgrom.mif",
        widthad_a            => 15,
        width_a              => 8,
        widthad_b            => 15,
        width_b              => 8
    )
    PORT MAP (
        -- Port A: character rendering.
        clock_a              => SYS_CLK,
        clocken_a            => '1',
        address_a            => CG_ROM_ADDR,
        data_a               => (others => '0'),
        wren_a               => '0',
        q_a                  => CGROM_BIT_DO,

        -- Port B: the CPU (MZ-800 CG-RAM), otherwise ioctl load/read.
        clock_b              => SYS_CLK,
        clocken_b            => '1',
        address_b            => CG_B_ADDR,
        data_b               => CG_B_DI,
        wren_b               => CG_IOCTL_WR or (CGROM_WEN and CG_CPU_SEL),
        q_b                  => CG_B_DO
    );
    -- The MZ-800 in 700 mode has its CG in RAM at C000 (the IPL copies the CG ROM there). Here the CPU reads and writes
    -- the MZ-800 bank of the CG ROM, which holds the same (bit-reversed) font.
    CG_CPU_SEL               <= '1' when CS_CXXXn = '0' and CS_VIDEO_LEGACYn = '0' and MODE_VIDEO_BASE = MODE_MZ800 and MODE_VIDEO_MZ700 = '1'
                                else '0';
    CG_B_ADDR                <= CG_BANK(3 downto 1) & VIDEO_ADDRi(11 downto 0) when CG_CPU_SEL = '1'
                                else CG_IOCTL_ADDR;
    CG_B_DI                  <= VIDEO_DATA_INi(7 downto 0) when CG_CPU_SEL = '1'
                                else CG_IOCTL_DOUT;
    CG_IOCTL_DIN             <= CG_B_DO;
    VGA_MODE_SEL             <= "000" & VIDEO_50HZ;                           -- Only native timings on MiSTer.
    CG_ROM_ADDR              <= CG_BANK(3 downto 1) & CG_ADDR(11) & CG_ADDR(10 downto 0) when CG_4K = '1'
                                else
                                CG_BANK & CG_ADDR(10 downto 0);
    CGROM_DO                 <= X"000000" & CG_B_DO;                              -- CPU read-back (MZ-800 CG-RAM).
    
    -- Programmable Character Generator RAM. This is instantiated for compatibility with original hardware upgrades and software that makes use of it.
    -- If writing new software, it is easier to just write to the CGROM as per above.
    --
    CGRAM0 : entity work.ChrGenRAM_DP_3208
    GENERIC MAP (
        addrbits             => 12                                                  -- Max address bit of total size in bytes. ie. 12 = 4096 bytes.
    )
    PORT MAP (
        clkA                 => SYS_CLK,
        memAAddr             => CG_ADDR(11 downto 0),
        memAWriteEnable      => CGRAM_WREN,
        memAWriteByte        => CGRAM_WEN_BYTE,
        memAWriteHalfWord    => CGRAM_WEN_HWORD,
        memAWrite            => CGRAM_DI,
        memARead             => CGRAM_DO,

        clkB                 => SYS_CLK,
        memBAddr             => CG_ADDR(11 downto 0),
        memBWriteEnable      => '0',
        memBWrite            => (others => '0'),
        memBRead             => CGRAM_BIT_DO
    );

    -- Process to bring all the interface signals into this clock domain with all timing within this component using the video system clock.
    process(SYS_CLK, VRESETn, VIDEO_ADDR, VIDEO_DATA_IN, VIDEO_DATA_OUTi, VIDEO_MREQn, VIDEO_IORQn, VIDEO_RDn, VIDEO_WRn, VIDEO_WR_BYTE, VIDEO_WR_HWORDi)
    begin
        if rising_edge(SYS_CLK) then
            if VRESETn = '0' then
                VIDEO_ADDRi                  <= (others => '0');
                VIDEO_DATA_INi               <= (others => '0');
                VIDEO_DATA_OUT               <= (others => '0');
                VIDEO_WR_BYTEi               <= '0';
                VIDEO_WR_HWORDi              <= '0';
                VIDEO_MREQni                 <= '1';
                VIDEO_IORQni                 <= '1';
                VIDEO_RDni                   <= '1';
                VIDEO_WRni                   <= '1';
                VIDEO_LAST_RDni              <= (others => '1');
                VIDEO_LAST_WRni              <= (others => '1');
            else
                VIDEO_ADDRi                  <= VIDEO_ADDR;
                VIDEO_MREQni                 <= VIDEO_MREQn;
                VIDEO_IORQni                 <= VIDEO_IORQn;
                VIDEO_DATA_INi               <= VIDEO_DATA_IN;
                VIDEO_WR_BYTEi               <= VIDEO_WR_BYTE;
                VIDEO_WR_HWORDi              <= VIDEO_WR_HWORDi;
                VIDEO_LAST_RDni              <= VIDEO_LAST_RDni(2 downto 0) & VIDEO_RDn;
                VIDEO_LAST_WRni              <= VIDEO_LAST_WRni(2 downto 0) & VIDEO_WRn;

                -- One cycle after read goes active latch the data for output to the CPLD.
                if MODE_HOST = '1' and HOST_HW_MZ2000 = '1' and VIDEO_LAST_RDni = "0000" and VIDEO_RDn = '1' then
                    VIDEO_DATA_OUT           <= VIDEO_DATA_OUTi;

                -- Not strictly necessary but seperate capture for MZ-80A.
          --      elsif MODE_HOST = '1' and HOST_HW_MZ80A = '1' and VIDEO_LAST_RDni = "0000" and VIDEO_RDn = '0' then
          --          VIDEO_DATA_OUT           <= VIDEO_DATA_OUTi;

                -- Timing is more critical for the T80, read and latch the data in advance of T80 T3 cycle.
                elsif MODE_EMUMZ = '1' then
                    -- Follow the read data for as long as RD is active. The original latched once, 4 SYS_CLKs
                    -- into the read, which is too late for the CPU at turbo speeds on this core's clock.
                    if VIDEO_RDn = '0' then
                        VIDEO_DATA_OUT       <= VIDEO_DATA_OUTi;
                    end if;

                elsif (MODE_IOP = '1' or MODE_HOST = '1') and VIDEO_LAST_RDni = "0000" and VIDEO_RDn = '0' then
                    VIDEO_DATA_OUT           <= VIDEO_DATA_OUTi;
                end if;

                -- Detect an edge on the RD/WR lines and create a video RD/WR which is one system clock pulse wide.
                VIDEO_WRni                   <= '1';
                VIDEO_RDni                   <= '1';
          --      if MODE_HOST = '1' and HOST_HW_MZ80A = '1' and VIDEO_LAST_RDni = "0000" and VIDEO_RDn = '0' then
          --          VIDEO_RDni               <= '0';
          --      else
                    VIDEO_RDni               <= VIDEO_RDn; --'0';
          --      end if;

               -- Matching the write timing of different drivers, even though the WR signal has been brought into this domain, the higher clock frequency and the timing of the driver does differ.
               if (MODE_HOST = '1'   and VIDEO_LAST_WRni = "1000" and VIDEO_WRn = '0') or
              --    (MODE_HOST = '1'   and HOST_HW_MZ80A = '1' and VIDEO_LAST_WRni = "0000" and VIDEO_WRn = '0') or
               --   (HOST_HW_MZ2000 = '1' and VIDEO_LAST_WRni = "1000" and VIDEO_WRn = '0') or
                  (MODE_IOP = '1'    and VIDEO_LAST_WRni = "1000" and VIDEO_WRn = '0') or
                  (MODE_EMUMZ = '1'  and VIDEO_LAST_WRni = "1111" and VIDEO_WRn = '0') then
                   VIDEO_WRni               <= VIDEO_WRn; --'0';
               end if;
            end if;
        end if;
    end process;
  --VIDEO_ADDRi              <= VIDEO_ADDR;
  --VIDEO_MREQni             <= VIDEO_MREQn;
  --VIDEO_IORQni             <= VIDEO_IORQn;
  --VIDEO_DATA_OUT           <= VIDEO_DATA_OUTi;
  --VIDEO_RDni               <= VIDEO_RDn;
  --VIDEO_WRni               <= VIDEO_WRn;
  --VIDEO_DATA_INi           <= VIDEO_DATA_IN;
  --VIDEO_WR_BYTEi           <= VIDEO_WR_BYTE;
  --VIDEO_WR_HWORDi          <= VIDEO_WR_HWORDi;

    -- Video clock enable. The original design switched between PLL clocks at 2x the dot clock
    -- (VID_CLK); here VID_CE pulses at that rate on SYS_CLK, chosen by CLOCKSEL, and every process
    -- that ran on VID_CLK runs on SYS_CLK gated by VID_CE. CE_PIXEL marks the VID_CE edges on which
    -- GENVIDEO advances a pixel (VIDCLK_DIV = '1').
    VIDEO_CLOCK_ENABLE: process( SYS_CLK )
        variable rate : natural;
        variable nxt  : natural;
    begin
        if rising_edge(SYS_CLK) then
            case CLOCKSEL is
                when SEL_CLOCK_8MHZ    => rate := 16000000;
                when SEL_CLOCK_8_8MHZ  => rate := 17734400;
                when SEL_CLOCK_16MHZ   => rate := 32000000;
                when SEL_CLOCK_17_7MHZ => rate := 35468800;
                when others            => rate := CLK_HZ / 2;                    -- VGA modes are not used on MiSTer.
            end case;
            if rate > CLK_HZ / 2 then
                rate := CLK_HZ / 2;
            end if;
            nxt := VID_CE_ACC + rate;
            if nxt >= CLK_HZ then
                VID_CE_ACC <= nxt - CLK_HZ;
                VID_CE     <= '1';
            else
                VID_CE_ACC <= nxt;
                VID_CE     <= '0';
            end if;
        end if;
    end process;
    CE_PIXEL <= VID_CE and VIDCLK_DIV;
    RENDR_VRAM_BADDR <= std_logic_vector(unsigned(RENDR_VRAM_ADDR) + 16#400#) when RENDR_PCG_PHASE = '1' else RENDR_VRAM_ADDR;

    -- Clock at maximum system speed to minimise transfer time. The video clock is running at two times the display clock and there are 8 clocks per colour word serialisation, this gives 15 cycles to render the next colour word component of the frame.
    -- The character word output is blended with the graphics and OSD planes to create final output.
    --
    RENDERCHRFRAME: process( VRESETn, SYS_CLK, VIDEOMODE_RESET_TIMER )
        variable RENDR_CHR_CYCLE : integer range 0 to 7;
        variable RENDR_SRC_COL   : integer range 0 to 80;
        variable RENDR_DST_SUBROW: integer range 0 to 7;
        variable V_CPIX_CNT      : integer range 0 to 3;                 -- Variable to indicate if vertical pixels should be multiplied (for conversion to alternate formats).
    begin

        -- Copy at end of Display based on the highest clock to minimise time,
        --
        if rising_edge(SYS_CLK) then if VID_CE = '1' then

            if VRESETn='0' then
                RENDR_VRAM_ADDR     <= (others => '0');
                RENDR_CGROM_ADDR    <= (others => '0');
                RENDR_SRC_COL       := 0;
                RENDR_DST_SUBROW    := 0;
                RENDR_CHR_CYCLE     := 0;
                FB_CHR_DATA         <= (others => '0');
                V_CPIX_CNT          := 0;
    
            else
                -- A video mode change is similar to a RESET, the process halts and all the control variables are reset.
                --
                if VIDEOMODE_RESET_TIMER > 16 then

                    RENDR_VRAM_ADDR     <= (others => '0');
                    RENDR_CGROM_ADDR    <= (others => '0');
                    RENDR_SRC_COL       := 0;
                    RENDR_DST_SUBROW    := 0;
                    RENDR_CHR_CYCLE     := 0;
                    FB_CHR_DATA         <= (others => '0');
                    V_CPIX_CNT          := to_integer(V_CPX);

                else

                    -- On signal from the frame generation, prepare the next chunk of the character plane ready for serialisation.
                    if RENDR_CHR_NEXT = '1' or RENDR_CHR_CYCLE /= 0 then

                        -- Framebuffer address change then re-initialise FSM.
                        if RENDR_CHR_NEXT = '1' then
                            RENDR_CHR_CYCLE      := 0;
                        end if;

                        -- Finite state machine to implement read and mapping of the character VRAM data.
                        case (RENDR_CHR_CYCLE) is
            
                            when 0 =>
                                FB_CHR_DATA      <= (others => '0');
                                RENDR_CHR_CYCLE  := 1;
            
                            -- Get the source character and map via the PCG to a slice of the displayed character.
                            -- Recalculate the destination address based on this loops values.
                            when 1 =>
                                -- Setup the PCG address based on the read character.
                                RENDR_CGROM_ADDR <= RENDR_VRAM_DATA(15) & RENDR_VRAM_DATA(7 downto 0) & std_logic_vector(to_unsigned(RENDR_DST_SUBROW, 3));
                                RENDR_CHR_WORD               <= RENDR_VRAM_DATA;
                                RENDR_PCG_PHASE              <= M15_PCGON;              -- MZ-1500: read the cell's PCG word next.
                                RENDR_CHR_CYCLE              := 2;

                            --   Graphics mode:- 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
                            --                     5 = GRAM Output Enable  0 = active.
                            --                     4 = VRAM Output Enable, 0 = active.
                            --                   3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
                            --                   1/0 = Read mode  (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Not used).
                            --
                            -- Extra cycle for CGROM to latch, use time to decide which mode we are processing.
                            when 2 =>
                                -- MZ-1500: the PCG word (low byte = PCG character bits 7-0, high byte bits 7-6 = bits 9-8, bit 3 = enable).
                                if RENDR_PCG_PHASE = '1' then
                                    PCG_RD_ADDR              <= RENDR_VRAM_DATA(15 downto 14) & RENDR_VRAM_DATA(7 downto 0) & std_logic_vector(to_unsigned(RENDR_DST_SUBROW, 3));
                                    RENDR_PCG_CELL           <= RENDR_VRAM_DATA(11);
                                else
                                    RENDR_PCG_CELL           <= '0';
                                end if;
                                RENDR_PCG_PHASE              <= '0';
                                -- Check to see if VRAM is disabled, if it is, skip.
                                --
                                if    GRAM_MODE_REG(4) = '0' and (MODE_VIDEO_MONO = '1'   or MODE_VIDEO_MONO80 = '1') then --or MODE_VIDEO_MZ80B = '1' or MODE_VIDEO_MZ2000 = '1') then
                                    -- Monochrome modes?
                                    RENDR_CHR_CYCLE          := 4;
            
                                elsif GRAM_MODE_REG(4) = '0' and (MODE_VIDEO_COLOUR = '1' or MODE_VIDEO_COLOUR80 = '1') then
                                    -- Colour modes?
                                    RENDR_CHR_CYCLE          := 3;
            
                                else
                                    -- Disabled or unrecognised mode.
                                    RENDR_CHR_CYCLE          := 0;
                                end if;
            
                            -- Colour modes?
                            -- Expand and store the slice of the character with colour expansion.
                            --
                            when 3 =>
                                if CGROM_DATA(7) = '0' then
                                    FB_CHR_DATA(7)           <= RENDR_CHR_WORD(9);              -- Red
                                    FB_CHR_DATA(15)          <= RENDR_CHR_WORD(8);              -- Blue
                                    FB_CHR_DATA(23)          <= RENDR_CHR_WORD(10);             -- Green
                                else
                                    FB_CHR_DATA(7)           <= RENDR_CHR_WORD(13);
                                    FB_CHR_DATA(15)          <= RENDR_CHR_WORD(12);
                                    FB_CHR_DATA(23)          <= RENDR_CHR_WORD(14);
                                end if;
                                if CGROM_DATA(6) = '0' then
                                    FB_CHR_DATA(6)           <= RENDR_CHR_WORD(9);
                                    FB_CHR_DATA(14)          <= RENDR_CHR_WORD(8);
                                    FB_CHR_DATA(22)          <= RENDR_CHR_WORD(10);
                                else
                                    FB_CHR_DATA(6)           <= RENDR_CHR_WORD(13);
                                    FB_CHR_DATA(14)          <= RENDR_CHR_WORD(12);
                                    FB_CHR_DATA(22)          <= RENDR_CHR_WORD(14);
                                end if;
                                if CGROM_DATA(5) = '0' then
                                    FB_CHR_DATA(5)           <= RENDR_CHR_WORD(9);
                                    FB_CHR_DATA(13)          <= RENDR_CHR_WORD(8);
                                    FB_CHR_DATA(21)          <= RENDR_CHR_WORD(10);
                                else
                                    FB_CHR_DATA(5)           <= RENDR_CHR_WORD(13);
                                    FB_CHR_DATA(13)          <= RENDR_CHR_WORD(12);
                                    FB_CHR_DATA(21)          <= RENDR_CHR_WORD(14);
                                end if;
                                if CGROM_DATA(4) = '0' then
                                    FB_CHR_DATA(4)           <= RENDR_CHR_WORD(9);
                                    FB_CHR_DATA(12)          <= RENDR_CHR_WORD(8);
                                    FB_CHR_DATA(20)          <= RENDR_CHR_WORD(10);
                                else
                                    FB_CHR_DATA(4)           <= RENDR_CHR_WORD(13);
                                    FB_CHR_DATA(12)          <= RENDR_CHR_WORD(12);
                                    FB_CHR_DATA(20)          <= RENDR_CHR_WORD(14);
                                end if;
                                if CGROM_DATA(3) = '0' then
                                    FB_CHR_DATA(3)           <= RENDR_CHR_WORD(9);
                                    FB_CHR_DATA(11)          <= RENDR_CHR_WORD(8);
                                    FB_CHR_DATA(19)          <= RENDR_CHR_WORD(10);
                                else
                                    FB_CHR_DATA(3)           <= RENDR_CHR_WORD(13);
                                    FB_CHR_DATA(11)          <= RENDR_CHR_WORD(12);
                                    FB_CHR_DATA(19)          <= RENDR_CHR_WORD(14);
                                end if;
                                if CGROM_DATA(2) = '0' then
                                    FB_CHR_DATA(2)           <= RENDR_CHR_WORD(9);
                                    FB_CHR_DATA(10)          <= RENDR_CHR_WORD(8);
                                    FB_CHR_DATA(18)          <= RENDR_CHR_WORD(10);
                                else
                                    FB_CHR_DATA(2)           <= RENDR_CHR_WORD(13);
                                    FB_CHR_DATA(10)          <= RENDR_CHR_WORD(12);
                                    FB_CHR_DATA(18)          <= RENDR_CHR_WORD(14);
                                end if;
                                if CGROM_DATA(1) = '0' then
                                    FB_CHR_DATA(1)           <= RENDR_CHR_WORD(9);
                                    FB_CHR_DATA(9)           <= RENDR_CHR_WORD(8);
                                    FB_CHR_DATA(17)          <= RENDR_CHR_WORD(10);
                                else
                                    FB_CHR_DATA(1)           <= RENDR_CHR_WORD(13);
                                    FB_CHR_DATA(9)           <= RENDR_CHR_WORD(12);
                                    FB_CHR_DATA(17)          <= RENDR_CHR_WORD(14);
                                end if;
                                if CGROM_DATA(0) = '0' then
                                    FB_CHR_DATA(0)           <= RENDR_CHR_WORD(9);
                                    FB_CHR_DATA(8)           <= RENDR_CHR_WORD(8);
                                    FB_CHR_DATA(16)          <= RENDR_CHR_WORD(10);
                                else
                                    FB_CHR_DATA(0)           <= RENDR_CHR_WORD(13);
                                    FB_CHR_DATA(8)           <= RENDR_CHR_WORD(12);
                                    FB_CHR_DATA(16)          <= RENDR_CHR_WORD(14);
                                end if;
                                if RENDR_PCG_CELL = '1' then
                                    RENDR_CHR_CYCLE          := 7;                      -- MZ-1500 PCG composite.
                                else
                                    RENDR_CHR_CYCLE          := 6;
                                end if;
            
                            -- Monochrome modes?
                            -- Expand and store the slice of the character in monochrome according to machine mode. MZ80K/C = white, MZ80A/1200 = Green.
                            --
                            when 4 =>
                                if CGROM_DATA(7) = '1' then
                                    FB_CHR_DATA(23)          <= '1';
                                    if MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' then
                                        FB_CHR_DATA(7)       <= '1';
                                        FB_CHR_DATA(15)      <= '1';
                                    end if;
                                end if;
                                if CGROM_DATA(6) = '1' then
                                    FB_CHR_DATA(22)          <= '1';
                                    if MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' then
                                        FB_CHR_DATA(6)       <= '1';
                                        FB_CHR_DATA(14)      <= '1';
                                    end if;
                                end if;
                                if CGROM_DATA(5) = '1' then
                                    FB_CHR_DATA(21)          <= '1';
                                    if MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' then
                                        FB_CHR_DATA(5)       <= '1';
                                        FB_CHR_DATA(13)      <= '1';
                                    end if;
                                end if;
                                if CGROM_DATA(4) = '1' then
                                    FB_CHR_DATA(20)          <= '1';
                                    if MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' then
                                        FB_CHR_DATA(4)       <= '1';
                                        FB_CHR_DATA(12)      <= '1';
                                    end if;
                                end if;
                                if CGROM_DATA(3) = '1' then
                                    FB_CHR_DATA(19)          <= '1';
                                    if MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' then
                                        FB_CHR_DATA(3)       <= '1';
                                        FB_CHR_DATA(11)      <= '1';
                                    end if;
                                end if;
                                if CGROM_DATA(2) = '1' then
                                    FB_CHR_DATA(18)          <= '1';
                                    if MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' then
                                        FB_CHR_DATA(2)       <= '1';
                                        FB_CHR_DATA(10)      <= '1';
                                    end if;
                                end if;
                                if CGROM_DATA(1) = '1' then
                                    FB_CHR_DATA(17)          <= '1';
                                    if MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' then
                                        FB_CHR_DATA(1)       <= '1';
                                        FB_CHR_DATA(9)       <= '1';
                                    end if;
                                end if;
                                if CGROM_DATA(0) = '1' then
                                    FB_CHR_DATA(16)          <= '1';
                                    if MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' then
                                        FB_CHR_DATA(0)       <= '1';
                                        FB_CHR_DATA(8)       <= '1';
                                    end if;
                                end if;
                                RENDR_CHR_CYCLE              := 5;
            
                            when 5 =>
                                -- If invert option selected, invert green.
                                --
                                if (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ80B = '1')and DISPLAY_INVERT = '1' then
                                    FB_CHR_DATA(23 downto 16)<= not FB_CHR_DATA(23 downto 16);
                                end if;
                                RENDR_CHR_CYCLE              := 6;
            
                            -- MZ-1500 PCG composite (mz800emu mz1500_framebuffer.c): PCG colour index = planes 2,1,0 bit, mapped
                            -- through the F1 palette. BFP: a non-zero index covers the character; BPF: the PCG replaces the
                            -- background and character foreground pixels stay on top.
                            when 7 =>
                                for i in 0 to 7 loop
                                    if (M15_PRIO = '1' and (PCG_RD_DATA(16+i) or PCG_RD_DATA(8+i) or PCG_RD_DATA(i)) = '1') or
                                       (M15_PRIO = '0' and CGROM_DATA(i) = '0') then
                                        for c in 0 to 7 loop
                                            if unsigned'(PCG_RD_DATA(16+i) & PCG_RD_DATA(8+i) & PCG_RD_DATA(i)) = c then
                                                FB_CHR_DATA(i)      <= M15_PAL(c*3+1);   -- Red
                                                FB_CHR_DATA(8+i)    <= M15_PAL(c*3);     -- Blue
                                                FB_CHR_DATA(16+i)   <= M15_PAL(c*3+2);   -- Green
                                            end if;
                                        end loop;
                                    end if;
                                end loop;
                                RENDR_CHR_CYCLE              := 6;

                            when 6 =>
                                -- For each source character, we generate pixels on 8 rows/lines. We need to process the same source row 8 times,
                                -- each time incrementing the sub-row which is used to extract the next pixel set from the CG. The data is thus 
                                -- generated as:-
                                -- <Row:0,CGLine:0,0 .. MAX_COLUMN -1> <Row:0,CGLine:1,0.. MAX_COLUMN -1> .. <Row:0,CGLine:7,0.. MAX_COLUMN -1>
                                -- ..
                                -- <Row:24,CGLine:0,0 .. MAX_COLUMN -1><Row:24,CGLine:1,0.. MAX_COLUMN -1> .. <Row:24,CGLine:7,0.. MAX_COLUMN -1>
                                --
                                -- To achieve this, we keep a note of the column and sub-row, incrementing the source address until end of line
                                -- then winding it back if we are still rendering the Characters for a given row. 
                                --
                                if RENDR_SRC_COL < MAX_COLUMN - 1 then
                                    RENDR_SRC_COL            := RENDR_SRC_COL + 1;
                                    RENDR_VRAM_ADDR          <= RENDR_VRAM_ADDR + 1;
                                else
                                    if RENDR_DST_SUBROW < MAX_SUBROW -1 then
                                        RENDR_SRC_COL        := 0;
                                        RENDR_VRAM_ADDR      <= RENDR_VRAM_ADDR - std_logic_vector((MAX_COLUMN - 1));

                                        if V_CPIX_CNT = 0 then
                                            RENDR_DST_SUBROW:= RENDR_DST_SUBROW + 1;
                                            V_CPIX_CNT       := to_integer(V_CPX);
                                        else
                                            V_CPIX_CNT       := V_CPIX_CNT - 1;
                                        end if;

                                    elsif RENDR_DST_SUBROW = MAX_SUBROW -1 and V_CPIX_CNT /= 0 then
                                        V_CPIX_CNT           := V_CPIX_CNT - 1;
                                        RENDR_SRC_COL        := 0;
                                        RENDR_VRAM_ADDR      <= RENDR_VRAM_ADDR - std_logic_vector((MAX_COLUMN - 1));
                                    else
                                        RENDR_SRC_COL        := 0;
                                        RENDR_VRAM_ADDR      <= RENDR_VRAM_ADDR + 1;
                                        RENDR_DST_SUBROW     := 0;
                                        V_CPIX_CNT           := to_integer(V_CPX);
                                    end if;
                                end if;

                                -- MZ800 machine, characters are scanned in reverse to other MZ machines with the bitmap being in reverse so, reverse the bit ordering.
                                --
                                if CONFIG(MZ800) = '1' then
                                    FB_CHR_DATA(23 downto 16)<= reverse_vector(FB_CHR_DATA(23 downto 16));
                                    FB_CHR_DATA(15 downto  8)<= reverse_vector(FB_CHR_DATA(15 downto  8));
                                    FB_CHR_DATA( 7 downto  0)<= reverse_vector(FB_CHR_DATA( 7 downto  0));
                                end if;
            
                                -- Destination address increments every tick.
                                --
                                RENDR_CHR_CYCLE              := 0;
                            end case;
                        end if;

                        -- At the end of the display component of a frame, reset the transfer parameters so that the first component of the new frame is ready for serialisation.
                        --
                        if V_COUNT = V_DSP_END then
            
                            -- Start of display, setup the start of VRAM for display according to machine. 
                            if MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1' then
                                RENDR_VRAM_ADDR <= (OFFSET_ADDR & "000");
                            else
                                RENDR_VRAM_ADDR <= (others => '0');
                            end if;
                            RENDR_CGROM_ADDR    <= (others => '0');
                            RENDR_SRC_COL       := 0;
                            RENDR_DST_SUBROW    := 0;
                            V_CPIX_CNT          := to_integer(V_CPX);
                        end if;
                end if;
            end if; -- if VRESET
        end if; end if; -- VID_CE, rising_edge(SYS_CLK)
    end process;

    -- Same as the character rendering, clock at maximum system speed to minimise transfer time. The video clock is running at two times the display clock and there are 8 clocks per colour word serialisation, this gives 15 cycles to render the next colour 
    -- word component of the frame.  The rendered pixel graphics word is later blended in with the character and OSD planes to create the final output.
    --
    RENDERGRAPHICSFRAME: process( VRESETn, SYS_CLK, FB_GFX_ADDR, VIDEOMODE_RESET_TIMER )
        variable RENDR_GFX_CYCLE        : integer range 0 to 4;
    begin

        -- Copy at end of Display based on the highest clock to minimise time,
        --
        if rising_edge(SYS_CLK) then if VID_CE = '1' then

            if VRESETn='0' then
                RENDR_GFX_CYCLE         := 0;
                FB_GFX_DATA             <= (others => '0');
                FB_GFX_LOADDR           <= (others => '0');
    
            else
                -- A video mode change is similar to a RESET, the process halts and all the control variables are reset.
                --
                if VIDEOMODE_RESET_TIMER > 16 then

                    RENDR_GFX_CYCLE     := 0;
                    FB_GFX_DATA         <= (others => '0');

                else

                    -- On framebuffer address change, prepare the next chunk of the frame ready for serialisation by the frame generator.
                    if RENDR_GFX_NEXT = '1' or RENDR_GFX_CYCLE /= 0 then

                        -- Framebuffer address change then re-initialise FSM.
                        if RENDR_GFX_NEXT = '1' then
                            RENDR_GFX_CYCLE      := 0;
                        end if;

                        -- MZ800 LSI renders graphics differently from the other MZ machines. It uses 1 or 2 banks of GRAM and subdivides them into Planes (Colours) and Frames.
                        -- We thus need a different FSM configuration to realise the output.
                        if MODE_VIDEO_MZ800 = '0' then

                            -- Finite state machine to implement read and mapping of the graphics GRAM data.
                            case (RENDR_GFX_CYCLE) is
            
                                when 0 =>
                                    FB_GFX_DATA                  <= (others => '0');

                                    --   Graphics mode:- 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
                                    --                     5 = GRAM Output Enable  0 = active.
                                    --                     4 = VRAM Output Enable, 0 = active.
                                    --                   3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
                                    --                   1/0 = Read mode  (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Not used).
                                    --
                                    -- If graphics are enabled then run the FSM otherwise stay at initial state.
                                    if GRAM_MODE_REG(5) = '0'  then
                                        RENDR_GFX_CYCLE          := 1;
                                    end if;
            
                                -- Setup filters and priority planes prior to data mapping.
                                when 1 =>
            
                                    -- MZ-2000 mode, setup the blend and filter operations.
                                    if MODE_VIDEO_MZ2000 = '1' then

                                        -- Background colour, all off pixels will be set to this colour.
                                        case MZ2K_GRAMCOLRSEL_REG(2 downto 0) is
                                            when "000" =>
                                                FB_RED_BG        <= "00000000";
                                                FB_GREEN_BG      <= "00000000";
                                                FB_BLUE_BG       <= "00000000";
                                            when "001" =>
                                                FB_RED_BG        <= "00000000";
                                                FB_GREEN_BG      <= "00000000";
                                                FB_BLUE_BG       <= "11111111";
                                            when "010" =>
                                                FB_RED_BG        <= "11111111";
                                                FB_GREEN_BG      <= "00000000";
                                                FB_BLUE_BG       <= "00000000";
                                            when "011" =>
                                                FB_RED_BG        <= "11111111";
                                                FB_GREEN_BG      <= "00000000";
                                                FB_BLUE_BG       <= "11111111";
                                            when "100" =>
                                                FB_RED_BG        <= "00000000";
                                                FB_GREEN_BG      <= "11111111";
                                                FB_BLUE_BG       <= "00000000";
                                            when "101" =>
                                                FB_RED_BG        <= "00000000";
                                                FB_GREEN_BG      <= "11111111";
                                                FB_BLUE_BG       <= "11111111";
                                            when "110" =>
                                                FB_RED_BG        <= "11111111";
                                                FB_GREEN_BG      <= "11111111";
                                                FB_BLUE_BG       <= "00000000";
                                            when "111" =>
                                                FB_RED_BG        <= "11111111";
                                                FB_GREEN_BG      <= "11111111";
                                                FB_BLUE_BG       <= "11111111";
                                            when others => null;
                                        end case;

                                        -- Priority colour, character pixel will override the graphic pixel setting for selected colour.
                                        case MZ2K_CRTGRPHPRIO_REG(2 downto 0) is
                                            when "000" =>
                                                FB_RED_PRIO      <= "00000000";
                                                FB_GREEN_PRIO    <= "00000000";
                                                FB_BLUE_PRIO     <= "00000000";
                                            when "001" =>
                                                FB_RED_PRIO      <= "00000000";
                                                FB_GREEN_PRIO    <= "00000000";
                                                FB_BLUE_PRIO     <= "11111111";
                                            when "010" =>
                                                FB_RED_PRIO      <= "11111111";
                                                FB_GREEN_PRIO    <= "00000000";
                                                FB_BLUE_PRIO     <= "00000000";
                                            when "011" =>
                                                FB_RED_PRIO      <= "11111111";
                                                FB_GREEN_PRIO    <= "00000000";
                                                FB_BLUE_PRIO     <= "11111111";
                                            when "100" =>
                                                FB_RED_PRIO      <= "00000000";
                                                FB_GREEN_PRIO    <= "11111111";
                                                FB_BLUE_PRIO     <= "00000000";
                                            when "101" =>
                                                FB_RED_PRIO      <= "00000000";
                                                FB_GREEN_PRIO    <= "11111111";
                                                FB_BLUE_PRIO     <= "11111111";
                                            when "110" =>
                                                FB_RED_PRIO      <= "11111111";
                                                FB_GREEN_PRIO    <= "11111111";
                                                FB_BLUE_PRIO     <= "00000000";
                                            when "111" =>
                                                FB_RED_PRIO      <= "11111111";
                                                FB_GREEN_PRIO    <= "11111111";
                                                FB_BLUE_PRIO     <= "11111111";
                                            when others => null;
                                        end case;

                                        -- Graphic pixel selection.
                                        case MZ2K_CRTGRPHSEL_REG(2 downto 0) is
                                            when "000" =>
                                                FB_RED_PIXEL     <= "00000000";
                                                FB_GREEN_PIXEL   <= "00000000";
                                                FB_BLUE_PIXEL    <= "00000000";
                                            when "001" =>
                                                FB_RED_PIXEL     <= "00000000";
                                                FB_GREEN_PIXEL   <= "00000000";
                                                FB_BLUE_PIXEL    <= reverse_vector(RENDR_GRAM_DATA(15 downto 8));
                                            when "010" =>
                                                FB_RED_PIXEL     <= reverse_vector(RENDR_GRAM_DATA(7 downto 0));
                                                FB_GREEN_PIXEL   <= "00000000";
                                                FB_BLUE_PIXEL    <= "00000000";
                                            when "011" =>
                                                FB_RED_PIXEL     <= reverse_vector(RENDR_GRAM_DATA(7 downto 0));
                                                FB_GREEN_PIXEL   <= "00000000";
                                                FB_BLUE_PIXEL    <= reverse_vector(RENDR_GRAM_DATA(15 downto 8));
                                            when "100" =>
                                                FB_RED_PIXEL     <= "00000000";
                                                FB_GREEN_PIXEL   <= reverse_vector(RENDR_GRAM_DATA(23 downto 16));
                                                FB_BLUE_PIXEL    <= "00000000";
                                            when "101" =>
                                                FB_RED_PIXEL     <= "00000000";
                                                FB_GREEN_PIXEL   <= reverse_vector(RENDR_GRAM_DATA(23 downto 16));
                                                FB_BLUE_PIXEL    <= reverse_vector(RENDR_GRAM_DATA(15 downto 8));
                                            when "110" =>
                                                FB_RED_PIXEL     <= reverse_vector(RENDR_GRAM_DATA(7 downto 0));
                                                FB_GREEN_PIXEL   <= reverse_vector(RENDR_GRAM_DATA(23 downto 16));
                                                FB_BLUE_PIXEL    <= "00000000";
                                            when "111" =>
                                                FB_RED_PIXEL     <= reverse_vector(RENDR_GRAM_DATA(7 downto 0));
                                                FB_GREEN_PIXEL   <= reverse_vector(RENDR_GRAM_DATA(23 downto 16));
                                                FB_BLUE_PIXEL    <= reverse_vector(RENDR_GRAM_DATA(15 downto 8));
                                            when others => null;
                                        end case;
                                    end if;
                                    RENDR_GFX_CYCLE              := 2;

                                when 2 =>
                                    --   Graphics mode:- 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
                                    --                     5 = GRAM Output Enable  0 = active.
                                    --                     4 = VRAM Output Enable, 0 = active.
                                    --                   3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
                                    --                   1/0 = Read mode  (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Not used).
                                    --

                                    -- For MZ80B, render according to the GRAM installed and enabled. Only the GREEN plane is active.
                                    --
                                    if MODE_VIDEO_MZ80B = '1' then
                                        if GRAM_OPT_OUT1 = '1' and GRAM_OPT_OUT2 = '1' then
                                            FB_GFX_DATA(23 downto 16)<= FB_GFX_DATA(23 downto 16) or (reverse_vector(RENDR_GRAM_DATA(7 downto 0)) or reverse_vector(RENDR_GRAM_DATA(15 downto 8)));
                                        elsif GRAM_OPT_OUT1 = '1' then
                                            FB_GFX_DATA(23 downto 16)<= FB_GFX_DATA(23 downto 16) or reverse_vector(RENDR_GRAM_DATA(7 downto 0));
                                        elsif GRAM_OPT_OUT2 = '1' then
                                            FB_GFX_DATA(23 downto 16)<= FB_GFX_DATA(23 downto 16) or reverse_vector(RENDR_GRAM_DATA(15 downto 8));
                                        end if;

                                    -- For MZ2000, store the pixels in reverse order within a byte compared to the rasterised character, ie. MSB-7654321 instead of MSB-01234567 so reverse the order for display.
                                    -- Filters and priority are applied on plane blending.
                                    elsif MODE_VIDEO_MZ2000 = '1' then
                                        FB_GFX_DATA              <= X"00" & FB_GREEN_PIXEL & FB_BLUE_PIXEL & FB_RED_PIXEL;

                                    -- Other machines can use the full graphics facilities of the Video Controller.
                                    else

                                        -- Direct output from GRAM. Actual blending according to the MODE register is achieved when blending the character and OSD planes.
                                        --
                                        FB_GFX_DATA              <= X"00" & RENDR_GRAM_DATA(23 downto 16) & RENDR_GRAM_DATA(15 downto 8) & RENDR_GRAM_DATA(7 downto 0);
                                    end if;

                                    RENDR_GFX_CYCLE              := 0;

                                -- Unused states restart at 0.
                                when others =>
                                    RENDR_GFX_CYCLE              := 0;
            
                            end case;

                        else -- MZ800 Mode

                            -- Calculate the Direct Mapping Address based on the current CPU address.
                   --         if GD_DMD_640X200 = '1' then
                   --             FB_DMA_ADDR                   <= '0' & FB_GFX_ADDR(12 downto 0);
                     --           if (GD_SSA & "000000") <= FB_GFX_ADDR(12 downto 0) and FB_GFX_ADDR(12 downto 0) < (GD_SEA & "000000") then
                     --               if (FB_GFX_ADDR(12 downto 0) + (GD_SOF & "000")) >= (GD_SEA & "000000") then
                     --                   FB_DMA_ADDR           <= '0' & FB_GFX_ADDR(12 downto 0) + (GD_SOF & "000") - (GD_SEA & "000000");
                     --               else
                     --                   FB_DMA_ADDR           <= '0' & FB_GFX_ADDR(12 downto 0) + (GD_SOF & "000");
                     --               end if;
                     --           end if;
                  --          else
                  --              FB_DMA_ADDR                   <= "00" & FB_GFX_ADDR(11 downto 0);
                     --           if (GD_SSA & "00000") <= FB_GFX_ADDR(11 downto 0) and FB_GFX_ADDR(11 downto 0) < (GD_SEA & "00000") then
                     --               if (FB_GFX_ADDR(11 downto 0) + (GD_SOF & "00")) >= (GD_SEA & "00000") then
                     --                   FB_DMA_ADDR(11 downto 0) <= FB_GFX_ADDR(11 downto 0) + (GD_SOF & "00") - (GD_SEA & "00000");
                     --               else
                     --                   FB_DMA_ADDR(11 downto 0) <= FB_GFX_ADDR(11 downto 0) + (GD_SOF & "00");
                     --               end if;
                     --           end if;
                  --          end if;

                            -- Finite state machine to implement read and mapping of the graphics GRAM data.
                            case (RENDR_GFX_CYCLE) is
            
                                when 0 =>
                                    FB_GFX_DATA                  <= (others => '0');

                                    -- Setup the starting byte address in the first plane.
                                    FB_GFX_LOADDR                <= "00";

                                    --   Graphics mode:- 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
                                    --                     5 = GRAM Output Enable  0 = active.
                                    --                     4 = VRAM Output Enable, 0 = active.
                                    --                   3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
                                    --                   1/0 = Read mode  (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Not used).
                                    --
                                    -- If graphics are enabled then run the FSM otherwise stay at initial state.
                                    if GRAM_MODE_REG(5) = '0'  then
                                        RENDR_GFX_CYCLE          := 1;
                                    end if;

                                when 1 =>
                                    -- Save the first plane data.
                                    if (GD_DMD_320X200 = '1' and FB_GFX_MUXADDR(14) = '0') or (GD_DMD_640X200 = '1'  and FB_GFX_MUXADDR(14) = '0') then
                                        FB_GFX_DATA              <= X"0000" & reverse_vector(RENDR_GRAM_DATA(7 downto 0))  & X"00";
                                    else
                                        FB_GFX_DATA              <= X"0000" & reverse_vector(RENDR_GRAM_DATA(15 downto 8)) & X"00";
                                    end if;

                                    -- Setup for the next plane.
                                    FB_GFX_LOADDR                <= FB_GFX_LOADDR + 1;

                                    -- If in 640x200 mode and the second RAM bank has not been installed, no more processing needed.
                                    if GD_DMD_640X200 = '1' and CONFIG(OPT_MZ1R25) = '0' then
                                        RENDR_GFX_CYCLE          := 0;
                                    else
                                        RENDR_GFX_CYCLE          := 2;
                                    end if;

                                when 2 =>
                                    -- Save the second plane data.
                                    if GD_DMD_640X200 = '1' then
                                        -- 640x200 mode, second plane is plane III, from either bank.
                                        if FB_GFX_MUXADDR(14) = '0' then
                                            FB_GFX_DATA          <= X"00" & reverse_vector(RENDR_GRAM_DATA(7 downto 0)) & FB_GFX_DATA(15 downto 8) & X"00";
                                        else
                                            FB_GFX_DATA          <= X"00" & reverse_vector(RENDR_GRAM_DATA(15 downto 8)) & FB_GFX_DATA(15 downto 8) & X"00";
                                        end if;
                                        RENDR_GFX_CYCLE          := 0;
                                    elsif (GD_DMD_320X200 = '1' and FB_GFX_MUXADDR(14) = '0') then
                                        FB_GFX_DATA              <= X"0000" & FB_GFX_DATA(15 downto 8) & reverse_vector(RENDR_GRAM_DATA(7 downto 0));
                                        RENDR_GFX_CYCLE          := 3;
                                    elsif (GD_DMD_320X200 = '1' and FB_GFX_MUXADDR(14) = '1') then
                                        FB_GFX_DATA              <= X"0000" & FB_GFX_DATA(15 downto 8) & reverse_vector(RENDR_GRAM_DATA(15 downto 8));

                                        -- If second RAM bank hasnt been installed, exit here.
                                        if GD_DMD_320X200 = '1' and CONFIG(OPT_MZ1R25) = '0' then
                                            RENDR_GFX_CYCLE      := 3;
                                        else
                                            RENDR_GFX_CYCLE      := 3;
                                        end if;
                                    else
                                        -- 640x200 mode, second plane is actually plane III.
                                        FB_GFX_DATA              <= X"00" & reverse_vector(RENDR_GRAM_DATA(15 downto 8)) & FB_GFX_DATA(15 downto 8) & X"00";
                                        RENDR_GFX_CYCLE          := 0;
                                    end if;

                                    -- Setup for the next plane.
                                    FB_GFX_LOADDR                <= FB_GFX_LOADDR + 1;

                                when 3 =>
                                    -- Save the third plane, only active in 320X200 mode.
                                    if FB_GFX_MUXADDR(14) = '0' then
                                        FB_GFX_DATA              <= X"00" & reverse_vector(RENDR_GRAM_DATA(7 downto 0)) & FB_GFX_DATA(15 downto 0);
                                    else
                                        FB_GFX_DATA              <= X"00" & reverse_vector(RENDR_GRAM_DATA(15 downto 8)) & FB_GFX_DATA(15 downto 0);
                                    end if;
                                    RENDR_GFX_CYCLE              := 4;

                                    -- Setup for the next plane.
                                    FB_GFX_LOADDR                <= FB_GFX_LOADDR + 1;

                                when 4 =>
                                    -- Save the fourth plane, only active in 320X200 mode.
                                    if FB_GFX_MUXADDR(14) = '0' then
                                        FB_GFX_DATA              <= reverse_vector(RENDR_GRAM_DATA(7 downto 0)) & FB_GFX_DATA(23 downto 0);
                                    else
                                        FB_GFX_DATA              <= reverse_vector(RENDR_GRAM_DATA(15 downto 8)) & FB_GFX_DATA(23 downto 0);
                                    end if;
                                    RENDR_GFX_CYCLE              := 0;

                                -- Unused states restart at 0.
                                when others =>
                                    RENDR_GFX_CYCLE              := 0;
            
                            end case;
                        end if;
                    end if;
                end if;
            end if; -- if VRESET
        end if; end if; -- VID_CE, rising_edge(SYS_CLK)
    end process;

    -- Process to generate the video data signals.
    -- The data is read out of the framebuffer, 8 pixels at a time and clocked out according to the timing clock. The H/V Sync and Blank signals are
    -- activated according to the mode selected and the values contained therein.
    --
    GENVIDEO: process( VRESETn, SYS_CLK, VIDEOMODE_RESET_TIMER )
        variable VIDEOTIMING         : integer;
        variable VIDEOTIMING_SWITCH  : std_logic;                            -- Video timing change detected, waiting for current display to complete before change.
        variable VIDEOTIMING_NEXT    : integer;
    begin

        -- Use the video clock for rendering to get the correct display frequencies.
        if rising_edge(SYS_CLK) then if VID_CE = '1' then

            -- On reset, set the basic parameters which hold the video signal generator in reset
            -- then load up the required parameter set and generate the video signal.
            --
            if VRESETn = '0' then
                    H_DSP_START                      <= (others => '0');
                    H_DSP_END                        <= (others => '0');
                    H_DSP_WND_START                  <= (others => '0');
                    H_DSP_WND_END                    <= (others => '0');
                    V_DSP_START                      <= (others => '0');
                    V_DSP_END                        <= (others => '0');
                    V_DSP_WND_START                  <= (others => '0');
                    V_DSP_WND_END                    <= (others => '0');
                    MAX_COLUMN                       <= (others => '0');
                    H_LINE_END                       <= (others => '0');
                    V_LINE_END                       <= (others => '0');
                    H_SYNC_START                     <= (others => '0');
                    H_SYNC_END                       <= (others => '0');
                    V_SYNC_START                     <= (others => '0');
                    V_SYNC_END                       <= (others => '0');
                    H_BLANK_START                    <= (others => '0');
                    H_BLANK_END                      <= (others => '0');
                    V_BLANK_START                    <= (others => '0');
                    V_BLANK_END                      <= (others => '0');
                    H_POLARITY                       <= (others => '0');
                    V_POLARITY                       <= (others => '0');
                    H_CPX                            <= (others => '0');
                    V_CPX                            <= (others => '0');
                    H_GPX                            <= (others => '0');
                    V_GPX                            <= (others => '0');
                    H_OPX                            <= (others => '0');
                    V_OPX                            <= (others => '0');
                    H_COUNT                          <= (others => '0');
                    V_COUNT                          <= (others => '0');
                    CLOCKSEL                         <= SEL_CLOCK_8MHZ;
                    H_BLANKi                         <= '1';
                    V_BLANKi                         <= '1';
                    H_SYNCni                         <= '1';
                    V_SYNCni                         <= '1';
                    H_CPX_CNT                        <= 0;
                  --  V_CPX_CNT                        <= 0;
                    H_GPX_CNT                        <= 0;
                    V_GPX_CNT                        <= 0;
                    H_OPX_CNT                        <= 0;
                    V_OPX_CNT                        <= 0;
                    H_CHR_SHIFT_CNT                  <= 0;
                    H_GFX_SHIFT_CNT                  <= 0;
                    FB_GFX_ADDR                      <= (others => '0');
                    FB_OSD_ADDR                      <= (others => '0');
                    VIDEOMODE_SWITCH                 <= '0';
                    VIDEOMODE                        <= 0;
                    VIDEOMODE_RESET_TIMER            <= (others => '1');
                    VIDCLK_DIV                       <= '0';
                    RENDR_CHR_NEXT                   <= '1';
                    RENDR_GFX_NEXT                   <= '1';
                    VIDEOTIMING_SWITCH               := '0';

            else

                -- The video clock is running at twice the display frequency to provide additional edges for rendering the display during the blanking periods.
                -- We therefore divide the clock by two and only act on the second edge in 2 edges.
                VIDCLK_DIV                           <= not VIDCLK_DIV;

                -- Render next byte signal is only 1 clock width wide, triggers the assembly of the next 8 pixels for display.
                RENDR_CHR_NEXT                       <= '0';
                RENDR_GFX_NEXT                       <= '0';

                -- Detect the menu/status buffer change via edge change.
                MENUENABLE_LAST                      <= VGA_ATTR_REG(6);
                STATUSENABLE_LAST                    <= VGA_ATTR_REG(7);
                if VGA_ATTR_REG(6) /= MENUENABLE_LAST or VGA_ATTR_REG(7) /= STATUSENABLE_LAST then
                    H_MNU_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING,  4), H_MNU_START'length            );
                    H_MNU_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING,  5), H_MNU_END'length              );
                    H_HDR_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING,  6), H_HDR_START'length            );
                    H_HDR_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING,  7), H_HDR_END'length              );
                    H_FTR_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING,  8), H_FTR_START'length            );
                    H_FTR_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING,  9), H_FTR_END'length              );
                    V_MNU_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING, 14), V_MNU_START'length            );
                    V_MNU_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING, 15), V_MNU_END'length              );
                    V_HDR_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING, 16), V_HDR_START'length            );
                    V_HDR_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING, 17), V_HDR_END'length              );
                    V_FTR_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING, 18), V_FTR_START'length            );
                    V_FTR_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING, 19), V_FTR_END'length              );
                end if;

                -- Pointers into the timing array based on selected video mode.
                VIDEOTIMING                          := FB_VIDEOMODE(VIDEOMODE, 0);
                VIDEOTIMING_NEXT                     := FB_VIDEOMODE(VIDEOMODE_NEXT, 0);

                -- If the video timing changes, we wait until the current frame has been displayed then commence switching to the new video settings.
                if VIDEOTIMING /= VIDEOTIMING_NEXT then
                    VIDEOTIMING_SWITCH               := '1';
                end if;

                -- Load up the video mode specific paramters.
                if VIDEOTIMING_SWITCH = '1' or VIDEOMODE /= VIDEOMODE_NEXT or MAX_COLUMN = 0 then
                    MAX_COLUMN                       <= to_unsigned(FB_VIDEOMODE(VIDEOMODE_NEXT,  1),  MAX_COLUMN'length       ); 
                    H_CPX                            <= to_unsigned(FB_VIDEOMODE(VIDEOMODE_NEXT,  2),  H_CPX'length            );   
                    V_CPX                            <= to_unsigned(FB_VIDEOMODE(VIDEOMODE_NEXT,  3),  V_CPX'length            );   
                    H_GPX                            <= to_unsigned(FB_VIDEOMODE(VIDEOMODE_NEXT,  4),  H_GPX'length            );   
                    V_GPX                            <= to_unsigned(FB_VIDEOMODE(VIDEOMODE_NEXT,  5),  V_GPX'length            );   
                    H_OPX                            <= to_unsigned(FB_VIDEOMODE(VIDEOMODE_NEXT,  6),  H_OPX'length            );   
                    V_OPX                            <= to_unsigned(FB_VIDEOMODE(VIDEOMODE_NEXT,  7),  V_OPX'length            );   
                    VIDEOMODE                        <= VIDEOMODE_NEXT;
                end if;

                -- As per the video mode, if the video timing signals change, perform the change at the end of a display frame to aid monitor sync.
                --
                if (VIDEOTIMING_SWITCH = '1' and V_COUNT = V_LINE_END) or MAX_COLUMN = 0
                then
                    VIDEOTIMING_SWITCH               := '0';

                    --         0            1          2             3               4            5           6          7          8            9           10         11             12            13            14            15         16           17          18           19         20            21     22     23            24                 25               26          27             28           29             30            31          32
                    --   H_DSP_START, H_DSP_END, H_DSP_WND_START, H_DSP_WND_END, H_MNU_START, H_MNU_END, H_HDR_START, H_HDR_END, H_FTR_START, H_FTR_END, V_DSP_START, V_DSP_END, V_DSP_WND_START, V_DSP_WND_END, V_MNU_START, V_MNU_END, V_HDR_START, V_HDR_END, V_FTR_START, V_FTR_END, H_LINE_END, V_LINE_END, CLOCK,  H_SYNC_START, H_SYNC_END,      V_SYNC_START,    V_SYNC_END,   H_BLANK_START, H_BLANK_END, V_BLANK_START, V_BLANK_END,  H_POLARITY, V_POLARITY
                    --
                    --         0                      1           2      3      4      5      6      7
                    --      VIDEOTIMING,              MAX_COLUMN, H_CPX, V_CPX, H_GPX, V_GPX, H_OPX, V_OPX        -- Mode | Description
                    -- Iniitialise control registers.
                    --
                    FB_GFX_ADDR                      <= (others => '0');
                    FB_OSD_ADDR                      <= (others => '0');
                    RENDR_CHR_NEXT                   <= '1';
                    RENDR_GFX_NEXT                   <= '1';
    
                    -- Load up configuration from the timing look up table based on video mode.
                    --
                    H_DSP_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,   0),  H_DSP_START'length      );    
                    H_DSP_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,   1),  H_DSP_END'length        );    
                    H_DSP_WND_START                  <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,   2),  H_DSP_WND_START'length  );    
                    H_DSP_WND_END                    <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,   3),  H_DSP_WND_END'length    );    
                    H_MNU_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,   4),  H_MNU_START'length      );    
                    H_MNU_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,   5),  H_MNU_END'length        );    
                    H_HDR_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,   6),  H_HDR_START'length      );    
                    H_HDR_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,   7),  H_HDR_END'length        );    
                    H_FTR_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,   8),  H_FTR_START'length      );    
                    H_FTR_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,   9),  H_FTR_END'length        );    
                    V_DSP_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  10),  V_DSP_START'length      );    
                    V_DSP_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  11),  V_DSP_END'length        );    
                    V_DSP_WND_START                  <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  12),  V_DSP_WND_START'length  );    
                    V_DSP_WND_END                    <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  13),  V_DSP_WND_END'length    );    
                    V_MNU_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  14),  V_MNU_START'length      );    
                    V_MNU_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  15),  V_MNU_END'length        );    
                    V_HDR_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  16),  V_HDR_START'length      );    
                    V_HDR_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  17),  V_HDR_END'length        );    
                    V_FTR_START                      <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  18),  V_FTR_START'length      );    
                    V_FTR_END                        <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  19),  V_FTR_END'length        );    
                    H_LINE_END                       <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  20),  H_LINE_END'length       );    
                    V_LINE_END                       <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  21),  V_LINE_END'length       );    
                    CLOCKSEL                         <=             FB_TIMING(VIDEOTIMING_NEXT,  22                            );    
                    H_SYNC_START                     <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  23),  H_SYNC_START'length     );    
                    H_SYNC_END                       <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  24),  H_SYNC_END'length       );    
                    V_SYNC_START                     <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  25),  V_SYNC_START'length     );    
                    V_SYNC_END                       <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  26),  V_SYNC_END'length       );    
                    H_BLANK_START                    <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  27),  H_BLANK_START'length    );    
                    H_BLANK_END                      <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  28),  H_BLANK_END'length      );    
                    V_BLANK_START                    <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  29),  V_BLANK_START'length    );    
                    V_BLANK_END                      <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  30),  V_BLANK_END'length      );    
                    H_POLARITY                       <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  31),  H_POLARITY'length       );    
                    V_POLARITY                       <= to_unsigned(FB_TIMING(VIDEOTIMING_NEXT,  32),  V_POLARITY'length       );    
                    --
                    H_COUNT                          <= (others => '0');
                    V_COUNT                          <= (others => '0');
                    H_BLANKi                         <= '1';
                    V_BLANKi                         <= '1';
                    if FB_TIMING(VIDEOTIMING_NEXT, 27) = 1 then H_SYNCni <= '0'; else H_SYNCni <= '1'; end if;
                    if FB_TIMING(VIDEOTIMING_NEXT, 28) = 1 then V_SYNCni <= '0'; else V_SYNCni <= '1'; end if;
                    H_CPX_CNT                        <= 0;
                    H_GPX_CNT                        <= 0;
                    V_GPX_CNT                        <= FB_VIDEOMODE(VIDEOMODE_NEXT,  5); --0;
                    H_OPX_CNT                        <= 0;
                    V_OPX_CNT                        <= FB_VIDEOMODE(VIDEOMODE_NEXT,  7);   
                    H_CHR_SHIFT_CNT                  <= 0;
                    H_GFX_SHIFT_CNT                  <= 0;
                    --
                    -- On display start or change we need to give a small period between one set of frequencies/display settings and the next.
                    -- This is necessary as I've noticed on one of my displays that changing modes too quickly results in lock up - probably a bug
                    -- of my monitor but this ensures other monitors arent affected either.
                    VIDEOMODE_RESET_TIMER            <= (others => '1');
                    --
                    VIDCLK_DIV                       <= '0';

                -- During reset periods, just count down, no active display signals will be generated.
                elsif VIDEOMODE_RESET_TIMER /= 0 then
                    VIDEOMODE_RESET_TIMER            <= VIDEOMODE_RESET_TIMER - 1;
                    --
                    VIDCLK_DIV                       <= '0';

                -- Only process the display output on the second of each video clock edges as the video clock is running at 2x frequency.
                --
                elsif VIDCLK_DIV = '1' then

                    -- Activate/deactivate signals according to pixel position.
                    --
                    if H_COUNT =  H_BLANK_START   then H_BLANKi  <= '0'; end if;
                    if H_COUNT =  H_BLANK_END     then H_BLANKi  <= '1'; end if;
                    --
                    if H_COUNT =  H_SYNC_END      then H_SYNCni  <= '1'; end if;
                    if H_COUNT =  H_SYNC_START    then H_SYNCni  <= '0'; end if;
                    --
                    if V_COUNT =  V_BLANK_START   then V_BLANKi  <= '0'; end if;
                    if V_COUNT =  V_BLANK_END     then V_BLANKi  <= '1'; end if;
                    --
                    if V_COUNT =  V_SYNC_START    then V_SYNCni  <= '0'; end if;
                    if V_COUNT =  V_SYNC_END      then V_SYNCni  <= '1'; end if;
    
                    -- If we are in the active visible area, stream the required output based on the various buffers.
                    --
                    if H_COUNT >= H_DSP_START and H_COUNT < H_DSP_END and V_COUNT >= V_DSP_START and V_COUNT < V_DSP_END then
    
                        -------------------------------------
                        -- Character Plane generation      --
                        -------------------------------------
                        -- During the active window output serialised character data else output border data in the unused displayable area..
                        if (V_COUNT >= V_DSP_WND_START(V_DSP_WND_START'length-1 downto 3)&"000" and V_COUNT < V_DSP_WND_END(V_DSP_WND_END'length-1 downto 3)&"000") and (H_COUNT >= H_DSP_WND_START and H_COUNT < H_DSP_WND_END) then

                            -- Update Horizontal Pixel multiplier.
                            --
                            if H_CPX_CNT = 0 then
    
                                H_CPX_CNT            <= to_integer(H_CPX);
                                H_CHR_SHIFT_CNT      <= H_CHR_SHIFT_CNT - 1;
    
                                -- Main screen.
                                --
                                if H_CHR_SHIFT_CNT = 0 then
    
                                    -- During the visible portion of the frame, data is generated by the render logic in bytes, 1 bit per pixel x 8 and 3 colors,
                                    -- thus 1 x 8 x 3 or 24 bit. Read out the values into shift registers to be serialised.
                                    --
                                    SR_R_CHR         <= FB_CHR_DATA( 7 downto 0);
                                    SR_B_CHR         <= FB_CHR_DATA(15 downto 8);
                                    SR_G_CHR         <= FB_CHR_DATA(23 downto 16);
                                    RENDR_CHR_NEXT   <= '1';

                                else
                                    -- During the active display area, if the shift counter is not 0 and the horizontal multiplier is equal to the setting,
                                    -- shift the data in the shift register to display the next pixel.
                                    --
                                    SR_R_CHR         <= SR_R_CHR(6 downto 0) & '0';
                                    SR_B_CHR         <= SR_B_CHR(6 downto 0) & '0';
                                    SR_G_CHR         <= SR_G_CHR(6 downto 0) & '0';
    
                                end if;
                            else
                                H_CPX_CNT            <= H_CPX_CNT - 1;
                            end if;
                        else
                            -- Blank.
                            --
                            SR_G_CHR                 <= (others => VGA_ATTR_REG(2));
                            SR_R_CHR                 <= (others => VGA_ATTR_REG(1));
                            SR_B_CHR                 <= (others => VGA_ATTR_REG(0));
                            H_CPX_CNT                <= 0;
                            H_CHR_SHIFT_CNT          <= 0;
                        end if;

                        --------------------------------------
                        -- Pixel Graphics Plane generation  --
                        --------------------------------------
                        -- During the active window serialise the pixel graphics frame buffer. The data is serialised in 8pixel blocks per colour and blended with the character/OSD pixels prior to palette mapping and display.
                        if (V_COUNT >= V_DSP_WND_START(V_DSP_WND_START'length-1 downto 3)&"000" and V_COUNT < V_DSP_WND_END(V_DSP_WND_END'length-1 downto 3)&"000") and (H_COUNT >= H_DSP_WND_START and H_COUNT < H_DSP_WND_END) then

                            -- Update Horizontal Pixel multiplier.
                            --
                            if H_GPX_CNT = 0 then
    
                                H_GPX_CNT            <= to_integer(H_GPX);
                                H_GFX_SHIFT_CNT      <= H_GFX_SHIFT_CNT - 1;
    
                                -- Main screen.
                                --
                                if H_GFX_SHIFT_CNT = 0 then
    
                                    -- During the visible portion of the frame, data is generated by the render logic in bytes, 1 bit per pixel x 8 and 3 colors,
                                    -- thus 1 x 8 x 3 or 24 bit. Read out the values into shift registers to be serialised.
                                    --
                                    SR_R_GFX         <= FB_GFX_DATA( 7 downto 0);
                                    SR_B_GFX         <= FB_GFX_DATA(15 downto 8);
                                    SR_G_GFX         <= FB_GFX_DATA(23 downto 16);
                                    SR_I_GFX         <= FB_GFX_DATA(31 downto 24);
                                    FB_GFX_ADDR      <= FB_GFX_ADDR + 1;
                                    RENDR_GFX_NEXT   <= '1';

                                else
                                    -- During the active display area, if the shift counter is not 0 and the horizontal multiplier is equal to the setting,
                                    -- shift the data in the shift register to display the next pixel.
                                    --
                                    SR_R_GFX         <= SR_R_GFX(6 downto 0) & '0';
                                    SR_B_GFX         <= SR_B_GFX(6 downto 0) & '0';
                                    SR_G_GFX         <= SR_G_GFX(6 downto 0) & '0';
                                    SR_I_GFX         <= SR_I_GFX(6 downto 0) & '0';
    
                                end if;
                            else
                                H_GPX_CNT            <= H_GPX_CNT - 1;
                            end if;
                        else
                            -- MZ800 mode outputs the border colour in the unused areas, else blank for all other modes..
                            --
                            if MODE_VIDEO_MZ800 = '1' then
                                SR_G_GFX             <= (others => GD_BCOL(2));
                                SR_R_GFX             <= (others => GD_BCOL(1));
                                SR_B_GFX             <= (others => GD_BCOL(0));
                                SR_I_GFX             <= (others => GD_BCOL(3));
                            else
                                SR_G_GFX             <= (others => '0');
                                SR_R_GFX             <= (others => '0');
                                SR_B_GFX             <= (others => '0');
                                SR_I_GFX             <= (others => '0');
                            end if;
                            H_GPX_CNT                <= 0;
                            H_GFX_SHIFT_CNT          <= 0;
                        end if;

                        --------------------------------------
                        -- OSD Menu/Status Plane generation --
                        --------------------------------------
                        -- If the Status areas or the menu is enabled, create a data stream for the status/menu data to be merged with the main data.
                        --
                        if VGA_ATTR_REG(6) = '1' or VGA_ATTR_REG(7) = '1' then

                            -- Update the shift register contents only when the horizontal multiplier is 0.
                            --
                            if H_OPX_CNT = 0 then

                                H_OPX_CNT            <= to_integer(H_OPX);
                                H_OSD_SHIFT_CNT      <= H_OSD_SHIFT_CNT - 1;

                                -- On each reset of the shift counter, load up Menu, Header, Footer or blank data to be serialised.
                                --
                                if H_OSD_SHIFT_CNT = 0 then

                                    -- OSD Menu
                                    --
                                    if VGA_ATTR_REG(6) = '1'
                                       and
                                       ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT < H_MNU_END)) then
        
                                        SR_G_OSD     <= FB_OSD_DATA( 7 downto 0);
                                        SR_R_OSD     <= FB_OSD_DATA(15 downto 8);
                                        SR_B_OSD     <= FB_OSD_DATA(23 downto 16);
                                      --SR_G_CHR     <= (others => VGA_ATTR_REG(2));
                                      --SR_R_CHR     <= (others => VGA_ATTR_REG(1));
                                      --SR_B_CHR     <= (others => VGA_ATTR_REG(0));
                                        FB_OSD_ADDR  <= FB_OSD_ADDR + 1;
        
                                    -- OSD Status Header/Footer
                                    --
                                    elsif VGA_ATTR_REG(7) = '1'
                                          and
                                          (((H_HDR_START /= H_HDR_END) and ((V_COUNT >= V_HDR_START and V_COUNT < V_HDR_END) and (H_COUNT >= H_HDR_START and H_COUNT < H_HDR_END)))
                                            or
                                           ((H_FTR_START /= H_FTR_END) and ((V_COUNT >= V_FTR_START and V_COUNT < V_FTR_END) and (H_COUNT >= H_FTR_START and H_COUNT < H_FTR_END)))) then
           
                                        -- During the visible portion of the unused header/footer, read out the status frame buffer, 1 bit per pixel x 8 and 3 colours.
                                        --
                                        SR_G_OSD     <= FB_OSD_DATA( 7 downto 0);
                                        SR_R_OSD     <= FB_OSD_DATA(15 downto 8);
                                        SR_B_OSD     <= FB_OSD_DATA(23 downto 16);
                                        FB_OSD_ADDR  <= FB_OSD_ADDR + 1;
        
                                    -- Blank.
                                    --
                                    else
                                        SR_G_OSD     <= (others => '0');
                                        SR_R_OSD     <= (others => '0');
                                        SR_B_OSD     <= (others => '0');
                                        H_OSD_SHIFT_CNT<= 0;
                                    end if;
        
                                -- Shift on each clock cycle to next active bit if not at start.
                                --
                                else 
                                    SR_G_OSD         <= SR_G_OSD(6 downto 0) & '0';
                                    SR_R_OSD         <= SR_R_OSD(6 downto 0) & '0';
                                    SR_B_OSD         <= SR_B_OSD(6 downto 0) & '0';
                                end if;
                            else
                                H_OPX_CNT            <= H_OPX_CNT - 1;
                            end if;
                        else
                            -- Blank.
                            --
                            SR_G_OSD                 <= (others => '0');
                            SR_R_OSD                 <= (others => '0');
                            SR_B_OSD                 <= (others => '0');
                            H_OPX_CNT                <= 0;
                            H_OSD_SHIFT_CNT          <= 0;
                        end if;
                    else
                        H_CPX_CNT                    <= 0;
                        H_GPX_CNT                    <= 0;
                        H_OPX_CNT                    <= 0;
                        H_CHR_SHIFT_CNT              <= 0;
                        H_GFX_SHIFT_CNT              <= 0;
                        H_OSD_SHIFT_CNT              <= 0;
                    end if;

                    -- Vertical counters are updated near line end to allow time for the address/counters to change and be rendered before the next frame.
                    --
                    if H_COUNT = H_LINE_END-16 then

                        -- Update Vertical OSD pixels multiplier.
                        --
                        if V_OPX_CNT = 0 then
                            V_OPX_CNT                <= to_integer(V_OPX);
                        else
                            V_OPX_CNT                <= V_OPX_CNT - 1;
                        end if;

                        -- Update Vertical graphics pixel multiplier.
                        --
                        if V_COUNT >= V_DSP_WND_START and V_COUNT < V_DSP_WND_END then
                            if V_GPX_CNT = 0 then
                                V_GPX_CNT            <= to_integer(V_GPX);
                            else
                                V_GPX_CNT            <= V_GPX_CNT - 1;
                            end if;
                        end if;

                        -- Character vertical pixels are multiplied in the rendering stage.
    
                        -- When we need to repeat a line due to pixel multiplying, wind back the framebuffer address to start of line.
                        --
                        if V_COUNT >= V_DSP_WND_START and V_COUNT < V_DSP_WND_END and V_GPX /= 0 and V_GPX_CNT > 0 then
                            if MODE_VIDEO_MZ80B = '1' then
                                FB_GFX_ADDR          <= FB_GFX_ADDR - 40;
                            elsif MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1' then
                                FB_GFX_ADDR          <= FB_GFX_ADDR - 80;
                            else
                                FB_GFX_ADDR          <= FB_GFX_ADDR - to_integer(MAX_COLUMN);
                            end if;
                        end if;
    
                        -- For VGA, expand the OSD vertical pixels according to setting.
                        --
                        if VGA_ATTR_REG(6) = '1' and (V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and V_OPX /= 0 and V_OPX_CNT > 0 then
                            --FB_OSD_ADDR              <= FB_OSD_ADDR - (to_integer((H_MNU_END and H_MNU_START))/8);
                            FB_OSD_ADDR              <= FB_OSD_ADDR - (to_integer((H_MNU_END - H_MNU_START))/8);
                        end if;                        

                        -- Once we have reached the end of the active vertical display, reset the framebuffer address.
                        --
                        if V_COUNT = V_DSP_END then
                            FB_GFX_ADDR              <= (others => '0');
                            FB_OSD_ADDR              <= (others => '0');
                            RENDR_CHR_NEXT           <= '1';
                        end if;
    
                        -- End of vertical line, increment to next or reset to beginning.
                        --
                        if V_COUNT = V_LINE_END then
                            V_COUNT                  <= (others => '0');
                            V_GPX_CNT                <= to_integer(V_GPX); --0;
                            V_OPX_CNT                <= to_integer(V_OPX);
                        else
                            V_COUNT                  <= V_COUNT + 1;
                        end if;

                        -- End of line, start the rendering of the next graphics pixel set.
                        RENDR_GFX_NEXT               <= '1';

                    end if;

                    -- Horizontal counters are update at line end ready for the next frame.
                    --
                    if H_COUNT = H_LINE_END then
                        H_COUNT                      <= (others => '0');
                        H_CPX_CNT                    <= 0;
                        H_GPX_CNT                    <= 0;
                        H_OPX_CNT                    <= 0;

                    else
                        H_COUNT                      <= H_COUNT + 1;
                    end if;
                end if;
            end if; -- if VRESETn
        end if; end if; -- VID_CE, rising_edge(SYS_CLK)
    end process;

    -- MZ800 CRTC LSI.
    --
    -- This process emulates the graphics components of the MZ800 CRTC LSI circuit. The rendering is done by the Graphics Render process.
    --
    CRTCLSI: process( VRESETn, SYS_CLK )
    begin
        -- System clock is used to obtain best performance for the LSI controller. The CPU writes/reads a register which behind the scenes is
        -- GRAM data with logic applied.
        if rising_edge(SYS_CLK) then
           
            -- Ensure default values at reset.
            if VRESETn='0' then
                GD_CPUADDR         <= (others => '0');                     -- Register to store the CPU address for a read/write operation.
                GD_CPUWRDATA       <= (others => '0');                     -- Register to store data for writing into the graphics RAM.
                GD_CPURDDATA       <= (others => '0');                     -- Register to store data read from the graphics RAM.
                GD_O_DATA          <= (others => '0');                     -- Register for storing updated data to be written to GRAM.
                GD_WEN_GI          <= '0';                                 -- Signal to indicate a write operation needed into GRAM Bank 1.
                GD_WEN_GII         <= '0';                                 -- Signal to indicate a write operation needed into GRAM Bank 2.
                GDMD_REG           <= "00001000";                          -- Graphics Display LSI Command Register. Default to MZ700 mode.
                GRF_REG            <= (others => '0');                     -- Graphics Display LSI Read Format Register.
                GWF_REG            <= (others => '0');                     -- Graphics Display LSI Write Format Register.
                GPALLET_REG        <= (X"9", X"F", X"9", X"F");            -- Graphics Display LSI Pallet Register: mz800emu's power-on
                                                                           -- values (gdg_init); Planetoids sets only palette 0 and draws in 1-3.
                GD_SOF             <= std_logic_vector(to_unsigned(0, GD_SOF'length)); -- Scroll offset regiser (SOF) 10 bits.
                GD_SW              <= std_logic_vector(to_unsigned(0, GD_SW'length));  -- Scroll width regiser (SW), 7 bits
                GD_SSA             <= std_logic_vector(to_unsigned(0, GD_SSA'length)); -- Scroll start address register (SSA), 7 bits
                GD_SEA             <= std_logic_vector(to_unsigned(0, GD_SEA'length)); -- Scroll end address register (SEA), 7 bits
                GD_WR_FRAME_A      <= '0';                                 -- Signal to make logic more readable.
                GD_WR_FRAME_B      <= '0';                                 -- 
                GD_WR_FRAME_AB     <= '0';                                 -- 
                GD_WR_PLANE_I      <= '0';                                 -- 
                GD_WR_PLANE_II     <= '0';                                 -- 
                GD_WR_PLANE_III    <= '0';                                 -- 
                GD_WR_PLANE_IV     <= '0';                                 -- 
                GD_RD_FRAME_A      <= '0';                                 -- 
                GD_RD_FRAME_B      <= '0';                                 -- 
                GD_RD_FRAME_AB     <= '0';                                 -- 
                GD_RD_PLANE_I      <= '0';                                 -- 
                GD_RD_PLANE_II     <= '0';                                 -- 
                GD_RD_PLANE_III    <= '0';                                 -- 
                GD_RD_PLANE_IV     <= '0';                                 -- 
                GD_WMD_SWRITE      <= '0';                                 --
                GD_WMD_EXOR        <= '0';                                 --
                GD_WMD_OR          <= '0';                                 --
                GD_WMD_RESET       <= '0';                                 --
                GD_WMD_REPLACE     <= '0';                                 --
                GD_WMD_PSET        <= '0';                                 --
                GD_RD_SEARCH       <= '0';                                 --
                GD_RD_SINGLE       <= '0';                                 --
                GD_DMD_FRAME_A     <= '0';                                 --

            else
                -- WEN cycles are 1 clock only.
                GD_WEN_GI                         <= '0';
                GD_WEN_GII                        <= '0';

                -- Register reads are catered for in the main CTRLREG block. This section is for any trigger actions.
                if VIDEO_RDni = '0' then
     --               -- Capture CPU address for read requests.
     --               if CS_800_GRAMn = '0' then
--
--                        -- Start a read transaction.
--                        GD_FSM                    <= 5;
 --                   end if;
                end if;

                -- Write registers. Detect the edge of the write signal and action register updates on this edge.
                if VIDEO_WRni = '0' then

                    -- 0xCF Graphics Display LSI CRT Control Register.
                    if(CS_GCRTCn = '0') then
                        -- Writes to the CRTC register use the upper byte (Reg B) in an OUT (A),C command to identify the target.
                        if VIDEO_ADDRi(15 downto 11) = "00000" then
                            case VIDEO_ADDRi(10 downto 8) is
                                -- Scroll offset regiser L (SOF1), 8 bits
                                when "001" =>
                                    GD_SOF(7 downto 0) <= VIDEO_DATA_IN(7 downto 0);

                                -- Scroll offset regiser R (SOF2), 2 bits
                                when "010" =>
                                    GD_SOF(9 downto 8) <= VIDEO_DATA_IN(1 downto 0);

                                -- Scroll width regiser (SW), 7 bits
                                when "011" =>
                                    GD_SW         <= VIDEO_DATA_IN(6 downto 0);

                                -- Scroll start address register (SSA), 7 bits
                                when "100" =>
                                    GD_SSA        <= VIDEO_DATA_IN(6 downto 0);

                                -- Scroll end address register (SEA), 7 bits
                                when "101" =>
                                    GD_SEA        <= VIDEO_DATA_IN(6 downto 0);

                                -- Border colour regiser (BCOL), 4 bits
                                when "110" =>
                                    GD_BCOL       <= VIDEO_DATA_IN(3 downto 0);

                                -- Superimpose bit (D7)(CKSW), 1 bit
                                when "111" =>
                                    GD_CKSW       <= VIDEO_DATA_IN(0);

                                when others =>
                            end case;
                        end if;
                    end if;                    

                    -- 0xCE Graphics Display LSI CRT Command Register.
                    if(CS_GDMDn = '0') then
                        GDMD_REG                  <= VIDEO_DATA_IN(7 downto 0);

                        -- Setup readable signals based on the register.
                        if VIDEO_DATA_IN(1 downto 0) = "00" then
                            GD_DMD_FRAME_A        <= '1';
                        else
                            GD_DMD_FRAME_A        <= '0';
                        end if;
                        if VIDEO_DATA_IN(1 downto 0) = "01" then
                            GD_DMD_FRAME_B        <= '1';
                        else
                            GD_DMD_FRAME_B        <= '0';
                        end if;
                        if VIDEO_DATA_IN(1 downto 0) = "10" then
                            GD_DMD_FRAME_AB       <= '1';
                        else
                            GD_DMD_FRAME_AB       <= '0';
                        end if;
                        if VIDEO_DATA_IN(3 downto 2) = "00" then
                            GD_DMD_320X200        <= '1';
                        else
                            GD_DMD_320X200        <= '0';
                        end if;
                        if VIDEO_DATA_IN(3 downto 2) = "01" then
                            GD_DMD_640X200        <= '1';
                        else
                            GD_DMD_640X200        <= '0';
                        end if;
                        if VIDEO_DATA_IN(3 downto 2) = "10" then
                            GD_DMD_MODE700        <= '1';
                        else
                            GD_DMD_MODE700        <= '0';
                        end if;
                    end if;                    

                    -- 0xCD Graphics Display LSI Read Format Register.
                    if(CS_GRFn = '0') then
                        GRF_REG                   <= VIDEO_DATA_IN(7 downto 0);

                        -- Setup readable signals based on the register.
                        GD_RD_FRAME_A             <= not VIDEO_DATA_IN(4);
                        GD_RD_FRAME_B             <= VIDEO_DATA_IN(4);
                        GD_RD_PLANE_I             <= VIDEO_DATA_IN(0);
                        GD_RD_PLANE_II            <= VIDEO_DATA_IN(1);
                        GD_RD_PLANE_III           <= VIDEO_DATA_IN(2);
                        GD_RD_PLANE_IV            <= VIDEO_DATA_IN(3);
                        GD_RD_SEARCH              <= VIDEO_DATA_IN(7);
                        GD_RD_SINGLE              <= not VIDEO_DATA_IN(7);
                    end if;                    

                    -- 0xCC Graphics Display LSI Write Format Register.
                    if(CS_GWFn = '0') then
                        GWF_REG                   <= VIDEO_DATA_IN(7 downto 0);

                        -- Setup readable signals based on the register.
                        GD_WR_FRAME_A             <= not VIDEO_DATA_IN(4);
                        GD_WR_FRAME_B             <= VIDEO_DATA_IN(4);
                        GD_WR_PLANE_I             <= VIDEO_DATA_IN(0);
                        GD_WR_PLANE_II            <= VIDEO_DATA_IN(1);
                        GD_WR_PLANE_III           <= VIDEO_DATA_IN(2);
                        GD_WR_PLANE_IV            <= VIDEO_DATA_IN(3);
                        if VIDEO_DATA_IN(7 downto 5) = "000" then
                            GD_WMD_SWRITE         <= '1';
                        else
                            GD_WMD_SWRITE         <= '0';
                        end if;
                        if VIDEO_DATA_IN(7 downto 5) = "001" then
                            GD_WMD_EXOR           <= '1';
                        else
                            GD_WMD_EXOR           <= '0';
                        end if;
                        if VIDEO_DATA_IN(7 downto 5) = "010" then
                            GD_WMD_OR             <= '1';
                        else
                            GD_WMD_OR             <= '0';
                        end if;
                        if VIDEO_DATA_IN(7 downto 5) = "011" then
                            GD_WMD_RESET          <= '1';
                        else
                            GD_WMD_RESET          <= '0';
                        end if;
                        if VIDEO_DATA_IN(7 downto 6) = "10" then
                            GD_WMD_REPLACE        <= '1';
                        else
                            GD_WMD_REPLACE        <= '0';
                        end if;
                        if VIDEO_DATA_IN(7 downto 6) = "11" then
                            GD_WMD_PSET           <= '1';
                        else
                            GD_WMD_PSET           <= '0';
                        end if;
                    end if;                    

                    -- 0xF0 Graphics Display LSI Pallet Register.
                    if(CS_GPALLETn = '0') then
                        if VIDEO_DATA_IN(6) = '0' then
                            GPALLET_REG(to_integer(unsigned(VIDEO_DATA_IN(5 downto 4)))) <= VIDEO_DATA_IN(3 downto 0);
                        elsif VIDEO_DATA_IN(6 downto 4) = "100" then
                            GD_PALLETSW           <= VIDEO_DATA_IN(1 downto 0);
                        end if;
                    end if;                    

                    -- Write to GRAM is indirect, via a register and the actual write occurs in the background.
                    if CS_800_GRAMn = '0' then
                        -- Capture data for write requests.
                        GD_CPUWRDATA              <= VIDEO_DATA_IN(7 downto 0);
               --         GD_CPUADDR                <= VIDEO_ADDRi(15 downto 0);
               --         GD_CPUADDR                <= VIDEO_ADDRi(15 downto 0);

                        -- Start a write transaction.
                        GD_FSM                    <= 1;
                    end if; 

                end if; -- VIDEO_WR

                -- Each clock cycle the current Video Address is registered which in turn starts the GRAM to output data for that address
                -- in anticipation of a READ-MODIFY-WRITE or READ cycle.
                GD_CPUADDR                        <= VIDEO_ADDRi(15 downto 0);

                -- Depending on the registered address, choose the correct source GRAM, Red for 320x200 when address < 0x1000 (4 bytes, 4 planes) or Blue >= 0x1000,
                -- 640x320 mode, Red < 0x2000 (2 bytes, 2 planes), or Blue >= 0x2000
                if (GD_DMD_320X200 = '1' and GD_DMA_ADDR(12) = '0') or (GD_DMD_640X200 = '1' and GD_DMA_ADDR(13) = '0') then
                    GD_SRC_DATA                   <= GRAM_DO_R_GI(31 downto 0);
                else
                    GD_SRC_DATA                   <= GRAM_DO_B_GII(31 downto 0);
                end if;

                if GD_FSM /= 0 then
                    GD_FSM                        <= GD_FSM + 1;
                end if;

                -- Finite State Machine for read-update-write write cycles and read-update read cycles.
                -- Updates occur based on the programmed register settings.
                case GD_FSM is
                    when 0 =>

                 --   -- Start of write. Read 4 bytes from GRAM which represent the 4 planes.
                 --   when 1 =>

                    -- Apply configured logic to the read data and write it back.
                    when 1 =>
                        -- Choose correct source GRAM, Red for 320x200 when address < 0x1000 (4 bytes, 4 planes) or Blue >= 0x1000,
                        -- 640x320 mode, Red < 0x2000 (2 bytes, 2 planes), or Blue >= 0x2000
                    --    if (GD_DMD_320X200 = '1' and GD_DMA_ADDR(12) = '0') or (GD_DMD_640X200 = '1' and GD_DMA_ADDR(13) = '0') then
                    --        GD_SRC_DATA       := GRAM_DO_R_GI(31 downto 0);
                    --    else
                    --        GD_SRC_DATA       := GRAM_DO_B_GII(31 downto 0);
                    --    end if;
                        GD_O_DATA             <= GD_SRC_DATA;

                        -- Single write.
                        -- SINGLE, EXOR, OR and RESET write the selected planes that exist in the current resolution
                        -- (I-IV at 320x200, I and III at 640x200); the frame bit in WF only matters for REPLACE and PSET
                        -- (mz800emu vramctrl, a transcription of the GDG VHDL).
                        if GD_WMD_SWRITE = '1' then
                            -- Frame A 320x200 Mode Plane I         or 640x200 Mode Plane I
                            if GD_WR_PLANE_I = '1' then
                                GD_O_DATA(GD_320_PLANE_I_RANGE)   <= GD_CPUWRDATA;
                            end if;
                            --  Frame A 320x200 mode Plane II
                            if (GD_DMD_320X200 = '1' and GD_WR_PLANE_II = '1') then
                                GD_O_DATA(GD_320_PLANE_II_RANGE)  <= GD_CPUWRDATA;
                            end if;
                            -- Frame B 640x200 mode Plane III          
                            if (GD_DMD_640X200 = '1' and GD_WR_PLANE_III = '1') then
                                GD_O_DATA(GD_640_PLANE_III_RANGE) <= GD_CPUWRDATA;
                            end if;
                            -- Frame B 320x200 Mode Plane III
                            if GD_DMD_320X200 = '1' and GD_WR_PLANE_III = '1' then
                                GD_O_DATA(GD_320_PLANE_III_RANGE) <= GD_CPUWRDATA;
                            end if;
                            -- Frame B 320x200 Mode Plane IV
                            if GD_DMD_320X200 = '1' and GD_WR_PLANE_IV = '1' then
                                GD_O_DATA(GD_320_PLANE_IV_RANGE) <= GD_CPUWRDATA;
                            end if;
                        end if;

                        -- EXOR
                        if GD_WMD_EXOR = '1' then
                            -- Frame A 320x200 Mode Plane I         or 640x200 Mode Plane I
                            if GD_WR_PLANE_I = '1' then
                                GD_O_DATA(GD_320_PLANE_I_RANGE)   <= (GD_SRC_DATA(GD_320_PLANE_I_RANGE) xor GD_CPUWRDATA);
                            end if;
                            --  Frame A 320x200 mode Plane II 
                            if (GD_DMD_320X200 = '1' and GD_WR_PLANE_II = '1') then
                               
                                GD_O_DATA(GD_320_PLANE_II_RANGE)  <= (GD_SRC_DATA(GD_320_PLANE_II_BIT7) xor GD_CPUWRDATA(7)) &
                                                                     (GD_SRC_DATA(GD_320_PLANE_II_BIT6) xor GD_CPUWRDATA(6)) &
                                                                     (GD_SRC_DATA(GD_320_PLANE_II_BIT5) xor GD_CPUWRDATA(5)) &
                                                                     (GD_SRC_DATA(GD_320_PLANE_II_BIT4) xor GD_CPUWRDATA(4)) &
                                                                     (GD_SRC_DATA(GD_320_PLANE_II_BIT3) xor GD_CPUWRDATA(3)) &
                                                                     (GD_SRC_DATA(GD_320_PLANE_II_BIT2) xor GD_CPUWRDATA(2)) &
                                                                     (GD_SRC_DATA(GD_320_PLANE_II_BIT1) xor GD_CPUWRDATA(1)) &
                                                                     (GD_SRC_DATA(GD_320_PLANE_II_BIT0) xor GD_CPUWRDATA(0));
                                --GD_CPUWRDATA; -- (GD_SRC_DATA(15 downto  8)); -- xor GD_CPUWRDATA);
                            end if;
                            -- Frame B 640x200 mode Plane III          
                            if (GD_DMD_640X200 = '1' and GD_WR_PLANE_III = '1') then

                                GD_O_DATA(GD_640_PLANE_III_RANGE) <= (GD_SRC_DATA(GD_640_PLANE_III_BIT7) xor GD_CPUWRDATA(7)) &
                                                                     (GD_SRC_DATA(GD_640_PLANE_III_BIT6) xor GD_CPUWRDATA(6)) &
                                                                     (GD_SRC_DATA(GD_640_PLANE_III_BIT5) xor GD_CPUWRDATA(5)) &
                                                                     (GD_SRC_DATA(GD_640_PLANE_III_BIT4) xor GD_CPUWRDATA(4)) &
                                                                     (GD_SRC_DATA(GD_640_PLANE_III_BIT3) xor GD_CPUWRDATA(3)) &
                                                                     (GD_SRC_DATA(GD_640_PLANE_III_BIT2) xor GD_CPUWRDATA(2)) &
                                                                     (GD_SRC_DATA(GD_640_PLANE_III_BIT1) xor GD_CPUWRDATA(1)) &
                                                                     (GD_SRC_DATA(GD_640_PLANE_III_BIT0) xor GD_CPUWRDATA(0));
                            end if;
                            -- Frame B 320x200 Mode Plane III
                            if GD_DMD_320X200 = '1' and GD_WR_PLANE_III = '1' then
                                GD_O_DATA(GD_320_PLANE_III_RANGE) <= (GD_SRC_DATA(GD_320_PLANE_III_RANGE) xor GD_CPUWRDATA);
                            end if;
                            -- Frame B 320x200 Mode Plane IV
                            if GD_DMD_320X200 = '1' and GD_WR_PLANE_IV = '1' then
                                GD_O_DATA(GD_320_PLANE_IV_RANGE)  <= (GD_SRC_DATA(GD_320_PLANE_IV_RANGE) xor GD_CPUWRDATA);
                            end if;
                        end if;
  
                        -- OR
                        if GD_WMD_OR = '1' then
                            -- Frame A 320x200 Mode Plane I         or 640x200 Mode Plane I
                            if GD_WR_PLANE_I = '1' then
                                GD_O_DATA(GD_320_PLANE_I_RANGE)   <= GD_SRC_DATA(GD_320_PLANE_I_RANGE)  or GD_CPUWRDATA;
                            end if;
                            --  Frame A 320x200 mode Plane II
                            if (GD_DMD_320X200 = '1' and GD_WR_PLANE_II = '1') then
                                GD_O_DATA(GD_320_PLANE_II_RANGE)  <= GD_SRC_DATA(GD_320_PLANE_II_RANGE)  or GD_CPUWRDATA;
                            end if;
                            -- Frame B 640x200 mode Plane III          
                            if (GD_DMD_640X200 = '1' and GD_WR_PLANE_III = '1') then
                                GD_O_DATA(GD_640_PLANE_III_RANGE) <= GD_SRC_DATA(GD_640_PLANE_III_RANGE)  or GD_CPUWRDATA;
                            end if;
                            -- Frame B 320x200 Mode Plane III
                            if GD_DMD_320X200 = '1' and GD_WR_PLANE_III = '1' then
                                GD_O_DATA(GD_320_PLANE_III_RANGE) <= GD_SRC_DATA(GD_320_PLANE_III_RANGE)  or GD_CPUWRDATA;
                            end if;
                            -- Frame B 320x200 Mode Plane IV
                            if GD_DMD_320X200 = '1' and GD_WR_PLANE_IV = '1' then
                                GD_O_DATA(GD_320_PLANE_IV_RANGE)  <= GD_SRC_DATA(GD_320_PLANE_IV_RANGE)  or GD_CPUWRDATA;
                            end if;
                        end if;
  
                        -- RESET
                        if GD_WMD_RESET = '1' then
                            -- Frame A 320x200 Mode Plane I         or 640x200 Mode Plane I
                            if GD_WR_PLANE_I = '1' then
                                GD_O_DATA(GD_320_PLANE_I_RANGE)   <= GD_SRC_DATA(GD_320_PLANE_I_RANGE) and not GD_CPUWRDATA;
                            end if;
                            --  Frame A 320x200 mode Plane II
                            if (GD_DMD_320X200 = '1' and GD_WR_PLANE_II = '1') then
                                GD_O_DATA(GD_320_PLANE_II_RANGE)  <= GD_SRC_DATA(GD_320_PLANE_II_RANGE) and not GD_CPUWRDATA;
                            end if;
                            -- Frame B 640x200 mode Plane III          
                            if (GD_DMD_640X200 = '1' and GD_WR_PLANE_III = '1') then
                                GD_O_DATA(GD_640_PLANE_III_RANGE) <= GD_SRC_DATA(GD_640_PLANE_III_RANGE) and not GD_CPUWRDATA;
                            end if;
                            -- Frame B 320x200 Mode Plane III
                            if GD_DMD_320X200 = '1' and GD_WR_PLANE_III = '1' then
                                GD_O_DATA(GD_320_PLANE_III_RANGE) <= GD_SRC_DATA(GD_320_PLANE_III_RANGE) and not GD_CPUWRDATA;
                            end if;
                            -- Frame B 320x200 Mode Plane IV
                            if GD_DMD_320X200 = '1' and GD_WR_PLANE_IV = '1' then
                                GD_O_DATA(GD_320_PLANE_IV_RANGE) <= GD_SRC_DATA(GD_320_PLANE_IV_RANGE) and not GD_CPUWRDATA;
                            end if;
                        end if;
  
                        -- REPLACE
                        if GD_WMD_REPLACE = '1' then
                            -- Frame A 320x200 Mode Plane I         or 640x200 Mode Plane I
                            if (GD_WR_FRAME_A = '1' or GD_DMD_FRAME_AB = '1') then
                                if GD_WR_PLANE_I = '1' then
                                    GD_O_DATA(GD_320_PLANE_I_RANGE)<= GD_CPUWRDATA;
                                else
                                    GD_O_DATA(GD_320_PLANE_I_RANGE)<= X"00"; 
                                end if;
                            end if;
                            --  Frame A 320x200 mode Plane II 
                            if (GD_WR_FRAME_A = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_320X200 = '1' then
                                if GD_WR_PLANE_II = '1' then
                                    GD_O_DATA(GD_320_PLANE_II_RANGE)<= GD_CPUWRDATA;
                                else
                                    GD_O_DATA(GD_320_PLANE_II_RANGE)<= X"00";
                                end if;
                            end if;
                            -- Frame B 640x200 mode Plane III          
                            if (GD_WR_FRAME_B = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_640X200 = '1' then
                                if GD_WR_PLANE_III = '1' then
                                    GD_O_DATA(GD_640_PLANE_III_RANGE)<= GD_CPUWRDATA;
                                else
                                    GD_O_DATA(GD_640_PLANE_III_RANGE)<= X"00";
                                end if;
                            end if;
                            -- Frame B 320x200 Mode Plane III
                            if (GD_WR_FRAME_B = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_320X200 = '1' then
                                if GD_WR_PLANE_III = '1' then
                                    GD_O_DATA(GD_320_PLANE_III_RANGE)<= GD_CPUWRDATA;
                                else
                                    GD_O_DATA(GD_320_PLANE_III_RANGE)<= X"00";
                                end if;
                            end if;
                            -- Frame B 320x200 Mode Plane IV
                            if (GD_WR_FRAME_B = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_320X200 = '1' then
                                if GD_WR_PLANE_IV = '1' then
                                    GD_O_DATA(GD_320_PLANE_IV_RANGE)<= GD_CPUWRDATA;
                                else
                                    GD_O_DATA(GD_320_PLANE_IV_RANGE)<= X"00";
                                end if;
                            end if;
                        end if;
  
                        -- PSET
                        if GD_WMD_PSET = '1' then
                            -- Frame A 320x200 Mode Plane I         or 640x200 Mode Plane I
                            if (GD_WR_FRAME_A = '1' or GD_DMD_FRAME_AB = '1') then
                                if GD_WR_PLANE_I = '1' then
                                    GD_O_DATA(GD_320_PLANE_I_RANGE)   <= GD_SRC_DATA(GD_320_PLANE_I_RANGE) or GD_CPUWRDATA;
                                else
                                    GD_O_DATA(GD_320_PLANE_I_RANGE)   <= GD_SRC_DATA(GD_320_PLANE_I_RANGE) and not GD_CPUWRDATA;
                                end if;
                            end if;
                            --  Frame A 320x200 mode Plane II 
                            if (GD_WR_FRAME_A = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_320X200 = '1' then
                                if GD_WR_PLANE_II = '1' then
                                    GD_O_DATA(GD_320_PLANE_II_RANGE)  <= GD_SRC_DATA(GD_320_PLANE_II_RANGE) or GD_CPUWRDATA;
                                else
                                    GD_O_DATA(GD_320_PLANE_II_RANGE)  <= GD_SRC_DATA(GD_320_PLANE_II_RANGE) and not GD_CPUWRDATA;
                                end if;
                            end if;
                            -- Frame B 640x200 mode Plane III          
                            if (GD_WR_FRAME_B = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_640X200 = '1' then
                                if GD_WR_PLANE_III = '1' then
                                    GD_O_DATA(GD_640_PLANE_III_RANGE)  <= GD_SRC_DATA(GD_640_PLANE_III_RANGE) or GD_CPUWRDATA;
                                else
                                    GD_O_DATA(GD_640_PLANE_III_RANGE)  <= GD_SRC_DATA(GD_640_PLANE_III_RANGE) and not GD_CPUWRDATA;
                                end if;
                            end if;
                            -- Frame B 320x200 Mode Plane III
                            if (GD_WR_FRAME_B = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_320X200 = '1' then
                                if GD_WR_PLANE_III = '1' then
                                    GD_O_DATA(GD_320_PLANE_III_RANGE) <= GD_SRC_DATA(GD_320_PLANE_III_RANGE) or GD_CPUWRDATA;
                                else
                                    GD_O_DATA(GD_320_PLANE_III_RANGE) <= GD_SRC_DATA(GD_320_PLANE_III_RANGE) and not GD_CPUWRDATA;
                                end if;
                            end if;
                            -- Frame B 320x200 Mode Plane IV
                            if (GD_WR_FRAME_B = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_320X200 = '1' then
                                if GD_WR_PLANE_IV = '1' then
                                    GD_O_DATA(GD_320_PLANE_IV_RANGE) <= GD_SRC_DATA(GD_320_PLANE_IV_RANGE) or GD_CPUWRDATA;
                                else
                                    GD_O_DATA(GD_320_PLANE_IV_RANGE) <= GD_SRC_DATA(GD_320_PLANE_IV_RANGE) and not GD_CPUWRDATA;
                                end if;
                            end if;
                        end if;

                        -- Blank out writes if the second RAM bank has not been installed.
                        if CONFIG(OPT_MZ1R25) = '0' then
                            if GD_DMD_320X200 = '1' then
                                GD_O_DATA(GD_320_MZ1R25_RANGE)       <= (others => '0');
                            else
                                GD_O_DATA(GD_640_MZ1R25_RANGE)       <= (others => '0');
                            end if;
                        end if;
 
                    -- Write updated data back to GRAM.
                    when 2 =>
                        if GD_DMD_320X200 = '1' then
                            GD_WEN_GI             <= not GD_DMA_ADDR(12);
                            GD_WEN_GII            <= GD_DMA_ADDR(12);
                        else
                            GD_WEN_GI             <= not GD_DMA_ADDR(13);
                            GD_WEN_GII            <= GD_DMA_ADDR(13);
                        end if;
                        GD_FSM                    <= 0;

                    -- Read cycle, setup address and fetch data.
            --        when 4 =>
                  --      GD_CPUADDR                <= VIDEO_ADDRi(15 downto 0);

             --       when 5 =>
             --           GD_FSM                    <= 0;

                    when others =>
                end case;
                  --      if (GD_DMD_320X200 = '1' and GD_DMA_ADDR(12) = '0') or (GD_DMD_640X200 = '1' and GD_DMA_ADDR(13) = '0') then
                  --          GD_SRC_DATA           := GRAM_DO_R_GI;
                  --      else
                  --          GD_SRC_DATA           := GRAM_DO_B_GII;
                  --      end if;

                -- Read data is calculated every clock based on the current data output by the GRAM. Actual processing is based on the GDG registers.
                -- Single read mode.
                if GD_RD_SINGLE = '1' then

                    if (GD_RD_FRAME_A = '1' or GD_DMD_FRAME_AB = '1') and GD_RD_PLANE_I = '1' then
                        GD_CPURDDATA      <= GD_SRC_DATA(GD_320_PLANE_I_RANGE);
                    end if;
                    if ((GD_RD_FRAME_A = '1' or GD_DMD_FRAME_AB = '1') and GD_RD_PLANE_II = '1') or ((GD_RD_FRAME_B = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_640X200 = '1' and CONFIG(OPT_MZ1R25) = '1' and GD_RD_PLANE_III = '1') then
                        GD_CPURDDATA      <= GD_SRC_DATA(GD_320_PLANE_II_RANGE);
                    end if;
                    if (GD_RD_FRAME_B = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_320X200 = '1' and CONFIG(OPT_MZ1R25) = '1' and GD_RD_PLANE_III = '1' then
                        GD_CPURDDATA      <= GD_SRC_DATA(GD_320_PLANE_III_RANGE);
                    end if;
                    if (GD_RD_FRAME_B = '1' or GD_DMD_FRAME_AB = '1') and GD_DMD_320X200 = '1' and CONFIG(OPT_MZ1R25) = '1' and GD_RD_PLANE_IV = '1' then
                        GD_CPURDDATA      <= GD_SRC_DATA(GD_320_PLANE_IV_RANGE);
                    end if;

                -- Colour match mode. Match the data stored in GRAM planes against that given in the GRF register, setting 1 if a match, 0 otherwise.
                else
                    GD_CPURDDATA          <= (others => '0');
                    -- In 16 colours (both frames) the display mode decides and the RF frame bit is ignored, as in mz800emu:
                    -- Abu Simbel clears VRAM with LDIR in 16-colour mode with RF=8C (frame bit 0); comparing only planes
                    -- I/II returned FF and filled VRAM with stripes.
                    -- Frame A 320x200
                    if    GD_RD_FRAME_A = '1'  and GD_DMD_320X200 = '1' and GD_DMD_FRAME_AB = '0' then 

                        GD_CPURDDATA      <= ((GD_SRC_DATA(GD_320_PLANE_I_BIT7) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_320_PLANE_II_BIT7) xnor GD_RD_PLANE_II)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_I_BIT6) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_320_PLANE_II_BIT6) xnor GD_RD_PLANE_II)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_I_BIT5) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_320_PLANE_II_BIT5) xnor GD_RD_PLANE_II)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_I_BIT4) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_320_PLANE_II_BIT4) xnor GD_RD_PLANE_II)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_I_BIT3) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_320_PLANE_II_BIT3) xnor GD_RD_PLANE_II)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_I_BIT2) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_320_PLANE_II_BIT2) xnor GD_RD_PLANE_II)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_I_BIT1) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_320_PLANE_II_BIT1) xnor GD_RD_PLANE_II)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_I_BIT0) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_320_PLANE_II_BIT0) xnor GD_RD_PLANE_II));

                    -- Frame B 320x200
                    elsif GD_RD_FRAME_B = '1'  and GD_DMD_320X200 = '1' and GD_DMD_FRAME_AB = '0' then 

                        GD_CPURDDATA      <= ((GD_SRC_DATA(GD_320_PLANE_IV_BIT7) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT7) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT6) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT6) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT5) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT5) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT4) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT4) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT3) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT3) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT2) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT2) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT1) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT1) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT0) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT0) xnor GD_RD_PLANE_III));

                    -- Both Frames 320x200
                    elsif GD_DMD_FRAME_AB = '1' and GD_DMD_320X200 = '1' and CONFIG(OPT_MZ1R25) = '1' then 

                        GD_CPURDDATA      <= ((GD_SRC_DATA(GD_320_PLANE_IV_BIT7) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT7) xnor GD_RD_PLANE_III) and (GD_SRC_DATA(GD_320_PLANE_II_BIT7) xnor GD_RD_PLANE_II) and (GD_SRC_DATA(GD_320_PLANE_I_BIT7) xnor GD_RD_PLANE_I)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT6) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT6) xnor GD_RD_PLANE_III) and (GD_SRC_DATA(GD_320_PLANE_II_BIT6) xnor GD_RD_PLANE_II) and (GD_SRC_DATA(GD_320_PLANE_I_BIT6) xnor GD_RD_PLANE_I)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT5) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT5) xnor GD_RD_PLANE_III) and (GD_SRC_DATA(GD_320_PLANE_II_BIT5) xnor GD_RD_PLANE_II) and (GD_SRC_DATA(GD_320_PLANE_I_BIT5) xnor GD_RD_PLANE_I)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT4) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT4) xnor GD_RD_PLANE_III) and (GD_SRC_DATA(GD_320_PLANE_II_BIT4) xnor GD_RD_PLANE_II) and (GD_SRC_DATA(GD_320_PLANE_I_BIT4) xnor GD_RD_PLANE_I)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT3) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT3) xnor GD_RD_PLANE_III) and (GD_SRC_DATA(GD_320_PLANE_II_BIT3) xnor GD_RD_PLANE_II) and (GD_SRC_DATA(GD_320_PLANE_I_BIT3) xnor GD_RD_PLANE_I)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT2) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT2) xnor GD_RD_PLANE_III) and (GD_SRC_DATA(GD_320_PLANE_II_BIT2) xnor GD_RD_PLANE_II) and (GD_SRC_DATA(GD_320_PLANE_I_BIT2) xnor GD_RD_PLANE_I)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT1) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT1) xnor GD_RD_PLANE_III) and (GD_SRC_DATA(GD_320_PLANE_II_BIT1) xnor GD_RD_PLANE_II) and (GD_SRC_DATA(GD_320_PLANE_I_BIT1) xnor GD_RD_PLANE_I)) &
                                             ((GD_SRC_DATA(GD_320_PLANE_IV_BIT0) xnor GD_RD_PLANE_IV) and (GD_SRC_DATA(GD_320_PLANE_III_BIT0) xnor GD_RD_PLANE_III) and (GD_SRC_DATA(GD_320_PLANE_II_BIT0) xnor GD_RD_PLANE_II) and (GD_SRC_DATA(GD_320_PLANE_I_BIT0) xnor GD_RD_PLANE_I));

                    -- Frame A 640x200
                    elsif GD_RD_FRAME_A = '1'  and GD_DMD_640X200 = '1' and GD_DMD_FRAME_AB = '0' then

                        GD_CPURDDATA      <= (GD_SRC_DATA(GD_640_PLANE_I_BIT7) xnor GD_RD_PLANE_I) &
                                             (GD_SRC_DATA(GD_640_PLANE_I_BIT6) xnor GD_RD_PLANE_I) &
                                             (GD_SRC_DATA(GD_640_PLANE_I_BIT5) xnor GD_RD_PLANE_I) &
                                             (GD_SRC_DATA(GD_640_PLANE_I_BIT4) xnor GD_RD_PLANE_I) &
                                             (GD_SRC_DATA(GD_640_PLANE_I_BIT3) xnor GD_RD_PLANE_I) &
                                             (GD_SRC_DATA(GD_640_PLANE_I_BIT2) xnor GD_RD_PLANE_I) &
                                             (GD_SRC_DATA(GD_640_PLANE_I_BIT1) xnor GD_RD_PLANE_I) &
                                             (GD_SRC_DATA(GD_640_PLANE_I_BIT0) xnor GD_RD_PLANE_I);

                    -- Frame B 640x200
                    elsif GD_RD_FRAME_B = '1'  and GD_DMD_640X200 = '1' and GD_DMD_FRAME_AB = '0' and CONFIG(OPT_MZ1R25) = '1' then

                        GD_CPURDDATA      <= (GD_SRC_DATA(GD_640_PLANE_III_BIT7) xnor GD_RD_PLANE_III) &
                                             (GD_SRC_DATA(GD_640_PLANE_III_BIT6) xnor GD_RD_PLANE_III) &
                                             (GD_SRC_DATA(GD_640_PLANE_III_BIT5) xnor GD_RD_PLANE_III) &
                                             (GD_SRC_DATA(GD_640_PLANE_III_BIT4) xnor GD_RD_PLANE_III) &
                                             (GD_SRC_DATA(GD_640_PLANE_III_BIT3) xnor GD_RD_PLANE_III) &
                                             (GD_SRC_DATA(GD_640_PLANE_III_BIT2) xnor GD_RD_PLANE_III) &
                                             (GD_SRC_DATA(GD_640_PLANE_III_BIT1) xnor GD_RD_PLANE_III) &
                                             (GD_SRC_DATA(GD_640_PLANE_III_BIT0) xnor GD_RD_PLANE_III);

                    -- Both Frames 640x200
                    elsif GD_DMD_FRAME_AB = '1' and GD_DMD_640X200 = '1' and CONFIG(OPT_MZ1R25) = '1' then

                        GD_CPURDDATA      <= ((GD_SRC_DATA(GD_640_PLANE_I_BIT7) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_640_PLANE_III_BIT7) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_640_PLANE_I_BIT6) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_640_PLANE_III_BIT6) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_640_PLANE_I_BIT5) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_640_PLANE_III_BIT5) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_640_PLANE_I_BIT4) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_640_PLANE_III_BIT4) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_640_PLANE_I_BIT3) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_640_PLANE_III_BIT3) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_640_PLANE_I_BIT2) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_640_PLANE_III_BIT2) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_640_PLANE_I_BIT1) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_640_PLANE_III_BIT1) xnor GD_RD_PLANE_III)) &
                                             ((GD_SRC_DATA(GD_640_PLANE_I_BIT0) xnor GD_RD_PLANE_I) and (GD_SRC_DATA(GD_640_PLANE_III_BIT0) xnor GD_RD_PLANE_III));
                    end if;
                end if;

            end if; -- VRESETn
        end if; -- SYS_CLK
    end process;

    -- A basic Graphics Processing Unit. The idea is to speed up certain tasks such as clearing the screen or setting a fixed colour. 
    -- The GPU works by several writes to the FB_TIMING register which stores upto 128bits of parameters, the bit allocation depending upon the command given later.
    -- Once the parameters are stored, a command is written into the GPU control register and the requested task is undertaken.
    --
    -- Command word:-
    --     Bit    [7] - 0 = VRAN, 1 = Pixel Frame Buffer
    --     Bits [6:0] - Command:-
    --                  0x00 = NOP/Idle.
    --
    -- VRAM commands.
    --   0x01 = Clear VRAM screen.
    --   0x02 = Clear VRAM screen with char and attribute:  Parameters: [15:8] - character, [7:0] - attribute byte
    --   0x03 = Parameterised Clear VRAM screen:  Parameters: [47:40] - Start X, [39:32] - Start Y, [31:24] - End X, [23:16] - End Y, [15:8] - display char, [7:0] - attribute byte
    -- Framebuffer commands.
    --   0x81 = Clear framebuffer screen. Clear entire screen using current R/G/B filters.
    --   0x82 = Parameterised Clear framebuffer screen. Parameters: start x [87:72], start y [71:56], end x [55:40], end y [39:24], R Filter [23:16], G Filter [15:8], B Filter [7:0] - R/G/B Filters are 8 pixel wide.
    -- Other commands.
    --   0xFF = Immediate GPU reset, cancel current command and return to idle.
    GPU: process( VRESETn, SYS_CLK )
        variable GPU_START_X      : integer range 0 to 640;               -- X starting location.
        variable GPU_START_Y      : integer range 0 to 200;               -- Y starting location.
        variable GPU_END_X        : integer range 0 to 640;               -- X ending location.
        variable GPU_END_Y        : integer range 0 to 200;               -- Y ending location.
        variable GPU_COLUMNS      : integer range 0 to 132;               -- Number of char per row, setting is dynamic based on video mode.
        variable GPU_ROWS         : integer range 0 to 50;                -- Number of rows, setting is dynamic based on video mode.
        variable GPU_VAR_Y        : integer range 0 to 200;               -- Working Y position
        variable GPU_VBLANK_WAIT  : std_logic;                            -- Flag to indicate if the GPU should wait for the VBLANK signal before writes.
        variable GPU_FILTER_R     : std_logic_vector(7 downto 0);         -- Byte wide filter for 8 pixels, 0 = pixel off, 1 = pixel on.
        variable GPU_FILTER_G     : std_logic_vector(7 downto 0);         -- Byte wide filter for 8 pixels, 0 = pixel off, 1 = pixel on.
        variable GPU_FILTER_B     : std_logic_vector(7 downto 0);         -- Byte wide filter for 8 pixels, 0 = pixel off, 1 = pixel on.
        variable GPU_VRAM_CHAR    : std_logic_vector(7 downto 0);         -- Character byte to write into VRAM.
        variable GPU_VRAM_ATTR    : std_logic_vector(7 downto 0);         -- Attribute byte to write into VRAM.
    begin

        -- System clock is used for the GPU to obtain maximum performance.
        if rising_edge(SYS_CLK) then
           
            -- Ensure default values at reset.
            if VRESETn='0' then
                GPU_STATUS            <= "00000000";
                GRAM_GPU_DI_R         <= (others => '0');
                GRAM_GPU_DI_G         <= (others => '0');
                GRAM_GPU_DI_B         <= (others => '0');
                GWEN_GPU_R            <= '0';
                GWEN_GPU_G            <= '0';
                GWEN_GPU_B            <= '0';
                VRAM_GPU_WEN          <= '0';
                GRAM_GPU_ADDR         <= (others => '0');
                GPU_STATE             <= GPU_State_Idle;

            else

                -- GPU access to GRAM is controlled by state rather than setting a flag in each state which waits for a clock edge to latch.
                --
                if GPU_STATE = GPU_FB_Clear_1 or GPU_STATE = GPU_FB_Clear_2 then
                    GRAM_GPU_ENABLE   <= '1';
                else
                    GRAM_GPU_ENABLE   <= '0';
                end if;

                -- GPU access to VRAM is controlled by state rather than setting a flag in each state which waits for a clock edge to latch.
                --
                if GPU_STATE = GPU_VRAM_Clear_1 or GPU_STATE = GPU_VRAM_Clear_2 then
                    VRAM_GPU_ENABLE   <= '1';
                else
                    VRAM_GPU_ENABLE   <= '0';
                end if;

                -- Debug, view the FSM state via the status register.
                GPU_STATUS(7 downto 1) <= std_logic_vector(to_unsigned(GPUStateType'POS(GPU_STATE), 7));

                -- A reset command whilst the GPU FSM is busy cancels the operation and returns the FSM to idle.
                if GPU_COMMAND = X"FF" then
                    GPU_STATE         <= GPU_State_Idle;
                    GPU_STATUS(0)     <= '0';

                -- If a command has been given and we are not executing a command, start the FSM.
                elsif GPU_COMMAND(6 downto 0) /= "0000000" and GPU_STATE = GPU_State_Idle then
                    -- GPU busy.
                    GPU_STATUS(0)     <= '1';

                    case GPU_COMMAND is
                        -- Clear the VRAM without updating attributes.
                        when X"01" =>
                            GPU_STATE <= GPU_VRAM_Clear;

                        -- Clear the VRAM/ARAM with given attribute byte,
                        when X"02" =>
                            GPU_STATE <= GPU_VRAM_Clear_Attr;

                        -- Clear the VRAM/ARAM with parameters.
                        when X"03" =>
                            GPU_STATE <= GPU_VRAM_Clear_Param;

                        -- Clear the entire Framebuffer.
                        when X"81" =>
                            GPU_STATE <= GPU_FB_Clear;
                        -- Clear the Framebuffer according to parameters.
                        when X"82" =>
                            GPU_STATE <= GPU_FB_Clear_Param;

                        when others =>
                            GPU_STATE <= GPU_State_Idle;
                    end case;

                else

                    -- FSM for the Graphics Processing Unit.
                    --
                    case GPU_STATE is
                        -- Clear the entire display, all pixels off.
                        when GPU_FB_Clear =>
                            GPU_START_X       := 0;
                            GPU_START_Y       := 0;
                            GPU_END_X         := 640;
                            GPU_END_Y         := 200;
                            GPU_FILTER_R      := (others => '0');
                            GPU_FILTER_G      := (others => '0');
                            GPU_FILTER_B      := (others => '0');
                            GPU_STATE         <= GPU_FB_Clear_Start;
    
                        -- Clear a parameterised part of the display, 
                        -- Parameters: [88] = VBLANK Wait, start x [87:72], start y [71:56], end x [55:40], end y [39:24], R Filter [23:16], G Filter [15:8], B Filter [7:0] - R/G/B Filters are 8 pixel wide.
                        when GPU_FB_Clear_Param =>
                            if to_integer(unsigned(GPU_PARAMS(87 downto 72))) >= 640 then
                                GPU_START_X   := 0;
                            else
                                GPU_START_X   := to_integer(unsigned(GPU_PARAMS(87 downto 72)));
                            end if;
                            if to_integer(unsigned(GPU_PARAMS(71 downto 56))) >= 200 then 
                                GPU_START_Y   := 0;
                            else
                                GPU_START_Y   := to_integer(unsigned(GPU_PARAMS(71 downto 56)));
                            end if;
                            if to_integer(unsigned(GPU_PARAMS(55 downto 40))) <= to_integer(unsigned(GPU_PARAMS(87 downto 72))) or to_integer(unsigned(GPU_PARAMS(55 downto 40))) >= 640 then
                                GPU_END_X     := 640;
                            else
                                GPU_END_X     := to_integer(unsigned(GPU_PARAMS(55 downto 40)));
                            end if;
                            if to_integer(unsigned(GPU_PARAMS(39 downto 24))) <= to_integer(unsigned(GPU_PARAMS(71 downto 56))) or to_integer(unsigned(GPU_PARAMS(39 downto 24))) >= 200 then
                                GPU_END_Y     := 200;
                            else
                                GPU_END_Y     := to_integer(unsigned(GPU_PARAMS(39 downto 24)));
                            end if;
                            GPU_VBLANK_WAIT   := GPU_PARAMS(88);
                            GPU_FILTER_R      := GPU_PARAMS(23 downto 16);
                            GPU_FILTER_G      := GPU_PARAMS(15 downto 8);
                            GPU_FILTER_B      := GPU_PARAMS(7 downto 0);
                            GPU_STATE         <= GPU_FB_Clear_Start;
    
                        when GPU_FB_Clear_Start =>
                            GPU_START_ADDR    <= std_logic_vector(to_unsigned(((GPU_START_X / 8) + (GPU_START_Y * 80)), GPU_START_ADDR'length));
                            GRAM_GPU_ADDR     <= std_logic_vector(to_unsigned(((GPU_START_X / 8) + (GPU_START_Y * 80)), GRAM_GPU_ADDR'length));
                            GRAM_GPU_DI_R     <= GPU_FILTER_R;
                            GRAM_GPU_DI_G     <= GPU_FILTER_G;
                            GRAM_GPU_DI_B     <= GPU_FILTER_B;
                            GPU_VAR_Y         := GPU_START_Y;
                            GPU_STATE         <= GPU_FB_Clear_1;
    
                        -- Wait for the vertical blanking period before writing into the framebuffer.
                        when GPU_FB_Clear_1 =>
                            if V_BLANKi = '1' or GPU_VBLANK_WAIT = '0' then
                                GWEN_GPU_R    <= '1';
                                GWEN_GPU_G    <= '1';
                                GWEN_GPU_B    <= '1';
                                GPU_STATE     <= GPU_FB_Clear_2;
                            end if;
    
                        when GPU_FB_Clear_2 =>
                            GWEN_GPU_R        <= '0';
                            GWEN_GPU_G        <= '0';
                            GWEN_GPU_B        <= '0';
    
                            if to_integer(unsigned(GRAM_GPU_ADDR)) >= to_integer(unsigned(GPU_START_ADDR)) + ((GPU_END_X - GPU_START_X)/8) or GRAM_GPU_ADDR = X"3FFF" then
                                if GPU_VAR_Y >= GPU_END_Y then
                                    GPU_STATE     <= GPU_FB_Clear_3;
                                else
                                    GRAM_GPU_ADDR <= GPU_START_ADDR + 80;
                                    GPU_START_ADDR<= GPU_START_ADDR + 80;
                                    GPU_VAR_Y     := GPU_VAR_Y + 1;
                                    GPU_STATE     <= GPU_FB_Clear_1;
                                end if;
                            else
                                GRAM_GPU_ADDR <= GRAM_GPU_ADDR + 1;
                                GPU_STATE     <= GPU_FB_Clear_1;
                            end if;
    
                        when GPU_FB_Clear_3 =>
                            GPU_STATE         <= GPU_State_Idle;
    
                        -- Clear the entire VRAM display to no characters and a blue background (for the MZ-700/colour modes).
                        when GPU_VRAM_Clear =>
                            GPU_COLUMNS       := 128;
                            GPU_ROWS          := 16;
                            GPU_START_X       := 0;
                            GPU_START_Y       := 0;
                            GPU_END_X         := GPU_COLUMNS - 1;
                            GPU_END_Y         := GPU_ROWS - 1;
                            GPU_VRAM_CHAR     := X"00";
                            GPU_VRAM_ATTR     := X"71";
                            GPU_STATE         <= GPU_VRAM_Clear_Start;
    
                        -- Clear the entire VRAM display to a character and a colour given as a parameter, [15:8] = character, [7:0] = attribute byte.
                        when GPU_VRAM_Clear_Attr =>
                            GPU_COLUMNS       := 128;
                            GPU_ROWS          := 16;
                            GPU_START_X       := 0;
                            GPU_START_Y       := 0;
                            GPU_END_X         := GPU_COLUMNS - 1;
                            GPU_END_Y         := GPU_ROWS - 1;
                            GPU_VRAM_CHAR     := GPU_PARAMS(15 downto 8);
                            GPU_VRAM_ATTR     := GPU_PARAMS(7 downto 0);
                            GPU_STATE         <= GPU_VRAM_Clear_Start;
    
                        -- Clear the VRAM display according to given parameters:
                        -- Parameters: [48] - VBLANK Wait, [47:40] - Start X, [39:32] - Start Y, [31:24] - End X, [23:16] - End Y, [15:8] - display char, [7:0] - attribute byte
                        when GPU_VRAM_Clear_Param =>
                            -- Update the column setting according to the dynamic mode.
                            if MODE_VIDEO_MONO = '1' or MODE_VIDEO_COLOUR = '1' then
                                GPU_COLUMNS   := 40;
                            else
                                GPU_COLUMNS   := 80;
                            end if;
                            GPU_ROWS          := 25;
    
                            -- Read and check the parameters.
                            if to_integer(unsigned(GPU_PARAMS(47 downto 40))) >= GPU_COLUMNS - 1 then
                                GPU_START_X   := GPU_COLUMNS - 1;
                            else
                                GPU_START_X   := to_integer(unsigned(GPU_PARAMS(47 downto 40)));
                            end if;
                            if to_integer(unsigned(GPU_PARAMS(39 downto 32))) >= GPU_ROWS - 1 then 
                                GPU_START_Y   := GPU_ROWS - 1;
                            else
                                GPU_START_Y   := to_integer(unsigned(GPU_PARAMS(39 downto 32)));
                            end if;
                            if to_integer(unsigned(GPU_PARAMS(31 downto 24))) < to_integer(unsigned(GPU_PARAMS(47 downto 40))) or to_integer(unsigned(GPU_PARAMS(31 downto 24))) >= GPU_COLUMNS - 1 then
                                GPU_END_X     := GPU_COLUMNS - 1;
                            else
                                GPU_END_X     := to_integer(unsigned(GPU_PARAMS(31 downto 24)));
                            end if;
                            if to_integer(unsigned(GPU_PARAMS(23 downto 16))) < to_integer(unsigned(GPU_PARAMS(39 downto 32))) or to_integer(unsigned(GPU_PARAMS(23 downto 16))) >= GPU_ROWS - 1 then
                                GPU_END_Y     := GPU_ROWS - 1;
                            else
                                GPU_END_Y     := to_integer(unsigned(GPU_PARAMS(23 downto 16)));
                            end if;
                            GPU_VRAM_CHAR     := GPU_PARAMS(15 downto 8);
                            GPU_VRAM_ATTR     := GPU_PARAMS(7 downto 0);
                            GPU_VBLANK_WAIT   := GPU_PARAMS(48);
                            GPU_STATE         <= GPU_VRAM_Clear_Start;
    
                        when GPU_VRAM_Clear_Start =>
                            -- For modes with hardware scroll, add in the current offset so the visible part of the display is updated.
                            if MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1' then
                                GPU_START_ADDR<= std_logic_vector(to_unsigned((GPU_START_X + (GPU_START_Y * GPU_COLUMNS)), GPU_START_ADDR'length)) + (OFFSET_ADDR & "000");
                                VRAM_GPU_ADDR <= std_logic_vector(to_unsigned((GPU_START_X + (GPU_START_Y * GPU_COLUMNS)), VRAM_GPU_ADDR'length)) + (OFFSET_ADDR & "000");
                            else
                                GPU_START_ADDR<= std_logic_vector(to_unsigned((GPU_START_X + (GPU_START_Y * GPU_COLUMNS)), GPU_START_ADDR'length));
                                VRAM_GPU_ADDR <= std_logic_vector(to_unsigned((GPU_START_X + (GPU_START_Y * GPU_COLUMNS)), VRAM_GPU_ADDR'length));
                            end if;
                            GPU_VAR_Y         := GPU_START_Y;
                            GPU_STATE         <= GPU_VRAM_Clear_1;
    
                        when GPU_VRAM_Clear_1 =>
    
                            -- Set data according to region being filled, character (000:7FF) or attribute (800:FFF)
                            if VRAM_GPU_ADDR < X"800" then
                                VRAM_GPU_DI   <= GPU_VRAM_CHAR;
                            else
                                VRAM_GPU_DI   <= GPU_VRAM_ATTR;
                            end if;
    
                            -- Need to wait for the vertical blanking interval even though were using dual port RAM, this is to avoid part display or
                            -- old data and new data causing a visible tear.
                            if V_BLANKi = '1' or GPU_VBLANK_WAIT = '0' then
                                VRAM_GPU_WEN  <= '1';
                                GPU_STATE     <= GPU_VRAM_Clear_2;
                            end if;
    
                            -- Keep the Write Enable active for one full clock cycle before moving on to the next state.
                          --if VRAM_GPU_WEN = '1' then
                          --    GPU_STATE     <= GPU_VRAM_Clear_2;
                          --end if;
    
                        when GPU_VRAM_Clear_2 =>
                            VRAM_GPU_WEN      <= '0';
                            GPU_STATE         <= GPU_VRAM_Clear_1;
    
                            if (to_integer(unsigned(VRAM_GPU_ADDR)) >= to_integer(unsigned(GPU_START_ADDR)) + (GPU_END_X - GPU_START_X)) or VRAM_GPU_ADDR >= X"FFF" then
    
                                -- If we have completed filling in the entire char and attr RAM, exit.
                                if VRAM_GPU_ADDR >= X"FFF" then
                                    GPU_STATE          <= GPU_VRAM_Clear_3;
                                else
                                    -- Alternate between character ram and attribute ram, they differ by 0x800 bytes, ie; 0xD000:D7FF and 0xD800:0xDFFF
                                    if VRAM_GPU_ADDR < X"800" then
                                        VRAM_GPU_ADDR  <= GPU_START_ADDR(12 downto 0) + X"800";
                                        GPU_START_ADDR <= GPU_START_ADDR + X"800";
                                    else
                                        VRAM_GPU_ADDR  <= GPU_START_ADDR(12 downto 0) - X"800" + GPU_COLUMNS;
                                        GPU_START_ADDR <= GPU_START_ADDR - X"800" + GPU_COLUMNS;
                                        GPU_VAR_Y      := GPU_VAR_Y + 1;
    
                                        -- If we have filled to the set line, exit.
                                        if GPU_VAR_Y > GPU_END_Y then
                                            GPU_STATE  <= GPU_VRAM_Clear_3;
                                        end if;
                                    end if;
                                end if;
                            else
                                VRAM_GPU_ADDR <= VRAM_GPU_ADDR + 1;
                            end if;
    
                        when GPU_VRAM_Clear_3 =>
                            GPU_STATE         <= GPU_State_Idle;
    
                        -- Set to idle and cancel any active signals.
                        when others =>
                            -- GPU idle.
                            GPU_STATUS(0)     <= '0';
                            GWEN_GPU_R        <= '0';
                            GWEN_GPU_G        <= '0';
                            GWEN_GPU_B        <= '0';
                            VRAM_GPU_WEN      <= '0';
                    end case;
                end if;
            end if; -- if VRESETn
        end if; -- rising_edge(SYS_CLK)
    end process;

    -- Control Registers
    --
    -- MZ1200/80A: INVERT display, accessed at E014
    --             SCROLL display, accessed at E200 - E2FF, the address determines the offset.
    --
    -- Select Palette:
    --   0xB0 sets the palette. The Video Module supports 4 bit per colour output but there is only enough RAM for 1 bit per colour so the pallette is used to change the colours output.
    --     Bits [7:0] defines the pallete number. This indexes a lookup table which contains the required 4bit output per 1bit input.
    -- GPU:
    --   0xB2 set parameters. Store parameters in a long word to be used by the graphics command processor.
    --     The parameter word is 128 bit and each write to the parameter word shifts left by 8 bits and adds the new byte at bits 7:0.
    --   0xB3 set the graphics processor unit commands.
    --     Bits [5:0] - 0 = Reset parameters.
    --                  1 = Clear to val. Start Location (16 bit), End Location (16 bit), Red Filter, Green Filter, Blue Filter
    --
    -- IO Range for Graphics enhancements is set by the Video Mode registers at 0xB0->.
    --   0xB8=<val> sets the mode of the Video Module. Bits [3:0] define the Video Module machine compatibility. 0000 = MZ80K, 0001 = MZ80C, 0010 = MZ1200, 0011 = MZ80A, 0100 = MZ-700, 0101 = MZ-1500, 0110 = MZ-800, 0111 = MZ-80B, 1000 = MZ-2000, 1001 = MZ-2200, 1010 = MZ-2500.
   --               [4] = 0 - 40 col, 1 - 80 col, [5] = 0 - mono, 1 - colour. [5] defines the colour mode, 0 = mono, 1 = colour - ignored on certain modes. [6] defines wether PCGRAM is enabled, 0 = disabled, 1 = enabled.
    --   0xB9=<val> sets the graphics mode. 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR), 5=GRAM Output Enable, 4 = VRAM Output Enable, 3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect), 1/0=Read mode (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
    --   0xBA=<val> sets the Red bit mask (1 bit = 1 pixel, 8 pixels per byte).
    --   0xBB=<val> sets the Green bit mask (1 bit = 1 pixel, 8 pixels per byte).
    --   0xBC=<val> sets the Blue bit mask (1 bit = 1 pixel, 8 pixels per byte).
    --   0xBD=<val> Video memory page register. [1:0] switches in 16Kb page (3 pages) of graphics ram to C000 - FFFF. Bits [1:0] = page, 00 = off, 01 = Red, 10 = Green, 11 = Blue GRAM paged in. This overrides all MZ700/MZ80B page switching functions. [7] 0 - normal, 1 - switches in CGROM for upload at D000:DFFF.
    --   0xBE=<val> set the VGA border and attributes. The VGA modes have areas not used by the graphics output, this register allows this area to be set to a specific colour (when colour mode enabled).
    --     Bits [2:0] define the border colour, 2 = R, 1 = G, 0 = B, Bits [4:3] define the VGA mode.
    --   0xBF=<val> sets the VGA output mode.
    --     Bits [3:0] sets the VGA output mode.
    --
    -- Palette configuration:
    --   0xA3 - set the palette slot (PALETTE_PARAM_SEL) Off position to be adjusted.
    --   0xA4 - set the palette slot (PALETTE_PARAM_SEL) On position to be adjusted.
    --   0xA5 - set the red palette value according to the PALETTE_PARAM_SEL address.
    --   0xA6 - set the green palette value according to the PALETTE_PARAM_SEL address.
    --   0xA7 - set the blue palette value according to the PALETTE_PARAM_SEL address.
    --
    -- OSD configuration:
    --   0xA8 - Get OSD Menu Horizontal Size (X).
    --   0xA9 - Get OSD Menu Vertical Size (Y).
    --   0xAA - Get OSD Status Header Horizontal Size (X).
    --   0xAB - Get OSD Status Header Vertical Size (Y).
    --   0xAC - Get OSD Status Footer Horizontal Size (X).
    --   0xAD - Get OSD Status Footer Vertical Size (Y).
    --
    -- MZ-80B GRAM:
    --   0xF4 Set the MZ80B graphics options.
    --        Bit 0   -  0 = Xfer CPU<->GRAM1, 1 = Xfer CPU<->GRAM2
    --        Bit 1   -  0 = Disable GRAM1 on CRT,  1 = Enable GRAM1 on CRT
    --        Bit 2:3 - 00 = Disable GRAM2 on CRT, 11 = Enable GRAM2 on CRT
    --     Bit 0 = 0, Write to Graphics RAM I, Bit 0 = 1, Write to Graphics RAM II.
    --     Bit 1 = 1, blend Graphics RAM I output on display, Bit 2 = 1, blend Graphics RAM II output on display.
    --
    CTRLREGISTERS: process( VRESETn, SYS_CLK, CGROM_PAGE, FBRAM_PAGE_ENABLE, VIDEOMODE, VIDEOMODE_NEXT, MAX_COLUMN, VIDEO_MODE_REG, MZ2K_VRAM_ENABLE, MZ2K_CHAR_ENABLE, MZ80B_VRAM_ENABLE, MZ80B_VRAM_LO_ADDR )
    begin

        if rising_edge(SYS_CLK) then

            -- Ensure default values at reset.
            if VRESETn='0' then
                VIDEO_DATA_AVAILn     <= '1';
                DISPLAY_INVERT        <= '0';
                OFFSET_ADDR           <= (others => '0');
                GRAM_MODE_REG         <= "00101100";
                GRAM_R_FILTER         <= (others => '1');
                GRAM_G_FILTER         <= (others => '1');
                GRAM_B_FILTER         <= (others => '1');
                GRAM_OPT_PAGE         <= '0';
                GRAM_OPT_OUT1         <= '0';
                GRAM_OPT_OUT2         <= '0';
                PCG_RAM_SEL           <= '0';
                MZ2K_VRAM_ENABLE      <= '0'; 
                MZ2K_CHAR_ENABLE      <= '0';
                MZ80B_VRAM_LO_ADDR    <= '0';
                MZ80B_VRAM_ENABLE     <= '0';
                FBRAM_PAGE_ENABLE     <= '0';
                CGROM_PAGE            <= '0';
                DISPLAY_VGATE         <= '0';
                CGRAM_ADDR            <= (others=>'0');
                PCG_DATA              <= (others=>'0');
                VGA_ATTR_REG          <= (others => '0');
                PALETTE_REG           <= (others => '0');
                PALETTE_PARAM_SEL     <= (others => '0');
                CGRAM_WEn             <= '1';
                GPU_PARAMS            <= (others => '0');
                GPU_COMMAND           <= (others => '0');
                CONFIG_LAST           <= (others => '0');                 -- Apply the configuration once reset is released.

            else

                -- Change detection, whenever the config value changes, use its values to update the register settings. 
                -- Only used in the Sharp MZ Series Emulator.
             --   if CONFIG /= CONFIG_LAST
             --   CONFIG_LAST           <= CONFIG;

                -- Clear the data available flag on each cycle. If in an active read state the signal will mirror the RD/CS combination.
                VIDEO_DATA_AVAILn     <= '1';

                -- If the GPU goes busy, clear the command register ready for next command.
                --
                if CS_FB_GPUn = '1' and GPU_STATUS(0) = '1' then
                    GPU_COMMAND       <= (others => '0');
                end if;

                -- Clear write enables to the palette register.
                --
                PALETTE_WEN_R         <= '0';
                PALETTE_WEN_G         <= '0';
                PALETTE_WEN_B         <= '0';

                -- Read registers. Detect the edge of the read signal and action register reads on this edge.
                if VIDEO_RDni = '0' then

                    -- MZ80A has hardware inversion which is basically the inversion of the video out stream. A signal is set when inversion is required by a read to E014 and reset
                    -- with a read to E015.
                    if CS_INVERTn='0' and (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1') then
                        DISPLAY_INVERT    <= Z80_MA(0);
                    end if;
    
                    -- MZ80A has hardware scrolling which is basically the addition, in blocks of 8, to the video address line. A read from E200 will set the addition to 0,
                    -- a read from each location, E201 - E2FE will add X x 8 bytes to the address, a read from E2FF will scroll fully to the end of the VRAM buffer.
                    if CS_SCROLLn='0' and (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1') then
                        if MODE_VIDEO_MONO80 = '1' or MODE_VIDEO_COLOUR80 = '1' then
                            OFFSET_ADDR   <= (others => '0');
                        else
                            OFFSET_ADDR   <= VIDEO_ADDRi(7 downto 0);
                        end if;
                    end if;
                end if; -- Read block

                -- The register shift of the GPU parameters must occur after the read transaction completes otherwise scrambled data will be sent to the external device.
                if VIDEO_LAST_RDni = "0001" and VIDEO_RDni = '1' then
                    -- Read out the rightmost byte of the GPU parameters and shift right, this allows reading or manipulating the parameters.
                    -- The shift is made at the end of the read cycle so that valid data is seen by the CPU.
                    if CS_FB_PARAMSn = '0' then
                        GPU_PARAMS(119 downto 0) <= GPU_PARAMS(127 downto 8);
                    end if;
                end if;

                -- Data output, selected according to addressed resource.
                if VIDEO_RDni = '0' then

                    -- Data available flag, given the large number of memory/io combinations, the external processor logic will be simpler when data is known to be available.
                    VIDEO_DATA_AVAILn         <= '0';

                    -- Decode all the I/O-memory combinations and latch the required data ready for delivery to the controlling processor.
                    --
                    if    CS_DXXXn = '0'       and ((CS_VIDEO_LEGACYn = '0' and MODE_VIDEO_MZ80B = '0'  and MODE_VIDEO_MZ2000 = '0'  and MODE_VIDEO_MZ2200 = '0' and CGROM_PAGE = '0')
                                                 or (CS_VIDEO_LEGACYn = '0' and MODE_VIDEO_MZ80B = '1'  and MZ80B_VRAM_ENABLE = '1'  and MZ80B_VRAM_LO_ADDR = '0')
                                                 or (CS_VIDEO_LEGACYn = '0' and (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1') and MZ2K_CHAR_ENABLE = '1'  and MZ2K_VRAM_ENABLE = '1')
                                                 or CS_VIDEO_VRAM_DIRECTn = '0'
                                                   ) then
                        VIDEO_DATA_OUTi       <= VRAM_VIDEO_DATA;

                    elsif CS_5XXXn = '0'       and (CS_VIDEO_LEGACYn = '0' and MODE_VIDEO_MZ80B = '1' and MZ80B_VRAM_ENABLE = '1' and MZ80B_VRAM_LO_ADDR = '1') then
                        VIDEO_DATA_OUTi       <= VRAM_VIDEO_DATA;

                    elsif (CS_FBRAMn = '0'     and GRAM_MODE_REG(1 downto 0) = "00")  then                                                -- For direct framebuffer access, C000:FFFF is assigned to the framebuffer during a read if the FBRAM_PAGE_ENABLE register is not 0. 
                        VIDEO_DATA_OUTi       <= GRAM_DO_R_GI;

                    elsif (CS_FBRAMn = '0'     and GRAM_MODE_REG(1 downto 0) = "01") then
                        VIDEO_DATA_OUTi       <= GRAM_DO_B_GII;

                    elsif (CS_FBRAMn = '0'     and GRAM_MODE_REG(1 downto 0) = "10") then
                        VIDEO_DATA_OUTi       <= GRAM_DO_G_GIII;

                    elsif CS_VIDEO_R_FB_DIRECTn = '0' then      
                        VIDEO_DATA_OUTi       <= GRAM_DO_R_GI;

                    elsif CS_VIDEO_B_FB_DIRECTn = '0' then
                        VIDEO_DATA_OUTi       <= GRAM_DO_B_GII;

                    elsif CS_VIDEO_G_FB_DIRECTn = '0' then
                        VIDEO_DATA_OUTi       <= GRAM_DO_G_GIII;
                    --
                    elsif (CS_MZ2K_GRAMn = '0' and GRAM_MODE_REG(1 downto 0) = "00" and GRAMII_ENABLED = '1') then                        -- For MZ-2000, read the red GRAM bank.
                        VIDEO_DATA_OUTi       <= GRAM_DO_R_GI;

                    elsif (CS_MZ2K_GRAMn = '0' and GRAM_MODE_REG(1 downto 0) = "10" and GRAMI_ENABLED = '1') then                         --                       blue
                        VIDEO_DATA_OUTi       <= GRAM_DO_B_GII;

                    elsif (CS_MZ2K_GRAMn = '0' and GRAM_MODE_REG(1 downto 0) = "01" and GRAMIII_ENABLED = '1') then                       --                       green
                        VIDEO_DATA_OUTi       <= GRAM_DO_G_GIII;
                    --
                    elsif CS_80B_GRAMn = '0'   and GRAM_OPT_PAGE = '0' and GRAMI_ENABLED = '1' then                                       -- For MZ80B GRAM I memory read - lower 8K  of red framebuffer.
                        VIDEO_DATA_OUTi       <= GRAM_DO_R_GI;

                    elsif CS_80B_GRAMn = '0'   and GRAM_OPT_PAGE = '1' and GRAMII_ENABLED = '1' then                                      -- For MZ80B GRAM II memory read - lower 8K of blue framebuffer.
                        VIDEO_DATA_OUTi       <= GRAM_DO_B_GII;

                    elsif CS_800_GRAMn = '0' then
                        VIDEO_DATA_OUTi       <= X"000000" & GD_CPURDDATA;                                                                -- Data read from the graphics RAM.

                    elsif CS_GDMDn = '0' then
                        VIDEO_DATA_OUTi       <= X"000000" & GDMD_REG(7 downto 2) & CONFIG(SWITCH_MZ800) & GDMD_REG(0);                   -- DMD status output.

                    elsif CS_FB_VMn = '0'     then                                                                                        -- 0xB8 set the video mode. 
                                                                                                                                          --                       Bits [3:0] define the Video Module machine compatibility. 0000 = MZ80K, 0001 = MZ80C, 0010 = MZ1200, 0011 = MZ80A, 0100 = MZ-700, 0101 = MZ-1500, 0110 = MZ-800, 0111 = MZ-80B, 1000 = MZ-2000, 1001 = MZ-2200, 1010 = MZ-2500.
                                                                                                                                          --                       Bit    [4] defines the 40/80 column mode, 0 = 40 col, 1 = 80 col.
                                                                                                                                          --                       Bit    [5] defines the colour mode, 0 = mono, 1 = colour - ignored on certain modes.
                                                                                                                                          --                       Bit    [6] defines wether PCGRAM is enabled, 0 = disabled, 1 = enabled.
                        VIDEO_DATA_OUTi       <= X"000000" & VIDEO_MODE_REG(7 downto 0);

                    elsif CS_FB_CTLn = '0'    then                                                                                        -- 0xB9 set the graphics mode. 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
                                                                                                                                          --                               5 = GRAM Output Enable (=0), 4 = VRAM Output Enable (=0),
                                                                                                                                          --                             3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
                                                                                                                                          --                             1/0 = Read mode (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
                        VIDEO_DATA_OUTi       <= X"000000" & GRAM_MODE_REG;

                    elsif CS_FB_REDn = '0'    then                                                                                         -- 0xBA set the Red bit mask (1 bit = 1 pixel, 8 pixels per byte).
                        VIDEO_DATA_OUTi       <= X"000000" & GRAM_R_FILTER;

                    elsif CS_FB_GREENn = '0'  then                                                                                         -- 0xBB set the Green bit mask (1 bit = 1 pixel, 8 pixels per byte).
                        VIDEO_DATA_OUTi       <= X"000000" & GRAM_G_FILTER;

                    elsif CS_FB_BLUEn = '0'   then                                                                                         -- 0xBC set the Blue bit mask (1 bit = 1 pixel, 8 pixels per byte).
                        VIDEO_DATA_OUTi       <= X"000000" & GRAM_B_FILTER;

                    elsif CS_FB_PAGEn = '0'   then                                                                                         -- 0xBD [0] - set the Video memory page in block C000:FFFF, [7] - set the CGROM upload access.
                        VIDEO_DATA_OUTi       <= X"000000" & PAGE_MODE_REG; --PAGE_MODE_REG(7) & V_BLANKi & H_BLANKi & PAGE_MODE_REG(6 downto 2);

                    elsif ((CS_DXXXn = '0'  and CS_VIDEO_LEGACYn = '0' and CGROM_PAGE = '1' and PCG_RAM_SEL = '0' and PCG_ENABLED = '1' and MODE_VIDEO_MZ80B = '0' and MODE_VIDEO_MZ2000 = '0' and MODE_VIDEO_MZ2200 = '0') or CS_VIDEO_CGROM_DIRECTn = '0') then
                        VIDEO_DATA_OUTi       <= CGROM_DO;                                                                                -- PCG Read ROM when RAM_SEL = 0

                    elsif (CS_CXXXn = '0'   and CS_VIDEO_LEGACYn = '0' and MODE_VIDEO_BASE = MODE_MZ800           and MODE_VIDEO_MZ700 = '1') then
                        VIDEO_DATA_OUTi       <= CGROM_DO;                                                                                -- MZ-800 mode read CGRAM.

                    elsif ((CS_DXXXn = '0'  and CS_VIDEO_LEGACYn = '0' and CGROM_PAGE = '1' and PCG_RAM_SEL = '1' and PCG_ENABLED = '1' and MODE_VIDEO_MZ80B = '0' and MODE_VIDEO_MZ2000 = '0' and MODE_VIDEO_MZ2200 = '0') or CS_VIDEO_CGRAM_DIRECTn = '0') then
                        VIDEO_DATA_OUTi       <= CGRAM_DO;

                    elsif CS_FB_GPUn = '0'    then                                                                                           -- 0xB3 set the graphics processor unit commands.
                                                                                                                                          --                       Bits [5:0] - 0 = Reset parameters.
                                                                                                                                          --                                    1 = Clear to val. Start Location (16 bit), End Location (16 bit), Red Filter, Green Filter, Blue Filter
                        VIDEO_DATA_OUTi       <= X"000000" & GPU_STATUS;
                    elsif CS_FB_PARAMSn = '0' then                                                                                        -- 0xB2 set parameters. Store parameters in a long word to be used by the graphics command processor.
                                                                                                                                          -- The parameter word is 128 bit and each write to the parameter word shifts left by 8 bits and adds the new byte at bits 7:0.
                        VIDEO_DATA_OUTi       <= X"000000" & GPU_PARAMS(7 downto 0);
                    elsif CS_FB_VGATTRn = '0' then                                                                                        -- 0xBE set the VGA border and attributes. The VGA modes have areas not used by the graphics output, this register allows this area to be set to a specific colour (when colour mode enabled).
                                                                                                                                          --                       Bits [2:0] define the border colour, 2 = R, 1 = G, 0 = B, Bit  [6]   - enable the on screen menu display, Bit  [7]   - enable the on screen status display.
                        VIDEO_DATA_OUTi       <= X"000000" & VGA_ATTR_REG;

                    elsif CS_FB_VGAMODEn = '0' then                                                                                       -- 0xBF set the VGA mode. The VGA modes define the characteristics of the output in terms of resolution, frequency etc.
                                                                                                                                          --                       Bits [3:0] define the VGA output mode.
                        VIDEO_DATA_OUTi       <= X"000000" & VGA_MODE_REG;

                    elsif CS_FB_PALETTEn = '0' then                                                                                       -- 0xB0 sets the palette. The Video Module supports 4 bit per colour output but there is only enough RAM for 1 bit per colour so the pallette is used to change the colours output.
                                                                                                                                          --                       Bits [7:0] defines the pallete number. This indexes a lookup table which contains the required 4bit output per 1bit input.
                        VIDEO_DATA_OUTi       <= X"000000" & PALETTE_REG;

                    elsif CS_GCRTCn = '0' and VIDEO_ADDRi(11 downto 8) = "0001" then                                                      -- Scroll offset regiser L (SOF1), 8 bits
                        VIDEO_DATA_OUTi       <= X"000000" & GD_SOF(7 downto 0);

                    elsif CS_GCRTCn = '0' and VIDEO_ADDRi(11 downto 8) = "0010" then                                                      -- Scroll offset regiser R (SOF2), 2 bits
                        VIDEO_DATA_OUTi       <= X"0000000" & "00" & GD_SOF(9 downto 8);

                    elsif CS_GCRTCn = '0' and VIDEO_ADDRi(11 downto 8) = "0011" then                                                      -- Scroll width regiser (SW), 7 bits
                        VIDEO_DATA_OUTi       <= X"000000" & '0' & GD_SW;

                    elsif CS_GCRTCn = '0' and VIDEO_ADDRi(11 downto 8) = "0100" then                                                      -- Scroll start address register (SSA), 7 bits
                        VIDEO_DATA_OUTi       <= X"000000" & '0' & GD_SSA;

                    elsif CS_GCRTCn = '0' and VIDEO_ADDRi(11 downto 8) = "0101" then                                                      -- Scroll end address register (SEA), 7 bits
                        VIDEO_DATA_OUTi       <= X"000000" & '0' & GD_SEA;

                    elsif CS_GCRTCn = '0' and VIDEO_ADDRi(11 downto 8) = "0110" then                                                      -- Border colour regiser (BCOL), 4 bits
                        VIDEO_DATA_OUTi       <= X"0000000" & GD_BCOL;

                    elsif CS_GCRTCn = '0' and VIDEO_ADDRi(11 downto 8) = "0111" then                                                      -- Superimpose bit (D7)(CKSW), 1 bit
                        VIDEO_DATA_OUTi       <= X"0000000" & "000" & GD_CKSW;

                    elsif CS_GCRTCn = '0' and VIDEO_ADDRi(11 downto 8) = "1000" then                                                      -- 
                        VIDEO_DATA_OUTi       <= X"000000" & GD_DMA_ADDR(7 downto 0);

                    elsif CS_GCRTCn = '0' and VIDEO_ADDRi(11 downto 8) = "1001" then                                                      -- 
                        VIDEO_DATA_OUTi       <= X"000000" & "00" & GD_DMA_ADDR(13 downto 8);

                    elsif CS_GPALLETn = '0' and VIDEO_ADDRi(11 downto 8) = "0000" then                                                    --  Pallet 0
                        VIDEO_DATA_OUTi       <= X"000000" & "0000" & GPALLET_REG(0);

                    elsif CS_GPALLETn = '0' and VIDEO_ADDRi(11 downto 8) = "0001" then                                                    --  Pallet 1
                        VIDEO_DATA_OUTi       <= X"000000" & "0000" & GPALLET_REG(1);

                    elsif CS_GPALLETn = '0' and VIDEO_ADDRi(11 downto 8) = "0010" then                                                    --  Pallet 2
                        VIDEO_DATA_OUTi       <= X"000000" & "0000" & GPALLET_REG(2);

                    elsif CS_GPALLETn = '0' and VIDEO_ADDRi(11 downto 8) = "0011" then                                                    --  Pallet 3
                        VIDEO_DATA_OUTi       <= X"000000" & "0000" & GPALLET_REG(3);

                    elsif CS_GPALLETn = '0' and VIDEO_ADDRi(11 downto 8) = "0100" then                                                    --  Pallet SW
                        VIDEO_DATA_OUTi       <= X"000000" & "000000" & GD_PALLETSW(1 downto 0); 

                    elsif CS_IO_AXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0101" then
                        VIDEO_DATA_OUTi       <= X"000000" & "000" & PALETTE_DO_R;

                    elsif CS_IO_AXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0110" then
                        VIDEO_DATA_OUTi       <= X"000000" & "000" & PALETTE_DO_G;

                    elsif CS_IO_AXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0111" then
                        VIDEO_DATA_OUTi       <= X"000000" & "000" & PALETTE_DO_B;

                    elsif CS_VIDEO_R_OSD_DIRn = '0' then
                        VIDEO_DATA_OUTi       <= OSD_DO_R;

                    elsif CS_VIDEO_G_OSD_DIRn = '0' then
                        VIDEO_DATA_OUTi       <= OSD_DO_G;

                    elsif CS_VIDEO_B_OSD_DIRn = '0' then
                        VIDEO_DATA_OUTi       <= OSD_DO_B;

                    -- MZ2000 registers.
                    elsif CS_GRAMCOLRSELn  = '0' then
                        VIDEO_DATA_OUTi       <= X"000000" & MZ2K_GRAMCOLRSEL_REG;
 
                    elsif CS_CRTGRPHSELn   = '0' then
                        VIDEO_DATA_OUTi       <= X"000000" & MZ2K_CRTGRPHSEL_REG;

                    elsif CS_CRTGRPHPRIOn  = '0' then
                        VIDEO_DATA_OUTi       <= X"000000" & MZ2K_CRTGRPHPRIO_REG;

                    elsif CS_CRTBKCOLRn    = '0' then
                        VIDEO_DATA_OUTi       <= X"000000" & MZ2K_CRTBKCOLR_REG;

                    -- Current OSD Menu Horizontal width in pixels/8.
                    elsif CS_IO_AXXn = '0' and VIDEO_ADDR(3 downto 0) = "1000" then
                        VIDEO_DATA_OUTi       <= X"00000000";                                                                    -- OSD size read-back (management CPU only) removed: it needed runtime dividers.

                    -- Current OSD Menu Vertical width in pixels/8.
                    elsif CS_IO_AXXn = '0' and VIDEO_ADDR(3 downto 0) = "1001" then
                        VIDEO_DATA_OUTi       <= X"00000000";                                                                    -- OSD size read-back (management CPU only) removed: it needed runtime dividers.

                    -- Current OSD Status Header Horizontal width in pixels/8.
                    elsif CS_IO_AXXn = '0' and VIDEO_ADDR(3 downto 0) = "1010" then
                        VIDEO_DATA_OUTi       <= X"00000000";                                                                    -- OSD size read-back (management CPU only) removed: it needed runtime dividers.

                    -- Current OSD Status Header Vertical width in pixels/8.
                    elsif CS_IO_AXXn = '0' and VIDEO_ADDR(3 downto 0) = "1011" then
                        VIDEO_DATA_OUTi       <= X"00000000";                                                                    -- OSD size read-back (management CPU only) removed: it needed runtime dividers.

                    -- Current OSD Status Footer Horizontal width in pixels/8.
                    elsif CS_IO_AXXn = '0' and VIDEO_ADDR(3 downto 0) = "1100" then
                        VIDEO_DATA_OUTi       <= X"00000000";                                                                    -- OSD size read-back (management CPU only) removed: it needed runtime dividers.

                    -- Current OSD Status Footer Vertical width in pixels/8.
                    elsif CS_IO_AXXn = '0' and VIDEO_ADDR(3 downto 0) = "1101" then
                        VIDEO_DATA_OUTi       <= X"00000000";                                                                    -- OSD size read-back (management CPU only) removed: it needed runtime dividers.

                    -- Lower byte of option configuration register.
                    elsif CS_IO_AXXn = '0' and VIDEO_ADDR(3 downto 0) = "1110" then
                        VIDEO_DATA_OUTi       <= X"000000" & OPTION_REG(7 downto 0);

                    -- Upper byte of option configuration register.
                    elsif CS_IO_AXXn = '0' and VIDEO_ADDR(3 downto 0) = "1111" then
                        VIDEO_DATA_OUTi       <= X"000000" & OPTION_REG(15 downto 8);

                    else
                        VIDEO_DATA_AVAILn     <= '1';
                        VIDEO_DATA_OUTi       <= (others => '0');
                    end if;
                end if; -- Read block

                -- Write registers. Detect the edge of the write signal and action register updates on this edge.
                if VIDEO_WRni = '0' then

                    -- 0xB2 set parameters. Store parameters in a long word to be used by the graphics command processor.
                    -- The parameter word is 128 bit and each write to the parameter word shifts left by 8 bits and adds the new byte at bits 7:0.
                    if CS_FB_PARAMSn = '0' then
                        GPU_PARAMS(127 downto 8)  <= GPU_PARAMS(119 downto 0);
                        GPU_PARAMS(7 downto 0)    <= VIDEO_DATA_INi(7 downto 0);
                    end if;

                    -- 0xBE - Setup the VGA border and attributes. The VGA modes have areas not used by the graphics output, this register allows this area to be set to a specific colour (when colour mode enabled). The
                    -- unused area can also be filled with bit addressed pixels for use in status output etc.
                    --        Bits [2:0] - define the border colour, 2 = R, 1 = G, 0 = B
                    --        Bit  [6]   - enable the on screen menu display.
                    --        Bit  [7]   - enable the on screen status display.
                    if CS_FB_VGATTRn = '0' then
                        VGA_ATTR_REG              <= VIDEO_DATA_INi(7 downto 0);
                    end if;

                    -- 0xBF - Setup the VGA mode. This register defines the output resolution, frequency etc.
                    --        Bits [3:0] - define the output mode.
                    if CS_FB_VGAMODEn = '0' then
                        VGA_MODE_REG              <= VIDEO_DATA_INi(7 downto 0);
                    end if;

                    -- 0xB0 sets the palette. The Video Module supports 4 bit per colour output but there is only enough RAM for 1 bit per colour so the pallette is used to change the colours output.
                    --                       Bits [7:0] defines the pallete number. This indexes a lookup table which contains the required 4bit output per 1bit input.
                    --
                    if CS_FB_PALETTEn = '0' then
                        PALETTE_REG               <= VIDEO_DATA_INi(7 downto 0);
                    end if;

                    -- Setup the palette values for off and on states and the configuration option settings.
                    --
                    if CS_IO_AXXn = '0' then

                        case VIDEO_ADDRi(3 downto 0) is
                            -- 0xA3 - set the palette slot Off position to be adjusted.
                            when "0011" =>
                                PALETTE_PARAM_SEL <= VIDEO_DATA_INi(7 downto 0) & '0';

                            -- 0xA4 - set the palette slot On position to be adjusted.
                            when "0100" =>
                                PALETTE_PARAM_SEL <= VIDEO_DATA_INi(7 downto 0) & '1';

                            -- 0xA5 - set the red palette value according to the PALETTE_PARAM_SEL address.
                            when "0101" =>
                                PALETTE_WEN_R     <= '1';

                            -- 0xA6 - set the green palette value according to the PALETTE_PARAM_SEL address.
                            when "0110" =>
                                PALETTE_WEN_G     <= '1';

                            -- 0xA7 - set the blue palette value according to the PALETTE_PARAM_SEL address.
                            when "0111" =>
                                PALETTE_WEN_B     <= '1';

                            -- Lower byte of the configuration option setting. This register configures options such as RAM options etc.
                            when "1110" =>
                                OPTION_REG(7 downto 0) <= VIDEO_DATA_IN(7 downto 0);

                            -- Upper byte of the configuration option setting.
                            when "1111" =>
                                OPTION_REG(15 downto 8)<= VIDEO_DATA_IN(7 downto 0);

                            when others =>
                        end case;
                    end if;

                    -- 0xB3 set the graphics processor unit commands.
                    --                       Bits [5:0] - 0 = Reset parameters.
                    --                                    1 = Clear to val. Start Location (16 bit), End Location (16 bit), Red Filter, Green Filter, Blue Filter
                    -- Store the incoming GPU command.
                    --
                    if CS_FB_GPUn = '0' then
                        GPU_COMMAND               <= VIDEO_DATA_INi(7 downto 0);
                    end if;
    
                    -- 0xB8 set the video mode. 
                    --                       Bits [3:0] define the Video Module machine compatibility. 0000 = MZ80K, 0001 = MZ80C, 0010 = MZ1200, 0011 = MZ80A, 0100 = MZ-700, 0101 = MZ-1500, 0110 = MZ-800, 0111 = MZ-80B, 1000 = MZ-2000, 1001 = MZ-2200, 1010 = MZ-2500.
                    --                       Bit    [4] defines the 40/80 column mode, 0 = 40 col, 1 = 80 col.
                    --                       Bit    [5] defines the colour mode, 0 = mono, 1 = colour - ignored on certain modes.
                    --                       Bit    [6] defines wether PCGRAM is enabled, 0 = disabled, 1 = enabled.
                    if CS_FB_VMn = '0' then
                        VIDEO_MODE_REG            <= VIDEO_DATA_INi(7 downto 0);   -- Store the programmed setting for CPU readback.
                    end if;

                    -- 0xB9 set the graphics mode. 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
                    --                               5 = GRAM Output Enable (=0)
                    --                               4 = VRAM Output Enable (=0),
                    --                             3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
                    --                             1/0 = Read mode  (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Not used).
                    if CS_FB_CTLn = '0' then
                        GRAM_MODE_REG             <= VIDEO_DATA_INi(7 downto 0);
                    end if;
    
                    -- 0xBA - sets the Red bit mask (1 bit = 1 pixel, 8 pixels per byte).
                    if CS_FB_REDn = '0' then
                        GRAM_R_FILTER             <= VIDEO_DATA_INi(7 downto 0);
                    end if;
    
                    -- 0xBB - sets the Green bit mask (1 bit = 1 pixel, 8 pixels per byte).
                    if CS_FB_GREENn = '0' then
                        GRAM_G_FILTER             <= VIDEO_DATA_INi(7 downto 0);
                    end if;
    
                    -- 0xBC - sets the Blue bit mask (1 bit = 1 pixel, 8 pixels per byte).
                    if CS_FB_BLUEn = '0' then
                        GRAM_B_FILTER             <= VIDEO_DATA_INi(7 downto 0);
                    end if;
    
                    -- 0xBD - Video memory page register. [1:0] switches in 16Kb page (3 pages) of graphics ram to C000 - FFFF. Bits [1:0] = page, 00 = off, 01 = Red, 10 = Green, 11 = Blue GRAM paged in. This overrides all MZ700/MZ80B page switching functions. [7] 0 - normal, 1 - switches in CGROM for upload at D000:DFFF.
                    if CS_FB_PAGEn = '0' then
                        if VIDEO_DATA_INi(1 downto 0) /= "00" then
                            FBRAM_PAGE_ENABLE     <= '1';
                        else
                            FBRAM_PAGE_ENABLE     <= '0';
                        end if;
                        CGROM_PAGE                <= VIDEO_DATA_INi(7);
                    end if;

                    -- MZ80K Series 8255 PPI port C controls video gating, ie. enabling/disabling the video signal, using bit 0 of Port C.
                    if CS_80K_PPIn = '0' then
                        -- Port C
                        if VIDEO_ADDRi(1 downto 0) = "10" then
                            DISPLAY_VGATE         <= VIDEO_DATA_INi(0);
                        end if;
                        -- Port C direct set/reset.
                        if VIDEO_ADDRi(1 downto 0) = "11" and VIDEO_DATA_INi(7) = '0' then
                            case VIDEO_DATA_INi(3 downto 1) is
                                when "000"        => DISPLAY_VGATE <= VIDEO_DATA_INi(0);
                                when "001"        => 
                                when "010"        =>
                                when "011"        => 
                                when "100"        => 
                                when "101"        => 
                                when "110"        => 
                                when "111"        =>
                                when others       => 
                            end case;
                        end if;
                    end if;

                    -- MZ80B/MZ2000 Registers - the writable values relevant to video are registered and stored in this module.
                    --
                    -- MZ80B/MZ2000 8255 PPI.
                    -- PA4 = 0 = Reverses B/W of entire display screen. 
                    -- PC3 = 0 = Starts IPL. 
                    -- PC2 =     Sound output
                    -- PC1 = 1 = Sets memory in normal state, starting $0000. 
                    -- PC0 = 1 = Unconditionally clears the display screen.
                    if CS_80B_PPIn = '0' then

                        -- Port A
                        if VIDEO_ADDRi(1 downto 0) = "00" then
                            DISPLAY_INVERT        <= not VIDEO_DATA_INi(4);
                        end if;
                        -- Port C
                        if VIDEO_ADDRi(1 downto 0) = "10" then
                            DISPLAY_VGATE         <= VIDEO_DATA_INi(0);
                            MZ80B_IPL             <= VIDEO_DATA_INi(3);
                            MZ80B_BOOT            <= VIDEO_DATA_INi(1);
                        end if;
                        -- Port C direct set/reset.
                        if VIDEO_ADDRi(1 downto 0) = "11" and VIDEO_DATA_INi(7) = '0' then
                            case VIDEO_DATA_INi(3 downto 1) is
                                when "000"        => DISPLAY_VGATE <= VIDEO_DATA_INi(0);
                                when "001"        => MZ80B_BOOT    <= VIDEO_DATA_INi(0);
                                when "010"        => 
                                when "011"        => MZ80B_IPL     <= VIDEO_DATA_INi(0);
                                when "100"        => 
                                when "101"        => 
                                when "110"        => 
                                when "111"        =>
                                when others       => 
                            end case;
                        end if;
                    end if;

                    -- MZ80B/MZ2000 8253 PIT.
                    if CS_80B_PITn = '0' then
                    end if;

                    -- MZ80B/MZ2000 Z80 PIO.
                    if CS_80B_PIOn = '0' then

                        -- Write to PIO A.
                        -- 7 = Enables VRAM/GRAM and assigns addresses $DOOO-$FFFF to V-RAM.
                        -- 6 = On MZ-80B, select VRAM/GRAM in low memory (H) $50000-$7FFF or normal memory $D000-$FFFF. On MZ-2000/2200, select
                        --     character RAM (H) or Graphics RAM (L).
                        -- 5 = Changes screen to 80-character mode (L: 40-character mode).
                        if VIDEO_ADDRi(1 downto 0) = "00" then
                            -- MZ-80B specific control signals.
                            if MODE_VIDEO_MZ80B = '1' then
                                MZ80B_VRAM_ENABLE     <= VIDEO_DATA_INi(7);
                                MZ80B_VRAM_LO_ADDR    <= VIDEO_DATA_INi(6);

                                -- Disable the custom graphics mode when in MZ80B mode.
                                FBRAM_PAGE_ENABLE     <= '0';
                            end if;

                            -- MZ-2000 specific control signals.
                            if MODE_VIDEO_MZ2000 = '1' then
                                MZ2K_VRAM_ENABLE      <= VIDEO_DATA_INi(7);   -- Enable graphics RAM in Z80 space, either 0xD000:0xDFFF (Character) or 0xC000:0xFFFF (Graphics)
                                MZ2K_CHAR_ENABLE      <= VIDEO_DATA_INi(6);   -- Select Character (1) or Graphics (0) RAM.

                                -- Disable the custom graphics mode when in MZ2000 mode.
                                FBRAM_PAGE_ENABLE     <= '0';
                            end if;

                            -- Update the mode according to the screen width flag.
                            VIDEO_MODE_REG(4)         <= VIDEO_DATA_INi(5);
                        end if;
                    end if;

                    -- Set ths MZ80B graphics options. 
                    -- Bit 0  - 0 = Xfer CPU<->GRAM1, 1 = Xfer CPU<->GRAM2
                    -- Bit 1  - 0 = Disable GRAM1 on CRT,  1 = Enable GRAM1 on CRT
                    -- Bit 2  - 0 = Disable GRAM2 on CRT, 11 = Enable GRAM2 on CRT
                    if CS_80B_VMODEn = '0' then
                        GRAM_OPT_PAGE                 <= VIDEO_DATA_INi(0);
                        GRAM_OPT_OUT1                 <= VIDEO_DATA_INi(1);
                        GRAM_OPT_OUT2                 <= VIDEO_DATA_INi(2);
                        GRAM_MODE_REG(5)              <= '1';                       
                        if VIDEO_DATA_INi(2 downto 1) /= "00" then
                            GRAM_MODE_REG(5)          <= '0';                       -- Enable graphics output.
                            VIDEO_MODE_REG(4)         <= '0';                       -- Switch to 40 column mode when graphics enabled.
                        end if;
                        MZ80B_VMODE_REG               <= VIDEO_DATA_INi(7 downto 0);
                    end if;

                    -- Graphics priority register, character or a graphics colour has front display priority.
                    if CS_CRTBKCOLRn    = '0' then
                        MZ2K_CRTBKCOLR_REG            <= VIDEO_DATA_INi(7 downto 0);
                    end if;

                    -- Graphics output select on CRT or external CRT
                    if CS_CRTGRPHPRIOn  = '0' then
                        MZ2K_CRTGRPHPRIO_REG          <= VIDEO_DATA_INi(7 downto 0);
                    end if;

                    -- Graphics RAM colour bank select.
                    if CS_CRTGRPHSELn   = '0' then
                        MZ2K_CRTGRPHSEL_REG           <= VIDEO_DATA_INi(7 downto 0);
                    end if;

                    -- Graphics RAM colour bank select.
                    if CS_GRAMCOLRSELn  = '0' then
                        MZ2K_GRAMCOLRSEL_REG          <= VIDEO_DATA_INi(7 downto 0);

                        -- Update the page select partof the graphics mode register to select correct page.
                        case VIDEO_DATA_INi(1 downto 0) is
                            when "00" =>
                                GRAM_MODE_REG(3 downto 0) <= "1111";
                            when "01" => -- Blue enable
                                GRAM_MODE_REG(3 downto 0) <= "1010";
                            when "10" => -- Red enable
                                GRAM_MODE_REG(3 downto 0) <= "0000";
                            when "11" => -- Green enable
                                GRAM_MODE_REG(3 downto 0) <= "0101";
                            when others => null;
                        end case;

                        -- Enable graphics output by default when the CPU accesses GRAM.
                        GRAM_MODE_REG(5)          <= '0';
                    end if;

                    -- PCG Access Registers
                    --
                    -- E010: PCG_DATA (byte to describe 8-pixel row of a character)
                    -- E011: PCG_ADDR (offset in the PCG in 8-pixel row unit) -> up to 256/8 = 32 characters
                    -- E012: PCG_CTRL
                    --                bit 0-1: character selector -> (PCG_ADDR + 256*(PCG_CTRL&3)) -> address in the range of the upper 128 characters font
                    --                bit 2 : font selector -> PCG_CTRL&2 == 0 -> 1st font else 2nd font
                    --                bit 3 : select which font for display
                    --                bit 4 : use programmable font for display
                    --                bit 5 : set programmable upper font -> PCG_CTRL&20 == 0 -> fixed upper 128 characters else programmable upper 128 characters
                    --                So if you want to change a character pattern (only doable in the upper 128 characters of a font), you need to:
                    --                - set bit 5 to 1 : PCG_CTRL[5] = 1
                    --                - set the font to select : PCG_CTRL[2] = font_number
                    --                - set the first row address of the character: PCG_ADDR[0..7] = row[0..7] and PCG_CTRL[0..1] = row[8..9]
                    --                - set the 8 pixels of the row in PCG_DATA
                    --
                    if CS_PCGn = '0' then
                        -- Set the PCG Data to program to RAM. 
                        if VIDEO_ADDRi(1 downto 0) = "00" then
                            PCG_DATA              <= VIDEO_DATA_INi(7 downto 0);
                        end if;

                        -- Set the PCG Address in RAM. 
                        if VIDEO_ADDRi(1 downto 0) = "01" then
                            CGRAM_ADDR(7 downto 0)<= VIDEO_DATA_INi(7 downto 0);
                        end if;

                        -- Set the PCG Control register.
                        if VIDEO_ADDRi(1 downto 0) = "10"  then
                            CGRAM_ADDR(11 downto 8)<= (VIDEO_DATA_INi(2) and MODE_VIDEO_MZ80A) & '1' & VIDEO_DATA_INi(1 downto 0);
                            CGRAM_WEn             <= not VIDEO_DATA_INi(4);
                            CGRAM_SEL             <= VIDEO_DATA_INi(5);
                        end if;
                    end if;
                end if; -- Write block

                -- Sharp MZ Series Emulation configuration. When using the emulation an external I/O processor changes the settings via a configuration string and not via
                -- register writes. This block detects changes and updates internal settings.
                --
         --       if CONFIG(CHANGED) = '1' then
--NEED TO TAKE INTO ACCOUNT THE RENDERING, ONLY CHANGE DURING VERTICAL BLANKING
                    -- When not using the emulation this vector wont change and therefore no updates will be made.
             --       if CONFIG(VGAMODE) /= CONFIG_LAST(VGAMODE) then
            --            VGA_MODE_REG(CONFIG(VGAMODE)'length-1 downto 0) <= CONFIG(VGAMODE);
             --       end if;
                    -- Machine mode change?
                    if CONFIG(CURRENTMACHINE) /= CONFIG_LAST(CURRENTMACHINE) then
                        --
                        -- Setup the machine type based on the CONFIG string.
                        --
                        if CONFIG(MZ80K) = '1' and VIDEO_MODE_REG(3 downto 0) /= "0000" then
                            VIDEO_MODE_REG(3 downto 0)<= "0000";
                        elsif CONFIG(MZ80C) = '1' and VIDEO_MODE_REG(3 downto 0) /= "0001" then
                            VIDEO_MODE_REG(3 downto 0)<= "0001";
                        elsif CONFIG(MZ1200) = '1' and VIDEO_MODE_REG(3 downto 0) /= "0010" then
                            VIDEO_MODE_REG(3 downto 0)<= "0010";
                        elsif CONFIG(MZ80A) = '1' and VIDEO_MODE_REG(3 downto 0) /= "0011" then
                            VIDEO_MODE_REG(3 downto 0)<= "0011";
                        elsif CONFIG(MZ700) = '1' and VIDEO_MODE_REG(3 downto 0) /= "0100" then
                            VIDEO_MODE_REG(3 downto 0)<= "0100";
                        elsif CONFIG(MZ800) = '1' and VIDEO_MODE_REG(3 downto 0) /= "0101" then
                            VIDEO_MODE_REG(3 downto 0)<= "0101";
                        elsif CONFIG(MZ1500) = '1' and VIDEO_MODE_REG(3 downto 0) /= "0110" then
                            VIDEO_MODE_REG(3 downto 0)<= "0110";
                        elsif CONFIG(MZ80B) = '1' and VIDEO_MODE_REG(3 downto 0) /= "0111" then
                            VIDEO_MODE_REG(3 downto 0)<= "0111";
                        elsif CONFIG(MZ2000) = '1' and VIDEO_MODE_REG(3 downto 0) /= "1000" then
                            VIDEO_MODE_REG(3 downto 0)<= "1000";
                        elsif CONFIG(MZ2200) = '1' and VIDEO_MODE_REG(3 downto 0) /= "1001" then
                            VIDEO_MODE_REG(3 downto 0)<= "1001";
                        elsif CONFIG(MZ2500) = '1' and VIDEO_MODE_REG(3 downto 0)<= "1010" then
                            VIDEO_MODE_REG(3 downto 0)<= "1010";
                        end if;
                        CONFIG_LAST(CURRENTMACHINE)   <= CONFIG(CURRENTMACHINE);
                    end if;
                    -- Display mode change?
                    if CONFIG(CURRENTDISPLAY) /= CONFIG_LAST(CURRENTDISPLAY) then
                        -- 80 column and colour flags follow the configuration (the original toggled them).
                        VIDEO_MODE_REG(4)             <= CONFIG(NORMAL80) or CONFIG(COLOUR80);
                        VIDEO_MODE_REG(5)             <= CONFIG(COLOUR) or CONFIG(COLOUR80);
                        CONFIG_LAST(CURRENTDISPLAY)   <= CONFIG(CURRENTDISPLAY);
                    end if;
                    -- Option changes?
                    if CONFIG(VRAMDISABLE) /= CONFIG_LAST(VRAMDISABLE) or CONFIG(CURRENTMACHINE) /= CONFIG_LAST(CURRENTMACHINE) then
                        GRAM_MODE_REG(4)              <= CONFIG(VRAMDISABLE);
                        CONFIG_LAST(VRAMDISABLE)      <= CONFIG(VRAMDISABLE);
                    end if;
                    if CONFIG(GRAMDISABLE) /= CONFIG_LAST(VRAMDISABLE) or CONFIG(CURRENTMACHINE) /= CONFIG_LAST(CURRENTMACHINE) then
                        GRAM_MODE_REG(5)              <= CONFIG(GRAMDISABLE);
                        CONFIG_LAST(GRAMDISABLE)      <= CONFIG(GRAMDISABLE);
                    end if;
                    if CONFIG(VRAMWAIT) /= CONFIG_LAST(VRAMWAIT) or CONFIG(CURRENTMACHINE) /= CONFIG_LAST(CURRENTMACHINE) then
                        GRAM_MODE_REG(6)              <= CONFIG(VRAMWAIT);
                        CONFIG_LAST(VRAMWAIT)         <= CONFIG(VRAMWAIT);
                    end if;
                    if CONFIG(PCGRAM) /= CONFIG_LAST(PCGRAM) or CONFIG(CURRENTMACHINE) /= CONFIG_LAST(CURRENTMACHINE) then
                        GRAM_MODE_REG(7)              <= CONFIG(PCGRAM);
                        CONFIG_LAST(PCGRAM)           <= CONFIG(PCGRAM);
                    end if;
                    -- GRAM installed change?
                    if CONFIG(GRAPHICSOPTION) /= CONFIG_LAST(GRAPHICSOPTION) or CONFIG(CURRENTMACHINE) /= CONFIG_LAST(CURRENTMACHINE)  then
                        OPTION_REG(0)                 <= CONFIG(GRAPHICSOPTION)(OPT_GRAMI);
                        OPTION_REG(1)                 <= CONFIG(GRAPHICSOPTION)(OPT_GRAMII);
                        OPTION_REG(2)                 <= CONFIG(GRAPHICSOPTION)(OPT_GRAMIII);
                        OPTION_REG(3)                 <= CONFIG(GRAPHICSOPTION)(OPT_PCG);
                        CONFIG_LAST(GRAPHICSOPTION)   <= CONFIG(GRAPHICSOPTION);
                    end if;
                    -- OSD Menu/Status change?
                    if CONFIG(MENUENABLE) /= CONFIG_LAST(MENUENABLE) then
                        VGA_ATTR_REG(6)               <= CONFIG(MENUENABLE);
                        CONFIG_LAST(MENUENABLE)       <= CONFIG(MENUENABLE);
                    end if;
                    if CONFIG(STATUSENABLE) /= CONFIG_LAST(STATUSENABLE) then
                        VGA_ATTR_REG(7)               <= CONFIG(STATUSENABLE);
                        CONFIG_LAST(STATUSENABLE)     <= CONFIG(STATUSENABLE);
                    end if;
               -- end if;

                -- Update the video mode according to the stored register value.
                --
                -- Bits [3:0] define the Video Module machine compatibility.
                -- Bit    [4] defines the 40/80 column mode, 0 = 40 col, 1 = 80 col.
                -- Bit    [5] defines the colour mode, 0 = mono, 1 = colour - ignored on certain modes.
                -- Bit    [6] defines wether PCGRAM is enabled, 0 = disabled, 1 = enabled.
                --
                MODE_VIDEO_MZ80K                  <= '0';
                MODE_VIDEO_MZ80C                  <= '0';
                MODE_VIDEO_MZ1200                 <= '0';
                MODE_VIDEO_MZ80A                  <= '0';
                MODE_VIDEO_MZ700                  <= '0';
                MODE_VIDEO_MZ1500                 <= '0';
                MODE_VIDEO_MZ800                  <= '0';
                MODE_VIDEO_MZ80B                  <= '0';
                MODE_VIDEO_MZ2000                 <= '0';
                MODE_VIDEO_MZ2200                 <= '0';
                MODE_VIDEO_MZ2500                 <= '0';
                MODE_VIDEO_MONO                   <= '0';
                MODE_VIDEO_MONO80                 <= '0';
                MODE_VIDEO_COLOUR                 <= '0';
                MODE_VIDEO_COLOUR80               <= '0';
                case MODE_VIDEO_BASE is

                    when MODE_MZ80K =>
                        MODE_VIDEO_MZ80K          <= '1';

                        -- The MZ-80K is a mono machine, so only consider the 40/80 column flag as extensions to the original hardware were made for CP/M.
                        if VIDEO_MODE_REG(4) = '0' then
                            MODE_VIDEO_MONO       <= '1';
                        else
                            MODE_VIDEO_MONO80     <= '1';
                        end if;

                    when MODE_MZ80C =>
                        MODE_VIDEO_MZ80C          <= '1';

                        -- The MZ-80C is a mono machine, so only consider the 40/80 column flag as extensions to the original hardware were made for CP/M.
                        if VIDEO_MODE_REG(4) = '0' then
                            MODE_VIDEO_MONO       <= '1';
                        else
                            MODE_VIDEO_MONO80     <= '1';
                        end if;

                    when MODE_MZ1200 =>
                        MODE_VIDEO_MZ1200         <= '1';

                        -- The MZ-1200 is a mono machine, so only consider the 40/80 column flag as extensions to the original hardware were made for CP/M.
                        if VIDEO_MODE_REG(4) = '0' then
                            MODE_VIDEO_MONO       <= '1';
                        else
                            MODE_VIDEO_MONO80     <= '1';
                        end if;

                    when MODE_MZ80A =>
                        MODE_VIDEO_MZ80A          <= '1';

                        -- The MZ-80A is a monochrome machine by default but can have the optional colour board, so consider the
                        -- colour flag (4) and the 40/80 column flag (3) to setup correct mode.
                        --
                        if VIDEO_MODE_REG(5) = '0' and VIDEO_MODE_REG(4) = '0' then
                            MODE_VIDEO_MONO       <= '1';
                        elsif VIDEO_MODE_REG(4) = '1' and VIDEO_MODE_REG(5) = '0' then
                            MODE_VIDEO_MONO80     <= '1';
                        elsif VIDEO_MODE_REG(4) = '0' and VIDEO_MODE_REG(5) = '1' then
                            MODE_VIDEO_COLOUR     <= '1';
                        else
                            MODE_VIDEO_COLOUR80   <= '1';
                        end if;

                    when MODE_MZ1500 =>
                        MODE_VIDEO_MZ1500         <= '1';

                        -- MZ-1500 is a colour machine, so only consider the 40/80 column switch.
                        if VIDEO_MODE_REG(4) = '0' then
                            MODE_VIDEO_COLOUR     <= '1';
                        else
                            MODE_VIDEO_COLOUR80   <= '1';
                        end if;

                    when MODE_MZ800 =>
                        -- Actual video mode depends on the LSI configuration.
                        -- MZ-800 is a colour machine which can operate as an MZ700 or an MZ800. The MZ700 is COLOUR 40 whilst the MZ800 mode can be 40 (320x200) or 80 (640x200).
                        if GD_DMD_MODE700 = '0' then
                            MODE_VIDEO_MZ800      <= '1';
                            GRAM_MODE_REG(5)      <= '0';
                            GRAM_MODE_REG(4)      <= '1';
                            if GD_DMD_320X200 = '1' then
                                MODE_VIDEO_COLOUR <= '1';
                            else
                                MODE_VIDEO_COLOUR80<= '1';
                            end if;
                        else
                            MODE_VIDEO_MZ700      <= '1';
                            MODE_VIDEO_COLOUR     <= '1';
                            GRAM_MODE_REG(5)      <= '1';
                            GRAM_MODE_REG(4)      <= '0';
                        end if;

                    when MODE_MZ80B =>
                        MODE_VIDEO_MZ80B          <= '1';

                        -- The MZ-80B is a monochrome machine so only consider monochrome. This is intentional as the GRAM used by the MZ80B
                        -- is used for the colour framebuffer, so true colour is not possible when using MZ80B compatible graphics. Colour is
                        -- possible if direct access to the colour frame buffers is used but this is a superset feature.
                        if VIDEO_MODE_REG(4) = '0' then
                            MODE_VIDEO_MONO       <= '1';
                        else
                            MODE_VIDEO_MONO80     <= '1';
                        end if;

                    when MODE_MZ2000 =>
                        MODE_VIDEO_MZ2000         <= '1';

                        -- The MZ-2000 is a monochrome machine by default but the external output is colour. By rerouting the internal video and regenerating it from RGB before
                        -- sending it on to the internal monitor we can simulate grey scale by adjusting the voltage level (contrast) to give shades of green. We only consider the
                        -- the 40/80 column flag (3) to setup correct mode as character output can only be mono.
                        --
                        if VIDEO_MODE_REG(4) = '0' then
                            MODE_VIDEO_MONO       <= '1';
                        else
                            MODE_VIDEO_MONO80     <= '1';
                        end if;

                    when MODE_MZ2200 =>
                        MODE_VIDEO_MZ2200         <= '1';

                        -- The MZ-2200 is a monochrome and colour machine, outputting both simultaneously. It is identical to the MZ-2000 with a fully populated MZ-1R01 graphics board installed.
                        --
                        if VIDEO_MODE_REG(4) = '0' then
                            MODE_VIDEO_MONO       <= '1';
                        else
                            MODE_VIDEO_MONO80     <= '1';
                        end if;

                    when MODE_MZ2500 =>
                        MODE_VIDEO_MZ2500         <= '1';

                        -- MZ-2500 is a colour graphics machine, so only consider the 40/80 column switch.
                        if VIDEO_MODE_REG(4) = '0' then
                            MODE_VIDEO_COLOUR     <= '1';
                        else
                            MODE_VIDEO_COLOUR80   <= '1';
                        end if;

                    -- Defaults to MZ-700 mode
                    --when MODE_MZ700 =>
                    when others =>
                        MODE_VIDEO_MZ700          <= '1';

                        -- MZ-700 is a colour machine, so only consider the 40/80 column switch.
                        if VIDEO_MODE_REG(4) = '0' then
                            MODE_VIDEO_COLOUR     <= '1';
                        else
                            MODE_VIDEO_COLOUR80   <= '1';
                        end if;

                end case;

                -- Set options as readable signals.
                GRAMI_ENABLED                     <= OPTION_REG(0);
                GRAMII_ENABLED                    <= OPTION_REG(1);
                GRAMIII_ENABLED                   <= OPTION_REG(2);
                PCG_ENABLED                       <= OPTION_REG(3);

                -- PCG RAM, enable/disable.
                PCG_RAM_SEL                       <= VIDEO_MODE_REG(6);

                -- The VGA Mode is used to change the type of VGA output frequency and resolution made to the external monitor.
            --    VGA_MODE_                  <= VGA_ATTR_REG(4 downto 3);

            end if; -- is RESETn
        end if; -- Rising clock edge block.

        -- Non-registered signal vectors for readback.
        -- Page register: [7] = CGROM Page setting, [6:3] = Current video mode, [0] = GRAM enabled setting.
        --PAGE_MODE_REG                 <= CGROM_PAGE & std_logic_vector(to_unsigned(VIDEOMODE_NEXT, 4)) & std_logic_vector(to_unsigned(MAX_COLUMN, 4)); --FBRAM_PAGE_ENABLE & MZ2K_VRAM_ENABLE & MZ2K_CHAR_ENABLE; --FBRAM_PAGE_ENABLE;
        PAGE_MODE_REG                 <= std_logic_vector(to_unsigned(VIDEOMODE_NEXT, 4)) & std_logic_vector(MAX_COLUMN(7 downto 4)); --FBRAM_PAGE_ENABLE & MZ2K_VRAM_ENABLE & MZ2K_CHAR_ENABLE; --FBRAM_PAGE_ENABLE;
    end process;
    
    -- Direct addressing Bus. Normally this is set to 0 during standard Sharp MZ operation, when 23:19 > 0 then direct addressing of the various video
    -- memory's is enabled.
    -- Address    A23 -A16
    -- 0x000000   00000000 - Normal Sharp MZ behaviour
    -- 0x200000   00010000 - Memory and I/O ports mapped into direct addressable memory location.
    --
    --                       A15 - A8 A7 -  A0
    --                       I/O registers are mapped to the bottom 256 bytes mirroring the I/O address.
    -- 0x2000A0              00000000 10100000 - 0xA0 - 
    --                       00000000 10100001 - 0xA1 - 
    --                       00000000 10100010 - 0xA2 - 
    --                       00000000 10100011 - 0xA3 - set the palette slot Off position to be adjusted.
    --                       00000000 10100100 - 0xA4 - set the palette slot On position to be adjusted.
    --                       00000000 10100101 - 0xA5 - set the red palette value according to the PALETTE_PARAM_SEL address.
    --                       00000000 10100110 - 0xA6 - set the green palette value according to the PALETTE_PARAM_SEL address.
    -- 0x2000A7              00000000 10100111 - 0xA7 - set the blue palette value according to the PALETTE_PARAM_SEL address.
    --                       00000000 10101000 - 0xA8 - Get OSD Menu Horizontal Size (X).
    --                       00000000 10101001 - 0xA9 - Get OSD Menu Vertical Size (Y).
    --                       00000000 10101010 - 0xAA - Get OSD Status Header Horizontal Size (X).
    --                       00000000 10101011 - 0xAB - Get OSD Status Header Vertical Size (Y).
    --                       00000000 10101100 - 0xAC - Get OSD Status Footer Horizontal Size (X).
    --                       00000000 10101101 - 0xAD - Get OSD Status Footer Vertical Size (Y).
    -- 0x2000B0              00000000 10110000 - 0xB0 - sets the active palette.
    -- 0x2000B1              00000000 10110001 - 0xB1 - 
    --                       00000000 10110010 - 0xB2 - set the GPU parameters.
    --                       00000000 10110011 - 0xB3 - set the graphics processor unit commands.
    --                       00000000 10111000 - 0xB8 - set the video mode. 
    --                       00000000 10111001 - 0xB9 - set the graphics mode.
    --                       00000000 10111010 - 0xBA - set the Red bit mask
    --                       00000000 10111011 - 0xBB - set the Green bit mask
    --                       00000000 10111100 - 0xBC - set the Blue bit mask
    -- 0x2000BD              00000000 10111101 - 0xBD - set the Video memory page in block C000:FFFF 
    --                       00000000 10111110 - 0xBE - set the VGA border colour and attributes.
    -- 0x2000BF              00000000 10111111 - 0xBF - set the VGA mode.
    --
    -- 0x2000E0              00000000 11100000 - 0xE0 MZ80B PPI
    --                       00000000 11100100 - 0xE4 MZ80B PIT
    -- 0x2000E8              00000000 11101000 - 0xE8 MZ80B PIO
    --
    --                       00000000 11110000 - 0xF0
    --                       00000000 11110001 - 0xF1
    --                       00000000 11110010 - 0xF2
    -- 0x2000F3              00000000 11110011 - 0xF3 
    --                       00000000 11110100 - 0xF4 set the MZ80B video in/out mode or MZ2000/2200 Colour CRT Background Colour Selection.
    --                       00000000 11110101 - 0xF5 MZ2000/2200 Priority, Bit 3 = 0, Character comes to foreground, = 1, Graphics comes to foreground. 2:0 = Colour
    --                       00000000 11110110 - 0xF6 MZ2000/2200 Bit 4 Graphics Display on CRT (H), 2:0 colour VRAM enable to Colour CRT / CRT (if enabled).
    --                       00000000 11110111 - 0xF7 MZ2000/2200 Selection of VRAM bank in memory map when enabled, 0 = None, 1 = Blue, 2 = Red, 3 = Green
    --
    --                       Memory registers are mapped to the E000 region as per base machines.
    -- 0x20E010              11100000 00010010 - Program Character Generator RAM. E010 - Write cycle (Read cycle = reset memory swap).
    --                       11100000 00010100 - Normal display select.
    --                       11100000 00010101 - Inverted display select.
    --                       11100010 00000000 - Scroll display register. E200 - E2FF
    -- 0x20E2FF              11111111
    --
    -- 0x210000   00100001 - Video/Attribute RAM / MZ800 Graphics RAM . 64K Window.
    -- 0x218000              10000000 00000000 - MZ800 Graphics RAM Window Start lower 16K
    -- 0x219FFF              10011111 11111111
    -- 0x21A000              10100000 00000000 - MZ800 Graphics RAM Window Start upper 16K
    -- 0x21BFFF              10111111 11111111
    -- 0x21D000              11010000 00000000 - Video RAM
    -- 0x21D7FF              11010111 11111111
    -- 0x21D800              11011000 00000000 - Attribute RAM
    -- 0x21DFFF              11011111 11111111
    --
    -- 0x220000   00010010 - Character Generator RAM
    -- 0x220000              00000000 00000000 - CGROM
    -- 0x220FFF              00001111 11111111 
    -- 0x221000              00010000 00000000 - CGRAM
    -- 0x221FFF              00011111 11111111
    --
    -- 0x240000   00010100 - Red framebuffer.
    --                       00000000 00000000 - Red pixel addressed framebuffer. Also MZ-80B GRAM I memory in lower 8K
    -- 0x243FFF              00111111 11111111
    -- 0x250000   00010101 - Blue framebuffer.
    --                       00000000 00000000 - Blue pixel addressed framebuffer. Also MZ-80B GRAM II memory in lower 8K
    -- 0x253FFF              00111111 11111111
    -- 0x260000   00010110 - Green framebuffer.
    --                       00000000 00000000 - Green pixel addressed framebuffer.
    -- 0x263FFF              00111111 11111111
    -- 0x270000   00010111 - Blue Menu/Status framebuffer.
    -- 0x271FFF              00011111 11111111
    -- 0x280000   00011000 - Red Menu/Status framebuffer.
    -- 0x281FFF              00011111 11111111
    -- 0x290000   00011001 - Green Menu/Status framebuffer.
    -- 0x291FFF              00011111 11111111
    -- 0x2A0000   00011010 - Red/Green/Blue Menu/Status framebuffer write only.
    -- 0x291FFF              00011111 11111111
    CS_VIDEO_LEGACYn      <= '0'                                             when VIDEO_ADDRi(23 downto 16) = "00000000"
                             else '1';
    CS_VIDEO_IO_DIRECTn   <= '0'                                             when VIDEO_ADDRi(23 downto 16) = "00100000"
                             else '1';
    CS_VIDEO_VRAM_DIRECTn <= '0'                                             when VIDEO_ADDRi(23 downto 16) = "00100001"
                             else '1';
    CS_VIDEO_CGROM_DIRECTn<= '0'                                             when VIDEO_ADDRi(23 downto 13) = "00100010000"
                             else '1';
    CS_VIDEO_CGRAM_DIRECTn<= '0'                                             when VIDEO_ADDRi(23 downto 13) = "00100010001"
                             else '1';
    CS_VIDEO_R_FB_DIRECTn <= '0'                                             when VIDEO_ADDRi(23 downto 16) = "00100100"
                             else '1';
    CS_VIDEO_B_FB_DIRECTn <= '0'                                             when VIDEO_ADDRi(23 downto 16) = "00100101"
                             else '1';
    CS_VIDEO_G_FB_DIRECTn <= '0'                                             when VIDEO_ADDRi(23 downto 16) = "00100110"
                             else '1';
    CS_VIDEO_FB_DIRECTn   <= '0'                                             when VIDEO_ADDRi(23 downto 18) = "001001" and VIDEO_ADDRi(17 downto 16) /= "11"
                             else '1';
    CS_VIDEO_B_OSD_DIRn   <= '0'                                             when VIDEO_ADDRi(23 downto 16) = "00100111"
                             else
                             '0'                                             when VIDEO_ADDRi(23 downto 16) = "00101010"
                             else '1';
    CS_VIDEO_R_OSD_DIRn   <= '0'                                             when VIDEO_ADDRi(23 downto 16) = "00101000"
                             else
                             '0'                                             when VIDEO_ADDRi(23 downto 16) = "00101010"
                             else '1';
    CS_VIDEO_G_OSD_DIRn   <= '0'                                             when VIDEO_ADDRi(23 downto 16) = "00101001"
                             else
                             '0'                                             when VIDEO_ADDRi(23 downto 16) = "00101010"
                             else '1';

    -- CPU / RAM signals and selects.
    --
    Z80_MA                <= "00" & VIDEO_ADDRi(9 downto 0)                  when MODE_VIDEO_MZ80K = '1'  or MODE_VIDEO_MZ80C = '1'
                             else
                             VIDEO_ADDRi(11 downto 0);

    CS_5XXXn              <= '0'                                             when VIDEO_MREQni = '0' and VIDEO_ADDRi(15 downto 12) = "0101"
                             else '1';
    CS_CXXXn              <= '0'                                             when VIDEO_MREQni = '0' and VIDEO_ADDRi(15 downto 12) = "1100"
                             else '1';
    CS_DXXXn              <= '0'                                             when VIDEO_MREQni = '0' and VIDEO_ADDRi(15 downto 12) = "1101"
                             else '1';
                             -- Standard access to memory mapped I/O.
    CS_EXXXn              <= '0'                                             when VIDEO_MREQni = '0' and VIDEO_ADDRi(15 downto 11) = "11100" and CS_VIDEO_IO_DIRECTn = '0'
                             else
                             '0'                                             when VIDEO_MREQni = '0' and VIDEO_ADDRi(15 downto 11) = "11100" and CS_VIDEO_LEGACYn = '0'   and FBRAM_PAGE_ENABLE = '0'  and MODE_VIDEO_MZ80B = '0' and MODE_VIDEO_MZ2000 = '0' and MODE_VIDEO_MZ2200 = '0' -- Normal memory mapped I/O for MZ80K series machines.
                             else '1';
                          -- MZ800 Graphics RAM enable. Range 0x8000:9FFF with 320x200 enabled, 0xA000:BFFF with 640x200 enabled.
    CS_800_GRAMn          <= '0'                                             when VIDEO_MREQni = '0' and (CS_VIDEO_LEGACYn = '0'  or CS_VIDEO_VRAM_DIRECTn = '0')      and VIDEO_ADDRi(15 downto 13) = "100"                             and MODE_VIDEO_MZ800 = '1'
                             else
                             '0'                                             when VIDEO_MREQni = '0' and (CS_VIDEO_LEGACYn = '0'  or CS_VIDEO_VRAM_DIRECTn = '0')      and VIDEO_ADDRi(15 downto 13) = "101"  and GD_DMD_640X200 = '1'   and MODE_VIDEO_MZ800 = '1'
                             else '1';
                             -- MZ80B Graphics RAM enabled, range E000:FFFF is mapped to graphics RAMI + II on MZ80B and D000:DFFF for standard video.
    CS_80B_GRAMn          <= '0'                                             when VIDEO_MREQni = '0' and CS_VIDEO_LEGACYn = '0' and unsigned(VIDEO_ADDRi(15 downto 0)) >= X"E000" and unsigned(VIDEO_ADDRi(15 downto 0)) <= X"FFFF" and FBRAM_PAGE_ENABLE = '0'  and MODE_VIDEO_MZ80B = '1'  and MZ80B_VRAM_ENABLE = '1'  and MZ80B_VRAM_LO_ADDR = '0' 
                             else
                             -- MZ80B Graphics RAM enabled, range 6000:7FFF is mapped to graphics RAMI + II and 5000:5FFF to standard video.
                             '0'                                             when VIDEO_MREQni = '0' and CS_VIDEO_LEGACYn = '0' and unsigned(VIDEO_ADDRi(15 downto 0)) >= X"6000" and unsigned(VIDEO_ADDRi(15 downto 0)) <= X"7FFF" and FBRAM_PAGE_ENABLE = '0'  and MODE_VIDEO_MZ80B = '1'  and MZ80B_VRAM_ENABLE = '1'  and MZ80B_VRAM_LO_ADDR = '1'
                             else '1';
                             -- MZ2000/2200 Graphics RAM enabled, range C000:FFFF is mapped to one of the 16K colour RAM banks, we just enable access to it.
    CS_MZ2K_GRAMn         <= '0'                                             when VIDEO_MREQni = '0' and CS_VIDEO_LEGACYn = '0' and unsigned(VIDEO_ADDRi(15 downto 0)) >= X"C000" and unsigned(VIDEO_ADDRi(15 downto 0)) <= X"FFFF" and FBRAM_PAGE_ENABLE = '0'  and (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1') and MZ2K_VRAM_ENABLE = '1'   and MZ2K_CHAR_ENABLE = '0'
                             else '1';
                             -- Graphics RAM enabled, range C000:FFFF is mapped to graphics RAM.
    CS_FBRAMn             <= '0'                                             when VIDEO_MREQni = '0' and CS_VIDEO_LEGACYn = '0'     and VIDEO_ADDRi(15 downto 14) = "11"        and FBRAM_PAGE_ENABLE = '1'           and MZ80B_VRAM_ENABLE = '0'  and  MZ2K_VRAM_ENABLE = '0'
                             else '1';
    CS_IO_AXXn            <= '1';                                           -- tranZPUter controller registers (A0-BF: palette, GPU, modes) not used on MiSTer.
    CS_IO_BXXn            <= '1';                                           -- tranZPUter controller registers (A0-BF: palette, GPU, modes) not used on MiSTer.
    CS_IO_CXXn            <= '0'                                             when (VIDEO_IORQni = '0' or (CS_VIDEO_IO_DIRECTn = '0' and VIDEO_ADDRi(15 downto 11) = "00000"))   and VIDEO_ADDRi(7 downto 4) = "1100"
                             else '1';
    CS_IO_DXXn            <= '0'                                             when (VIDEO_IORQni = '0' or (CS_VIDEO_IO_DIRECTn = '0' and VIDEO_ADDRi(15 downto 8) = "00000000")) and VIDEO_ADDRi(7 downto 4) = "1101"
                             else '1';
    CS_IO_EXXn            <= '0'                                             when (VIDEO_IORQni = '0' or (CS_VIDEO_IO_DIRECTn = '0' and VIDEO_ADDRi(15 downto 8) = "00000000")) and VIDEO_ADDRi(7 downto 4) = "1110"
                             else '1';
    CS_IO_FXXn            <= '0'                                             when (VIDEO_IORQni = '0' or (CS_VIDEO_IO_DIRECTn = '0' and VIDEO_ADDRi(15 downto 8) = "00000000")) and VIDEO_ADDRi(7 downto 4) = "1111"
                             else '1';

    -- Program Character Generator RAM. E010 - Write cycle (Read cycle = reset memory swap).
    CS_PCGn               <= '0'                                             when CS_EXXXn = '0'    and VIDEO_ADDRi(10 downto 4) = "0000001"   and PCG_ENABLED = '1'
                             else '1';                                                                   -- E010 -> E01f
    -- Invert display register. E014/E015
    CS_INVERTn            <= '0'                                             when CS_EXXXn = '0'    and Z80_MA(11 downto 2) = "0000000101"
                             else '1';
    -- Scroll display register. E200 - E2FF
    CS_SCROLLn            <= '0'                                             when CS_EXXXn = '0'    and VIDEO_ADDRi(10 downto 8)="010"
                             else '1';

    -- PPI Select.
    CS_80K_PPIn           <= '0'                                             when CS_EXXXn = '0'    and VIDEO_ADDRi(10 downto 2) = "000000000"
                             else '1';

    -- 0xB0 sets the palette. The Video Module supports 4 bit per colour output but there is only enough RAM for 1 bit per colour so the pallette is used to change the colours output.
    --                       Bits [7:0] defines the pallete number. This indexes a lookup table which contains the required 4bit output per 1bit input.
    CS_FB_PALETTEn        <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0000"
                             else '1';
    -- 0xB2 set parameters. Store parameters in a long word to be used by the graphics command processor.
    -- The parameter word is 128 bit and each write to the parameter word shifts left by 8 bits and adds the new byte at bits 7:0.
    CS_FB_PARAMSn         <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0010"
                             else '1';
    -- 0xB3 set the graphics processor unit commands.
    --                       Bits [5:0] - 0 = Reset parameters.
    --                                    1 = Clear to val. Start Location (16 bit), End Location (16 bit), Red Filter, Green Filter, Blue Filter
    CS_FB_GPUn            <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0011"
                             else '1';
    -- 0xB8 set the video mode. 
    --                       Bits [3:0] define the Video Module machine compatibility. 0000 = MZ80K, 0001 = MZ80C, 0010 = MZ1200, 0011 = MZ80A, 0100 = MZ-700, 0101 = MZ-1500, 0110 = MZ-800, 0111 = MZ-80B, 1000 = MZ-2000, 1001 = MZ-2200, 1010 = MZ-2500.
    --                       Bit    [4] defines the 40/80 column mode, 0 = 40 col, 1 = 80 col.
    --                       Bit    [5] defines the colour mode, 0 = mono, 1 = colour - ignored on certain modes.
    --                       Bit    [6] defines wether PCGRAM is enabled, 0 = disabled, 1 = enabled.
    CS_FB_VMn             <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1000"
                             else '1';
    -- 0xB9 set the graphics mode. 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
    --                               5 = GRAM Output Enable (=0), 4 = VRAM Output Enable (=0),
    --                             3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
    --                             1/0 = Read mode (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
    CS_FB_CTLn            <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1001"
                             else '1';
    -- 0xBA set the Red bit mask (1 bit = 1 pixel, 8 pixels per byte).
    CS_FB_REDn            <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1010"
                             else '1';
    -- 0xBB set the Green bit mask (1 bit = 1 pixel, 8 pixels per byte).
    CS_FB_GREENn          <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1011"
                             else '1';
    -- 0xBC set the Blue bit mask (1 bit = 1 pixel, 8 pixels per byte).
    CS_FB_BLUEn           <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1100"
                             else '1';
    -- 0xBD - Video memory page register. [1:0] switches in 16Kb page (3 pages) of graphics ram to C000 - FFFF. Bits [1:0] = page, 00 = off, 01 = Red, 10 = Green, 11 = Blue GRAM paged in. This overrides all MZ700/MZ80B page switching functions. [7] 0 - normal, 1 - switches in CGROM for upload at D000:DFFF.
    CS_FB_PAGEn           <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1101"
                             else '1';
    -- 0xBE set the VGA border colour and attributes. The VGA modes have areas not used by the graphics output, this register allows this area to be set to a specific colour (when colour mode enabled).
    --                       Bits [2:0] define the border colour, 2 = R, 1 = G, 0 = B, Bit  [6]   - enable the on screen menu display, Bit  [7]   - enable the on screen status display.
    CS_FB_VGATTRn         <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1110"
                             else '1';
    -- 0xBF set the VGA mode. This register sets the output resolution, frequency etc.
    --                       Bits [3:0] define the VGA output mode.
    CS_FB_VGAMODEn        <= '0'                                             when CS_IO_BXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1111"
                             else '1';

    -- 0xCF - Graphics Display LSI (MZ800) Control Register.
    CS_GCRTCn             <= '0'                                             when CS_IO_CXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1111" and MODE_VIDEO_BASE = MODE_MZ800   -- MZ-800 CRT Control Register select.
                             else '1';
    -- 0xCE - Graphics Display LSI (MZ800) Mode Register.
    CS_GDMDn              <= '0'                                             when CS_IO_CXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1110" and MODE_VIDEO_BASE = MODE_MZ800   -- MZ-800 CRT Command Register select.
                             else '1';
    -- 0xCD - Graphics Display LSI (MZ800) Read Format Register.
    CS_GRFn               <= '0'                                             when CS_IO_CXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1101" and MODE_VIDEO_BASE = MODE_MZ800   -- MZ-800 CRT Read Format Register select.
                             else '1';
    -- 0xCC - Graphics Display LSI (MZ800) Write Format Register.
    CS_GWFn               <= '0'                                             when CS_IO_CXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "1100" and MODE_VIDEO_BASE = MODE_MZ800   -- MZ-800 CRT Write Format Register select.
                             else '1';
    -- 0xF0 - Graphics Display LSI (MZ800) Pallet Register.
    CS_GPALLETn           <= '0'                                             when CS_IO_FXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0000" and MODE_VIDEO_BASE = MODE_MZ800   -- MZ-800 CRT Pallet Register select.
                             else '1';

    -- MZ80B/MZ2000/MZ2200 I/O Registers in range E0-EB,
    -- 0xE0:0xE3 - 9255 PPI
    CS_80B_PPIn           <= '0'                                             when CS_IO_EXXn = '0'  and VIDEO_ADDRi(3 downto 2) = "00"   and (MODE_VIDEO_MZ80B = '1' or MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')
                             else '1';
    -- 0xE4:0xE7 - 8253 Programmable Interval Timer
    CS_80B_PITn           <= '0'                                             when CS_IO_EXXn = '0'  and VIDEO_ADDRi(3 downto 2) = "01"   and (MODE_VIDEO_MZ80B = '1' or MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')
                             else '1';
    -- 0xE8:0xEB - Z80 PIO
    CS_80B_PIOn           <= '0'                                             when CS_IO_EXXn = '0'  and VIDEO_ADDRi(3 downto 2) = "10"   and (MODE_VIDEO_MZ80B = '1' or MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')
                             else '1';

    -- 0xF4 - Configure external CRT background colour.
    -- Bit 2:0 | Blue       | Red       | Green
    -- ------- | ---------- | --------- | -----
    -- 00        X            X           X
    -- 01        O            X           X
    -- 02        X            O           X
    -- 03        O            O           X
    -- 04        X            X           O
    -- 05        O            X           O
    -- 06        X            O           O
    -- 07        O            O           O
    -- ie. Bit 0 - Select Blue, Bit 1 - Select Red, Bit 2 - Select Green.
    CS_CRTBKCOLRn         <= '0'                                             when CS_IO_FXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0100" and (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')
                             else '1';
    -- 0xF5 - Graphics priority register, character or a graphics selected colour has front display priority.
    -- Bit 3:0 | Character    | Blue       | Red       | Green   - Character pixels take priority
    -- ------- | ---------    | ----       | ---       | -----
    -- 00      |              | X          | X         | X
    -- 01      |              | O          | X         | X
    -- 02      |              | X          | O         | X
    -- 03      |              | O          | O         | X
    -- 04      |              | X          | X         | O
    -- 05      |              | O          | X         | O
    -- 06      |              | X          | O         | O
    -- 07      |              | O          | O         | O
    -- ------- | Graphic      | Blue       | Red       | Green   - Graphic pixels take priority
    -- 08      |              | X          | X         | X
    -- 09      |              | O          | X         | X
    -- 10      |              | X          | O         | X
    -- 11      |              | O          | O         | X
    -- 12      |              | X          | X         | O
    -- 13      |              | O          | X         | O
    -- 14      |              | X          | O         | O
    -- 15      |              | O          | O         | O
    -- ie. Bit 3 = 0, select character, = 1 select graphics
    --     Bit 0 - Select blue, Bit 1 - Select Red, Bit 2 - Select Green
    CS_CRTGRPHPRIOn       <= '0'                                             when CS_IO_FXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0101" and (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')
                             else '1';
    -- 0xF6 - Graphics output select on CRT
    -- Bit 3:0 | Graphic Ovly | Blue       | Red       | Green
    --         | on CRT       |            |           |
    -- ------- | ---------    | ----       | ---       | -----
    -- 00      |    O         | X          | X         | X
    -- 01      |    O         | O          | X         | X
    -- 02      |    O         | X          | O         | X
    -- 03      |    O         | O          | O         | X
    -- 04      |    O         | X          | X         | O
    -- 05      |    O         | O          | X         | O
    -- 06      |    O         | X          | O         | O
    -- 07      |    O         | O          | O         | O
    -- 08      |    X         | X          | X         | X
    -- 09      |    X         | O          | X         | X
    -- 10      |    X         | X          | O         | X
    -- 11      |    X         | O          | O         | X
    -- 12      |    X         | X          | X         | O
    -- 13      |    X         | O          | X         | O
    -- 14      |    X         | X          | O         | O
    -- 15      |    X         | O          | O         | O
    -- ie. Bit 3 = 0 - graphics enabled on CRT, = 1 - graphics disabled on CRT
    CS_CRTGRPHSELn        <= '0'                                             when CS_IO_FXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0110" and (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')
                             else '1';
    -- 0xF7 - Graphics RAM colour bank select.
    -- Bit 2:0 | Blue       | Red       | Green
    -- ------- | ---------- | --------- | -----
    -- 00      | X          | X         | X
    -- 01      | O          | X         | X
    -- 02      | X          | O         | X
    -- 03      | X          | X         | O
    CS_GRAMCOLRSELn       <= '0'                                             when CS_IO_FXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0111" and (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')
                             else '1';

    -- 0xF4 set the MZ80B video in/out mode.
    -- Output data | V-RAM GRPH I | V-RAM GRPH II
    -- to port $F4 | Input Output | Input Output
    -- 00              0     X        X     X
    -- 01              X     X        0     X
    -- 02              0     0        X     X
    -- 03              X     0        0     X
    -- 0c              0     X        X     O
    -- OD              X     X        0     O
    -- OE              0     0        X     O
    -- OF              X     0        0     O
    -- Note Input  0: V-RAM transfer enabled
    --             X: V-RAM transfer disabled
    --      Output 0: shown on CRT display
    --             X: not shown on CRT display
    CS_80B_VMODEn         <= '0'                                             when CS_IO_FXXn = '0'  and VIDEO_ADDRi(3 downto 0) = "0100"  and (MODE_VIDEO_MZ80B = '1' or MODE_VIDEO_MZ2200 = '1')
                             else '1';

    -- Wait state generation, when the GRAM Frame Buffer is being written to and the CPU is attempting to write, pause the CPU.
    VWAITn_V_CSYNC        <= 'Z'                                             when MB_VIDEO_ENABLEn = '0'
                             else
                             '0'                                             when MB_VIDEO_ENABLEn = '1' and  V_BLANKi = '1' and CS_FBRAMn = '0'
                             else
                             '1'                                             when MB_VIDEO_ENABLEn = '1' and (V_BLANKi = '0' or  CS_FBRAMn = '1')
                             else '1';

    -- VRAM mux between the CPU signals and the GPU. GPU takes priority.
    --
    VRAM_ADDR             <= VRAM_GPU_ADDR(11 downto 0)                      when VRAM_GPU_ENABLE = '1'
                             else
                             VIDEO_ADDRi(11 downto 0);
    VRAM_DI               <= X"000000" & VRAM_GPU_DI                         when VRAM_GPU_ENABLE = '1'
                             else
                             VIDEO_DATA_INi;
    VRAM_WEN              <= '1'                                             when VRAM_GPU_WEN = '1'
                             else
                             '1'                                             when VIDEO_WRni = '0'        and CS_DXXXn = '0'         and CS_VIDEO_LEGACYn = '0' and  MODE_VIDEO_MZ80B = '0'   and MODE_VIDEO_MZ2000 = '0'  and MODE_VIDEO_MZ2200 = '0'  and CGROM_PAGE = '0'    and FBRAM_PAGE_ENABLE = '0'
                             else
                             '1'                                             when VIDEO_WRni = '0'        and CS_DXXXn = '0'         and CS_VIDEO_LEGACYn = '0' and MODE_VIDEO_MZ80B = '1'    and MZ80B_VRAM_ENABLE = '1'  and MZ80B_VRAM_LO_ADDR = '0' 
                             else
                             '1'                                             when VIDEO_WRni = '0'        and CS_5XXXn = '0'         and CS_VIDEO_LEGACYn = '0' and MODE_VIDEO_MZ80B = '1'    and MZ80B_VRAM_ENABLE = '1'  and MZ80B_VRAM_LO_ADDR = '1' 
                             else
                             '1'                                             when VIDEO_WRni = '0'        and CS_DXXXn = '0'         and CS_VIDEO_LEGACYn = '0' and (MODE_VIDEO_MZ2000 = '1'   or MODE_VIDEO_MZ2200 = '1') and  MZ2K_CHAR_ENABLE = '1'  and MZ2K_VRAM_ENABLE = '1'
                             else
                             '1'                                             when VIDEO_WRni = '0'        and CS_DXXXn = '0'         and CS_VIDEO_VRAM_DIRECTn = '0'
                             else '0';
    VRAM_WEN_BYTE         <= '1'                                             when VIDEO_WRni = '1'
                             else
                             VIDEO_WR_BYTEi;
    VRAM_WEN_HWORD        <= '0'                                             when VIDEO_WRni = '1'
                             else
                             VIDEO_WR_HWORDi;

    -- OSD framebuffer and display control.
    OSD_ADDR              <= VIDEO_ADDRi(12 downto 0);

    OSD_WEN_R             <= '1'                                             when VIDEO_WRni = '0'        and CS_VIDEO_R_OSD_DIRn = '0' 
                             else '0';
    OSD_WEN_G             <= '1'                                             when VIDEO_WRni = '0'        and CS_VIDEO_G_OSD_DIRn = '0' 
                             else '0';
    OSD_WEN_B             <= '1'                                             when VIDEO_WRni = '0'        and CS_VIDEO_B_OSD_DIRn = '0' 
                             else '0';
    OSD_WEN_BYTE          <= '1'                                             when VIDEO_WRni = '1'
                             else
                             VIDEO_WR_BYTEi;
    OSD_WEN_HWORD         <= '0'                                             when VIDEO_WRni = '1'
                             else
                             VIDEO_WR_HWORDi;
    OSD_DI_R              <= VIDEO_DATA_INi;
    OSD_DI_G              <= VIDEO_DATA_INi;
    OSD_DI_B              <= VIDEO_DATA_INi;

    -- CGROM Data to CG RAM, either ROM -> RAM copy or Z80 provides map.
    --
    CGRAM_DI              <= X"000000" & CGROM_BIT_DO                        when CGRAM_SEL = '1'               -- Data from ROM
                             else
                             X"000000" & PCG_DATA                            when CGRAM_SEL = '0'               -- Data from PCG
                             else (others=>'0');
    CGRAM_WREN            <= '1'                                             when VIDEO_WRni = '0'        and ((CGRAM_WEn = '0' and CS_PCGn = '0') or (CS_VIDEO_CGRAM_DIRECTn = '0'))
                             else '0';
    CGRAM_WEN_BYTE        <= '1'                                             when VIDEO_WRni = '1'
                             else
                             VIDEO_WR_BYTEi;
    CGRAM_WEN_HWORD       <= '0'                                             when VIDEO_WRni = '1'
                             else
                             VIDEO_WR_HWORDi;
    
    --
    -- Font select
    --
    CGROM_DATA            <= CGROM_BIT_DO                                    when PCG_RAM_SEL ='0'
                             else
                             CGRAM_BIT_DO                                    when PCG_RAM_SEL ='0'        and CGRAM_SEL = '1'
                             else
                             PCG_DATA                                        when CS_PCGn='0'             and VIDEO_ADDRi(1 downto 0)="10" and VIDEO_WRni='0'
                             else
                             CGRAM_DO(7 downto 0)                            when PCG_RAM_SEL ='1'
                             else (others => '1');
    CG_ADDR               <= CGRAM_ADDR(11 downto 0)                         when CGRAM_WEn = '0'
                             else RENDR_CGROM_ADDR;
    CGROM_WEN             <= '1'                                             when VIDEO_WRni = '0'        and ((CS_DXXXn = '0' and CS_VIDEO_LEGACYn = '0' and CGROM_PAGE = '1' and MODE_VIDEO_MZ80B = '0' and MODE_VIDEO_MZ2000 = '0' and MODE_VIDEO_MZ2200 = '0' and FBRAM_PAGE_ENABLE = '0') or (CS_VIDEO_CGROM_DIRECTn = '0'))
                             else
                             -- MZ-800 CGRAM mode.
                             '1'                                             when VIDEO_WRni = '0'        and (CS_CXXXn = '0'  and CS_VIDEO_LEGACYn = '0' and MODE_VIDEO_BASE = MODE_MZ800 and MODE_VIDEO_MZ700 = '1')
                             else '0';
    CGROM_WEN_BYTE        <= '1'                                             when VIDEO_WRni = '1'
                             else
                             VIDEO_WR_BYTEi;
    CGROM_WEN_HWORD       <= '0'                                             when VIDEO_WRni = '1'
                             else
                             VIDEO_WR_HWORDi;
    
    
    -- The Graphics RAM is in 3 distinct blocks, 16Kbyte each, to allow for all the MZ models (MZ2500 wip - needs bigger VRAM/FPGA) and one block per colour (RGB). In MZ80B mode,
    -- only the first 8K of Red and Blue blocks are used, in MZ2000/2200 mode only the first 16K of Red, Blue and Green are used, custom mode allows full 3x16K to be
    -- used.
    --
    GRAM_ADDR             <= GRAM_GPU_ADDR(13 downto 0)                      when GRAM_GPU_ENABLE = '1'
                             else
                             VIDEO_ADDRi(13 downto 0)                        when CS_VIDEO_FB_DIRECTn = '1'   and (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')                 -- Full 16Kbyte is used.
                             else
                             '0' & VIDEO_ADDRi(12 downto 0)                  when CS_VIDEO_FB_DIRECTn = '1'   and MODE_VIDEO_MZ80B = '1'                                               -- Only the first 8Kbyte is used.
                             else
                             GD_DMA_ADDR(11 downto 0) & "00"                 when CS_VIDEO_FB_DIRECTn = '1'   and MODE_VIDEO_MZ800 = '1'   and GD_DMD_320X200 = '1'                    -- The register calculated video RAM address for MZ800 mode in 320x200 mode.
                             else
                             GD_DMA_ADDR(12 downto 0) & '0'                  when CS_VIDEO_FB_DIRECTn = '1'   and MODE_VIDEO_MZ800 = '1'   and GD_DMD_640X200 = '1'                    -- The register calculated video RAM address for MZ800 mode in 640x200 mode.
                             else
                             VIDEO_ADDRi(13 downto 0);                                                                                                                                 -- All other modes use the full 16Kbyte address range.
                            -- direct writes when accessing individual pages.
    GRAM_DI_R_GI          <= X"000000" & GRAM_GPU_DI_R                       when GRAM_GPU_ENABLE = '1'
                             else
                             VIDEO_DATA_INi                                  when CS_VIDEO_R_FB_DIRECTn = '0'
                             else
                             GD_O_DATA                                       when CS_VIDEO_R_FB_DIRECTn = '1' and MODE_VIDEO_MZ800 = '1'   and GD_DMD_320X200 = '1'                    -- 32bit, 4 planes in 320x200 mode.
                             else
                             X"0000" & GD_O_DATA(15 downto 0)                when CS_VIDEO_R_FB_DIRECTn = '1' and MODE_VIDEO_MZ800 = '1'   and GD_DMD_640X200 = '1'                    -- 16bit, 2 planes in 640x200 mode.
                             else
                             X"000000" & (VIDEO_DATA_INi(7 downto 0) and GRAM_R_FILTER)  when GRAM_MODE_REG(3 downto 2) = "11"
                             else
                             X"000000" & VIDEO_DATA_INi(7 downto 0); 
                            -- direct writes when accessing individual pages.
    GRAM_DI_B_GII         <= X"000000" & GRAM_GPU_DI_B                       when GRAM_GPU_ENABLE = '1'
                             else
                             VIDEO_DATA_INi                                  when CS_VIDEO_B_FB_DIRECTn = '0'
                             else
                             GD_O_DATA                                       when CS_VIDEO_R_FB_DIRECTn = '1' and MODE_VIDEO_MZ800 = '1'   and GD_DMD_320X200 = '1'                    -- 32bit, 4 planes in 320x200 mode.
                             else
                             X"0000" & GD_O_DATA(15 downto 0)                when CS_VIDEO_R_FB_DIRECTn = '1' and MODE_VIDEO_MZ800 = '1'   and GD_DMD_640X200 = '1'                    -- 16bit, 2 planes in 640x200 mode.
                             else
                             X"000000" & (VIDEO_DATA_INi(7 downto 0) and GRAM_B_FILTER)  when GRAM_MODE_REG(3 downto 2) = "11"
                             else
                             X"000000" & VIDEO_DATA_INi(7 downto 0);
                            -- direct writes when accessing individual pages.
    GRAM_DI_G_GIII        <= X"000000" & GRAM_GPU_DI_G                       when GRAM_GPU_ENABLE = '1'
                             else
                             VIDEO_DATA_INi                                  when CS_VIDEO_G_FB_DIRECTn = '0'
                             else
                             X"000000" & (VIDEO_DATA_INi(7 downto 0) and GRAM_G_FILTER)  when GRAM_MODE_REG(3 downto 2) = "11"
                             else
                             X"000000" & VIDEO_DATA_INi(7 downto 0);
    GRAM_WEN_R_GI         <= '1'                                             when GWEN_GPU_R = '1'
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_80B_GRAMn = '0'    and GRAM_OPT_PAGE = '0'               and GRAMI_ENABLED = '1'
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_MZ2K_GRAMn = '0'   and GRAM_MODE_REG(3 downto 2) = "00"  and GRAMII_ENABLED = '1'
                             else
                             '1'                                             when GD_WEN_GI  = '1'       and MODE_VIDEO_MZ800 = '1'
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_FBRAMn = '0'       and (GRAM_MODE_REG(3 downto 2) = "00"  or GRAM_MODE_REG(3 downto 2) = "11")
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_VIDEO_R_FB_DIRECTn = '0'
                             else
                             '0';
    GRAM_WEN_B_GII        <= '1'                                             when GWEN_GPU_B = '1'
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_80B_GRAMn = '0'    and GRAM_OPT_PAGE = '1'               and GRAMII_ENABLED = '1'
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_MZ2K_GRAMn = '0'   and GRAM_MODE_REG(3 downto 2) = "10"  and GRAMI_ENABLED = '1'
                             else
                             '1'                                             when GD_WEN_GII = '1'       and MODE_VIDEO_MZ800 = '1'
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_FBRAMn = '0'       and (GRAM_MODE_REG(3 downto 2) = "10" or GRAM_MODE_REG(3 downto 2) = "11")
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_VIDEO_B_FB_DIRECTn = '0'
                             else
                             '0';
    GRAM_WEN_G_GIII       <= '1'                                             when GWEN_GPU_G = '1'
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_MZ2K_GRAMn = '0'   and GRAM_MODE_REG(3 downto 2) = "01"  and GRAMIII_ENABLED = '1'
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_FBRAMn = '0'       and (GRAM_MODE_REG(3 downto 2) = "01" or GRAM_MODE_REG(3 downto 2) = "11")
                             else
                             '1'                                             when VIDEO_WRni = '0'       and CS_VIDEO_G_FB_DIRECTn = '0'
                             else
                             '0';
    GRAM_WEN_BYTE         <= '0'                                             when MODE_VIDEO_MZ800 = '1' and (GD_WEN_GI = '1' or GD_WEN_GII = '1')
                             else
                             '1'                                             when VIDEO_WRni = '1'
                             else
                             VIDEO_WR_BYTEi;
    GRAM_WEN_HWORD        <= '0'                                             when MODE_VIDEO_MZ800 = '1' and (GD_WEN_GI = '1' or GD_WEN_GII = '1') and GD_DMD_320X200 = '1'
                             else
                             '1'                                             when MODE_VIDEO_MZ800 = '1' and (GD_WEN_GI = '1' or GD_WEN_GII = '1') and GD_DMD_640X200 = '1'
                             else
                             '0'                                             when VIDEO_WRni = '1'
                             else
                             VIDEO_WR_HWORDi;
    
    -- Work out the current video mode, which is used to look up the parameters for frame generation.
    --
    -- Video Mode - VGA Mode         -
    --     0        0 - Internal@60Hz   MZ80K/C/1200/A machines have a monochrome 60Hz display with scan of 512 x 260 for a 320x200 viewable area.               
    --     1        0 - Internal@60Hz   MZ80K/C/1200/A machines with an adapted monochrome 60Hz display with scan of 1024 x 260 for a 640x200 viewable area.		 
    --     2        0 - Internal@60Hz   MZ80K/C/1200/A machines with MZ700 style colour @ 60Hz display with scan of 512 x 260 for a 320x200 viewable area.		 
    --     3        0 - Internal@60Hz   MZ80K/C/1200/A machines with MZ700 style colour @ 60Hz display with scan of 1024 x 260 for a 640x200 viewable area.		 
    --     4        2 - 640x480@60Hz    Mode 0 upscaled as 640x480 @ 60Hz timings for 40Char mode monochrome. 			
    --     5        2 - 640x480@60Hz    Mode 1 upscaled as 640x480 @ 60Hz timings for 80Char mode monochrome.
    --     6        2 - 640x480@60Hz    Mode 2 upscaled as 640x480 @ 60Hz timings for 40Char mode colour. 			
    --     7        2 - 640x480@60Hz    Mode 3 upscaled as 640x480 @ 60Hz timings for 80Char mode colour.
    --     8        3 - 800x600@60Hz    Mode 0 upscaled as 800x600 @ 60Hz timings for 40Char mode monochrome. 			
    --     9        3 - 800x600@60Hz    Mode 1 upscaled as 800x600 @ 60Hz timings for 80Char mode monochrome.
    --     10       3 - 800x600@60Hz    Mode 2 upscaled as 800x600 @ 60Hz timings for 40Char mode colour. 			
    --     11       3 - 800x600@60Hz    Mode 3 upscaled as 800x600 @ 60Hz timings for 80Char mode colour.
    --     12       1 - Internal@60Hz   MZ80K/C/1200/A machines have a monochrome 60Hz display with scan of 512 x 260 for a 320x200 viewable area.               
    --     13       1 - Internal@60Hz   MZ80K/C/1200/A machines with an adapted monochrome 60Hz display with scan of 1024 x 260 for a 640x200 viewable area.		 
    --     14       1 - Internal@60Hz   MZ80K/C/1200/A machines with MZ700 style colour @ 50Hz display with scan of 568 x 312 for a 320x200 viewable area.
    --     15       1 - Internal@60Hz   MZ80K/C/1200/A machines with MZ700 style colour @ 50Hz display with scan of 1136 x 312 for a 640x200 viewable area.		 
    --     16       n/a                 MZ-2000 Internal monitor 40 column mode.
    --     17       n/a                 MZ-2000 Internal monitor 80 column mode.                                                                                   
    --
    -- The matrix indicates which machine mode the video controller is configured in and the matching video output mode..
    VIDEOMODE_NEXT        <= --0                                               when VIDEO_DEBUG = '1'
                             --else
                             0                                               when VGA_MODE_SEL(3 downto 0) = "0000" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' or MODE_VIDEO_MZ1200 = '1' or MODE_VIDEO_MZ80A = '1')     and MODE_VIDEO_MONO   = '1'
                             else
                             1                                               when VGA_MODE_SEL(3 downto 0) = "0000" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' or MODE_VIDEO_MZ1200 = '1' or MODE_VIDEO_MZ80A = '1')     and MODE_VIDEO_MONO80 = '1'
                             else
                             2                                               when VGA_MODE_SEL(3 downto 0) = "0000" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1' or MODE_VIDEO_MZ1500 = '1')                               and MODE_VIDEO_COLOUR   = '1'
                             else
                             3                                               when VGA_MODE_SEL(3 downto 0) = "0000" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1' or MODE_VIDEO_MZ1500 = '1')                               and MODE_VIDEO_COLOUR80 = '1' 

                             else

                             4                                               when VGA_MODE_SEL(3 downto 0) = "0010" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' or MODE_VIDEO_MZ1200 = '1' or MODE_VIDEO_MZ80A = '1')     and MODE_VIDEO_MONO   = '1'
                             else
                             5                                               when VGA_MODE_SEL(3 downto 0) = "0010" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' or MODE_VIDEO_MZ1200 = '1' or MODE_VIDEO_MZ80A = '1')     and MODE_VIDEO_MONO80 = '1'
                             else
                             6                                               when VGA_MODE_SEL(3 downto 0) = "0010" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1' or MODE_VIDEO_MZ1500 = '1')                               and MODE_VIDEO_COLOUR   = '1'
                             else
                             7                                               when VGA_MODE_SEL(3 downto 0) = "0010" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1' or MODE_VIDEO_MZ1500 = '1')                               and MODE_VIDEO_COLOUR80 = '1' 

                             else

                             8                                               when VGA_MODE_SEL(3 downto 0) = "0011" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' or MODE_VIDEO_MZ1200 = '1' or MODE_VIDEO_MZ80A = '1')     and MODE_VIDEO_MONO   = '1'
                             else
                             9                                               when VGA_MODE_SEL(3 downto 0) = "0011" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' or MODE_VIDEO_MZ1200 = '1' or MODE_VIDEO_MZ80A = '1')     and MODE_VIDEO_MONO80 = '1'
                             else
                             10                                              when VGA_MODE_SEL(3 downto 0) = "0011" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1' or MODE_VIDEO_MZ1500 = '1')                               and MODE_VIDEO_COLOUR   = '1'
                             else
                             11                                              when VGA_MODE_SEL(3 downto 0) = "0011" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1' or MODE_VIDEO_MZ1500 = '1')                               and MODE_VIDEO_COLOUR80 = '1' 

                             else

                             12                                              when VGA_MODE_SEL(3 downto 0) = "0001" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' or MODE_VIDEO_MZ1200 = '1' or MODE_VIDEO_MZ80A = '1')     and MODE_VIDEO_MONO   = '1'
                             else
                             13                                              when VGA_MODE_SEL(3 downto 0) = "0001" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80K = '1' or MODE_VIDEO_MZ80C = '1' or MODE_VIDEO_MZ1200 = '1' or MODE_VIDEO_MZ80A = '1')     and MODE_VIDEO_MONO80 = '1'
                             else
                             14                                              when VGA_MODE_SEL(3 downto 0) = "0001" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1' or MODE_VIDEO_MZ1500 = '1')                               and MODE_VIDEO_COLOUR   = '1'
                             else
                             15                                              when VGA_MODE_SEL(3 downto 0) = "0001" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ80A = '1' or MODE_VIDEO_MZ700 = '1' or MODE_VIDEO_MZ1500 = '1')                               and MODE_VIDEO_COLOUR80 = '1' 

                             -- MZ2000 Modes
                             else
                             16                                              when VGA_MODE_SEL(3 downto 1) = "000"  and HOST_HW_MZ2000 = '1'                                                                                                                                         and (MODE_VIDEO_MONO   = '1' or MODE_VIDEO_COLOUR   = '1') -- Internal mode active when VGA set to original.
                             else
                             17                                              when VGA_MODE_SEL(3 downto 1) = "000"  and HOST_HW_MZ2000 = '1'                                                                                                                                         and (MODE_VIDEO_MONO80 = '1' or MODE_VIDEO_COLOUR80 = '1') -- Internal mode active when VGA set to original.
                             else
                             18                                              when VGA_MODE_SEL(3 downto 1) = "000"  and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')                                                        and MODE_VIDEO_MONO   = '1'
                             else
                             19                                              when VGA_MODE_SEL(3 downto 1) = "000"  and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')                                                        and MODE_VIDEO_MONO80 = '1'
                             else
                             20                                              when VGA_MODE_SEL(3 downto 0) = "0010" and                                                  (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')                                                        and MODE_VIDEO_MONO   = '1'
                             else
                             21                                              when VGA_MODE_SEL(3 downto 0) = "0010" and                                                  (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')                                                        and MODE_VIDEO_MONO80 = '1'
                             else
                             22                                              when VGA_MODE_SEL(3 downto 0) = "0011" and                                                  (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')                                                        and MODE_VIDEO_MONO   = '1'
                             else
                             23                                              when VGA_MODE_SEL(3 downto 0) = "0011" and                                                  (MODE_VIDEO_MZ2000 = '1' or MODE_VIDEO_MZ2200 = '1')                                                        and MODE_VIDEO_MONO80 = '1'

                             -- MZ80B Modes
                             else
                             24                                              when VGA_MODE_SEL(3 downto 1) = "000"  and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and MODE_VIDEO_MZ80B = '1'                                                                                      and MODE_VIDEO_MONO   = '1'
                             else
                             25                                              when VGA_MODE_SEL(3 downto 1) = "000"  and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and MODE_VIDEO_MZ80B = '1'                                                                                      and MODE_VIDEO_MONO80 = '1'
                             else
                             26                                              when VGA_MODE_SEL(3 downto 0) = "0010" and                                                  MODE_VIDEO_MZ80B = '1'                                                                                      and MODE_VIDEO_MONO   = '1'
                             else
                             27                                              when VGA_MODE_SEL(3 downto 0) = "0010" and                                                  MODE_VIDEO_MZ80B = '1'                                                                                      and MODE_VIDEO_MONO80 = '1'
                             else
                             28                                              when VGA_MODE_SEL(3 downto 0) = "0011" and                                                  MODE_VIDEO_MZ80B = '1'                                                                                      and MODE_VIDEO_MONO   = '1'
                             else
                             29                                              when VGA_MODE_SEL(3 downto 0) = "0011" and                                                  MODE_VIDEO_MZ80B = '1'                                                                                      and MODE_VIDEO_MONO80 = '1'

                             -- MZ800 Modes
                             else
                             30                                              when VGA_MODE_SEL(3 downto 0) = "0000" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and MODE_VIDEO_BASE = MZ800                                                                                     and MODE_VIDEO_COLOUR = '1'
                             else
                             31                                              when VGA_MODE_SEL(3 downto 0) = "0000" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and MODE_VIDEO_BASE = MZ800                                                                                     and MODE_VIDEO_COLOUR80 = '1'
                             else
                             32                                              when VGA_MODE_SEL(3 downto 0) = "0001" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and MODE_VIDEO_BASE = MZ800                                                                                     and MODE_VIDEO_COLOUR = '1'
                             else
                             33                                              when VGA_MODE_SEL(3 downto 0) = "0001" and HOST_HW_MZ80A = '0' and HOST_HW_MZ2000 = '0' and MODE_VIDEO_BASE = MZ800                                                                                     and MODE_VIDEO_COLOUR80 = '1'
                             else
                             34                                              when VGA_MODE_SEL(3 downto 0) = "0010" and                                                  MODE_VIDEO_BASE = MZ800                                                                                     and MODE_VIDEO_COLOUR = '1'
                             else
                             35                                              when VGA_MODE_SEL(3 downto 0) = "0010" and                                                  MODE_VIDEO_BASE = MZ800                                                                                     and MODE_VIDEO_COLOUR80 = '1'
                             else
                             36                                              when VGA_MODE_SEL(3 downto 0) = "0011" and                                                  MODE_VIDEO_BASE = MZ800                                                                                     and MODE_VIDEO_COLOUR = '1'
                             else
                             37                                              when VGA_MODE_SEL(3 downto 0) = "0011" and                                                  MODE_VIDEO_BASE = MZ800                                                                                     and MODE_VIDEO_COLOUR80 = '1'

                             -- MZ80A Modes
                             else
                             38                                              when VGA_MODE_SEL(3 downto 1) = "000"  and HOST_HW_MZ80A = '1'                                                                                                                                          and (MODE_VIDEO_MONO   = '1' or MODE_VIDEO_COLOUR   = '1') -- Internal mode active when VGA set to original.
                             else
                             39                                              when VGA_MODE_SEL(3 downto 1) = "000"  and HOST_HW_MZ80A = '1'                                                                                                                                          and (MODE_VIDEO_MONO80 = '1' or MODE_VIDEO_COLOUR80 = '1') -- Internal mode active when VGA set to original.
                             else
                             40                                              when VGA_MODE_SEL(3 downto 1) = "000"  and HOST_HW_MZ80A = '0' and                          MODE_VIDEO_MZ80A = '1'                                                                                      and MODE_VIDEO_MONO   = '1'
                             else
                             41                                              when VGA_MODE_SEL(3 downto 1) = "000"  and HOST_HW_MZ80A = '0' and                          MODE_VIDEO_MZ80A = '1'                                                                                      and MODE_VIDEO_MONO80 = '1'
                             else
                             42                                              when VGA_MODE_SEL(3 downto 0) = "0010" and                                                  MODE_VIDEO_MZ80A = '1'                                                                                      and MODE_VIDEO_MONO   = '1'
                             else
                             43                                              when VGA_MODE_SEL(3 downto 0) = "0010" and                                                  MODE_VIDEO_MZ80A = '1'                                                                                      and MODE_VIDEO_MONO80 = '1'
                             else
                             44                                              when VGA_MODE_SEL(3 downto 0) = "0011" and                                                  MODE_VIDEO_MZ80A = '1'                                                                                      and MODE_VIDEO_MONO   = '1'
                             else
                             45                                              when VGA_MODE_SEL(3 downto 0) = "0011" and                                                  MODE_VIDEO_MZ80A = '1'                                                                                      and MODE_VIDEO_MONO80 = '1'

                             else
                             0;

    -- Select the video clock based on the video mode. The video mode selects an active clock when the old and previous clocks go to the high level.
    --
    --

    -- To simply reading, assign the current base video mode to a signal. This is used when a video mode may have more than 1 sub mode, ie. MZ-800.
    MODE_VIDEO_BASE       <= to_integer(unsigned(VIDEO_MODE_REG(3 downto 0)));

--   -- Process to output signals on clock edges, to clean them up as needed.
--   --
--   process(VID_CLK)
--   begin
--       if rising_edge(VID_CLK) then
--           if MB_VIDEO_ENABLEn = '1' then
--
--               if H_POLARITY(0) = '0' then
--                   HSYNC_OUTn            <= H_SYNCni;
--               else
--                   HSYNC_OUTn            <= not H_SYNCni;
--               end if;
--
--               if V_POLARITY(0) = '0' then
--                   VSYNC_OUTn            <= V_SYNCni;
--               else
--                   VSYNC_OUTn            <= not V_SYNCni;
--               end if;
--
--                if  H_BLANKi='0' and V_BLANKi = '0' and ((DISPLAY_VGATE = '0' and MODE_VIDEO_MZ80B = '1') or MODE_VIDEO_MZ80B = '0') then
--                    VGA_R(3 downto 0)     <= FB_PALETTE_R(3 downto 0);
--                    VGA_G(3 downto 0)     <= FB_PALETTE_G(3 downto 0);
--                    VGA_B(3 downto 0)     <= FB_PALETTE_B(3 downto 0);
--                else 
--                    VGA_R(3 downto 0)     <= (others => '0');
--                    VGA_G(3 downto 0)     <= (others => '0');
--                    VGA_B(3 downto 0)     <= (others => '0');
--                end if;
--
--          elsif MB_VIDEO_ENABLEn = '0' then
--              HSYNC_OUTn            <= V_HSYNCn;                                                   -- Horizontal sync (negative) from mainboard.
--              VSYNC_OUTn            <= V_VSYNCn;                                                   -- Vertical sync (negative) from mainboard.
--                VGA_R(3 downto 0)     <=  (others => V_R);
--                VGA_G(3 downto 0)     <=  (others => V_R);
--                VGA_B(3 downto 0)     <=  (others => V_R);
--          end if;
--  HBLANK_OUT            <= H_BLANKi;
--  VBLANK_OUT            <= V_BLANKi;
--      end if;
--  end process;

    HSYNC_OUTn            <= V_HSYNCn                                        when MB_VIDEO_ENABLEn = '0'
                             else
                             H_SYNCni                                        when MB_VIDEO_ENABLEn = '1' and H_POLARITY(0) = '0'
                             else
                             not H_SYNCni;                                                                                              -- Horizontal sync (negative) from mainboard.
    VSYNC_OUTn            <= V_VSYNCn                                        when MB_VIDEO_ENABLEn = '0'
                             else
                             V_SYNCni                                        when MB_VIDEO_ENABLEn = '1' and V_POLARITY(0) = '0'
                             else
                             not V_SYNCni;                                                                                              -- Vertical sync (negative) from mainboard.
    HBLANK_OUT            <= H_BLANKi;
    VBLANK_OUT            <= V_BLANKi;

    -- Set underlying hardware mode flag according to value input into controller.
    HOST_HW_MZ80K         <= '1'                                             when to_integer(unsigned(HW_HOST(2 downto 0))) = MODE_HOST_MZ80K
                             else '0';
    HOST_HW_MZ80C         <= '1'                                             when to_integer(unsigned(HW_HOST(2 downto 0))) = MODE_HOST_MZ80C
                             else '0';
    HOST_HW_MZ1200        <= '1'                                             when to_integer(unsigned(HW_HOST(2 downto 0))) = MODE_HOST_MZ1200
                             else '0';
    HOST_HW_MZ80A         <= '1'                                             when to_integer(unsigned(HW_HOST(2 downto 0))) = MODE_HOST_MZ80A
                             else '0';
    HOST_HW_MZ700         <= '1'                                             when to_integer(unsigned(HW_HOST(2 downto 0))) = MODE_HOST_MZ700
                             else '0';
    HOST_HW_MZ800         <= '1'                                             when to_integer(unsigned(HW_HOST(2 downto 0))) = MODE_HOST_MZ800
                             else '0';
    HOST_HW_MZ80B         <= '1'                                             when to_integer(unsigned(HW_HOST(2 downto 0))) = MODE_HOST_MZ80B
                             else '0';
    HOST_HW_MZ2000        <= '1'                                             when to_integer(unsigned(HW_HOST(2 downto 0))) = MODE_HOST_MZ2000
                             else '0';
    MODE_HOST             <= '1'                                             when HW_MODE(1 downto 0) = "00"
                             else '0';
    MODE_IOP              <= '1'                                             when HW_MODE(1 downto 0) = "01"
                             else '0';
    MODE_EMUMZ            <= '1'                                             when HW_MODE(1 downto 0) = "10"
                             else '0';

    VGA_R(3 downto 0)     <= FB_PALETTE_R(3 downto 0)                        when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and ((DISPLAY_VGATE = '0' and MODE_VIDEO_MZ80B = '1') or (MODE_VIDEO_MZ80B = '0') or (VGA_ATTR_REG(6) = '1' and ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT <= H_MNU_END))))
                             else
                             (others => V_R)                                 when MB_VIDEO_ENABLEn = '0'
                             else (others => '0');
    VGA_G(3 downto 0)     <= FB_PALETTE_G(3 downto 0)                        when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and ((DISPLAY_VGATE = '0' and MODE_VIDEO_MZ80B = '1') or (MODE_VIDEO_MZ80B = '0') or (VGA_ATTR_REG(6) = '1' and ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT <= H_MNU_END))))
                             else
                             (others => V_G)                                 when MB_VIDEO_ENABLEn = '0'
                             else (others => '0');
    VGA_B(3 downto 0)     <= FB_PALETTE_B(3 downto 0)                        when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and ((DISPLAY_VGATE = '0' and MODE_VIDEO_MZ80B = '1') or (MODE_VIDEO_MZ80B = '0') or (VGA_ATTR_REG(6) = '1' and ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT <= H_MNU_END))))
                             else
                             (others => V_B)                                 when MB_VIDEO_ENABLEn = '0'
                             else (others => '0');
    VGA_R_COMPOSITE       <= V_R                                             when MB_VIDEO_ENABLEn = '0' --and V_R = '1'
                             else
                             FB_PALETTE_R(4)                                 when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and (MODE_VIDEO_MONO = '1'   or MODE_VIDEO_MONO80 = '1')
                             else
                             '1'                                             when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and (MODE_VIDEO_COLOUR = '1' or MODE_VIDEO_COLOUR80 = '1') and SR_R_CHR(7) = '1' and PALETTE_REG = X"00" and VGA_ATTR_REG(6) = '0'
                             else
                             '0'                                             when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and (MODE_VIDEO_COLOUR = '1' or MODE_VIDEO_COLOUR80 = '1') and FB_PALETTE_R(4) = '0'
                             else 'Z';
    VGA_G_COMPOSITE       <= V_G                                             when MB_VIDEO_ENABLEn = '0' --and V_G = '1'
                             else
                             FB_PALETTE_G(4)                                 when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and (MODE_VIDEO_MONO = '1'   or MODE_VIDEO_MONO80 = '1')
                             else
                             '1'                                             when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and (MODE_VIDEO_COLOUR = '1' or MODE_VIDEO_COLOUR80 = '1') and SR_G_CHR(7) = '1' and PALETTE_REG = X"00" and VGA_ATTR_REG(6) = '0'
                             else
                             '0'                                             when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and (MODE_VIDEO_COLOUR = '1' or MODE_VIDEO_COLOUR80 = '1') and FB_PALETTE_G(4) = '0'
                             else 'Z';
    VGA_B_COMPOSITE       <= V_B                                             when MB_VIDEO_ENABLEn = '0' --and V_B = '1'
                             else
                             FB_PALETTE_B(4)                                 when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and (MODE_VIDEO_MONO = '1'   or MODE_VIDEO_MONO80 = '1') 
                             else
                             '1'                                             when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and (MODE_VIDEO_COLOUR = '1' or MODE_VIDEO_COLOUR80 = '1') and SR_B_CHR(7) = '1' and PALETTE_REG = X"00" and VGA_ATTR_REG(6) = '0'
                             else
                         --    '1'                                             when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and(MODE_VIDEO_MZ800 = '1'  and FB_PALETTE_B(4) = '1'
                         --    else
                             '0'                                             when MB_VIDEO_ENABLEn = '1' and H_BLANKi='0' and V_BLANKi = '0' and (MODE_VIDEO_COLOUR = '1' or MODE_VIDEO_COLOUR80 = '1') and FB_PALETTE_B(4) = '0'
                             else 'Z';

    -- Composite video signal output. Composite video is formed in external hardware by the combination of VGA R/G/B signals.
    CSYNC_OUTn            <= '1'; --not VWAITn_V_CSYNC                              when MB_VIDEO_ENABLEn = '0'
                             --else
                             --'1'                                             when VGA_MODE_REG(3 downto 1) /= "000" and (HOST_HW_MZ80A = '1' or HOST_HW_MZ2000 = '1')  -- Disable sync when running with an internal monitor or we switch to a higher unsupported VGA mode.
                             --else
                             --not (H_SYNCni xor not V_SYNCni);
    CSYNC_OUT             <= VWAITn_V_CSYNC                                  when MB_VIDEO_ENABLEn = '0'
                             else
                             '0'                                             when VGA_MODE_REG(3 downto 1) /= "000" and (HOST_HW_MZ80A = '1' or HOST_HW_MZ2000 = '1')  -- Disable sync when running with an internal monitor or we switch to a higher unsupported VGA mode.
                             else
                             H_SYNCni xor not V_SYNCni;
    COLR_OUT              <= V_COLR                                          when MB_VIDEO_ENABLEn = '0'      -- Composite and RF base frequency from mainboard. Sound input on MZ-2000.
                             else
                             V_COLR;

end architecture rtl;
