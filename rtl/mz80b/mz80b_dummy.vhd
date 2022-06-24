---------------------------------------------------------------------------------------------------------
--
-- Name:            mz80b.vhd
-- Created:         August 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series Business Computer:
--                                  Models MZ-80B, MZ-2000
--
--                  This module is the main (top level) container for the Business MZ Computer
--                  Emulation.
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
--                                      |
--                                      |
--                                      |                                         -> cmt.vhd                   (common)
--                                      |                                         -> keymatrix.vhd             (common)
--                                      |                                         -> pll.v                     (common)
--                                      |                                         -> clkgen.vhd                (common)
--                                      |                                         -> T80                       (common)
--                                      |                                         -> i8255                     (common)
--                  sys_top.sv (emu) ->	(emu) sharpmz.vhd (hps_io) -> hps_io.sv
--                                      |                                         -> i8253                     (common)
--                                      |                                         -> dpram.vhd                 (common)
--                                      |                                         -> dprom.vhd                 (common)
--                                      |                                         -> mctrl.vhd                 (common)
--                                      |                                         -> video.vhd                 (common)
--                                      |
--                                      |
--                                      (emu) sharpmz.vhd (mz80b)	->	mz80b.vhd (under development)
--
--
-- Credits:         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         August 2018   - Initial module created.
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

entity mz80b is
    PORT (
          -- Clocks
          CLKBUS             : in  std_logic_vector(CLKBUS_WIDTH);    -- Clock signals created by clkgen module.

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
          CS_ROM_n           : out std_logic;                            -- ROM Select
          CS_RAM_n           : out std_logic;                            -- RAM Select
          CS_VRAM_n          : out std_logic;                            -- VRAM Select
          CS_MEM_G_n         : out std_logic;                            -- Memory mapped Peripherals Select
          CS_GRAM_n          : out std_logic;                            -- GRAM Select
          CS_GRAM_80B_n      : out std_logic;                            -- GRAM Select
          CS_IO_G_n          : out std_logic;                            -- Graphics FB IO Select range
          CS_SWP_MEMBANK_n   : out std_logic;

          -- Audio.
          AUDIO_L            : out std_logic;
          AUDIO_R            : out std_logic;

          -- Different operations modes.
          CONFIG             : in  std_logic_vector(CONFIG_WIDTH);

          -- I/O                                                         -- I/O down to the core.
          KEYB_SCAN          : out std_logic_vector(3 downto 0);         -- Keyboard scan lines out.
          KEYB_DATA          : in  std_logic_vector(7 downto 0);         -- Keyboard scan data in.
          KEYB_STALL         : out std_logic;                            -- Keyboard Stall out.

          -- Cassette magnetic tape signals.
          CMT_BUS_OUT        : in  std_logic_vector(CMT_BUS_OUT_WIDTH);
          CMT_BUS_IN         : out std_logic_vector(CMT_BUS_IN_WIDTH);

          -- Video signals
          VGATE_n            : out std_logic;                            -- Video Gate enable.
          INVERSE            : out std_logic;                            -- Invert video output.
          CHAR80             : out std_logic;                            -- 
          HBLANK             : in  std_logic;                            -- Horizontal Blanking Signal
          VBLANK             : in  std_logic;                            -- Vertical Blanking Signal

          -- HPS Interface
          IOCTL_DOWNLOAD     : in  std_logic;                            -- HPS Downloading to FPGA.
          IOCTL_UPLOAD       : in  std_logic;                            -- HPS Uploading from FPGA.
          IOCTL_CLK          : in  std_logic;                            -- HPS I/O Clock.
          IOCTL_WR           : in  std_logic;                            -- HPS Write Enable to FPGA.
          IOCTL_RD           : in  std_logic;                            -- HPS Read Enable from FPGA.
          IOCTL_ADDR         : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
          IOCTL_DOUT         : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
          IOCTL_DIN          : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.

          -- Debug Status Leds
          DEBUG_STATUS_LEDS  : out std_logic_vector(111 downto 0)        -- 112 leds to display status.
    );
end mz80b;

architecture rtl of mz80b is
begin
          T80_CLKEN          <= '1';
          T80_WAIT_n         <= '1';
          T80_INT_n          <= '1';
          T80_NMI_n          <= '1';
          T80_BUSRQ_n        <= '1';
          T80_DI             <= (others => '0');
          CS_ROM_n           <= '1';
          CS_RAM_n           <= '1';
          CS_VRAM_n          <= '1';
          CS_MEM_G_n         <= '1';
          CS_GRAM_n          <= '1';
          CS_GRAM_80B_n      <= '1';
          CS_IO_G_n          <= '1';
          CS_SWP_MEMBANK_n   <= '1';
          AUDIO_L            <= '1';
          AUDIO_R            <= '1';
          VGATE_n            <= '1';
          INVERSE            <= '0';
          CHAR80             <= '0';
          CMT_BUS_IN(MOTORON)<= '0';
          CMT_BUS_IN(READBIT)<= '0';
          IOCTL_DIN          <= (others => '0');
          DEBUG_STATUS_LEDS  <= (others => '0');
end rtl;
