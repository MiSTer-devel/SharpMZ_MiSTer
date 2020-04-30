---------------------------------------------------------------------------------------------------------
--
-- Name:            video.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series Video logic.
--                  This module fully emulates the Sharp MZ Personal Computer series video display
--                  logic plus extensions for MZ80K, MZ80C, MZ1200, MZ80A, MZ700, MZ80B & MZ2000.
--                  
--                  The display is capable of performing 40x25, 80x25 Mono/Colour display along with
--                  a Programmable Character Generator, the MZ-80B/2000 Graphics Options and a bit mapped
--                  320x200/640x200 framebuffer.                                                                                                    
--
--                  The design is slightly different to the original Sharp's in that I use a dual
--                  buffer technique, ie. the original 1K/2K VRAM + ARAM and a pixel mapped displaybuffer.
--                  During Horizontal/Vertical blanking, the VRAM+ARAM is copied and expanded into the display
--                  buffer which is then displayed during the next display window. Part of the reasoning
--                  was to cut down on snow/tearing on the older K/C models (but still provide the
--                  blanking signals so any original software works) and also allow the option of
--                  disabling the MZ80A/700 wait states.
--
--                  As an addition, I added a graphics framebuffer (320x200, 640x200 8 colours) 
--                  the interface to which is, at the moment, non-standard, but as I get more details
--                  on add on cards, I can add mapping layers so this graphics framebuffer can be used
--                  by customised software. Pixels drawn in the graphics framebuffer can be blended into
--                  the main display buffer via programmable logic mode (ie. XOR, OR etc).
--
--                  The MZ80B/2000 use a standard VRAM + CG for 40/80 character display with a Graphics
--                  RAM option. These have been added and the output if blended into the display buffer.
--
--                  A lot of timing information can be found in the docs/SharpMZ_Notes.xlsx spreadsheet,
--                  but the main info is:
--                      MZ80K/C/1200/A (Monochrome)                
--                      Signal    Start    End    Period    Comment
--                      64uS 15.625KHz                
--                      HDISPEN    0    320     40uS    
--                      HBLANK    318    510     24uS    
--                      BLNK        318    486     21uS    
--                      HSYNC    393    438     5.625uS    
--                 
--                      16.64mS 60.10Hz                
--                      VDISPEN    0    200     12.8mS    
--                      VSYNC    219    223     256uS    
--                      VBLANK    201    259     3.712mS    not VDISPEN
--                 
--                      MZ700 (Colour)                
--                      Signal    Start    End    Period    Comment
--                      64.056uS 15.611KHz                
--                      HDISPEN    0    320     36.088uS    
--                      HBLANK    320    567     27.968uS    
--                      BLNK    320    548     25.7126uS    
--                      HSYNC    400    440       4.567375uS    
--                 
--                      16.654mS 50.0374Hz                
--                      VDISPEN    0    200     12.8112mS    
--                      VSYNC    212    215     0.19216ms    
--                      VBLANK    201    311     7.1738mS     not VDISPEN                                                                                                            
--
--                  A Look Up Table was added to allow for VGA display resolutions and upscaling as necessary. 
--                  All video parameters are now stored in the LUT.
--                                                         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         July 2018      - Initial module written.
--                  August 2018    - Main portions written, including the display buffer.
--                  September 2018 - Added the graphics framebuffer.
--                                 - Reworked the transfer VRAM/GRAM -> Framebuffer logic, too conceptual
--                                   and caused timing issues. 
--                                   Reworked the Framebuffer display, too conceptual.
--                                   Added MZ80B/MZ2000 logic.
--                  October 2018   - Parameterised graphics modes via a LUT.
--                  November 2018  - Added VGA upscaling.
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
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;
use pkgs.functions_pkg.all;

entity video is
Port (
    RST_n                    : in  std_logic;                            -- Reset

    -- Different operations modes.
    CONFIG                   : in  std_logic_vector(CONFIG_WIDTH);

    -- Clocks
    CLKBUS                   : in  std_logic_vector(CLKBUS_WIDTH);       -- Clock signals created by clkgen module.

    -- CPU Signals
    T80_A                    : in  std_logic_vector(13 downto 0);        -- CPU Address Bus
    T80_RD_n                 : in  std_logic;                            -- CPU Read Signal
    T80_WR_n                 : in  std_logic;                            -- CPU Write Signal
    T80_MREQ_n               : in  std_logic;                            -- CPU Memory Request
    T80_BUSACK_n             : in  std_logic;                            -- CPU Bus Acknowledge
    T80_WAIT_n               : out std_logic;                            -- CPU Wait Request
    T80_DI                   : in  std_logic_vector(7 downto 0);         -- CPU Data Bus in
    T80_DO                   : out std_logic_vector(7 downto 0);         -- CPU Data Bus out

    -- Selects.
    CS_VRAM_n                : in  std_logic;                            -- VRAM Select
    CS_MEM_G_n               : in  std_logic;                            -- Memory mapped Peripherals Select
    CS_GRAM_n                : in  std_logic;                            -- Colour GRAM Select
    CS_GRAM_80B_n            : in  std_logic;                            -- MZ80B GRAM Select
    CS_IO_GFB_n              : in  std_logic;                            -- Framebuffer register IO Select range.
    CS_IO_G_n                : in  std_logic;                            -- MZ80B Graphics Options IO Select range.

    -- Video Signals
    VGATE_n                  : in  std_logic;                            -- Video Output Control
    INVERSE_n                : in  std_logic;                            -- Invert video display.
    CONFIG_CHAR80            : in  std_logic;                            -- 40 Char = 0, 80 Char = 1 select.
    HBLANK                   : out std_logic;                            -- Horizontal Blanking
    VBLANK                   : out std_logic;                            -- Vertical Blanking
    HSYNC_n                  : out std_logic;                            -- Horizontal Sync
    VSYNC_n                  : out std_logic;                            -- Vertical Sync
    ROUT                     : out std_logic_vector(7 downto 0);         -- Red Output
    GOUT                     : out std_logic_vector(7 downto 0);         -- Green Output
    BOUT                     : out std_logic_vector(7 downto 0);         -- Green Output

    -- HPS Interface
    IOCTL_DOWNLOAD           : in  std_logic;                            -- HPS Downloading to FPGA.
    IOCTL_UPLOAD             : in  std_logic;                            -- HPS Uploading from FPGA.
    IOCTL_CLK                : in  std_logic;                            -- HPS I/O Clock..
    IOCTL_WR                 : in  std_logic;                            -- HPS Write Enable to FPGA.
    IOCTL_RD                 : in  std_logic;                            -- HPS Read Enable from FPGA.
    IOCTL_ADDR               : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
    IOCTL_DOUT               : in  std_logic_vector(31 downto 0);        -- HPS Data to be written into FPGA.
    IOCTL_DIN                : out std_logic_vector(31 downto 0)         -- HPS Data to be read into HPS.
);
end video;

architecture RTL of video is

type VIDEOLUT is array (integer range 0 to 19, integer range 0 to 28) of integer range 0 to 2000;

-- Constants
--
constant MAX_SUBROW          : integer := 8;
constant MENU_FG_RED         : integer := 15;
constant MENU_FG_GREEN       : integer := 14;
constant MENU_FG_BLUE        : integer := 13;
constant MENU_BG_RED         : integer := 12;
constant MENU_BG_GREEN       : integer := 11;
constant MENU_BG_BLUE        : integer := 10;

-- 
-- Video Timings for different machines and display configuration.
--
constant FB_PARAMS           : VIDEOLUT := (

-- Display window variables:-
--   H_DSP_START,      H_DSP_END,H_DSP_WND_START,  H_DSP_WND_END,    H_MNU_START,      H_MNU_END,    H_HDR_START,      H_HDR_END,    H_FTR_START,      H_FTR_END,    V_DSP_START,      V_DSP_END,V_DSP_WND_START,  V_DSP_WND_END,    V_MNU_START,      V_MNU_END,    V_HDR_START,      V_HDR_END,    V_FTR_START,      V_FTR_END,     H_LINE_END,     V_LINE_END,   MAX_COLUMNS,        H_SYNC_START,                   H_SYNC_END,               V_SYNC_START,                   V_SYNC_END,           H_PX,             V_PX      			
(              0,            320,              0,            320,             32,            288,              0,              0,              0,              0,              0,            200,              0,            200,             36,            164,              0,              0,              0,             0,             511,            259,         40,                320  + 73,              320 + 73  + 45,                   200 + 19,                 200 + 19 + 4,              0,               0),      -- 0  MZ80B/2000 machines have a monochrome 60Hz display  with scan of 512 x 260 for a 320x200 viewable area in 40Char mode.			
(              0,            640,              0,            640,            192,            448,              0,              0,              0,              0,              0,            200,              0,            200,             36,            164,              0,              0,              0,             0,            1023,            259,         80,                640  + 146,             640 + 146 + 90,                   200 + 19,                 200 + 19 + 4,              0,               0),      -- 1  MZ80B/2000 machines have a monochrome 60Hz display  with scan of 1024 x 260 for a 640x200 viewable area in 80Char mode.			
(              0,            320,              0,            320,             32,            288,              0,              0,              0,              0,              0,            200,              0,            200,             36,            164,              0,              0,              0,             0,             511,            259,         40,                320  + 73,              320 + 73  + 45,                   200 + 19,                 200 + 19 + 4,              0,               0),      -- 2  MZ80K/C/1200/A machines have a monochrome 60Hz display  with scan of 512 x 260 for a 320x200 viewable area.			
(              0,            640,              0,            640,            192,            448,              0,              0,              0,              0,              0,            200,              0,            200,             36,            164,              0,              0,              0,             0,            1023,            259,         80,                640  + 146,             640 + 146 + 90,                   200 + 19,                 200 + 19 + 4,              0,               0),      -- 3  MZ80K/C/1200/A machines with an adapted monochrome 60Hz display  with scan of 1024 x 260 for a 640x200 viewable area.			
(              0,            320,              0,            320,             32,            288,              0,              0,              0,              0,              0,            200,              0,            200,             36,            164,              0,              0,              0,             0,             567,            311,         40,                320  + 80,              320 + 80  + 40,                   200 + 45,                 200 + 45 + 3,              0,               0),      -- 4  MZ700 has a colour 50Hz display  with scan of 568 x 320 for a 320x200 viewable area.			
(              0,            640,              0,            640,            192,            448,              0,              0,              0,              0,              0,            200,              0,            200,             36,            164,              0,              0,              0,             0,            1134,            311,         80,                640  + 160,             640 + 160 + 80,                   200 + 45,                 200 + 45 + 3,              0,               0),      -- 5  MZ700 has colour 50Hz display  with scan of 1136 x 320 for a 640x200 viewable area.			
(              0,            320,              0,            320,             32,            288,              0,              0,              0,              0,              0,            200,              0,            200,             36,            164,              0,              0,              0,             0,             511,            259,         40,                320  + 73,              320 + 73  + 45,                   200 + 19,                 200 + 19 + 4,              0,               0),      -- 6  MZ80K/C/1200/A machines with MZ700 style colour @ 60Hz display  with scan of 512 x 260 for a 320x200 viewable area.			
(              0,            640,              0,            640,            192,            448,              0,              0,              0,              0,              0,            200,              0,            200,             36,            164,              0,              0,              0,             0,            1023,            259,         80,                640  + 146,             640 + 146 + 90,                   200 + 19,                 200 + 19 + 4,              0,               0),      -- 7  MZ80K/C/1200/A machines with MZ700 style colour @ 60Hz display  with scan of 1024 x 260 for a 640x200 viewable area.			
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            831,            519,         40,                640  + 16,              640 + 16  + 96,                   480 + 10,                 480 + 10 + 2,              1,               1),      -- 8  640x480  @ 60Hz timings for 40Char mode monochrome. 			
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            799,            524,         40,                640  + 16,              640 + 16  + 96,                   480 + 10,                 480 + 10 + 2,              1,               1),      -- 9  640x480  @ 60Hz timings for 40Char mode monochrome.
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            831,            508,         80,                640  + 16,              640 + 16  + 96,                   480 + 10,                 480 + 10 + 2,              0,               1),      -- 10 640x480  @ 60Hz timings for 80Char mode monochrome.
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            799,            524,         80,                640  + 16,              640 + 16  + 96,                   480 + 10,                 480 + 10 + 2,              0,               1),      -- 11 640x480  @ 60Hz timings for 80Char mode monochrome.
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            831,            508,         40,                640  + 16,              640 + 16  + 96,                   480 + 10,                 480 + 10 + 2,              1,               1),      -- 12 640x480  @ 60Hz timings for 80Char mode colour.
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            799,            524,         40,                640  + 16,              640 + 16  + 96,                   480 + 10,                 480 + 10 + 2,              1,               1),      -- 13 640x480  @ 60Hz timings for 40Char mode colour.
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            831,            508,         80,                640  + 16,              640 + 16  + 96,                   480 + 10,                 480 + 10 + 2,              0,               1),      -- 14 640x480  @ 60Hz timings for 80Char mode colour.
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            799,            524,         80,                640  + 16,              640 + 16  + 96,                   480 + 10,                 480 + 10 + 2,              0,               1),      -- 15 640x480  @ 60Hz timings for 80Char mode colour.
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            831,            519,         40,                640  + 24,              640 + 24  + 40,                   480 + 9,                  480 +  9 + 2,              1,               1),      -- 16 640x480  @ 72Hz timings for 40Char mode monochrome. 			
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            831,            519,         80,                640  + 24,              640 + 24  + 40,                   480 + 9,                  480 +  9 + 2,              0,               1),      -- 17 640x480  @ 72Hz timings for 80Char mode monochrome. 			
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            831,            519,         40,                640  + 24,              640 + 24  + 40,                   480 + 9,                  480 +  9 + 2,              1,               1),      -- 18 640x480  @ 72Hz timings for 40Char mode colour. 			
(              0,            640,              0,            640,            192,            448,              0,            640,              0,            640,              0,            480,             39,            439,            111,            367,              8,             24,            444,            479,            831,            519,         80,                640  + 24,              640 + 24  + 40,                   480 + 9,                  480 +  9 + 2,              0,               1)       -- 19 640x480  @ 72Hz timings for 80Char mode colour. 			
);


