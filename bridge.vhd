---------------------------------------------------------------------------------------------------------
--
-- Name:            bridge.vhd
-- Created:         November 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series compatible logic IO Control.
--                                                     
--                  This module is the IO control layer which provides io services to the emulation,
--                  which at time of writing can come from the DE10 Nano HPS or the soft-core STORM
--                  or NEO430 microcontroller.
--
-- Credits:         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         November 2018 - Initial creation.
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

entity bridge is
  port(
        --------------------                Clock Input                         ----------------------------     
        clkmaster             : in    std_logic;                                -- Master Clock(50MHz)
        clksys                : out   std_logic;                                -- System clock.
        clkvid                : out   std_logic;                                -- Pixel base clock of video.
        --------------------             Reset                                  ----------------------------
        cold_reset            : in    std_logic;
        warm_reset            : in    std_logic;
        --------------------                     main_leds                      ----------------------------
        main_leds             : out   std_logic_vector(7 downto 0);             -- main_leds Green[7:0]
        --------------------                     PS2                            ----------------------------
        ps2_key               : in    std_logic_vector(10 downto 0);            -- PS2 Key data.
        --------------------                     VGA                            ----------------------------
        vga_hb_o              : out   std_logic;                                -- VGA Horizontal Blank
        vga_vb_o              : out   std_logic;                                -- VGA Vertical Blank
        vga_hs_o              : out   std_logic;                                -- VGA H_SYNC
        vga_vs_o              : out   std_logic;                                -- VGA V_SYNC
        vga_r_o               : out   std_logic_vector(7 downto 0);             -- VGA Red[3:0], [7:4] = 0
        vga_g_o               : out   std_logic_vector(7 downto 0);             -- VGA Green[3:0]
        vga_b_o               : out   std_logic_vector(7 downto 0);             -- VGA Blue[3:0]
        --------------------                     AUDIO                          ------------------------------
        audio_l_o             : out   std_logic;
        audio_r_o             : out   std_logic;

        uart_rx               : in    std_logic;
        uart_tx               : out   std_logic; 
        sd_sck                : out   std_logic; 
        sd_mosi               : out   std_logic; 
        sd_miso               : in    std_logic; 
        sd_cs                 : out   std_logic;
        sd_cd                 : out   std_logic; 
        --------------------                   HPS Interface                    ------------------------------
        ioctl_download        : in    std_logic;                                -- HPS Downloading to FPGA.
        ioctl_upload          : in    std_logic;                                -- HPS Uploading from FPGA.
        ioctl_clk             : in    std_logic;                                -- HPS I/O Clock.
        ioctl_wr              : in    std_logic;                                -- HPS Write Enable to FPGA.
        ioctl_rd              : in    std_logic;                                -- HPS Read Enable from FPGA.
        ioctl_addr            : in    std_logic_vector(24 downto 0);            -- HPS Address in FPGA to write into.
        ioctl_dout            : in    std_logic_vector(15 downto 0);            -- HPS Data to be written into FPGA.
        ioctl_din             : out   std_logic_vector(15 downto 0)             -- HPS Data to be read into HPS.
);
end bridge;

architecture rtl of bridge is

