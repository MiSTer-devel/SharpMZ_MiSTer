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
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity mz80b is
    PORT (
          -- Clocks
          CK50M              : in  std_logic;                            -- Master Clock(50MHz)
          CK25M              : in  std_logic;                            -- VGA Clock MZ80B (25MHz)
          CK16M              : in  std_logic;                            -- MZ80B CPU Clock (16MHz)
          CK12M5             : in  std_logic;                            -- VGA Clock MZ80C (12.5MHz)
          CK8M               : in  std_logic;                            -- 15.6kHz Dot Clock(8MHz)
          CK4M               : in  std_logic;                            -- CPU Turbo Clock MZ80C (4MHz)
          CK3M125            : in  std_logic;                            -- Music Base Clock(31.25kHz)
          CK2M               : in  std_logic;                            -- Z80 Original Clock MZ80C
          CLKVIDEO           : out std_logic;                            -- Base clock for video.

          -- Resets.
          COLD_RESET         : in  std_logic;
          WARM_RESET         : in  std_logic;
          
          -- Z80 CPU
          T80_RST_n          : in  std_logic;
          T80_CLK_n          : in  std_logic;
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
          CSROM_n            : out std_logic;
          CSRAM_n            : out std_logic;

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

          -- Type of machine we are emulating.
          MODE_MZ80K         : in  std_logic;
          MODE_MZ80C         : in  std_logic;
          MODE_MZ1200        : in  std_logic;
          MODE_MZ80A         : in  std_logic;
          MODE_MZ80B         : in  std_logic;
          MODE_MZ2000        : in  std_logic;
          MODE_MZ700         : in  std_logic;
          MODE_MZ800         : in  std_logic;
          MODE_MZ_KC         : in  std_logic;
          MODE_MZ_A          : in  std_logic;
          MODE_MZ_B          : in  std_logic;
          MODE_MZ_80C        : in  std_logic;
          MODE_MZ_80B        : in  std_logic;
          -- Type of display to emulate.
          DISPLAY_NORMAL     : in  std_logic;
          DISPLAY_NIDECOM    : in  std_logic;
          DISPLAY_GAL5       : in  std_logic;
          DISPLAY_COLOUR     : in  std_logic;
          -- Buttons to emulate.
          BUTTON_PLAYSW      : in  std_logic;                            -- Tape Play Switch, 1 = Play.
          -- Different operations modes
          CONFIG_TURBO       : in  std_logic;                            -- CPU Speed, 0 = Normal, 1 = Turbo

          -- I/O                                                         -- I/O down to the core.
          PS2_KEY            : in  std_logic_vector(10 downto 0);
          PS2_MOUSE          : in  std_logic_vector(24 downto 0);

          -- HPS Interface
          IOCTL_DOWNLOAD     : in  std_logic;                            -- HPS Downloading to FPGA.
          IOCTL_INDEX        : in  std_logic_vector(7 downto 0);         -- Menu index used to upload file.
          IOCTL_WR           : in  std_logic;                            -- HPS Write Enable to FPGA.
          IOCTL_RD           : in  std_logic;                            -- HPS Read Enable from FPGA.
          IOCTL_ADDR         : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
          IOCTL_DOUT         : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
          IOCTL_DIN          : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.
          IOCTL_INTERRUPT    : out std_logic;                            -- HPS Interrupt.

          -- Debug Status Leds
          DEBUG_STATUS_LEDS  : out std_logic_vector(23 downto 0)         -- 24 leds to display status.
    );
end mz80b;

        -- Switch
        SW                : in std_logic_vector(9 downto 0);    --    Toggle Switch[9:0]
        -- PS2
        PS2_KBDAT    : in std_logic;                        --    PS2 Keyboard Data
        PS2_KBCLK    : in std_logic;                        --    PS2 Keyboard Clock
  );
end mz80b_core;

architecture rtl of mz80b_core is

          DEBUG_STATUS_LEDS  : out std_logic_vector(23 downto 0)         -- 24 leds to display status.
