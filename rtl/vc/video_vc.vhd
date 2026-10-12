---------------------------------------------------------------------------------------------------------
--
-- Name:            video_vc.vhd
-- Description:     The v2 VideoController (rtl/vc/VideoController.vhd) behind the interface of the v1
--                  video module (rtl/video.vhd), so rtl/sharpmz.vhd can use either.
--
--                  - Translates this core's CONFIG bus into the v2 (tranZPUter emuMZ) layout.
--                  - Gates MREQ with the machine's own memory decode, so memory banking (MZ-700) is
--                    respected; the controller would otherwise decode D000-DFFF on its own.
--                  - Keeps the v1 VRAM access wait states (MZ-80A/700, CONFIG(VRAMWAIT)).
--                  - Loads the character generator ROM over ioctl at 0x500000, as v1 did.
--
-- Copyright:       (c) 2018-2022 Philip Smart <philip.smart@net2net.org> (VideoController, v1 video)
--                  2026 SharpMZ MiSTer contributors (MiSTer integration)
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
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
---------------------------------------------------------------------------------------------------------

library ieee;
library pkgs;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;
use work.vc_rams_pkg.all;

entity video_vc is
    Port (
        RST_n                    : in  std_logic;
        CONFIG                   : in  std_logic_vector(CONFIG_WIDTH);
        CLKBUS                   : in  std_logic_vector(CLKBUS_WIDTH);
        T80_A                    : in  std_logic_vector(15 downto 0);
        T80_RD_n                 : in  std_logic;
        T80_WR_n                 : in  std_logic;
        T80_MREQ_n               : in  std_logic;
        T80_IORQ_n               : in  std_logic;
        T80_BUSACK_n             : in  std_logic;
        T80_WAIT_n               : out std_logic;
        T80_DI                   : in  std_logic_vector(7 downto 0);
        T80_DO                   : out std_logic_vector(7 downto 0);
        CS_VRAM_n                : in  std_logic;
        CS_MEM_G_n               : in  std_logic;
        CS_GRAM_n                : in  std_logic;
        CS_GRAM_80B_n            : in  std_logic;
        CS_IO_GFB_n              : in  std_logic;
        CS_IO_G_n                : in  std_logic;
        VGATE_n                  : in  std_logic;
        INVERSE_n                : in  std_logic;
        CONFIG_CHAR80            : in  std_logic;
        HBLANK                   : out std_logic;
        VBLANK                   : out std_logic;
        HSYNC_n                  : out std_logic;
        VSYNC_n                  : out std_logic;
        ROUT                     : out std_logic_vector(7 downto 0);
        GOUT                     : out std_logic_vector(7 downto 0);
        BOUT                     : out std_logic_vector(7 downto 0);
        CE_PIXEL                 : out std_logic;
        -- MZ-1500 PCG (from mz80c.vhd).
        M15_PCG_CS               : in  std_logic := '0';
        M15_PCG_PLANE            : in  std_logic_vector(1 downto 0) := "00";
        M15_CG_CS                : in  std_logic := '0';                 -- CPU read of the CG ROM (OUT E5 0).
        M15_PCG_DO               : out std_logic_vector(7 downto 0);
        M15_DMD                  : in  std_logic_vector(1 downto 0) := "00";
        M15_PAL                  : in  std_logic_vector(23 downto 0) := (others => '0');
        BCOL                     : out std_logic_vector(3 downto 0);   -- MZ-800 border colour (I, G, R, B).
        IOCTL_DOWNLOAD           : in  std_logic;
        IOCTL_UPLOAD             : in  std_logic;
        IOCTL_CLK                : in  std_logic;
        IOCTL_WR                 : in  std_logic;
        IOCTL_RD                 : in  std_logic;
        IOCTL_ADDR               : in  std_logic_vector(24 downto 0);
        IOCTL_DOUT               : in  std_logic_vector(31 downto 0);
        IOCTL_DIN                : out std_logic_vector(31 downto 0)
    );
end video_vc;