--
-- Signals.
--
signal CON_CLKMASTER          :       std_logic;
signal CON_CLKSYS             :       std_logic;
signal CON_CLKVID             :       std_logic;
signal CON_CLKIOP             :       std_logic;
signal CON_COLD_RESET         :       std_logic;
signal CON_WARM_RESET         :       std_logic;
signal CON_MAIN_LEDS          :       std_logic_vector(7 downto 0);
signal CON_PS2_KEY            :       std_logic_vector(10 downto 0);
signal CON_VGA_HB_O           :       std_logic;
signal CON_VGA_VB_O           :       std_logic;
signal CON_VGA_HS_O           :       std_logic;
signal CON_VGA_VS_O           :       std_logic;
signal CON_VGA_R_O            :       std_logic_vector(7 downto 0);
signal CON_VGA_G_O            :       std_logic_vector(7 downto 0);
signal CON_VGA_B_O            :       std_logic_vector(7 downto 0);
signal CON_AUDIO_L_O          :       std_logic;
signal CON_AUDIO_R_O          :       std_logic;
signal CON_IOCTL_DOWNLOAD     :       std_logic;
signal CON_IOCTL_UPLOAD       :       std_logic;
signal CON_IOCTL_CLK          :       std_logic;
signal CON_IOCTL_WR           :       std_logic;
signal CON_IOCTL_RD           :       std_logic;
signal CON_IOCTL_ADDR         :       std_logic_vector(24 downto 0);
signal CON_IOCTL_DOUT         :       std_logic_vector(31 downto 0);
signal CON_IOCTL_DIN          :       std_logic_vector(31 downto 0);
--
-- IO Processor Signals.
--
signal IOP_IOCTL_DOWNLOAD     :       std_logic;
signal IOP_IOCTL_UPLOAD       :       std_logic;
signal IOP_IOCTL_CLK          :       std_logic;
signal IOP_IOCTL_WR           :       std_logic;
signal IOP_IOCTL_RD           :       std_logic;
signal IOP_IOCTL_ADDR         :       std_logic_vector(24 downto 0);
signal IOP_IOCTL_DOUT         :       std_logic_vector(31 downto 0);
signal IOP_IOCTL_DIN          :       std_logic_vector(31 downto 0);
signal IOP_IOCTL_SENSE        :       std_logic;
signal IOP_IOCTL_SELECT       :       std_logic;
--
--
--
signal CON_UART_TX            :       std_logic;
signal CON_UART_RX            :       std_logic;
signal CON_SPI_SCLK           :       std_logic;
signal CON_SPI_MOSI           :       std_logic;
signal CON_SPI_MISO           :       std_logic;
signal CON_SPI_CS             :       std_logic_vector(7 downto 0);

--
-- Components
--
component sharpmz
    port (
        --------------------                Clock Input                         ----------------------------     
        CLKMASTER             : in    std_logic;                                -- Master Clock(50MHz)
        CLKSYS                : out   std_logic;                                -- System clock.
        CLKVID                : out   std_logic;                                -- Pixel base clock of video.
        CLKIOP                : out   std_logic;                                -- IO processor clock.
        --------------------             Reset                                  ----------------------------
        COLD_RESET            : in    std_logic;
        WARM_RESET            : in    std_logic;
        --------------------                     main_leds                      ----------------------------
        MAIN_LEDS             : out   std_logic_vector(7 downto 0);             -- main_leds Green[7:0]
        --------------------                     PS2                            ----------------------------
        PS2_KEY               : in    std_logic_vector(10 downto 0);            -- PS2 Key data.
        --------------------                     VGA                            ----------------------------
        VGA_HB_O              : out   std_logic;                                -- VGA Horizontal Blank
        VGA_VB_O              : out   std_logic;                                -- VGA Vertical Blank
        VGA_HS_O              : out   std_logic;                                -- VGA H_SYNC
        VGA_VS_O              : out   std_logic;                                -- VGA V_SYNC
        VGA_R_O               : out   std_logic_vector(7 downto 0);             -- VGA Red[3:0], [7:4] = 0
        VGA_G_O               : out   std_logic_vector(7 downto 0);             -- VGA Green[3:0]
        VGA_B_O               : out   std_logic_vector(7 downto 0);             -- VGA Blue[3:0]
        --------------------                     AUDIO                          ------------------------------
        AUDIO_L_O             : out   std_logic;
        AUDIO_R_O             : out   std_logic;
        --------------------                   HPS Interface                    ------------------------------
        IOCTL_DOWNLOAD        : in    std_logic;                                -- Downloading to FPGA.
        IOCTL_UPLOAD          : in    std_logic;                                -- Uploading from FPGA.
        IOCTL_CLK             : in    std_logic;                                -- I/O Clock.
        IOCTL_WR              : in    std_logic;                                -- Write Enable to FPGA.
        IOCTL_RD              : in    std_logic;                                -- Read Enable from FPGA.
        IOCTL_ADDR            : in    std_logic_vector(24 downto 0);            -- Address in FPGA to write into.
        IOCTL_DOUT            : in    std_logic_vector(31 downto 0);            -- Data to be written into FPGA.
        IOCTL_DIN             : out   std_logic_vector(31 downto 0)             -- Data to be read into HPS.
    );
