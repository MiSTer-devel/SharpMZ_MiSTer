---------------------------------------------------------------------------------------------------------
--
-- Name:            mz80c.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series Personal Computer:
--                                  Models MZ-80K, MZ-80C, MZ-1200, MZ-80A, MZ-700, MZ-800
--
--                  This module is the main (top level) container for the Personal MZ Computer
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

library ieee;
library pkgs;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use pkgs.config_pkg.all;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;

entity mz80c is
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
          CS_MEM_G_n         : out std_logic;                            -- Memory Peripherals Select
          CS_GRAM_n          : out std_logic;                            -- GRAM Select
          CS_IO_GFB_n        : out std_logic;                            -- Graphics Framebuffer IO Select range

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
end mz80c;

architecture rtl of mz80c is

--
-- Buffered output signals.
--
signal BLNK_n                :     std_logic;

-- Parent signals.
--
signal MZ_RESET              :     std_logic;
signal MZ_MEMORY_SWAP        :     std_logic;
signal MZ_LOW_RAM_ENABLE     :     std_logic;
signal MZ_HIGH_RAM_ENABLE    :     std_logic;
signal MZ_HIGH_RAM_INHIBIT   :     std_logic;
signal MZ_INHIBIT_RESET      :     std_logic;
signal MZ_GRAM_ENABLE        :     std_logic;
signal i8255_PA_I            :     std_logic_vector(7 downto 0);
signal i8255_PA_O            :     std_logic_vector(7 downto 0);
signal i8255_PA_OE_n         :     std_logic_vector(7 downto 0);
signal i8255_PB_I            :     std_logic_vector(7 downto 0);
signal i8255_PB_O            :     std_logic_vector(7 downto 0);
signal i8255_PC_I            :     std_logic_vector(7 downto 0);
signal i8255_PC_O            :     std_logic_vector(7 downto 0);
signal i8255_PC_OE_n         :     std_logic_vector(7 downto 0);
--
-- System Clocks
--
signal MZ_RTC_CASCADE_CLK    :     std_logic;                            -- i8254 subdivision of the 31.250KHz clock creating 1s/1Hz timebase.
--
-- Decodes, misc
--
signal CS_VRAM_ni            :     std_logic;
signal CS_E_ni               :     std_logic;
signal CS_E0_n               :     std_logic;
signal CS_E1_n               :     std_logic;
signal CS_E2_n               :     std_logic;
signal CS_ESWP_n             :     std_logic;
signal CS_GRAM_ni            :     std_logic;
signal DO367                 :     std_logic_vector(7 downto 0);
signal CS_BANKSWITCH_n       :     std_logic;
signal CS_MZ700BS_n          :     std_logic;
signal CS_IO_E0_n            :     std_logic;
signal CS_IO_E1_n            :     std_logic;
signal CS_IO_E2_n            :     std_logic;
signal CS_IO_E3_n            :     std_logic;
signal CS_IO_E4_n            :     std_logic;
signal CS_IO_E5_n            :     std_logic;
signal CS_IO_E6_n            :     std_logic;
signal CS_IO_GRAMENABLE_n    :     std_logic;
signal CS_IO_GRAMDISABLE_n   :     std_logic;
signal CS_IO_GFB_ni          :     std_logic;
signal CS_ROM_ni             :     std_logic;
signal CS_RAM_ni             :     std_logic;
signal VGATE_ni              :     std_logic;                               -- Video Output Enable
signal T80_IWR_n             :     std_logic;
signal T80_INT_ni            :     std_logic;
--
-- PPI
--
signal DOPPI                 :     std_logic_vector(7 downto 0);
signal INTMSK                :     std_logic;                               -- EISUU/KANA LED
--
-- PIT
--
signal DOPIT                 :     std_logic_vector(7 downto 0);
signal SOUND_ENABLE          :     std_logic;
signal SOUND_PULSE_X2        :     std_logic;
signal SOUND                 :     std_logic;
signal INTX                  :     std_logic;
--
-- CURSOR blink
--
signal CURSOR_RESET          :     std_logic;
signal CURSOR_CLK            :     std_logic;
signal CURSOR_BLINK          :     std_logic;
signal CCOUNT                :     std_logic_vector(4 downto 0);
--
-- Remote
--
signal SNS                   :     std_logic;
signal MTR                   :     std_logic;
signal M_ON                  :     std_logic;
signal SENSE0                :     std_logic;
signal SWIN                  :     std_logic_vector(3 downto 0);
--
-- Debug
--
signal PULSECPU              :     std_logic; 

