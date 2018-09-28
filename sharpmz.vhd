---------------------------------------------------------------------------------------------------------
--
-- Name:            sharpmz.vhd
-- Created:         June 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series compatible logic.
--                                                     
--                  This module is the main (top level) container for the Emulation.
--
--                  The design tries to work from top-down, where components which are common 
--                  to the Business and Personal MZ series are at the top (ie. main memory,
--                  ROM, CPU), drilling down two trees, MZ-80B (Business), MZ-80C (Personal)
--                  to the machine specific modules and components. Some components are common
--                  by their nature (ie. 8255 PIO) but these are instantiated within the lower
--                  tree branch as their design use is less generic.
--
--                  The tree is as follows;-
--
--                                      (emu) sharpmz.vhd (mz80c)	->	mz80c.vhd
--                                      |                                         -> mz80c_video.vhd
--                                      |                                         -> pcg.vhd
--                                      |                                         -> cmt.vhd (this may move to common and be shared with mz80b)
--                                      |                                         -> keymatrix.vhd             (common)
--                                      |                                         -> pll.v                     (common)
--                                      |                                         -> clkgen.vhd                (common)
--                                      |                                         -> T80                       (common)
--                                      |                                         -> i8255                     (common)
--                                      |                                         -> i8253                     (common)
--                                      |                                         -> dpram.vhd                 (common)
--                                      |                                         -> dprom.vhd                 (common)
--                                      |                                         -> mctrl.vhd                 (common)
--                  sys_top.sv (emu) ->	(emu) sharpmz.vhd (hps_io) -> hps_io.sv
--                                      |
--                                      (emu) sharpmz.vhd (mz80b)	->	mz80b.vhd (under development)
--
--                  The idea of the design is to keep the emulation as independent of the HPS
--                  as possible (so it works standalone), only needing the HPS to set control registers,
--                  load tape ram and overlay the menu system. This in theory should allow easier
--                  porting if someone wants to port this emulator to another platform or even
--                  target an non-HPS Cyclone chip and instantiate another CPU as the menu control.
--
--                  As the Cyclone V SE on the Terasic DE10 has 5.5Mbits of memory, nearly all the RAM used
--                  by the emulation is on the FPGA. The Floppy Disk Controller may use HPS memory (or the
--                  external SDRAM) depending on wether I decide to cache entire Floppy Disks as per the CMT
--                  unit.
--
-- Credits:         Credit to Nibbles Lab. 2012-2016, as I was originally going to port his mz80c_de0 emulator
--                  based on a Terasic DE0 board. He used external memory and an instantiated NIOSII CPU
--                  to provide a menu/control system. Some snippets of his code, such as the keyboard matrix
--                  have been re-used in this emulation.
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         June 2018 - Initial creation.
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
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;

entity sharpmz is
  port(
        --------------------                Clock Input                         ----------------------------     
        clkmaster             : in     std_logic;                               -- Master Clock(50MHz)
        clksys                : out    std_logic;                               -- System clock.
        clkvid                : out    std_logic;                               -- Pixel base clock of video.
        --------------------                Reset                               ----------------------------
        cold_reset            : in     std_logic;
        warm_reset            : in     std_logic;
        --------------------                        main_leds                    ----------------------------
        main_leds             : out    std_logic_vector(7 downto 0);            -- main_leds Green[7:0]
        --------------------                        PS2                         ----------------------------
        ps2_key               : in     std_logic_vector(10 downto 0);           -- PS2 Key data.
        --------------------                        VGA                         ----------------------------
        vga_hb_o              : out    std_logic;                               -- VGA Horizontal Blank
        vga_vb_o              : out    std_logic;                               -- VGA Vertical Blank
        vga_hs_o              : out    std_logic;                               -- VGA H_SYNC
        vga_vs_o              : out    std_logic;                               -- VGA V_SYNC
        vga_r_o               : out    std_logic_vector(7 downto 0);            -- VGA Red[3:0], [7:4] = 0
        vga_g_o               : out    std_logic_vector(7 downto 0);            -- VGA Green[3:0]
        vga_b_o               : out    std_logic_vector(7 downto 0);            -- VGA Blue[3:0]
        --------------------                        AUDIO                       ------------------------------
        audio_l_o             : out    std_logic;
        audio_r_o             : out    std_logic;
        --------------------                      HPS Interface                 ------------------------------
        ioctl_download        : in     std_logic;                               -- HPS Downloading to FPGA.
        ioctl_upload          : in     std_logic;                               -- HPS Uploading from FPGA.
        ioctl_clk             : in     std_logic;                               -- HPS I/O Clock.
        ioctl_wr              : in     std_logic;                               -- HPS Write Enable to FPGA.
        ioctl_rd              : in     std_logic;                               -- HPS Read Enable from FPGA.
        ioctl_addr            : in     std_logic_vector(24 downto 0);           -- HPS Address in FPGA to write into.
        ioctl_dout            : in     std_logic_vector(15 downto 0);           -- HPS Data to be written into FPGA.
        ioctl_din             : out    std_logic_vector(15 downto 0)            -- HPS Data to be read into HPS.
);
end sharpmz;

architecture rtl of sharpmz is

