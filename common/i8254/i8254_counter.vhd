---------------------------------------------------------------------------------------------------------
--
-- Name:            i8254_counter.vhd
-- Created:         November 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series i8254 Timer
--                  This module emulates the Intel i8254 Programmable Interval Timer.
--
-- Credits:         Based on Verilog pit_counter by Aleksander Osman, 2014.
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         November 2018 - Initial write.
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

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity i8254_counter is
    Port (
        CLK                  : in  std_logic;
        RESET                : in  std_logic;
        --
        DATA_IN              : in  std_logic_vector(7 downto 0);
        DATA_OUT             : out std_logic_vector(7 downto 0);
        WRITE                : in  std_logic;
        READ                 : in  std_logic;
        CTRL_MODE_EN         : in  std_logic;
        LATCH_COUNT_EN       : in  std_logic;
        LATCH_STATUS_EN      : in  std_logic;
        --
        CTR_CLK              : in  std_logic;
        CTR_GATE             : in  std_logic;
        CTR_OUT              : out std_logic
    );
end i8254_counter;

architecture Behavioral of i8254_counter is

subtype LSB is integer range 7 downto 0;
subtype MSB is integer range 15 downto 8;

signal MODE                  : std_logic_vector(2 downto 0);
signal RW_MODE               : std_logic_vector(1 downto 0);
signal BCD                   : std_logic;
signal REGISTER_IN           : std_logic_vector(15 downto 0);
signal REGISTER_OUT          : std_logic_vector(15 downto 0);
signal REGISTER_OUT_LATCHED  : std_logic;
signal NULL_COUNTER          : std_logic;
signal MSB_WRITE             : std_logic;
signal MSB_READ              : std_logic;
signal STATUS                : std_logic_vector(7 downto 0);
signal STATUS_LATCHED        : std_logic;
--
signal CLOCK_LAST            : std_logic;
signal CLOCK_PULSE           : std_logic;
signal GATE_LAST             : std_logic;
signal GATE_SAMPLED          : std_logic;
signal TRIGGER               : std_logic;
signal TRIGGER_SAMPLED       : std_logic;
signal WRITTEN               : std_logic;
signal LOADED                : std_logic;
signal CTR_OUTi              : std_logic;
--
signal MODE0                 : std_logic;
signal MODE1                 : std_logic;
signal MODE2                 : std_logic;
signal MODE3                 : std_logic;
signal MODE4                 : std_logic;
signal MODE5                 : std_logic;
signal LOAD                  : std_logic;
signal LOAD_MODE0            : std_logic;
signal LOAD_MODE1            : std_logic;
signal LOAD_MODE2            : std_logic;
signal LOAD_MODE3            : std_logic;
signal LOAD_MODE4            : std_logic;
signal LOAD_MODE5            : std_logic;
signal LOAD_EVEN             : std_logic;
signal ENABLE_MODE0          : std_logic;
signal ENABLE_MODE1          : std_logic;
signal ENABLE_MODE2          : std_logic;
signal ENABLE_MODE3          : std_logic;
signal ENABLE_MODE4          : std_logic;
signal ENABLE_MODE5          : std_logic;
signal ENABLE_DOUBLE         : std_logic;
signal ENABLE                : std_logic;
signal BCD_DIGIT_1           : std_logic_vector(3 downto 0);
signal BCD_DIGIT_2           : std_logic_vector(3 downto 0);
signal BCD_DIGIT_3           : std_logic_vector(3 downto 0);
signal COUNTER_MINUS_1       : std_logic_vector(15 downto 0);
signal COUNTER_MINUS_2       : std_logic_vector(15 downto 0);
signal COUNTER               : std_logic_vector(15 downto 0);

