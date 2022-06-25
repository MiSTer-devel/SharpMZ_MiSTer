---------------------------------------------------------------------------------------------------------
--
-- Name:            mz80c_video.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series Video logic.
--                  This module fully emulates the Sharp MZ Personal Computer series video display
--                  logic plus extensions.
--                  The display is capable of performing 40x25, 80x25 Mono/Colour display along with
--                  a Programmable Character Generator and a bit mapped 320x200/640x200 framebuffer.                                                                                                    
--                  The design is slightly different to the original Sharps in that I use a dual
--                  buffer technique, ie. the original 1K/2K VRAM + ARAM and a pixel mapped displaybuffer.
--                  During Vertical blanking, the VRAM+ARAM is copied and expanded into the display
--                  buffer which is then displayed during the next display window. Part of the reasoning
--                  was to cut down on snow/tearing on the older K/C models (but still provide the
--                  blanking signals so any original software works) and also allow the option of
--                  disabling the MZ80A/700 wait states.
--                  As an addition, I added a graphics framebuffer (320x200, 640x200 8 colours) 
--                  the interface to which is, at the moment, non-standard, but as I get more details
--                  on add on cards, I can add mapping layers so this graphics framebuffer can be used
--                  by customised software. Pixels drawn in the graphics framebuffer can be blended into
--                  the main display buffer via programmable logic mode (ie. XOR, OR etc).
--                  A lot of timing information can be found in the docs/SharpMZ_Notes.xlsx spreadsheet,
--                  but the main info is:
--                      MZ80K/C/1200/A (Monochrome)				
--                      Signal	Start	End	Period	Comment
--                      64uS 15.625KHz				
--                      HDISPEN	0	320	 40uS	
--                      HBLANK	318	510	 24uS	
--                      BLNK	    318	486	 21uS	
--                      HSYNC	393	438	 5.625uS	
-- 				
--                      16.64mS 60.10Hz				
--                      VDISPEN	0	200	 12.8mS	
--                      VSYNC	219	223	 256uS	
--                      VBLANK	201	259	 3.712mS	not VDISPEN
-- 				
--                      MZ700 (Colour)				
--                      Signal	Start	End	Period	Comment
--                      64.056uS 15.611KHz				
--                      HDISPEN	0	320	 36.088uS	
--                      HBLANK	320	567	 27.968uS	
--                      BLNK	320	548	 25.7126uS	
--                      HSYNC	400	440	   4.567375uS	
-- 				
--                      16.654mS 50.0374Hz				
--                      VDISPEN	0	200	 12.8112mS	
--                      VSYNC	212	215	 0.19216ms	
--                      VBLANK	201	311	 7.1738mS	 not VDISPEN                                                                                                            
--                                                         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         July 2018      - Initial module written.
--                  August 2018    - Main portions written, including the display buffer.
--                  September 2018 - Added the graphics framebuffer.
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

entity mz80c_video is
    Port (
        RST_n                : in  std_logic;                            -- Reset

        -- Different operations modes.
        CONFIG               : in  std_logic_vector(CONFIG_WIDTH);

        -- Clocks
        CLKBUS               : in  std_logic_vector(CLKBUS_WIDTH);       -- Clock signals created by clkgen module.

        -- CPU Signals
        T80_A                : in  std_logic_vector(13 downto 0);        -- CPU Address Bus
        T80_RD_n             : in  std_logic;                            -- CPU Read Signal
        T80_WR_n             : in  std_logic;                            -- CPU Write Signal
        T80_MREQ_n           : in  std_logic;                            -- CPU Memory Request
        T80_BUSACK_n         : in  std_logic;                            -- CPU Bus Acknowledge
        T80_WAIT_n           : out std_logic;                            -- CPU Wait Request
        T80_DI               : in  std_logic_vector(7 downto 0);         -- CPU Data Bus in
        T80_DO               : out std_logic_vector(7 downto 0);         -- CPU Data Bus out

        -- Selects.
        CS_D_n               : in  std_logic;                            -- VRAM Select
        CS_E_n               : in  std_logic;                            -- Peripherals Select
        CS_G_n               : in  std_logic;                            -- GRAM Select
        CS_IO_GRAM_n         : in  std_logic;                            -- GRAM IO Select range E8 - EF

        -- Video Signals
        VGATE_n              : in  std_logic;                            -- Video Output Control
        HBLANK               : out std_logic;                            -- Horizontal Blanking
        VBLANK               : out std_logic;                            -- Vertical Blanking
        HSYNC_n              : out std_logic;                            -- Horizontal Sync
        VSYNC_n              : out std_logic;                            -- Vertical Sync
        ROUT                 : out std_logic;                            -- Red Output
        GOUT                 : out std_logic;                            -- Green Output
        BOUT                 : out std_logic;                            -- Green Output

        -- HPS Interface
        IOCTL_DOWNLOAD       : in  std_logic;                            -- HPS Downloading to FPGA.
        IOCTL_UPLOAD         : in  std_logic;                            -- HPS Uploading from FPGA.
        IOCTL_CLK            : in  std_logic;                            -- HPS I/O Clock..
        IOCTL_WR             : in  std_logic;                            -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                            -- HPS Read Enable from FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0)         -- HPS Data to be read into HPS.
    );
end mz80c_video;

architecture RTL of mz80c_video is

--
-- Registers
--
signal MAX_COLUMN            :     integer range 0 to 80;
signal MAX_ROW               :     integer range 0 to 25;
signal MAX_SUBROW            :     integer range 0 to 8;
signal FB_ADDR               :     std_logic_vector(13 downto 0);        -- Frame buffer actual address
signal OFFSET_ADDR           :     std_logic_vector(7 downto 0);         -- Display Offset - for MZ1200/80A machines with 2K VRAM
signal SR_G_DATA             :     std_logic_vector(7 downto 0);         -- Shift Register to Display Green
signal SR_R_DATA             :     std_logic_vector(7 downto 0);         -- Shift Register to Display Red
signal SR_B_DATA             :     std_logic_vector(7 downto 0);         -- Shift Register to Display Blue
signal DISPLAY_DATA          :     std_logic_vector(23 downto 0);
signal XFER_ADDR             :     std_logic_vector(10 downto 0);
signal XFER_SUB_ADDR         :     std_logic_vector(2 downto 0);
signal XFER_VRAM_DATA        :     std_logic_vector(15 downto 0);
signal XFER_GRAM_DATA        :     std_logic_vector(23 downto 0);
signal XFER_MAPPED_DATA      :     std_logic_vector(23 downto 0);
signal XFER_WEN              :     std_logic;
signal XFER_VRAM_ADDR        :     std_logic_vector(10 downto 0);
signal XFER_DST_ADDR         :     std_logic_vector(13 downto 0);
signal XFER_CGROM_ADDR       :     std_logic_vector(11 downto 0);
signal CGROM_DATA            :     std_logic_vector(7 downto 0);         -- Font Data To Display
signal DISPLAY_INVERT        :     std_logic;                            -- Invert display Mode of MZ80A/1200

