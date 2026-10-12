---------------------------------------------------------------------------------------------------------
--
-- Name:            clkgen.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     Clock enable generator.
--
--                  Everything in the emulator runs on a single system clock (CKBASE, the MiSTer
--                  clk_sys). This module derives the clock enables the machine needs from it, plus
--                  the square-wave inputs of the 8253/8254 timers, which the timers sample in the
--                  same clock domain.
--
--                  Each output is a fractional accumulator: every clk_sys cycle it adds the target
--                  rate and emits an enable when it wraps at CLK_HZ. Rates are exact rationals
--                  (numerator / denominator Hz). When CLK_HZ is an integer multiple of a rate, the
--                  enable is a plain divide-by-N with no jitter. With CLK_HZ = 70.9376 MHz
--                  (4 x the 17.7344 MHz MZ-700 crystal) every MZ-700/800 rate is exact, and so is
--                  the 8 MHz MZ-80K/80A/80B pixel clock family at 64 MHz.
--
--                  CPU turbo speeds are capped at CLK_HZ/2.
--
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         July 2018   - Initial module written.
--                  October 2018- Updated and seperated so that debug code can be removed at compile time.
--                  2026        - Rewritten for MiSTer: single clock, accumulator clock enables, no PLLs
--                                or derived clocks. MZ-700 8253 sound input corrected to 1.1088 MHz.
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

library IEEE;
library pkgs;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use pkgs.config_pkg.all;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;

entity clkgen is
    Generic (
        CLK_HZ                     : natural := CLK_SYS_HZ               -- Frequency of CKBASE (clk_sys).
    );
    Port (
        RST                        : in  std_logic;                      -- Reset
        -- Clocks
        CKBASE                     : in  std_logic;                      -- System clock (clk_sys).
        CLKBUS                     : out std_logic_vector(CLKBUS_WIDTH); -- Clock and enable signals created by this module.
        -- Different operations modes.
        CONFIG                     : in  std_logic_vector(CONFIG_WIDTH);
        -- Debug modes (unused, kept for interface compatibility).
        DEBUG                      : in  std_logic_vector(DEBUG_WIDTH)
    );
end clkgen;

architecture RTL of clkgen is

    constant ACC_BITS              : natural := 40;
    subtype  acc_t                 is unsigned(ACC_BITS-1 downto 0);

    -- A rate is num/den Hz. The accumulator adds num each cycle and wraps at CLK_HZ*den.
    type rate_t is record
        num                        : acc_t;
        modulus                    : acc_t;
    end record;

    function rate(num : natural; den : natural := 1) return rate_t is
        variable r                 : rate_t;
    begin
        r.num     := to_unsigned(num, ACC_BITS);
        r.modulus := resize(to_unsigned(CLK_HZ, 32) * to_unsigned(den, 16), ACC_BITS);
        return r;
    end function;

    -- Never run the CPU faster than every other clk_sys cycle.
    function capped(r : rate_t) return rate_t is
        variable c                 : rate_t := r;
    begin
        if r.num * 2 > r.modulus then
            c.num := shift_right(r.modulus, 1);
        end if;
        return c;
    end function;

    -- Machine clock rates (Hz). The MZ-700/800 family derive from a 17.7344 MHz crystal.
    constant XTAL_700              : natural := 17734400;
    constant R_2M                  : rate_t  := rate(2000000);
    constant R_4M                  : rate_t  := rate(4000000);
    constant R_8M                  : rate_t  := rate(8000000);
    constant R_16M                 : rate_t  := rate(16000000);
    constant R_32M                 : rate_t  := rate(32000000);
    constant R_3M5                 : rate_t  := rate(XTAL_700, 5);        -- MZ-700 CPU, 3.54688 MHz.
    constant R_7M                  : rate_t  := rate(XTAL_700 * 2, 5);
    constant R_14M                 : rate_t  := rate(XTAL_700 * 4, 5);
    constant R_28M                 : rate_t  := rate(XTAL_700 * 8, 5);
    constant R_56M                 : rate_t  := rate(XTAL_700 * 16, 5);
    constant R_64M                 : rate_t  := rate(64000000);
    -- Timer inputs are square waves, so their enables run at twice the timer clock.
    constant R_SND_2M_X2           : rate_t  := rate(2000000 * 2);
    constant R_SND_700_X2          : rate_t  := rate(XTAL_700 * 2, 16);   -- MZ-700 8253 counter 0, 1.1088 MHz.
    constant R_RTC_31500_X2        : rate_t  := rate(31500 * 2);
    constant R_RTC_31250_X2        : rate_t  := rate(31250 * 2);
    constant R_RTC_HSYNC_X2        : rate_t  := rate(XTAL_700 * 2, 1136); -- MZ-700 line rate, 15.611 kHz.

    signal CPU_RATE                : rate_t;
    signal SND_RATE                : rate_t;
    signal RTC_RATE                : rate_t;

    signal CPU_ACC                 : acc_t;
    signal PER_ACC                 : acc_t;
    signal PSG_ACC                 : acc_t;
    signal SND_ACC                 : acc_t;
    signal RTC_ACC                 : acc_t;

    signal CKENCPUi                : std_logic;
    signal CKENPERi                : std_logic;
    signal CKENPSGi                : std_logic;
    signal CKSOUNDi                : std_logic;
    signal CKRTCi                  : std_logic;

    -- One accumulator step: advance by the rate and pulse the enable when it wraps.
    procedure step(signal acc : inout acc_t; r : rate_t; signal ce : out std_logic) is
        variable nxt               : acc_t;
    begin
        nxt := acc + r.num;
        if nxt >= r.modulus then
            acc <= nxt - r.modulus;
            ce  <= '1';
        else
            acc <= nxt;
            ce  <= '0';
        end if;
    end procedure;