-- Parent signals brought out onto wires.
--
signal MZ_PS2_KEY            :     std_logic_vector(10 downto 0);
--
-- Master Control signals and configuration.
--
signal MZ_SYSTEM_RESET       :     std_logic;
signal MZ_MEMWR              :     std_logic;
--
-- Signal BUS's
--
signal CLKBUS                :     std_logic_vector(CLKBUS_WIDTH);
signal CONFIG                :     std_logic_vector(CONFIG_WIDTH);
signal DEBUG                 :     std_logic_vector(DEBUG_WIDTH);
signal MZ_CMTBUS             :     std_logic_vector(CMTBUS_WIDTH);
--
-- HPS Control.
--
signal MZ_IOCTL_DOWNLOAD     :     std_logic;
signal MZ_IOCTL_UPLOAD       :     std_logic;
signal MZ_IOCTL_CLK          :     std_logic;
signal MZ_IOCTL_WR           :     std_logic;
signal MZ_IOCTL_RD           :     std_logic;
signal MZ_IOCTL_ADDR         :     std_logic_vector(24 downto 0);
signal MZ_IOCTL_DOUT         :     std_logic_vector(15 downto 0);
signal MZ_IOCTL_DIN_SYSROM   :     std_logic_vector(7 downto 0);
signal MZ_IOCTL_DIN_SYSRAM   :     std_logic_vector(7 downto 0);
signal MZ_IOCTL_DIN_MZ80C    :     std_logic_vector(15 downto 0);
signal MZ_IOCTL_DIN_MZ80B    :     std_logic_vector(15 downto 0);
signal MZ_IOCTL_DIN_MCTRL    :     std_logic_vector(15 downto 0);
signal MZ_IOCTL_WENROM       :     std_logic;
signal MZ_IOCTL_WENRAM       :     std_logic;
signal MZ_IOCTL_RENROM       :     std_logic;
signal MZ_IOCTL_RENRAM       :     std_logic;
--
-- T80 for MZ80C
--
signal MZ80C_RST_n           :     std_logic;
signal MZ80C_MREQ_n          :     std_logic;
signal MZ80C_BUSRQ_n         :     std_logic;
signal MZ80C_IORQ_n          :     std_logic;
signal MZ80C_WR_n            :     std_logic;
signal MZ80C_RD_n            :     std_logic;
signal MZ80C_MWR_n           :     std_logic;
signal MZ80C_MRD_n           :     std_logic;
signal MZ80C_IWR_n           :     std_logic;
signal MZ80C_WAIT_n          :     std_logic;
signal MZ80C_M1_n            :     std_logic;
signal MZ80C_RFSH_n          :     std_logic;
signal MZ80C_A16             :     std_logic_vector(15 downto 0);
signal MZ80C_INT_n           :     std_logic;
signal MZ80C_DO              :     std_logic_vector(7 downto 0);
signal MZ80C_DI              :     std_logic_vector(7 downto 0);
signal MZ80C_BUSAK_n         :     std_logic;
signal MZ80C_CLK             :     std_logic;
signal MZ80C_CLKEN           :     std_logic;
signal MZ80C_NMI_n           :     std_logic;
signal MZ80C_HALT_n          :     std_logic;
--
-- Tape Control 
--
signal MZ80C_CMTBUS          :     std_logic_vector(CMTBUS_WIDTH);
--
-- Video 
--
signal MZ_R                  :     std_logic;
signal MZ_B                  :     std_logic;
signal MZ_G                  :     std_logic;
signal MZ_HSYNC_n            :     std_logic;
signal MZ_VSYNC_n            :     std_logic;
signal MZ_HBLANK             :     std_logic;
signal MZ_VBLANK             :     std_logic;
--
-- Selects for MZ80C.
--
signal MZ80C_CS_ROM_n        :     std_logic;
signal MZ80C_CS_RAM_n        :     std_logic;
--
-- Audio for MZ80C
--
signal MZ80C_AUDIO_L         :     std_logic;
signal MZ80C_AUDIO_R         :     std_logic;
--
-- Video for MZ80C
--
signal MZ80C_R               :     std_logic;
signal MZ80C_G               :     std_logic;
signal MZ80C_B               :     std_logic;
signal MZ80C_HSYNC_n         :     std_logic;
signal MZ80C_VSYNC_n         :     std_logic;
signal MZ80C_HBLANK          :     std_logic;
signal MZ80C_VBLANK          :     std_logic;
--
-- Debug for MZ80C
--
signal MZ80C_DEBUG_LEDS      :     std_logic_vector(111 downto 0);
--
-- T80 for MZ80B
--
signal MZ80B_RST_n           :     std_logic;
signal MZ80B_MREQ_n          :     std_logic;
signal MZ80B_BUSRQ_n         :     std_logic;
signal MZ80B_IORQ_n          :     std_logic;
signal MZ80B_WR_n            :     std_logic;
signal MZ80B_RD_n            :     std_logic;
signal MZ80B_MWR_n           :     std_logic;
signal MZ80B_MRD_n           :     std_logic;
signal MZ80B_IWR_n           :     std_logic;
signal MZ80B_WAIT_n          :     std_logic;
signal MZ80B_M1_n            :     std_logic;
signal MZ80B_RFSH_n          :     std_logic;
signal MZ80B_A16             :     std_logic_vector(15 downto 0);
signal MZ80B_INT_n           :     std_logic;
signal MZ80B_DO              :     std_logic_vector(7 downto 0);
signal MZ80B_DI              :     std_logic_vector(7 downto 0);
signal MZ80B_BUSAK_n         :     std_logic;
signal MZ80B_CLK             :     std_logic;
signal MZ80B_CLKEN           :     std_logic;
signal MZ80B_NMI_n           :     std_logic;
signal MZ80B_HALT_n          :     std_logic;
--
-- Selects for MZ80B.
--
signal MZ80B_CS_ROM_n        :     std_logic;
signal MZ80B_CS_RAM_n        :     std_logic;
--
-- Audio for MZ80B
--
signal MZ80B_AUDIO_L         :     std_logic;
signal MZ80B_AUDIO_R         :     std_logic;
--
-- Tape Control 
--
signal MZ80B_CMTBUS          :     std_logic_vector(CMTBUS_WIDTH);
--
-- Video for MZ80B
--
signal MZ80B_R               :     std_logic;
signal MZ80B_G               :     std_logic;
signal MZ80B_B               :     std_logic;
signal MZ80B_HSYNC_n         :     std_logic;
signal MZ80B_VSYNC_n         :     std_logic;
signal MZ80B_HBLANK          :     std_logic;
signal MZ80B_VBLANK          :     std_logic;
--signal MZ80B_CLKVIDEO        :     std_logic;
--
-- Debug for MZ80B
--
signal MZ80B_DEBUG_LEDS      :     std_logic_vector(111 downto 0);
--
-- T80
--
signal T80_RST_n             :     std_logic;
signal T80_MREQ_n            :     std_logic;
signal T80_BUSRQ_n           :     std_logic;
signal T80_IORQ_n            :     std_logic;
signal T80_WR_n              :     std_logic;
signal T80_RD_n              :     std_logic;
signal T80_MWR_n             :     std_logic;
signal T80_MRD_n             :     std_logic;
signal T80_WAIT_n            :     std_logic;
signal T80_M1_n              :     std_logic;
signal T80_RFSH_n            :     std_logic;
signal T80_A16               :     std_logic_vector(15 downto 0);
signal T80_INT_n             :     std_logic;
signal T80_DO                :     std_logic_vector(7 downto 0);
signal T80_DI                :     std_logic_vector(7 downto 0);
signal T80_BUSAK_n           :     std_logic;
signal T80_CLKEN             :     std_logic;
signal T80_NMI_n             :     std_logic;
signal T80_HALT_n            :     std_logic;
--
-- Decodes, control, misc
--
signal WENSYSRAM             :     std_logic;
signal CSBANKSWITCH_n        :     std_logic;
--
-- Monitor ROM
--
signal DOSYSROM              :     std_logic_vector(7 downto 0);
signal CS_ROM_n              :     std_logic;
signal MROM_BANK             :     std_logic_vector(5 downto 0);
--
-- Static RAM
--
signal DOSYSRAM              :     std_logic_vector(7 downto 0);
signal CS_RAM_n              :     std_logic;
--
-- Debug and internal process signals.
--
signal Q0                    :     std_logic;
signal Q1                    :     std_logic;
signal Q2                    :     std_logic;
signal Q3                    :     std_logic;
signal debug_counter         :     integer range 0 to 13       := 0;
signal flip_counter          :     integer range 0 to 10000000 := 0;
signal block_flip            :     integer range 0 to 800000   := 0;
signal bank_flip             :     integer range 0 to 10000000 := 0;

--
-- Components
--
component clkgen
    Port (
          RST                : in  std_logic;                            -- Reset

          -- Clocks
          CKBASE             : in  std_logic;                            -- Base system main clock.
          CLKBUS             : out std_logic_vector(CLKBUS_WIDTH);       -- Clock signals created by this module.

          -- Different operations modes.
          CONFIG             : in  std_logic_vector(CONFIG_WIDTH);        

          -- Debug modes.
          DEBUG              : in  std_logic_vector(DEBUG_WIDTH) 
    );
end component;

component T80se
    generic (
          Mode               :     integer := 0;                         -- 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
          T2Write            :     integer := 1;                         -- 0 => WR_n active in T3, /=0 => WR_n active in T2
          IOWait             :     integer := 1                          -- 0 => Single cycle I/O, 1 => Std I/O cycle
    );
    Port (
          RESET_n            : in  std_logic;
          CLK_n              : in  std_logic;                            -- NB. Clock is high active.
          CLKEN              : in  std_logic;
          WAIT_n             : in  std_logic;
          INT_n              : in  std_logic;
          NMI_n              : in  std_logic;
          BUSRQ_n            : in  std_logic;
          M1_n               : out std_logic;
          MREQ_n             : out std_logic;
          IORQ_n             : out std_logic;
          RD_n               : out std_logic;
          WR_n               : out std_logic;
          RFSH_n             : out std_logic;
          HALT_n             : out std_logic;
          BUSAK_n            : out std_logic;
          A                  : out std_logic_vector(15 downto 0);
          DI                 : in  std_logic_vector(7 downto 0);
          DO                 : out std_logic_vector(7 downto 0)
    );
end component;

component dpram
    generic (
          init_file          : string;
          widthad_a          : natural;
          width_a            : natural;
          widthad_b          : natural;
          width_b            : natural;
          outdata_reg_a      : string := "UNREGISTERED";
          outdata_reg_b      : string := "UNREGISTERED"
    );
    Port (
          clock_a            : in  std_logic  := '1';
          clocken_a          : in  std_logic  := '1';
          address_a          : in  std_logic_vector (widthad_a-1 downto 0);
          data_a             : in  std_logic_vector (width_a-1 downto 0);
          wren_a             : in  std_logic  := '0';
          q_a                : out std_logic_vector (width_a-1 downto 0);

          clock_b            : in  std_logic;
          clocken_b          : in  std_logic  := '1';
          address_b          : in  std_logic_vector (widthad_b-1 downto 0);
          data_b             : in  std_logic_vector (width_b-1 downto 0);
          wren_b             : in  std_logic  := '0';
          q_b                : out std_logic_vector (width_b-1 downto 0)
      );
end component;

component mctrl
    Port (
          -- Clock signals used by this module.
          CLKBUS             : in  std_logic_vector(CLKBUS_WIDTH);

          -- Reset's
          COLD_RESET         : in  std_logic;
          WARM_RESET         : in  std_logic;
          SYSTEM_RESET       : out std_logic;

          -- HPS Interface
          IOCTL_CLK          : in  std_logic;                            -- HPS I/O Clock
          IOCTL_WR           : in  std_logic;                            -- HPS Write Enable to FPGA.
          IOCTL_RD           : in  std_logic;                            -- HPS Read Enable from FPGA.
          IOCTL_ADDR         : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
          IOCTL_DOUT         : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
          IOCTL_DIN          : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.

          -- Different operations modes.
          CONFIG             : out std_logic_vector(CONFIG_WIDTH);

          -- Cassette magnetic tape signals.
          CMTBUS             : in  std_logic_vector(CMTBUS_WIDTH);

          -- Debug modes.
          DEBUG              : out std_logic_vector(DEBUG_WIDTH) 
    );
end component;