--
-- Registers
--
signal VIDEOMODE             :     integer range 0 to 20;
signal VIDEOMODE_LAST        :     integer range 0 to 20;
signal VIDEOMODE_CHANGED     :     std_logic;
signal MAX_COLUMN            :     integer range 0 to 80;
signal FB_ADDR               :     std_logic_vector(13 downto 0);        -- Frame buffer actual address
signal FB_ADDR_STATUS        :     std_logic_vector(11 downto 0);        -- Status display frame buffer actual address
signal FB_ADDR_MENU          :     std_logic_vector(12 downto 0);        -- Menu display frame buffer actual address
signal OFFSET_ADDR           :     std_logic_vector(7 downto 0);         -- Display Offset - for MZ1200/80A machines with 2K VRAM
signal SR_G_DATA             :     std_logic_vector(7 downto 0);         -- Shift Register to serialise Green pixels.
signal SR_R_DATA             :     std_logic_vector(7 downto 0);         -- Shift Register to serialise Red pixels.
signal SR_B_DATA             :     std_logic_vector(7 downto 0);         -- Shift Register to serialise Blue pixels.
signal SR_G_MENU             :     std_logic_vector(7 downto 0);         -- Shift Register to serialise Menu pixels.
signal SR_R_MENU             :     std_logic_vector(7 downto 0);         -- Shift Register to serialise Menu pixels.
signal SR_B_MENU             :     std_logic_vector(7 downto 0);         -- Shift Register to serialise Menu pixels.
signal DISPLAY_DATA          :     std_logic_vector(23 downto 0);
signal DISPLAY_STATUS        :     std_logic_vector(23 downto 0);
signal DISPLAY_MENU          :     std_logic_vector(23 downto 0);
signal XFER_ADDR             :     std_logic_vector(10 downto 0);
signal XFER_SUB_ADDR         :     std_logic_vector(2 downto 0);
signal XFER_VRAM_DATA        :     std_logic_vector(15 downto 0);
signal XFER_GRAM_DATA        :     std_logic_vector(39 downto 0);        -- 3 x 16Kb Colour Graphics + GRAM I (MZ80B) + GRAM II (MZ80B)
signal XFER_MAPPED_DATA      :     std_logic_vector(23 downto 0);
signal XFER_WEN              :     std_logic;
signal XFER_VRAM_ADDR        :     std_logic_vector(10 downto 0);
signal XFER_DST_ADDR         :     std_logic_vector(13 downto 0);
signal XFER_CGROM_ADDR       :     std_logic_vector(11 downto 0);
signal CGROM_DATA            :     std_logic_vector(7 downto 0);         -- Font Data To Display
signal DISPLAY_INVERT        :     std_logic;                            -- Invert display Mode of MZ80A/1200
signal H_SHIFT_CNT           :     integer range 0 to 7;
signal H_MNU_SHIFT_CNT       :     integer range 0 to 7;
signal H_PX                  :     integer range 0 to 3;                 -- Variable to indicate if horizontal pixels should be multiplied (for conversion to alternate formats).
signal H_PX_CNT              :     integer range 0 to 3;                 -- Variable to indicate if horizontal pixels should be multiplied (for conversion to alternate formats).
signal V_PX                  :     integer range 0 to 3;                 -- Variable to indicate if vertical pixels should be multiplied (for conversion to alternate formats).
signal V_PX_CNT              :     integer range 0 to 3;                 -- Variable to indicate if vertical pixels should be multiplied (for conversion to alternate formats).

--
-- CPU/Video Access
--
signal VRAM_VIDEO_DATA       :     std_logic_vector(7 downto 0);         -- Display data output to CPU.
signal VRAM_ADDR             :     std_logic_vector(11 downto 0);        -- VRAM Address.
signal VRAM_DI               :     std_logic_vector(7 downto 0);         -- VRAM Data in.
signal VRAM_DO               :     std_logic_vector(7 downto 0);         -- VRAM Data out.
signal VRAM_WEN              :     std_logic;                            -- VRAM Write enable signal.
signal VRAM_CLK              :     std_logic;                            -- Clock used to access the VRAM (CPU or IOCTL_CLK).
signal VRAM_CLK_EN           :     std_logic;                            -- Clock enable for VRAM.
signal GRAM_VIDEO_DATA       :     std_logic_vector(7 downto 0);         -- Graphics display data output to CPU.
signal GRAM_ADDR             :     std_logic_vector(13 downto 0);        -- Graphics RAM Address.
signal GRAM_DI_R             :     std_logic_vector(7 downto 0);         -- Graphics Red RAM Data.
signal GRAM_DI_G             :     std_logic_vector(7 downto 0);         -- Graphics Green RAM Data.
signal GRAM_DI_B             :     std_logic_vector(7 downto 0);         -- Graphics Blue RAM Data.
signal GRAM_DI_GI            :     std_logic_vector(7 downto 0);         -- Graphics Option GRAM I for MZ80B
signal GRAM_DI_GII           :     std_logic_vector(7 downto 0);         -- Graphics Option GRAM II for MZ80B
signal GRAM_DO_R             :     std_logic_vector(7 downto 0);         -- Graphics Red RAM Data out.
signal GRAM_DO_G             :     std_logic_vector(7 downto 0);         -- Graphics Green RAM Data out.
signal GRAM_DO_B             :     std_logic_vector(7 downto 0);         -- Graphics Blue RAM Data out.
signal GRAM_DO_GI            :     std_logic_vector(7 downto 0);         -- Graphics Option GRAM I Data out for MZ80B.
signal GRAM_DO_GII           :     std_logic_vector(7 downto 0);         -- Graphics Option GRAM II Data out for MZ80B.
signal GRAM_WEN_R            :     std_logic;                            -- Graphics Red RAM Write enable signal.
signal GRAM_WEN_G            :     std_logic;                            -- Graphics Green RAM Write enable signal.
signal GRAM_WEN_B            :     std_logic;                            -- Graphics Blue RAM Write enable signal.
signal GRAM_WEN_GI           :     std_logic;                            -- Graphics Option GRAM I Write enable signal for MZ80B.
signal GRAM_WEN_GII          :     std_logic;                            -- Graphics Option GRAM II Write enable signal for MZ80B.
signal GRAM_CLK              :     std_logic;                            -- Clock used to access the GRAM (CPU or IOCTL_CLK).
signal GRAM_CLK_EN           :     std_logic;                            -- Clock enable for GRAM.
signal GRAM_MODE             :     std_logic_vector(7 downto 0);         -- Programmable mode register to control GRAM operations.
signal GRAM_R_FILTER         :     std_logic_vector(7 downto 0);         -- Red pixel writer filter.
signal GRAM_G_FILTER         :     std_logic_vector(7 downto 0);         -- Green pixel writer filter.
signal GRAM_B_FILTER         :     std_logic_vector(7 downto 0);         -- Blue pixel writer filter.
signal GRAM_OPT_WRITE        :     std_logic;                            -- Graphics write to GRAMI (0) or GRAMII (1) for MZ80B/MZ2000
signal GRAM_OPT_OUT1         :     std_logic;                            -- Graphics enable GRAMI output to display
signal GRAM_OPT_OUT2         :     std_logic;                            -- Graphics enable GRAMII output to display
signal T80_MA                :     std_logic_vector(11 downto 0);        -- CPU Address Masked according to machine model.
signal CS_INVERT_n           :     std_logic;                            -- Chip Select to enable Inverse mode.
signal CS_SCROLL_n           :     std_logic;                            -- Chip Select to perform a hardware scroll.
signal CS_GRAM_OPT_n         :     std_logic;                            -- Chip Select to write the graphics options for MZ80B/MZ2000.
signal CS_FB_CTL_n           :     std_logic;                            -- Chip Select to write to the Graphics mode register.
signal CS_FB_RED_n           :     std_logic;                            -- Chip Select to write to the Red pixel per byte indirect write register.
signal CS_FB_GREEN_n         :     std_logic;                            -- Chip Select to write to the Green pixel per byte indirect write register.
signal CS_FB_BLUE_n          :     std_logic;                            -- Chip Select to write to the Blue pixel per byte indirect write register.
signal CS_PCG_n              :     std_logic;
signal WAITi_n               :     std_logic;                            -- Wait
signal WAITii_n              :     std_logic;                            -- Wait(delayed)
signal VWEN                  :     std_logic;                            -- Write enable to VRAM.
signal GWEN_R                :     std_logic;                            -- Write enable to Red GRAM.
signal GWEN_G                :     std_logic;                            -- Write enable to Green GRAM.
signal GWEN_B                :     std_logic;                            -- Write enable to Blue GRAM.
signal GWEN_GI               :     std_logic;                            -- Write enable to for GRAMI option on MZ80B/2000.
signal GWEN_GII              :     std_logic;                            -- Write enable to for GRAMII option on MZ80B/2000.
--
-- Internal Signals
--
signal H_COUNT               :     unsigned(10 downto 0);                -- Horizontal pixel counter
signal H_BLANKi              :     std_logic;                            -- Horizontal Blanking
signal H_SYNC_ni             :     std_logic;                            -- Horizontal Blanking
signal H_DSP_START           :     integer range 0 to 2047;
signal H_DSP_END             :     integer range 0 to 2047;
signal H_DSP_WND_START       :     integer range 0 to 2047;              -- Window within the horizontal display when data is output.
signal H_DSP_WND_END         :     integer range 0 to 2047;
signal H_MNU_START           :     integer range 0 to 2047;
signal H_MNU_END             :     integer range 0 to 2047;
signal H_HDR_START           :     integer range 0 to 2047;
signal H_HDR_END             :     integer range 0 to 2047;
signal H_FTR_START           :     integer range 0 to 2047;
signal H_FTR_END             :     integer range 0 to 2047;
signal H_SYNC_START          :     integer range 0 to 2047;
signal H_SYNC_END            :     integer range 0 to 2047;
signal H_LINE_END            :     integer range 0 to 2047;
signal V_COUNT               :     unsigned(10 downto 0);                -- Vertical pixel counter
signal V_BLANKi              :     std_logic;                            -- Vertical Blanking
signal V_SYNC_ni             :     std_logic;                            -- Horizontal Blanking
signal V_DSP_START           :     integer range 0 to 2047;
signal V_DSP_END             :     integer range 0 to 2047;
signal V_DSP_WND_START       :     integer range 0 to 2047;              -- Window within the vertical display when data is output.
signal V_DSP_WND_END         :     integer range 0 to 2047;
signal V_MNU_START           :     integer range 0 to 2047;
signal V_MNU_END             :     integer range 0 to 2047;
signal V_HDR_START           :     integer range 0 to 2047;
signal V_HDR_END             :     integer range 0 to 2047;
signal V_FTR_START           :     integer range 0 to 2047;
signal V_FTR_END             :     integer range 0 to 2047;
signal V_SYNC_START          :     integer range 0 to 2047;
signal V_SYNC_END            :     integer range 0 to 2047;
signal V_LINE_END            :     integer range 0 to 2047;
signal VRAM_WAIT             :     std_logic;                            -- Horizontal Blanking Memory Access
--
-- CG-ROM
--
signal CGROM_DO              :     std_logic_vector(7 downto 0);
signal CGROM_BANK            :     std_logic_vector(3 downto 0);
--
-- PCG
--
signal CGRAM_DO              :     std_logic_vector(7 downto 0);
signal CG_ADDR               :     std_logic_vector(11 downto 0);
signal CGRAM_ADDR            :     std_logic_vector(11 downto 0);
signal PCG_DATA              :     std_logic_vector(7 downto 0);
signal CGRAM_DI              :     std_logic_vector(7 downto 0);
signal CGRAM_WE_n            :     std_logic;
signal CGRAM_WEN             :     std_logic;
signal CGRAM_SEL             :     std_logic;
--
-- HPS Control.
--
signal IOCTL_CS_VRAM_n       :     std_logic;                            -- Chip Select to allow the HPS to access the VRAM.
signal IOCTL_CS_GRAM_n       :     std_logic;                            -- Chip Select to allow the HPS to access the GRAM.
signal IOCTL_CS_GRAM_80B_n   :     std_logic;                            -- Chip Select to allow the HPS to access the MZ80B/2000 GRAM option memory.
signal IOCTL_CS_CGROM_n      :     std_logic;
signal IOCTL_CS_CGRAM_n      :     std_logic;
signal IOCTL_CS_STRAM_n      :     std_logic;
signal IOCTL_CS_MNURAM_n     :     std_logic;
signal IOCTL_CS_CONFIG_n     :     std_logic;
signal IOCTL_WEN_VRAM        :     std_logic;                            -- Write Enable to allow the HPS to write to VRAM.
signal IOCTL_WEN_GRAM_R      :     std_logic;                            -- Write Enable to allow the HPS to write to the Red GRAM.
signal IOCTL_WEN_GRAM_G      :     std_logic;                            -- Write Enable to allow the HPS to write to the Green GRAM.
signal IOCTL_WEN_GRAM_B      :     std_logic;                            -- Write Enable to allow the HPS to write to the Blue GRAM.
signal IOCTL_WEN_GRAM_GI     :     std_logic;                            -- Write Enable to allow the HPS to write to the MZ80B GRAM I Option RAM.
signal IOCTL_WEN_GRAM_GII    :     std_logic;                            -- Write Enable to allow the HPS to write to the MZ80B GRAM II Option RAM.
signal IOCTL_WEN_STRAM       :     std_logic;                            -- Write Enable to allow the HPS to write to the Status Frame Buffer RAM for Green.
signal IOCTL_WEN_MNURAM      :     std_logic;                            -- Write Enable to allow the HPS to write to the Menu Frame Buffer RAM for Green.
signal IOCTL_WEN_CGROM       :     std_logic;
signal IOCTL_WEN_CGRAM       :     std_logic;
signal IOCTL_DIN_VRAM        :     std_logic_vector(7 downto 0);
signal IOCTL_DIN_GRAM        :     std_logic_vector(7 downto 0);
signal IOCTL_DIN_PCG         :     std_logic_vector(15 downto 0);
signal IOCTL_DIN_CGROM       :     std_logic_vector(7 downto 0);
signal IOCTL_DIN_CGRAM       :     std_logic_vector(7 downto 0);
signal IOCTL_DIN_STRAM       :     std_logic_vector(23 downto 0);
signal IOCTL_DIN_MNURAM      :     std_logic_vector(23 downto 0);
signal IOCTL_DIN_CONFIG      :     std_logic_vector(15 downto 0);