--
-- T80
--
signal MREQ_n                : std_logic;
signal IORQ_n                : std_logic;
signal RD_n                  : std_logic;
--signal MWR                 : std_logic;
--signal MRD                 : std_logic;
signal IWR                   : std_logic;
signal ZWAIT_n               : std_logic;
signal M1                    : std_logic;
signal RFSH_n                : std_logic;
signal ZDTO                  : std_logic_vector(7 downto 0);
signal ZDTI                  : std_logic_vector(7 downto 0);
--signal RAMCS_n             : std_logic;
signal RAMDI                 : std_logic_vector(7 downto 0);
signal BAK_n                 : std_logic;
signal BREQ_n                : std_logic;
--
-- Clocks
--
signal CK4M                  : std_logic;
signal CK16M                 : std_logic;
signal CK25M                 : std_logic;
signal CK3125                : std_logic;
--signal SCLK                : std_logic;
--signal HCLK                : std_logic;
signal CASCADE01             : std_logic;
signal CASCADE12             : std_logic;
--
-- Decodes, misc
--
--signal CSE_n               : std_logic;
--signal CSE2_n              : std_logic;
--signal BUF                 : std_logic_vector(9 downto 0);
signal CSHSK                 : std_logic;
signal MZMODE                : std_logic;
signal DMODE                 : std_logic;
signal KBEN                  : std_logic;
signal KBDT                  : std_logic_vector(7 downto 0);
signal BOOTM                 : std_logic;
signal F_BTN                 : std_logic;
signal IRQ_CMT               : std_logic;
signal C_LEDG                : std_logic_vector(9 downto 0);
signal IRQ_FDD               : std_logic;
signal F_LEDG                : std_logic_vector(9 downto 0);
--
-- Video
--
signal HBLANKi               : std_logic;
signal VBLANKi               : std_logic;
signal HSYNC_ni              : std_logic;
signal VSYNC_ni              : std_logic;
signal Ri                    : std_logic;
signal Gi                    : std_logic;
signal Bi                    : std_logic;
--signal VGATE               : std_logic;
signal CSV_n                 : std_logic;
signal CSG_n                 : std_logic;
signal VRAMDO                : std_logic_vector(7 downto 0);
--
-- PPI
--
signal CSE0_n                : std_logic;
signal PPI_DO                 : std_logic_vector(7 downto 0);
signal PPIPA                 : std_logic_vector(7 downto 0);
signal PPIPB                 : std_logic_vector(7 downto 0);
signal PPIPC                 : std_logic_vector(7 downto 0);
signal BST_n                 : std_logic;
--
-- PIT
--
signal CSE4_n                : std_logic;
signal DOPIT                 : std_logic_vector(7 downto 0);
signal RST8253_n             : std_logic;
--
-- PIO
--
signal CSE8_n                : std_logic;
signal PIO_DO                 : std_logic_vector(7 downto 0);
signal INT_n                 : std_logic;
signal PIOPA                 : std_logic_vector(7 downto 0);
signal PIOPB                 : std_logic_vector(7 downto 0);
--
-- FDD,FDC
--
signal DOFDC                 : std_logic_vector(7 downto 0);
signal DS                    : std_logic_vector(3 downto 0);
signal HS                    : std_logic;
signal MOTOR_n               : std_logic;
signal INDEX_n               : std_logic;
signal TRACK00_n             : std_logic;
signal WPRT_n                : std_logic;
signal STEP_n                : std_logic;
signal DIREC                 : std_logic;
signal FDO                   : std_logic_vector(7 downto 0);
signal FDI                   : std_logic_vector(7 downto 0);
signal WGATE_n               : std_logic;
signal DTCLK                 : std_logic;
--
-- for Debug
--

--
-- Components
--
component i8255
    Port (
        RST                  : in std_logic;
        CLK                  : in std_logic;
        A                    : in std_logic_vector(1 downto 0);
        CS                   : in std_logic;
        RD                   : in std_logic;
        WR                   : in std_logic;
        DI                   : in std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        -- Port
        PA                   : out std_logic_vector(7 downto 0);
        PB                   : in std_logic_vector(7 downto 0);
        PC                   : out std_logic_vector(7 downto 0);
        -- Mode
        MODE_MZ80B           : in  std_logic;
        MODE_MZ2000          : in  std_logic
    );
end component;