component mz80c
    PORT (
          -- Clocks
          CLKBUS             : in  std_logic_vector(CLKBUS_WIDTH);    -- Clock signals created by this module.

          -- Resets.
          SYSTEM_RESET       : in  std_logic;
          
          -- Z80 CPU
          T80_RST_n          : in  std_logic;
          T80_CLK            : in  std_logic;
          T80_CLKEN          : out std_logic;
          T80_WAIT_n         : out std_logic;
          T80_INT_n          : out std_logic;
          T80_NMI_n          : out std_logic;
          T80_BUSRQ_n        : out std_logic;
          T80_M1_n           : in  std_logic;
          T80_MREQ_n         : in  std_logic;
          T80_IORQ_n         : in  std_logic;
          T80_RD_n           : in  std_logic;
          T80_WR_n           : in  std_logic;
          T80_RFSH_n         : in  std_logic;
          T80_HALT_n         : in  std_logic;
          T80_BUSAK_n        : in  std_logic;
          T80_A16            : in  std_logic_vector(15 downto 0);
          T80_DI             : out std_logic_vector(7 downto 0);
          T80_DO             : in  std_logic_vector(7 downto 0);

          -- Chip selects to common resources.
          CS_ROM_n           : out std_logic;
          CS_RAM_n           : out std_logic;

          -- Audio.
          AUDIO_L            : out std_logic;
          AUDIO_R            : out std_logic;

          -- Video signals.
          R                  : out std_logic;
          G                  : out std_logic;
          B                  : out std_logic;
          HSYNC_n            : out std_logic;
          VSYNC_n            : out std_logic;
          HBLANK             : out std_logic;
          VBLANK             : out std_logic;

          -- Different operations modes.
          CONFIG             : in  std_logic_vector(CONFIG_WIDTH);

          -- Cassette magnetic tape signals.
          CMTBUS             : out std_logic_vector(CMTBUS_WIDTH);

          -- I/O                                                         -- I/O down to the core.
          PS2_KEY            : in  std_logic_vector(10 downto 0);

          -- HPS Interface
          IOCTL_DOWNLOAD     : in  std_logic;                            -- HPS Downloading to FPGA.
          IOCTL_UPLOAD       : in  std_logic;                            -- HPS Uploading from FPGA.
          IOCTL_CLK          : in  std_logic;                            -- HPS I/O Clock
          IOCTL_WR           : in  std_logic;                            -- HPS Write Enable to FPGA.
          IOCTL_RD           : in  std_logic;                            -- HPS Read Enable from FPGA.
          IOCTL_ADDR         : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
          IOCTL_DOUT         : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
          IOCTL_DIN          : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.

          -- Debug Status Leds
          DEBUG_STATUS_LEDS  : out std_logic_vector(111 downto 0)        -- 112 leds to display status.
    );
end component;

component mz80b
    PORT (
          -- Clocks
          CLKBUS             : in  std_logic_vector(CLKBUS_WIDTH);    -- Clock signals created by this module.

          -- Resets.
          SYSTEM_RESET       : in  std_logic;
          
          -- Z80 CPU
          T80_RST_n          : in  std_logic;
          T80_CLK            : in  std_logic;
          T80_CLKEN          : out std_logic;
          T80_WAIT_n         : out std_logic;
          T80_INT_n          : out std_logic;
          T80_NMI_n          : out std_logic;
          T80_BUSRQ_n        : out std_logic;
          T80_M1_n           : in  std_logic;
          T80_MREQ_n         : in  std_logic;
          T80_IORQ_n         : in  std_logic;
          T80_RD_n           : in  std_logic;
          T80_WR_n           : in  std_logic;
          T80_RFSH_n         : in  std_logic;
          T80_HALT_n         : in  std_logic;
          T80_BUSAK_n        : in  std_logic;
          T80_A16            : in  std_logic_vector(15 downto 0);
          T80_DI             : out std_logic_vector(7 downto 0);
          T80_DO             : in  std_logic_vector(7 downto 0);

          -- Chip selects to common resources.
          CS_ROM_n           : out std_logic;
          CS_RAM_n           : out std_logic;

          -- Audio.
          AUDIO_L            : out std_logic;
          AUDIO_R            : out std_logic;

          -- Video signals.
          R                  : out std_logic;
          G                  : out std_logic;
          B                  : out std_logic;
          HSYNC_n            : out std_logic;
          VSYNC_n            : out std_logic;
          HBLANK             : out std_logic;
          VBLANK             : out std_logic;

          -- Different operations modes.
          CONFIG             : in  std_logic_vector(CONFIG_WIDTH);

          -- Cassette magnetic tape signals.
          CMTBUS             : out std_logic_vector(CMTBUS_WIDTH);

          -- I/O                                                         -- I/O down to the core.
          PS2_KEY            : in  std_logic_vector(10 downto 0);

          -- HPS Interface
          IOCTL_DOWNLOAD     : in  std_logic;                            -- HPS Downloading to FPGA.
          IOCTL_UPLOAD       : in  std_logic;                            -- HPS Uploading from FPGA.
          IOCTL_CLK          : in  std_logic;                            -- HPS I/O Clock
          IOCTL_WR           : in  std_logic;                            -- HPS Write Enable to FPGA.
          IOCTL_RD           : in  std_logic;                            -- HPS Read Enable from FPGA.
          IOCTL_ADDR         : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
          IOCTL_DOUT         : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
          IOCTL_DIN          : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.

          -- Debug Status Leds
          DEBUG_STATUS_LEDS  : out std_logic_vector(111 downto 0)        -- 112 leds to display status.
    );
end component;