end component;

--component STORM_SoC
--    port (
--        -- Global Control --
--        CLK_I                 : in    std_logic;
--        RST_I                 : in    std_logic;
--
--        -- General purpose (debug) UART --
--        UART0_RXD_I           : in    std_logic;
--        UART0_TXD_O           : out   std_logic;
--
--        -- System Control --
--        START_I               : in    std_logic; -- low active
--        BOOT_CONFIG_I         : in    std_logic_vector(03 downto 0); -- low active
--        LED_BAR_O             : out   std_logic_vector(07 downto 0);
--
--        -- GP Input Pins --
--        GP_INPUT_I            : in    std_logic_vector(07 downto 0);
--
--        -- GP Output Pins --
--        GP_OUTPUT_O           : out   std_logic_vector(07 downto 0);
--
--        -- I²C Port --
--        I2C_SCL_IO            : inout std_logic;
--        I2C_SDA_IO            : inout std_logic;
--
--        -- SPI Port 0 [3 devices] --
--        SPI_P0_CLK_O          : out   std_logic;
--        SPI_P0_MISO_I         : in    std_logic;
--        SPI_P0_MOSI_O         : out   std_logic;
--        SPI_P0_CS_O           : out   std_logic_vector(02 downto 0);
--
--        -- SPI Port 1 [3 devices] --
--        SPI_P1_CLK_O          : out   std_logic;
--        SPI_P1_MISO_I         : in    std_logic;
--        SPI_P1_MOSI_O         : out   std_logic;
--        SPI_P1_CS_O           : out   std_logic_vector(02 downto 0);
--
--        -- SPI Port 2 [2 devices] --
--        SPI_P2_CLK_O          : out   std_logic;
--        SPI_P2_MISO_I         : in    std_logic;
--        SPI_P2_MOSI_O         : out   std_logic;
--        SPI_P2_CS_O           : out   std_logic_vector(01 downto 0);
--
--        -- PWM Port 0 --
----      PWM0_PORT_O           : out   std_logic_vector(07 downto 0)
--
--        -- IOCTL Bus --
--        IOCTL_DOWNLOAD        : out   std_logic;                                  -- Downloading to FPGA.
--        IOCTL_UPLOAD          : out   std_logic;                                  -- Uploading from FPGA.
--        IOCTL_CLK             : out   std_logic;                                  -- I/O Clock.
--        IOCTL_WR              : out   std_logic;                                  -- Write Enable to FPGA.
--        IOCTL_RD              : out   std_logic;                                  -- Read Enable from FPGA.
--        IOCTL_SENSE           : in    std_logic;                                  -- Sense to see if HPS accessing ioctl bus.
--        IOCTL_SELECT          : out   std_logic;                                  -- Enable IOP control over ioctl bus.
--        IOCTL_ADDR            : out   std_logic_vector(24 downto 0);              -- Address in FPGA to write into.
--        IOCTL_DOUT            : out   std_logic_vector(31 downto 0);              -- Data to be written into FPGA.
--        IOCTL_DIN             : in    std_logic_vector(31 downto 0)               -- Data to be read into HPS.
--
----      -- SDRAM Interface --
----      SDRAM_CLK_O           : out   std_logic;
----      SDRAM_CSN_O           : out   std_logic;
----      SDRAM_CKE_O           : out   std_logic;
----      SDRAM_RASN_O          : out   std_logic;
----      SDRAM_CASN_O          : out   std_logic;
----      SDRAM_WEN_O           : out   std_logic;
----      SDRAM_DQM_O           : out   std_logic_vector(01 downto 0);
----      SDRAM_BA_O            : out   std_logic_vector(01 downto 0);
----      SDRAM_ADR_O           : out   std_logic_vector(11 downto 0);
----      SDRAM_DAT_IO          : inout std_logic_vector(15 downto 0)
--    );
--end component;
--
--component neo430
--    generic (
--        -- general configuration --
--        CLOCK_SPEED           : natural := 100000000; -- main clock in Hz
--        IMEM_SIZE             : natural := 4*1024; -- internal IMEM size in bytes, max 48kB (default=4kB)
--        DMEM_SIZE             : natural := 2*1024; -- internal DMEM size in bytes, max 12kB (default=2kB)
--        -- additional configuration --
--        USER_CODE             : std_logic_vector(15 downto 0) := x"0000"; -- custom user code
--        -- module configuration --
--        DADD_USE              : boolean := true; -- implement DADD instruction? (default=true)
--        MULDIV_USE            : boolean := true; -- implement multiplier/divider unit? (default=true)
--        WB32_USE              : boolean := false;-- implement WB32 unit? (default=true)
--        WDT_USE               : boolean := true; -- implement WDT? (default=true)
--        GPIO_USE              : boolean := true; -- implement GPIO unit? (default=true)
--        TIMER_USE             : boolean := true; -- implement timer? (default=true)
--        UART_USE              : boolean := true; -- implement UART? (default=true)
--        CRC_USE               : boolean := true; -- implement CRC unit? (default=true)
--        CFU_USE               : boolean := true; -- implement custom functions unit? (default=false)
--        PWM_USE               : boolean := true; -- implement PWM controller?
--        TWI_USE               : boolean := true; -- implement two wire serial interface? (default=true)
--        SPI_USE               : boolean := true; -- implement SPI? (default=true)
--        -- boot configuration --
--        BOOTLD_USE            : boolean := true; -- implement and use bootloader? (default=true)
--        IMEM_AS_ROM           : boolean := false -- implement IMEM as read-only memory? (default=false)
--   );
--    port (
--        -- global control --
--        clk_i                 : in    std_logic; -- global clock, rising edge
--        rst_i                 : in    std_logic; -- global reset, async, low-active
--        -- gpio --
--        gpio_o                : out   std_logic_vector(15 downto 0); -- parallel output
--        gpio_i                : in    std_logic_vector(15 downto 0); -- parallel input
--        -- pwm channels --
--        pwm_o                 : out   std_logic_vector(02 downto 0); -- pwm channels
--        -- serial com --
--        uart_txd_o            : out   std_logic; -- UART send data
--        uart_rxd_i            : in    std_logic; -- UART receive data
--        spi_sclk_o            : out   std_logic; -- serial clock line
--        spi_mosi_o            : out   std_logic; -- serial data line out
--        spi_miso_i            : in    std_logic; -- serial data line in
--        spi_cs_o              : out   std_logic_vector(07 downto 0); -- SPI CS 0..7
--        twi_sda_io            : inout std_logic; -- twi serial data line
--        twi_scl_io            : inout std_logic; -- twi serial clock line
--        -- IOCTL Bus --
--        ioctl_download        : out   std_logic;                                  -- Downloading to FPGA.
--        ioctl_upload          : out   std_logic;                                  -- Uploading from FPGA.
--        ioctl_clk             : out   std_logic;                                  -- I/O Clock.
--        ioctl_wr              : out   std_logic;                                  -- Write Enable to FPGA.
--        ioctl_rd              : out   std_logic;                                  -- Read Enable from FPGA.
--        ioctl_sense           : in    std_logic;                                  -- Sense to see if HPS accessing ioctl bus.
--        ioctl_select          : out   std_logic;                                  -- Enable CFU control over ioctl bus.
--        ioctl_addr            : out   std_logic_vector(24 downto 0);              -- Address in FPGA to write into.
--        ioctl_dout            : out   std_logic_vector(31 downto 0);              -- Data to be written into FPGA.
--        ioctl_din             : in    std_logic_vector(31 downto 0);              -- Data to be read into HPS.
--        -- 32-bit wishbone interface --
--        wb_adr_o              : out   std_logic_vector(31 downto 0); -- address
--        wb_dat_i              : in    std_logic_vector(31 downto 0); -- read data
--        wb_dat_o              : out   std_logic_vector(31 downto 0); -- write data
--        wb_we_o               : out   std_logic; -- read/write
--        wb_sel_o              : out   std_logic_vector(03 downto 0); -- byte enable
--        wb_stb_o              : out   std_logic; -- strobe
--        wb_cyc_o              : out   std_logic; -- valid cycle
--        wb_ack_i              : in    std_logic; -- transfer acknowledge
--        -- interrupts --
--        irq_i                 : in    std_logic; -- external interrupt request line
--        irq_ack_o             : out   std_logic  -- external interrupt request acknowledge
--    );
--end component;