--
-- Components
--
component dpram
 generic (
      init_file          :     string;
      widthad_a          :     natural;
      width_a            :     natural;
      widthad_b          :     natural;
      width_b            :     natural;
      outdata_reg_a      :     string := "UNREGISTERED";
      outdata_reg_b      :     string := "UNREGISTERED"
  );
  Port (
      clock_a            : in  std_logic ;
      clocken_a          : in  std_logic := '1';
      address_a          : in  std_logic_vector (widthad_a-1 downto 0);
      data_a             : in  std_logic_vector (width_a-1 downto 0);
      wren_a             : in  std_logic;
      q_a                : out std_logic_vector (width_a-1 downto 0);

      clock_b            : in  std_logic ;
      clocken_b          : in  std_logic := '1';
      address_b          : in  std_logic_vector (widthad_b-1 downto 0);
      data_b             : in  std_logic_vector (width_b-1 downto 0);
      wren_b             : in  std_logic;
      q_b                : out std_logic_vector (width_b-1 downto 0)
);
end component;

begin

--
-- Instantiation
--

-- Video memory as seen by the MZ Series. This is a 1K or 2K or 2K + 2K Attribute RAM
-- organised as 4K x 8 on the CPU side and 2K x 16 on the display side, top bits are not used for MZ80K/C/1200/A.
--
VRAM0 : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 12,
    width_a              => 8,
    widthad_b            => 11,
    width_b              => 16,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for CPU access.
    clock_a              => VRAM_CLK,       
    clocken_a            => VRAM_CLK_EN,
    address_a            => VRAM_ADDR,      
    data_a               => VRAM_DI,   
    wren_a               => VRAM_WEN,       
    q_a                  => VRAM_DO,

    -- Port B used for VRAM -> DISPLAY BUFFER transfer (SOURCE).
    clock_b              => CLKBUS(CKMASTER),
    clocken_b            => '1',
    address_b            => XFER_VRAM_ADDR,
    data_b               => (others => '0'),
    wren_b               => '0',
    q_b                  => XFER_VRAM_DATA
);

-- Graphics frame buffer memory. This is an enhancement and allows for 320x200 or 640x200 pixel display in 8 colours. It matches
-- the output frame buffer in size, so the contents are blended by a programmable logical operator (ie. OR) with the expanded Video
-- Ram contents to create the output display.
--
GRAMG : dpram -- GREEN
GENERIC MAP (
    init_file            => null,
    widthad_a            => 14,
    width_a              => 8,
    widthad_b            => 14,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for CPU access.
    clock_a              => GRAM_CLK,
    clocken_a            => GRAM_CLK_EN,
    address_a            => GRAM_ADDR,
    data_a               => GRAM_DI_G,
    wren_a               => GRAM_WEN_G, 
    q_a                  => GRAM_DO_G,

    -- Port B used for VRAM -> DISPLAY BUFFER transfer (SOURCE).
    clock_b              => CLKBUS(CKMASTER),
    clocken_b            => '1',
    address_b            => XFER_DST_ADDR,   -- FB Destination address is used as GRAM is on a 1:1 mapping with FB.
    data_b               => (others => '0'),
    wren_b               => '0',
    q_b                  => XFER_GRAM_DATA(7 downto 0)
);
--
GRAMR : dpram -- RED
GENERIC MAP (
    init_file            => null,
    widthad_a            => 14,
    width_a              => 8,
    widthad_b            => 14,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for CPU access.
    clock_a              => GRAM_CLK,
    clocken_a            => GRAM_CLK_EN,
    address_a            => GRAM_ADDR,
    data_a               => GRAM_DI_R,
    wren_a               => GRAM_WEN_R, 
    q_a                  => GRAM_DO_R,

    -- Port B used for VRAM -> DISPLAY BUFFER transfer (SOURCE).
    clock_b              => CLKBUS(CKMASTER),
    clocken_b            => '1',
    address_b            => XFER_DST_ADDR,   -- FB Destination address is used as GRAM is on a 1:1 mapping with FB.
    data_b               => (others => '0'),
    wren_b               => '0',
    q_b                  => XFER_GRAM_DATA(15 downto 8)
);
--
GRAMB : dpram -- BLUE
GENERIC MAP (
    init_file            => null,
    widthad_a            => 14,
    width_a              => 8,
    widthad_b            => 14,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for CPU access.
    clock_a              => GRAM_CLK,
    clocken_a            => GRAM_CLK_EN,
    address_a            => GRAM_ADDR,
    data_a               => GRAM_DI_B,
    wren_a               => GRAM_WEN_B, 
    q_a                  => GRAM_DO_B,

    -- Port B used for VRAM -> DISPLAY BUFFER transfer (SOURCE).
    clock_b              => CLKBUS(CKMASTER),
    clocken_b            => '1',
    address_b            => XFER_DST_ADDR,   -- FB Destination address is used as GRAM is on a 1:1 mapping with FB.
    data_b               => (others => '0'),
    wren_b               => '0',
    q_b                  => XFER_GRAM_DATA(23 downto 16)
);

-- MZ80B Graphics RAM Option I
--
GRAMI : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 13,
    width_a              => 8,
    widthad_b            => 13,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for CPU access.
    clock_a              => GRAM_CLK,
    clocken_a            => GRAM_CLK_EN,
    address_a            => GRAM_ADDR(12 downto 0),
    data_a               => GRAM_DI_GI,
    wren_a               => GRAM_WEN_GI, 
    q_a                  => GRAM_DO_GI,

    -- Port B used for VRAM -> DISPLAY BUFFER transfer (SOURCE).
    clock_b              => CLKBUS(CKMASTER),
    clocken_b            => '1',
    address_b            => XFER_DST_ADDR(12 downto 0),            -- FB Destination address is used as GRAM is on a 1:1 mapping with FB.
    data_b               => (others => '0'),
    wren_b               => '0',
    q_b                  => XFER_GRAM_DATA(31 downto 24)
);

-- MZ80B Graphics RAM Option II
--
GRAMII : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 13,
    width_a              => 8,
    widthad_b            => 13,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for CPU access.
    clock_a              => GRAM_CLK,
    clocken_a            => GRAM_CLK_EN,
    address_a            => GRAM_ADDR(12 downto 0),
    data_a               => GRAM_DI_GII,
    wren_a               => GRAM_WEN_GII, 
    q_a                  => GRAM_DO_GII,

    -- Port B used for VRAM -> DISPLAY BUFFER transfer (SOURCE).
    clock_b              => CLKBUS(CKMASTER),
    clocken_b            => '1',
    address_b            => XFER_DST_ADDR(12 downto 0),           -- FB Destination address is used as GRAM is on a 1:1 mapping with FB.
    data_b               => (others => '0'),
    wren_b               => '0',
    q_b                  => XFER_GRAM_DATA(39 downto 32)
);

-- Display Buffer Memory, organised in a Row x Col format, where Address = (Row * MAX_COLUMN * 8) + Col,
-- but in real terms it is a 320x200x3 or 640x200x3 frame buffer.
--
FRAMEBUF0 : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 14,
    width_a              => 24,
    widthad_b            => 14,
    width_b              => 24,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for Display output.
    clock_a              => CLKBUS(CKMASTER),
    clocken_a            => CLKBUS(CKENVIDEO),
    address_a            => FB_ADDR,
    data_a               => (others => '0'),
    wren_a               => '0',
    q_a                  => DISPLAY_DATA,

    -- Port B used for VRAM -> DISPLAY BUFFER transfer (DESTINATION).
    clock_b              => CLKBUS(CKMASTER),
    clocken_b            => '1',
    address_b            => XFER_DST_ADDR,
    data_b               => XFER_MAPPED_DATA,
    wren_b               => XFER_WEN 
  --q_b                  =>
);

-- A small pixel mapped buffer to display status information in the border area of the frame
-- on VGA scaled output.
--
STATUSBUFG : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 12,
    width_a              => 8,
    widthad_b            => 12,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for Display output.
    clock_a              => CLKBUS(CKMASTER),
    clocken_a            => CLKBUS(CKENVIDEO),
    address_a            => FB_ADDR_STATUS,
    data_a               => (others => '0'),
    wren_a               => '0',
    q_a                  => DISPLAY_STATUS(7 downto 0),

    -- Port B used for IOCTL access.
    clock_b              => IOCTL_CLK,
    clocken_b            => '1',
    address_b            => IOCTL_ADDR(11 downto 0),
    data_b               => IOCTL_DOUT(7 downto 0),
    wren_b               => IOCTL_WEN_STRAM, 
    q_b                  => IOCTL_DIN_STRAM(7 downto 0)
);
--
STATUSBUFR : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 12,
    width_a              => 8,
    widthad_b            => 12,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for Display output.
    clock_a              => CLKBUS(CKMASTER),
    clocken_a            => CLKBUS(CKENVIDEO),
    address_a            => FB_ADDR_STATUS,
    data_a               => (others => '0'),
    wren_a               => '0',
    q_a                  => DISPLAY_STATUS(15 downto 8),

    -- Port B used for IOCTL access.
    clock_b              => IOCTL_CLK,
    clocken_b            => '1',
    address_b            => IOCTL_ADDR(11 downto 0),
    data_b               => IOCTL_DOUT(15 downto 8),
    wren_b               => IOCTL_WEN_STRAM, 
    q_b                  => IOCTL_DIN_STRAM(15 downto 8)
);
--
STATUSBUFB : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 12,
    width_a              => 8,
    widthad_b            => 12,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for Display output.
    clock_a              => CLKBUS(CKMASTER),
    clocken_a            => CLKBUS(CKENVIDEO),
    address_a            => FB_ADDR_STATUS,
    data_a               => (others => '0'),
    wren_a               => '0',
    q_a                  => DISPLAY_STATUS(23 downto 16),

    -- Port B used for IOCTL access.
    clock_b              => IOCTL_CLK,
    clocken_b            => '1',
    address_b            => IOCTL_ADDR(11 downto 0),
    data_b               => IOCTL_DOUT(23 downto 16),
    wren_b               => IOCTL_WEN_STRAM, 
    q_b                  => IOCTL_DIN_STRAM(23 downto 16)
);
--
MENUBUFG : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 13,
    width_a              => 8,
    widthad_b            => 13,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for Display output.
    clock_a              => CLKBUS(CKMASTER),
    clocken_a            => CLKBUS(CKENVIDEO),
    address_a            => FB_ADDR_MENU,
    data_a               => (others => '0'),
    wren_a               => '0',
    q_a                  => DISPLAY_MENU(7 downto 0),

    -- Port B used for IOCTL access.
    clock_b              => IOCTL_CLK,
    clocken_b            => '1',
    address_b            => IOCTL_ADDR(12 downto 0),
    data_b               => IOCTL_DOUT(7 downto 0),
    wren_b               => IOCTL_WEN_MNURAM,
    q_b                  => IOCTL_DIN_MNURAM(7 downto 0)
);
--
MENUBUFR : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 13,
    width_a              => 8,
    widthad_b            => 13,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for Display output.
    clock_a              => CLKBUS(CKMASTER),
    clocken_a            => CLKBUS(CKENVIDEO),
    address_a            => FB_ADDR_MENU,
    data_a               => (others => '0'),
    wren_a               => '0',
    q_a                  => DISPLAY_MENU(15 downto 8),

    -- Port B used for IOCTL access.
    clock_b              => IOCTL_CLK,
    clocken_b            => '1',
    address_b            => IOCTL_ADDR(12 downto 0),
    data_b               => IOCTL_DOUT(15 downto 8),
    wren_b               => IOCTL_WEN_MNURAM,
    q_b                  => IOCTL_DIN_MNURAM(15 downto 8)
);
--
MENUBUFB : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 13,
    width_a              => 8,
    widthad_b            => 13,
    width_b              => 8,
    outdata_reg_b        => "UNREGISTERED"
)
PORT MAP (
    -- Port A used for Display output.
    clock_a              => CLKBUS(CKMASTER),
    clocken_a            => CLKBUS(CKENVIDEO),
    address_a            => FB_ADDR_MENU,
    data_a               => (others => '0'),
    wren_a               => '0',
    q_a                  => DISPLAY_MENU(23 downto 16),

    -- Port B used for IOCTL access.
    clock_b              => IOCTL_CLK,
    clocken_b            => '1',
    address_b            => IOCTL_ADDR(12 downto 0),
    data_b               => IOCTL_DOUT(23 downto 16),
    wren_b               => IOCTL_WEN_MNURAM,
    q_b                  => IOCTL_DIN_MNURAM(23 downto 16)
);