component i8253
    Port (
        RST                  : in  std_logic;
        CLK_n                : in  std_logic;
        A                    : in  std_logic_vector(1 downto 0);
        DI                   : in  std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        CS_n                 : in  std_logic;
        WR_n                 : in  std_logic;
        RD_n                 : in  std_logic;
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
end component;

component z8420
    Port (
        -- System
        RST_n                : in std_logic;                             -- Only Power On Reset
        -- Z80 Bus Signals
        CLK                  : in std_logic;
        BASEL                : in std_logic;
        CDSEL                : in std_logic;
        CE                   : in std_logic;
        RD_n                 : in std_logic;
        WR_n                 : in std_logic;
        IORQ_n               : in std_logic;
        M1_n                 : in std_logic;
        DI                   : in std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        IEI                  : in std_logic;
        IEO                  : out std_logic;
        INT_n                : out std_logic;
        -- Port
        A                    : out std_logic_vector(7 downto 0);
        B                    : in std_logic_vector(7 downto 0);
    );
end component;

component keymatrix
    Port (
        RST_n                : in  std_logic;
        CLK                  : in  std_logic;                           -- System Clock
        -- Operating mode of emulator
        MZ_MODE_B            : in  std_logic;
        -- i8255
        PA                   : in  std_logic_vector(3 downto 0);
        PB                   : out std_logic_vector(7 downto 0);
        STALL                : in  std_logic;
        -- PS/2 Keyboard Data
        PS2_KEY              : in  std_logic_vector(10 downto 0);       -- PS2 Key data.
        PS2_MOUSE            : in  std_logic_vector(24 downto 0);       -- PS2 Mouse data.
        -- Type of machine we are emulating.
        MODE_MZ80K           : in  std_logic;
        MODE_MZ80C           : in  std_logic;
        MODE_MZ1200          : in  std_logic;
        MODE_MZ80A           : in  std_logic;
        MODE_MZ80B           : in  std_logic;
        MODE_MZ2000          : in  std_logic;
        MODE_MZ700           : in  std_logic;
        MODE_MZ_KC           : in  std_logic;
        MODE_MZ_A            : in  std_logic;
        -- HPS Interface
        IOCTL_DOWNLOAD       : in  std_logic;                           -- HPS Downloading to FPGA.
        IOCTL_INDEX          : in  std_logic_vector(7 downto 0);        -- Menu index used to upload file.
        IOCTL_WR             : in  std_logic;                           -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                           -- HPS Read Enable to FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);       -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0);       -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0);       -- HPS Data to be read into HPS.
        IOCTL_INTERRUPT      : out std_logic                            -- HPS Interrupt.
    );
end component;

component mz80b_videoout
    Port (
        RST_n                : in  std_logic;                            -- Reset
        BOOTM                : in  std_logic;                            -- BOOT Mode
        -- Type of machine we are emulating.
        MODE_MZ80B           : in  std_logic;
        MODE_MZ2000          : in  std_logic;
        -- Type of display to emulate.
        DISPLAY_NORMAL       : in  std_logic;
        DISPLAY_NIDECOM      : in  std_logic;
        DISPLAY_GAL5         : in  std_logic;
        DISPLAY_COLOUR       : in  std_logic;
        -- Different operations modes.
        CONFIG_PCGRAM        : in  std_logic;                            -- PCG Mode Switch, 0 = CGROM, 1 = CGRAM.
        -- Clocks
        CK16M                : in  std_logic;                            -- 15.6kHz Dot Clock(16MHz)
        T80_CLK_n            : in  std_logic;                            -- Z80 Current Clock
        T80_CLK              : in  std_logic;                            -- Z80 Current Clock Inverted
        -- CPU Signals
        T80_A                : in  std_logic_vector(13 downto 0);        -- CPU Address Bus
        CSV_n                : in  std_logic;                            -- CPU Memory Request(VRAM)
        CSG_n                : in  std_logic;                            -- CPU Memory Request(GRAM)
        T80_RD_n             : in  std_logic;                            -- CPU Read Signal
        T80_WR_n             : in  std_logic;                            -- CPU Write Signal
        T80_MREQ_n           : in  std_logic;                            -- CPU Memory Request
        T80_BUSACK_n         : in  std_logic;                            -- CPU Bus Acknowledge
        T80_WAIT_n           : out std_logic;                            -- CPU Wait Request
        T80_DI               : in  std_logic_vector(7 downto 0);         -- CPU Data Bus(in)
        T80_DO               : out std_logic_vector(7 downto 0);         -- CPU Data Bus(out)
        -- Video Control from outside
        INV                  : in std_logic;                             -- Reverse mode(8255 PA4)
        VGATE                : in std_logic;                             -- Video Output Control(8255 PC0)
        CH80                 : in std_logic;                             -- Text Character Width(Z80PIO A5)
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
        IOCTL_INDEX          : in  std_logic_vector(7 downto 0);         -- Menu index used to upload file.
        IOCTL_WR             : in  std_logic;                            -- HPS Write Enable to FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0)         -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.
        IOCTL_INTERRUPT      : out std_logic                             -- HPS Interrupt.
    );
