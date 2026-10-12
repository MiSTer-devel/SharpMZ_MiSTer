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
use ieee.numeric_std.all;
use pkgs.config_pkg.all;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;
use work.vc_rams_pkg.all;

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
          CPU_DIN            : in  std_logic_vector(7 downto 0) := (others => '1'); -- What the CPU reads (opcodes: the PIO decodes RETI).

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
          AUDIO_PSG          : out std_logic_vector(13 downto 0);        -- MZ-800 PSG (SN76489) mix, unsigned. MZ-1500: PSG0, left.
          AUDIO_PSG_R        : out std_logic_vector(13 downto 0);        -- MZ-1500 PSG1 (right); the MZ-800 PSG otherwise.

          -- MZ-1500 PCG and display registers.
          M15_PCG_CS         : out std_logic;                            -- CPU access to a PCG plane (OUT E5 1-3: D000-EFFF).
          M15_PCG_PLANE      : out std_logic_vector(1 downto 0);         -- Plane 0-2.
          M15_CG_CS          : out std_logic;                            -- CPU read of the CG ROM (OUT E5 0: D000-EFFF).
          M15_PCG_DI         : in  std_logic_vector(7 downto 0);         -- PCG read data.
          M15_DMD            : out std_logic_vector(1 downto 0);         -- Port F0: 0 PCG on, 1 priority (0 = BPF, 1 = BFP).
          M15_PAL            : out std_logic_vector(23 downto 0);        -- Port F1: colour of PCG index i in bits 3i+2..3i.

          -- Joysticks, MiSTer order: 5 fire 2, 4 fire 1, 3 up, 2 down, 1 left, 0 right (1 = active).
          JOY0               : in  std_logic_vector(5 downto 0);
          JOY1               : in  std_logic_vector(5 downto 0);
          JOY_1X03           : in  std_logic;                            -- MZ-700/1500: MZ-1X03 joysticks connected.
          RAMDISK_EN         : in  std_logic;                            -- MZ-800: 64 KB RAM disk board at E9-EB, F8-FA.
          PRN_EN             : in  std_logic;                            -- Printer connected (OSD Printer: UART).
          PRN_RDA            : in  std_logic;                            -- Printer busy / acknowledge (high).
          PRN_DATA           : out std_logic_vector(7 downto 0);         -- Printer data (MZ-700 FF, MZ-800/1500 PIO port B).
          PRN_STB            : out std_logic;                            -- Printer strobe RDP (MZ-700 FE bit 7, MZ-800/1500 PA7).

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
          HSYNC_n            : in  std_logic;                            -- Horizontal Sync (MZ-800 status).
          VSYNC_n            : in  std_logic;                            -- Vertical Sync (MZ-800 status).

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
signal JOY_CNT               :     unsigned(13 downto 0);                -- CPU T-states since the start of vertical blank.
signal JOY_VB_LAST           :     std_logic;
signal JOY_E008              :     std_logic_vector(4 downto 1);         -- MZ-1X03 bits of E008.
signal M8_JOY_DO             :     std_logic_vector(7 downto 0);         -- MZ-800 joystick ports F0/F1.
signal RD_SEL                :     std_logic;                            -- RAM disk data port (EA, F9 read; EA, FA write).
signal RD_SEL_LAST           :     std_logic;
signal RD_OFF                :     unsigned(15 downto 0);
signal RD_WE                 :     std_logic;
signal RD_DO                 :     std_logic_vector(7 downto 0);
signal RD_Q                  :     std_logic_vector(7 downto 0);
signal RD_DI                 :     std_logic_vector(7 downto 0);
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
signal SOUND_PULSE_X2_LAST   :     std_logic := '0';
signal CS_ESWP_LAST_n        :     std_logic;
signal CURSOR_TICK          :     std_logic := '0';
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
-- MZ-800
--
signal M8                    :     std_logic;                               -- Machine is an MZ-800.
signal M8_700                :     std_logic;                               -- MZ-800 in MZ-700 mode (DMD bit 3).
signal M8_DMD                :     std_logic_vector(3 downto 0);            -- Copy of the GDG display mode register (OUT CE).
signal M8_ROM0               :     std_logic;                               -- Memory map: ROM at 0000-0FFF.
signal M8_ROM1               :     std_logic;                               -- Memory map: CG ROM at 1000-1FFF.
signal M8_CGV                :     std_logic;                               -- Memory map: CG-RAM at C000 (700 mode) / VRAM at 8000 (800 mode).
signal M8_ROME               :     std_logic;                               -- Memory map: ROM at E000-FFFF (and VRAM at D000 in 700 mode).
signal M8_PROH               :     std_logic;                               -- Memory map: "prohibited", E000-FFFF reads 1A.
signal M8_E00X               :     std_logic;                               -- Address is E000-E00F.
signal M8_LOROM              :     std_logic;                               -- 0000-1FFF is mapped to ROM.
signal M8_HIGH               :     std_logic;                               -- E000-FFFF is not RAM.
signal M8_CS_E_n             :     std_logic;                               -- 700 mode memory mapped ports E000-E00F.
signal M8_CS_ROM_n           :     std_logic;
signal M8_CS_RAM_n           :     std_logic;
signal M8_CS_VRAM_n          :     std_logic;
signal M8_CS_GRAM_n          :     std_logic;
signal M8_IO                 :     std_logic_vector(7 downto 0);            -- I/O port address when IORQ is active, else 00.
signal M8_STATUS             :     std_logic_vector(7 downto 0);            -- IN CE status.
signal M8_TEMPO              :     std_logic;
signal M8_TEMPO_CNT          :     integer range 0 to 228;
signal M8_HBLANK_LAST        :     std_logic;
signal M8_PSG_CS_n           :     std_logic;
signal M15                   :     std_logic;                            -- MZ-1500 (CONFIG(MZ700) is also set).
signal M15_SPEC              :     std_logic_vector(2 downto 0);         -- OUT E5: 1 = CG ROM, 2-4 = PCG plane 1-3 at D000-EFFF.
signal M15_SPEC_ON           :     std_logic;
signal M15_WIN               :     std_logic;                            -- CPU access inside the special window.
signal M15_DMD_R             :     std_logic_vector(1 downto 0);
signal M15_PAL_R             :     std_logic_vector(23 downto 0);
signal M15_PSG1_CS_n         :     std_logic;
signal M15_PSG1_MIX          :     unsigned(13 downto 0);
signal M8_PIO_CS             :     std_logic;
signal M8_PIO_DO             :     std_logic_vector(7 downto 0);
signal M8_PIO_VOE            :     std_logic;
signal M8_PIO_INT_n          :     std_logic;
signal M8_PIO_PA             :     std_logic_vector(7 downto 0);
signal M8_PIO_PAO            :     std_logic_vector(7 downto 0);
signal M8_PIO_PBO            :     std_logic_vector(7 downto 0);
signal M7_PRN_DATA           :     std_logic_vector(7 downto 0);            -- MZ-700 printer port FF.
signal M7_PRN_CTRL           :     std_logic_vector(7 downto 0);            -- MZ-700 printer port FE: 7 RDP, 6 IRT.
signal M7_PRN                :     std_logic;                               -- MZ-700 model (not the MZ-800/1500).
signal M8_PSG_MIX            :     unsigned(13 downto 0);
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
            GATE0            => SOUND_ENABLE,                            -- E008 bit 0 on every model; the MZ-800 only decodes E008 in 700 mode (as mz800emu).
            OUT0             => SOUND_PULSE_X2,
            CLK1             => CLKBUS(CKRTC),
            GATE1            => '1',
            OUT1             => MZ_RTC_CASCADE_CLK,
            CLK2             => MZ_RTC_CASCADE_CLK,
            GATE2            => '1',
            OUT2             => INTX
      );

    -- MZ-800 PSG (SN76489) at port F2, write only. Its clock is fixed at 3.54688 MHz so turbo does not change the pitch.
    --
    PSG0 : entity work.sn76489_audio
        generic map (
            FAST_IO_G        => '1',                                     -- No wait states, as mz800emu.
            MIN_PERIOD_CNT_G => 6
        )
        port map (
            clk_i            => CLKBUS(CKMASTER),
            en_clk_psg_i     => CLKBUS(CKENPSG),
            ce_n_i           => M8_PSG_CS_n,
            wr_n_i           => T80_WR_n,
            ready_o          => open,
            data_i           => T80_DO,
            ch_a_o           => open,
            ch_b_o           => open,
            ch_c_o           => open,
            noise_o          => open,
            mix_audio_o      => M8_PSG_MIX,
            pcm14s_o         => open
        );
    M8_PSG_CS_n              <= '0' when M8 = '1' and M8_IO = X"F2" else
                                '0' when M15 = '1' and (M8_IO = X"F2" or M8_IO = X"E9") else '1';       -- MZ-1500: F2 left, E9 both

    -- MZ-1500 second PSG (right channel) at F3; E9 writes both.
    --
    PSG1 : entity work.sn76489_audio
        generic map (
            FAST_IO_G        => '1',
            MIN_PERIOD_CNT_G => 6
        )
        port map (
            clk_i            => CLKBUS(CKMASTER),
            en_clk_psg_i     => CLKBUS(CKENPSG),
            ce_n_i           => M15_PSG1_CS_n,
            wr_n_i           => T80_WR_n,
            ready_o          => open,
            data_i           => T80_DO,
            ch_a_o           => open,
            ch_b_o           => open,
            ch_c_o           => open,
            noise_o          => open,
            mix_audio_o      => M15_PSG1_MIX,
            pcm14s_o         => open
        );
    M15_PSG1_CS_n            <= '0' when M15 = '1' and (M8_IO = X"F3" or M8_IO = X"E9") else '1';

    -- MZ-800 Z80 PIO at FC-FF. Port A: 0 printer /RDA, 1 printer STA, 4 /CTC0, 5 /VBLN; CP/M runs its
    -- keyboard and clock from the /VBLN bit mode interrupt (IM 2).
    --
    PIO800 : entity work.mz800_pio
        port map (
            CLK              => CLKBUS(CKMASTER),
            RESET            => MZ_RESET or not (M8 or M15),
            CS               => M8_PIO_CS,
            A                => T80_A16(1 downto 0),
            RD_n             => T80_RD_n,
            WR_n             => T80_WR_n,
            IORQ_n           => T80_IORQ_n,
            M1_n             => T80_M1_n,
            RD_n_CPU         => T80_RD_n,
            CPU_DIN          => CPU_DIN,
            DI               => T80_DO,
            DO               => M8_PIO_DO,
            VECTOR_OE        => M8_PIO_VOE,
            INT_n            => M8_PIO_INT_n,
            PA_IN            => M8_PIO_PA,
            PB_IN            => x"FF",
            PA_OUT           => M8_PIO_PAO,
            PB_OUT           => M8_PIO_PBO
        );
    M8_PIO_CS                <= '1' when (M8 = '1' or M15 = '1') and M8_IO(7 downto 2) = "111111" else '0';   -- MZ-800 and MZ-1500
    -- PA0 RDA: always ready with no printer (as before), the printer's acknowledge with one. PA1 STA high: paper.
    M8_PIO_PA                <= "11" & (not VBLANK) & (not SOUND_PULSE_X2) & "001" & (PRN_RDA and PRN_EN);

    -- Printer port. MZ-800/1500: Z80 PIO port B data, PA7 RDP. MZ-700: the plotter/printer port at I/O FF (data)
    -- and FE (write: 7 RDP, 6 IRT; read: 0 RDA, 1 STA, 2-3 low), as MZ-700 BASIC 1Z-013B drives it (2871): wait
    -- for FE AND 0D = 0, OUT FF, OUT FE 80, wait for bit 0 high, OUT FE 0. Without a printer FE reads FF, as before.
    M7_PRN                   <= '1' when CONFIG(MZ700) = '1' and M8 = '0' and M15 = '0' else '0';
    process( MZ_RESET, CLKBUS(CKMASTER) )
    begin
        if MZ_RESET = '1' then
            M7_PRN_CTRL      <= (others => '0');
        elsif rising_edge(CLKBUS(CKMASTER)) then
            if M7_PRN = '1' and T80_WR_n = '0' and M8_IO = X"FF" then
                M7_PRN_DATA  <= T80_DO;
            end if;
            if M7_PRN = '1' and T80_WR_n = '0' and M8_IO = X"FE" then
                M7_PRN_CTRL  <= T80_DO;
            end if;
        end if;
    end process;
    PRN_DATA                 <= M8_PIO_PBO    when M8 = '1' or M15 = '1' else M7_PRN_DATA;
    PRN_STB                  <= M8_PIO_PAO(7) when M8 = '1' or M15 = '1' else M7_PRN_CTRL(7) and M7_PRN;
    AUDIO_PSG                <= std_logic_vector(M8_PSG_MIX)   when (M8 = '1' or M15 = '1') and CONFIG(AUDIOSRC) = '0' else (others => '0');
    AUDIO_PSG_R              <= std_logic_vector(M15_PSG1_MIX) when M15 = '1' and CONFIG(AUDIOSRC) = '0' else
                                std_logic_vector(M8_PSG_MIX)   when M8 = '1'  and CONFIG(AUDIOSRC) = '0' else (others => '0');

    -- Parent signals onto local wires.
    --
    T80_BUSRQ_n              <= '1';
    T80_NMI_n                <= '1';
    T80_WAIT_n               <= '1';
    MZ_RESET                 <= SYSTEM_RESET;

    --
    -- MZ-80A - Mask interrupt from 8254 if INTMSK low.
    -- MZ-80K - Interrupt is from 8254 direct.
    T80_INT_ni               <= '0' when ((CONFIG(MZ_A)='1' or CONFIG(MZ700) = '1' or M8 = '1') and INTX='1' and INTMSK='1') or ((CONFIG(MZ_KC)='1' and INTX='1'))
                                     or ((M8 = '1' or M15 = '1') and M8_PIO_INT_n = '0')
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
    T80_DI                   <= M8_PIO_DO when (M8 = '1' or M15 = '1') and (M8_PIO_VOE = '1' or (M8_PIO_CS = '1' and T80_RD_n = '0'))   -- MZ-800/1500 Z80 PIO, and its vector
                                else
                                M15_PCG_DI when M15_WIN = '1' and T80_RD_n = '0'                                     -- MZ-1500 PCG plane or CG ROM
                                else
                                M8_JOY_DO when M8 = '1' and T80_RD_n = '0' and M8_IO(7 downto 1) = "1111000"             -- MZ-800 joysticks F0/F1
                                else
                                "1111001" & PRN_RDA when M7_PRN = '1' and PRN_EN = '1' and T80_RD_n = '0' and M8_IO = X"FE"  -- MZ-700 printer status
                                else
                                RD_DO     when RD_SEL = '1' and T80_RD_n = '0'                                          -- MZ-800 RAM disk
                                else
                                X"1A"     when M8 = '1' and T80_MREQ_n = '0' and T80_RD_n = '0' and T80_A16(15 downto 13) = "111" and M8_PROH = '1'
                                else
                                X"1A"     when M8 = '1' and M8_CS_E_n = '0' and T80_RD_n = '0' and T80_A16(3 downto 0) > "1000"
                                else
                                (not HBLANK) & "00000" & '0' & M8_TEMPO
                                          when M8 = '1' and M8_CS_E_n = '0' and T80_RD_n = '0' and T80_A16(3 downto 0) = "1000"
                                else
                                M8_STATUS when M8 = '1' and M8_IO = X"CE" and T80_RD_n = '0'
                                else
                                DOPPI     when CS_E0_n  ='0' and T80_RD_n = '0'                                -- Read from 8255
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
    CS_VRAM_ni          <= '0'  when ( (T80_A16(15 downto 12)="1101" and T80_MREQ_n = '0' and MZ_GRAM_ENABLE = '0' and M15_SPEC_ON = '0')
                                       and
                                       ( (CONFIG(MZ_KC)='1' or CONFIG(MZ_A)='1')
                                         or
                                         (CONFIG(MZ700)='1' and MZ_HIGH_RAM_ENABLE='0' and MZ_HIGH_RAM_INHIBIT='0')
                                       )
                                     ) 
                                else '1';
    -- E000 - EFFF
    CS_E_ni             <= '0'  when ( (T80_A16(15 downto 12)="1110" and T80_MREQ_n = '0' and MZ_GRAM_ENABLE = '0' and M15_SPEC_ON = '0')
                                       and
                                       ( (CONFIG(MZ_KC)='1' or CONFIG(MZ_A)='1')
                                         or
                                         (CONFIG(MZ700)='1' and MZ_HIGH_RAM_ENABLE='0' and MZ_HIGH_RAM_INHIBIT='0')
                                       )
                                     )
                                else '1';
    -- Sub division E000 - E200
    CS_E0_n             <= '0'  when M8 = '1' and M8_CS_E_n = '0' and T80_A16(3 downto 2) = "00"                                          -- MZ-800 700 mode 8255
                                else
                                '0'  when M8 = '1' and M8_700 = '0' and M8_IO(7 downto 2) = "110100"                                         -- MZ-800 800 mode 8255 (D0-D3)
                                else
                                '0'  when M8 = '0' and CS_E_ni = '0' and T80_A16(11 downto 2) = "0000000000"                                 -- 8255
                                else '1';
    CS_E1_n             <= '0'  when M8 = '1' and M8_CS_E_n = '0' and T80_A16(3 downto 2) = "01"                                          -- MZ-800 700 mode 8254
                                else
                                '0'  when M8 = '1' and M8_700 = '0' and M8_IO(7 downto 2) = "110101"                                         -- MZ-800 800 mode 8254 (D4-D7)
                                else
                                '0'  when M8 = '0' and CS_E_ni = '0' and T80_A16(11 downto 2) = "0000000001"                                 -- 8254
                                else '1';
    CS_E2_n             <= '0'  when M8 = '1' and M8_CS_E_n = '0' and T80_A16(3 downto 0) = "1000"                                        -- MZ-800 700 mode E008
                                else
                                '0'  when M8 = '0' and CS_E_ni = '0' and T80_A16(11 downto 2) = "0000000010"                                 -- LS367
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
                                         M15_SPEC_ON = '0'                                                                                -- MZ-1500: not under the CG/PCG window.
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
    CS_ROM_n            <= M8_CS_ROM_n  when M8 = '1' else CS_ROM_ni;
    CS_RAM_n            <= M8_CS_RAM_n  when M8 = '1' else CS_RAM_ni;
    CS_VRAM_n           <= M8_CS_VRAM_n when M8 = '1' else CS_VRAM_ni;
    CS_MEM_G_n          <= M8_CS_E_n    when M8 = '1' else CS_E_ni;
    CS_GRAM_n           <= M8_CS_GRAM_n when M8 = '1' else CS_GRAM_ni;

    --
    -- MZ-800 memory map (mz800emu / MZ-800 Technical Reference Manual).
    --
    -- 0000-0FFF ROM (M8_ROM0) or RAM.       1000-1FFF CG ROM (M8_ROM1) or RAM.
    -- 8000-9FFF VRAM in 800 mode (M8_CGV), A000-BFFF too when 640 wide (DMD bit 2), else RAM.
    -- C000-CFFF CG-RAM in 700 mode (M8_CGV) else RAM.  D000-DFFF VRAM in 700 mode (M8_ROME) else RAM.
    -- E000-FFFF ROM (M8_ROME) or RAM. With ROM mapped, E000-E00F is the memory mapped ports in 700 mode
    --           (E000-E008, E009-E00F read 1A) and reads FF in 800 mode. M8_PROH makes all of E000-FFFF read 1A.
    --
    M8                  <= CONFIG(MZ800);
    M15                 <= CONFIG(IS_MZ1500);

    -- MZ-1500 special window (mz800emu mz1500_memory.c): OUT E5 n maps the CG ROM (n=0) or PCG plane n (1-3) over
    -- D000-EFFF while the upper ROM area is mapped, hiding VRAM, the E000 ports and the E800 ROM; E3, E4 and E6 unmap it.
    -- F0 is the display mode (0: PCG on, 1: priority), F1 the PCG palette (bits 6-4 index, 2-0 colour).
    M15_SPEC_ON         <= '1' when M15 = '1' and M15_SPEC /= "000" and MZ_HIGH_RAM_ENABLE = '0' else '0';
    M15_WIN             <= '1' when M15_SPEC_ON = '1' and T80_MREQ_n = '0' and (T80_A16(15 downto 12) = "1101" or T80_A16(15 downto 12) = "1110") else '0';
    M15_PCG_CS          <= '1' when M15_WIN = '1' and M15_SPEC(2 downto 1) /= "00" else '0';
    M15_CG_CS           <= '1' when M15_WIN = '1' and M15_SPEC = "001" else '0';
    M15_PCG_PLANE       <= std_logic_vector(unsigned(M15_SPEC(1 downto 0)) - 2) when M15_SPEC(2) = '0' else "10";
    M15_DMD             <= M15_DMD_R;
    M15_PAL             <= M15_PAL_R;

    process( MZ_RESET, CLKBUS(CKMASTER) ) begin
        if MZ_RESET = '1' then
            M15_SPEC   <= "000";
            M15_DMD_R  <= "00";
            M15_PAL_R  <= (others => '0');
        elsif rising_edge(CLKBUS(CKMASTER)) then
            if CLKBUS(CKENCPU) = '1' and M15 = '1' then
                if CS_IO_E5_n = '0' then
                    M15_SPEC <= std_logic_vector(unsigned('0' & T80_DO(1 downto 0)) + 1);
                elsif CS_IO_E6_n = '0' or CS_IO_E3_n = '0' or CS_IO_E4_n = '0' then
                    M15_SPEC <= "000";
                end if;
                if T80_IORQ_n = '0' and T80_WR_n = '0' and T80_M1_n = '1' then
                    if T80_A16(7 downto 0) = X"F0" then
                        M15_DMD_R <= T80_DO(1 downto 0);
                    elsif T80_A16(7 downto 0) = X"F1" then
                        for i in 0 to 7 loop
                            if unsigned(T80_DO(6 downto 4)) = i then
                                M15_PAL_R(i*3+2 downto i*3) <= T80_DO(2 downto 0);
                            end if;
                        end loop;
                    end if;
                end if;
            end if;
        end if;
    end process;
    M8_700              <= M8_DMD(3);
    M8_E00X             <= '1'  when T80_A16(15 downto 4) = X"E00" else '0';
    M8_IO               <= T80_A16(7 downto 0) when T80_IORQ_n = '0' and T80_M1_n = '1' else X"00";
    M8_LOROM            <= '1'  when (T80_A16(15 downto 12) = "0000" and M8_ROM0 = '1') or (T80_A16(15 downto 12) = "0001" and M8_ROM1 = '1')
                                else '0';
    M8_HIGH             <= '1'  when T80_A16(15 downto 13) = "111" and (M8_ROME = '1' or (M8_PROH = '1' and T80_RD_n = '0'))
                                else '0';
    M8_CS_ROM_n         <= '0'  when T80_MREQ_n = '0' and (M8_LOROM = '1' or (M8_HIGH = '1' and M8_ROME = '1' and M8_E00X = '0' and (M8_PROH = '0' or T80_RD_n = '1')))
                                else '1';
    M8_CS_E_n           <= '0'  when T80_MREQ_n = '0' and M8_E00X = '1' and M8_ROME = '1' and M8_700 = '1' and (M8_PROH = '0' or T80_RD_n = '1')
                                else '1';
    M8_CS_VRAM_n        <= '0'  when T80_MREQ_n = '0' and M8_700 = '1' and ((T80_A16(15 downto 12) = "1101" and M8_ROME = '1') or (T80_A16(15 downto 12) = "1100" and M8_CGV = '1'))
                                else '1';
    M8_CS_GRAM_n        <= '0'  when T80_MREQ_n = '0' and M8_700 = '0' and M8_CGV = '1' and (T80_A16(15 downto 13) = "100" or (T80_A16(15 downto 13) = "101" and M8_DMD(2) = '1'))
                                else '1';
    M8_CS_RAM_n         <= '0'  when T80_MREQ_n = '0' and M8_LOROM = '0' and M8_HIGH = '0' and M8_CS_VRAM_n = '1' and M8_CS_GRAM_n = '1'
                                else '1';

    -- IN CE status: 7 /HBLNK, 6 /VBLNK, 5 /HSYNC, 4 /VSYNC, 2 CKSW, 1 mode switch, 0 TEMPO.
    M8_STATUS           <= (not HBLANK) & (not VBLANK) & HSYNC_n & VSYNC_n & '0' & '0' & CONFIG(MZ800_MODE) & M8_TEMPO;

    -- MZ-800 memory map register and DMD copy. OUT E0-E6 and IN E0/E1 change the map.
    --
    process( MZ_RESET, CLKBUS(CKMASTER) ) begin
        if MZ_RESET = '1' then
            M8_ROM0                   <= '1';
            M8_ROM1                   <= '1';
            M8_CGV                    <= '0';
            M8_ROME                   <= '1';
            M8_PROH                   <= '0';
            M8_DMD                    <= "1000";

        elsif rising_edge(CLKBUS(CKMASTER)) then
            if CLKBUS(CKENCPU) = '1' and M8 = '1' then
                if T80_WR_n = '0' then
                    case M8_IO is
                        when X"E0" => M8_ROM0 <= '0'; M8_ROM1 <= '0';
                        when X"E1" => M8_ROME <= '0';
                        when X"E2" => M8_ROM0 <= '1';
                        when X"E3" => M8_ROME <= '1';
                        when X"E4" =>
                            M8_ROM0           <= '1';
                            M8_ROME           <= '1';
                            M8_ROM1           <= not M8_700;
                            M8_CGV            <= not M8_700;
                        when X"E5" => M8_PROH <= '1';
                        when X"E6" => M8_PROH <= '0';
                        when X"CE" => M8_DMD  <= T80_DO(3 downto 0);
                        when others => null;
                    end case;
                elsif T80_RD_n = '0' then
                    case M8_IO is
                        when X"E0" => M8_ROM1 <= '1'; M8_CGV <= '1';
                        when X"E1" => M8_ROM1 <= '0'; M8_CGV <= '0';
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- TEMPO: about 34Hz, toggles every 229 lines.
    process( CLKBUS(CKMASTER) ) begin
        if rising_edge(CLKBUS(CKMASTER)) then
            M8_HBLANK_LAST            <= HBLANK;
            if HBLANK = '1' and M8_HBLANK_LAST = '0' then
                if M8_TEMPO_CNT = 228 then
                    M8_TEMPO_CNT      <= 0;
                    M8_TEMPO          <= not M8_TEMPO;
                else
                    M8_TEMPO_CNT      <= M8_TEMPO_CNT + 1;
                end if;
            end if;
        end if;
    end process;
    CS_IO_GFB_n         <= CS_IO_GFB_ni;

    -- MZ80A/1200 Memory Swap - swap rom out and ram in.
    --
    process( MZ_RESET, CLKBUS(CKMASTER) ) begin
        if(MZ_RESET = '1') then
            MZ_MEMORY_SWAP            <= '0';
            CS_ESWP_LAST_n            <= '1';
        elsif rising_edge(CLKBUS(CKMASTER)) then
            CS_ESWP_LAST_n            <= CS_ESWP_n;
            if CS_ESWP_n = '0' and CS_ESWP_LAST_n = '1' then     -- Falling edge of the swap chip select.
                if(T80_A16(4 downto 2) = "011") then
                    MZ_MEMORY_SWAP    <= '1';
                elsif(T80_A16(4 downto 2) = "100") then
                    MZ_MEMORY_SWAP    <= '0';
                end if;
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

                elsif(CS_IO_E5_n = '0' and M15 = '1') then                  -- MZ-1500: E5 also maps the upper ROM area.
                    MZ_HIGH_RAM_ENABLE  <= '0';
    
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

                if(CS_IO_E5_n = '0' and M15 = '0') then                     -- MZ-1500: E5 selects the CG/PCG window instead.
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
            CURSOR_TICK         <= '0';
            if CLKBUS(CKENPERIPH) = '1' then
                if( TCOUNT = 18371 ) then
                    TCOUNT      := (others=>'0');
                    CURSOR_CLK  <= not CURSOR_CLK;
                    CURSOR_TICK <= not CURSOR_CLK;                    -- Pulse where CURSOR_CLK rises.
                else
                    TCOUNT      := TCOUNT + '1';
                end if;
            end if;
        end if;
    end process;

    --
    -- Cursor blink Clock
    --
    process( CLKBUS(CKMASTER) ) begin
        if rising_edge(CLKBUS(CKMASTER)) then
            if( CURSOR_RESET='0' ) then
                CCOUNT           <= (others => '0');
            elsif( CURSOR_TICK = '1' ) then
                if( CCOUNT = 18 ) then
                    CCOUNT       <=(others=>'0');
                    CURSOR_BLINK <= not CURSOR_BLINK;
                else
                    CCOUNT       <= CCOUNT+'1';
                end if;
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

            -- Any clock of the write: a CPU write is shorter than the gap between CKENPERIPH pulses at some
            -- phases, and then E008 writes were lost (no beeper) depending on when the program started.
            if T80_WR_n = '0' and CS_E2_n = '0' then
                SOUND_ENABLE <= T80_DO(0);
            end if;
        end if;
    end process;

    -- Audio output. Choose between generated sound and CMT pulse audio.
    --
    AUDIO_L    <= (SOUND and (VGATE_ni or not M8)) when CONFIG(AUDIOSRC) = '0'            -- Sound Output Left (MZ-800: gated by PC0)
                  else
                  CMT_BUS_OUT(WRITEBIT);
    AUDIO_R    <= (SOUND and (VGATE_ni or not M8)) when CONFIG(AUDIOSRC) = '0'            -- Sound Output Right (MZ-800: gated by PC0)
                  else
                  CMT_BUS_OUT(READBIT);

    -- MZ-80K family: counter 0 runs from 2 MHz and a flip-flop halves its output. The MZ-700/800 clock counter 0 at
    -- 1.1088 MHz and use its mode 3 square wave directly: the monitor's BELL (count 04ECh) is 880 Hz, as documented.
    process( CLKBUS(CKMASTER) ) begin
        if rising_edge(CLKBUS(CKMASTER)) then
            SOUND_PULSE_X2_LAST <= SOUND_PULSE_X2;
            if CONFIG(MZ700) = '1' or M8 = '1' then
                SOUND <= SOUND_PULSE_X2;
            elsif SOUND_PULSE_X2 = '1' and SOUND_PULSE_X2_LAST = '0' then
                SOUND <= not SOUND;
            end if;
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
    DO367(6 downto 5) <= (others=>'1');
    DO367(4 downto 1) <= JOY_E008 when JOY_1X03 = '1' and CONFIG(MZ700) = '1' and M8 = '0' else (others => '1');

    -- MZ-1X03 joysticks (MZ-700, MZ-1500), as mz800emu's joymz-1x03.c: E008 bits 1-4 are JA1, JA2, JB1, JB2. While the
    -- picture is displayed they are the fire buttons (low = pressed); from the start of vertical blank each is low for
    -- 68 + 28 x position T-states (the stick's X or Y, 0-255), which the ROM measures with a counting loop. A MiSTer
    -- joystick is digital: left/up 0, centre 128, right/down 255.
    process(CLKBUS(CKMASTER)) begin
        if rising_edge(CLKBUS(CKMASTER)) then
            if CLKBUS(CKENCPU) = '1' then
                JOY_VB_LAST <= VBLANK;
                if VBLANK = '1' and JOY_VB_LAST = '0' then
                    JOY_CNT <= (others => '0');
                elsif JOY_CNT /= to_unsigned(16383, JOY_CNT'length) then
                    JOY_CNT <= JOY_CNT + 1;
                end if;
            end if;
        end if;
    end process;
    process(VBLANK, JOY0, JOY1, JOY_CNT)
        function pulse(cnt : unsigned; neg : std_logic; pos : std_logic) return std_logic is
            variable t : natural;
        begin
            if neg = '1' and pos = '0' then t := 68; elsif pos = '1' and neg = '0' then t := 68 + 255 * 28; else t := 68 + 128 * 28; end if;
            if cnt < t then return '0'; else return '1'; end if;
        end function;
    begin
        if VBLANK = '0' then
            JOY_E008 <= not JOY1(5) & not JOY1(4) & not JOY0(5) & not JOY0(4);
        else
            JOY_E008 <= pulse(JOY_CNT, JOY1(3), JOY1(2)) & pulse(JOY_CNT, JOY1(1), JOY1(0)) &
                        pulse(JOY_CNT, JOY0(3), JOY0(2)) & pulse(JOY_CNT, JOY0(1), JOY0(0));
        end if;
    end process;

    -- MZ-800 RAM disk board, the "standard" 64 KB one of mz800emu (hw-generic/ramdisk): OUT EB sets the offset (high
    -- byte from the address bus, OUT (C),A), EA reads or writes the byte there and moves on, F9 reads and FA writes the
    -- same way, IN F8 resets the offset. E9 selects a 64 KB bank, which a 64 KB board ignores.
    -- The data is stored inverted so that the board starts out reading FF, as mz800emu's: the IPL boots a "RAM file"
    -- whose 9th byte equals the number of 1 bits in the first eight, which an all-zero board passes.
    RD_DI  <= not T80_DO;
    RD_DO  <= not RD_Q;
    RD_SEL <= '1' when M8 = '1' and RAMDISK_EN = '1' and
                       (M8_IO = X"EA" or (M8_IO = X"F9" and T80_RD_n = '0') or (M8_IO = X"FA" and T80_WR_n = '0')) else '0';
    process(CLKBUS(CKMASTER)) begin
        if rising_edge(CLKBUS(CKMASTER)) then
            RD_SEL_LAST <= RD_SEL;
            RD_WE       <= '0';
            if RD_SEL = '1' and RD_SEL_LAST = '0' and T80_WR_n = '0' then
                RD_WE <= '1';                                                   -- Write at the start of the cycle,
            end if;
            if RD_SEL = '0' and RD_SEL_LAST = '1' then
                RD_OFF <= RD_OFF + 1;                                           -- next byte at its end.
            end if;
            if M8 = '1' and RAMDISK_EN = '1' and T80_WR_n = '0' and M8_IO = X"EB" then
                RD_OFF <= unsigned(T80_A16(15 downto 8) & T80_DO);
            end if;
            if M8 = '1' and RAMDISK_EN = '1' and T80_RD_n = '0' and M8_IO = X"F8" then
                RD_OFF <= (others => '0');
            end if;
        end if;
    end process;
    RAMDISK : dpram
        generic map (init_file => "", widthad_a => 16, width_a => 8, widthad_b => 16, width_b => 8)
        port map (clock_a => CLKBUS(CKMASTER), address_a => std_logic_vector(RD_OFF), data_a => RD_DI, wren_a => RD_WE, q_a => RD_Q,
                  clock_b => CLKBUS(CKMASTER), address_b => (others => '0'), data_b => (others => '0'), wren_b => '0', q_b => open);

    -- MZ-800 joysticks: port F0 (F1) reads joystick 1 (2) while 8255 PA4 (PA5) is low, low active strobes (MZ-800
    -- Technical Reference Manual, 9 Joystick; mz800emu's code tests PA5/PA6, one bit off from its own comments, and
    -- Exolon, which strobes only PA4, then never saw the stick). Bits 0 up, 1 down, 2 left, 3 right, 4 fire 1,
    -- 5 fire 2, low = active.
    M8_JOY_DO <= "11" & not JOY0(5) & not JOY0(4) & not JOY0(0) & not JOY0(1) & not JOY0(2) & not JOY0(3)
                     when M8_IO(0) = '0' and i8255_PA_O(4) = '0' else
                 "11" & not JOY1(5) & not JOY1(4) & not JOY1(0) & not JOY1(1) & not JOY1(2) & not JOY1(3)
                     when M8_IO(0) = '1' and i8255_PA_O(5) = '0' else
                 X"FF";

    -- Video Output.
    --
    VGATE_n    <= '0' when M8 = '1' else VGATE_ni;

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
