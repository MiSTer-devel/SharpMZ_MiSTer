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
--                                      |                                         -> i8254                     (common)
--                                      |                                         -> dpram.vhd                 (common)
--                                      |                                         -> dprom.vhd                 (common)
--                                      |                                         -> mctrl.vhd                 (common)
--                                      |                                         -> video.vhd                 (common)
--                                      |
--                                      |
--                                      (emu) sharpmz.vhd (mz80b)	->	mz80b.vhd
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
use pkgs.config_pkg.all;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;

entity mz80b is
    PORT (
          -- Clocks
          CLKBUS             : in  std_logic_vector(CLKBUS_WIDTH);    -- Clock signals created by clkgen module.

          -- Resets.
          COLD_RESET         : in  std_logic;
          SYSTEM_RESET       : in  std_logic;
          
          -- Z80 CPU
          T80_RST_n          : in  std_logic;
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
          CS_GRAM_n          : out std_logic;                            -- Colour Graphics GRAM Select
          CS_GRAM_80B_n      : out std_logic;                            -- MZ80B GRAM Option Select
          CS_IO_GFB_n        : out std_logic;                            -- Graphics Framebuffer IO Select range
          CS_IO_G_n          : out std_logic;                            -- Graphics Options IO Select range
          CS_SWP_MEMBANK_n   : out std_logic;                            -- Move lower 32K into upper block.

          -- Audio.
          AUDIO_L            : out std_logic;
          AUDIO_R            : out std_logic;

          -- Different operations modes.
          CONFIG             : in  std_logic_vector(CONFIG_WIDTH);

          -- I/O                                                         -- I/O down to the core.
          KEYB_SCAN          : out std_logic_vector(3 downto 0);         -- Keyboard scan lines out.
          KEYB_DATA          : in  std_logic_vector(7 downto 0);         -- Keyboard scan data in.
          KEYB_STALL         : out std_logic;                            -- Keyboard Stall out.
          KEYB_BREAKDETECT   : in  std_logic;                            -- Keyboard break detect.

          -- Cassette magnetic tape signals.
          CMT_BUS_OUT        : in  std_logic_vector(CMT_BUS_OUT_WIDTH);
          CMT_BUS_IN         : out std_logic_vector(CMT_BUS_IN_WIDTH);

          -- Video signals
          VGATE_n            : out std_logic;                            -- Video Gate enable.
          INVERSE_n          : out std_logic;                            -- Invert video output.
          CONFIG_CHAR80      : out std_logic;                            -- 40 Char = 0, 80 Char = 1 select.
          HBLANK             : in  std_logic;                            -- Horizontal Blanking Signal
          VBLANK             : in  std_logic;                            -- Vertical Blanking Signal

          -- HPS Interface
          IOCTL_DOWNLOAD     : in  std_logic;                            -- HPS Downloading to FPGA.
          IOCTL_UPLOAD       : in  std_logic;                            -- HPS Uploading from FPGA.
          IOCTL_CLK          : in  std_logic;                            -- HPS I/O Clock.
          IOCTL_WR           : in  std_logic;                            -- HPS Write Enable to FPGA.
          IOCTL_RD           : in  std_logic;                            -- HPS Read Enable from FPGA.
          IOCTL_ADDR         : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
          IOCTL_DOUT         : in  std_logic_vector(31 downto 0);        -- HPS Data to be written into FPGA.
          IOCTL_DIN          : out std_logic_vector(31 downto 0);        -- HPS Data to be read into HPS.

          -- Debug Status Leds
          DEBUG_STATUS_LEDS  : out std_logic_vector(111 downto 0)        -- 112 leds to display status.
    );
end mz80b;

architecture rtl of mz80b is