architecture rtl of video_vc is

    -- v2 CONFIG layout (rtl/vc/vc_mctrl_pkg.vhd), written out as literals so this unit can use this
    -- core's mctrl_pkg names for its own CONFIG.
    constant V2_WIDTH        : natural := 91;
    constant V2_MZ80K        : natural := 0;
    constant V2_MZ80C        : natural := 1;
    constant V2_MZ1200       : natural := 2;
    constant V2_MZ80A        : natural := 3;
    constant V2_MZ700        : natural := 4;
    constant V2_MZ800        : natural := 5;
    constant V2_MZ80B        : natural := 7;
    constant V2_MZ2000       : natural := 8;
    constant V2_NORMAL       : natural := 16;
    constant V2_NORMAL80     : natural := 17;
    constant V2_COLOUR       : natural := 18;
    constant V2_COLOUR80     : natural := 19;
    constant V2_OPT_GRAMI    : natural := 43;
    constant V2_OPT_GRAMII   : natural := 44;
    constant V2_OPT_GRAMIII  : natural := 45;
    constant V2_OPT_PCG      : natural := 46;
    constant V2_OPT_MZ1R25   : natural := 47;
    constant V2_VRAMDISABLE  : natural := 69;
    constant V2_GRAMDISABLE  : natural := 70;

    signal V2_CONFIG         : std_logic_vector(V2_WIDTH-1 downto 0);

    -- MZ-1500 PCG: three 8 KB planes (mz800emu g_memory.PCG). The CPU sees one plane at D000-EFFF (OUT E5 1-3);
    -- the renderer reads all three for a character row.
    signal PCG_CPU_ADDR      : std_logic_vector(12 downto 0);
    signal PCG_WE            : std_logic_vector(2 downto 0);
    signal PCG_CPU_Q0, PCG_CPU_Q1, PCG_CPU_Q2 : std_logic_vector(7 downto 0);
    signal PCG_RD_ADDR       : std_logic_vector(12 downto 0);
    signal PCG_RD_DATA       : std_logic_vector(23 downto 0);
    signal M15_PCGON         : std_logic;
    signal VIDEO_MREQ_n      : std_logic;
    signal VIDEO_DATA_OUT    : std_logic_vector(31 downto 0);
    signal VGA_R, VGA_G, VGA_B : std_logic_vector(3 downto 0);
    signal HBLANKi           : std_logic;
    signal CG_BANK           : std_logic_vector(3 downto 0);
    signal CG_4K             : std_logic;
    signal CG_IOCTL_WR       : std_logic;
    signal CG_IOCTL_DIN      : std_logic_vector(7 downto 0);
    signal CG_PORT_ADDR      : std_logic_vector(14 downto 0);
    signal T80_MREQ_LAST_n   : std_logic := '1';
    signal VRAM_WAIT         : std_logic := '1';
    signal WAITi_n           : std_logic;
    signal WAITii_n          : std_logic := '1';
    signal CSYNC_UNUSED      : std_logic_vector(3 downto 0);
    signal R_COMP, G_COMP, B_COMP, WAIT_CSYNC : std_logic;