end component;

component cmt
    Port (
        RST_n                : in  std_logic;                            -- Reset
        CLK                  : in  std_logic;                            -- System Clock
        -- Interrupt
        INTO                 : out std_logic;                            -- Tape action interrupt
        -- Z80 Bus
        ZCLK                 : in  std_logic;
--      ZA8                  : in  std_logic_vector(7 downto 0);
--      ZIWR_n               : in  std_logic;
--      ZDI                  : in  std_logic_vector(7 downto 0);
--      ZDO                  : out std_logic_vector(7 downto 0);
        -- Tape signals
        T_END                : out std_logic;                            -- Sense CMT(Motor on/off)
        OPEN_n               : in  std_logic;                            -- Open
        PLAY_n               : in  std_logic;                            -- Play
        STOP_n               : in  std_logic;                            -- Stop
        FF_n                 : in  std_logic;                            -- Fast Foward
        REW_n                : in  std_logic;                            -- Rewind
        APSS_n               : in  std_logic;                            -- APSS
        FFREW                : in  std_logic;                            -- FF/REW mode
        FMOTOR               : in  std_logic;                            -- FF/REW start
        FLATCH               : in  std_logic;                            -- FF/REW latch
        WREADY               : out std_logic;                            -- Write enable
        TREADY               : out std_logic;                            -- Tape exist
--      EXIN                 : in std_logic;                             -- CMT IN from I/O board
        RDATA                : out std_logic;                            -- to 8255
        -- Status Signal
        SCLK                 : in  std_logic;                            -- Slow Clock(31.25kHz)
        MZMODE               : in  std_logic;                            -- Hardware Mode
        DMODE                : in  std_logic                             -- Display Mode
        -- HPS Interface
        IOCTL_DOWNLOAD       : in  std_logic;                            -- HPS Downloading to FPGA.
        IOCTL_INDEX          : in  std_logic_vector(7 downto 0);         -- Menu index used to upload file.
        IOCTL_WR             : in  std_logic;                            -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                            -- HPS Read Enable from FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.
        IOCTL_INTERRUPT      : out std_logic                             -- HPS Interrupt.
    );
end component;

component mz1e05
    Port (
        -- CPU Signals
        ZRST_n               : in  std_logic;
        ZCLK                 : in  std_logic;
        ZADR                 : in  std_logic_vector(7 downto 0);         -- CPU Address Bus(lower)
        ZRD_n                : in  std_logic;                            -- CPU Read Signal
        ZWR_n                : in  std_logic;                            -- CPU Write Signal
        ZIORQ_n              : in  std_logic;                            -- CPU I/O Request
        ZDI                  : in  std_logic_vector(7 downto 0);         -- CPU Data Bus(in)
        ZDO                  : out std_logic_vector(7 downto 0);         -- CPU Data Bus(out)
        SCLK                 : in  std_logic;                            -- Slow Clock
        -- FD signals
        DS_n                 : out std_logic_vector(4 downto 1);         -- Drive Select
        HS                   : out std_logic;                            -- Head Select
        MOTOR_n              : out std_logic;                            -- Motor On
        INDEX_n              : in  std_logic;                            -- Index Hole Detect
        TRACK00              : in  std_logic;                            -- Track 0
        WPRT_n               : in  std_logic;                            -- Write Protect
        STEP_n               : out std_logic;                            -- Head Step In/Out
        DIREC                : out std_logic;                            -- Head Step Direction
        WGATE_n              : out std_logic;                            -- Write Gate
        DTCLK                : in  std_logic;                            -- Data Clock
        FDI                  : in  std_logic_vector(7 downto 0);         -- Read Data
        FDO                  : out std_logic_vector(7 downto 0)          -- Write Data
    );
end component;