begin

    -- Rate selection from the machine configuration.
    process(CONFIG)
    begin
        case CONFIG(CPUSPEED) is
            when "0001" => CPU_RATE <= R_3M5;
            when "0010" => CPU_RATE <= R_4M;
            when "0011" => CPU_RATE <= R_7M;
            when "0100" => CPU_RATE <= R_8M;
            when "0101" => CPU_RATE <= capped(R_14M);
            when "0110" => CPU_RATE <= capped(R_16M);
            when "0111" => CPU_RATE <= capped(R_28M);
            when "1000" => CPU_RATE <= capped(R_32M);
            when "1001"         => CPU_RATE <= capped(R_56M);  -- Former 56.75 MHz setting.
            when "1010"         => CPU_RATE <= capped(R_64M);  -- Former 64 MHz setting.
            when others => CPU_RATE <= R_2M;
        end case;

        case CONFIG(SNDSPEED) is
            when "01"   => SND_RATE <= R_SND_700_X2;
            when others => SND_RATE <= R_SND_2M_X2;
        end case;

        case CONFIG(RTCSPEED) is
            when "01"   => RTC_RATE <= R_RTC_31250_X2;
            when "10"   => RTC_RATE <= R_RTC_HSYNC_X2;
            when others => RTC_RATE <= R_RTC_31500_X2;
        end case;
    end process;

    process(CKBASE)
    begin
        if rising_edge(CKBASE) then
            if RST = '1' then
                CPU_ACC            <= (others => '0');
                PER_ACC            <= (others => '0');
                PSG_ACC            <= (others => '0');
                SND_ACC            <= (others => '0');
                RTC_ACC            <= (others => '0');
                CKENCPUi           <= '0';
                CKENPERi           <= '0';
                CKENPSGi           <= '0';
                CKSOUNDi           <= '0';
                CKRTCi             <= '0';
            else
                step(CPU_ACC, CPU_RATE, CKENCPUi);
                step(PER_ACC, R_2M,     CKENPERi);
                step(PSG_ACC, R_3M5,    CKENPSGi);

                -- Square waves: toggle on each enable.
                if SND_ACC + SND_RATE.num >= SND_RATE.modulus then
                    SND_ACC        <= SND_ACC + SND_RATE.num - SND_RATE.modulus;
                    CKSOUNDi       <= not CKSOUNDi;
                else
                    SND_ACC        <= SND_ACC + SND_RATE.num;
                end if;
                if RTC_ACC + RTC_RATE.num >= RTC_RATE.modulus then
                    RTC_ACC        <= RTC_ACC + RTC_RATE.num - RTC_RATE.modulus;
                    CKRTCi         <= not CKRTCi;
                else
                    RTC_ACC        <= RTC_ACC + RTC_RATE.num;
                end if;
            end if;
        end if;
    end process;

    CLKBUS(CKMASTER)               <= CKBASE;                            -- System clock.
    CLKBUS(CKSOUND)                <= CKSOUNDi;                          -- Sound timer input, 50/50 square wave (data, sampled on CKBASE).
    CLKBUS(CKRTC)                  <= CKRTCi;                            -- RTC timer input, 50/50 square wave (data, sampled on CKBASE).
    CLKBUS(CKENVIDEO)              <= '0';                               -- Unused: the video controller makes its own pixel enable.
    CLKBUS(CKVIDEO)                <= '0';                               -- Unused.
    CLKBUS(CKIOP)                  <= '0';                               -- Unused (was the IO processor clock).
    CLKBUS(CKENCPU)                <= CKENCPUi;                          -- CPU clock enable.
    CLKBUS(CKENLEDS)               <= CKENCPUi;                          -- Debug LED sampling follows the CPU.
    CLKBUS(CKENPERIPH)             <= CKENPERi;                          -- Peripheral clock enable, 2 MHz.
    CLKBUS(CKENPSG)                <= CKENPSGi;                          -- MZ-800 PSG clock enable, 3.54688 MHz.

end RTL;