--
-- Decodes, misc
--
signal BOOTSTRAP_n           :     std_logic;                            -- Memory select, Low = ROM 0000 - 07FF, High = RAM 0000 - 7FFF
signal SEL_VRAM_ENABLE       :     std_logic;                            -- Enable VRAM/GRAM = 1.
signal SEL_VRAM_HIGHADDR     :     std_logic;                            -- Select VRAM as High (D000-FFFF) address, Low (5000-7FFF)
signal BST_n                 :     std_logic; 
signal NST                   :     std_logic; 
signal MZ_GRAM_ENABLE        :     std_logic;
signal CS_VRAM_ni            :     std_logic;
signal CS_IO_8255_n          :     std_logic;
signal CS_IO_8254_n          :     std_logic;
signal CS_IO_8254_RST_CLK_n  :     std_logic;
signal CS_IO_Z80PIO_n        :     std_logic;
signal CS_GRAM_ni            :     std_logic;
signal CS_GRAM_80B_ni        :     std_logic;
signal CS_IO_GRAMENABLE_n    :     std_logic;
signal CS_IO_GRAMDISABLE_n   :     std_logic;
signal CS_IO_GFB_ni          :     std_logic;
signal CS_IO_G_ni            :     std_logic;
signal CS_ROM_ni             :     std_logic;
signal CS_RAM_ni             :     std_logic;
signal T80_INT_ni            :     std_logic;
signal IRQ_CMT               :     std_logic;
signal IRQ_FDD               :     std_logic;
--
-- PPI
--
signal PPI_DO                :     std_logic_vector(7 downto 0);
signal i8255_PA_O            :     std_logic_vector(7 downto 0);
signal i8255_PA_OE_n         :     std_logic_vector(7 downto 0);
signal i8255_PB_I            :     std_logic_vector(7 downto 0);
signal i8255_PB_O            :     std_logic_vector(7 downto 0);
signal i8255_PC_O            :     std_logic_vector(7 downto 0);
signal i8255_PC_OE_n         :     std_logic_vector(7 downto 0);
--
-- PIT
--
signal PIT_DO                :     std_logic_vector(7 downto 0);
--
-- PIO
--
signal PIO_DO                :     std_logic_vector(7 downto 0);
signal Z80PIO_INT_n          :     std_logic;
signal Z80PIO_PA             :     std_logic_vector(7 downto 0);
signal Z80PIO_PB             :     std_logic_vector(7 downto 0);
--
-- Clocks
--
signal CASCADE01             :     std_logic;
signal CASCADE12             :     std_logic;
--
-- Video
--
signal HBLANKi               :     std_logic;
signal VBLANKi               :     std_logic;
signal HSYNC_ni              :     std_logic;
signal VSYNC_ni              :     std_logic;
signal Ri                    :     std_logic;
signal Gi                    :     std_logic;
signal Bi                    :     std_logic;
signal VGATE_ni              :     std_logic;                               -- Video Outpu Enable
signal VRAM_DO               :     std_logic_vector(7 downto 0);
--
-- Keyboard.
--
signal LED_RVS               :     std_logic;
signal LED_GRPH              :     std_logic;
signal LED_SHIFT_LOCK        :     std_logic;
--
-- Audio
--
signal SOUND                 :     std_logic;
--
-- FDD,FDC
--
signal DOFDC                 :     std_logic_vector(7 downto 0);
signal DS                    :     std_logic_vector(3 downto 0);
signal HS                    :     std_logic;
signal MOTOR_n               :     std_logic;
signal INDEX_n               :     std_logic;
signal TRACK00_n             :     std_logic;
signal WPRT_n                :     std_logic;
signal STEP_n                :     std_logic;
signal DIREC                 :     std_logic;
signal FDO                   :     std_logic_vector(7 downto 0);
signal FDI                   :     std_logic_vector(7 downto 0);
signal WGATE_n               :     std_logic;
signal DTCLK                 :     std_logic;
--
-- Debug
--
signal PULSECPU              :     std_logic; 



--
-- Components
--
component i8255
  port (
      RESET                : in    std_logic;
      CLK                  : in    std_logic;
      ENA                  : in    std_logic; -- (CPU) clk enable
      ADDR                 : in    std_logic_vector(1 downto 0); -- A1-A0
      DI                   : in    std_logic_vector(7 downto 0); -- D7-D0
      DO                   : out   std_logic_vector(7 downto 0);
      CS_n                 : in    std_logic;
      RD_n                 : in    std_logic;
      WR_n                 : in    std_logic;
  
      PA_I                 : in    std_logic_vector(7 downto 0);
      PA_O                 : out   std_logic_vector(7 downto 0);
      PA_O_OE_n            : out   std_logic_vector(7 downto 0);
  
      PB_I                 : in    std_logic_vector(7 downto 0);
      PB_O                 : out   std_logic_vector(7 downto 0);
      PB_O_OE_n            : out   std_logic_vector(7 downto 0);

      PC_I                 : in    std_logic_vector(7 downto 0);
      PC_O                 : out   std_logic_vector(7 downto 0);
      PC_O_OE_n            : out   std_logic_vector(7 downto 0)
  );