-- 0 = MZ80K  CGROM = 2Kbytes -> 0000:07ff
-- 1 = MZ80C  CGROM = 2Kbytes -> 0800:0fff
-- 2 = MZ1200 CGROM = 2Kbytes -> 1000:17ff
-- 3 = MZ80A  CGROM = 2Kbytes -> 1800:1fff
-- 4 = MZ700  CGROM = 4Kbytes -> 2000:2fff
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
    clock_a              => CLKBUS(CKMASTER),
    clocken_a            => '1',
    address_a            => CGROM_BANK & CG_ADDR(10 downto 0),
    data_a               => (others => '0'),
    wren_a               => '0',
    q_a                  => CGROM_DO,

    clock_b              => IOCTL_CLK,
    clocken_b            => '1',
    address_b            => IOCTL_ADDR(14 downto 0),
    data_b               => IOCTL_DOUT(7 downto 0),
    wren_b               => IOCTL_WEN_CGROM,
    q_b                  => IOCTL_DIN_CGROM
);

CGRAM : dpram
GENERIC MAP (
    init_file            => null,
    widthad_a            => 12,
    width_a              => 8,
    widthad_b            => 12,
    width_b              => 8
) 
PORT MAP (
    clock_a              => CLKBUS(CKMASTER), 
    clocken_a            => '1',
    address_a            => CG_ADDR(11 downto 0),
    data_a               => CGRAM_DI,
    wren_a               => CGRAM_WEN,
    q_a                  => CGRAM_DO,

    clock_b              => IOCTL_CLK,
    clocken_b            => '1',
    address_b            => IOCTL_ADDR(11 downto 0),
    data_b               => IOCTL_DOUT(7 downto 0),
    wren_b               => IOCTL_WEN_CGRAM,
    q_b                  => IOCTL_DIN_CGRAM
);

-- Clock as maximum system speed to minimise transfer time.
--
process( RST_n, CLKBUS(CKMASTER) )
    variable XFER_CYCLE      : integer range 0 to 10;
    variable XFER_ENABLED    : std_logic;                            -- Enable transfer of VRAM/GRAM to framebuffer.
    variable XFER_PAUSE      : std_logic;                            -- Pause transfer of VRAM/GRAM to framebuffer during data display period.
    variable XFER_SRC_COL    : integer range 0 to 80;
    variable XFER_DST_SUBROW : integer range 0 to 7;