begin

    --
    -- Instantiation
    --
    SHARPMZ_0 : sharpmz
        port map (
            --------------------                Clock Input                         ----------------------------     
            CLKMASTER             => CON_CLKMASTER,                                 -- Master Clock(50MHz)
            CLKSYS                => CON_CLKSYS,                                    -- System clock.
            CLKVID                => CON_CLKVID,                                    -- Pixel base clock of video.
            CLKIOP                => CON_CLKIOP,                                    -- IO Processor Clock.
            --------------------                                                    ----------------------------
            COLD_RESET            => CON_COLD_RESET,
            WARM_RESET            => CON_WARM_RESET,
            --------------------                                                    ----------------------------
            MAIN_LEDS             => CON_MAIN_LEDS,                                 -- main_leds Green[7:0]
            --------------------                                                    ----------------------------
            PS2_KEY               => CON_PS2_KEY,                                   -- PS2 Key data.
            --------------------                                                    ----------------------------
            VGA_HB_O              => CON_VGA_HB_O,                                  -- VGA Horizontal Blank
            VGA_VB_O              => CON_VGA_VB_O,                                  -- VGA Vertical Blank
            VGA_HS_O              => CON_VGA_HS_O,                                  -- VGA H_SYNC
            VGA_VS_O              => CON_VGA_VS_O,                                  -- VGA V_SYNC
            VGA_R_O               => CON_VGA_R_O,                                   -- VGA Red[3:0], [7:4] = 0
            VGA_G_O               => CON_VGA_G_O,                                   -- VGA Green[3:0]
            VGA_B_O               => CON_VGA_B_O,                                   -- VGA Blue[3:0]
            --------------------                                                    ------------------------------
            AUDIO_L_O             => CON_AUDIO_L_O,
            AUDIO_R_O             => CON_AUDIO_R_O,
            --------------------                                                    ------------------------------
            IOCTL_DOWNLOAD        => CON_IOCTL_DOWNLOAD,                            -- Downloading to FPGA.
            IOCTL_UPLOAD          => CON_IOCTL_UPLOAD,                              -- Uploading from FPGA.
            IOCTL_CLK             => CON_IOCTL_CLK,                                 -- I/O Clock.
            IOCTL_WR              => CON_IOCTL_WR,                                  -- Write Enable to FPGA.
            IOCTL_RD              => CON_IOCTL_RD,                                  -- Read Enable from FPGA.
            IOCTL_ADDR            => CON_IOCTL_ADDR,                                -- Address in FPGA to write into.
            IOCTL_DOUT            => CON_IOCTL_DOUT,                                -- Data to be written into FPGA.
            IOCTL_DIN             => CON_IOCTL_DIN                                  -- Data to be read into HPS.
    );

