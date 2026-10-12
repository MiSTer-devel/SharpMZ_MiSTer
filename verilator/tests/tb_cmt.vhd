-- Unit test for rtl/cmt.vhd (the tape unit), MZ-700 configuration, tape buttons on Auto.
-- Run: make test-cmt (from verilator/).
--
-- A 16-byte file is downloaded into the CMT buffer (header at 400000h into the CMT, data at 410000h into the
-- testbench's tape buffer, which stands in for DDR3 and answers 5 clocks after each address change)
-- and played. The WRITEBIT pulse train is decoded (long high = 1, short = 0; after a tape mark, each byte is a
-- 1 start bit and 8 bits MSB first) and compared with what was downloaded.
--
-- 1. The header block plays back byte for byte, the data block too.
-- 2. The deck stops after the header and stays off for 3M CPU clocks (longer than the CMT's 2M-clock release
--    timer), then restarts: PLAY_READY stays set and the data block still plays (the MZ-2000 BASIC monitor case).
-- 3. The same with the stop in the gap before the data block.
--
-- The testbench analyses its own clkgen_pkg with CLK_SYS_HZ / 64 (only the CMT's PLAY_READY quiet time uses it).
library IEEE;
library pkgs;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use pkgs.config_pkg.all;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;

entity tb_cmt is
end tb_cmt;

architecture sim of tb_cmt is
    signal clk             : std_logic := '0';
    signal rst             : std_logic := '1';
    signal clkbus          : std_logic_vector(CLKBUS_WIDTH) := (others => '0');
    signal config          : std_logic_vector(CONFIG_WIDTH) := (others => '0');
    signal bus_out         : std_logic_vector(CMT_BUS_OUT_WIDTH);
    signal bus_in          : std_logic_vector(CMT_BUS_IN_WIDTH) := (others => '0');
    signal ioctl_wr        : std_logic := '0';
    signal ioctl_addr      : std_logic_vector(24 downto 0) := (others => '0');
    signal ioctl_dout      : std_logic_vector(31 downto 0) := (others => '0');
    signal done            : boolean := false;
    -- Tape data buffer (DDR3 in the core, rtl/tape_ddr.sv): here an array that answers 5 clocks after the
    -- address changes, so the CMT has to wait for TAPEDATA_READY.
    signal td_addr         : std_logic_vector(15 downto 0);
    signal td_wdata, td_rdata : std_logic_vector(7 downto 0) := (others => '0');
    signal td_we           : std_logic;
    signal td_ready        : std_logic := '0';

    type bytes_t is array(natural range <>) of natural;
    constant DATA_LEN      : natural := 16;

    -- Decoder results (written by the decoder process, read by the stimulus).
    signal blk_count       : natural := 0;                 -- blocks completed (first copies after a tape mark)
    signal blk_long        : boolean := false;             -- last block had a long tape mark (header)
    signal zero_run        : natural := 0;                 -- consecutive 0 bits right now
    type store_t is array(0 to 1, 0 to 129) of natural;
    signal got             : store_t := (others => (others => 0));
    signal got_blk         : natural := 0;                 -- which store slot the decoder fills (0 header, 1 data)

    shared variable errors : natural := 0;
    procedure check(cond : boolean; msg : string) is
    begin
        if not cond then report "FAIL: " & msg severity error; errors := errors + 1; end if;
    end procedure;

    function hdr_byte(i : natural) return natural is
        constant name : string := "TESTFILE";
    begin
        if i = 0 then return 1; end if;                                   -- attribute: machine code
        if i >= 1 and i <= 8 then return character'pos(name(i)); end if;
        if i = 9 then return 16#0D#; end if;
        if i = 18 then return DATA_LEN; end if;
        if i = 21 or i = 23 then return 16#12#; end if;                  -- load / exec 1200h
        return 0;
    end function;
    function data_byte(i : natural) return natural is
    begin
        return (i * 37 + 5) mod 256;
    end function;
begin
    clk <= not clk after 5 ns when not done;
    clkbus(CKMASTER) <= clk;
    -- CPU clock enable every other clock: the CMT reads its RAM one clock after setting the address, which the
    -- core's real enable (about 1 in 20 clocks) always allows.
    cpu_ce : process(clk) begin
        if rising_edge(clk) then clkbus(CKENCPU) <= not clkbus(CKENCPU); end if;
    end process;

    dut : entity work.cmt
        port map (RST => rst, CLKBUS => clkbus, CONFIG => config, CMT_BUS_OUT => bus_out, CMT_BUS_IN => bus_in,
                  IOCTL_DOWNLOAD => '0', IOCTL_UPLOAD => '0', IOCTL_CLK => clk, IOCTL_WR => ioctl_wr,
                  IOCTL_RD => '0', IOCTL_ADDR => ioctl_addr, IOCTL_DOUT => ioctl_dout, IOCTL_DIN => open,
                  TAPEDATA_ADDR => td_addr, TAPEDATA_DOUT => td_wdata, TAPEDATA_WE => td_we,
                  TAPEDATA_DIN => td_rdata, TAPEDATA_READY => td_ready,
                  DEBUG_STATUS_LEDS => open);

    tape_buffer : process(clk)
        type mem_t is array(0 to 65535) of std_logic_vector(7 downto 0);
        variable mem    : mem_t := (others => (others => '0'));
        variable last   : std_logic_vector(15 downto 0) := (others => '1');
        variable wait_c : natural := 0;
        variable we_l   : std_logic := '0';
    begin
        if rising_edge(clk) then
            if ioctl_wr = '1' and ioctl_addr(24 downto 16) = "001000001" then
                mem(to_integer(unsigned(ioctl_addr(15 downto 0)))) := ioctl_dout(7 downto 0);
            end if;
            if td_we = '1' and we_l = '0' then mem(to_integer(unsigned(td_addr))) := td_wdata; end if;
            we_l := td_we;
            if td_addr /= last then
                last := td_addr; wait_c := 5; td_ready <= '0';
            elsif wait_c /= 0 then
                wait_c := wait_c - 1;
            else
                td_rdata <= mem(to_integer(unsigned(td_addr))); td_ready <= '1';
            end if;
        end if;
    end process;

    -- Decoder: pulse high time in clocks -> bit; bits -> blocks after a tape mark (>= 20 ones, then zeros).
    decode : process
        variable high, ones, zeros, bitn, b, idx, need : natural := 0;
        variable st   : natural := 0;                                     -- 0 gap, 1 mark ones, 2 mark zeros, 3 bytes
        variable prev : std_logic := '0';
        variable bitv : natural;
        variable long : boolean;
    begin
        wait until rising_edge(clk);
        if bus_out(WRITEBIT) = '1' then
            if clkbus(CKENCPU) = '1' then high := high + 1; end if;      -- high time in CPU clocks
        elsif prev = '1' then                                             -- falling edge: one bit ended
            if high > 1200 then bitv := 1; else bitv := 0; end if;
            high := 0;
            if bitv = 0 then zero_run <= zero_run + 1; else zero_run <= 0; end if;
            case st is
                when 0 =>
                    if bitv = 1 then ones := ones + 1; else ones := 0; end if;
                    if ones >= 15 then st := 1; end if;
                when 1 =>
                    if bitv = 1 then ones := ones + 1; else long := ones >= 30; zeros := 1; st := 2; end if;
                when 2 =>
                    if bitv = 0 then zeros := zeros + 1;
                    else                                                  -- the 1 after the mark
                        st := 3; bitn := 0; idx := 0; b := 0;
                        if long then need := 130; else need := DATA_LEN + 2; end if;
                    end if;
                when others =>
                    if bitn = 0 then
                        if bitv /= 1 then report "decoder: missing start bit" severity warning; end if;
                        bitn := 1;
                    else
                        b := b * 2 + bitv; bitn := bitn + 1;
                        if bitn = 9 then
                            if long then got(0, idx) <= b; else got(1, idx) <= b; end if;
                            idx := idx + 1; b := 0; bitn := 0;
                            if idx = need then
                                blk_long <= long; blk_count <= blk_count + 1; st := 0; ones := 0;
                            end if;
                        end if;
                    end if;
            end case;
        end if;
        prev := bus_out(WRITEBIT);
    end process;

    stim : process
        procedure ioctl(addr : natural; v : natural) is
        begin
            wait until rising_edge(clk);
            ioctl_addr <= std_logic_vector(to_unsigned(addr, 25)); ioctl_dout <= std_logic_vector(to_unsigned(v, 32));
            ioctl_wr <= '1';
            wait until rising_edge(clk);
            ioctl_wr <= '0';
        end procedure;
        procedure play_pulse is                                           -- toggles the motor (MZ-80C series deck)
        begin
            bus_in(PLAY) <= '1'; for i in 1 to 8 loop wait until rising_edge(clk); end loop;
            bus_in(PLAY) <= '0'; for i in 1 to 8 loop wait until rising_edge(clk); end loop;
        end procedure;
        procedure load_and_start is
        begin
            rst <= '1'; config(BUTTONS) <= "00";
            for i in 1 to 10 loop wait until rising_edge(clk); end loop;
            rst <= '0';
            for i in 1 to 10 loop wait until rising_edge(clk); end loop;
            for i in 0 to 127 loop ioctl(16#400000# + i, hdr_byte(i)); end loop;
            for i in 0 to DATA_LEN - 1 loop ioctl(16#410000# + i, data_byte(i)); end loop;
            config(BUTTONS) <= "11";                                      -- Auto: PLAY pressed, motor on
        end procedure;
        procedure check_blocks(tag : string) is
            variable line_s : string(1 to 24 * 4) := (others => ' ');
            variable hx     : string(1 to 16) := "0123456789ABCDEF";
        begin
            for i in 0 to 23 loop
                line_s(i * 4 + 1) := hx(got(0, i) / 16 + 1); line_s(i * 4 + 2) := hx(got(0, i) mod 16 + 1);
            end loop;
            report tag & ": header " & line_s severity note;
            for i in 0 to DATA_LEN - 1 loop
                line_s(i * 4 + 1) := hx(got(1, i) / 16 + 1); line_s(i * 4 + 2) := hx(got(1, i) mod 16 + 1);
            end loop;
            report tag & ": data   " & line_s severity note;
            for i in 0 to 127 loop
                check(got(0, i) = hdr_byte(i), tag & ": header byte " & integer'image(i) & " = " &
                      integer'image(got(0, i)) & ", want " & integer'image(hdr_byte(i)));
            end loop;
            for i in 0 to DATA_LEN - 1 loop
                check(got(1, i) = data_byte(i), tag & ": data byte " & integer'image(i) & " = " &
                      integer'image(got(1, i)) & ", want " & integer'image(data_byte(i)));
            end loop;
        end procedure;
        procedure stopped_wait(tag : string) is
        begin
            play_pulse;                                                   -- motor off
            for i in 1 to 6000000 loop wait until rising_edge(clk); end loop;  -- 3M CPU clocks
            check(bus_out(PLAY_READY) = '1', tag & ": PLAY_READY kept while the deck is stopped");
            play_pulse;                                                   -- motor on again
        end procedure;
        variable n : natural;
    begin
        config(MZ700) <= '1'; config(MZ_80C) <= '1';

        -- 1 and 2: stop right after the header.
        load_and_start;
        wait until blk_count = 1;
        check(blk_long, "test 2: first block is the header");
        stopped_wait("test 2");
        for i in 1 to 80 loop                                             -- the 11,000-pulse data gap is ~390 ms
            wait for 10 ms;
            report "after restart +" & integer'image(i * 10) & " ms: playing " & std_logic'image(bus_out(PLAYING)) &
                   " ready " & std_logic'image(bus_out(PLAY_READY)) & " sense " & std_logic'image(bus_out(SENSE)) &
                   " blocks " & integer'image(blk_count) & " zero run " & integer'image(zero_run) severity note;
            exit when blk_count = 2;
        end loop;
        check(blk_count = 2 and not blk_long, "test 2: the data block plays after the restart");
        check_blocks("test 2");

        -- 3: stop in the gap before the data block.
        n := blk_count;
        load_and_start;
        wait until blk_count = n + 1;
        wait until zero_run > 2000;                                      -- (zero_run counts bits)                                       -- past the header's copy, into the data gap
        stopped_wait("test 3");
        wait until blk_count = n + 2 for 800 ms;
        check(blk_count = n + 2 and not blk_long, "test 3: the data block plays after the restart");
        check_blocks("test 3");

        if errors = 0 then
            report "tb_cmt: all checks passed" severity note;
        else
            report "tb_cmt: " & integer'image(errors) & " check(s) failed" severity failure;
        end if;
        done <= true;
        wait;
    end process;
end sim;