--
-- Components
--
component i8255
    port (
        RESET                : in  std_logic;
        CLK                  : in  std_logic;
        ENA                  : in  std_logic; -- (CPU) clk enable
        ADDR                 : in  std_logic_vector(1 downto 0); -- A1-A0
        DI                   : in  std_logic_vector(7 downto 0); -- D7-D0
        DO                   : out std_logic_vector(7 downto 0);
        CS_n                 : in  std_logic;
        RD_n                 : in  std_logic;
        WR_n                 : in  std_logic;
    
        PA_I                 : in  std_logic_vector(7 downto 0);
        PA_O                 : out std_logic_vector(7 downto 0);
        PA_O_OE_n            : out std_logic_vector(7 downto 0);
    
        PB_I                 : in  std_logic_vector(7 downto 0);
        PB_O                 : out std_logic_vector(7 downto 0);
        PB_O_OE_n            : out std_logic_vector(7 downto 0);
    
        PC_I                 : in  std_logic_vector(7 downto 0);
        PC_O                 : out std_logic_vector(7 downto 0);
        PC_O_OE_n            : out std_logic_vector(7 downto 0)
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

begin

    --
    -- Instantiation
    --
    -- 8255 PPI used for Tape control and interfacing, Keyboard input
    -- and Video/Sound control.
    --
    PPI0A : i8255
        port map (
            RESET            => MZ_RESET,
            CLK              => CLKBUS(CKMASTER),
            ENA              => CLKBUS(CKENCPU), --'1',
            ADDR             => T80_A16(1 downto 0), 
            DI               => T80_DO,
            DO               => DOPPI,
            CS_n             => CS_E0_n,
            RD_n             => T80_RD_n,
            WR_n             => T80_WR_n, 
    
            PA_I             => i8255_PA_O,
            PA_O             => i8255_PA_O,
            PA_O_OE_n        => i8255_PA_OE_n,
    
            PB_I             => i8255_PB_I, 
            PB_O             => open, 
            PB_O_OE_n        => open,
    
            PC_I             => i8255_PC_I,
            PC_O             => i8255_PC_O,
            PC_O_OE_n        => i8255_PC_OE_n
        );

    -- 8253 used for real time clock and sound generation.
    --
    PIT0 : i8254
      port map (
            RST              => MZ_RESET,
            CLK              => CLKBUS(CKMASTER),
            ENA              => CLKBUS(CKENCPU),
            A                => T80_A16(1 downto 0),
            DI               => T80_DO,
            DO               => DOPIT,
            CS_n             => CS_E1_n,
            WR_n             => T80_WR_n,
            RD_n             => T80_RD_n,
            CLK0             => CLKBUS(CKSOUND),
            GATE0            => SOUND_ENABLE,
            OUT0             => SOUND_PULSE_X2,
            CLK1             => CLKBUS(CKRTC),
            GATE1            => '1',
            OUT1             => MZ_RTC_CASCADE_CLK,
            CLK2             => MZ_RTC_CASCADE_CLK,
            GATE2            => '1',
            OUT2             => INTX
      );

    -- Parent signals onto local wires.
    --
    T80_BUSRQ_n              <= '1';
    T80_NMI_n                <= '1';
    T80_WAIT_n               <= '1';
    MZ_RESET                 <= SYSTEM_RESET;

    --
    -- MZ-80A - Mask interrupt from 8254 if INTMSK low.
    -- MZ-80K - Interrupt is from 8254 direct.
    T80_INT_ni               <= '0' when ((CONFIG(MZ_A)='1' or CONFIG(MZ700) = '1') and INTX='1' and INTMSK='1') or ((CONFIG(MZ_KC)='1' and INTX='1'))
                                else '1';
    T80_INT_n                <= T80_INT_ni;

    -- PIO and PIT signals. PIO, allow readback of output signals.
    --
    i8255_PC_I(7)            <= VBLANK;                                  -- V-BLANK signal
    i8255_PC_I(6)            <= CURSOR_BLINK;                            -- Cursor Blink
    i8255_PC_I(5)            <= CMT_BUS_OUT(WRITEBIT);                   -- MZ in from CMT out.
    i8255_PC_I(4)            <= CMT_BUS_OUT(SENSE);                      -- CMT Read/Write status.
    i8255_PC_I(3)            <= i8255_PC_O(3) when i8255_PC_OE_n(3) = '0'
                                else '0';
    i8255_PC_I(2)            <= INTMSK;                                  -- Red/Green LED MZ80K, Interrupt Mask MZ80A
    i8255_PC_I(1)            <= i8255_PC_O(1) when i8255_PC_OE_n(1) = '0'
                                else '0';
    i8255_PC_I(0)            <= VGATE_ni;                                -- Video Output Enable
    --
    CMT_BUS_IN(REEL_MOTOR)   <= '0';
    CMT_BUS_IN(READBIT)      <= i8255_PC_O(1) when i8255_PC_OE_n(1) = '0'
                                else '0';                                -- Data Read Bit into CMT originating from MZ.
    CMT_BUS_IN(STOP)         <= '0';
    CMT_BUS_IN(PLAY)         <= i8255_PC_O(3) when i8255_PC_OE_n(3) = '0'
                                else '0';                                -- Play motor on clock. A high pulse activates the motor.
    CMT_BUS_IN(SEEK)         <= '0';
    CMT_BUS_IN(DIRECTION)    <= '0';
    CMT_BUS_IN(EJECT)        <= '1';
    CMT_BUS_IN(WRITEENABLE)  <= '0';
    CURSOR_RESET             <= i8255_PA_O(7) when i8255_PA_OE_n(7) = '0'
                                else '1';
    INTMSK                   <= i8255_PC_O(2) when i8255_PC_OE_n(2) = '0'
                                else '1';
    VGATE_ni                 <= i8255_PC_O(0) when i8255_PC_OE_n(0) = '0'
                                else '1';
    KEYB_SCAN                <= i8255_PA_O(3 downto 0) when i8255_PA_OE_n(3 downto 0) /= "1111"
                                else "0000";                             -- Keyboard scan lines out.
    KEYB_STALL               <= i8255_PA_O(4) when i8255_PA_OE_n(4) = '0'
                                else '0';                                -- Keyboard Stall out.
    i8255_PB_I               <= KEYB_DATA;                               -- Keyboard scan data in.

    --
    -- Data Bus Multiplexing, plex all the output devices onto the Z80 Data Input according to the CS.
    --
    T80_DI                   <= DOPPI     when CS_E0_n  ='0' and T80_RD_n = '0'                                -- Read from 8255
                                else 
                                DOPIT     when CS_E1_n  ='0' and T80_RD_n = '0'                                -- Read from 8254
                                else 
                                DO367     when CS_E2_n  ='0' and T80_RD_n = '0'                                -- Read from LS367
                                else 
                                (others=>'1');

    -- HPS Bus Multiplexing for reads.
    IOCTL_DIN                <= "11111111000000001100110010101010";                                                            -- Test pattern.

    --
    -- Chip Select map.
    --
    -- 0000 - 0FFF = CS_ROM_ni : MZ80K/A/700   = Monitor ROM or RAM (MZ80A rom swap)
    -- 1000 - CFFF = CS_RAM_ni : MZ80K/A/700   = RAM
    -- C000 - CFFF = CS_ROM_ni : MZ80A         = Monitor ROM (MZ80A rom swap)
    -- D000 - D7FF = CS_VRAM_ni: MZ80K/A/700   = VRAM
    -- D800 - DFFF = CS_VRAM_ni: MZ700         = Colour VRAM (MZ700)
    -- E000 - E003 = CS_E0_n   : MZ80K/A/700   = 8255       
    -- E004 - E007 = CS_E1_n   : MZ80K/A/700   = 8254
    -- E008 - E00B = CS_E2_n   : MZ80K/A/700   = LS367
    -- E00C - E00F = CS_ESWP_n : MZ80A         = Memory Swap (MZ80A)
    -- E010 - E013 = CS_ESWP_n : MZ80A         = Reset Memory Swap (MZ80A)
    -- E014        = CS_E5_n   : MZ80A/700     = Normat CRT display
    -- E015        = CS_E6_n   : MZ80A/700     = Reverse CRT display
    -- E200 - E2FF =           : MZ80A/700     = VRAM roll up/roll down.
    -- E800 - EFFF =           : MZ80K/A/700   = User ROM socket or DD Eprom (MZ700)
    -- F000 - F7FF =           : MZ80K/A/700   = Floppy Disk interface.
    -- F800 - FFFF =           : MZ80K/A/700   = Floppy Disk interface.
    --
    -- C000 - CFFF
    --CS_C_n            <= '0'  when ( (T80_A16(15 downto 12)="1100" and T80_MREQ_n = '0' and MZ_GRAM_ENABLE = '0')
    --                               )
    --                          else '1';

    -- D000 - DFFF
    CS_VRAM_ni          <= '0'  when ( (T80_A16(15 downto 12)="1101" and T80_MREQ_n = '0' and MZ_GRAM_ENABLE = '0')
                                       and
                                       ( (CONFIG(MZ_KC)='1' or CONFIG(MZ_A)='1')
                                         or
                                         (CONFIG(MZ700)='1' and MZ_HIGH_RAM_ENABLE='0' and MZ_HIGH_RAM_INHIBIT='0')
                                       )
                                     ) 
                                else '1';
    -- E000 - EFFF
    CS_E_ni             <= '0'  when ( (T80_A16(15 downto 12)="1110" and T80_MREQ_n = '0' and MZ_GRAM_ENABLE = '0')
                                       and
                                       ( (CONFIG(MZ_KC)='1' or CONFIG(MZ_A)='1')
                                         or
                                         (CONFIG(MZ700)='1' and MZ_HIGH_RAM_ENABLE='0' and MZ_HIGH_RAM_INHIBIT='0')
                                       )
                                     )
                                else '1';
    -- Sub division E000 - E200
    CS_E0_n             <= '0'  when CS_E_ni = '0' and T80_A16(11 downto 2) = "0000000000"                                                -- 8255
                                else '1';
    CS_E1_n             <= '0'  when CS_E_ni = '0' and T80_A16(11 downto 2) = "0000000001"                                                -- 8254
                                else '1';
    CS_E2_n             <= '0'  when CS_E_ni = '0' and T80_A16(11 downto 2) = "0000000010"                                                -- LS367
                                else '1';
    CS_ESWP_n           <= '0'  when CONFIG(MZ_A) = '1' and CS_E_ni = '0' and T80_RD_n = '0' and T80_A16(11 downto 5) = "0000000"         -- ROM/RAM Swap
                                else '1';

    -- F000 - FFFF
    --CS_F_n            <= '0'  when ( (T80_A16(15 downto 12)="1111" and T80_MREQ_n = '0' and MZ_GRAM_ENABLE = '0')
    --                                 and
    --                                 ( (CONFIG(MZ_KC)='1' or CONFIG(MZ_A)='1')
    --                                   or
    --                                   (CONFIG(MZ700)='1' and MZ_HIGH_RAM_ENABLE='0' and MZ_HIGH_RAM_INHIBIT='0')
    --                                 )
    --                               )
    --                          else '1';

    -- C000 - FFFF
    CS_GRAM_ni          <= '0'  when MZ_GRAM_ENABLE = '1' and T80_A16(15 downto 14) = "11" and T80_MREQ_n='0'
                                else '1';
    --
    CS_ROM_ni           <= '0'  when ( ( (T80_A16(15 downto 12)="0000") 
                                         and
                                         ( (CONFIG(MZ_A)='1' and MZ_MEMORY_SWAP='0')                                                      -- 0000 -> 0FFF MZ80A ROM
                                           or
                                           (CONFIG(MZ_KC)='1')                                                                            -- 0000 -> 0FFF MZ80K ROM
                                           or
                                           (CONFIG(MZ700)='1' and MZ_LOW_RAM_ENABLE='0')                                                  -- 0000 -> 0FFF MZ700 ROM
                                         ) 
                                       )
                                       or
                                       ( (T80_A16(15 downto 12)="1100")
                                         and
                                         ( (CONFIG(MZ_A)='1' and MZ_GRAM_ENABLE='0' and MZ_MEMORY_SWAP='1')                               -- C000 -> CFFF MZ80A ROM memory swapped.
                                         )
                                       )
                                       or
                                       ( T80_A16(15 downto 11) = "11101"                                                                  -- E800 -> EFFF User ROM memory.
                                         and
                                         (CONFIG(USERROM) and CONFIG(CURRENTMACHINE)) /= "00000000"                                       -- Active machine has the user rom enabled.
                                         and
                                         MZ_GRAM_ENABLE = '0'                                                                             -- Graphics RAM is not enabled.
                                         and
                                         (MZ_HIGH_RAM_ENABLE = '0' or (MZ_HIGH_RAM_ENABLE = '1' and MZ_HIGH_RAM_INHIBIT = '1'))           -- High RAM is not enabled.
                                       )
                                       or
                                       ( T80_A16(15 downto 12) = "1111"
                                         and
                                         (CONFIG(FDCROM) and CONFIG(CURRENTMACHINE)) /= "00000000"                                        -- Active machine has the fdc rom enabled.
                                         and
                                         MZ_GRAM_ENABLE = '0'                                                                             -- Graphics RAM is not enabled.
                                         and
                                         (MZ_HIGH_RAM_ENABLE = '0' or (MZ_HIGH_RAM_ENABLE = '1' and MZ_HIGH_RAM_INHIBIT = '1'))           -- F000 -> FFFF FDC ROM memory.
                                       )
                                     ) and T80_MREQ_n='0'
                                else '1';
    --
    CS_RAM_ni           <= '0'  when ( ( (T80_A16(15 downto 12)="0000")
                                         and 
                                         ( (CONFIG(MZ_A)='1' and MZ_MEMORY_SWAP='1')                                                      -- 0000 -> 0FFF MZ80A memory swapped.
                                           or
                                           (CONFIG(MZ700)='1' and MZ_LOW_RAM_ENABLE='1')                                                  -- 0000 -> 0FFF MZ700 Low Ram Enabled.
                                         )
                                       )
                                       or

                                       (T80_A16(15 downto 12)="0001" or T80_A16(15 downto 12)="0010" or                                   -- 1000 -> 2FFF
                                        T80_A16(15 downto 12)="0011" or T80_A16(15 downto 12)="0100" or                                   -- 3000 -> 4FFF
                                        T80_A16(15 downto 12)="0101" or T80_A16(15 downto 12)="0110" or                                   -- 5000 -> 6FFF
                                        T80_A16(15 downto 12)="0111" or T80_A16(15 downto 12)="1000" or                                   -- 7000 -> 8FFF
                                        T80_A16(15 downto 12)="1001" or T80_A16(15 downto 12)="1010" or                                   -- 9000 -> AFFF
                                        T80_A16(15 downto 12)="1011")                                                                     -- B000 -> BFFF
                                       or

                                       ( (MZ_GRAM_ENABLE = '0')
                                         and                                                                                              -- Higher memory only available when GRAM not active.
                                         ( ( (T80_A16(15 downto 12)="1100") 
                                             and
                                             ( (CONFIG(MZ_A)='1' and MZ_MEMORY_SWAP='0')                                                  -- C000 -> CFFF MZ80A memory not swapped.
                                               or
                                               (CONFIG(MZ_KC)='1')                                                                        -- C000 -> CFFF MZ80K
                                               or
                                               (CONFIG(MZ700)='1')                                                                        -- C000 -> CFFF MZ700
                                             )
                                           )
                                           or
                                           ( (CONFIG(MZ700)='1' and MZ_HIGH_RAM_ENABLE='1' and MZ_HIGH_RAM_INHIBIT='0')                   -- D000 -> FFFF MZ700 Ram Enabled.
                                             and
                                             ( (T80_A16(15 downto 12)="1101" or T80_A16(15 downto 12)="1110"
                                               or
                                                T80_A16(15 downto 12)="1111")
                                             )
                                           ) 
                                         )
                                       )
                                     )
                                     and T80_MREQ_n='0'
                                else '1';

    --
    -- IO Select Map.
    -- E0 - E6 are used by the MZ700 to perform memory bank switching.
    --
    -- IO Range for Graphics enhancements is set by the MCTRL DISPLAY2{7:3] register.
    -- x[0|8],<val> sets the graphics mode. 7/6 = Operator (00=OR,01=AND,10=NAND,11=XOR), 5=GRAM Output Enable, 4 = VRAM Output Enable, 3/2 = Write mode (00=Page 1:Red, 01=Page 2:Green, 10=Page 3:Blue, 11=Indirect), 1/0=Read mode (00=Page 1:Red, 01=Page2:Green, 10=Page 3:Blue, 11=Not used).
    -- x[1|9],<val> sets the Red bit mask (1 bit = 1 pixel, 8 pixels per byte).
    -- x[2|A],<val> sets the Green bit mask (1 bit = 1 pixel, 8 pixels per byte).
    -- x[3|B],<val> sets the Blue bit mask (1 bit = 1 pixel, 8 pixels per byte).
    -- x[4|C]       switches in 1 16Kb page (3 pages) of graphics ram to C000 - FFFF. This overrides all MZ700 page switching functions.
    -- x[5|D]       switches out the graphics ram and returns to previous state.
    --
    CS_BANKSWITCH_n     <= '0'  when T80_IORQ_n='0'     and T80_WR_n = '0' and T80_A16(7 downto 4) = "1110"
                                else '1';
    CS_MZ700BS_n        <= '0'  when CONFIG(MZ700)='1'  and CS_BANKSWITCH_n = '0' and T80_A16(3) = '0'
                                else '1';
    CS_IO_E0_n          <= '0'  when CS_MZ700BS_n = '0' and T80_A16(2 downto 0) = "000"                                 -- IO E0 = 0000 -> 0FFF RAM,       D000 -> FFFF No Action
                                else '1';
    CS_IO_E1_n          <= '0'  when CS_MZ700BS_n = '0' and T80_A16(2 downto 0) = "001"                                 -- IO E1 = 0000 -> 0FFF No Action, D000 -> FFFF RAM
                                else '1';
    CS_IO_E2_n          <= '0'  when CS_MZ700BS_n = '0' and T80_A16(2 downto 0) = "010"                                 -- IO E2 = 0000 -> 0FFF ROM,       D000 -> FFFF No Action
                                else '1';
    CS_IO_E3_n          <= '0'  when CS_MZ700BS_n = '0' and T80_A16(2 downto 0) = "011"                                 -- IO E3 = 0000 -> 0FFF No Action, D000 -> FFFF VRAM + IO Ports
                                else '1';
    CS_IO_E4_n          <= '0'  when CS_MZ700BS_n = '0' and T80_A16(2 downto 0) = "100"                                 -- IO E4 = 0000 -> 0FFF ROM,       D000 -> FFFF VRAM + IO Ports
                                else '1';
    CS_IO_E5_n          <= '0'  when CS_MZ700BS_n = '0' and T80_A16(2 downto 0) = "101"                                 -- IO E5 = 0000 -> 0FFF No Action, D000 -> FFFF Inhibit
                                else '1';
    CS_IO_E6_n          <= '0'  when CS_MZ700BS_n = '0' and T80_A16(2 downto 0) = "110"                                 -- IO E6 = 0000 -> 0FFF No Action, D000 -> FFFF Unlock Inhibit
                                else '1';
    CS_IO_GFB_ni        <= '0'  when T80_IORQ_n   = '0' and T80_A16(7 downto 3) = CONFIG(GRAMIOADDR) and T80_WR_n = '0' -- IO Range for Graphics framebuffer register controlled by mctrl register.
                                else '1';
    CS_IO_GRAMENABLE_n  <= '0'  when CS_IO_GFB_ni = '0' and T80_A16(2 downto 0) = "100"                                 -- IO Addr base+4 sets C000 -> FFFF map to Graphics RAM.
                           else '1';
    CS_IO_GRAMDISABLE_n <= '0'  when CS_IO_GFB_ni = '0' and T80_A16(2 downto 0) = "101"                                 -- IO Addr base+5 sets C000 -> FFFF revert to previous mode.
                           else '1';

    -- Send signals to module interface.
    --
    CS_ROM_n            <= CS_ROM_ni;
    CS_RAM_n            <= CS_RAM_ni;
    CS_VRAM_n           <= CS_VRAM_ni;
    CS_MEM_G_n          <= CS_E_ni;
    CS_GRAM_n           <= CS_GRAM_ni;
    CS_IO_GFB_n         <= CS_IO_GFB_ni;

    -- MZ80A/1200 Memory Swap - swap rom out and ram in.
    --
    process( MZ_RESET, CS_ESWP_n ) begin
        if(MZ_RESET = '1') then
            MZ_MEMORY_SWAP            <= '0';
        elsif(CS_ESWP_n'event and CS_ESWP_n='0') then
            if(T80_A16(4 downto 2) = "011") then
                MZ_MEMORY_SWAP        <= '1';
            elsif(T80_A16(4 downto 2) = "100") then
                MZ_MEMORY_SWAP        <= '0';
            end if;
        end if;
    end process;

    -- MZ700 - Latch wether to enable RAM or ROM at 0000->0FFF.
    --
    process( MZ_RESET, CLKBUS(CKMASTER), CS_IO_E0_n, CS_IO_E2_n, CS_IO_E4_n ) begin
        if(MZ_RESET = '1') then
            MZ_LOW_RAM_ENABLE         <= '0';

        elsif(CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1') then

            if CLKBUS(CKENCPU) = '1' then

                if(CS_IO_E0_n = '0') then
                    MZ_LOW_RAM_ENABLE <= '1';
    
                elsif(CS_IO_E2_n = '0') then
                    MZ_LOW_RAM_ENABLE <= '0';
    
                elsif(CS_IO_E4_n = '0') then
                    MZ_LOW_RAM_ENABLE <= '0';
                end if;
            end if;
        end if;
    end process;

    -- MZ700 - Latch wether to enable I/O or RAM at D000->FFFF.
    --
    process( MZ_RESET, CLKBUS(CKMASTER), CS_IO_E1_n, CS_IO_E3_n, CS_IO_E4_n, MZ_HIGH_RAM_INHIBIT ) begin
        if(MZ_RESET = '1') then
            MZ_HIGH_RAM_ENABLE        <= '0';
            MZ_INHIBIT_RESET          <= '0';

        elsif(CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1') then

            if CLKBUS(CKENCPU) = '1' then

                if(CS_IO_E1_n = '0' and MZ_HIGH_RAM_INHIBIT = '0') then
                    MZ_HIGH_RAM_ENABLE  <= '1';
    
                elsif(CS_IO_E3_n = '0' and MZ_HIGH_RAM_INHIBIT = '0') then
                    MZ_HIGH_RAM_ENABLE  <= '0';
    
                elsif(CS_IO_E4_n = '0') then
                    MZ_HIGH_RAM_ENABLE  <= '0';
                    MZ_INHIBIT_RESET    <= '1';
    
                elsif(MZ_HIGH_RAM_INHIBIT = '0' and MZ_INHIBIT_RESET = '1') then
                    MZ_INHIBIT_RESET    <= '0';
                end if;
            end if;
        end if;
    end process;

    -- MZ700 - Latch wether to inhibit all functionality at D000->FFFF.
    --
    process( MZ_RESET, CLKBUS(CKMASTER), CS_IO_E5_n, CS_IO_E6_n, MZ_INHIBIT_RESET ) begin
        if(MZ_RESET = '1') then
            MZ_HIGH_RAM_INHIBIT         <= '0';

        elsif(CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1') then

            if CLKBUS(CKENCPU) = '1' then

                if(CS_IO_E5_n = '0') then
                    MZ_HIGH_RAM_INHIBIT <= '1';

                elsif(CS_IO_E6_n = '0' or MZ_INHIBIT_RESET = '1') then
                    MZ_HIGH_RAM_INHIBIT <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Graphics Ram - Latch wether to enable Graphics RAM page from C000 - FFFF.
    --
    process( MZ_RESET, CLKBUS(CKMASTER), CS_IO_GRAMENABLE_n, CS_IO_GRAMDISABLE_n ) begin
        if(MZ_RESET = '1') then
            MZ_GRAM_ENABLE              <= '0';

        elsif(CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1') then

            if CLKBUS(CKENCPU) = '1' then

                if(CS_IO_GRAMENABLE_n = '0') then
                    MZ_GRAM_ENABLE      <= '1';

                elsif(CS_IO_GRAMDISABLE_n = '0') then
                    MZ_GRAM_ENABLE      <= '0';

                end if;
            end if;
        end if;
    end process;

    --
    -- Cursor Base Clock  
    --
    process( CLKBUS(CKMASTER), T80_RST_n )
        variable TCOUNT : std_logic_vector(15 downto 0);
    begin
        if T80_RST_n = '0' then
            TCOUNT          := (others=>'0');

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1' then
            if CLKBUS(CKENPERIPH) = '1' then
                if( TCOUNT = 18371 ) then
                    TCOUNT      := (others=>'0');
                    CURSOR_CLK  <= not CURSOR_CLK;
                else
                    TCOUNT      := TCOUNT + '1';
                end if;
            end if;
        end if;
    end process;

    --
    -- Cursor blink Clock
    --
    process( CURSOR_CLK, CURSOR_RESET ) begin
        if( CURSOR_RESET='0' ) then
            CCOUNT           <= (others => '0');
        elsif( CURSOR_CLK'event and CURSOR_CLK = '1' ) then
            if( CCOUNT = 18 ) then
                CCOUNT       <=(others=>'0');
                CURSOR_BLINK <= not CURSOR_BLINK;
            else
                CCOUNT       <= CCOUNT+'1';
            end if;
        end if;
    end process;

    --
    -- Sound gate control
    --
    process( CLKBUS(CKMASTER), T80_WR_n, CS_E2_n, T80_RST_n ) begin
        if( T80_RST_n = '0' ) then
            SOUND_ENABLE     <= '0';

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER) = '1' then

            if CLKBUS(CKENPERIPH) = '1' and T80_WR_n = '0' and CS_E2_n = '0' then
                SOUND_ENABLE <= T80_DO(0);
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

    -- The signal coming out of the 8254 is not a square wave and twice the frequency. The addition of a flip-flop to divide the
    -- frequency by 2 results in a square wave of the correct audio frequency.
    process( SOUND_PULSE_X2 ) begin
        if( SOUND_PULSE_X2'event and SOUND_PULSE_X2 = '1' ) then
            SOUND <= not SOUND;
        end if;
    end process;

    -- MZ80 BLNK signal, enabled by VGATE being active and HBLANK pulsing. If HBLANK stops pulsing for more
    -- than 32ms, then BLNK goes inactive.
    --
    process( CLKBUS(CKMASTER), T80_RST_n )
        variable TCOUNT     : std_logic_vector(6 downto 0);
        variable HBLANKLAST : std_logic;
    begin
        if T80_RST_n = '0' then
            BLNK_n          <= '1';
            TCOUNT          := (others=>'0');

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1' then

            if CLKBUS(CKENPERIPH) = '1' then
                -- If HBLANK goes active the first time or is retriggered, reset counter and set BLANKING active.
                if (HBLANK = '1' and TCOUNT = 0) or (HBLANK = '1' and HBLANKLAST = '0') then
                    TCOUNT      := "0000001";
                    BLNK_n      <= '0';

                -- If not retriggered and we get to the end of the count (32ms) then turn off the BLANKING signal.
                elsif TCOUNT = 63 then
                    TCOUNT      := (others=>'0');
                    BLNK_n      <= '1';
                else
                    TCOUNT      := TCOUNT + '1';
                end if;

                -- Remember last state so we can retrigger.
                HBLANKLAST := HBLANK;
            end if;
        end if;
    end process;

    -- Try state register read, LS124 in MZ80A, LS367 in MZZ700. On MZ700 this register also inputs the
    -- Joystick readings, yet to be implemented.
    --
    DO367(0)          <= CURSOR_CLK;
    DO367(7)          <= not HBLANK  when CONFIG(MZ700) = '1'
                         else
                         '1'         when CONFIG(MZ_A)  = '1' and (BLNK_n = '0' and VGATE_ni = '0')
                         else '1';
    DO367(6 downto 1) <= (others=>'1');

    -- Video Output.
    --
    VGATE_n    <= VGATE_ni;

    -- Only enable debugging LEDS if enabled in the config package.
    --
    DEBUG80B: if DEBUG_ENABLE = 1 generate
        -- A simple 1*cpufreq second pulse to indicate accuracy of CPU frequency for debug purposes..
        --
        process (SYSTEM_RESET, CLKBUS(CKMASTER))
            variable cnt : integer range 0 to 1999999 := 0;
        begin
            if SYSTEM_RESET = '1' then
                PULSECPU         <= '0';
                cnt              := 0;
            elsif rising_edge(CLKBUS(CKMASTER)) then
                if CLKBUS(CKENCPU) = '1' then
                    cnt          := cnt + 1;
                    if cnt = 0 then
                        PULSECPU <= not PULSECPU;
                    end if;
                end if;
            end if;
        end process;

        -- Debug leds.
        --
        DEBUG_STATUS_LEDS(0)  <= CS_VRAM_ni;
        DEBUG_STATUS_LEDS(1)  <= CS_E_ni;
        DEBUG_STATUS_LEDS(2)  <= CS_E0_n;
        DEBUG_STATUS_LEDS(3)  <= CS_E1_n;
        DEBUG_STATUS_LEDS(4)  <= CS_E2_n;
        DEBUG_STATUS_LEDS(5)  <= CS_ESWP_n;
        DEBUG_STATUS_LEDS(6)  <= CS_ROM_ni;
        DEBUG_STATUS_LEDS(7)  <= CS_RAM_ni;
        --
        DEBUG_STATUS_LEDS(8)  <= CS_BANKSWITCH_n;
        DEBUG_STATUS_LEDS(9)  <= CS_IO_E0_n;
        DEBUG_STATUS_LEDS(10) <= CS_IO_E1_n;
        DEBUG_STATUS_LEDS(11) <= CS_IO_E2_n;
        DEBUG_STATUS_LEDS(12) <= CS_IO_E3_n;
        DEBUG_STATUS_LEDS(13) <= CS_IO_E4_n;
        DEBUG_STATUS_LEDS(14) <= CS_IO_E5_n;
        DEBUG_STATUS_LEDS(15) <= CS_IO_E6_n;
        --
        DEBUG_STATUS_LEDS(16) <= CS_IO_GRAMENABLE_n;
        DEBUG_STATUS_LEDS(17) <= CS_IO_GRAMDISABLE_n;
        DEBUG_STATUS_LEDS(18) <= CS_IO_GFB_ni;
        DEBUG_STATUS_LEDS(19) <= CS_GRAM_ni;
        DEBUG_STATUS_LEDS(20) <= MZ_GRAM_ENABLE;
        DEBUG_STATUS_LEDS(21) <= '0';
        DEBUG_STATUS_LEDS(22) <= '0';
        DEBUG_STATUS_LEDS(23) <= '0';
        --
        DEBUG_STATUS_LEDS(24) <= PULSECPU;
        DEBUG_STATUS_LEDS(25) <= T80_INT_ni;
        DEBUG_STATUS_LEDS(26) <= INTMSK;
        DEBUG_STATUS_LEDS(27) <= MZ_MEMORY_SWAP;
        DEBUG_STATUS_LEDS(28) <= MZ_LOW_RAM_ENABLE;
        DEBUG_STATUS_LEDS(29) <= MZ_HIGH_RAM_ENABLE;
        DEBUG_STATUS_LEDS(30) <= MZ_HIGH_RAM_INHIBIT;
        DEBUG_STATUS_LEDS(31) <= MZ_INHIBIT_RESET;
        --
        DEBUG_STATUS_LEDS(32) <= '0';
        DEBUG_STATUS_LEDS(33) <= '0';
        DEBUG_STATUS_LEDS(34) <= '0';
        DEBUG_STATUS_LEDS(35) <= '0';
        DEBUG_STATUS_LEDS(36) <= CURSOR_BLINK;
        DEBUG_STATUS_LEDS(37) <= SOUND_ENABLE;
        DEBUG_STATUS_LEDS(38) <= MZ_RTC_CASCADE_CLK;
        DEBUG_STATUS_LEDS(39) <= PULSECPU;
        --
        -- LEDS 40 .. 112 are available.
        DEBUG_STATUS_LEDS(111 downto 40) <= (others => '0');
    end generate;
end rtl;