begin
    if RST_n='0' then
        XFER_VRAM_ADDR   <= (others => '0');
        XFER_DST_ADDR    <= (others => '0');
        XFER_CGROM_ADDR  <= (others => '0');
        XFER_ENABLED     := '0';
        XFER_PAUSE       := '0';
        XFER_SRC_COL     := 0;
        XFER_DST_SUBROW  := 0;
        XFER_CYCLE       := 0;
        XFER_WEN         <= '0';
        XFER_MAPPED_DATA <= (others => '0');

    -- Copy at end of Display based on the highest clock to minimise time,
    --
    elsif rising_edge(CLKBUS(CKMASTER)) then

        -- Every time we reach the end of the visible display area we enable copying of the VRAM and GRAM into the
        -- display framebuffer, ready for the next frame display. This starts to occur a fixed set of rows after 
        -- they have been displayed, initially only during the hblank period of a row, but the during the full row
        -- in the vblank period.
        --
        if V_COUNT = 0 then
            XFER_ENABLED   := '1';
        end if;

        -- During the actual data display, we pause until the start of the hblanking period.
        --
        if XFER_WEN = '0' and H_BLANKi = '0' and V_BLANKi = '0' then -- XFER_WEN = '0' and (((V_COUNT >= V_DSP_START and V_COUNT < V_DSP_END) and (H_COUNT >= H_DSP_START and H_COUNT < H_DSP_END)) or (H_COUNT >= H_LINE_END-1)) then
            XFER_PAUSE      := '1';
        else
            XFER_PAUSE      := '0';
        end if;

        -- If we are in the active transfer window, start transfer.
        --
        if XFER_ENABLED = '1' and XFER_PAUSE = '0' then

            -- Once we reach the end of the framebuffer, disable the copying until next frame.
            --
            if XFER_DST_ADDR = 16383 then
                XFER_ENABLED := '0';
            end if;

            -- Finite state machine to implement read, map and write.
            case (XFER_CYCLE) is

                when 0 =>
                    XFER_MAPPED_DATA <= (others => '0');
                    XFER_CYCLE       := 1;

                -- Get the source character and map via the PCG to a slice of the displayed character.
                -- Recalculate the destination address based on this loops values.
                when 1 =>
                    -- Setup the PCG address based on the read character.
                    XFER_CGROM_ADDR  <= XFER_VRAM_DATA(15) & XFER_VRAM_DATA(7 downto 0) & std_logic_vector(to_unsigned(XFER_DST_SUBROW, 3));
                    XFER_CYCLE       := 2;

                --   Graphics mode:- 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
                --                     5 = GRAM Output Enable  0 = active.
                --                     4 = VRAM Output Enable, 0 = active.
                --                   3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
                --                   1/0 = Read mode  (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
                --
                -- Extra cycle for CGROM to latch, use time to decide which mode we are processing.
                when 2 =>
                    -- Check to see if VRAM is disabled, if it is, skip.
                    --
                    if CONFIG(VRAMDISABLE) = '0' and GRAM_MODE(4) = '0' and (CONFIG(NORMAL) = '1' or CONFIG(NORMAL80) = '1') then
                        -- Monochrome modes?
                        XFER_CYCLE := 4;

                    elsif CONFIG(VRAMDISABLE) = '0' and GRAM_MODE(4) = '0' and (CONFIG(COLOUR) = '1' or CONFIG(COLOUR80) = '1') then
                        -- Colour modes?
                        XFER_CYCLE := 3;

                    else
                        -- Disabled or unrecognised mode.
                        XFER_CYCLE := 5;
                    end if;

                -- Colour modes?
                -- Expand and store the slice of the character with colour expansion.
                --
                when 3 =>
                    if CGROM_DATA(7) = '0' then
                        XFER_MAPPED_DATA(7)      <= XFER_VRAM_DATA(10);
                        XFER_MAPPED_DATA(15)     <= XFER_VRAM_DATA(9);
                        XFER_MAPPED_DATA(23)     <= XFER_VRAM_DATA(8);
                    else
                        XFER_MAPPED_DATA(7)      <= XFER_VRAM_DATA(14);
                        XFER_MAPPED_DATA(15)     <= XFER_VRAM_DATA(13);
                        XFER_MAPPED_DATA(23)     <= XFER_VRAM_DATA(12);
                    end if;
                    if CGROM_DATA(6) = '0' then
                        XFER_MAPPED_DATA(6)      <= XFER_VRAM_DATA(10);
                        XFER_MAPPED_DATA(14)     <= XFER_VRAM_DATA(9);
                        XFER_MAPPED_DATA(22)     <= XFER_VRAM_DATA(8);
                    else
                        XFER_MAPPED_DATA(6)      <= XFER_VRAM_DATA(14);
                        XFER_MAPPED_DATA(14)     <= XFER_VRAM_DATA(13);
                        XFER_MAPPED_DATA(22)     <= XFER_VRAM_DATA(12);
                    end if;
                    if CGROM_DATA(5) = '0' then
                        XFER_MAPPED_DATA(5)      <= XFER_VRAM_DATA(10);
                        XFER_MAPPED_DATA(13)     <= XFER_VRAM_DATA(9);
                        XFER_MAPPED_DATA(21)     <= XFER_VRAM_DATA(8);
                    else
                        XFER_MAPPED_DATA(5)      <= XFER_VRAM_DATA(14);
                        XFER_MAPPED_DATA(13)     <= XFER_VRAM_DATA(13);
                        XFER_MAPPED_DATA(21)     <= XFER_VRAM_DATA(12);
                    end if;
                    if CGROM_DATA(4) = '0' then
                        XFER_MAPPED_DATA(4)      <= XFER_VRAM_DATA(10);
                        XFER_MAPPED_DATA(12)     <= XFER_VRAM_DATA(9);
                        XFER_MAPPED_DATA(20)     <= XFER_VRAM_DATA(8);
                    else
                        XFER_MAPPED_DATA(4)      <= XFER_VRAM_DATA(14);
                        XFER_MAPPED_DATA(12)     <= XFER_VRAM_DATA(13);
                        XFER_MAPPED_DATA(20)     <= XFER_VRAM_DATA(12);
                    end if;
                    if CGROM_DATA(3) = '0' then
                        XFER_MAPPED_DATA(3)      <= XFER_VRAM_DATA(10);
                        XFER_MAPPED_DATA(11)     <= XFER_VRAM_DATA(9);
                        XFER_MAPPED_DATA(19)     <= XFER_VRAM_DATA(8);
                    else
                        XFER_MAPPED_DATA(3)      <= XFER_VRAM_DATA(14);
                        XFER_MAPPED_DATA(11)     <= XFER_VRAM_DATA(13);
                        XFER_MAPPED_DATA(19)     <= XFER_VRAM_DATA(12);
                    end if;
                    if CGROM_DATA(2) = '0' then
                        XFER_MAPPED_DATA(2)      <= XFER_VRAM_DATA(10);
                        XFER_MAPPED_DATA(10)     <= XFER_VRAM_DATA(9);
                        XFER_MAPPED_DATA(18)     <= XFER_VRAM_DATA(8);
                    else
                        XFER_MAPPED_DATA(2)      <= XFER_VRAM_DATA(14);
                        XFER_MAPPED_DATA(10)     <= XFER_VRAM_DATA(13);
                        XFER_MAPPED_DATA(18)     <= XFER_VRAM_DATA(12);
                    end if;
                    if CGROM_DATA(1) = '0' then
                        XFER_MAPPED_DATA(1)      <= XFER_VRAM_DATA(10);
                        XFER_MAPPED_DATA(9)      <= XFER_VRAM_DATA(9);
                        XFER_MAPPED_DATA(17)     <= XFER_VRAM_DATA(8);
                    else
                        XFER_MAPPED_DATA(1)      <= XFER_VRAM_DATA(14);
                        XFER_MAPPED_DATA(9)      <= XFER_VRAM_DATA(13);
                        XFER_MAPPED_DATA(17)     <= XFER_VRAM_DATA(12);
                    end if;
                    if CGROM_DATA(0) = '0' then
                        XFER_MAPPED_DATA(0)      <= XFER_VRAM_DATA(10);
                        XFER_MAPPED_DATA(8)      <= XFER_VRAM_DATA(9);
                        XFER_MAPPED_DATA(16)     <= XFER_VRAM_DATA(8);
                    else
                        XFER_MAPPED_DATA(0)      <= XFER_VRAM_DATA(14);
                        XFER_MAPPED_DATA(8)      <= XFER_VRAM_DATA(13);
                        XFER_MAPPED_DATA(16)     <= XFER_VRAM_DATA(12);
                    end if;
                    XFER_CYCLE := 6;

                -- Monochrome modes?
                -- Expand and store the slice of the character.
                --
                when 4 =>
                    if CGROM_DATA(7) = '1' then
                        XFER_MAPPED_DATA(7)      <= '1';
                        if CONFIG(MZ_KC) = '1' then
                            XFER_MAPPED_DATA(15) <= '1';
                            XFER_MAPPED_DATA(23) <= '1';
                        end if;
                    end if;
                    if CGROM_DATA(6) = '1' then
                        XFER_MAPPED_DATA(6)      <= '1';
                        if CONFIG(MZ_KC) = '1' then
                            XFER_MAPPED_DATA(14) <= '1';
                            XFER_MAPPED_DATA(22) <= '1';
                        end if;
                    end if;
                    if CGROM_DATA(5) = '1' then
                        XFER_MAPPED_DATA(5)      <= '1';
                        if CONFIG(MZ_KC) = '1' then
                            XFER_MAPPED_DATA(13) <= '1';
                            XFER_MAPPED_DATA(21) <= '1';
                        end if;
                    end if;
                    if CGROM_DATA(4) = '1' then
                        XFER_MAPPED_DATA(4)      <= '1';
                        if CONFIG(MZ_KC) = '1' then
                            XFER_MAPPED_DATA(12) <= '1';
                            XFER_MAPPED_DATA(20) <= '1';
                        end if;
                    end if;
                    if CGROM_DATA(3) = '1' then
                        XFER_MAPPED_DATA(3)      <= '1';
                        if CONFIG(MZ_KC) = '1' then
                            XFER_MAPPED_DATA(11) <= '1';
                            XFER_MAPPED_DATA(19) <= '1';
                        end if;
                    end if;
                    if CGROM_DATA(2) = '1' then
                        XFER_MAPPED_DATA(2)      <= '1';
                        if CONFIG(MZ_KC) = '1' then
                            XFER_MAPPED_DATA(10) <= '1';
                            XFER_MAPPED_DATA(18) <= '1';
                        end if;
                    end if;
                    if CGROM_DATA(1) = '1' then
                        XFER_MAPPED_DATA(1)      <= '1';
                        if CONFIG(MZ_KC) = '1' then
                            XFER_MAPPED_DATA(9)  <= '1';
                            XFER_MAPPED_DATA(17) <= '1';
                        end if;
                    end if;
                    if CGROM_DATA(0) = '1' then
                        XFER_MAPPED_DATA(0)      <= '1';
                        if CONFIG(MZ_KC) = '1' then
                            XFER_MAPPED_DATA(8)  <= '1';
                            XFER_MAPPED_DATA(16) <= '1';
                        end if;
                    end if;
                    XFER_CYCLE := 5;

                when 5 =>
                    -- If invert option selected, invert green.
                    --
                    if (CONFIG(MZ_80B) = '1' and INVERSE_n = '0') or (CONFIG(MZ_A) = '1' and DISPLAY_INVERT = '1') then
                        XFER_MAPPED_DATA(7 downto 0) <= not XFER_MAPPED_DATA(7 downto 0);
                    end if;
                    XFER_CYCLE := 6;

                when 6 =>
                    -- Graphics ram enabled?
                    --
                    if CONFIG(GRAMDISABLE) = '0' and GRAM_MODE(5) = '0' then
                        -- Merge in the graphics data using defined mode.
                        --
                        case GRAM_MODE(7 downto 6) is
                            when "00" =>
                                XFER_MAPPED_DATA <= XFER_MAPPED_DATA or   reverse_vector(XFER_GRAM_DATA(23 downto 16)) & reverse_vector(XFER_GRAM_DATA(15 downto 8)) & reverse_vector(XFER_GRAM_DATA(7 downto 0));
                            when "01" =>
                                XFER_MAPPED_DATA <= XFER_MAPPED_DATA and  reverse_vector(XFER_GRAM_DATA(23 downto 16)) & reverse_vector(XFER_GRAM_DATA(15 downto 8)) & reverse_vector(XFER_GRAM_DATA(7 downto 0));
                            when "10" =>
                                XFER_MAPPED_DATA <= XFER_MAPPED_DATA nand reverse_vector(XFER_GRAM_DATA(23 downto 16)) & reverse_vector(XFER_GRAM_DATA(15 downto 8)) & reverse_vector(XFER_GRAM_DATA(7 downto 0));
                            when "11" =>
                                XFER_MAPPED_DATA <= XFER_MAPPED_DATA xor  reverse_vector(XFER_GRAM_DATA(23 downto 16)) & reverse_vector(XFER_GRAM_DATA(15 downto 8)) & reverse_vector(XFER_GRAM_DATA(7 downto 0));
                        end case;
                    end if;
                    XFER_CYCLE := 7;

                when 7 =>
                    -- For MZ80B, if enabled, blend in the graphics memory.
                    --
                    if CONFIG(MZ_80B) = '1' and XFER_DST_ADDR < 8192 then
                        if GRAM_OPT_OUT1 = '1' and GRAM_OPT_OUT2 = '1' then
                            XFER_MAPPED_DATA(15 downto 8) <= XFER_MAPPED_DATA(15 downto 8) or reverse_vector(XFER_GRAM_DATA(31 downto 24)) or reverse_vector(XFER_GRAM_DATA(39 downto 32));
                        elsif GRAM_OPT_OUT1 = '1' then
                            XFER_MAPPED_DATA(15 downto 8) <= XFER_MAPPED_DATA(15 downto 8) or reverse_vector(XFER_GRAM_DATA(31 downto 24));
                        elsif GRAM_OPT_OUT2 = '1' then
                            XFER_MAPPED_DATA(15 downto 8) <= XFER_MAPPED_DATA(15 downto 8) or reverse_vector(XFER_GRAM_DATA(39 downto 32));
                        end if;
                    end if;
                    XFER_CYCLE := 8;

                -- Commence write of mapped data.
                when 8 =>
                    XFER_WEN   <= '1';
                    XFER_CYCLE := 9;

                -- Complete write and update address.
                when 9 =>
                    -- Write cycle to framebuffer finished.
                    XFER_WEN   <= '0';
                    XFER_CYCLE := 10;

                when 10 =>
                    -- For each source character, we generate 8 lines in the frame buffer. Thus we need to 
                    -- process the same source row 8 times, each time incrementing the sub-row which is used
                    -- to extract the next pixel set from the CG. This data is thus written into the destination as:-
                    -- <Row:0,CGLine:0,0 .. MAX_COLUMN -1> <Row:0,CGLine:1,0.. MAX_COLUMN -1> .. <Row:0,CGLine:7,0.. MAX_COLUMN -1>
                    -- ..
                    -- <Row:24,CGLine:0,0 .. MAX_COLUMN -1><Row:24,CGLine:1,0.. MAX_COLUMN -1> .. <Row:24,CGLine:7,0.. MAX_COLUMN -1>
                    --
                    -- To achieve this, we keep a note of the column and sub-row, incrementing the source address until end of line
                    -- then winding it back if we are still rendering the Characters for a given row. 
                    -- Destination address always increments every clock cycle to take the next pixel set.
                    --
                    if XFER_SRC_COL < MAX_COLUMN - 1 then
                        XFER_SRC_COL        := XFER_SRC_COL + 1;
                        XFER_VRAM_ADDR      <= XFER_VRAM_ADDR + 1;
                    else
                        if XFER_DST_SUBROW < MAX_SUBROW -1 then
                            XFER_SRC_COL    := 0;
                            XFER_DST_SUBROW := XFER_DST_SUBROW + 1;
                            XFER_VRAM_ADDR  <= XFER_VRAM_ADDR - (MAX_COLUMN - 1);
                        else
                            XFER_SRC_COL    := 0;
                            XFER_VRAM_ADDR  <= XFER_VRAM_ADDR + 1;
                            XFER_DST_SUBROW := 0;
                        end if;
                    end if;

                    -- Destination address increments every tick.
                    --
                    XFER_DST_ADDR <= XFER_DST_ADDR + 1;
                    XFER_CYCLE := 0;
            end case;
        end if;

        -- On a new cycle, reset the transfer parameters.
        --
        if V_COUNT = V_LINE_END and H_COUNT = H_LINE_END - 1 then

            -- Start of display, setup the start of VRAM for display according to machine. 
            if CONFIG(MZ_A) = '1' then
                XFER_VRAM_ADDR <= (OFFSET_ADDR & "000");
            else
                XFER_VRAM_ADDR   <= (others => '0');
            end if;
            XFER_DST_ADDR    <= (others => '0');
            XFER_CGROM_ADDR  <= (others => '0');
            XFER_SRC_COL     := 0;
            XFER_DST_SUBROW  := 0;
            XFER_CYCLE       := 0;
            XFER_ENABLED     := '0';
            XFER_WEN         <= '0';
            XFER_MAPPED_DATA <= (others => '0');
        end if;
    end if;
end process;

-- Process to generate the video data signals.
--
process( RST_n, CLKBUS )
begin
    -- On reset, set the basic parameters which hold the video signal generator in reset
    -- then load up the required parameter set and generate the video signal.
    --
    if RST_n = '0' then
            H_DSP_START                  <= 0;
            H_DSP_END                    <= 0;
            H_DSP_WND_START              <= 0;
            H_DSP_WND_END                <= 0;
            H_MNU_START                  <= 0;
            H_MNU_END                    <= 0;
            H_HDR_START                  <= 0;
            H_HDR_END                    <= 0;
            H_FTR_START                  <= 0;
            H_FTR_END                    <= 0;
            V_DSP_START                  <= 0;
            V_DSP_END                    <= 0;
            V_DSP_WND_START              <= 0;
            V_DSP_WND_END                <= 0;
            V_MNU_START                  <= 0;
            V_MNU_END                    <= 0;
            V_HDR_START                  <= 0;
            V_HDR_END                    <= 0;
            V_FTR_START                  <= 0;
            V_FTR_END                    <= 0;
            MAX_COLUMN                   <= 0;
            H_LINE_END                   <= 0;
            V_LINE_END                   <= 0;
            H_COUNT                      <= (others => '0');
            V_COUNT                      <= (others => '0');
            H_BLANKi                     <= '1';
            V_BLANKi                     <= '1';
            H_SYNC_ni                    <= '1';
            V_SYNC_ni                    <= '1';
            H_PX_CNT                     <= 0;
            V_PX_CNT                     <= 0;
            H_SHIFT_CNT                  <= 0;
            H_MNU_SHIFT_CNT              <= 0;
            VIDEOMODE_LAST               <= 0;
            VIDEOMODE_CHANGED            <= '1';
            FB_ADDR                      <= (others => '0');
            FB_ADDR_STATUS               <= (others => '0');
            FB_ADDR_MENU                 <= (others => '0');

  --  elsif rising_edge(CLKBUS(CKVIDEO)) then
    elsif rising_edge(CLKBUS(CKMASTER)) then
    if CLKBUS(CKENVIDEO) = '1' then

        -- If the video mode changes, reset the variables to the initial state. This occurs
        -- at the end of a frame to minimise the monitor syncing incorrectly.
        --
        VIDEOMODE_LAST                   <= VIDEOMODE;
        if VIDEOMODE_LAST /= VIDEOMODE then
            VIDEOMODE_CHANGED            <= '1';
        end if;
        if VIDEOMODE_CHANGED = '1' then

            -- Iniitialise control registers.
            --
            FB_ADDR                          <= (others => '0');
            FB_ADDR_STATUS                   <= (others => '0');
            FB_ADDR_MENU                     <= (others => '0');
            VIDEOMODE_CHANGED                <= '0';

            -- Load up configuration from the look up table based on video mode.
            --
            H_DSP_START                      <= FB_PARAMS(VIDEOMODE, 0);
            H_DSP_END                        <= FB_PARAMS(VIDEOMODE, 1);
            H_DSP_WND_START                  <= FB_PARAMS(VIDEOMODE, 2);
            H_DSP_WND_END                    <= FB_PARAMS(VIDEOMODE, 3);
            H_MNU_START                      <= FB_PARAMS(VIDEOMODE, 4);
            H_MNU_END                        <= FB_PARAMS(VIDEOMODE, 5);
            H_HDR_START                      <= FB_PARAMS(VIDEOMODE, 6);
            H_HDR_END                        <= FB_PARAMS(VIDEOMODE, 7);
            H_FTR_START                      <= FB_PARAMS(VIDEOMODE, 8);
            H_FTR_END                        <= FB_PARAMS(VIDEOMODE, 9);
            V_DSP_START                      <= FB_PARAMS(VIDEOMODE, 10);
            V_DSP_END                        <= FB_PARAMS(VIDEOMODE, 11);
            V_DSP_WND_START                  <= FB_PARAMS(VIDEOMODE, 12);
            V_DSP_WND_END                    <= FB_PARAMS(VIDEOMODE, 13);
            V_MNU_START                      <= FB_PARAMS(VIDEOMODE, 14);
            V_MNU_END                        <= FB_PARAMS(VIDEOMODE, 15);
            V_HDR_START                      <= FB_PARAMS(VIDEOMODE, 16);
            V_HDR_END                        <= FB_PARAMS(VIDEOMODE, 17);
            V_FTR_START                      <= FB_PARAMS(VIDEOMODE, 18);
            V_FTR_END                        <= FB_PARAMS(VIDEOMODE, 19);
            H_LINE_END                       <= FB_PARAMS(VIDEOMODE, 20);
            V_LINE_END                       <= FB_PARAMS(VIDEOMODE, 21);
            MAX_COLUMN                       <= FB_PARAMS(VIDEOMODE, 22);
            H_SYNC_START                     <= FB_PARAMS(VIDEOMODE, 23);
            H_SYNC_END                       <= FB_PARAMS(VIDEOMODE, 24);
            V_SYNC_START                     <= FB_PARAMS(VIDEOMODE, 25);
            V_SYNC_END                       <= FB_PARAMS(VIDEOMODE, 26);
            H_PX                             <= FB_PARAMS(VIDEOMODE, 27);
            V_PX                             <= FB_PARAMS(VIDEOMODE, 28);
            --
            H_COUNT                          <= (others => '0');
            V_COUNT                          <= (others => '0');
            H_BLANKi                         <= '1';
            V_BLANKi                         <= '1';
            H_SYNC_ni                        <= '1';
            V_SYNC_ni                        <= '1';
            H_PX_CNT                         <= 0;
            V_PX_CNT                         <= 0;
            H_SHIFT_CNT                      <= 0;
            H_MNU_SHIFT_CNT                  <= 0;

        else

            -- Activate/deactivate signals according to pixel position.
            --
            if H_COUNT =  H_DSP_START     then H_BLANKi  <= '0'; end if;
            --if H_COUNT =  H_LINE_END      then H_BLANKi  <= '0'; end if;
            if H_COUNT =  H_DSP_END       then H_BLANKi  <= '1'; end if;
            if H_COUNT =  H_SYNC_END      then H_SYNC_ni <= '1'; end if;
            if H_COUNT =  H_SYNC_START    then H_SYNC_ni <= '0'; end if;
            if V_COUNT =  V_DSP_START     then V_BLANKi  <= '0'; end if;
            --if V_COUNT =  V_LINE_END      then V_BLANKi  <= '0'; end if;
            if V_COUNT =  V_DSP_END       then V_BLANKi  <= '1'; end if;
            if V_COUNT =  V_SYNC_START    then V_SYNC_ni <= '0'; end if;
            if V_COUNT =  V_SYNC_END      then V_SYNC_ni <= '1'; end if;

            -- If we are in the active visible area, stream the required output based on the various buffers.
            --
            if H_COUNT >= H_DSP_START and H_COUNT < H_DSP_END and V_COUNT >= V_DSP_START and V_COUNT < V_DSP_END then

                if (V_COUNT >= V_DSP_WND_START and V_COUNT < V_DSP_WND_END) and (H_COUNT >= H_DSP_WND_START and H_COUNT < H_DSP_WND_END) then
                    -- Update Horizontal Pixel multiplier.
                    --
                    if H_PX_CNT = 0 then

                        H_PX_CNT             <= H_PX;
                        H_SHIFT_CNT          <= H_SHIFT_CNT - 1;

                        -- Main screen.
                        --
                        if H_SHIFT_CNT = 0 then -- and (V_COUNT >= V_DSP_WND_START and V_COUNT < V_DSP_WND_END) and (H_COUNT >= H_DSP_WND_START and H_COUNT < H_DSP_WND_END) then

                            -- During the visible portion of the frame, data is stored in the frame buffer in bytes, 1 bit per pixel x 8 and 3 colors,
                            -- thus 1 x 8 x 3 or 24 bit. Read out the values into shift registers to be serialised.
                            --
                            SR_G_DATA        <= DISPLAY_DATA( 7 downto 0);
                            SR_R_DATA        <= DISPLAY_DATA(15 downto 8);
                            SR_B_DATA        <= DISPLAY_DATA(23 downto 16);
                            FB_ADDR          <= FB_ADDR + 1;

                        else -- H_SHIFT_CNT /= 0 then --and H_COUNT >= H_DSP_START and H_COUNT < H_DSP_END and V_COUNT >= V_DSP_START and V_COUNT < V_DSP_END then
                            -- During the active display area, if the shift counter is not 0 and the horizontal multiplier is equal to the setting,
                            -- shift the data in the shift register to display the next pixel.
                            --
                            SR_G_DATA        <= SR_G_DATA(6 downto 0) & '0';
                            SR_R_DATA        <= SR_R_DATA(6 downto 0) & '0';
                            SR_B_DATA        <= SR_B_DATA(6 downto 0) & '0';

                        end if;
                    else
                        H_PX_CNT             <= H_PX_CNT - 1;
                    end if;
                else
                    -- Blank.
                    --
                    SR_G_DATA                <= (others => '0');
                    SR_R_DATA                <= (others => '0');
                    SR_B_DATA                <= (others => '0');
                    H_PX_CNT                 <= H_PX;
                    H_SHIFT_CNT              <= 1;
                end if;

                -- If the Status areas or the menu is enabled, create a data stream for the status/menu data to be merged with the main data.
                --
                if CONFIG(MENUENABLE) = '1' or CONFIG(STATUSENABLE) = '1' then

                    H_MNU_SHIFT_CNT          <= H_MNU_SHIFT_CNT - 1;

                    -- On each reset of the shift counter, load up Menu, Header, Footer or blank data to be serialised.
                    --
                    if H_MNU_SHIFT_CNT = 0 then

                        -- OSD Menu
                        --
                        if CONFIG(MENUENABLE) = '1'
                           and
                           ((V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and (H_COUNT >= H_MNU_START and H_COUNT < H_MNU_END)) then
        
                            -- Merge the OSD with the underlying screen data.
                            --
                            --for i in 0 to 7 loop
                            --    if DISPLAY_MENU(i) = '1' and DISPLAY_MENU(MENU_FG_GREEN) = '1' then
                            --        SR_G_MENU(i) <= '1';
                            --    elsif DISPLAY_MENU(i) = '0' and DISPLAY_MENU(MENU_BG_GREEN) = '1' then
                            --        SR_G_MENU(i) <= '1';
                            --    else
                            --        SR_G_MENU(i) <= '0';
                            --    end if;
                            --end loop;
                            --for i in 0 to 7 loop
                            --    if DISPLAY_MENU(i) = '1' and DISPLAY_MENU(MENU_FG_RED) = '1' then
                            --        SR_R_MENU(i) <= '1';
                            --    elsif DISPLAY_MENU(i) = '0' and DISPLAY_MENU(MENU_BG_RED) = '1' then
                            --        SR_R_MENU(i) <= '1';
                            --    else
                            --        SR_R_MENU(i) <= '0';
                            --    end if;
                            --end loop;
                            --for i in 0 to 7 loop
                            --    if DISPLAY_MENU(i) = '1' and DISPLAY_MENU(MENU_FG_BLUE) = '1' then
                            --        SR_B_MENU(i) <= '1';
                            --    elsif DISPLAY_MENU(i) = '0' and DISPLAY_MENU(MENU_BG_BLUE) = '1' then
                            --        SR_B_MENU(i) <= '1';
                            --    else
                            --        SR_B_MENU(i) <= '0';
                            --    end if;
                            --end loop;
                            SR_G_MENU        <= DISPLAY_MENU( 7 downto 0);
                            SR_R_MENU        <= DISPLAY_MENU(15 downto 8);
                            SR_B_MENU        <= DISPLAY_MENU(23 downto 16);
                            FB_ADDR_MENU     <= FB_ADDR_MENU + 1;
        
                        -- Header/Footer
                        --
                        elsif CONFIG(STATUSENABLE) = '1'
                              and
                              (((H_HDR_START /= H_HDR_END) and ((V_COUNT >= V_HDR_START and V_COUNT < V_HDR_END) and (H_COUNT >= H_HDR_START and H_COUNT < H_HDR_END)))
                                or
                               ((H_FTR_START /= H_FTR_END) and ((V_COUNT >= V_FTR_START and V_COUNT < V_FTR_END) and (H_COUNT >= H_FTR_START and H_COUNT < H_FTR_END)))) then
           
                            -- During the visible portion of the unused header/footer, read out the status frame buffer, 1 bit per pixel x 8 and 3 colours.
                            --
                            SR_G_MENU        <= DISPLAY_STATUS( 7 downto 0);
                            SR_R_MENU        <= DISPLAY_STATUS(15 downto 8);
                            SR_B_MENU        <= DISPLAY_STATUS(23 downto 16);
                            FB_ADDR_STATUS   <= FB_ADDR_STATUS + 1;
        
                        -- Blank.
                        --
                        else
                            SR_G_MENU        <= (others => '0');
                            SR_R_MENU        <= (others => '0');
                            SR_B_MENU        <= (others => '0');
                            H_MNU_SHIFT_CNT  <= 0;
                        end if;
        
                    -- Shift on each clock cycle to next active bit if not at start.
                    --
                    else 
                        SR_G_MENU            <= SR_G_MENU(6 downto 0) & '0';
                        SR_R_MENU            <= SR_R_MENU(6 downto 0) & '0';
                        SR_B_MENU            <= SR_B_MENU(6 downto 0) & '0';
                    end if;
                end if;
            else
                H_PX_CNT                     <= 0;
                H_SHIFT_CNT                  <= 0;
                H_MNU_SHIFT_CNT              <= 0;
            end if;

            -- Horizontal/Vertical counters are updated each clock cycle to accurately track pixel/timing.
            --
            if H_COUNT = H_LINE_END then
                H_COUNT                      <= (others => '0');
                H_PX_CNT                     <= 0;

                -- Update Vertical Pixel multiplier.
                --
                if V_PX_CNT = 0 then
                    V_PX_CNT                 <= V_PX;
                else
                    V_PX_CNT                 <= V_PX_CNT - 1;
                end if;

                -- When we need to repeat a line due to pixel multiplying, wind back the framebuffer address to start of line.
                --
                if V_COUNT >= V_DSP_WND_START and V_COUNT < V_DSP_WND_END and V_PX /= 0 and V_PX_CNT > 0 then
                    FB_ADDR                  <= FB_ADDR - MAX_COLUMN;
                end if;

                -- For VGA, expand the vertical pixels according to setting.
                --
                if CONFIG(MENUENABLE) = '1' and (V_COUNT >= V_MNU_START and V_COUNT < V_MNU_END) and V_PX /= 0 and V_PX_CNT > 0 then
                    FB_ADDR_MENU             <= FB_ADDR_MENU - 32;
                end if;

                -- Once we have reached the end of the active vertical display, reset the framebuffer address.
                --
                if V_COUNT = V_DSP_END then
                    FB_ADDR                  <= (others => '0');
                    FB_ADDR_STATUS           <= (others => '0');
                    FB_ADDR_MENU             <= (others => '0');
                end if;

                -- End of vertical line, increment to next or reset to beginning.
                --
                if V_COUNT = V_LINE_END then
                    V_COUNT                  <= (others => '0');
                    V_PX_CNT                 <= 0;
                else
                    V_COUNT                  <= V_COUNT + 1;
                end if;
            else
                H_COUNT                      <= H_COUNT + 1;
            end if;
        end if;
    end if;
    end if;
end process;

-- Control Registers
--
-- MZ1200/80A: INVERT display, accessed at E014
--             SCROLL display, accessed at E200 - E2FF, the address determines the offset.
-- F0-F3 clocks the i8253 gate for MZ80B. (not used in this module)
-- F4-F7 set ths MZ80B/MZ2000 graphics options. Bit 0 = 0, Write to Graphics RAM I, Bit 0 = 1, Write to Graphics RAM II.
--       Bit 1 = 1, blend Graphics RAM I output on display, Bit 2 = 1, blend Graphics RAM II output on display.
--
-- IO Range for Graphics enhancements is set by the MCTRL DISPLAY2{7:3] register.
-- x[0|8],<val> sets the graphics mode. 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR), 5=GRAM Output Enable, 4 = VRAM Output Enable, 3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect), 1/0=Read mode (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
-- x[1|9],<val> sets the Red bit mask (1 bit = 1 pixel, 8 pixels per byte).
-- x[2|A],<val> sets the Green bit mask (1 bit = 1 pixel, 8 pixels per byte).
-- x[3|B],<val> sets the Blue bit mask (1 bit = 1 pixel, 8 pixels per byte).
-- x[4|C]       switches in 1 16Kb page (3 pages) of graphics ram to C000 - FFFF. This overrides all MZ700 page switching functions.
-- x[5|D]       switches out the graphics ram and returns to previous state.
--
process( RST_n, CLKBUS(CKMASTER) )
begin
    if RST_n='0' then
        DISPLAY_INVERT        <= '0';
        OFFSET_ADDR           <= (others => '0');
        GRAM_MODE             <= "00001100";
        GRAM_R_FILTER         <= (others => '1');
        GRAM_G_FILTER         <= (others => '1');
        GRAM_B_FILTER         <= (others => '1');
        GRAM_OPT_WRITE        <= '0';
        GRAM_OPT_OUT1         <= '0';
        GRAM_OPT_OUT2         <= '0';

    elsif rising_edge(CLKBUS(CKMASTER)) then

        if CLKBUS(CKENCPU) = '1' then

            if CS_INVERT_n='0' and T80_RD_n='0' then
                DISPLAY_INVERT    <= T80_MA(0);
            end if;

            if CS_SCROLL_n='0' and T80_RD_n='0' then
                if CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1' then
                    OFFSET_ADDR   <= (others => '0');
                else
                    OFFSET_ADDR   <= T80_A(7 downto 0);
                end if;
            end if;

            if CS_FB_CTL_n = '0'   and T80_WR_n = '0' then
                GRAM_MODE         <= T80_DI;
            end if;

            if CS_FB_RED_n = '0'   and T80_WR_n = '0' then
                GRAM_R_FILTER     <= T80_DI;
            end if;

            if CS_FB_GREEN_n = '0' and T80_WR_n = '0' then
                GRAM_G_FILTER     <= T80_DI;
            end if;

            if CS_FB_BLUE_n = '0'  and T80_WR_n = '0' then
                GRAM_B_FILTER     <= T80_DI;
            end if;

            if CS_GRAM_OPT_n = '0' and T80_WR_n = '0' then
                GRAM_OPT_WRITE    <= T80_DI(0);
                GRAM_OPT_OUT1     <= T80_DI(1);
                GRAM_OPT_OUT2     <= T80_DI(2);
            end if;
        end if;
    end if;
end process;

-- Enable Video Wait States - Original design has wait states inserted into the cycle if the CPU accesses the VRAM during display. In the updated design, the VRAM
-- is copied into a framebuffer during the Vertical Blanking period so no wait states are needed. To keep consistency with the original design (for programs which depend on it),
-- the wait states can be enabled by configuration.
--
process( T80_MREQ_n ) begin
    if falling_edge(T80_MREQ_n) then
        VRAM_WAIT <= H_BLANKi;
    end if;
end process;
--
-- Extend wait by 1 cycle
process( CLKBUS(CKMASTER) ) begin
    if rising_edge(CLKBUS(CKMASTER)) then
        if CLKBUS(CKENCPU) = '1' then
            WAITii_n       <= WAITi_n;
        end if;
    end if;
end process;

--
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
process( RST_n, CLKBUS(CKMASTER) ) begin
    if RST_n = '0' then
        CGRAM_ADDR                <= (others=>'0');
        PCG_DATA                  <= (others=>'0');
        CGRAM_WE_n                <= '1';

    elsif rising_edge(CLKBUS(CKMASTER)) then

        if CLKBUS(CKENCPU) = '1' then

            if CS_PCG_n = '0' and T80_WR_n = '0' then
                -- Set the PCG Data to program to RAM. 
                if T80_A(1 downto 0) = "00" then
                    PCG_DATA                <= T80_DI;
                end if;

                -- Set the PCG Address in RAM. 
                if T80_A(1 downto 0) = "01" then
                    CGRAM_ADDR(7 downto 0)  <= T80_DI;
                end if;

                -- Set the PCG Control register.
                if T80_A(1 downto 0) = "10"  then
                    CGRAM_ADDR(11 downto 8) <= (T80_DI(2) and CONFIG(MZ_A)) & '1' & T80_DI(1 downto 0);
                    CGRAM_WE_n              <= not T80_DI(4);
                    CGRAM_SEL               <= T80_DI(5);
                end if;
            end if;
        end if;
    end if;
end process;

-- Process to allow the HPS or uC to read the configuration array.
--
process( IOCTL_CLK ) begin
    if rising_edge(IOCTL_CLK) then
        if IOCTL_ADDR(10) = '1' then
            IOCTL_DIN_CONFIG <= "00000000000" & std_logic_vector(to_unsigned(VIDEOMODE, 5));
        else
            IOCTL_DIN_CONFIG <= std_logic_vector(to_unsigned(FB_PARAMS(to_integer(unsigned(IOCTL_ADDR(4 downto 0))), to_integer(unsigned(IOCTL_ADDR(9 downto 5)))), IOCTL_DIN_CONFIG'length));
        end if;
    end if;
end process;

--
-- CPU / RAM signals and selects.
--
WAITi_n              <= '0'                                          when CS_VRAM_n = '0'          and VRAM_WAIT = '0' and H_BLANKi = '0' and (CONFIG(MZ_A) = '1' or CONFIG(MZ700) = '1')
                        else '1';
T80_WAIT_n           <= WAITi_n and WAITii_n                         when CONFIG(VRAMWAIT) = '1'
                        else '1';
T80_MA               <= "00" & T80_A(9 downto 0)                     when CONFIG(MZ_KC) = '1'
                        else
                        T80_A(11 downto 0);
-- Program Character Generator RAM. E010 - Write cycle (Read cycle = reset memory swap).
CS_PCG_n             <= '0'                                          when CS_MEM_G_n = '0'      and T80_A(10 downto 4) = "0000001"
                        else '1';                                                                   -- D010 -> D01f
-- Invert display register. E014/E015
CS_INVERT_n          <= '0'                                          when CS_MEM_G_n = '0'      and CONFIG(MZ_A) = '1'        and T80_MA(11 downto 9) = "000" and T80_MA(4 downto 2) = "101"
                        else '1';
-- Scroll display register. E200 - E2FF
CS_SCROLL_n          <= '0'                                          when CS_MEM_G_n = '0'      and T80_A(11 downto 8)="0010" and CONFIG(MZ_A)='1'
                        else '1';
-- MZ80B/MZ2000 Graphics Options Register select. F4-F7
CS_GRAM_OPT_n        <= '0'                                          when CS_IO_G_n = '0'       and T80_A(1 downto 0) = "00"
                        else '1';
-- <block>0,<val> sets the graphics mode. 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
--                                          5 = GRAM Output Enable, 4 = VRAM Output Enable,
--                                        3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
--                                        1/0 = Read mode (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
CS_FB_CTL_n          <= '0'                                          when CS_IO_GFB_n = '0'     and T80_A(2 downto 0) = "000"
                        else '1';
--  01,<val> sets the Red bit mask (1 bit = 1 pixel, 8 pixels per byte).
CS_FB_RED_n          <= '0'                                          when CS_IO_GFB_n = '0'     and T80_A(2 downto 0) = "001"
                        else '1';
--  02,<val> sets the Green bit mask (1 bit = 1 pixel, 8 pixels per byte).
CS_FB_GREEN_n        <= '0'                                          when CS_IO_GFB_n = '0'     and T80_A(2 downto 0) = "010"
                        else '1';
--  03,<val> sets the Blue bit mask (1 bit = 1 pixel, 8 pixels per byte).
CS_FB_BLUE_n         <= '0'                                          when CS_IO_GFB_n = '0'     and T80_A(2 downto 0) = "011"
                        else '1';

T80_DO               <= VRAM_VIDEO_DATA                              when T80_RD_n = '0'        and CS_VRAM_n = '0'
                        else
                        GRAM_VIDEO_DATA                              when T80_RD_n = '0'        and CS_GRAM_n = '0'
                        else
                        GRAM_DO_GI                                   when T80_RD_n = '0'        and CS_GRAM_80B_n = '0' and GRAM_OPT_WRITE = '0'
                        else
                        GRAM_DO_GII                                  when T80_RD_n = '0'        and CS_GRAM_80B_n = '0' and GRAM_OPT_WRITE = '1'
                        else
                        (others=>'0');

VRAM_ADDR            <= T80_MA(10 downto 0) & T80_MA(11)             when IOCTL_CS_VRAM_n = '1'
                        else
                        IOCTL_ADDR(10 downto 0) & IOCTL_ADDR(11);
VRAM_DI              <= T80_DI                                       when IOCTL_CS_VRAM_n = '1'
                        else
                        IOCTL_DOUT(7 downto 0);
VWEN                 <= '1'                                          when T80_WR_n='0'          and CS_VRAM_n = '0'
                        else '0';
VRAM_WEN             <= VWEN                                         when IOCTL_CS_VRAM_n = '1'
                        else
                        IOCTL_WEN_VRAM;
VRAM_VIDEO_DATA      <= VRAM_DO                                      when IOCTL_CS_VRAM_n = '1'
                        else
                        (others=>'0');
IOCTL_DIN_VRAM       <= VRAM_DO                                      when IOCTL_CS_VRAM_n = '0'
                        else
                        (others=>'0');
VRAM_CLK             <= CLKBUS(CKMASTER)                             when IOCTL_CS_VRAM_n = '1'
                        else
                        IOCTL_CLK;
VRAM_CLK_EN          <= CLKBUS(CKENCPU)                              when IOCTL_CS_VRAM_n = '1'
                        else
                        '1';

-- CGROM Data to CG RAM, either ROM -> RAM copy or Z80 provides map.
--
CGRAM_DI             <= CGROM_DO                                     when CGRAM_SEL = '1'               -- Data from ROM
                        else
                        PCG_DATA                                     when CGRAM_SEL = '0'               -- Data from PCG
                        else (others=>'0');
CGRAM_WEN            <= not (CGRAM_WE_n or CS_PCG_n) and not T80_WR_n; 

--
-- Font select
--
CGROM_DATA           <= CGROM_DO                                     when CONFIG(PCGRAM)='0'
                        else
                        PCG_DATA                                     when CS_PCG_n='0'         and T80_A(1 downto 0)="10" and T80_WR_n='0'
                        else
                        CGRAM_DO                                     when CONFIG(PCGRAM)='1'
                        else (others => '1');
CG_ADDR              <= CGRAM_ADDR(11 downto 0)                      when CGRAM_WE_n = '0'
                        else XFER_CGROM_ADDR;
CGROM_BANK           <= "0000"                                       when CONFIG(MZ80K)  = '1'
                        else
                        "0001"                                       when CONFIG(MZ80C)  = '1'
                        else
                        "0010"                                       when CONFIG(MZ1200) = '1'
                        else
                        "0011"                                       when CONFIG(MZ80A)  = '1'
                        else
                        "0100"                                       when CONFIG(MZ700)  = '1'  and XFER_CGROM_ADDR(11) = '0'
                        else
                        "0101"                                       when CONFIG(MZ700)  = '1'  and XFER_CGROM_ADDR(11) = '1'
                        else
                        "0110"                                       when CONFIG(MZ800)  = '1'  and XFER_CGROM_ADDR(11) = '0'
                        else
                        "0111"                                       when CONFIG(MZ800)  = '1'  and XFER_CGROM_ADDR(11) = '1'
                        else
                        "1000"                                       when CONFIG(MZ80B)  = '1'
                        else
                        "1001"                                       when CONFIG(MZ2000) = '1'
                        else
                        "1111";


-- As the Graphics RAM is an odd size, 16384 x 3 colour planes, it has to be in 3 seperate 16K blocks to avoid wasting memory (or having it synthesized away),
-- thus there are 3 sets of signals, 1 per colour.
--
GRAM_ADDR            <= T80_A(13 downto 0)                           when IOCTL_CS_GRAM_n = '1'
                        else
                        IOCTL_ADDR(13 downto 0);
                        -- direct writes when accessing individual pages.
GRAM_DI_R            <= T80_DI                                       when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "00"
                        else
                        T80_DI and GRAM_R_FILTER                     when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "11"
                        else
                        IOCTL_DOUT(7 downto 0)                       when IOCTL_CS_GRAM_n = '0' and IOCTL_ADDR(15 downto 14) = "00"
                        else
                        (others=>'0');
                        -- direct writes when accessing individual pages.
GRAM_DI_G            <= T80_DI                                       when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "01"
                        else
                        T80_DI and GRAM_G_FILTER                     when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "11"
                        else
                        IOCTL_DOUT(7 downto 0)                       when IOCTL_CS_GRAM_n = '0' and IOCTL_ADDR(15 downto 14) = "01"
                        else
                        (others=>'0');
                        -- direct writes when accessing individual pages.
GRAM_DI_B            <= T80_DI                                       when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "10"
                        else
                        T80_DI and GRAM_B_FILTER                     when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "11"
                        else
                        IOCTL_DOUT(7 downto 0)                       when IOCTL_CS_GRAM_n = '0' and IOCTL_ADDR(15 downto 14) = "10"
                        else
                        (others=>'0');
GWEN_R               <= '1'                                          when T80_WR_n = '0' and CS_GRAM_n = '0' and GRAM_MODE(3 downto 2) = "00"
                        else
                        '1'                                          when T80_WR_n = '0' and CS_GRAM_n = '0' and GRAM_MODE(3 downto 2) = "11"
                        else
                        '0';
GRAM_WEN_R           <= GWEN_R                                       when IOCTL_CS_GRAM_n = '1'
                        else
                        IOCTL_WEN_GRAM_R;
GWEN_G               <= '1'                                          when T80_WR_n='0'   and CS_GRAM_n = '0' and GRAM_MODE(3 downto 2) = "01"
                        else
                        '1'                                          when T80_WR_n='0'   and CS_GRAM_n = '0' and GRAM_MODE(3 downto 2) = "11"
                        else
                        '0';
GRAM_WEN_G           <= GWEN_G                                       when IOCTL_CS_GRAM_n = '1'
                        else
                        IOCTL_WEN_GRAM_G;
GWEN_B               <= '1'                                          when T80_WR_n='0'   and CS_GRAM_n = '0' and GRAM_MODE(3 downto 2) = "10"
                        else
                        '1'                                          when T80_WR_n='0'   and CS_GRAM_n = '0' and GRAM_MODE(3 downto 2) = "11"
                        else
                        '0';
GRAM_WEN_B           <= GWEN_B                                       when IOCTL_CS_GRAM_n = '1'
                        else
                        IOCTL_WEN_GRAM_B;

GRAM_VIDEO_DATA      <= GRAM_DO_R                                    when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(1 downto 0) = "00"
                        else
                        GRAM_DO_G                                    when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(1 downto 0) = "01"
                        else
                        GRAM_DO_B                                    when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(1 downto 0) = "10"
                        else
                        (others=>'0');
GRAM_CLK             <= CLKBUS(CKMASTER)                             when IOCTL_CS_GRAM_n = '1'
                        else
                        IOCTL_CLK;
GRAM_CLK_EN          <= CLKBUS(CKENCPU)                              when IOCTL_CS_GRAM_n = '1'
                        else
                        '1';

-- MZ80B/MZ2000 Graphics Option RAM.
--
GRAM_DI_GI           <= T80_DI                                       when IOCTL_CS_GRAM_80B_n = '1'
                        else
                        IOCTL_DOUT(7 downto 0)                       when IOCTL_CS_GRAM_80B_n = '0' and IOCTL_ADDR(13) = '0'
                        else
                        (others=>'0');
GRAM_DI_GII          <= T80_DI                                       when IOCTL_CS_GRAM_80B_n = '1'
                        else
                        IOCTL_DOUT(7 downto 0)                       when IOCTL_CS_GRAM_80B_n = '0' and IOCTL_ADDR(13) = '1'
                        else
                        (others=>'0');
GWEN_GI              <= '1'                                          when T80_WR_n = '0' and CS_GRAM_80B_n = '0' and GRAM_OPT_WRITE = '0'
                        else
                        '0';
GRAM_WEN_GI          <= GWEN_GI                                      when IOCTL_CS_GRAM_80B_n = '1'
                        else
                        IOCTL_WEN_GRAM_GI;
GWEN_GII             <= '1'                                          when T80_WR_n='0'   and CS_GRAM_80B_n = '0' and GRAM_OPT_WRITE = '1'
                        else
                        '0';
GRAM_WEN_GII         <= GWEN_GII                                     when IOCTL_CS_GRAM_80B_n = '1'
                        else
                        IOCTL_WEN_GRAM_GII;

--
-- HPS Access - match whole address, additional LE but easier to read.
--
IOCTL_WEN_VRAM       <= '1'                                          when IOCTL_CS_VRAM_n = '0'       and IOCTL_WR = '1'
                        else '0';
IOCTL_WEN_GRAM_R     <= '1'                                          when IOCTL_CS_GRAM_n = '0'       and IOCTL_WR = '1' and IOCTL_ADDR(15 downto 14) = "00"
                        else '0';
IOCTL_WEN_GRAM_G     <= '1'                                          when IOCTL_CS_GRAM_n = '0'       and IOCTL_WR = '1' and IOCTL_ADDR(15 downto 14) = "01"
                        else '0';
IOCTL_WEN_GRAM_B     <= '1'                                          when IOCTL_CS_GRAM_n = '0'       and IOCTL_WR = '1' and IOCTL_ADDR(15 downto 14) = "10"
                        else '0';
IOCTL_WEN_GRAM_GI    <= '1'                                          when IOCTL_CS_GRAM_80B_n = '0'   and IOCTL_WR = '1' and IOCTL_ADDR(13) = '0'
                        else '0';
IOCTL_WEN_GRAM_GII   <= '1'                                          when IOCTL_CS_GRAM_80B_n = '0'   and IOCTL_WR = '1' and IOCTL_ADDR(13) = '1'
                        else '0';
IOCTL_WEN_CGROM      <= '1'                                          when IOCTL_CS_CGROM_n = '0'      and IOCTL_WR = '1'
                        else '0';
IOCTL_WEN_CGRAM      <= '1'                                          when IOCTL_CS_CGRAM_n = '0'      and IOCTL_WR = '1'
                        else '0';
IOCTL_WEN_STRAM      <= '1'                                          when IOCTL_CS_STRAM_n = '0'      and IOCTL_WR = '1'
                        else '0';
IOCTL_WEN_MNURAM     <= '1'                                          when IOCTL_CS_MNURAM_n = '0'     and IOCTL_WR = '1'
                        else '0';
IOCTL_CS_VRAM_n      <= '0'                                          when IOCTL_ADDR(24 downto 12) = "0001100000000"
                        else '1';
IOCTL_CS_GRAM_n      <= '0'                                          when IOCTL_ADDR(24 downto 16) = "000110001" and IOCTL_ADDR(15 downto 14) /= "11"
                        else '1';
IOCTL_CS_GRAM_80B_n  <= '0'                                          when IOCTL_ADDR(24 downto 14) = "00011000111"
                        else '1';
IOCTL_CS_CGROM_n     <= '0'                                          when IOCTL_ADDR(24 downto 17) = "00101000"
                        else '1';
IOCTL_CS_CGRAM_n     <= '0'                                          when IOCTL_ADDR(24 downto 17) = "00110000"
                        else '1';
IOCTL_CS_STRAM_n     <= '0'                                          when IOCTL_ADDR(24 downto 16) = "000110010" and IOCTL_ADDR(15 downto 12) = "0000"
                        else '1';
IOCTL_CS_MNURAM_n    <= '0'                                          when IOCTL_ADDR(24 downto 16) = "000110010" and IOCTL_ADDR(15 downto 12) = "0010"
                        else '1';
IOCTL_CS_CONFIG_n    <= '0'                                          when IOCTL_ADDR(24 downto 16) = "000110010" and IOCTL_ADDR(15 downto 12) = "0100"
                        else '1';
IOCTL_DIN            <= X"000000" & IOCTL_DIN_VRAM                   when IOCTL_CS_VRAM_n = '0'       and IOCTL_RD = '1'
                        else
                        X"000000" & IOCTL_DIN_GRAM                   when IOCTL_CS_GRAM_n = '0'       and IOCTL_RD = '1'
                        else
                        X"FF0000" & IOCTL_DIN_CGROM                  when IOCTL_CS_CGROM_n = '0'      and IOCTL_RD = '1'
                        else
                        X"000000" & IOCTL_DIN_CGRAM                  when IOCTL_CS_CGRAM_n = '0'      and IOCTL_RD = '1'
                        else
                        X"00" & IOCTL_DIN_STRAM(23 downto 0)         when IOCTL_CS_STRAM_n = '0'      and IOCTL_RD = '1' 
                        else
                        X"0000" & IOCTL_DIN_MNURAM(15 downto 0)      when IOCTL_CS_MNURAM_n = '0'     and IOCTL_RD = '1'
                        else
                        X"0000" & IOCTL_DIN_CONFIG                   when IOCTL_CS_CONFIG_n = '0'     and IOCTL_RD = '1'
                        else
                        (others=>'0');                        
IOCTL_DIN_GRAM       <= GRAM_DO_R                                    when IOCTL_CS_GRAM_n = '0'       and IOCTL_ADDR(15 downto 14) = "00"
                        else
                        GRAM_DO_G                                    when IOCTL_CS_GRAM_n = '0'       and IOCTL_ADDR(15 downto 14) = "01"
                        else
                        GRAM_DO_B                                    when IOCTL_CS_GRAM_n = '0'       and IOCTL_ADDR(15 downto 14) = "10"
                        else
                        GRAM_DO_GI                                   when IOCTL_CS_GRAM_80B_n = '0'   and IOCTL_ADDR(13) = '0'
                        else
                        GRAM_DO_GII                                  when IOCTL_CS_GRAM_80B_n = '0'   and IOCTL_ADDR(13) = '1'
                        else
                        (others=>'0');

-- Work out the current video mode, which is used to look up the parameters for frame generation.
--
VIDEOMODE            <= 0  when CONFIG(VGAMODE) = "11" and CONFIG(MZ_80B)   = '1' and CONFIG_CHAR80 = '0'
                        else
                        1  when CONFIG(VGAMODE) = "11" and CONFIG(MZ_80B)   = '1' and CONFIG_CHAR80 = '1'
                        else
                        2  when CONFIG(VGAMODE) = "11" and CONFIG(NORMAL)   = '1'
                        else
                        3  when CONFIG(VGAMODE) = "11" and CONFIG(NORMAL80) = '1'
                        else
                        4  when CONFIG(VGAMODE) = "11" and CONFIG(COLOUR)   = '1' and CONFIG(MZ700) = '1'
                        else
                        5  when CONFIG(VGAMODE) = "11" and CONFIG(COLOUR80) = '1' and CONFIG(MZ700) = '1'
                        else
                        6  when CONFIG(VGAMODE) = "11" and CONFIG(COLOUR)   = '1'
                        else
                        7  when CONFIG(VGAMODE) = "11" and CONFIG(COLOUR80) = '1' 
                        else
                        8  when CONFIG(VGAMODE) = "00" and CONFIG(MZ_80B)   = '1' and CONFIG_CHAR80 = '0'
                        else
                        10 when CONFIG(VGAMODE) = "00" and CONFIG(MZ_80B)   = '1' and CONFIG_CHAR80 = '1'
                        else
                        9  when CONFIG(VGAMODE) = "01" and CONFIG(MZ_80B)   = '1' and CONFIG_CHAR80 = '0'
                        else
                        11 when CONFIG(VGAMODE) = "01" and CONFIG(MZ_80B)   = '1' and CONFIG_CHAR80 = '1'
                        else
                        8  when CONFIG(VGAMODE) = "00" and CONFIG(NORMAL)   = '1'
                        else
                        9  when CONFIG(VGAMODE) = "01" and CONFIG(NORMAL)   = '1'
                        else
                        10 when CONFIG(VGAMODE) = "00" and CONFIG(NORMAL80) = '1'
                        else
                        11 when CONFIG(VGAMODE) = "01" and CONFIG(NORMAL80) = '1'
                        else
                        12 when CONFIG(VGAMODE) = "00" and CONFIG(COLOUR)   = '1' and CONFIG(MZ700) = '1'
                        else
                        13 when CONFIG(VGAMODE) = "01" and CONFIG(COLOUR)   = '1' and CONFIG(MZ700) = '1'
                        else
                        18 when CONFIG(VGAMODE) = "10" and CONFIG(COLOUR)   = '1' and CONFIG(MZ700) = '1'
                        else
                        14 when CONFIG(VGAMODE) = "00" and CONFIG(COLOUR80) = '1' and CONFIG(MZ700) = '1'
                        else
                        15 when CONFIG(VGAMODE) = "01" and CONFIG(COLOUR80) = '1' and CONFIG(MZ700) = '1'
                        else
                        19 when CONFIG(VGAMODE) = "10" and CONFIG(COLOUR80) = '1' and CONFIG(MZ700) = '1'
                        else
                        12 when CONFIG(VGAMODE) = "00" and CONFIG(COLOUR)   = '1'
                        else
                        13 when CONFIG(VGAMODE) = "01" and CONFIG(COLOUR)   = '1'
                        else
                        18 when CONFIG(VGAMODE) = "10" and CONFIG(COLOUR)   = '1'
                        else
                        14 when CONFIG(VGAMODE) = "00" and CONFIG(COLOUR80) = '1'
                        else
                        15 when CONFIG(VGAMODE) = "01" and CONFIG(COLOUR80) = '1'
                        else
                        19 when CONFIG(VGAMODE) = "10" and CONFIG(COLOUR80) = '1'
                        else
                        16 when CONFIG(VGAMODE) = "10" and CONFIG(NORMAL)   = '1'
                        else
                        17 when CONFIG(VGAMODE) = "10" and CONFIG(NORMAL80) = '1'
                        else
                        2;

    --
    -- Video Output Signals
    --
    VBLANK           <= V_BLANKi;
    HBLANK           <= H_BLANKi;
    VSYNC_n          <= V_SYNC_ni;
    HSYNC_n          <= H_SYNC_ni;
    ROUT             <= (others => SR_R_DATA(7) or SR_R_MENU(7)) when H_BLANKi='0' or VGATE_n='1'
                        else
                        (others => '0');
    GOUT             <= (others => SR_G_DATA(7) or SR_G_MENU(7)) when H_BLANKi='0' or VGATE_n='1'
                        else
                        (others => '0');
    BOUT             <= (others => SR_B_DATA(7) or SR_B_MENU(7)) when H_BLANKi='0' or VGATE_n='1'
                        else
                        (others => '0');

end RTL;