-- PDS : needs buffer ram and an interface to HPS to write into buffer memory.
--component fdunit
--    Port (
--        RST_n                : in  std_logic;                            -- Reset
--        CLK                  : in  std_logic;                            -- System Clock
--        -- Interrupt
--        INTO                 : out std_logic;                            -- Step Pulse interrupt
--        -- FD signals
--        FCLK                 : in  std_logic;
--        DS_n                 : in  std_logic_vector(4 downto 1);         -- Drive Select
--        HS                   : in  std_logic;                            -- Head Select
--        MOTOR_n              : in  std_logic;                            -- Motor On
--        INDEX_n              : out std_logic;                            -- Index Hole Detect
--        TRACK00              : out std_logic;                            -- Track 0
--        WPRT_n               : out std_logic;                            -- Write Protect
--        STEP_n               : in  std_logic;                            -- Head Step In/Out
--        DIREC                : in  std_logic;                            -- Head Step Direction
--        WG_n                 : in  std_logic;                            -- Write Gate
--        DTCLK                : out std_logic;                            -- Data Clock
--        FDI                  : in  std_logic_vector(7 downto 0);         -- Write Data
--        FDO                  : out std_logic_vector(7 downto 0);         -- Read Data
--        -- Buffer RAM I/F
--        BCS_n                : out std_logic;                            -- RAM Request
--        BADR                 : out std_logic_vector(22 downto 0);        -- RAM Address
--        BWR_n                : out std_logic;                            -- RAM Write Signal
--        BDI                  : in  std_logic_vector(7 downto 0);         -- Data Bus Input from RAM
--        BDO                  : out std_logic_vector(7 downto 0)          -- Data Bus Output to RAM
--        -- HPS Interface
--        IOCTL_DOWNLOAD       : in  std_logic;                           -- HPS Downloading to FPGA.
--        IOCTL_INDEX          : in  std_logic_vector(7 downto 0);        -- Menu index used to upload file.
--        IOCTL_WR             : in  std_logic;                           -- HPS Write Enable to FPGA.
--        IOCTL_RD             : in  std_logic;                           -- HPS Read Enable from FPGA.
--        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);       -- HPS Address in FPGA to write into.
--        IOCTL_DOUT           : in  std_logic_vector(15 downto 0);       -- HPS Data to be written into FPGA.
--        IOCTL_DIN            : out std_logic_vector(15 downto 0);       -- HPS Data to be read into HPS.
--        IOCTL_INTERRUPT      : out std_logic                            -- HPS Interrupt.
--    );
--end component;

begin

    --
    -- Instantiation
    --
    CPU0 : T80se
    generic map(
        Mode                 => 0,                                       -- 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
        T2Write              => 1,                                       -- 0 => WR_n active in T3, /=0 => WR_n active in T2
        IOWait               => 1                                        -- 0 => Single cycle I/O, 1 => Std I/O cycle
    )
    port map (
        RESET_n              => T80_RST_n,
        CLK_n                => CK4M,
        CLKEN                => '1',
        WAIT_n               => ZWAIT_n,
        INT_n                => INT_n,
--        INT_n              => '1',
        NMI_n                => '1',
        BUSRQ_n              => BREQ_n,
        M1_n                 => M1,
        MREQ_n               => MREQ_n,
        IORQ_n               => IORQ_n,
        RD_n                 => RD_n,
        WR_n                 => T80_WR_n,
        RFSH_n               => RFSH_n,
        HALT_n               => open,
        BUSAK_n              => BAK_n,
        A                    => T80_A16,
        DI                   => ZDTI,
        DO                   => ZDTO
    );

    PPI0 : i8255 port map (
        RST                  => T80_RST,
        CLK                  => CK4M,
        A                    => T80_A16(1 downto 0),
        CS                   => CSE0_n,
        RD                   => RD_n,
        WR                   => T80_WR_n,
        DI                   => ZDTO,
        DO                   => PPI_DO,
        -- Port
        PA                   => PPIPA,
        PB                   => PPIPB,
        PC                   => PPIPC,
        -- Mode
        MODE_MZ80B           => MODE_MZ80B,
        MODE_MZ2000          => MODE_MZ2000
    );
    PPIPB(7)<=PIOPB(7);
--    WDATA<=PPIPC(7);
--    REC_n<=PPIPC(6);
--    WRIT_n<=PPIPC(6);
--    KINH<=PPIPC(5);
--    L_FR<=PPIPC(5);
    BST_n<=PPIPC(3);