begin

    --
    -- Instantiation
    --
    CLKGEN0 :  clkgen port map (
            RST              => cold_reset,                              -- Reset

            -- Clocks
            CKBASE           => clkmaster,                               -- Input clocks from top level.
            CLKBUS           => CLKBUS,                                  -- Clock signals created by this module.

            -- Different operations modes.
            CONFIG           => CONFIG,

            -- Debug modes.
            DEBUG            => DEBUG
    );

    CPU0 : T80se
        generic map (
            Mode             => 0,                                       -- 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
            T2Write          => 1,                                       -- 0 => WR_n active in T3, /=0 => WR_n active in T2
            IOWait           => 1                                        -- 0 => Single cycle I/O, 1 => Std I/O cycle
        )
        port map (
            RESET_n          => T80_RST_n,
            CLK_n            => CLKBUS(CKCPU),                           -- T80se uses positive level clock.
            CLKEN            => T80_CLKEN,
            WAIT_n           => T80_WAIT_n,
            INT_n            => T80_INT_n,
            NMI_n            => T80_NMI_n,
            BUSRQ_n          => T80_BUSRQ_n,
            M1_n             => T80_M1_n,
            MREQ_n           => T80_MREQ_n,
            IORQ_n           => T80_IORQ_n,
            RD_n             => T80_RD_n,
            WR_n             => T80_WR_n,
            RFSH_n           => T80_RFSH_n,                              --RFSH_n
            HALT_n           => T80_HALT_n,
            BUSAK_n          => T80_BUSAK_n,
            A                => T80_A16,
            DI               => T80_DI,
            DO               => T80_DO
        );

    -- MZ80 System RAM
    -- 
    SYSRAM : dpram
        generic map (
            init_file        => "./mif/combined_mainmemory.mif",
            widthad_a        => 16,
            width_a          => 8,
            widthad_b        => 16,
            width_b          => 8,
            outdata_reg_a    => "UNREGISTERED",
            outdata_reg_b    => "UNREGISTERED"
        )
        port map (
            clock_a          => CLKBUS(CKMEM), 
            clocken_a        => '1',
            address_a        => T80_A16,
            data_a           => T80_DO,
            wren_a           => WENSYSRAM,                               -- Pulse width controlled according to Master Clock.
            q_a              => DOSYSRAM,

            clock_b          => MZ_IOCTL_CLK,
            clocken_b        => '1',
            address_b        => MZ_IOCTL_ADDR(15 downto 0),
            data_b           => MZ_IOCTL_DOUT(7 downto 0),
            wren_b           => MZ_IOCTL_WENRAM,
            q_b              => MZ_IOCTL_DIN_SYSRAM
        );

    -- MZ Monitor ROM
    -- 0  =         80K MROM 4KBytes -> 0000:0fff 0000 bytes padding
    -- 1  =  80x25  80K MROM 4KBytes -> 1000:1fff 0000 bytes padding
    -- 2  =         80C MROM 4KBytes -> 2000:2fff 0000 bytes padding
    -- 3  =  80x25  80C MROM 4KBytes -> 3000:3fff 0000 bytes padding
    -- 4  =        1200 MROM 4KBytes -> 4000:4fff 0000 bytes padding
    -- 5  =  80x25 1200 MROM 4KBytes -> 5000:5fff 0000 bytes padding
    -- 6  =         80A MROM 4KBytes -> 6000:6fff 0000 bytes padding
    -- 7  =  80x25  80A MROM 4KBytes -> 7000:7fff 0000 bytes padding
    -- 8  =         700 MROM 4KBytes -> 8000:8fff 0000 bytes padding
    -- 9  =  80x25  700 MROM 4KBytes -> 9000:9fff 0000 bytes padding
    -- 10 =         80B MROM 2KBytes -> a000:afff 0800 bytes padding
    -- 11 =  80x25  80B MROM 2KBytes -> b000:bfff 0800 bytes padding
    -- 
    --SYSROM : dprom
    SYSROM : dpram
        generic map (
            init_file        => "./mif/combined_mrom.mif",
            widthad_a        => 17,
            width_a          => 8,
            widthad_b        => 17,
            width_b          => 8,
            outdata_reg_a    => "UNREGISTERED",
            outdata_reg_b    => "UNREGISTERED"
        )
        port map (
            clock_a          => CLKBUS(CKMEM),
            clocken_a        => '1',
            address_a        => MROM_BANK & T80_A16(10 downto 0),
            data_a           => T80_DO,
            wren_a           => '0',                                     -- Block writes from Z80 to ROM.
            q_a              => DOSYSROM,

            clock_b          => MZ_IOCTL_CLK,
            clocken_b        => '1',
            address_b        => MZ_IOCTL_ADDR(16 downto 0),
            data_b           => MZ_IOCTL_DOUT(7 downto 0),
            wren_b           => MZ_IOCTL_WENROM,
            q_b              => MZ_IOCTL_DIN_SYSROM
        );

    CTRL0 : mctrl
        port map (
            -- Clock
            CLKBUS           => CLKBUS,

            -- Reset's
            COLD_RESET       => cold_reset,
            WARM_RESET       => warm_reset,
            SYSTEM_RESET     => MZ_SYSTEM_RESET,

            -- HPS Interface
            IOCTL_CLK        => MZ_IOCTL_CLK,                            -- HPS I/O Clock
            IOCTL_WR         => MZ_IOCTL_WR,
            IOCTL_RD         => MZ_IOCTL_RD,
            IOCTL_ADDR       => MZ_IOCTL_ADDR,
            IOCTL_DOUT       => MZ_IOCTL_DOUT,
            IOCTL_DIN        => MZ_IOCTL_DIN_MCTRL,

            -- Different operations modes.
            CONFIG           => CONFIG,

            -- Cassette magnetic tape signals.
            CMTBUS           => MZ_CMTBUS,

            -- Debug modes.
            DEBUG            => DEBUG
        );

    MZ80HW : mz80c
        port map (
            -- Clocks
            CLKBUS           => CLKBUS,                                  -- Clock signals created by this module.

            -- Resets.
            SYSTEM_RESET     => MZ_SYSTEM_RESET,                         -- Reset generated by system based on Cold/Warm or trigger.

            -- Z80 CPU
            T80_RST_n        => MZ80C_RST_n,
            T80_CLK          => MZ80C_CLK,
            T80_CLKEN        => MZ80C_CLKEN,
            T80_WAIT_n       => MZ80C_WAIT_n,
            T80_INT_n        => MZ80C_INT_n,
            T80_NMI_n        => MZ80C_NMI_n,
            T80_BUSRQ_n      => MZ80C_BUSRQ_n,
            T80_M1_n         => MZ80C_M1_n,
            T80_MREQ_n       => MZ80C_MREQ_n,
            T80_IORQ_n       => MZ80C_IORQ_n,
            T80_RD_n         => MZ80C_RD_n,
            T80_WR_n         => MZ80C_WR_n,
            T80_RFSH_n       => MZ80C_RFSH_n,                            --RFSH_n
            T80_HALT_n       => MZ80C_HALT_n,
            T80_BUSAK_n      => MZ80C_BUSAK_n,
            T80_A16          => MZ80C_A16,
            T80_DI           => MZ80C_DI,
            T80_DO           => MZ80C_DO,

            -- Chip selects to common resources.
            CS_ROM_n         => MZ80C_CS_ROM_n,
            CS_RAM_n         => MZ80C_CS_RAM_n,

            -- Audio.
            AUDIO_L          => MZ80C_AUDIO_L,
            AUDIO_R          => MZ80C_AUDIO_R,

            -- Video signals.
            R                => MZ80C_R,
            G                => MZ80C_G,
            B                => MZ80C_B,
            HSYNC_n          => MZ80C_HSYNC_n,
            VSYNC_n          => MZ80C_VSYNC_n,
            HBLANK           => MZ80C_HBLANK,
            VBLANK           => MZ80C_VBLANK,

            -- Different operations modes.
            CONFIG           => CONFIG,

            -- CMT status signals.
            CMTBUS           => MZ80C_CMTBUS,

            -- I/O                                                       -- I/O down to the core.
            PS2_KEY          => MZ_PS2_KEY,

            -- HPS Interface
            IOCTL_DOWNLOAD   => MZ_IOCTL_DOWNLOAD,                    
            IOCTL_UPLOAD     => MZ_IOCTL_UPLOAD,                    
            IOCTL_CLK        => MZ_IOCTL_CLK,                            -- HPS I/O Clock
            IOCTL_WR         => MZ_IOCTL_WR,
            IOCTL_RD         => MZ_IOCTL_RD,
            IOCTL_ADDR       => MZ_IOCTL_ADDR,
            IOCTL_DOUT       => MZ_IOCTL_DOUT,
            IOCTL_DIN        => MZ_IOCTL_DIN_MZ80C,

            -- Debug Status Leds
            DEBUG_STATUS_LEDS=> MZ80C_DEBUG_LEDS
    );

    MZ80BHW : mz80b
        port map (
            -- Clocks
            CLKBUS           => CLKBUS,                                  -- Clock signals created by this module.

            -- Resets.
            SYSTEM_RESET     => MZ_SYSTEM_RESET,                         -- Reset generated by system based on Cold/Warm or trigger.

            -- Z80 CPU
            T80_RST_n        => MZ80B_RST_n,
            T80_CLK          => MZ80B_CLK,
            T80_CLKEN        => MZ80B_CLKEN,
            T80_WAIT_n       => MZ80B_WAIT_n,
            T80_INT_n        => MZ80B_INT_n,
            T80_NMI_n        => MZ80B_NMI_n,
            T80_BUSRQ_n      => MZ80B_BUSRQ_n,
            T80_M1_n         => MZ80B_M1_n,
            T80_MREQ_n       => MZ80B_MREQ_n,
            T80_IORQ_n       => MZ80B_IORQ_n,
            T80_RD_n         => MZ80B_RD_n,
            T80_WR_n         => MZ80B_WR_n,
            T80_RFSH_n       => MZ80B_RFSH_n,                            --RFSH_n
            T80_HALT_n       => MZ80B_HALT_n,
            T80_BUSAK_n      => MZ80B_BUSAK_n,
            T80_A16          => MZ80B_A16,
            T80_DI           => MZ80B_DI,
            T80_DO           => MZ80B_DO,

            -- Chip selects to common resources.
            CS_ROM_n         => MZ80B_CS_ROM_n,
            CS_RAM_n         => MZ80B_CS_RAM_n,

            -- Audio.
            AUDIO_L          => MZ80B_AUDIO_L,
            AUDIO_R          => MZ80B_AUDIO_R,

            -- Video signals.
            R                => MZ80B_R,
            G                => MZ80B_G,
            B                => MZ80B_B,
            HSYNC_n          => MZ80B_HSYNC_n,
            VSYNC_n          => MZ80B_VSYNC_n,
            HBLANK           => MZ80B_HBLANK,
            VBLANK           => MZ80B_VBLANK,

            -- Different operations modes.
            CONFIG           => CONFIG,

            -- CMT status signals.
            CMTBUS           => MZ80B_CMTBUS,

            -- I/O                                                       -- I/O down to the core.
            PS2_KEY          => MZ_PS2_KEY,

            -- HPS Interface
            IOCTL_DOWNLOAD   => MZ_IOCTL_DOWNLOAD,                    
            IOCTL_UPLOAD     => MZ_IOCTL_UPLOAD,                    
            IOCTL_CLK        => MZ_IOCTL_CLK,                            -- HPS I/O Clock
            IOCTL_WR         => MZ_IOCTL_WR,
            IOCTL_RD         => MZ_IOCTL_RD,
            IOCTL_ADDR       => MZ_IOCTL_ADDR,
            IOCTL_DOUT       => MZ_IOCTL_DOUT,
            IOCTL_DIN        => MZ_IOCTL_DIN_MZ80B,

            -- Debug Status Leds
            DEBUG_STATUS_LEDS=> MZ80B_DEBUG_LEDS
    );

    -- Clocks.
    --
    --clksys                   <= CLKBUS(CKMEM);                           -- System clock.
    clksys                   <= CLKBUS(CKHPS);                           -- HPS clock.
    clkvid                   <= CLKBUS(CKVIDEO);                         -- Video pixel clock output.

    -- Multiplexer -> Signals to enabled hardware.
    --
    MZ80C_RST_n              <= T80_RST_n         when CONFIG(MZ_80C) = '1'   else '1';    -- If not selected, hold in reset.
    MZ80B_RST_n              <= T80_RST_n         when CONFIG(MZ_80B) = '1'   else '1';
    MZ80C_CLK                <= CLKBUS(CKCPU)     when CONFIG(MZ_80C) = '1'   else '1';
    MZ80B_CLK                <= CLKBUS(CKCPU)     when CONFIG(MZ_80B) = '1'   else '1';
    T80_CLKEN                <= MZ80C_CLKEN       when CONFIG(MZ_80C) = '1'   else MZ80B_CLKEN;
    T80_WAIT_n               <= MZ80C_WAIT_n      when CONFIG(MZ_80C) = '1'   else MZ80B_WAIT_n;
    T80_INT_n                <= MZ80C_INT_n       when CONFIG(MZ_80C) = '1'   else MZ80B_INT_n;
    T80_NMI_n                <= MZ80C_NMI_n       when CONFIG(MZ_80C) = '1'   else MZ80B_NMI_n;
    T80_BUSRQ_n              <= MZ80C_BUSRQ_n     when CONFIG(MZ_80C) = '1'   else '1';
    MZ80C_M1_n               <= T80_M1_n          when CONFIG(MZ_80C) = '1'   else '1';
    MZ80B_M1_n               <= T80_M1_n          when CONFIG(MZ_80B) = '1'   else '1';
    MZ80C_MREQ_n             <= T80_MREQ_n        when CONFIG(MZ_80C) = '1'   else '1';
    MZ80B_MREQ_n             <= T80_MREQ_n        when CONFIG(MZ_80B) = '1'   else '1';
    MZ80C_IORQ_n             <= T80_IORQ_n        when CONFIG(MZ_80C) = '1'   else '1';
    MZ80B_IORQ_n             <= T80_IORQ_n        when CONFIG(MZ_80B) = '1'   else '1';
    MZ80C_RD_n               <= T80_RD_n          when CONFIG(MZ_80C) = '1'   else '1';
    MZ80B_RD_n               <= T80_RD_n          when CONFIG(MZ_80B) = '1'   else '1';
    MZ80C_WR_n               <= T80_WR_n          when CONFIG(MZ_80C) = '1'   else '1';
    MZ80B_WR_n               <= T80_WR_n          when CONFIG(MZ_80B) = '1'   else '1';
    MZ80C_RFSH_n             <= T80_RFSH_n        when CONFIG(MZ_80C) = '1'   else '1';
    MZ80B_RFSH_n             <= T80_RFSH_n        when CONFIG(MZ_80B) = '1'   else '1';
    MZ80C_HALT_n             <= T80_HALT_n        when CONFIG(MZ_80C) = '1'   else '1';
    MZ80B_HALT_n             <= T80_HALT_n        when CONFIG(MZ_80B) = '1'   else '1';
    MZ80C_BUSAK_n            <= T80_BUSAK_n       when CONFIG(MZ_80C) = '1'   else '1';
    MZ80B_BUSAK_n            <= T80_BUSAK_n       when CONFIG(MZ_80B) = '1'   else '1';
    MZ80C_A16                <= T80_A16           when CONFIG(MZ_80C) = '1'   else (others=>'1');
    MZ80B_A16                <= T80_A16           when CONFIG(MZ_80B) = '1'   else (others=>'1');
    MZ_CMTBUS                <= MZ80C_CMTBUS      when CONFIG(MZ_80C) = '1'   else MZ80B_CMTBUS;
    T80_DI                   <= DOSYSRAM  when CS_RAM_n ='0' and T80_RD_n = '0'                  -- Read from System RAM
                                else 
                                DOSYSROM  when CS_ROM_n ='0' and T80_RD_n = '0'                  -- Read from System ROM        
                                else 
                                MZ80C_DI  when CONFIG(MZ_80C) = '1'  
                                else
                                MZ80B_DI  when CONFIG(MZ_80B) = '1'
                                else
                                (others=>'1');                                                  -- Float the bus as high when not driven.
    MZ80C_DO                 <= T80_DO            when CONFIG(MZ_80C) = '1'   else (others=>'1');
    MZ80B_DO                 <= T80_DO            when CONFIG(MZ_80B) = '1'   else (others=>'1');
    CS_ROM_n                 <= MZ80C_CS_ROM_n    when CONFIG(MZ_80C) = '1'   else MZ80B_CS_ROM_n;
    CS_RAM_n                 <= MZ80C_CS_RAM_n    when CONFIG(MZ_80C) = '1'   else MZ80B_CS_RAM_n;
    audio_l_o                <= MZ80C_AUDIO_L     when CONFIG(MZ_80C) = '1'   else MZ80B_AUDIO_L;
    audio_r_o                <= MZ80C_AUDIO_R     when CONFIG(MZ_80C) = '1'   else MZ80B_AUDIO_R;
    MZ_R                     <= MZ80C_R           when CONFIG(MZ_80C) = '1'   else MZ80B_R;
    MZ_G                     <= MZ80C_G           when CONFIG(MZ_80C) = '1'   else MZ80B_G;
    MZ_B                     <= MZ80C_B           when CONFIG(MZ_80C) = '1'   else MZ80B_B;
    MZ_HSYNC_n               <= MZ80C_HSYNC_n     when CONFIG(MZ_80C) = '1'   else MZ80B_HSYNC_n;
    MZ_VSYNC_n               <= MZ80C_VSYNC_n     when CONFIG(MZ_80C) = '1'   else MZ80B_VSYNC_n;
    MZ_HBLANK                <= MZ80C_HBLANK      when CONFIG(MZ_80C) = '1'   else MZ80B_HBLANK;
    MZ_VBLANK                <= MZ80C_VBLANK      when CONFIG(MZ_80C) = '1'   else MZ80B_VBLANK;

    -- VGA can be output in original format or via the Scan converter to increase line width.
    --
    vga_hs_o                 <= not MZ_HSYNC_n;
    vga_vs_o                 <= not MZ_VSYNC_n;
    vga_r_o                  <= ('0', '0', MZ_R, MZ_R, MZ_R, MZ_R, MZ_R, MZ_R);
    vga_g_o                  <= ('0', '0', MZ_G, MZ_G, MZ_G, MZ_G, MZ_G, MZ_G);
    vga_b_o                  <= ('0', '0', MZ_B, MZ_B, MZ_B, MZ_B, MZ_B, MZ_B);
    vga_vb_o                 <= MZ_VBLANK;
    vga_hb_o                 <= MZ_HBLANK;

    -- Parent signals onto local wires.
    --
    MZ_PS2_KEY               <= ps2_key;
    MZ_IOCTL_DOWNLOAD        <= ioctl_download;
    MZ_IOCTL_UPLOAD          <= ioctl_upload;
    MZ_IOCTL_CLK             <= ioctl_clk;
    MZ_IOCTL_WR              <= ioctl_wr;
    MZ_IOCTL_RD              <= ioctl_rd;
    MZ_IOCTL_ADDR            <= ioctl_addr;
    MZ_IOCTL_DOUT            <= ioctl_dout;
    ioctl_din                <= X"00" & MZ_IOCTL_DIN_SYSROM when MZ_IOCTL_RENROM = '1'
                                else
                                X"00" & MZ_IOCTL_DIN_SYSRAM when MZ_IOCTL_RENRAM = '1'
                                else
                                MZ_IOCTL_DIN_MCTRL          when IOCTL_ADDR(24 downto 4) = "100000000000000000000"
                                else
                                MZ_IOCTL_DIN_MZ80C          when CONFIG(MZ_80C) = '1'
                                else
                                MZ_IOCTL_DIN_MZ80B          when CONFIG(MZ_80B) = '1'
                                else
                                (others=>'0');

    --
    -- Control Signals
    --
    T80_MRD_n                <= T80_MREQ_n or T80_RD_n;
    T80_MWR_n                <= T80_MREQ_n or T80_WR_n;
    T80_RST_n                <= not MZ_SYSTEM_RESET;
    --
    MZ_MEMWR                 <= not T80_WR_n;
    WENSYSRAM                <= MZ_MEMWR when CS_RAM_n = '0'                                             -- Write enable to System RAM
                                else '0';
    MZ_IOCTL_WENROM          <= '1'   when MZ_IOCTL_ADDR(24 downto 17)="00000000"  and MZ_IOCTL_WR = '1' -- Write enable from HPS to ROM.
                                else '0';
    MZ_IOCTL_WENRAM          <= '1'   when MZ_IOCTL_ADDR(24 downto 16)="000000010" and MZ_IOCTL_WR = '1' -- Write enable from HPS to RAM.
                                else '0';
    MZ_IOCTL_RENROM          <= '1'   when MZ_IOCTL_ADDR(24 downto 17)="00000000"  and MZ_IOCTL_RD = '1' -- Read enable from ROM to HPS.
                                else '0';
    MZ_IOCTL_RENRAM          <= '1'   when MZ_IOCTL_ADDR(24 downto 16)="000000010" and MZ_IOCTL_RD = '1' -- Read enable from RAM to HPS.
                                else '0';

    -- System ROM. 128K split up into chunks which are enabled according to the running machine. The ROM can be accessed by the
    -- HPS via the IOCTL bus and updated as necessary.
    --
    --                                         16    15   14   13   12   11            16     15   14   13   12   11
    -- K   4096    0         4095    0000000    0    0    0    0    0    0    0000FFF    0    0    0    0    0    1
    --     4096    4096      8191    0001000    0    0    0    0    1    0    0001FFF    0    0    0    0    1    1
    --     2048    8192     10239    0002000    0    0    0    1    0    0    00027FF    0    0    0    1    0    0
    --     2048    10240    12287    0002800    0    0    0    1    0    1    0002FFF    0    0    0    1    0    1
    --     2048    12288    14335    0003000    0    0    0    1    1    0    00037FF    0    0    0    1    1    0
    -- C   4096    14336    18431    0003800    0    0    0    1    1    1    00047FF    0    0    1    0    0    0
    --     4096    18432    22527    0004800    0    0    1    0    0    1    00057FF    0    0    1    0    1    0
    --     2048    22528    22527    0005800    0    0    1    0    1    1    0005FFF    0    0    1    0    1    1
    --     2048    22528    24575    0006000    0    0    1    1    0    0    00067FF    0    0    1    1    0    0
    --     2048    24576    26623    0006800    0    0    1    1    0    1    0006FFF    0    0    1    1    0    1
    -- 12  4096    18432    22527    0007000    0    0    1    1    1    0    0007FFF    0    0    1    1    1    1
    --     4096    22528    26623    0008000    0    1    0    0    0    0    0008FFF    0    1    0    0    0    1
    --     2048    26624    28671    0009000    0    1    0    0    1    0    00097FF    0    1    0    0    1    0
    --     2048    28672    30719    0009800    0    1    0    0    1    1    0009FFF    0    1    0    0    1    1
    --     2048    30720    32767    000A000    0    1    0    1    0    0    000A7FF    0    1    0    1    0    0
    -- A   4096    22528    26623    000A800    0    1    0    1    0    1    000B7FF    0    1    0    1    1    0
    --     4096    26624    30719    000B800    0    1    0    1    1    1    000C7FF    0    1    1    0    0    0
    --     2048    30720    32767    000C800    0    1    1    0    0    1    000CFFF    0    1    1    0    0    1
    --     2048    32768    34815    000D000    0    1    1    0    1    0    000D7FF    0    1    1    0    1    0
    --     2048    34816    36863    000D800    0    1    1    0    1    1    000DFFF    0    1    1    0    1    1
    -- 7   4096    26624    30719    000E000    0    1    1    1    0    0    000EFFF    0    1    1    1    0    1
    --     4096    30720    34815    000F000    0    1    1    1    1    0    000FFFF    0    1    1    1    1    1
    --     2048    34816    36863    0010000    1    0    0    0    0    0    00107FF    1    0    0    0    0    0
    --     2048    36864    38911    0010800    1    0    0    0    0    1    0010FFF    1    0    0    0    0    1
    --     2048    38912    40959    0011000    1    0    0    0    1    0    00117FF    1    0    0    0    1    0
    -- 8   4096    30720    34815    0011800    1    0    0    0    1    1    00127FF    1    0    0    1    0    0
    --     4096    34816    38911    0012800    1    0    0    1    0    1    00137FF    1    0    0    1    1    0
    --     2048    38912    40959    0013800    1    0    0    1    1    1    0013FFF    1    0    0    1    1    1
    --     2048    40960    43007    0014000    1    0    1    0    0    0    00147FF    1    0    1    0    0    0
    --     2048    43008    45055    0014800    1    0    1    0    0    1    0014FFF    1    0    1    0    0    1
    -- B   2048    34816    36863    0015000    1    0    1    0    1    0    00157FF    1    0    1    0    1    0
    --     2048    36864    38911    0015800    1    0    1    0    1    1    0015FFF    1    0    1    0    1    1
    --     2048    38912    40959    0016000    1    0    1    1    0    0    00167FF    1    0    1    1    0    0
    --     2048    40960    43007    0016800    1    0    1    1    0    1    0016FFF    1    0    1    1    0    1
    --     2048    43008    45055    0017000    1    0    1    1    1    0    00177FF    1    0    1    1    1    0
    -- 20  2048    36864    38911    0017800    1    0    1    1    1    1    0017FFF    1    0    1    1    1    1
    --     2048    38912    40959    0018000    1    1    0    0    0    0    00187FF    1    1    0    0    0    0
    --     2048    40960    43007    0018800    1    1    0    0    0    1    0018FFF    1    1    0    0    0    1
    --     2048    43008    45055    0019000    1    1    0    0    1    0    00197FF    1    1    0    0    1    0
    --     2048    45056    47103    0019800    1    1    0    0    1    1    0019FFF    1    1    0    0    1    1
    --
    MROM_BANK                <= "00000" & T80_A16(11)     when CONFIG(MZ80K)                 = '1' and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "00001" & T80_A16(11)     when CONFIG(MZ80K)                 = '1' and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "000100"                  when CONFIG(MZ80K)                 = '1' and T80_A16(15 downto 11) = "11101"
                                else
                                "000101"                  when CONFIG(MZ80K)                 = '1' and T80_A16(15 downto 11) = "11110"
                                else
                                "000110"                  when CONFIG(MZ80K)                 = '1' and T80_A16(15 downto 11) = "11111"
                                else
                                "000111"                  when CONFIG(pkgs.mctrl_pkg.MZ80C)  = '1' and T80_A16(11) = '0'                 and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "001000"                  when CONFIG(pkgs.mctrl_pkg.MZ80C)  = '1' and T80_A16(11) = '1'                 and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "001001"                  when CONFIG(pkgs.mctrl_pkg.MZ80C)  = '1' and T80_A16(11) = '0'                 and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "001010"                  when CONFIG(pkgs.mctrl_pkg.MZ80C)  = '1' and T80_A16(11) = '1'                 and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "001011"                  when CONFIG(pkgs.mctrl_pkg.MZ80C)  = '1' and T80_A16(15 downto 11) = "11101"
                                else
                                "001100"                  when CONFIG(pkgs.mctrl_pkg.MZ80C)  = '1' and T80_A16(15 downto 11) = "11110"
                                else
                                "001101"                  when CONFIG(pkgs.mctrl_pkg.MZ80C)  = '1' and T80_A16(15 downto 11) = "11111"
                                else
                                "00111" & T80_A16(11)     when CONFIG(MZ1200)                = '1' and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "01000" & T80_A16(11)     when CONFIG(MZ1200)                = '1' and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "010010"                  when CONFIG(MZ1200)                = '1' and T80_A16(15 downto 11) = "11101"
                                else
                                "010011"                  when CONFIG(MZ1200)                = '1' and T80_A16(15 downto 11) = "11110"
                                else
                                "010100"                  when CONFIG(MZ1200)                = '1' and T80_A16(15 downto 11) = "11111"
                                else
                                "010101"                  when CONFIG(MZ80A)                 = '1' and T80_A16(11) = '0'                 and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "010110"                  when CONFIG(MZ80A)                 = '1' and T80_A16(11) = '1'                 and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "010111"                  when CONFIG(MZ80A)                 = '1' and T80_A16(11) = '0'                 and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "011000"                  when CONFIG(MZ80A)                 = '1' and T80_A16(11) = '1'                 and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "011001"                  when CONFIG(MZ80A)                 = '1' and T80_A16(15 downto 11) = "11101"
                                else
                                "011010"                  when CONFIG(MZ80A)                 = '1' and T80_A16(15 downto 11) = "11110"
                                else
                                "011011"                  when CONFIG(MZ80A)                 = '1' and T80_A16(15 downto 11) = "11111"
                                else
                                "01110" & T80_A16(11)     when CONFIG(MZ700)                 = '1' and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "01111" & T80_A16(11)     when CONFIG(MZ700)                 = '1' and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "100000"                  when CONFIG(MZ700)                 = '1' and T80_A16(15 downto 11) = "11101"
                                else
                                "100001"                  when CONFIG(MZ700)                 = '1' and T80_A16(15 downto 11) = "11110"
                                else
                                "100010"                  when CONFIG(MZ700)                 = '1' and T80_A16(15 downto 11) = "11111"
                                else
                                "100011"                  when CONFIG(MZ800)                 = '1' and T80_A16(11) = '0'                 and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "100100"                  when CONFIG(MZ800)                 = '1' and T80_A16(11) = '1'                 and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "100101"                  when CONFIG(MZ800)                 = '1' and T80_A16(11) = '0'                 and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "100110"                  when CONFIG(MZ800)                 = '1' and T80_A16(11) = '1'                 and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "100111"                  when CONFIG(MZ800)                 = '1' and T80_A16(15 downto 11) = "11101"
                                else
                                "101000"                  when CONFIG(MZ800)                 = '1' and T80_A16(15 downto 11) = "11110"
                                else
                                "101001"                  when CONFIG(MZ800)                 = '1' and T80_A16(15 downto 11) = "11111"
                                else
                                -- MZ80/2000 Series have different rom requirements.
                                "101010"                  when CONFIG(pkgs.mctrl_pkg.MZ80B)  = '1' and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "101011"                  when CONFIG(pkgs.mctrl_pkg.MZ80B)  = '1' and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "101100"                  when CONFIG(pkgs.mctrl_pkg.MZ80B)  = '1' and T80_A16(15 downto 11) = "11101"
                                else
                                "101101"                  when CONFIG(pkgs.mctrl_pkg.MZ80B)  = '1' and T80_A16(15 downto 11) = "11110"
                                else
                                "101110"                  when CONFIG(pkgs.mctrl_pkg.MZ80B)  = '1' and T80_A16(15 downto 11) = "11111"
                                else
                                "101111"                  when CONFIG(pkgs.mctrl_pkg.MZ80B)  = '1' and (CONFIG(NORMAL80) = '0' and CONFIG(COLOUR80) = '0')
                                else
                                "110000"                  when CONFIG(pkgs.mctrl_pkg.MZ80B)  = '1' and (CONFIG(NORMAL80) = '1' or CONFIG(COLOUR80) = '1')
                                else
                                "110001"                  when CONFIG(pkgs.mctrl_pkg.MZ80B)  = '1' and T80_A16(15 downto 11) = "11101"
                                else
                                "110010"                  when CONFIG(pkgs.mctrl_pkg.MZ80B)  = '1' and T80_A16(15 downto 11) = "11110"
                                else
                                "110011"                  when CONFIG(pkgs.mctrl_pkg.MZ80B)  = '1' and T80_A16(15 downto 11) = "11111"
                                else
                                "000000"; -- Default to K ROM.

    -- Debug: Every 5 seconds, change the mb led bank to show a set of values (0 -> 7), bank indicated by 1 second of a bank number.
    --
    --process( cold_reset, CLKBUS(CKLEDS), DEBUG) begin
    process( MZ_SYSTEM_RESET, CLKBUS(CKLEDS), DEBUG) begin
        if MZ_SYSTEM_RESET = '1'  then
            debug_counter <= 0;
            flip_counter  <= 0;

        elsif rising_edge(CLKBUS(CKLEDS)) then

            -- If debug mode is enabled, enable use of sequencer.
            --
            if DEBUG(ENABLED) = '1' then

                -- If LEDS are switched on, run the sample sequencer.
                --
                if DEBUG(LEDS_ON) = '1' then
    
                    -- The changing of the values displayed depends on the sample frequency as this drives the process.
                    case DEBUG(SMPFREQ) is
                        when "0000" =>  -- CMT/CPU frequency - default to 1s/5s @ 2MHz.
                            block_flip <= 250000;
                            bank_flip  <= 10000000;
                        when "0001" =>  -- 1MHz
                            block_flip <= 800000;
                            bank_flip  <= 5000000;
                        when "0010" =>  -- 100KHz
                            block_flip <= 80000;
                            bank_flip  <= 500000;
                        when "0011" =>  -- 10KHz
                            block_flip <= 8000;
                            bank_flip  <= 50000;
                        when "0100" =>  -- 5KHz
                            block_flip <= 4000;
                            bank_flip  <= 25000;
                        when "0101" =>  -- 1KHz
                            block_flip <= 800;
                            bank_flip  <= 5000;
                        when "0110" =>  -- 500Hz
                            block_flip <= 400;
                            bank_flip  <= 2500;
                        when "0111" =>  -- 100Hz
                            block_flip <= 80;
                            bank_flip  <= 500;
                        when "1000" =>  -- 50Hz
                            block_flip <= 40;
                            bank_flip  <= 250;
                        when "1001" =>  -- 10Hz
                            block_flip <= 8;
                            bank_flip  <= 50;
                        when "1010" =>  -- 5Hz
                            block_flip <= 4;
                            bank_flip  <= 25;
                        when "1011" =>  -- 2Hz
                            block_flip <= 1;
                            bank_flip  <= 10;
                        when "1100" =>  -- 1Hz
                            block_flip <= 1;
                            bank_flip  <= 5;
                        when "1101" =>  -- 0.5Hz
                            block_flip <= 1;
                            bank_flip  <= 5;
                        when "1110" =>  -- 0.2Hz
                            block_flip <= 1;
                            bank_flip  <= 2;
                        when "1111" =>  -- 0.1Hz
                            block_flip <= 1;
                            bank_flip  <= 1;
                    end case;
        
                    -- If a subbank has been provided, we dont cycle through the blocks in the bank,
                    -- just fix on the given subbank.
                    --
                    case DEBUG(LEDS_SUBBANK) is
                        when "001" => debug_counter <= 1;
                        when "010" => debug_counter <= 3;
                        when "011" => debug_counter <= 5;
                        when "100" => debug_counter <= 7;
                        when "101" => debug_counter <= 9;
                        when "110" => debug_counter <= 11;
                        when "111" => debug_counter <= 13;
                        when "000" =>
                            flip_counter <= flip_counter + 1;
                            if(flip_counter = block_flip-1 and (debug_counter mod 2) = 0) then
                                flip_counter <= 0;
                                debug_counter <= debug_counter + 1;
                            elsif(flip_counter = bank_flip-1) then
                                flip_counter <= 0;
                                debug_counter <= debug_counter + 1;
                            end if;
                    end case;
        
                    -- Bank 0 : T80 Signals
                    if( DEBUG(LEDS_BANK) = "000") then
                        case debug_counter is
                            when 0 => main_leds(7 downto 0) <= "00010000";                     
                            when 1 => main_leds(7 downto 0) <= T80_A16(7 downto 0);            -- Address Bus A0->A7
                            when 2 => main_leds(7 downto 0) <= "00010001";                     
                            when 3 => main_leds(7 downto 0) <= T80_A16(15 downto 8);           -- Address Bus A8->A15
                            when 4 => main_leds(7 downto 0) <= "00010010";                     
                            when 5 => main_leds(7 downto 0) <= T80_DI(7 downto 0);             -- Data Bus D0->D7
                            when 6 => main_leds(7 downto 0) <= "00010011";                     
                            when 7 => main_leds(0)          <= T80_RST_n;                      -- T80 signals
                                      main_leds(1)          <= T80_WAIT_n;
                                      main_leds(2)          <= T80_INT_n; 
                                      main_leds(3)          <= T80_BUSRQ_n;
                                      main_leds(4)          <= T80_M1_n;
                                      main_leds(5)          <= T80_IORQ_n;
                                      main_leds(6)          <= T80_MRD_n;                              
                                      main_leds(7)          <= T80_MWR_n;
                            when 8 => main_leds(7 downto 0) <= "00010100";                     
                            when 10=> main_leds(7 downto 0) <= "00010101";                     
                            when 12=> main_leds(7 downto 0) <= "00010110";                     
                            when others => main_leds        <= "00010111";
                        end case;
        
                    -- Bank 1 : Video and Keyboard.
                    elsif( DEBUG(LEDS_BANK) = "001") then
                        case debug_counter is
                            when 0 => main_leds(7 downto 0) <= "00110000";                     
                            when 1 => main_leds(0)          <= MZ_VBLANK;                      -- Video signals
                                      main_leds(1)          <= MZ_HBLANK;                      -- Video signals
                                      main_leds(2)          <= '0';
                                      main_leds(3)          <= MZ_HSYNC_n;
                                      main_leds(4)          <= MZ_VSYNC_n;
                                      main_leds(5)          <= MZ_R;
                                      main_leds(6)          <= MZ_G;
                                      main_leds(7)          <= MZ_B;
                            when 2 => main_leds(7 downto 0) <= "00110001";                     
                            when 3 => main_leds(0)          <= MZ_PS2_KEY(0);                  -- PS2 Keyboard Data
                                      main_leds(1)          <= MZ_PS2_KEY(1);
                                      main_leds(2)          <= MZ_PS2_KEY(2);
                                      main_leds(3)          <= MZ_PS2_KEY(3);
                                      main_leds(4)          <= MZ_PS2_KEY(4);
                                      main_leds(5)          <= MZ_PS2_KEY(5);
                                      main_leds(6)          <= MZ_PS2_KEY(6);
                                      main_leds(7)          <= MZ_PS2_KEY(7);
                            when 4 => main_leds(7 downto 0) <= "00110010";                     
                            when 5 => main_leds(0)          <= MZ_PS2_KEY(9);
                                      main_leds(1)          <= MZ_PS2_KEY(10);
                                      main_leds(2)          <= CS_ROM_n;
                                      main_leds(3)          <= CS_RAM_n;
                                      main_leds(4)          <= WENSYSRAM;
                                      main_leds(7 downto 5) <= CONFIG(TURBO);
                            when 6 => main_leds(7 downto 0) <= "00111011";                     
                            when 8 => main_leds(7 downto 0) <= "00111100";                     
                            when 10=> main_leds(7 downto 0) <= "00111101";                     
                            when 12=> main_leds(7 downto 0) <= "00111110";                     
                            when others => main_leds        <= "00110111";
                        end case;
        
                    -- Bank 2: IOCTL
                    elsif( DEBUG(LEDS_BANK) = "010") then
                        case debug_counter is
                            when 0 => main_leds(7 downto 0) <= "01010000";                    
                            when 1 => main_leds             <= MZ_IOCTL_ADDR(23 downto 16);
                            when 2 => main_leds(7 downto 0) <= "01010001";                     
                            when 3 => main_leds             <= MZ_IOCTL_ADDR(15 downto 8);
                            when 4 => main_leds(7 downto 0) <= "01010010";                     
                            when 5 => main_leds             <= MZ_IOCTL_ADDR(7 downto 0);
                            when 6 => main_leds(7 downto 0) <= "01010011";                    
                            when 7 => main_leds(0)          <= MZ_IOCTL_RD;
                                      main_leds(1)          <= MZ_IOCTL_WR;
                                      main_leds(2)          <= MZ_IOCTL_DOWNLOAD;
                                      main_leds(3)          <= MZ_IOCTL_UPLOAD;
                                      main_leds(4)          <= MZ_IOCTL_WENROM;
                                      main_leds(5)          <= MZ_IOCTL_WENRAM;
                                      main_leds(6)          <= MZ_IOCTL_RENROM;
                                      main_leds(7)          <= MZ_IOCTL_RENRAM;
                            when 8 => main_leds(7 downto 0) <= "01010100";                     
                            when 10=> main_leds(7 downto 0) <= "01010101";                     
                            when 12=> main_leds(7 downto 0) <= "01010110";                     
                            when others => main_leds        <= "01010111";
                        end case;
        
                    -- Bank 3 : Config
                    elsif( DEBUG(LEDS_BANK) = "011") then
                        case debug_counter is
                            when 0 => main_leds(7 downto 0) <= "01110000";                    
                            when 1 => main_leds(0)          <= CONFIG(MZ80K);                  -- Mode of operation.
                                      main_leds(1)          <= CONFIG(pkgs.mctrl_pkg.MZ80C);
                                      main_leds(2)          <= CONFIG(MZ1200);
                                      main_leds(3)          <= CONFIG(MZ80A);
                                      main_leds(4)          <= CONFIG(pkgs.mctrl_pkg.MZ80B);
                                      main_leds(5)          <= CONFIG(MZ2000);
                                      main_leds(6)          <= CONFIG(MZ700);
                                      main_leds(7)          <= CONFIG(MZ800);
                            when 2 => main_leds(7 downto 0) <= "01110001";                     
                            when 3 => main_leds(0)          <= CONFIG(MZ_KC);
                                      main_leds(1)          <= CONFIG(MZ_A);
                                      main_leds(2)          <= CONFIG(pkgs.mctrl_pkg.MZ_B);
                                      main_leds(3)          <= CONFIG(MZ_80B);
                                      main_leds(4)          <= CONFIG(MZ_80C);
                                      main_leds(5)          <= CONFIG(NORMAL);
                                      main_leds(6)          <= CONFIG(NORMAL80);
                                      main_leds(7)          <= CONFIG(COLOUR);
                            when 4 => main_leds(7 downto 0) <= "01110010";                     
                            when 5 => main_leds(0)          <= CONFIG(AUDIOSRC);
                                      main_leds(3 downto 1) <= CONFIG(TURBO);
                                      main_leds(6 downto 4) <= CONFIG(FASTTAPE);
                                      main_leds(7)          <= CONFIG(PCGRAM);
                            when 6 => main_leds(7 downto 0) <= "01110011";                    
                            when 7 => main_leds(3 downto 0) <= CONFIG(CPUSPEED);
                                      main_leds(6 downto 4) <= CONFIG(VIDSPEED);
                                      main_leds(7)          <= '0';
                            when 8 => main_leds(7 downto 0) <= "01110100";                     
                            when 9 => main_leds(1 downto 0) <= CONFIG(PERSPEED);
                                      main_leds(3 downto 2) <= CONFIG(RTCSPEED);
                                      main_leds(5 downto 4) <= CONFIG(SNDSPEED);
                                      main_leds(7 downto 6) <= CONFIG(BUTTONS);
                            when 10=> main_leds(7 downto 0) <= "01110101";                     
                            when 11=> main_leds             <= "00000000";
                            when 12=> main_leds(7 downto 0) <= "01110110";                     
                            when 13=> main_leds             <= "00000000";
                            when others => main_leds        <= "01110111";
                        end case;
                        
        
                    -- Bank 4 & 5: MZ80C Debug Leds
                    elsif( DEBUG(LEDS_BANK) = "100") then
                        case debug_counter is
                            when 0 => main_leds(7 downto 0) <= "10010000";                    
                            when 1 => main_leds             <= MZ80C_DEBUG_LEDS(7 downto 0);
                            when 2 => main_leds(7 downto 0) <= "10010001";                     
                            when 3 => main_leds             <= MZ80C_DEBUG_LEDS(15 downto 8);
                            when 4 => main_leds(7 downto 0) <= "10010010";                     
                            when 5 => main_leds             <= MZ80C_DEBUG_LEDS(23 downto 16);
                            when 6 => main_leds(7 downto 0) <= "10010011";                     
                            when 7 => main_leds             <= MZ80C_DEBUG_LEDS(31 downto 24);
                            when 8 => main_leds(7 downto 0) <= "10010100";                     
                            when 9 => main_leds             <= MZ80C_DEBUG_LEDS(39 downto 32);
                            when 10=> main_leds(7 downto 0) <= "10010101";                     
                            when 11=> main_leds             <= MZ80C_DEBUG_LEDS(47 downto 40);
                            when 12=> main_leds(7 downto 0) <= "10010110";                     
                            when 13=> main_leds             <= MZ80C_DEBUG_LEDS(55 downto 48);
                            when others => main_leds        <= "10010111";
                        end case;
                    elsif( DEBUG(LEDS_BANK) = "101") then
                        case debug_counter is
                            when 0 => main_leds(7 downto 0) <= "10110000";                    
                            when 1 => main_leds             <= MZ80C_DEBUG_LEDS(63 downto 56);
                            when 2 => main_leds(7 downto 0) <= "10110001";
                            when 3 => main_leds             <= MZ80C_DEBUG_LEDS(71 downto 64);
                            when 4 => main_leds(7 downto 0) <= "10110010";                     
                            when 5 => main_leds             <= MZ80C_DEBUG_LEDS(79 downto 72);
                            when 6 => main_leds(7 downto 0) <= "10110011";                     
                            when 7 => main_leds             <= MZ80C_DEBUG_LEDS(87 downto 80);
                            when 8 => main_leds(7 downto 0) <= "10110100";                     
                            when 9 => main_leds             <= MZ80C_DEBUG_LEDS(95 downto 88);
                            when 10=> main_leds(7 downto 0) <= "10110101";                     
                            when 11=> main_leds             <= MZ80C_DEBUG_LEDS(103 downto 96);
                            when 12=> main_leds(7 downto 0) <= "10110110";                     
                            when 13=> main_leds             <= MZ80C_DEBUG_LEDS(111 downto 104);
                            when others => main_leds        <= "10110111";
                        end case;
        
                    -- Bank 6 & 7 : MZ80B Debug Leds
                    elsif( DEBUG(LEDS_BANK) = "110") then
                        case debug_counter is
                            when 0 => main_leds(7 downto 0) <= "11010000";                    
                            when 1 => main_leds             <= MZ80B_DEBUG_LEDS(7 downto 0);
                            when 2 => main_leds(7 downto 0) <= "11010001";                     
                            when 3 => main_leds             <= MZ80B_DEBUG_LEDS(15 downto 8);
                            when 4 => main_leds(7 downto 0) <= "11010010";                     
                            when 5 => main_leds             <= MZ80B_DEBUG_LEDS(23 downto 16);
                            when 6 => main_leds(7 downto 0) <= "11010011";                     
                            when 7 => main_leds             <= MZ80B_DEBUG_LEDS(31 downto 24);
                            when 8 => main_leds(7 downto 0) <= "11010100";                     
                            when 9 => main_leds             <= MZ80B_DEBUG_LEDS(39 downto 32);
                            when 10=> main_leds(7 downto 0) <= "11010101";                     
                            when 11=> main_leds             <= MZ80B_DEBUG_LEDS(47 downto 40);
                            when 12=> main_leds(7 downto 0) <= "11010110";                     
                            when 13=> main_leds             <= MZ80B_DEBUG_LEDS(55 downto 48);
                            when others => main_leds        <= "11010111";
                        end case;
                    elsif( DEBUG(LEDS_BANK) = "111") then
                        case debug_counter is
                            when 0 => main_leds(7 downto 0) <= "11110000";                    
                            when 1 => main_leds             <= MZ80B_DEBUG_LEDS(63 downto 56);
                            when 2 => main_leds(7 downto 0) <= "11110001";                     
                            when 3 => main_leds             <= MZ80B_DEBUG_LEDS(71 downto 64);
                            when 4 => main_leds(7 downto 0) <= "11110010";                     
                            when 5 => main_leds             <= MZ80B_DEBUG_LEDS(79 downto 72);
                            when 6 => main_leds(7 downto 0) <= "11110011";                     
                            when 7 => main_leds             <= MZ80B_DEBUG_LEDS(87 downto 80);
                            when 8 => main_leds(7 downto 0) <= "11110100";                     
                            when 9 => main_leds             <= MZ80B_DEBUG_LEDS(95 downto 88);
                            when 10=> main_leds(7 downto 0) <= "11110101";                     
                            when 11=> main_leds             <= MZ80B_DEBUG_LEDS(103 downto 96);
                            when 12=> main_leds(7 downto 0) <= "11110110";                     
                            when 13=> main_leds             <= MZ80B_DEBUG_LEDS(111 downto 104);
                            when others => main_leds        <= "11110111";
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;
end rtl;