--    -- If enabled, instantiate the local STORM IO processor to provide IO and user interface services.
--    --
--    STORM_ENABLED: if STORM_ENABLE = 1 generate
--      STORM_0: STORM_SoC
--        port map (
--            -- Global Control --
--            CLK_I                 => CON_CLKIOP,                                    -- global clock, rising edge
--            RST_I                 => (CON_COLD_RESET or CON_WARM_RESET),            -- global reset, async
--
--            -- General purpose (debug) UART --
--            UART0_RXD_I           => CON_UART_RX,
--            UART0_TXD_O           => CON_UART_TX,
--
--            -- System Control --
--            START_I               => '1',
--            BOOT_CONFIG_I         => "0000",
--            LED_BAR_O             => open,
--
--            -- GP Input Pins --
--            GP_INPUT_I            => x"FF",
--
--            -- GP Output Pins --
--            GP_OUTPUT_O           => open,
--
--            -- I²C Port --
--            I2C_SCL_IO            => open,
--            I2C_SDA_IO            => open,
--
--            -- SPI Port 0 [3 devices] --
--            SPI_P0_CLK_O          => CON_SPI_SCLK,
--            SPI_P0_MISO_I         => CON_SPI_MISO,
--            SPI_P0_MOSI_O         => CON_SPI_MOSI,
--            SPI_P0_CS_O           => CON_SPI_CS(2 downto 0),
--
--            -- SPI Port 1 [3 devices] --
--            SPI_P1_CLK_O          => open,
--            SPI_P1_MISO_I         => '0',
--            SPI_P1_MOSI_O         => open,
--            SPI_P1_CS_O           => open,
--
--            -- SPI Port 2 [2 devices] --
--            SPI_P2_CLK_O          => open,
--            SPI_P2_MISO_I         => '0',
--            SPI_P2_MOSI_O         => open,
--            SPI_P2_CS_O           => open,
--
--            -- PWM Port 0 --
----          PWM0_PORT_O           => open
--
--            -- IOCTL Bus --
--            IOCTL_DOWNLOAD        => IOP_IOCTL_DOWNLOAD,                            -- Downloading to FPGA.
--            IOCTL_UPLOAD          => IOP_IOCTL_UPLOAD,                              -- Uploading from FPGA.
--            IOCTL_CLK             => IOP_IOCTL_CLK,                                 -- I/O Clock.
--            IOCTL_WR              => IOP_IOCTL_WR,                                  -- Write Enable to FPGA.
--            IOCTL_RD              => IOP_IOCTL_RD,                                  -- Read Enable from FPGA.
--            IOCTL_SENSE           => IOP_IOCTL_SENSE,                               -- Sense to see if HPS accessing ioctl bus.
--            IOCTL_SELECT          => IOP_IOCTL_SELECT,                              -- Enable IOP control over ioctl bus.
--            IOCTL_ADDR            => IOP_IOCTL_ADDR,                                -- Address in FPGA to write into.
--            IOCTL_DOUT            => IOP_IOCTL_DOUT,                                -- Data to be written into FPGA.
--            IOCTL_DIN             => IOP_IOCTL_DIN                                  -- Data to be read into HPS.
--
----          -- SDRAM Interface --
----          SDRAM_CLK_O           => open,
----          SDRAM_CSN_O           => open,
----          SDRAM_CKE_O           => open,
----          SDRAM_RASN_O          => open,
----          SDRAM_CASN_O          => open,
----          SDRAM_WEN_O           => open,
----          SDRAM_DQM_O           => open,
----          SDRAM_BA_O            => open,
----          SDRAM_ADR_O           => open,
----          SDRAM_DAT_IO          => open
--        );
--    end generate;
--
--    -- If enabled, instantiate the local IO processor to provide IO and user interface services.
--    --
--    NEO430_ENABLED: if NEO_ENABLE = 1 generate
--      NEO430_0 : neo430
--        generic map (
--            -- general configuration --
--            CLOCK_SPEED           => 64000000,                                      -- main clock in Hz
--            IMEM_SIZE             => 48*1024,                                       -- internal IMEM size in bytes, max 48kB (default=4kB)
--            DMEM_SIZE             => 12*1024,                                       -- internal DMEM size in bytes, max 12kB (default=2kB)
--            -- additional configuration --
--            USER_CODE             => x"0000",                                       -- custom user code
--            -- module configuration --
--            DADD_USE              => true,                                          -- implement DADD instruction? (default=true)
--            MULDIV_USE            => true,                                          -- implement multiplier/divider unit? (default=true)
--            WB32_USE              => false,                                         -- implement WB32 unit? (default=true)
--            WDT_USE               => true,                                          -- implement WDT? (default=true)
--            GPIO_USE              => true,                                          -- implement GPIO unit? (default=true)
--            TIMER_USE             => true,                                          -- implement timer? (default=true)
--            UART_USE              => true,                                          -- implement UART? (default=true)
--            CRC_USE               => false,                                         -- implement CRC unit? (default=true)
--            CFU_USE               => false,                                         -- implement custom functions unit? (default=false)
--            PWM_USE               => true,                                          -- implement PWM controller?
--            TWI_USE               => false,                                         -- implement two wire serial interface? (default=true)
--            SPI_USE               => true,                                          -- implement SPI? (default=true)
--            -- boot configuration --
--            BOOTLD_USE            => true,                                          -- implement and use bootloader? (default=true)
--            IMEM_AS_ROM           => false                                          -- implement IMEM as read-only memory? (default=false)
--        )
--        port map (
--            -- global control --
--            clk_i                 => CON_CLKIOP,                                    -- global clock, rising edge
--            rst_i                 => not (CON_COLD_RESET or CON_WARM_RESET),        -- global reset, async
--            -- gpio --
--            gpio_o                => open,                                          -- parallel output
--            gpio_i                => X"0000",                                       -- parallel input
--            -- pwm channels --
--            pwm_o                 => open,                                          -- pwm channels
--            -- serial com --
--            uart_txd_o            => CON_UART_TX,                                   -- UART send data
--            uart_rxd_i            => CON_UART_RX,                                   -- UART receive data
--            spi_sclk_o            => CON_SPI_SCLK,                                  -- serial clock line
--            spi_mosi_o            => CON_SPI_MOSI,                                  -- serial data line out
--            spi_miso_i            => CON_SPI_MISO,                                  -- serial data line in
--            spi_cs_o              => CON_SPI_CS,                                    -- SPI CS 0..7
--            twi_sda_io            => open,                                          -- twi serial data line
--            twi_scl_io            => open,                                          -- twi serial clock line
--            -- IOCTL Bus --
--            ioctl_download        => IOP_IOCTL_DOWNLOAD,                            -- Downloading to FPGA.
--            ioctl_upload          => IOP_IOCTL_UPLOAD,                              -- Uploading from FPGA.
--            ioctl_clk             => IOP_IOCTL_CLK,                                 -- I/O Clock.
--            ioctl_wr              => IOP_IOCTL_WR,                                  -- Write Enable to FPGA.
--            ioctl_rd              => IOP_IOCTL_RD,                                  -- Read Enable from FPGA.
--            ioctl_sense           => IOP_IOCTL_SENSE,                               -- Sense to see if HPS accessing ioctl bus.
--            ioctl_select          => IOP_IOCTL_SELECT,                              -- Enable CFU control over ioctl bus.
--            ioctl_addr            => IOP_IOCTL_ADDR,                                -- Address in FPGA to write into.
--            ioctl_dout            => IOP_IOCTL_DOUT,                                -- Data to be written into FPGA.
--            ioctl_din             => IOP_IOCTL_DIN,                                 -- Data to be read into HPS.
--            -- 32-bit wishbone interface --
--            wb_adr_o              => open,                                          -- address
--            wb_dat_i              => (others => '0'),                               -- read data
--            wb_dat_o              => open,                                          -- write data
--            wb_we_o               => open,                                          -- read/write
--            wb_sel_o              => open,                                          -- byte enable
--            wb_stb_o              => open,                                          -- strobe
--            wb_cyc_o              => open,                                          -- valid cycle
--            wb_ack_i              => '0',                                           -- transfer acknowledge
--            -- interrupts --
--            irq_i                 => '0',                                           -- external interrupt request line
--            irq_ack_o             => open                                           -- external interrupt request acknowledge
--        );
--    end generate;