--    NST<=PPIPC(1);

    CMT0 : cmt port map (
        -- Interrupt
        INTO                 => IRQ_CMT,                                 -- Tape action interrupt
        -- Z80 Bus
        ZCLK                 => CK4M,
        -- Tape signals
        T_END                => PPIPB(3),                                -- Sense CMT(Motor on/off)
        OPEN_n               => PPIPC(4),                                -- Open
        PLAY_n               => PPIPA(2),                                -- Play
        STOP_n               => PPIPA(3),                                -- Stop
        FF_n                 => PPIPA(1),                                -- Fast Foward
        REW_n                => PPIPA(0),                                -- Rewind
        APSS_n               => PPIPA(7),                                -- APSS
        FFREW                => PPIPA(1),                                -- FF/REW mode
        FMOTOR               => PPIPA(0),                                -- FF/REW start
        FLATCH               => PPIPC(5),                                -- FF/REW latch
        WREADY               => PPIPB(4),                                -- Write enable
        TREADY               => PPIPB(5),                                -- Tape exist
        RDATA                => PPIPB(6),                                -- to 8255
        -- Status Signal
        SCLK                 => CK3125,                                  -- Slow Clock(31.25kHz)
        MZMODE               => MZMODE,
        DMODE                => DMODE
    );

    PIT0 : i8253 port map (
        RST                  => T80_RST,
        CLK                  => CK4M,
        A                    => T80_A16(1 downto 0),
        DI                   => ZDTO,
        DO                   => DOPIT,
        CS                   => CSE4_n,
        WR                   => T80_WR_n,
        RD                   => RD_n,
        CLK0                 => CK3125,
        GATE0                => RST8253_n,
        OUT0                 => CASCADE01,
        CLK1                 => CASCADE01,
        GATE1                => RST8253_n,
        OUT1                 => CASCADE12,
        CLK2                 => CASCADE12,
        GATE2                => '1',
        OUT2                 => open
    );

    PIO0 : z8420 port map (
        -- System
        RST_n                => T80_RST_n,                                    -- Only Power On Reset
        -- Z80 Bus Signals
        CLK                  => CK4M,
        BASEL                => T80_A16(1),
        CDSEL                => T80_A16(0),
        CE                   => CSE8_n,
        RD_n                 => RD_n,
        WR_n                 => T80_WR_n,
        IORQ_n               => IORQ_n,
        M1_n                 => M1,
        DI                   => ZDTO,
        DO                   => PIO_DO,
        IEI                  => '1',
        IEO                  => open,
--        INT_n              => open,
        INT_n                => INT_n,
        -- Port
        A                    => PIOPA,
        B                    => PIOPB,
    );

    KEYS : keymatrix
        port map (
            RST_n            => T80_RST_n,
            CLK              => T80_CLK,                                 -- System clock.
            -- Operating mode of emulator
            MZ_MODE_B        => MODE_MZ_B,
            -- i8255
            PA               => i8255_PA_O(3 downto 0),
            PB               => i8255_PB_I,
            STALL            => i8255_PA_O(4),
            -- PS/2 Keyboard Data
            PS2_KEY          => PS2_KEY,                                 -- PS2 Key data.
            PS2_MOUSE        => PS2_MOUSE,                               -- PS2 Mouse data.
            -- Type of machine we are emulating.
            MODE_MZ80K       => MODE_MZ80K,
            MODE_MZ80C       => MODE_MZ80C,
            MODE_MZ1200      => MODE_MZ1200,
            MODE_MZ80A       => MODE_MZ80A,
            MODE_MZ80B       => MODE_MZ80B,
            MODE_MZ2000      => MODE_MZ2000,
            MODE_MZ700       => MODE_MZ700,
            MODE_MZ_KC       => MODE_MZ_KC,
            MODE_MZ_A        => MODE_MZ_A,
            -- HPS Interface
            IOCTL_DOWNLOAD   => IOCTL_DOWNLOAD,                          -- HPS Downloading to FPGA.
            IOCTL_INDEX      => IOCTL_INDEX,                             -- Menu index used to upload file.
            IOCTL_WR         => IOCTL_WR,                                -- HPS Write Enable to FPGA.
            IOCTL_RD         => IOCTL_RD,                                -- HPS Read Enable from FPGA.
            IOCTL_ADDR       => IOCTL_ADDR,                              -- HPS Address in FPGA to write into.
            IOCTL_DOUT       => IOCTL_DOUT,                              -- HPS Data to be written into FPGA.
            IOCTL_DIN        => IOCTL_DIN_KEY,                           -- HPS Data to be sent to HPS.
            IOCTL_INTERRUPT  => IOCTL_INTERRUPT                          -- Interrupt to HPS.
        );

    VIDEO0 : mz80b_videoout Port map (
        RST                  => T80_RST_n                                -- Reset
        MZMODE               => MZMODE,                                  -- Hardware Mode
        DMODE                => DMODE,                                   -- Display Mode
        -- Clocks
        CK50M                => CK50M,                                   -- Master Clock(50MHz)
        CK25M                => CK25M,                                   -- VGA Clock(25MHz)
        CK16M                => CK16M,                                   -- 15.6kHz Dot Clock(16MHz)
        CK4M                 => CK4M,                                    -- CPU/CLOCK Clock(4MHz)
        CK3125               => CK3125,                                  -- Time Base Clock(31.25kHz)
        -- CPU Signals
        A                    => T80_A16(13 downto 0),                    -- CPU Address Bus
        CSV_n                => CSV_n,                                   -- CPU Memory Request(VRAM)
        CSG_n                => CSG_n,                                   -- CPU Memory Request(GRAM)
        RD_n                 => RD_n,                                    -- CPU Read Signal
        WR_n                 => T80_WR_n,                                -- CPU Write Signal
        MREQ_n               => MREQ_n,                                  -- CPU Memory Request
        IORQ_n               => IORQ_n,                                  -- CPU I/O Request
        WAIT_n               => ZWAIT_n,                                 -- CPU Wait Request
        DI                   => ZDTO,                                    -- CPU Data Bus(in)
        DO                   => VRAMDO,                                  -- CPU Data Bus(out)
        -- Video Control from outside
        INV                  => PPIPA(4),                                -- Reverse mode(8255 PA4)
        VGATE                => PPIPC(0),                                -- Video Output Control
        CH80                 => PIOPA(5),
        -- Video Signals
        VGATE_n              => VGATE_n,                                 -- Video Output Control
        HBLANK               => HBLANKi,                                 -- Horizontal Blanking
        VBLANK               => VBLANKi,                                 -- Vertical Blanking
        HSYNC_n              => HSYNC_ni,                                -- Horizontal Sync
        VSYNC_n              => VSYNC_ni,                                -- Vertical Sync
        ROUT                 => Ri,                                      -- Red Output
        GOUT                 => Gi,                                      -- Green Output
        BOUT                 => Bi,                                      -- Blue Output
        HBLANK               => HBLANKi,                                 -- Horizontal Blanking
        VBLANK               => VBLANKi,                                 -- Vertical Blanking
        -- Control Signal
        BOOTM                => BOOTM,                                   -- BOOT Mode
        BACK                 => BAK_n                                    -- Z80 Bus Acknowlegde
    );