begin

    -- Control register settings. A write to the control register sets up the mode of this counter, wether it 
    -- uses BCD or 16 bit binary and how the data is accessed, ie. LSB, MSB or both.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            MODE                     <= "010";
            BCD                      <= '0';
            RW_MODE                  <= "01";
        elsif CLK'event and CLK = '1' then
            if CTRL_MODE_EN = '1' then
                MODE                 <= DATA_IN(3 downto 1);
                BCD                  <= DATA_IN(0);
                RW_MODE              <= DATA_IN(5 downto 4);
            end if;
        end if;
    end process;

    -- Staging counter loading. Depending on the mode, the byte is stored in the LSB, NSB or according to the write flag
    -- for 16 bit mode. The staging counter is used to load the main counter.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            REGISTER_IN              <= (others => '0');

        elsif CLK'event and CLK = '1' then

            if CTRL_MODE_EN = '1' then
                REGISTER_IN          <= (others => '0');
            elsif WRITE = '1' and RW_MODE = "11" and MSB_WRITE = '0' then
                REGISTER_IN(LSB)     <= DATA_IN;
            elsif WRITE = '1' and RW_MODE = "11" and MSB_WRITE = '1' then
                REGISTER_IN(MSB)     <= DATA_IN;
            elsif WRITE = '1' and RW_MODE = "01" then
                REGISTER_IN(LSB)     <= DATA_IN;
            elsif WRITE = '1' and RW_MODE = "10" then
                REGISTER_IN(MSB)     <= DATA_IN;
            end if;
        end if;
    end process;

    -- Store the counter contents on every clock until a latch request is made, then we suspend storing
    -- until data is read.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            REGISTER_OUT             <= (others => '0');
        elsif CLK'event and CLK = '1' then

            -- Store each clock cycle, stop on the clock between LATCH going active and REGISTER_OUT_LATCHED going active.
            --
            if LATCH_COUNT_EN = '1' and REGISTER_OUT_LATCHED = '0' then
                REGISTER_OUT         <= COUNTER(15 downto 0);
            elsif REGISTER_OUT_LATCHED = '0' then
                REGISTER_OUT         <= COUNTER(15 downto 0);
            end if;
        end if;
    end process;

    -- Set the output latched signal if LATCH_COUNT_EN goes high, this will stop the storing of the counter until
    -- output latch is cleared, which can be done by a control register access or a 1/2 byte read depending on mode.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            REGISTER_OUT_LATCHED     <= '0';
        elsif CLK'event and CLK = '1' then
            if CTRL_MODE_EN = '1' then
                REGISTER_OUT_LATCHED <= '0';
            elsif LATCH_COUNT_EN = '1' then
                REGISTER_OUT_LATCHED <= '1';
            elsif (READ = '1' and (RW_MODE /= "11" or MSB_READ = '1')) then
                REGISTER_OUT_LATCHED <= '0';
            end if;
        end if;
    end process;

    -- Status flag null count - indicates if the counter can be read (0) or it is being loaded (1).
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            NULL_COUNTER             <= '0';
        elsif CLK'event and CLK = '1' then
            if CTRL_MODE_EN = '1' then
                NULL_COUNTER         <= '1';
            elsif (WRITE = '1' and (RW_MODE /= "11" or MSB_WRITE = '1')) then
                NULL_COUNTER         <= '1';
            elsif LOAD = '1' then
                NULL_COUNTER         <= '0';
            end if;
        end if;
    end process;

    -- Double byte handling for 16 bit load and fetch. An access to the control register resets the flag,
    -- but on each write or read it gets toggled. The flag indicates wether the LSB(0) or MSB(1) is being read or writted.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            MSB_WRITE                <= '0';
            MSB_READ                 <= '0';
        elsif CLK'event and CLK = '1' then
            if CTRL_MODE_EN = '1' then
                MSB_WRITE            <= '0';
                MSB_READ             <= '0';
            elsif WRITE = '1' and RW_MODE = "11" then
                MSB_WRITE            <= not MSB_WRITE;
            elsif READ = '1' and RW_MODE = "11" then
                MSB_READ             <= not MSB_READ;
            end if;
        end if;
    end process;

    -- Status register, contains the Output pin value, the state on the counter being read (1 = can be read) and the programmed
    -- mode of the counter. The current values are latched during the clock between the LATCH_STATUS_EN going active and the latched
    -- signal going active.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            STATUS                   <= (others => '0');
        elsif CLK'event and CLK = '1' then
            if LATCH_STATUS_EN = '1' and STATUS_LATCHED = '0' then
                STATUS               <= CTR_OUTi & NULL_COUNTER & RW_MODE & MODE & BCD;
            end if;
        end if;
    end process;

    -- Set the status latch signal if the LATCH_STATUS_EN goes active. Any read or control mode access resets the flag.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            STATUS_LATCHED           <= '0';
        elsif CLK'event and CLK = '1' then
            if CTRL_MODE_EN = '1' then
                STATUS_LATCHED       <= '0';
            elsif LATCH_STATUS_EN = '1' then
                STATUS_LATCHED       <= '1';
            elsif READ = '1' then
                STATUS_LATCHED       <= '0';
            end if;
        end if;
    end process;

    -- Set the internal counter signals according to the output clock and gate.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            CLOCK_PULSE              <= '0';
            CLOCK_LAST               <= '0';
            GATE_LAST                <= '1';
            GATE_SAMPLED             <= '0';
            TRIGGER                  <= '0';
            TRIGGER_SAMPLED          <= '0';
        elsif CLK'event and CLK = '1' then
            CLOCK_LAST               <= CTR_CLK;
            GATE_LAST                <= CTR_GATE;

            if CLOCK_LAST = '1' and CTR_CLK = '0' then
                CLOCK_PULSE          <= '1';
            else
                CLOCK_PULSE          <= '0';
            end if;

            if CLOCK_LAST = '0' and CTR_CLK = '1' then
                GATE_SAMPLED         <= CTR_GATE;
                TRIGGER_SAMPLED      <= TRIGGER;
            end if;

            if GATE_LAST = '0' and CTR_GATE = '1' then
                TRIGGER              <= '1';
            elsif CLOCK_LAST = '0' and CTR_CLK = '1' then
                TRIGGER              <= '0';
            end if;

        end if;
    end process;

    -- Set the counter output according to programmed mode and events.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            CTR_OUTi                 <= '1';
        elsif CLK'event and CLK = '1' then

            if    CTRL_MODE_EN = '1' then
                if MODE0 = '1' then
                    CTR_OUTi         <= '0';
                elsif MODE1 = '1' or MODE2 = '1' or MODE3 = '1' or MODE4 = '1' or MODE5 = '1' then
                    CTR_OUTi         <= '1';
                end if;

            elsif MODE0 = '1' then
                if WRITE = '1' and RW_MODE = "11" and MSB_WRITE = '0' then
                    CTR_OUTi     <= '0';
                elsif WRITTEN = '1' then
                    CTR_OUTi     <= '0';
                elsif COUNTER = "0000000000000001" and ENABLE = '1' then
                    CTR_OUTi     <= '1';
                end if;

            elsif MODE1 = '1' then
                if LOAD = '1' then
                    CTR_OUTi     <= '0';
                elsif COUNTER = "0000000000000001" and ENABLE = '1' then
                    CTR_OUTi     <= '1';
                end if;

            elsif MODE2 = '1' then
                if CTR_GATE = '0' then
                    CTR_OUTi     <= '1';
                elsif COUNTER = "0000000000000010" and ENABLE = '1' then
                    CTR_OUTi     <= '0';
                elsif LOAD = '1' then
                    CTR_OUTi     <= '1';
                end if;

            elsif MODE3 = '1' then
                if CTR_GATE = '0' then
                    CTR_OUTi     <= '1';
                elsif LOAD = '1' and COUNTER = "000000000000010" and CTR_OUTi = '1' and REGISTER_IN(0) = '0' then
                    CTR_OUTi     <= '0';
                elsif LOAD = '1' and COUNTER = "000000000000000" and CTR_OUTi = '1' and REGISTER_IN(0) = '1' then
                    CTR_OUTi     <= '0';
                elsif LOAD = '1' then
                    CTR_OUTi     <= '1';
                end if;

            elsif MODE4 = '1' then
                if LOAD = '1' then
                    CTR_OUTi     <= '1';
                elsif COUNTER = "0000000000000010" and ENABLE = '1' then
                    CTR_OUTi     <= '0';
                elsif COUNTER = "0000000000000001" and ENABLE = '1' then
                    CTR_OUTi     <= '1';
                end if;

            elsif MODE5 = '1' then
                if    COUNTER = "0000000000000010" and ENABLE = '1' then
                    CTR_OUTi     <= '0';
                elsif COUNTER = "0000000000000001" and ENABLE = '1' then
                    CTR_OUTi     <= '1';
                end if;
            end if;
        end if;
    end process;

    -- Setup flags to indicate if the counter has been written to or loaded. These flags then determine loading operation
    -- of the staging counter into the counter.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            WRITTEN                  <= '0';
            LOADED                   <= '0';
        elsif CLK'event and CLK = '1' then
            if CTRL_MODE_EN = '1' then
                WRITTEN              <= '0';
            elsif WRITE = '1' and RW_MODE /= "11" then
                WRITTEN              <= '1';
            elsif WRITE = '1' and RW_MODE = "11" and MSB_WRITE = '1' then
                WRITTEN              <= '1';
            elsif LOAD = '1' then
                WRITTEN              <= '0';
            end if;

            if CTRL_MODE_EN = '1' then
                LOADED               <= '0';
            elsif LOAD = '1' then
                LOADED               <= '1';
            end if;
        end if;
    end process;

    -- Process to present the requested data, according to mode, to the uC. The data is latched for timing delay to allow the uC
    -- more time to read the byte.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            DATA_OUT                 <= (others => '0');
        elsif CLK'event and CLK = '1' then
            if STATUS_LATCHED = '1' then
                DATA_OUT             <= STATUS;
            elsif RW_MODE = "11" and MSB_READ = '0' then
                DATA_OUT             <= REGISTER_OUT(LSB);
            elsif RW_MODE = "11" and MSB_READ = '1' then
                DATA_OUT             <= REGISTER_OUT(MSB);
            elsif RW_MODE = "01" then
                DATA_OUT             <= REGISTER_OUT(LSB);
            else
                DATA_OUT             <= REGISTER_OUT(MSB);
            end if;
        end if;
    end process;

    -- Load up the primary counter according to the programmed mode and load signals coming from the uC.
    --
    process(RESET, CLK)
    begin
        if RESET = '1' then
            COUNTER                  <= (others => '1');
        elsif CLK'event and CLK = '1' then
            if LOAD_EVEN = '1' then
                COUNTER              <= REGISTER_IN(15 downto 1) & '0';
            elsif LOAD = '1' then
                COUNTER              <= REGISTER_IN;
            elsif ENABLE_DOUBLE = '1' then
                COUNTER              <= COUNTER_MINUS_2;
            elsif ENABLE = '1' then
                COUNTER              <= COUNTER_MINUS_1;
            end if;
        end if;
    end process;


    -- Quick reference signals to indicate programmed mode.
    --
    MODE0        <= '1' when MODE = "000"
                    else '0';
    MODE1        <= '1' when MODE = "001"
                    else '0';
    MODE2        <= '1' when MODE(1 downto 0) = "10"
                    else '0';
    MODE3        <= '1' when MODE(1 downto 0) = "11"
                    else '0';
    MODE4        <= '1' when MODE = "100"
                    else '0';
    MODE5        <= '1' when MODE = "101"
                    else '0';

    -- Quick reference signals to indicate a load is required for a given mode.
    --
    LOAD_MODE0   <= '1' when MODE0 = '1' and WRITTEN = '1'
                    else '0';
    LOAD_MODE1   <= '1' when MODE1 = '1' and WRITTEN = '1' and TRIGGER_SAMPLED = '1'
                    else '0';
    LOAD_MODE2   <= '1' when MODE2 = '1' and (WRITTEN = '1' or TRIGGER_SAMPLED = '1' or (LOADED = '1' and GATE_SAMPLED = '1' and COUNTER = "0000000000000001"))
                    else '0';
    LOAD_MODE3   <= '1' when MODE3 = '1' and (WRITTEN = '1' or TRIGGER_SAMPLED = '1' or (LOADED = '1' and GATE_SAMPLED = '1' and ((COUNTER = "0000000000000010" and (REGISTER_IN(0) = '0' or CTR_OUTi = '0')) or (COUNTER = "0000000000000000" and REGISTER_IN(0) = '1' and CTR_OUTi = '1')))) 
                    else '0';
    LOAD_MODE4   <= '1' when MODE4 = '1' and WRITTEN = '1'
                    else '0';
    LOAD_MODE5   <= '1' when MODE5 = '1' and (WRITTEN = '1' or LOADED = '1') and TRIGGER_SAMPLED = '1'
                    else '0';

    -- Quick reference signals to indicate a programmed mode can be enabled and set running.
    --
    ENABLE_MODE0 <= '1' when MODE0 = '1' and GATE_SAMPLED = '1' and MSB_WRITE = '0'
                    else '0';
    ENABLE_MODE1 <= '1' when MODE1 = '1'
                    else '0';
    ENABLE_MODE2 <= '1' when MODE2 = '1' and GATE_SAMPLED = '1'
                    else '0';
    ENABLE_MODE3 <= '1' when MODE3 = '1' and GATE_SAMPLED = '1'
                    else '0';
    ENABLE_MODE4 <= '1' when MODE4 = '1' and GATE_SAMPLED = '1'
                    else '0';
    ENABLE_MODE5 <= '1' when MODE5 = '1'
                    else '0';

    -- Signals to indicate the type of data to be loaded into the primary counter according to programmed mode.
    --
    LOAD         <= '1' when CLOCK_PULSE = '1' and (LOAD_MODE0 = '1' or LOAD_MODE1 = '1' or LOAD_MODE2 = '1' or LOAD_MODE3 = '1' or LOAD_MODE4 = '1' or LOAD_MODE5 = '1')
                    else '0';
    LOAD_EVEN    <= '1' when LOAD = '1' and MODE3 = '1' 
                    else '0';
    ENABLE       <= '1' when LOAD = '0' and LOADED = '1' and CLOCK_PULSE = '1' and (ENABLE_MODE0 = '1' or ENABLE_MODE1 = '1' or ENABLE_MODE2 = '1' or ENABLE_MODE4 = '1' or ENABLE_MODE5 = '1')
                    else '0';
    ENABLE_DOUBLE<= '1' when LOAD = '0' and LOADED = '1' and CLOCK_PULSE = '1' and ENABLE_MODE3 = '1'
                    else '0';


    -- BCD logic. Calculate each digit to ease the main 
    BCD_DIGIT_3  <= COUNTER(15 downto 12) - X"1";
    BCD_DIGIT_2  <= COUNTER(11 downto 8)  - X"1";
    BCD_DIGIT_1  <= COUNTER(7  downto 4)  - X"1";

    -- Count down of the primary counter, 1 clock at a time. If we are in BCD mode, adjust count to reflect the BCD value, otherwise make
    -- a normal binary countdown.
    --
    COUNTER_MINUS_1 <= X"9999"                                     when BCD = '1' and COUNTER = X"0000"
                      else
                      BCD_DIGIT_3 & X"999"                        when BCD = '1' and COUNTER(11 downto 0) = X"000"
                      else
                      COUNTER(15 downto 12) & BCD_DIGIT_2 & X"99" when BCD = '1' and COUNTER(7 downto 0) = X"00"
                      else
                      COUNTER(15 downto 8) & BCD_DIGIT_1 & X"9"   when BCD = '1' and COUNTER(3 downto 0) = X"0"
                      else
                      COUNTER - X"0001";

    -- Count down evenly. Same as above but we count down 2 clocks at a time.
    --
    COUNTER_MINUS_2 <= X"9998"                                     when BCD = '1' and COUNTER = X"0000"
                       else
                       BCD_DIGIT_3 & X"998"                        when BCD = '1' and COUNTER(11 downto 0) = X"000"
                       else
                       COUNTER(15 downto 12) & BCD_DIGIT_2 & X"98" when BCD = '1' and COUNTER(7 downto 0) = X"00"
                       else
                       COUNTER(15 downto 8) & BCD_DIGIT_1 & X"8"   when BCD = '1' and COUNTER(3 downto 0) = X"0"
                       else
                       COUNTER - X"0002";

    -- Counter output.
    --
    CTR_OUT      <= CTR_OUTi;
end Behavioral;