--    -- If the IO Processor is disabled, set the signals to inactive.
--    --
--    IOP_DISABLED: if NEO_ENABLE = 0 and STORM_ENABLE = 0 generate
        IOP_IOCTL_DOWNLOAD        <= '0';
        IOP_IOCTL_UPLOAD          <= '0';
        IOP_IOCTL_CLK             <= '0';
        IOP_IOCTL_WR              <= '0';
        IOP_IOCTL_RD              <= '0';
        IOP_IOCTL_ADDR            <= (others => '0');
        IOP_IOCTL_DOUT            <= (others => '0');
        --IOP_IOCTL_DIN           => open;
        --IOP_IOCTL_SENSE         => open;
        IOP_IOCTL_SELECT          <= '0';
--    end generate;

    -- Assign signals from the emu onto local wires.
    --
    CON_CLKMASTER                 <= clkmaster; 
    clksys                        <= CON_CLKSYS;
    clkvid                        <= CON_CLKVID;
    CON_COLD_RESET                <= cold_reset; 
    CON_WARM_RESET                <= warm_reset; 
    main_leds                     <= CON_MAIN_LEDS;
    CON_PS2_KEY                   <= ps2_key; 
    vga_hb_o                      <= CON_VGA_HB_O;
    vga_vb_o                      <= CON_VGA_VB_O;
    vga_hs_o                      <= CON_VGA_HS_O;
    vga_vs_o                      <= CON_VGA_VS_O;
    vga_r_o                       <= CON_VGA_R_O;
    vga_g_o                       <= CON_VGA_G_O;
    vga_b_o                       <= CON_VGA_B_O;
    audio_l_o                     <= CON_AUDIO_L_O;
    audio_r_o                     <= CON_AUDIO_R_O;

    uart_tx                       <= CON_UART_TX;
    CON_UART_RX                   <= uart_rx;
    sd_sck                        <= CON_SPI_SCLK;
    sd_mosi                       <= CON_SPI_MOSI;
    CON_SPI_MISO                  <= sd_miso;
    sd_cs                         <= CON_SPI_CS(0);
    --
    -- Multiplexer, default IO control to the HPS unless the IOP is enabled and selects. 
    -- The IOP first senses to ensure there is no activity on the bus, then takes control
    --
    CON_IOCTL_DOWNLOAD            <= ioctl_download              when IOP_IOCTL_SELECT = '0'
                                     else
                                     IOP_IOCTL_DOWNLOAD; 
    CON_IOCTL_UPLOAD              <= ioctl_upload                when IOP_IOCTL_SELECT = '0'
                                     else
                                     IOP_IOCTL_UPLOAD; 
    CON_IOCTL_CLK                 <= ioctl_clk                   when IOP_IOCTL_SELECT = '0'
                                     else
                                     IOP_IOCTL_CLK; 
    CON_IOCTL_WR                  <= ioctl_wr                    when IOP_IOCTL_SELECT = '0'
                                     else
                                     IOP_IOCTL_WR; 
    CON_IOCTL_RD                  <= ioctl_rd                    when IOP_IOCTL_SELECT = '0'
                                     else
                                     IOP_IOCTL_RD; 
    CON_IOCTL_ADDR                <= ioctl_addr                  when IOP_IOCTL_SELECT = '0'
                                     else
                                     IOP_IOCTL_ADDR; 
    CON_IOCTL_DOUT                <= X"0000" & ioctl_dout        when IOP_IOCTL_SELECT = '0'
                                     else
                                     IOP_IOCTL_DOUT; 
    ioctl_din                     <= CON_IOCTL_DIN(15 downto 0)  when IOP_IOCTL_SELECT = '0'
                                     else
                                     (others => '0');
    IOP_IOCTL_DIN                 <= CON_IOCTL_DIN               when IOP_IOCTL_SELECT = '1'
                                     else
                                     (others => '0');
    IOP_IOCTL_SENSE               <= ioctl_download or ioctl_upload or ioctl_wr or ioctl_rd;

end rtl;