begin

    -- MZ-1500 PCG planes. D000-EFFF -> plane offset 0000-1FFF (A12 inverted).
    PCG_CPU_ADDR <= (not T80_A(12)) & T80_A(11 downto 0);
    PCG_WE(0)    <= '1' when M15_PCG_CS = '1' and T80_WR_n = '0' and M15_PCG_PLANE = "00" else '0';
    PCG_WE(1)    <= '1' when M15_PCG_CS = '1' and T80_WR_n = '0' and M15_PCG_PLANE = "01" else '0';
    PCG_WE(2)    <= '1' when M15_PCG_CS = '1' and T80_WR_n = '0' and M15_PCG_PLANE = "10" else '0';

    PCGP0 : dpram
        generic map (init_file => "", widthad_a => 13, width_a => 8, widthad_b => 13, width_b => 8)
        port map (clock_a => CLKBUS(CKMASTER), address_a => PCG_CPU_ADDR, data_a => T80_DI, wren_a => PCG_WE(0), q_a => PCG_CPU_Q0,
                  clock_b => CLKBUS(CKMASTER), address_b => PCG_RD_ADDR, data_b => (others => '0'), wren_b => '0', q_b => PCG_RD_DATA(7 downto 0));
    PCGP1 : dpram
        generic map (init_file => "", widthad_a => 13, width_a => 8, widthad_b => 13, width_b => 8)
        port map (clock_a => CLKBUS(CKMASTER), address_a => PCG_CPU_ADDR, data_a => T80_DI, wren_a => PCG_WE(1), q_a => PCG_CPU_Q1,
                  clock_b => CLKBUS(CKMASTER), address_b => PCG_RD_ADDR, data_b => (others => '0'), wren_b => '0', q_b => PCG_RD_DATA(15 downto 8));
    PCGP2 : dpram
        generic map (init_file => "", widthad_a => 13, width_a => 8, widthad_b => 13, width_b => 8)
        port map (clock_a => CLKBUS(CKMASTER), address_a => PCG_CPU_ADDR, data_a => T80_DI, wren_a => PCG_WE(2), q_a => PCG_CPU_Q2,
                  clock_b => CLKBUS(CKMASTER), address_b => PCG_RD_ADDR, data_b => (others => '0'), wren_b => '0', q_b => PCG_RD_DATA(23 downto 16));
    M15_PCGON  <= CONFIG(IS_MZ1500) and M15_DMD(0);
    -- The CG ROM read (OUT E5 0) goes through the CG ROM's ioctl port. The CPU sees the font with bit 7 as the
    -- leftmost pixel, the order the core keeps it in and the PCG's order: software copies CG characters into
    -- the PCG (Xetter '91's text came out mirrored with the dump's bit 0-left order).
    M15_PCG_DO <= CG_IOCTL_DIN when M15_CG_CS = '1' else
                  PCG_CPU_Q0 when M15_PCG_PLANE = "00" else PCG_CPU_Q1 when M15_PCG_PLANE = "01" else PCG_CPU_Q2;

    -- Configuration translation.
    process( CONFIG )
    begin
        V2_CONFIG                 <= (others => '0');
        V2_CONFIG(V2_MZ80K)       <= CONFIG(MZ80K);
        V2_CONFIG(V2_MZ80C)       <= CONFIG(MZ80C);
        V2_CONFIG(V2_MZ1200)      <= CONFIG(MZ1200);
        V2_CONFIG(V2_MZ80A)       <= CONFIG(MZ80A);
        V2_CONFIG(V2_MZ700)       <= CONFIG(MZ700);
        V2_CONFIG(V2_MZ800)       <= CONFIG(MZ800);
        V2_CONFIG(V2_MZ80B)       <= CONFIG(MZ80B);
        V2_CONFIG(V2_MZ2000)      <= CONFIG(MZ2000);
        V2_CONFIG(V2_NORMAL)      <= CONFIG(NORMAL);
        V2_CONFIG(V2_NORMAL80)    <= CONFIG(NORMAL80);
        V2_CONFIG(V2_COLOUR)      <= CONFIG(COLOUR);
        V2_CONFIG(V2_COLOUR80)    <= CONFIG(COLOUR80);
        -- Graphics options fitted on every machine that has them.
        V2_CONFIG(V2_OPT_GRAMI)   <= '1';
        V2_CONFIG(V2_OPT_GRAMII)  <= '1';
        V2_CONFIG(V2_OPT_GRAMIII) <= '1';
        V2_CONFIG(V2_OPT_PCG)     <= '1';
        V2_CONFIG(V2_OPT_MZ1R25)  <= CONFIG(MZ800);                  -- MZ-800 VRAM expansion (frame B, 16/4 colour modes), fitted as in mz800emu.
        V2_CONFIG(V2_VRAMDISABLE) <= CONFIG(VRAMDISABLE);
        V2_CONFIG(V2_GRAMDISABLE) <= CONFIG(GRAMDISABLE);
        -- VRAMWAIT and PCGRAM stay 0: VideoController copies them into its character/graphics blend
        -- register (GRAM_MODE_REG 6/7). Wait states are generated here instead.
    end process;

    -- Only let the controller see memory cycles the machine has decoded as video/graphics.
    VIDEO_MREQ_n <= T80_MREQ_n or (CS_VRAM_n and CS_MEM_G_n and CS_GRAM_n and CS_GRAM_80B_n);

    -- Character generator ROM bank (layout of rtl/software/mif/combined_cgrom.mif).
    CG_BANK <= "0000" when CONFIG(MZ80K)  = '1' else
               "0001" when CONFIG(MZ80C)  = '1' else
               "0010" when CONFIG(MZ1200) = '1' else
               "0011" when CONFIG(MZ80A)  = '1' else
               "1010" when CONFIG(IS_MZ1500) = '1' else           -- before MZ700: the MZ-1500 also sets it
               "0100" when CONFIG(MZ700)  = '1' else
               "0110" when CONFIG(MZ800)  = '1' else
               "1000" when CONFIG(MZ80B)  = '1' else
               "1001" when CONFIG(MZ2000) = '1' else
               "1111";
    CG_4K   <= CONFIG(MZ700) or CONFIG(MZ800);                  -- MZ-1500 included (CONFIG(MZ700))
    CG_IOCTL_WR <= '1' when IOCTL_WR = '1' and IOCTL_ADDR(24 downto 20) = "00101" else '0';
    -- MZ-1500 CG ROM bank (cg 5000-5FFF) for OUT E5 0 reads, otherwise the ioctl address.
    CG_PORT_ADDR <= "101" & T80_A(11 downto 0) when M15_CG_CS = '1' and IOCTL_DOWNLOAD = '0' else IOCTL_ADDR(14 downto 0);

    VC: entity work.VideoController
        port map (
            CLOCK_50         => '0',
            SYS_CLK          => CLKBUS(CKMASTER),
            VRESETn          => RST_n,
            M15_PCGON        => M15_PCGON,
            M15_PRIO         => M15_DMD(1),
            M15_PAL          => M15_PAL,
            BCOL_O           => BCOL,
            PCG_RD_ADDR      => PCG_RD_ADDR,
            PCG_RD_DATA      => PCG_RD_DATA,
            VIDEO_ADDR       => X"00" & T80_A,
            VIDEO_DATA_IN    => X"000000" & T80_DI,
            VIDEO_DATA_OUT   => VIDEO_DATA_OUT,
            VIDEO_MREQn      => VIDEO_MREQ_n,
            VIDEO_IORQn      => T80_IORQ_n,
            VIDEO_RDn        => T80_RD_n,
            VIDEO_WRn        => T80_WR_n,
            VIDEO_WR_BYTE    => '1',
            VIDEO_WR_HWORD   => '0',
            VIDEO_DATA_AVAILn=> open,
            VGA_R            => VGA_R,
            VGA_G            => VGA_G,
            VGA_B            => VGA_B,
            VGA_R_COMPOSITE  => R_COMP,
            VGA_G_COMPOSITE  => G_COMP,
            VGA_B_COMPOSITE  => B_COMP,
            HSYNC_OUTn       => HSYNC_n,
            VSYNC_OUTn       => VSYNC_n,
            HBLANK_OUT       => HBLANKi,
            VBLANK_OUT       => VBLANK,
            COLR_OUT         => CSYNC_UNUSED(0),
            CSYNC_OUTn       => CSYNC_UNUSED(1),
            CSYNC_OUT        => CSYNC_UNUSED(2),
            VWAITn_V_CSYNC   => WAIT_CSYNC,
            V_HSYNCn         => '1',
            V_VSYNCn         => '1',
            V_COLR           => '0',
            V_G              => '0',
            V_B              => '0',
            V_R              => '0',
            HW_HOST          => "100",                                       -- MZ-700 host (no host hardware on MiSTer).
            HW_MODE          => "10",                                        -- Emulator controlled.
            MB_VIDEO_ENABLEn => '1',                                         -- FPGA video.
            CONFIG           => V2_CONFIG,
            CE_PIXEL         => CE_PIXEL,
            VIDEO_50HZ       => CONFIG(MZ700) or CONFIG(MZ800),               -- European MZ-700/800 are PAL 50Hz machines.
            CG_BANK          => CG_BANK,
            CG_4K            => CG_4K,
            CG_IOCTL_ADDR    => CG_PORT_ADDR,
            CG_IOCTL_WR      => CG_IOCTL_WR,
            CG_IOCTL_DOUT    => IOCTL_DOUT(7 downto 0),
            CG_IOCTL_DIN     => CG_IOCTL_DIN
        );

    HBLANK    <= HBLANKi;
    T80_DO    <= VIDEO_DATA_OUT(7 downto 0);
    ROUT      <= VGA_R & VGA_R;
    GOUT      <= VGA_G & VGA_G;
    BOUT      <= VGA_B & VGA_B;
    IOCTL_DIN <= X"000000" & CG_IOCTL_DIN when IOCTL_ADDR(24 downto 20) = "00101" else (others => '0');

    -- VRAM wait states, as v1: a VRAM access that starts during the active display is held for the
    -- rest of the cycle plus one CPU clock (MZ-80A/1200 and MZ-700, when enabled).
    process( CLKBUS(CKMASTER) )
    begin
        if rising_edge(CLKBUS(CKMASTER)) then
            T80_MREQ_LAST_n <= T80_MREQ_n;
            if T80_MREQ_n = '0' and T80_MREQ_LAST_n = '1' then
                VRAM_WAIT <= HBLANKi;
            end if;
            if CLKBUS(CKENCPU) = '1' then
                WAITii_n <= WAITi_n;
            end if;
        end if;
    end process;
    WAITi_n    <= '0' when CS_VRAM_n = '0' and VRAM_WAIT = '0' and HBLANKi = '0' and (CONFIG(MZ_A) = '1' or CONFIG(MZ700) = '1') else '1';
    T80_WAIT_n <= WAITi_n and WAITii_n when CONFIG(VRAMWAIT) = '1' else '1';

end rtl;
