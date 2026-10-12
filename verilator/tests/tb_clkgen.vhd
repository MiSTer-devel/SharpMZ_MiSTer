-- Checks clkgen enable rates and jitter for the MZ-700 and MZ-80K configurations.
-- Run: make test-clkgen (from verilator/).
library IEEE;
library pkgs;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;

entity tb_clkgen is
end tb_clkgen;

architecture sim of tb_clkgen is

    type result_t is record
        count, min_gap, max_gap : natural;
    end record;

    procedure measure(signal clk : in std_logic; signal ce : in std_logic; cycles : natural; variable r : out result_t) is
        variable last, gap, n, mn, mx : natural := 0;
        variable seen                 : boolean := false;
    begin
        mn := natural'high; mx := 0; n := 0;
        for i in 1 to cycles loop
            wait until rising_edge(clk);
            if ce = '1' then
                if seen then
                    gap := i - last;
                    if gap < mn then mn := gap; end if;
                    if gap > mx then mx := gap; end if;
                end if;
                seen := true; last := i; n := n + 1;
            end if;
        end loop;
        r := (n, mn, mx);
    end procedure;

    procedure measure_toggle(signal clk : in std_logic; signal sq : in std_logic; cycles : natural; variable r : out result_t) is
        variable prev  : std_logic := '0';
        variable last, gap, n, mn, mx : natural := 0;
        variable seen  : boolean := false;
    begin
        mn := natural'high; mx := 0; n := 0;
        prev := sq;                                  -- Don't count a wave that is already high as an edge.
        for i in 1 to cycles loop
            wait until rising_edge(clk);
            if sq = '1' and prev = '0' then
                if seen then
                    gap := i - last;
                    if gap < mn then mn := gap; end if;
                    if gap > mx then mx := gap; end if;
                end if;
                seen := true; last := i; n := n + 1;
            end if;
            prev := sq;
        end loop;
        r := (n, mn, mx);
    end procedure;

    signal clk7, clk6 : std_logic := '0';
    signal rst        : std_logic := '1';
    signal cfg7, cfg6 : std_logic_vector(CONFIG_WIDTH) := (others => '0');
    signal bus7, bus6 : std_logic_vector(CLKBUS_WIDTH);

    procedure report_rate(name : string; r : result_t; cycles : natural; clk_hz : real; expect_hz : real; exact : boolean) is
        variable hz : real;
    begin
        hz := real(r.count) * clk_hz / real(cycles);
        report name & ": " & integer'image(integer(hz)) & " Hz (expect " & integer'image(integer(expect_hz)) &
               "), period " & integer'image(r.min_gap) & ".." & integer'image(r.max_gap) & " clocks";
        assert abs(hz - expect_hz) / expect_hz < 0.002 report name & " rate out of tolerance" severity error;
        if exact then
            assert r.min_gap = r.max_gap report name & " has jitter but should be an exact divide" severity error;
        end if;
    end procedure;

begin
    clk7 <= not clk7 after 7.048 ns;   -- ~70.9376 MHz
    clk6 <= not clk6 after 7.8125 ns;  -- 64 MHz

    DUT7 : entity pkgs.clkgen generic map (CLK_HZ => 70937600)
        port map (RST => rst, CKBASE => clk7, CLKBUS => bus7, CONFIG => cfg7, DEBUG => (others => '0'));
    DUT6 : entity pkgs.clkgen generic map (CLK_HZ => 64000000)
        port map (RST => rst, CKBASE => clk6, CLKBUS => bus6, CONFIG => cfg6, DEBUG => (others => '0'));

    process
        variable r : result_t;
        constant N7 : natural := 709376;   -- 10 ms at 70.9376 MHz
        constant N6 : natural := 640000;   -- 10 ms at 64 MHz
    begin
        -- MZ-700: CPU 3.5 MHz, 40 column colour video, 700 sound, HSYNC RTC.
        cfg7(CPUSPEED) <= "0001"; cfg7(VIDSPEED) <= "010"; cfg7(SNDSPEED) <= "01"; cfg7(RTCSPEED) <= "10";
        -- MZ-80K: CPU 2 MHz, 40 column mono video, 2 MHz sound, 31.5 kHz RTC.
        cfg6(CPUSPEED) <= "0000"; cfg6(VIDSPEED) <= "000"; cfg6(SNDSPEED) <= "00"; cfg6(RTCSPEED) <= "00";
        wait for 100 ns; rst <= '0';

        measure(clk7, bus7(CKENCPU), N7, r);          report_rate("MZ-700 CPU",   r, N7, 70937600.0, 3546880.0, true);
        measure_toggle(clk7, bus7(CKSOUND), N7, r);   report_rate("MZ-700 8253 CLK0", r, N7, 70937600.0, 1108400.0, true);
        measure_toggle(clk7, bus7(CKRTC), N7, r);     report_rate("MZ-700 8253 CLK1", r, N7, 70937600.0, 15611.27, true);
        cfg7(CPUSPEED) <= "0111"; wait until rising_edge(clk7);
        measure(clk7, bus7(CKENCPU), N7, r);          report_rate("MZ-700 CPU x8", r, N7, 70937600.0, 28375040.0, false);
        cfg7(CPUSPEED) <= "1001"; wait until rising_edge(clk7);
        measure(clk7, bus7(CKENCPU), N7, r);          report_rate("MZ-700 CPU cap", r, N7, 70937600.0, 35468800.0, true);

        cfg6(CPUSPEED) <= "1010"; wait until rising_edge(clk6);
        measure(clk6, bus6(CKENCPU), N6, r);          report_rate("MZ-80K CPU cap", r, N6, 64000000.0, 32000000.0, true);
        cfg6(CPUSPEED) <= "0000"; wait until rising_edge(clk6);
        measure(clk6, bus6(CKENCPU), N6, r);          report_rate("MZ-80K CPU",   r, N6, 64000000.0, 2000000.0, true);
        measure_toggle(clk6, bus6(CKSOUND), N6, r);   report_rate("MZ-80K 8253 CLK0", r, N6, 64000000.0, 2000000.0, true);
        measure(clk6, bus6(CKENPERIPH), N6, r);       report_rate("MZ-80K periph", r, N6, 64000000.0, 2000000.0, true);

        report "tb_clkgen done";
        std.env.stop;
    end process;
end sim;