end component;

component i8254
 Port (
        RST                  : in  std_logic;
        CLK                  : in  std_logic;
        ENA                  : in  std_logic;
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
        RST_n                : in  std_logic;                            -- Only Power On Reset
        -- Z80 Bus Signals
        CLK                  : in  std_logic;
        ENA                  : in  std_logic;
        BASEL                : in  std_logic;
        CDSEL                : in  std_logic;
        CE                   : in  std_logic;
        RD_n                 : in  std_logic;
        WR_n                 : in  std_logic;
        IORQ_n               : in  std_logic;
        M1_n                 : in  std_logic;
        DI                   : in  std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        IEI                  : in  std_logic;
        IEO                  : out std_logic;
        INT_n                : out std_logic;
        -- Port
        A                    : out std_logic_vector(7 downto 0);
        B                    : in std_logic_vector(7 downto 0)
    );
end component;

begin

    --
    -- Instantiation
    --
    -- 8255 Used for Tape Control and interfacing and system boot control.
    --
    PPI0B : i8255
        port map (
            RESET            => SYSTEM_RESET,
            CLK              => CLKBUS(CKMASTER),
            ENA              => CLKBUS(CKENCPU),
            ADDR             => T80_A16(1 downto 0), 
            DI               => T80_DO,
            DO               => PPI_DO,
            CS_n             => CS_IO_8255_n,
            RD_n             => T80_RD_n,
            WR_n             => T80_WR_n, 
  
            PA_I             => i8255_PA_O,
            PA_O             => i8255_PA_O,
            PA_O_OE_n        => i8255_PA_OE_n,
  
            PB_I             => i8255_PB_I, 
            PB_O             => open, 
            PB_O_OE_n        => open,
    
            PC_I             => i8255_PC_O,
            PC_O             => i8255_PC_O,
            PC_O_OE_n        => i8255_PC_OE_n
     );

    -- 8253 Timer used for the real time clock.
    --
    PIT0 : i8254
      port map (
            RST              => SYSTEM_RESET,
            CLK              => CLKBUS(CKMASTER),
            ENA              => CLKBUS(CKENCPU),
            A                => T80_A16(1 downto 0),
            DI               => T80_DO,
            DO               => PIT_DO,
            CS_n             => CS_IO_8254_n,
            WR_n             => T80_WR_n,
            RD_n             => T80_RD_n,
            CLK0             => CLKBUS(CKRTC),
            GATE0            => CS_IO_8254_RST_CLK_n,
            OUT0             => CASCADE01,
            CLK1             => CASCADE01,
            GATE1            => CS_IO_8254_RST_CLK_n,
            OUT1             => CASCADE12,
            CLK2             => CASCADE12,
            GATE2            => '1',
            OUT2             => open
      );

    -- Z80 PIO used for keyboard, RAM and Video control.
    --
    PIO0 : z8420
        port map (
            -- System
            RST_n            => T80_RST_n,                               -- Only Power On Reset
            -- Z80 Bus Signals
            CLK              => CLKBUS(CKMASTER),
            ENA              => CLKBUS(CKENCPU),
            BASEL            => T80_A16(1),
            CDSEL            => T80_A16(0),
            CE               => CS_IO_Z80PIO_n,
            RD_n             => T80_RD_n,
            WR_n             => T80_WR_n,
            IORQ_n           => T80_IORQ_n,
            M1_n             => T80_M1_n and T80_RST_n,
            DI               => T80_DO,
            DO               => PIO_DO,
            IEI              => '1',
            IEO              => open,
            INT_n            => Z80PIO_INT_n,

            A                => Z80PIO_PA,
            B                => Z80PIO_PB
        );

    -- A1 clocked by C5, if A1 = L when C5 (SEEK) pulses high, then tape rewinds on activation of A0. If A1 is high, then 
    -- tape will fast forward. A0, when pulsed high, activates the motor to go forward/backward.
    -- A2 pulsed high activates the play motor.which cancels a FF/REW event.
    -- A3 when High, stops the Play/FF/REW events.
    -- B5 when high indicates tape drive present and ready.
    -- C4 when Low, ejects the tape.
    -- C6 when Low enables record, otherwise whe High enables play.
    -- C7 is the data to write to tape.
    -- B6 is the data read from tape.
    -- BW ehn Low blocks recording.


    -- PPI Port A - Output connections.
    --
    LED_RVS                  <= i8255_PA_O(7) when i8255_PA_OE_n(7) = '0'
                                else '0';
    LED_GRPH                 <= i8255_PA_O(6) when i8255_PA_OE_n(6) = '0'
                                else '0';
    LED_SHIFT_LOCK           <= i8255_PA_O(5) when i8255_PA_OE_n(5) = '0'
                                else '0';
    INVERSE_n                <= i8255_PA_O(4) when i8255_PA_OE_n(4) = '0'
                                else '1';
    CMT_BUS_IN(STOP)         <= i8255_PA_O(3) when i8255_PA_OE_n(3) = '0'
                                else '0';
    CMT_BUS_IN(PLAY)         <= i8255_PA_O(2) when i8255_PA_OE_n(2) = '0'
                                else '0';
    CMT_BUS_IN(DIRECTION)    <= i8255_PA_O(1) when i8255_PA_OE_n(1) = '0'
                                else '0';
    CMT_BUS_IN(REEL_MOTOR)   <= i8255_PA_O(0) when i8255_PA_OE_n(0) = '0'
                                else '0';


    -- PPI Port B - Input connections.
    --
    i8255_PB_I(7)            <= KEYB_BREAKDETECT;
    i8255_PB_I(6)            <= CMT_BUS_OUT(WRITEBIT);                   -- Tape is loaded in deck when L (0).
    i8255_PB_I(5)            <= CMT_BUS_OUT(TAPEREADY);                  -- Tape is loaded in deck when L (0).
    i8255_PB_I(4)            <= CMT_BUS_OUT(WRITEREADY);                 -- Prohibit Write when L (0).
    i8255_PB_I(3 downto 1)   <= (others => '1');
    i8255_PB_I(0)            <= VBLANK;
    

    -- PPI Port C - Output connections. Feed output to input to be able to read latched value.
    --
    CMT_BUS_IN(READBIT)      <= i8255_PC_O(7) when i8255_PC_OE_n(7) = '0'
                                else '0';
    CMT_BUS_IN(WRITEENABLE)  <= i8255_PC_O(6) when i8255_PC_OE_n(6) = '0'
                                else '0';
    CMT_BUS_IN(SEEK)         <= i8255_PC_O(5) when i8255_PC_OE_n(5) = '0'
                                else '0';
    CMT_BUS_IN(EJECT)        <= i8255_PC_O(4) when i8255_PC_OE_n(4) = '0'
                                else '0';
    BST_n                    <= i8255_PC_O(3) when i8255_PC_OE_n(3) = '0'
                                else '1';
    SOUND                    <= i8255_PC_O(2) when i8255_PC_OE_n(2) = '0'
                                else '0';
    NST                      <= i8255_PC_O(1) when i8255_PC_OE_n(1) = '0'
                                else '0';
    VGATE_ni                 <= i8255_PC_O(0) when i8255_PC_OE_n(0) = '0'
                                else '1';

    -- Z80 PIO Port A - Output.
    --
    SEL_VRAM_ENABLE          <= Z80PIO_PA(7);
    SEL_VRAM_HIGHADDR        <= Z80PIO_PA(6);
    CONFIG_CHAR80            <= Z80PIO_PA(5);
    KEYB_STALL               <= Z80PIO_PA(4);
    KEYB_SCAN                <= Z80PIO_PA(3 downto 0);

    -- Z80 PIO Port B - Input - Keyboard data.
    --
    Z80PIO_PB                <= KEYB_DATA;

    -- Parent signals onto local wires.
    --
    T80_BUSRQ_n              <= '1';
    T80_NMI_n                <= '1';
    T80_WAIT_n               <= '1';

    --
    -- MZ-80B - Interrupts from the Z80PIO or external sources.
    T80_INT_ni               <= '0'        when Z80PIO_INT_n = '0'
                                else '1';
    T80_INT_n                <= T80_INT_ni;

    --
    -- Data Bus Multiplexing, plex all the output devices onto the Z80 Data Input according to the CS.
    --
    T80_DI                   <= PPI_DO     when CS_IO_8255_n  ='0' and T80_RD_n = '0'                          -- Read from 8255
                                else 
                                PIT_DO     when CS_IO_8254_n  ='0' and T80_RD_n = '0'                          -- Read from 8254
                                else 
                                PIO_DO     when CS_IO_Z80PIO_n='0' and T80_RD_n = '0'                          -- Read from Z80PIO
                                else
                                (others=>'1');

    -- HPS Bus Multiplexing for reads.
    IOCTL_DIN                <= "00000000111111111100110010101010";                                            -- Test pattern.

    --
    -- Chip Select map.
    --
    -- 0000 - FFFF             : MZ80B/2000    unless portion paged out by below selects.
    -- 5000 - 5FFF             : MZ80B         = Alternate VRAM location
    -- 6000 - 7FFF             : MZ80B         = Alternate GRAM location
    -- C000 - FFFF             : MZ2000        = GRAM
    -- D000 - DFFF             : MZ80B/2000    = VRAM
    -- E000 - FFFF             : MZ80B         = GRAM
    --
    --
    -- Video RAM Select.
    -- 5000 - 5FFF
    -- D000 - DFFF
    CS_VRAM_ni          <= -- D000 - DFFF
                           '0' when CONFIG(pkgs.mctrl_pkg.MZ80B) = '1'  and SEL_VRAM_ENABLE = '1' and T80_A16(15 downto 12) = "1101" and T80_MREQ_n = '0' and SEL_VRAM_HIGHADDR = '0'
                               else
                           -- 5000 - 5FFF
                           '0' when CONFIG(pkgs.mctrl_pkg.MZ80B) = '1'  and SEL_VRAM_ENABLE = '1' and T80_A16(15 downto 12) = "0101" and T80_MREQ_n = '0' and SEL_VRAM_HIGHADDR = '1'
                               else
                           -- D000 - DFFF
                           '0' when CONFIG(MZ2000) = '1'                and SEL_VRAM_ENABLE = '1' and T80_A16(15 downto 12) = "1101" and T80_MREQ_n = '0' and SEL_VRAM_HIGHADDR = '1'
                               else '1';

    -- MZ80B/2000 Graphics RAM Select.
    --
    CS_GRAM_80B_ni      <= -- E000 - FFFF
                           '0' when CONFIG(pkgs.mctrl_pkg.MZ80B) = '1'  and SEL_VRAM_ENABLE = '1' and T80_A16(15 downto 13) = "111"  and T80_MREQ_n = '0' and SEL_VRAM_HIGHADDR = '0'
                           else
                           -- 6000 - 7FFF
                           '0' when CONFIG(pkgs.mctrl_pkg.MZ80B) = '1'  and SEL_VRAM_ENABLE = '1' and T80_A16(15 downto 13) = "011"  and T80_MREQ_n = '0' and SEL_VRAM_HIGHADDR = '1'
                           else
                           -- C000 - FFFF
                           '0' when CONFIG(MZ2000) = '1'                and SEL_VRAM_ENABLE = '1' and T80_A16(15 downto 14) = "11"   and T80_MREQ_n = '0' and SEL_VRAM_HIGHADDR = '0'
                           else '1';

    -- Colour frame buffer.
    -- C000 - FFFF
    --
    CS_GRAM_ni          <= '0' when CONFIG(pkgs.mctrl_pkg.MZ80B) = '1'  and MZ_GRAM_ENABLE = '1'  and T80_A16(15 downto 14) = "11"   and T80_MREQ_n='0'
                           else '1';


    -- Boot ROM. Enabled only at startup when
    --
    -- 0000 -> 07FF when in IPL mode.
    CS_ROM_ni           <= '0' when BOOTSTRAP_n = '0' and T80_A16(15 downto 11) = "00000" and T80_MREQ_n = '0'
                           else '1';
    --
    CS_RAM_ni           <= '0' when BOOTSTRAP_n = '0' and T80_A16(15) = '1' and CS_VRAM_ni = '1' and CS_GRAM_ni = '1' and CS_GRAM_80B_ni = '1' and T80_MREQ_n = '0'
                           else
                           '0' when BOOTSTRAP_n = '1' and CS_VRAM_ni = '1' and CS_GRAM_ni = '1' and CS_GRAM_80B_ni = '1' and T80_MREQ_n = '0'
                           else '1';

    --
    -- IO Select Map.
    -- E0 - EF are used by the MZ80B/2000 to perform memory switching and graphics control.
    -- F0-F3 write is used to set the gates of the 8254
    -- F4-F7 is used to control the graphics options.
    -- F8 is used to write the MSB of the Rom Expansion
    -- F9 is used to write the LSB of the Rom Expansion and to read the data byte back.
    --
    -- IO Range for Graphics enhancements is set by the MCTRL DISPLAY2{7:3] register.
    -- x[0|8],<val> sets the graphics mode. 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR), 5=GRAM Output Enable, 4 = VRAM Output Enable, 3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect), 1/0=Read mode (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
    -- x[1|9],<val> sets the Red bit mask (1 bit = 1 pixel, 8 pixels per byte).
    -- x[2|A],<val> sets the Green bit mask (1 bit = 1 pixel, 8 pixels per byte).
    -- x[3|B],<val> sets the Blue bit mask (1 bit = 1 pixel, 8 pixels per byte).
    -- x[4|C]       switches in 1 16Kb page (3 pages) of graphics ram to C000 - FFFF. This overrides all MZ700 page switching functions.
    -- x[5|D]       switches out the graphics ram and returns to previous state.
    --
    CS_IO_8255_n        <= '0'  when T80_IORQ_n   = '0' and T80_A16(7 downto 2) = "111000"                               -- IO E0-E3 = 8255
                           else '1';
    CS_IO_8254_n        <= '0'  when T80_IORQ_n   = '0' and T80_A16(7 downto 2) = "111001"                               -- IO E4-E7 = 8254
                           else '1';
    CS_IO_Z80PIO_n      <= '0'  when T80_IORQ_n   = '0' and T80_A16(7 downto 2) = "111010"                               -- IO E8-EB = Z80PIO
                           else '1';
    CS_IO_8254_RST_CLK_n<= '0'  when T80_IORQ_n   = '0' and T80_A16(7 downto 2) = "111100" and T80_WR_n = '0'            -- IO F0-F3 = 8254 Clock reset.
                           else '1';
    CS_IO_G_ni          <= '0'  when T80_IORQ_n   = '0' and T80_A16(7 downto 2) = "111101" and T80_WR_n = '0'            -- IO Range for Graphics framebuffer register controlled by mctrl register.
                           else '1';
    CS_IO_GFB_ni        <= '0'  when T80_IORQ_n   = '0' and T80_A16(7 downto 3) = CONFIG(GRAMIOADDR) and T80_WR_n = '0'  -- IO Range for Graphics framebuffer register controlled by mctrl register.
                           else '1';
    CS_IO_GRAMENABLE_n  <= '0'  when CS_IO_GFB_ni = '0' and T80_A16(2 downto 0) = "100"                                  -- IO Addr base+4 sets C000 -> FFFF map to Graphics RAM.
                           else '1';
    CS_IO_GRAMDISABLE_n <= '0'  when CS_IO_GFB_ni = '0' and T80_A16(2 downto 0) = "101"                                  -- IO Addr base+5 sets C000 -> FFFF revert to previous mode.
                           else '1';

    -- Send signals to module interface.
    --
    CS_ROM_n            <= CS_ROM_ni;
    CS_RAM_n            <= CS_RAM_ni;
    CS_VRAM_n           <= CS_VRAM_ni;
    CS_GRAM_n           <= CS_GRAM_ni;
    CS_GRAM_80B_n       <= CS_GRAM_80B_ni;
    CS_IO_GFB_n         <= CS_IO_GFB_ni;
    CS_IO_G_n           <= CS_IO_G_ni;
    CS_SWP_MEMBANK_n    <= BOOTSTRAP_n;
    VGATE_n             <= VGATE_ni;

    -- On initial reset, BOOTSTRAP_n is set active, a reset setup and hold takes place, then the processor is set running with the
    -- IPL monitor rom at 0000-07ff. 
    -- If NST goes High (due to the IPL setting it), then a flip flop is clocked setting BOOTSTRAP_n to inactive which places RAM
    -- into the normal running state at 0000-7fff and the IPL monitor rom is disabled.
    -- BOOT_RESET (external input) or BST_n when Low sets the BOOTSTRAP_n so that IPL mode is entered and the IPL monitor rom
    -- is active at 0000. 
    --
    process( COLD_RESET, CONFIG(BOOT_RESET), BST_n, CLKBUS(CKMASTER), NST )
    begin
        -- A cold reset sets up the initial state, further resets just reset variables as needed.
        --
        if COLD_RESET = '1' then
            BOOTSTRAP_n  <= '0'; 

        elsif(CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1') then
            
            if CLKBUS(CKENCPU) = '1' then

                if CONFIG(BOOT_RESET) = '1' or BST_n = '0' then
                    -- Only a boot reset or BST_n can set the BOOTSTRAP signal. A system reset just
                    -- resets the cpu and peripherals.
                    --
                    if CONFIG(BOOT_RESET) = '1' or BST_n = '0' then
                        BOOTSTRAP_n <= '0'; 
                    end if;
    
                else 
                    -- If the NST signal goes high, then reset the BOOTSTRAP signal. This signal can only be set
                    -- by a reset action.
                    --
                    if NST = '1' then
                        BOOTSTRAP_n <= '1'; 
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Graphics Ram - Latch wether to enable Graphics RAM page from C000 - FFFF.
    --
    process( SYSTEM_RESET, CLKBUS(CKMASTER), CS_IO_GRAMENABLE_n, CS_IO_GRAMDISABLE_n ) begin
        if(SYSTEM_RESET = '1') then
            MZ_GRAM_ENABLE <= '0';

        elsif(CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1') then

            if CLKBUS(CKENCPU) = '1' then

                if(CS_IO_GRAMENABLE_n = '0') then
                    MZ_GRAM_ENABLE <= '0';
    
                elsif(CS_IO_GRAMDISABLE_n = '0') then
                    MZ_GRAM_ENABLE <= '0';
    
                end if;
            end if;
        end if;
    end process;

    -- Audio output. Choose between generated sound and CMT pulse audio.
    --
    AUDIO_L    <= SOUND when CONFIG(AUDIOSRC) = '0'            -- Sound Output Left
                  else
                  CMT_BUS_OUT(WRITEBIT);
    AUDIO_R    <= SOUND when CONFIG(AUDIOSRC) = '0'            -- Sound Output Right
                  else
                  CMT_BUS_OUT(READBIT);

    -- Only enable debugging LEDS if enabled in the config package.
    --
    DEBUG80B: if DEBUG_ENABLE = 1 generate

        -- A simple 1*cpufreq second pulse to indicate accuracy of CPU frequency for debug purposes..
        --
        process (SYSTEM_RESET, CLKBUS(CKMASTER))
            variable cnt : integer range 0 to 1999999 := 0;
        begin
            if SYSTEM_RESET = '1' then
                PULSECPU <= '0';
                cnt      := 0;
            elsif rising_edge(CLKBUS(CKMASTER)) then
                if CLKBUS(CKENCPU) = '1' then
                    cnt      := cnt + 1;
                    if cnt = 0 then
                        PULSECPU <= not PULSECPU;
                    end if;
                end if;
            end if;
        end process;

        -- Debug leds.
        --
        DEBUG_STATUS_LEDS(0)  <= CS_VRAM_ni;
        DEBUG_STATUS_LEDS(1)  <= CS_GRAM_ni;
        DEBUG_STATUS_LEDS(2)  <= CS_GRAM_80B_ni;
        DEBUG_STATUS_LEDS(3)  <= CS_IO_8255_n;
        DEBUG_STATUS_LEDS(4)  <= CS_IO_8254_n;
        DEBUG_STATUS_LEDS(5)  <= CS_IO_Z80PIO_n;
        DEBUG_STATUS_LEDS(6)  <= CS_ROM_ni;
        DEBUG_STATUS_LEDS(7)  <= CS_RAM_ni;
        --
        DEBUG_STATUS_LEDS(8)  <= '0';
        DEBUG_STATUS_LEDS(9)  <= CS_IO_8254_RST_CLK_n;
        DEBUG_STATUS_LEDS(10) <= CS_IO_GRAMENABLE_n;
        DEBUG_STATUS_LEDS(11) <= CS_IO_GRAMDISABLE_n;
        DEBUG_STATUS_LEDS(12) <= CS_IO_GFB_ni;
        DEBUG_STATUS_LEDS(13) <= CS_IO_G_ni;
        DEBUG_STATUS_LEDS(14) <= '0';
        DEBUG_STATUS_LEDS(15) <= '0';
        --
        DEBUG_STATUS_LEDS(16) <= BST_n;
        DEBUG_STATUS_LEDS(17) <= NST;
        DEBUG_STATUS_LEDS(18) <= MZ_GRAM_ENABLE;
        DEBUG_STATUS_LEDS(19) <= BOOTSTRAP_n;
        DEBUG_STATUS_LEDS(20) <= SEL_VRAM_ENABLE;
        DEBUG_STATUS_LEDS(21) <= SEL_VRAM_HIGHADDR;
        DEBUG_STATUS_LEDS(22) <= VGATE_ni;
        DEBUG_STATUS_LEDS(23) <= CONFIG(BOOT_RESET);
        --
        DEBUG_STATUS_LEDS(24) <= PULSECPU;
        DEBUG_STATUS_LEDS(25) <= T80_INT_ni;
        DEBUG_STATUS_LEDS(26) <= '0';
        DEBUG_STATUS_LEDS(27) <= COLD_RESET;
        DEBUG_STATUS_LEDS(28) <= SYSTEM_RESET;
        DEBUG_STATUS_LEDS(29) <= '0';
        DEBUG_STATUS_LEDS(30) <= CONFIG(BOOT_RESET);
        DEBUG_STATUS_LEDS(31) <= BST_n;
        --
        DEBUG_STATUS_LEDS(32) <= LED_RVS;
        DEBUG_STATUS_LEDS(33) <= LED_GRPH;
        DEBUG_STATUS_LEDS(34) <= LED_SHIFT_LOCK;
        DEBUG_STATUS_LEDS(35) <= '0';
        DEBUG_STATUS_LEDS(36) <= '0';
        DEBUG_STATUS_LEDS(37) <= CASCADE01;
        DEBUG_STATUS_LEDS(38) <= CASCADE12;
        DEBUG_STATUS_LEDS(39) <= PULSECPU;
        --
        DEBUG_STATUS_LEDS(40) <= i8255_PA_O(0);
        DEBUG_STATUS_LEDS(41) <= i8255_PA_O(1);
        DEBUG_STATUS_LEDS(42) <= i8255_PA_O(2);
        DEBUG_STATUS_LEDS(43) <= i8255_PA_O(3);
        DEBUG_STATUS_LEDS(44) <= i8255_PA_O(4);
        DEBUG_STATUS_LEDS(45) <= i8255_PA_O(5);
        DEBUG_STATUS_LEDS(46) <= i8255_PA_O(6);
        DEBUG_STATUS_LEDS(47) <= i8255_PA_O(7);
        --
        DEBUG_STATUS_LEDS(48) <= i8255_PB_I(0);
        DEBUG_STATUS_LEDS(49) <= i8255_PB_I(1);
        DEBUG_STATUS_LEDS(50) <= i8255_PB_I(2);
        DEBUG_STATUS_LEDS(51) <= i8255_PB_I(3);
        DEBUG_STATUS_LEDS(52) <= i8255_PB_I(4);
        DEBUG_STATUS_LEDS(53) <= i8255_PB_I(5);
        DEBUG_STATUS_LEDS(54) <= i8255_PB_I(6);
        DEBUG_STATUS_LEDS(55) <= i8255_PB_I(7);
        --
        DEBUG_STATUS_LEDS(56) <= i8255_PC_O(0);
        DEBUG_STATUS_LEDS(57) <= i8255_PC_O(1);
        DEBUG_STATUS_LEDS(58) <= i8255_PC_O(2);
        DEBUG_STATUS_LEDS(59) <= i8255_PC_O(3);
        DEBUG_STATUS_LEDS(60) <= i8255_PC_O(4);
        DEBUG_STATUS_LEDS(61) <= i8255_PC_O(5);
        DEBUG_STATUS_LEDS(62) <= i8255_PC_O(6);
        DEBUG_STATUS_LEDS(63) <= i8255_PC_O(7);

        -- LEDS 64 .. 112 are available.
        DEBUG_STATUS_LEDS(111 downto 64) <= (others => '0');
    end generate;
end rtl;
