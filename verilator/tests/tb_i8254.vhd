-- Unit test for rtl/i8254 (the 8253/8254 timer of the MZ-80K/A/700/800/1500).
-- Run: make test-i8254 (from verilator/).
--
-- 1. Power-up: every counter in mode 0 with OUT low, idle until a count is written (as mz800emu). The MZ-700
--    monitor never programs counter 2 but enables its interrupt; OUT high there was an endless interrupt.
-- 2. Mode 0 (counter 2, the MZ-700 clock): OUT low after the count is written, high at terminal count, low
--    again when a new count is written (the monitor's interrupt handler does exactly that).
-- 3. Counter latch (control word 80h for counter 2) and LSB/MSB reads of the latched value.
-- 4. Mode 3 (counter 0, the sound): square wave, period = count clocks.
-- 5. Mode 2 (counter 1): one low pulse every count clocks.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_i8254 is
end tb_i8254;

architecture sim of tb_i8254 is
    signal clk                    : std_logic := '0';
    signal rst                    : std_logic := '1';
    signal a                      : std_logic_vector(1 downto 0) := "00";
    signal di, dout                : std_logic_vector(7 downto 0) := (others => '0');
    signal cs_n, wr_n, rd_n       : std_logic := '1';
    signal c0, c1, c2             : std_logic := '0';
    signal o0, o1, o2             : std_logic;
    signal done                   : boolean := false;
    shared variable errors        : natural := 0;

    procedure check(cond : boolean; msg : string) is
    begin
        if not cond then
            report "FAIL: " & msg severity error;
            errors := errors + 1;
        end if;
    end procedure;
begin
    clk <= not clk after 5 ns when not done;

    dut : entity work.i8254
        port map (RST => rst, CLK => clk, ENA => '1', A => a, DI => di, DO => dout, CS_n => cs_n, WR_n => wr_n,
                  RD_n => rd_n, CLK0 => c0, GATE0 => '1', OUT0 => o0, CLK1 => c1, GATE1 => '1', OUT1 => o1,
                  CLK2 => c2, GATE2 => '1', OUT2 => o2);

    process
        procedure wr(addr : natural; v : natural) is
        begin
            wait until rising_edge(clk);
            a <= std_logic_vector(to_unsigned(addr, 2)); di <= std_logic_vector(to_unsigned(v, 8));
            cs_n <= '0'; wr_n <= '0';
            wait until rising_edge(clk);
            cs_n <= '1'; wr_n <= '1';
            for i in 1 to 3 loop wait until rising_edge(clk); end loop;
        end procedure;

        procedure rd(addr : natural; v : out natural) is
        begin
            wait until rising_edge(clk);
            a <= std_logic_vector(to_unsigned(addr, 2)); cs_n <= '0'; rd_n <= '0';
            wait until rising_edge(clk);
            wait for 1 ns;
            v := to_integer(unsigned(dout));
            cs_n <= '1'; rd_n <= '1';
            for i in 1 to 3 loop wait until rising_edge(clk); end loop;
        end procedure;

        -- One counter clock: high for 4 system clocks, low for 4 (the counters count on the falling edge).
        procedure tick(signal c : out std_logic; n : natural) is
        begin
            for i in 1 to n loop
                c <= '1'; for j in 1 to 4 loop wait until rising_edge(clk); end loop;
                c <= '0'; for j in 1 to 4 loop wait until rising_edge(clk); end loop;
            end loop;
        end procedure;

        variable lo, hi, edges, lows, n : natural;
        variable prev : std_logic;
    begin
        for i in 1 to 4 loop wait until rising_edge(clk); end loop;
        rst <= '0';
        for i in 1 to 4 loop wait until rising_edge(clk); end loop;

        -- 1. Power-up.
        check(o0 = '0' and o1 = '0' and o2 = '0', "power-up: OUT0-2 low");
        tick(c2, 70000);                                                 -- no count written: stays quiet
        check(o2 = '0', "power-up: unprogrammed counter 2 stays low while clocked");

        -- 2. Mode 0 on counter 2, count 5.
        wr(3, 16#B0#);                                                   -- counter 2, LSB+MSB, mode 0
        check(o2 = '0', "mode 0: OUT low after the control word");
        wr(2, 5); wr(2, 0);
        tick(c2, 1);                                                     -- loads the count
        tick(c2, 4);
        check(o2 = '0', "mode 0: OUT still low before terminal count");
        tick(c2, 2);
        check(o2 = '1', "mode 0: OUT high at terminal count");
        wr(2, 16#C0#); wr(2, 16#A8#);                                    -- new count (as the MZ-700 clock handler)
        check(o2 = '0', "mode 0: writing a new count drops OUT");

        -- 3. Counter latch.
        tick(c2, 3);                                                     -- load, then count down 2
        wr(3, 16#80#);                                                   -- latch counter 2
        tick(c2, 10);                                                    -- the latched value must not move
        rd(2, lo); rd(2, hi);
        check(hi = 16#A8# and lo >= 16#BC# and lo <= 16#BF#,
              "latch: read " & integer'image(hi) & "/" & integer'image(lo) & ", want A8/BC-BF");

        -- 4. Mode 3 on counter 0, count 10: period 10 clocks.
        wr(3, 16#36#); wr(0, 10); wr(0, 0);
        tick(c0, 4);
        edges := 0; prev := o0;
        for i in 1 to 100 loop
            tick(c0, 1);
            if o0 = '1' and prev = '0' then edges := edges + 1; end if;
            prev := o0;
        end loop;
        check(edges = 10, "mode 3: " & integer'image(edges) & " rising edges in 100 clocks, want 10");

        -- 5. Mode 2 on counter 1, count 8: one low pulse per 8 clocks.
        wr(3, 16#74#); wr(1, 8); wr(1, 0);
        tick(c1, 4);
        lows := 0; prev := o1;
        for i in 1 to 80 loop
            tick(c1, 1);
            if o1 = '0' and prev = '1' then lows := lows + 1; end if;
            prev := o1;
        end loop;
        check(lows = 10, "mode 2: " & integer'image(lows) & " low pulses in 80 clocks, want 10");

        if errors = 0 then
            report "tb_i8254: all checks passed" severity note;
        else
            report "tb_i8254: " & integer'image(errors) & " check(s) failed" severity failure;
        end if;
        done <= true;
        wait;
    end process;
end sim;