PDS :- Need BOOTM
    
    FDIF0 : mz1e05 Port map(
        -- CPU Signals
        ZRST_n               => T80_RST_n,
        ZCLK                 => CK4M,
        ZADR                 => T80_A16(7 downto 0),                     -- CPU Address Bus(lower)
        ZRD_n                => RD_n,                                    -- CPU Read Signal
        ZWR_n                => T80_WR_n,                                -- CPU Write Signal
        ZIORQ_n              => IORQ_n,                                  -- CPU I/O Request
        ZDI                  => ZDTO,                                    -- CPU Data Bus(in)
        ZDO                  => DOFDC,                                   -- CPU Data Bus(out)
        SCLK                 => CK3125,                                  -- Slow Clock
        -- FD signals
        DS_n                 => DS,                                      -- Drive Select
        HS                   => HS,                                      -- Head Select
        MOTOR_n              => MOTOR_n,                                 -- Motor On
        INDEX_n              => INDEX_n,                                 -- Index Hole Detect
        TRACK00              => TRACK00_n,                               -- Track 0
        WPRT_n               => WPRT_n,                                  -- Write Protect
        STEP_n               => STEP_n,                                  -- Head Step In/Out
        DIREC                => DIREC,                                   -- Head Step Direction
        WGATE_n              => WGATE_n,                                 -- Write Gate
        DTCLK                => DTCLK,                                   -- Data Clock
        FDI                  => FDI,                                     -- Read Data
        FDO                  => FDO                                      -- Write Data
    );