--
-- CPU/Video Access
--
signal VRAM_VIDEO_DATA       :     std_logic_vector(7 downto 0);         -- Display data output to CPU.
signal VRAM_ADDR             :     std_logic_vector(11 downto 0);        -- VRAM Address.
signal VRAM_DATA_IN          :     std_logic_vector(7 downto 0);         -- VRAM Data in.
signal VRAM_DATA_OUT         :     std_logic_vector(7 downto 0);         -- VRAM Data out.
signal VRAM_WEN              :     std_logic;                            -- VRAM Write enable signal.
signal VRAM_CLK              :     std_logic;                            -- Clock used to access the VRAM (CKMEM or IOCTL_CLK).
signal GRAM_VIDEO_DATA       :     std_logic_vector(7 downto 0);         -- Graphics display data output to CPU.
signal GRAM_ADDR             :     std_logic_vector(13 downto 0);        -- Graphics RAM Address.
signal GRAM_DATA_IN_R        :     std_logic_vector(7 downto 0);         -- Graphics Red RAM Data.
signal GRAM_DATA_IN_G        :     std_logic_vector(7 downto 0);         -- Graphics Green RAM Data.
signal GRAM_DATA_IN_B        :     std_logic_vector(7 downto 0);         -- Graphics Blue RAM Data.
signal GRAM_DATA_OUT_R       :     std_logic_vector(7 downto 0);         -- Graphics Red RAM Data out.
signal GRAM_DATA_OUT_G       :     std_logic_vector(7 downto 0);         -- Graphics Green RAM Data out.
signal GRAM_DATA_OUT_B       :     std_logic_vector(7 downto 0);         -- Graphics Blue RAM Data out.
signal GRAM_WEN_R            :     std_logic;                            -- Graphics Red RAM Write enable signal.
signal GRAM_WEN_G            :     std_logic;                            -- Graphics Green RAM Write enable signal.
signal GRAM_WEN_B            :     std_logic;                            -- Graphics Blue RAM Write enable signal.
signal GRAM_CLK              :     std_logic;                            -- Clock used to access the GRAM (CKMEM or IOCTL_CLK).
signal GRAM_MODE             :     std_logic_vector(7 downto 0);         -- Programmable mode register to control GRAM operations.
signal GRAM_RED_WRITER       :     std_logic_vector(7 downto 0);         -- Red pixel writer filter.
signal GRAM_GREEN_WRITER     :     std_logic_vector(7 downto 0);         -- Green pixel writer filter.
signal GRAM_BLUE_WRITER      :     std_logic_vector(7 downto 0);         -- Blue pixel writer filter.
signal T80_MA                :     std_logic_vector(11 downto 0);        -- CPU Address Masked according to machine model.
signal CS_INVERT_n           :     std_logic;                            -- Chip Select to enable Inverse mode.
signal CS_SCROLL_n           :     std_logic;                            -- Chip Select to perform a hardware scroll.
signal CS_IO_EA_n            :     std_logic;                            -- Chip Select to write to the Graphics mode register.
signal CS_IO_EB_n            :     std_logic;                            -- Chip Select to write to the Red pixel per byte indirect write register.
signal CS_IO_EC_n            :     std_logic;                            -- Chip Select to write to the Green pixel per byte indirect write register.
signal CS_IO_ED_n            :     std_logic;                            -- Chip Select to write to the Blue pixel per byte indirect write register.
signal CS_PCG_n              :     std_logic;
signal WAITi_n               :     std_logic;                            -- Wait
signal WAITii_n              :     std_logic;                            -- Wait(delayed)
signal VWEN                  :     std_logic;                            -- Write enable to VRAM.
signal GWEN_R                :     std_logic;                            -- Write enable to Red GRAM.
signal GWEN_G                :     std_logic;                            -- Write enable to Green GRAM.
signal GWEN_B                :     std_logic;                            -- Write enable to Blue GRAM.
--
-- Internal Signals
--
signal H_COUNT               :     unsigned(10 downto 0);                -- Horizontal pixel counter
signal H_BLANKi              :     std_logic;                            -- Horizontal Blanking
signal H_SYNC_ni             :     std_logic;                            -- Horizontal Blanking
signal H_DISPLAY_START       :     integer range 0 to 2047;
signal H_DISPLAY_END         :     integer range 0 to 2047;
signal H_BLNK_START          :     integer range 0 to 2047;
signal H_BLNK_END            :     integer range 0 to 2047;
signal H_SYNC_START          :     integer range 0 to 2047;
signal H_SYNC_END            :     integer range 0 to 2047;
signal H_LINE_END            :     integer range 0 to 2047;
signal V_COUNT               :     unsigned(10 downto 0);                -- Vertical pixel counter
signal V_BLANKi              :     std_logic;                            -- Vertical Blanking
signal V_SYNC_ni             :     std_logic;                            -- Horizontal Blanking
signal V_DISPLAY_START       :     integer range 0 to 2047;
signal V_DISPLAY_END         :     integer range 0 to 2047;
signal V_SYNC_START          :     integer range 0 to 2047;
signal V_SYNC_END            :     integer range 0 to 2047;
signal V_LINE_END            :     integer range 0 to 2047;
signal BLNK                  :     std_logic;                            -- Horizontal Blanking CPU Wait interval
signal BLNK_MEMACCESS        :     std_logic;                            -- Horizontal Blanking Memory Access
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
signal IOCTL_WEN_VRAM        :     std_logic;                            -- Write Enable to allow the HPS to write to VRAM.
signal IOCTL_WEN_GRAM_R      :     std_logic;                            -- Write Enable to allow the HPS to write to the Red GRAM.
signal IOCTL_WEN_GRAM_G      :     std_logic;                            -- Write Enable to allow the HPS to write to the Green GRAM.
signal IOCTL_WEN_GRAM_B      :     std_logic;                            -- Write Enable to allow the HPS to write to the Blue GRAM.
signal IOCTL_DIN_VRAM        :     std_logic_vector(7 downto 0);
signal IOCTL_DIN_GRAM        :     std_logic_vector(7 downto 0);
signal IOCTL_DIN_PCG         :     std_logic_vector(15 downto 0);
signal IOCTL_CS_CGROM_n      :     std_logic;
signal IOCTL_CS_CGRAM_n      :     std_logic;
signal IOCTL_WEN_CGROM       :     std_logic;
signal IOCTL_WEN_CGRAM       :     std_logic;
signal IOCTL_DIN_CGROM       :     std_logic_vector(7 downto 0);
signal IOCTL_DIN_CGRAM       :     std_logic_vector(7 downto 0);

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
        clocken_a            => '1',
        address_a            => VRAM_ADDR,      
        data_a               => VRAM_DATA_IN,   
        wren_a               => VRAM_WEN,       
        q_a                  => VRAM_DATA_OUT,

        -- Port B used for VRAM -> DISPLAY BUFFER transfer (SOURCE).
        clock_b              => CLKBUS(CKSYS),
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
        clocken_a            => '1',
        address_a            => GRAM_ADDR,
        data_a               => GRAM_DATA_IN_G,
        wren_a               => GRAM_WEN_G, 
        q_a                  => GRAM_DATA_OUT_G,

        -- Port B used for VRAM -> DISPLAY BUFFER transfer (SOURCE).
        clock_b              => CLKBUS(CKSYS),
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
        clocken_a            => '1',
        address_a            => GRAM_ADDR,
        data_a               => GRAM_DATA_IN_R,
        wren_a               => GRAM_WEN_R, 
        q_a                  => GRAM_DATA_OUT_R,

        -- Port B used for VRAM -> DISPLAY BUFFER transfer (SOURCE).
        clock_b              => CLKBUS(CKSYS),
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
        clocken_a            => '1',
        address_a            => GRAM_ADDR,
        data_a               => GRAM_DATA_IN_B,
        wren_a               => GRAM_WEN_B, 
        q_a                  => GRAM_DATA_OUT_B,

        -- Port B used for VRAM -> DISPLAY BUFFER transfer (SOURCE).
        clock_b              => CLKBUS(CKSYS),
        clocken_b            => '1',
        address_b            => XFER_DST_ADDR,   -- FB Destination address is used as GRAM is on a 1:1 mapping with FB.
        data_b               => (others => '0'),
        wren_b               => '0',
        q_b                  => XFER_GRAM_DATA(23 downto 16)
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
        clock_a              => CLKBUS(CKVIDEO),
        clocken_a            => '1',
        address_a            => FB_ADDR,
        data_a               => (others => '0'),
        wren_a               => '0',
        q_a                  => DISPLAY_DATA,

        -- Port B used for VRAM -> DISPLAY BUFFER transfer (DESTINATION).
        clock_b              => CLKBUS(CKSYS),
        clocken_b            => '1',
        address_b            => XFER_DST_ADDR,
        data_b               => XFER_MAPPED_DATA,
        wren_b               => XFER_WEN 
      --q_b                  =>
    );

    -- 0 = MZ80K  CGROM = 2Kbytes -> 0000:07ff
    -- 1 = MZ80C  CGROM = 2Kbytes -> 0800:0fff
    -- 2 = MZ1200 CGROM = 2Kbytes -> 1000:17ff
    -- 3 = MZ80A  CGROM = 2Kbytes -> 1800:1fff
    -- 4 = MZ700  CGROM = 4Kbytes -> 2000:2fff
    --
    CGROM0 : dpram
    GENERIC MAP (
        init_file            => "./mif/combined_cgrom.mif",
        widthad_a            => 15,
        width_a              => 8,
        widthad_b            => 15,
        width_b              => 8
    ) 
    PORT MAP (
        clock_a              => CLKBUS(CKSYS),
        clocken_a            => '1',
        address_a            => CGROM_BANK & CG_ADDR(10 downto 0),
        data_a               => (others => '0'),
        wren_a               => '0',
        q_a                  => CGROM_DO,

        clock_b              => IOCTL_CLK,
        clocken_b            => '1',
        address_b            => IOCTL_ADDR(14 downto 0),
        data_b               => IOCTL_DOUT(7 DOWNTO 0),
        wren_b               => IOCTL_WEN_CGROM,
        q_b                  => IOCTL_DIN_CGROM
    );

    CGRAM : dpram
    GENERIC MAP (
        init_file            => "./mif/combined_cgrom.mif",
        widthad_a            => 15,
        width_a              => 8,
        widthad_b            => 15,
        width_b              => 8
    ) 
    PORT MAP (
        clock_a              => CLKBUS(CKSYS), 
        clocken_a            => '1',
        address_a            => CGROM_BANK & CG_ADDR(10 downto 0),
        data_a               => CGRAM_DI,
        wren_a               => CGRAM_WEN,
        q_a                  => CGRAM_DO,

        clock_b              => IOCTL_CLK,
        clocken_b            => '1',
        address_b            => IOCTL_ADDR(14 DOWNTO 0),
        data_b               => IOCTL_DOUT(7 DOWNTO 0),
        wren_b               => IOCTL_WEN_CGRAM,
        q_b                  => IOCTL_DIN_CGRAM
    );
    
    -- Clock as maximum system speed to minimise transfer time.
    --
    process( RST_n, CLKBUS(CKSYS) )
        variable XFER_CYCLE      : integer range 0 to 6;
        variable XFER_SRC_COL    : integer range 0 to 80;
        variable XFER_SRC_ROW    : integer range 0 to 25;
        variable XFER_DST_COL    : integer range 0 to 80;
        variable XFER_DST_ROW    : integer range 0 to 25;
        variable XFER_DST_SUBROW : integer range 0 to 7;
        variable MAPPED_DATA     : std_logic_vector(23 downto 0);
    begin
        if RST_n='0' then
            XFER_VRAM_ADDR   <= (others => '0');
            XFER_DST_ADDR    <= (others => '0');
            XFER_CGROM_ADDR  <= (others => '0');
            XFER_SRC_COL     := 0;
            XFER_SRC_ROW     := 0;
            XFER_DST_COL     := 0;
            XFER_DST_SUBROW  := 0;
            XFER_DST_ROW     := 0;
            XFER_CYCLE       := 0;
            XFER_WEN         <= '0';

        -- Process on negative edge as the RAM locks a write on positive edge.
        --
        elsif CLKBUS(CKSYS)'event and CLKBUS(CKSYS)='0' then

            -- If we are in the active transfer window, start transfer.
            if V_COUNT >= V_DISPLAY_END and XFER_DST_ROW < MAX_ROW then

                -- Finite state machine to implement read, map and write.
                case (XFER_CYCLE) is
                    -- Setup the source character address.
                    when 0 =>
                        if CONFIG(MZ_KC) = '1' then
                            XFER_VRAM_ADDR   <= std_logic_vector(to_unsigned((XFER_SRC_ROW * MAX_COLUMN) + XFER_SRC_COL, 11));
                        else
                            XFER_VRAM_ADDR   <= std_logic_vector(to_unsigned((XFER_SRC_ROW * MAX_COLUMN) + XFER_SRC_COL, 11)) + (OFFSET_ADDR & "000");
                        end if;
                        XFER_CYCLE      := 1;

                    -- Get the source character and map via the PCG to a slice of the displayed character.
                    -- Recalculate the destination address based on this loops values.
                    when 1 =>
                        -- Setup the PCG address based on the read character.
                        XFER_CGROM_ADDR <= XFER_VRAM_DATA(15) & XFER_VRAM_DATA(7 downto 0) & std_logic_vector(to_unsigned(XFER_DST_SUBROW, 3));

                        -- Destination is recalculated each loop due to subrow changing.
                        -- As the Graphics framebuffer is on a 1-1, we use the same address counter to read out data from GRAM.
                        XFER_DST_ADDR  <= std_logic_vector(to_unsigned((((XFER_DST_ROW * MAX_SUBROW) + XFER_DST_SUBROW) * MAX_COLUMN) + XFER_DST_COL, 14));
                        XFER_CYCLE      := 2;

                    -- An extra clock needed for the CGROM to settle.
                    when 2 =>
                        XFER_CYCLE      := 3;

                    -- Expand and store the slice of the character.
                    when 3 =>
                        --   Graphics mode:- 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
                        --                     5 = GRAM Output Enable  0 = active.
                        --                     4 = VRAM Output Enable, 0 = active.
                        --                   3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
                        --                   1/0 = Read mode  (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
                        if CONFIG(VRAMDISABLE) = '0' and GRAM_MODE(4) = '0' then
                            if CONFIG(COLOUR) = '1' or CONFIG(COLOUR80) = '1' then
                                if CGROM_DATA(7) = '0' then
                                    MAPPED_DATA(7)      := XFER_VRAM_DATA(10);
                                    MAPPED_DATA(15)     := XFER_VRAM_DATA(9);
                                    MAPPED_DATA(23)     := XFER_VRAM_DATA(8);
                                else
                                    MAPPED_DATA(7)      := XFER_VRAM_DATA(14);
                                    MAPPED_DATA(15)     := XFER_VRAM_DATA(13);
                                    MAPPED_DATA(23)     := XFER_VRAM_DATA(12);
                                end if;
                                if CGROM_DATA(6) = '0' then
                                    MAPPED_DATA(6)      := XFER_VRAM_DATA(10);
                                    MAPPED_DATA(14)     := XFER_VRAM_DATA(9);
                                    MAPPED_DATA(22)     := XFER_VRAM_DATA(8);
                                else
                                    MAPPED_DATA(6)      := XFER_VRAM_DATA(14);
                                    MAPPED_DATA(14)     := XFER_VRAM_DATA(13);
                                    MAPPED_DATA(22)     := XFER_VRAM_DATA(12);
                                end if;
                                if CGROM_DATA(5) = '0' then
                                    MAPPED_DATA(5)      := XFER_VRAM_DATA(10);
                                    MAPPED_DATA(13)     := XFER_VRAM_DATA(9);
                                    MAPPED_DATA(21)     := XFER_VRAM_DATA(8);
                                else
                                    MAPPED_DATA(5)      := XFER_VRAM_DATA(14);
                                    MAPPED_DATA(13)     := XFER_VRAM_DATA(13);
                                    MAPPED_DATA(21)     := XFER_VRAM_DATA(12);
                                end if;
                                if CGROM_DATA(4) = '0' then
                                    MAPPED_DATA(4)      := XFER_VRAM_DATA(10);
                                    MAPPED_DATA(12)     := XFER_VRAM_DATA(9);
                                    MAPPED_DATA(20)     := XFER_VRAM_DATA(8);
                                else
                                    MAPPED_DATA(4)      := XFER_VRAM_DATA(14);
                                    MAPPED_DATA(12)     := XFER_VRAM_DATA(13);
                                    MAPPED_DATA(20)     := XFER_VRAM_DATA(12);
                                end if;
                                if CGROM_DATA(3) = '0' then
                                    MAPPED_DATA(3)      := XFER_VRAM_DATA(10);
                                    MAPPED_DATA(11)     := XFER_VRAM_DATA(9);
                                    MAPPED_DATA(19)     := XFER_VRAM_DATA(8);
                                else
                                    MAPPED_DATA(3)      := XFER_VRAM_DATA(14);
                                    MAPPED_DATA(11)     := XFER_VRAM_DATA(13);
                                    MAPPED_DATA(19)     := XFER_VRAM_DATA(12);
                                end if;
                                if CGROM_DATA(2) = '0' then
                                    MAPPED_DATA(2)      := XFER_VRAM_DATA(10);
                                    MAPPED_DATA(10)     := XFER_VRAM_DATA(9);
                                    MAPPED_DATA(18)     := XFER_VRAM_DATA(8);
                                else
                                    MAPPED_DATA(2)      := XFER_VRAM_DATA(14);
                                    MAPPED_DATA(10)     := XFER_VRAM_DATA(13);
                                    MAPPED_DATA(18)     := XFER_VRAM_DATA(12);
                                end if;
                                if CGROM_DATA(1) = '0' then
                                    MAPPED_DATA(1)      := XFER_VRAM_DATA(10);
                                    MAPPED_DATA(9)      := XFER_VRAM_DATA(9);
                                    MAPPED_DATA(17)     := XFER_VRAM_DATA(8);
                                else
                                    MAPPED_DATA(1)      := XFER_VRAM_DATA(14);
                                    MAPPED_DATA(9)      := XFER_VRAM_DATA(13);
                                    MAPPED_DATA(17)     := XFER_VRAM_DATA(12);
                                end if;
                                if CGROM_DATA(0) = '0' then
                                    MAPPED_DATA(0)      := XFER_VRAM_DATA(10);
                                    MAPPED_DATA(8)      := XFER_VRAM_DATA(9);
                                    MAPPED_DATA(16)     := XFER_VRAM_DATA(8);
                                else
                                    MAPPED_DATA(0)      := XFER_VRAM_DATA(14);
                                    MAPPED_DATA(8)      := XFER_VRAM_DATA(13);
                                    MAPPED_DATA(16)     := XFER_VRAM_DATA(12);
                                end if;
                            end if;
                            if CONFIG(NORMAL) = '1' or CONFIG(NORMAL80) = '1' then
                                if CGROM_DATA(7) = '0' then
                                    MAPPED_DATA(7)      := '0';
                                    MAPPED_DATA(15)     := '0';
                                    MAPPED_DATA(23)     := '0';
                                else
                                    MAPPED_DATA(7)      := '1';
                                    if CONFIG(MZ_KC) = '1' then
                                        MAPPED_DATA(15) := '1';
                                        MAPPED_DATA(23) := '1';
                                    end if;
                                end if;
                                if CGROM_DATA(6) = '0' then
                                    MAPPED_DATA(6)      := '0';
                                    MAPPED_DATA(14)     := '0';
                                    MAPPED_DATA(22)     := '0';
                                else
                                    MAPPED_DATA(6)      := '1';
                                    if CONFIG(MZ_KC) = '1' then
                                        MAPPED_DATA(14) := '1';
                                        MAPPED_DATA(22) := '1';
                                    end if;
                                end if;
                                if CGROM_DATA(5) = '0' then
                                    MAPPED_DATA(5)      := '0';
                                    MAPPED_DATA(13)     := '0';
                                    MAPPED_DATA(21)     := '0';
                                else
                                    MAPPED_DATA(5)      := '1';
                                    if CONFIG(MZ_KC) = '1' then
                                        MAPPED_DATA(13) := '1';
                                        MAPPED_DATA(21) := '1';
                                    end if;
                                end if;
                                if CGROM_DATA(4) = '0' then
                                    MAPPED_DATA(4)      := '0';
                                    MAPPED_DATA(12)     := '0';
                                    MAPPED_DATA(20)     := '0';
                                else
                                    MAPPED_DATA(4)      := '1';
                                    if CONFIG(MZ_KC) = '1' then
                                        MAPPED_DATA(12) := '1';
                                        MAPPED_DATA(20) := '1';
                                    end if;
                                end if;
                                if CGROM_DATA(3) = '0' then
                                    MAPPED_DATA(3)      := '0';
                                    MAPPED_DATA(11)     := '0';
                                    MAPPED_DATA(19)     := '0';
                                else
                                    MAPPED_DATA(3)      := '1';
                                    if CONFIG(MZ_KC) = '1' then
                                        MAPPED_DATA(11) := '1';
                                        MAPPED_DATA(19) := '1';
                                    end if;
                                end if;
                                if CGROM_DATA(2) = '0' then
                                    MAPPED_DATA(2)      := '0';
                                    MAPPED_DATA(10)     := '0';
                                    MAPPED_DATA(18)     := '0';
                                else
                                    MAPPED_DATA(2)      := '1';
                                    if CONFIG(MZ_KC) = '1' then
                                        MAPPED_DATA(10) := '1';
                                        MAPPED_DATA(18) := '1';
                                    end if;
                                end if;
                                if CGROM_DATA(1) = '0' then
                                    MAPPED_DATA(1)      := '0';
                                    MAPPED_DATA(9)      := '0';
                                    MAPPED_DATA(17)     := '0';
                                else
                                    MAPPED_DATA(1)      := '1';
                                    if CONFIG(MZ_KC) = '1' then
                                        MAPPED_DATA(9)  := '1';
                                        MAPPED_DATA(17) := '1';
                                    end if;
                                end if;
                                if CGROM_DATA(0) = '0' then
                                    MAPPED_DATA(0)      := '0';
                                    MAPPED_DATA(8)      := '0';
                                    MAPPED_DATA(16)     := '0';
                                else
                                    MAPPED_DATA(0)      := '1';
                                    if CONFIG(MZ_KC) = '1' then
                                        MAPPED_DATA(8)  := '1';
                                        MAPPED_DATA(16) := '1';
                                    end if;
                                end if;
    
                                -- If invert option selected, invert green.
                                --
                                if CONFIG(MZ_A) = '1' and DISPLAY_INVERT = '1' then
                                    MAPPED_DATA(7 downto 0) := not MAPPED_DATA(7 downto 0);
                                end if;
                            end if;
                        else
                            MAPPED_DATA  := (others => '0');
                        end if;

                        -- Graphics ram enabled?
                        --
                        if CONFIG(GRAMDISABLE) = '0' and GRAM_MODE(5) = '0' then
                            -- Merge in the graphics data using defined mode.
                            --
                            case GRAM_MODE(7 downto 6) is
                                when "00" =>
                                    MAPPED_DATA := MAPPED_DATA or   XFER_GRAM_DATA;
                                when "01" =>
                                    MAPPED_DATA := MAPPED_DATA and  XFER_GRAM_DATA;
                                when "10" =>
                                    MAPPED_DATA := MAPPED_DATA nand XFER_GRAM_DATA;
                                when "11" =>
                                    MAPPED_DATA := MAPPED_DATA xor  XFER_GRAM_DATA;
                            end case;
                        end if;

                        -- Assign the video data to the framebuffer input.
                        XFER_MAPPED_DATA <= MAPPED_DATA;
                        XFER_CYCLE := 4;

                    -- Commence write of mapped data.
                    when 4 =>
                        XFER_WEN   <= '1';
                        XFER_CYCLE := 5;

                    -- Complete write and update address.
                    when 5 =>
                        -- Write cycle to framebuffer finished.
                        XFER_WEN   <= '0';
                        XFER_CYCLE := 6;

                    -- Update the counters.
                    when 6 =>
                        -- For each source character, we generate 8 lines in the frame buffer. Thus we increment the
                        -- source character sub-row which addresses a different portion of the Character Generator Rom 
                        -- and store that data into the frame buffer. Once we get to the last sub-row address, 
                        -- increment the source and destination address parameters.
                        if XFER_DST_SUBROW < MAX_SUBROW-1 then
                            XFER_DST_SUBROW  := XFER_DST_SUBROW + 1;
                            XFER_CYCLE       := 1;
                        else
                            -- Increment Source Column/Row
                            if XFER_SRC_COL < MAX_COLUMN - 1 then
                                XFER_SRC_COL := XFER_SRC_COL + 1;
                            else
                                XFER_SRC_COL := 0;
                                XFER_SRC_ROW := XFER_SRC_ROW + 1;
                            end if;
                    
                            -- Increment Destination Column/Row - reset subrow to 0
                            XFER_DST_SUBROW  := 0;
                            if XFER_DST_COL < MAX_COLUMN - 1 then
                                XFER_DST_COL := XFER_DST_COL + 1;
                            else
                                XFER_DST_COL := 0;
                                XFER_DST_ROW := XFER_DST_ROW + 1;
                            end if;
                            XFER_CYCLE       := 0;
                        end if;
                end case;
            end if;

            -- On a new cycle, reset the transfer parameters.
            --
            if V_COUNT = V_DISPLAY_START then
                XFER_VRAM_ADDR   <= (others => '0');
                XFER_DST_ADDR    <= (others => '0');
                XFER_CGROM_ADDR  <= (others => '0');
                XFER_SRC_COL     := 0;
                XFER_SRC_ROW     := 0;
                XFER_DST_COL     := 0;
                XFER_DST_SUBROW  := 0;
                XFER_DST_ROW     := 0;
                XFER_CYCLE       := 0;
                XFER_WEN         <= '0';
            end if;
        end if;
    end process;

    --
    -- Blank & Sync Generation
    --
    process( RST_n, CLKBUS(CKVIDEO), H_LINE_END, V_LINE_END )
        variable configured          : integer range 0 to 2000000;
        variable FB_COL              : integer range 0 to 80;
        variable FB_LINE             : integer range 0 to 200;
    begin
        -- On reset, initialise parameters then set wait timer running.
        --
        if RST_n='0' then

            FB_COL                   := 0;
            FB_LINE                  := 0;
            FB_ADDR                  <= (others => '0');

            -- In order to ensure the correct machine configuration has been latched, wait a period of
            -- time before loading the display configuration.
            --
            configured               := 2000000;

        elsif CLKBUS(CKVIDEO)'event and CLKBUS(CKVIDEO)='1' then

            -- When the time period for allowing the machine configuration to be latched has expired, set the
            -- display configuration according to machine/display model.
            if configured = 1 then

                -- MZ80K/C/1200/A machines have a monochrome 60Hz display, with scan of 512 x 260 for a 320x200 viewable area.
                if CONFIG(NORMAL) = '1' then
                    MAX_COLUMN           <= 40;   -- 40 x 25 character display area.
                    MAX_ROW              <= 25;
                    MAX_SUBROW           <= 8;
                    H_COUNT              <= to_unsigned(H_LINE_END, 11);
                    V_COUNT              <= to_unsigned(0, 11); --(others => '0');
                    H_BLANKi             <= '1';
                    V_BLANKi             <= '0';
                    BLNK                 <= '0';
                    H_SYNC_ni            <= '1';
                    V_SYNC_ni            <= '1';
                    H_DISPLAY_START      <= 0;
                    H_DISPLAY_END        <= 320;
                    H_BLNK_START         <= 320;
                    H_BLNK_END           <= 486;
                    H_SYNC_START         <= 320 + 73;
                    H_SYNC_END           <= 320 + 73 + 45;
                    H_LINE_END           <= 511;
                    V_DISPLAY_START      <= 0;
                    V_DISPLAY_END        <= 200;
                    V_SYNC_START         <= 200 + 19;
                    V_SYNC_END           <= 200 + 19 + 4;
                    V_LINE_END           <= 259;
                    FB_ADDR              <= (others => '0');
                    SR_G_DATA            <= (others => '0');
                    SR_R_DATA            <= (others => '0');
                    SR_B_DATA            <= (others => '0');

                -- MZ80K/C/1200/A machines with an adapted monochrome 60Hz display, with scan of 1024 x 260 for a 640x200 viewable area.
                elsif CONFIG(NORMAL80) = '1' then
                    MAX_COLUMN           <= 80;   -- 80 x 25 character display area.
                    MAX_ROW              <= 25;
                    MAX_SUBROW           <= 8;
                    H_COUNT              <= to_unsigned(H_LINE_END, 11);
                    V_COUNT              <= to_unsigned(0, 11); --(others => '0');
                    H_BLANKi             <= '1';
                    V_BLANKi             <= '0';
                    BLNK                 <= '0';
                    H_SYNC_ni            <= '1';
                    V_SYNC_ni            <= '1';
                    H_DISPLAY_START      <= 0;
                    H_DISPLAY_END        <= 640;
                    H_BLNK_START         <= 640;
                    H_BLNK_END           <= 972;
                    H_SYNC_START         <= 640 + 146;
                    H_SYNC_END           <= 640 + 146 + 90;
                    H_LINE_END           <= 1023;
                    V_DISPLAY_START      <= 0;
                    V_DISPLAY_END        <= 200;
                    V_SYNC_START         <= 200 + 19;
                    V_SYNC_END           <= 200 + 19 + 4;
                    V_LINE_END           <= 259;
                    FB_ADDR              <= (others => '0');
                    SR_G_DATA            <= (others => '0');
                    SR_R_DATA            <= (others => '0');
                    SR_B_DATA            <= (others => '0');

                -- MZ700 has a colour 50Hz display, with scan of 568 x 320 for a 320x200 viewable area.
                elsif CONFIG(COLOUR) = '1' and CONFIG(MZ700) = '1' then
                    MAX_COLUMN           <= 40;   -- 40 x 25 character display area.
                    MAX_ROW              <= 25;
                    MAX_SUBROW           <= 8;
                    H_COUNT              <= to_unsigned(H_LINE_END, 11);
                    V_COUNT              <= to_unsigned(0, 11); --(others => '0');
                    H_BLANKi             <= '1';
                    V_BLANKi             <= '0';
                    BLNK                 <= '0';
                    H_SYNC_ni            <= '1';
                    V_SYNC_ni            <= '1';
                    H_DISPLAY_START      <= 0;
                    H_DISPLAY_END        <= 320;
                    H_BLNK_START         <= 320;
                    H_BLNK_END           <= 548;
                    H_SYNC_START         <= 320 + 80;
                    H_SYNC_END           <= 320 + 80 + 40;
                    H_LINE_END           <= 567;
                    V_DISPLAY_START      <= 0;
                    V_DISPLAY_END        <= 200;
                    V_SYNC_START         <= 200 + 45;
                    V_SYNC_END           <= 200 + 45 + 3;
                    V_LINE_END           <= 311;
                    FB_ADDR              <= (others => '0');
                    SR_G_DATA            <= (others => '0');
                    SR_R_DATA            <= (others => '0');
                    SR_B_DATA            <= (others => '0');

                -- MZ700 has colour 50Hz display, with scan of 1136 x 320 for a 640x200 viewable area.
                elsif CONFIG(COLOUR80) = '1' and CONFIG(MZ700) = '1' then
                    MAX_COLUMN           <= 80;   -- 80 x 25 character display area.
                    MAX_ROW              <= 25;
                    MAX_SUBROW           <= 8;
                    H_COUNT              <= to_unsigned(H_LINE_END, 11);
                    V_COUNT              <= to_unsigned(0, 11); --(others => '0');
                    H_BLANKi             <= '1';
                    V_BLANKi             <= '0';
                    BLNK                 <= '0';
                    H_SYNC_ni            <= '1';
                    V_SYNC_ni            <= '1';
                    H_DISPLAY_START      <= 0;
                    H_DISPLAY_END        <= 640;
                    H_BLNK_START         <= 640;
                    H_BLNK_END           <= 1096;
                    H_SYNC_START         <= 640 + 160;
                    H_SYNC_END           <= 640 + 160 + 80;
                    H_LINE_END           <= 1134;
                    V_DISPLAY_START      <= 0;
                    V_DISPLAY_END        <= 200;
                    V_SYNC_START         <= 200 + 45;
                    V_SYNC_END           <= 200 + 45 + 3;
                    V_LINE_END           <= 311;
                    FB_ADDR              <= (others => '0');
                    SR_G_DATA            <= (others => '0');
                    SR_R_DATA            <= (others => '0');
                    SR_B_DATA            <= (others => '0');

                -- MZ80K/C/1200/A machines with MZ700 style colour @ 60Hz display, with scan of 512 x 260 for a 320x200 viewable area.
                elsif CONFIG(COLOUR) = '1' then
                    MAX_COLUMN           <= 40;   -- 40 x 25 character display area.
                    MAX_ROW              <= 25;
                    MAX_SUBROW           <= 8;
                    H_COUNT              <= to_unsigned(H_LINE_END, 11);
                    V_COUNT              <= to_unsigned(0, 11); --(others => '0');
                    H_BLANKi             <= '1';
                    V_BLANKi             <= '0';
                    BLNK                 <= '0';
                    H_SYNC_ni            <= '1';
                    V_SYNC_ni            <= '1';
                    H_DISPLAY_START      <= 0;
                    H_DISPLAY_END        <= 320;
                    H_BLNK_START         <= 320;
                    H_BLNK_END           <= 486;
                    H_SYNC_START         <= 320 + 73;
                    H_SYNC_END           <= 320 + 73 + 45;
                    H_LINE_END           <= 511;
                    V_DISPLAY_START      <= 0;
                    V_DISPLAY_END        <= 200;
                    V_SYNC_START         <= 200 + 19;
                    V_SYNC_END           <= 200 + 19 + 4;
                    V_LINE_END           <= 259;
                    FB_ADDR              <= (others => '0');
                    SR_G_DATA            <= (others => '0');
                    SR_R_DATA            <= (others => '0');
                    SR_B_DATA            <= (others => '0');

                -- MZ80K/C/1200/A machines with MZ700 style colour @ 60Hz display, with scan of 1024 x 260 for a 640x200 viewable area.
                elsif CONFIG(COLOUR80) = '1' then
                    MAX_COLUMN           <= 80;   -- 80 x 25 character display area.
                    MAX_ROW              <= 25;
                    MAX_SUBROW           <= 8;
                    H_COUNT              <= to_unsigned(H_LINE_END, 11);
                    V_COUNT              <= to_unsigned(0, 11); --(others => '0');
                    H_BLANKi             <= '1';
                    V_BLANKi             <= '0';
                    BLNK                 <= '0';
                    H_SYNC_ni            <= '1';
                    V_SYNC_ni            <= '1';
                    H_DISPLAY_START      <= 0;
                    H_DISPLAY_END        <= 640;
                    H_BLNK_START         <= 640;
                    H_BLNK_END           <= 972;
                    H_SYNC_START         <= 640 + 146;
                    H_SYNC_END           <= 640 + 146 + 90;
                    H_LINE_END           <= 1023;
                    V_DISPLAY_START      <= 0;
                    V_DISPLAY_END        <= 200;
                    V_SYNC_START         <= 200 + 19;
                    V_SYNC_END           <= 200 + 19 + 4;
                    V_LINE_END           <= 259;
                    FB_ADDR              <= (others => '0');
                    SR_G_DATA            <= (others => '0');
                    SR_R_DATA            <= (others => '0');
                    SR_B_DATA            <= (others => '0');
    
                -- Default set for unrecognised machine id.
                --
                else
                    MAX_COLUMN           <= 40;   -- 40 x 25 character display area.
                    MAX_ROW              <= 25;
                    MAX_SUBROW           <= 8;
                    H_COUNT              <= to_unsigned(0, 11);
                    V_COUNT              <= to_unsigned(0, 11); --(others => '0');
                    H_BLANKi             <= '1';
                    V_BLANKi             <= '0';
                    BLNK                 <= '0';
                    H_SYNC_ni            <= '1';
                    V_SYNC_ni            <= '1';
                    H_DISPLAY_START      <= 0;
                    H_DISPLAY_END        <= 320;
                    H_BLNK_START         <= 320;
                    H_BLNK_END           <= 486;
                    H_SYNC_START         <= 320 + 73;
                    H_SYNC_END           <= 320 + 73 + 45;
                    H_LINE_END           <= 511;
                    V_DISPLAY_START      <= 0;
                    V_DISPLAY_END        <= 200;
                    V_SYNC_START         <= 200 + 19;
                    V_SYNC_END           <= 200 + 19 + 4;
                    V_LINE_END           <= 259;
                    FB_ADDR              <= (others => '0');
                    SR_G_DATA            <= (others => '0');
                    SR_R_DATA            <= (others => '0');
                    SR_B_DATA            <= (others => '0');
                end if;
    
                configured := 0;
    
            elsif configured = 0 then
                -- Activate/deactivate signals according to pixel position.
                --
                if H_COUNT =  H_DISPLAY_START then H_BLANKi  <= '0'; end if;
                if H_COUNT =  H_DISPLAY_END   then H_BLANKi  <= '1'; end if;
                if H_COUNT =  H_BLNK_START    then BLNK      <= '1'; end if;
                if H_COUNT =  H_BLNK_END      then BLNK      <= '0'; end if;
                if H_COUNT =  H_SYNC_END      then H_SYNC_ni <= '1'; end if;
                if H_COUNT =  H_SYNC_START    then H_SYNC_ni <= '0'; end if;
                if V_COUNT =  V_DISPLAY_START then V_BLANKi  <= '0'; end if;
                if V_COUNT =  V_DISPLAY_END   then V_BLANKi  <= '1'; end if;
                if V_COUNT =  V_SYNC_START    then V_SYNC_ni <= '0'; end if;
                if V_COUNT =  V_SYNC_END      then V_SYNC_ni <= '1'; end if;

                -- During the active display area, clock out from the frame buffer the pixel information.
                --
                if  H_COUNT < H_DISPLAY_END and V_COUNT < V_DISPLAY_END then

                    -- Data is stored in the frame buffer in bytes, 1 bit per pixel x 8 and 3 colors, thus 1 x 8 x 3 or 24 bit. Read
                    -- out the values into shift registers to be serialised.
                    --
                    if H_COUNT(2 downto 0) = "000" then
                        SR_G_DATA <= DISPLAY_DATA(7 downto 0);
                        SR_R_DATA <= DISPLAY_DATA(15 downto 8);
                        SR_B_DATA <= DISPLAY_DATA(23 downto 16);
                    end if;

                    -- One clock cycle after loading the shift registers, we update the column position so the next memory location
                    -- address can be calculated and presented to RAM so new data is available for next shift register load.
                    --
                    if H_COUNT(2 downto 0) = "001" then
                        if FB_COL < MAX_COLUMN - 1 then
                            FB_COL  := FB_COL + 1;
                        elsif FB_COL = MAX_COLUMN -1 then
                            FB_COL  := 0;
                            FB_LINE := FB_LINE + 1;
                        end if;
                    end if;

                    -- Using the horizontal counter in sets of 8, when 0 we load the shift register from memory and bit 7 is immediately 
                    -- available as a pixel, then all other horizontal counter values, ie. 1 - 7, we shift the bits along to be output 
                    -- as a video signal.
                    --
                    if H_COUNT(2 downto 0) /= "000" then
                        SR_G_DATA <= SR_G_DATA(6 downto 0) & '0';
                        SR_R_DATA <= SR_R_DATA(6 downto 0) & '0';
                        SR_B_DATA <= SR_B_DATA(6 downto 0) & '0';
                    end if;
                end if;

                -- The column and row position is reset to home once we reach the end of the active display.
                --
                if H_COUNT = H_LINE_END and V_COUNT = V_DISPLAY_END then
                    FB_COL  := 0;
                    FB_LINE := 0;
                end if;

                -- Calculate the new frame buffer address, based on Line x Col format.
                --
                FB_ADDR <= std_logic_vector(to_unsigned((FB_LINE * MAX_COLUMN) + FB_COL, 14));

                -- Horizontal/Vertical counters are updated each clock cycle to accurately track pixel/timing.
                --
                if H_COUNT = H_LINE_END then
                    H_COUNT <= (others => '0');
    
                    if V_COUNT = V_LINE_END then
                        V_COUNT <= (others => '0');
                    else
                        V_COUNT <= V_COUNT + 1;
                    end if;
                else
                    H_COUNT <= H_COUNT + 1;
                end if;
            else
                -- Decrement configured timer to implement Reset -> load config delay.
                --
                configured := configured -1;
            end if;
        end if;
    end process;

    --
    -- Control Registers
    -- MZ1200/80A: INVERT display, accessed at E014
    --             SCROLL display, accessed at E200 - E2FF, the address determines the offset.
    --   EA,<val> sets the graphics mode. 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR), 5=GRAM Output Enable, 4 = VRAM Output Enable, 3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect), 1/0=Read mode (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
    --   EB,<val> sets the Red bit mask (1 bit = 1 pixel, 8 pixels per byte).
    --   EC,<val> sets the Green bit mask (1 bit = 1 pixel, 8 pixels per byte).
    --   ED,<val> sets the Blue bit mask (1 bit = 1 pixel, 8 pixels per byte).    
    --
    process( RST_n, CLKBUS(CKCPU) ) begin
        if RST_n='0' then
            DISPLAY_INVERT        <= '0';
            OFFSET_ADDR           <= (others => '0');
            GRAM_MODE             <= "00001100";
            GRAM_RED_WRITER       <= (others => '1');
            GRAM_GREEN_WRITER     <= (others => '1');
            GRAM_BLUE_WRITER      <= (others => '1');

        elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU)='1' then

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

            if CS_IO_EA_n='0' and T80_WR_n='0' then
                GRAM_MODE         <= T80_DI;
            end if;

            if CS_IO_EB_n='0' and T80_WR_n='0' then
                GRAM_RED_WRITER   <= T80_DI;
            end if;

            if CS_IO_EC_n='0' and T80_WR_n='0' then
                GRAM_GREEN_WRITER <= T80_DI;
            end if;

            if CS_IO_ED_n='0' and T80_WR_n='0' then
                GRAM_BLUE_WRITER  <= T80_DI;
            end if;
        end if;
    end process;

    -- Enable Video Wait States - Original design has wait states inserted into the cycle if the CPU accesses the VRAM during display. In the updated design, the VRAM
    -- is copied into a framebuffer during the Vertical Blanking period so no wait states are needed. To keep consistency with the original design (for programs which depend on it),
    -- the wait states can be enabled by configuration.
    --
    process( T80_MREQ_n ) begin
        if T80_MREQ_n'event and T80_MREQ_n='0' then
            BLNK_MEMACCESS <= BLNK;
        end if;
    end process;
    --
    -- Extend wait by 1 cycle
    process( CLKBUS(CKCPU) ) begin
        if CLKBUS(CKCPU)'event and CLKBUS(CKCPU)='1' then
            WAITii_n       <= WAITi_n;
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
    process( RST_n, CLKBUS(CKCPU) ) begin
        if RST_n = '0' then
            CGRAM_ADDR                <= (others=>'0');
            PCG_DATA                      <= (others=>'0');
            CGRAM_WE_n                <= '1';

        elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU)='1' then

            if CS_PCG_n = '0' and T80_WR_n = '0' then
                -- Set the PCG Data to program to RAM. 
                if T80_A(1 downto 0) = "00" then
                    PCG_DATA              <= T80_DI;
                end if;

                -- Set the PCG Address in RAM. 
                if T80_A(1 downto 0) = "01" then
                    CGRAM_ADDR(7 downto 0)  <= T80_DI;
                end if;

                -- Set the PCG Control register.
                if T80_A(1 downto 0) = "10"  then
                    CGRAM_ADDR(11 downto 8) <= (T80_DI(2) and CONFIG(MZ_A)) & '1' & T80_DI(1 downto 0);
                    CGRAM_WE_n              <= not T80_DI(4);
                    CGRAM_SEL              <= T80_DI(5);
                end if;
            end if;
        end if;
    end process;

    --
    -- CPU / RAM signals and selects.
    --
    WAITi_n          <= '0'                                        when CS_D_n = '0' and BLNK_MEMACCESS = '0' and BLNK = '0' and (CONFIG(MZ_A) = '1' or CONFIG(MZ700) = '1')
                        else '1';
    T80_WAIT_n       <= WAITi_n and WAITii_n                       when CONFIG(VRAMWAIT) = '1'
                        else '1';
    T80_MA           <= "00" & T80_A(9 downto 0)                   when CONFIG(MZ_KC) = '1'
                        else
                        T80_A(11 downto 0);
    -- Program Character Generator RAM. E010 - Write cycle (Read cycle = reset memory swap).
    CS_PCG_n         <= '0'                                        when CS_E_n = '0'      and T80_A(10 downto 4) = "0000001"
                        else '1';                                                                   -- D010 -> D01f
    -- Invert display register. E014/E015
    CS_INVERT_n      <= '0'                                        when CS_E_n = '0'      and CONFIG(MZ_A) = '1'        and T80_MA(11 downto 9) = "000" and T80_MA(4 downto 2) = "101"
                        else '1';
    -- Scroll display register. E200 - E2FF
    CS_SCROLL_n      <= '0'                                        when CS_E_n = '0'      and T80_A(11 downto 8)="0010" and CONFIG(MZ_A)='1'
                        else '1';
    -- EA,<val> sets the graphics mode. 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR),
    --                                    5 = GRAM Output Enable, 4 = VRAM Output Enable,
    --                                  3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect),
    --                                  1/0 = Read mode (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
    CS_IO_EA_n       <= '0'                                        when CS_IO_GRAM_n = '0' and T80_A(2 downto 0) = "010"
                        else '1';
    --  EB,<val> sets the Red bit mask (1 bit = 1 pixel, 8 pixels per byte).
    CS_IO_EB_n       <= '0'                                        when CS_IO_GRAM_n = '0' and T80_A(2 downto 0) = "011"
                        else '1';
    --  EC,<val> sets the Green bit mask (1 bit = 1 pixel, 8 pixels per byte).
    CS_IO_EC_n       <= '0'                                        when CS_IO_GRAM_n = '0' and T80_A(2 downto 0) = "100"
                        else '1';
    --  ED,<val> sets the Blue bit mask (1 bit = 1 pixel, 8 pixels per byte).
    CS_IO_ED_n       <= '0'                                        when CS_IO_GRAM_n = '0' and T80_A(2 downto 0) = "101"
                        else '1';

    T80_DO           <= VRAM_VIDEO_DATA                            when T80_RD_n = '0'     and CS_D_n = '0'
                        else
                        GRAM_VIDEO_DATA                            when T80_RD_n = '0'     and CS_G_n = '0'
                        else
                        (others=>'0');

    VRAM_ADDR        <= T80_MA(10 downto 0) & T80_MA(11)           when IOCTL_CS_VRAM_n = '1'
                        else
                        IOCTL_ADDR(10 downto 0) & IOCTL_ADDR(11);
    VRAM_DATA_IN     <= T80_DI                                     when IOCTL_CS_VRAM_n = '1'
                        else
                        IOCTL_DOUT(7 downto 0);
    VWEN             <= '1'                                        when T80_WR_n='0'       and CS_D_n = '0'
                        else '0';
    VRAM_WEN         <= VWEN                                       when IOCTL_CS_VRAM_n = '1'
                        else
                        IOCTL_WEN_VRAM;
    VRAM_VIDEO_DATA  <= VRAM_DATA_OUT                              when IOCTL_CS_VRAM_n = '1'
                        else
                        (others=>'0');
    IOCTL_DIN_VRAM   <= VRAM_DATA_OUT                              when IOCTL_CS_VRAM_n = '0'
                        else
                        (others=>'0');
    VRAM_CLK         <= CLKBUS(CKMEM)                              when IOCTL_CS_VRAM_n = '1'
                        else
                        IOCTL_CLK;

    -- CGROM Data to CG RAM, either ROM -> RAM copy or Z80 provides map.
    --
    CGRAM_DI         <= CGROM_DO                                   when CGRAM_SEL = '1'               -- Data from ROM
                        else
                        PCG_DATA                                   when CGRAM_SEL = '0'               -- Data from PCG
                        else (others=>'0');
    CGRAM_WEN        <= not (CGRAM_WE_n or CS_PCG_n) and not T80_WR_n; 

    --
    -- Font select
    --
    CGROM_DATA       <= CGROM_DO                                   when CONFIG(PCGRAM)='0'
                        else
                        PCG_DATA                                   when CS_PCG_n='0'         and T80_A(1 downto 0)="10" and T80_WR_n='0'
                        else
                        CGRAM_DO                                   when CONFIG(PCGRAM)='1'
                        else (others => '1');
    CG_ADDR          <= CGRAM_ADDR(11 downto 0)                    when CGRAM_WE_n = '0'
                        else XFER_CGROM_ADDR;
    CGROM_BANK       <= "0000"                                     when CONFIG(MZ80K)  = '1'
                        else
                        "0001"                                     when CONFIG(MZ80C)  = '1'
                        else
                        "0010"                                     when CONFIG(MZ1200) = '1'
                        else
                        "0011"                                     when CONFIG(MZ80A)  = '1'
                        else
                        "0100"                                     when CONFIG(MZ700)  = '1'  and XFER_CGROM_ADDR(11) = '0'
                        else
                        "0101"                                     when CONFIG(MZ700)  = '1'  and XFER_CGROM_ADDR(11) = '1'
                        else
                        "0110"                                     when CONFIG(MZ800)  = '1'  and XFER_CGROM_ADDR(11) = '0'
                        else
                        "0111"                                     when CONFIG(MZ800)  = '1'  and XFER_CGROM_ADDR(11) = '1'
                        else
                        "1000"                                     when CONFIG(MZ80B)  = '1'
                        else
                        "1001"                                     when CONFIG(MZ2000) = '1'
                        else
                        "1111";


    -- As the Graphics RAM is an odd size, 16384 x 3 colour planes, it has to be in 3 seperate 16K blocks to avoid wasting memory (or having it synthesized away),
    -- thus there are 3 sets of signals, 1 per colour.
    --
    GRAM_ADDR        <= T80_A(13 downto 0)                         when IOCTL_CS_GRAM_n = '1'
                        else
                        IOCTL_ADDR(13 downto 0);
                        -- direct writes when accessing individual pages.
    GRAM_DATA_IN_R   <= T80_DI                                     when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "00"
                        else
                        T80_DI and GRAM_RED_WRITER                 when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "11"
                        else
                        IOCTL_DOUT(7 downto 0)                     when IOCTL_ADDR(15 downto 14) = "00"
                        else
                        (others=>'0');
                        -- direct writes when accessing individual pages.
    GRAM_DATA_IN_G   <= T80_DI                                     when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "01"
                        else
                        T80_DI and GRAM_GREEN_WRITER               when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "11"
                        else
                        IOCTL_DOUT(7 downto 0)                     when IOCTL_ADDR(15 downto 14) = "01"
                        else
                        (others=>'0');
                        -- direct writes when accessing individual pages.
    GRAM_DATA_IN_B   <= T80_DI                                     when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "10"
                        else
                        T80_DI and GRAM_BLUE_WRITER                when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(3 downto 2) = "11"
                        else
                        IOCTL_DOUT(7 downto 0)                     when IOCTL_ADDR(15 downto 14) = "10"
                        else
                        (others=>'0');
    GWEN_R           <= '1'                                        when T80_WR_n = '0' and CS_G_n = '0' and GRAM_MODE(3 downto 2) = "00"
                        else
                        '1'                                        when T80_WR_n = '0' and CS_G_n = '0' and GRAM_MODE(3 downto 2) = "11"
                        else
                        '0';
    GRAM_WEN_R       <= GWEN_R                                     when IOCTL_CS_GRAM_n = '1'
                        else
                        IOCTL_WEN_GRAM_R;
    GWEN_G           <= '1'                                        when T80_WR_n='0'   and CS_G_n = '0' and GRAM_MODE(3 downto 2) = "01"
                        else
                        '1'                                        when T80_WR_n='0'   and CS_G_n = '0' and GRAM_MODE(3 downto 2) = "11"
                        else
                        '0';
    GRAM_WEN_G       <= GWEN_G                                     when IOCTL_CS_GRAM_n = '1'
                        else
                        IOCTL_WEN_GRAM_G;
    GWEN_B           <= '1'                                        when T80_WR_n='0'   and CS_G_n = '0' and GRAM_MODE(3 downto 2) = "10"
                        else
                        '1'                                        when T80_WR_n='0'   and CS_G_n = '0' and GRAM_MODE(3 downto 2) = "11"
                        else
                        '0';
    GRAM_WEN_B       <= GWEN_B                                     when IOCTL_CS_GRAM_n = '1'
                        else
                        IOCTL_WEN_GRAM_B;

    GRAM_VIDEO_DATA  <= GRAM_DATA_OUT_R                            when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(1 downto 0) = "00"
                        else
                        GRAM_DATA_OUT_G                            when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(1 downto 0) = "01"
                        else
                        GRAM_DATA_OUT_B                            when IOCTL_CS_GRAM_n = '1' and GRAM_MODE(1 downto 0) = "10"
                        else
                        (others=>'0');
    IOCTL_DIN_GRAM   <= GRAM_DATA_OUT_R                            when IOCTL_CS_GRAM_n = '0' and GRAM_MODE(1 downto 0) = "00"
                        else
                        GRAM_DATA_OUT_G                            when IOCTL_CS_GRAM_n = '0' and GRAM_MODE(1 downto 0) = "01"
                        else
                        GRAM_DATA_OUT_B                            when IOCTL_CS_GRAM_n = '0' and GRAM_MODE(1 downto 0) = "10"
                        else
                        (others=>'0');
    GRAM_CLK         <= CLKBUS(CKMEM)                              when IOCTL_CS_GRAM_n = '1'
                        else
                        IOCTL_CLK;

    --
    -- HPS Access - match whole address, additional LE but easier to read.
    --
    IOCTL_WEN_VRAM   <= '1'                                        when IOCTL_CS_VRAM_n = '0' and IOCTL_WR = '1'
                        else '0';
    IOCTL_WEN_GRAM_R <= '1'                                        when IOCTL_CS_GRAM_n = '0' and IOCTL_WR = '1' and IOCTL_ADDR(15 downto 14) = "00"
                        else '0';
    IOCTL_WEN_GRAM_G <= '1'                                        when IOCTL_CS_GRAM_n = '0' and IOCTL_WR = '1' and IOCTL_ADDR(15 downto 14) = "01"
                        else '0';
    IOCTL_WEN_GRAM_B <= '1'                                        when IOCTL_CS_GRAM_n = '0' and IOCTL_WR = '1' and IOCTL_ADDR(15 downto 14) = "10"
                        else '0';
    IOCTL_WEN_CGROM  <= '1'                                        when IOCTL_CS_CGROM_n = '0' and IOCTL_WR = '1'
                        else '0';
    IOCTL_WEN_CGRAM  <= '1'                                        when IOCTL_CS_CGRAM_n = '0' and IOCTL_WR = '1'
                        else '0';
    IOCTL_CS_VRAM_n  <= '0'                                        when IOCTL_ADDR(24 downto 16) = "000000100"
                        else '1';
    IOCTL_CS_GRAM_n  <= '0'                                        when IOCTL_ADDR(24 downto 16) = "000000100"
                        else '1';
    IOCTL_CS_CGROM_n <= '0'                                        when IOCTL_ADDR(24 downto 15) = "0000001110"
                        else '1';
    IOCTL_CS_CGRAM_n <= '0'                                        when IOCTL_ADDR(24 downto 11) = "00000100000000"
                        else '1';
    IOCTL_DIN        <= X"00" & IOCTL_DIN_VRAM                     when IOCTL_CS_VRAM_n = '0'  and IOCTL_RD = '1'
                        else
                        X"00" & IOCTL_DIN_GRAM                     when IOCTL_CS_GRAM_n = '0'  and IOCTL_RD = '1'
                        else
                        X"00" & IOCTL_DIN_CGROM                    when IOCTL_CS_CGROM_n = '0' and IOCTL_RD = '1'
                        else
                        X"00" & IOCTL_DIN_CGRAM                    when IOCTL_CS_CGRAM_n = '0' and IOCTL_RD = '1'
                        else
                        (others=>'0');

    --
    -- Video Output Signals
    --
    VBLANK           <= V_BLANKi;
    HBLANK           <= H_BLANKi;
    VSYNC_n          <= V_SYNC_ni;
    HSYNC_n          <= H_SYNC_ni;
    ROUT             <= SR_R_DATA(7)                               when H_BLANKi='0' or VGATE_n='1'
                        else
                        '0';
    GOUT             <= SR_G_DATA(7)                               when H_BLANKi='0' or VGATE_n='1'
                        else
                        '0';
    BOUT             <= SR_B_DATA(7)                               when H_BLANKi='0' or VGATE_n='1'
                        else
                        '0';
end RTL;