--    FDU0 : fdunit Port map(
--        -- Interrupt
--        INTO                 => IRQ_FDD,                                 -- Step Pulse interrupt
--        -- FD signals
--        FCLK                 => CK4M,
--        DS_n                 => DS,                                      -- Drive Select
--        HS                   => HS,                                      -- Head Select
--        MOTOR_n              => MOTOR_n,                                 -- Motor On
--        INDEX_n              => INDEX_n,                                 -- Index Hole Detect
--        TRACK00              => TRACK00_n,                               -- Track 0
--        WPRT_n               => WPRT_n,                                  -- Write Protect
--        STEP_n               => STEP_n,                                  -- Head Step In/Out
--        DIREC                => DIREC,                                   -- Head Step Direction
--        WG_n                 => WGATE_n,                                 -- Write Gate
--        DTCLK                => DTCLK,                                   -- Data Clock
--        FDO                  => FDI,                                     -- Read Data
--        FDI                  => FDO,                                     -- Write Data
--        -- Buffer RAM I/F
--        BCS_n                => BCS_n,                                   -- RAM Request
--        BADR                 => BADR,                                    -- RAM Address
--        BWR_n                => BWR_n,                                   -- RAM Write Signal
--        BDI                  => BDI,                                     -- Data Bus Input from RAM
--        BDO                  => BDO                                      -- Data Bus Output to RAM
--    );

    --
    -- Control Signals
    --
    IWR            <= IORQ_n or T80_WR_n;

    --
    -- Data Bus
    --
    ZDTI           <= PPI_DO or DOPIT or PIO_DO or VRAMDO or RAMDI or DOFDC;
    RAMDI          <= T80_DO when RD_n='0' and MREQ_n='0' and CSV_n='1' and CSG_n='1' else (others=>'0');
--              HSKDI when CSHSK='0' else T80_DO;

    --
    -- Chip Select
    --
    CSV_n          <= '0' when MZMODE='0' and PIOPA(7)='1' and T80_A16(15 downto 12)="1101" and MREQ_n='0' and PIOPA(6)='0' else        -- $D000 - $DFFF (80B)
                      '0' when MZMODE='0' and PIOPA(7)='1' and T80_A16(15 downto 12)="0101" and MREQ_n='0' and PIOPA(6)='1' else        -- $5000 - $5FFF (80B)
                      '0' when MZMODE='1' and PIOPA(7)='1' and T80_A16(15 downto 12)="1101" and MREQ_n='0' and PIOPA(6)='1' else '1';   -- $D000 - $DFFF (2000)
    CSG_n          <= '0' when MZMODE='0' and PIOPA(7)='1' and T80_A16(15 downto 13)="111" and MREQ_n='0' and PIOPA(6)='0' else         -- $E000 - $FFFF (80B)
                      '0' when MZMODE='0' and PIOPA(7)='1' and T80_A16(15 downto 13)="011" and MREQ_n='0' and PIOPA(6)='1' else         -- $6000 - $7FFF (80B)
                      '0' when MZMODE='1' and PIOPA(7)='1' and T80_A16(15 downto 14)="11" and MREQ_n='0' and PIOPA(6)='0' else '1';     -- $C000 - $FFFF (2000)
    CSHSK          <= '0' when T80_A16(7 downto 3)="10001" and IORQ_n='0' else '1';                                                     -- HandShake Port
    CSE0_n         <= '0' when T80_A16(7 downto 2)="111000" and IORQ_n='0' else '1';                                                    -- 8255
    CSE4_n         <= '0' when T80_A16(7 downto 2)="111001" and IORQ_n='0' else '1';                                                    -- 8253
    CSE8_n         <= '0' when T80_A16(7 downto 2)="111010" and IORQ_n='0' else '1';                                                    -- PIO

    --
    -- Video Output.
    --
    HSYNC_n        <= HSYNC_ni;
    VSYNC_n        <= VSYNC_ni;
    R              <= Ri;
    G              <= Gi;
    B              <= Bi;
    VBLANK         <= VBLANKi;
    HBLANK         <= HBLANKi;
    VBLANKi        <= PPIPB(0);                                -- Vertical Blanking

    --
    -- Ports
    --
    CSRAM_n        <= MREQ_n when CSV_n='1' and CSG_n='1' and RFSH_n='1' else '1';
    T80_DI         <= ZDTO;
    ZWR_n          <= T80_WR_n;

    --
    -- Misc
    --
    MZMODE         <= SW(9);
    DMODE          <= SW(8);
    T80_RST        <= not T80_RST_n;

    RST8253_n      <= '0' when T80_A16(7 downto 2)="111100" and IWR='0' else '1';

    GPIO1_D(15)<=PPIPC(2);    -- Sound Output
    GPIO1_D(14)<=PPIPC(2);

end rtl;
