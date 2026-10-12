-- Behavioural stand-in for the dpram (altsyncram) wrapper, for GHDL testbenches only (tests/tb_cmt.vhd).
-- The netlist build leaves dpram as a black box filled by rtl_v/dpram.v; this file is analysed only into the
-- testbench library (ghdl_work_tb), never into the netlist one. init_file is ignored (RAM starts at zero).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram is
    generic (
        init_file            : string;
        widthad_a            : natural;
        width_a              : natural;
        widthad_b            : natural;
        width_b              : natural;
        outdata_reg_a        : string := "UNREGISTERED";
        outdata_reg_b        : string := "UNREGISTERED"
    );
    port (
        clock_a              : in  std_logic := '1';
        clocken_a            : in  std_logic := '1';
        address_a            : in  std_logic_vector(widthad_a-1 downto 0);
        data_a               : in  std_logic_vector(width_a-1 downto 0);
        wren_a               : in  std_logic := '0';
        q_a                  : out std_logic_vector(width_a-1 downto 0);
        clock_b              : in  std_logic;
        clocken_b            : in  std_logic := '1';
        address_b            : in  std_logic_vector(widthad_b-1 downto 0);
        data_b               : in  std_logic_vector(width_b-1 downto 0);
        wren_b               : in  std_logic := '0';
        q_b                  : out std_logic_vector(width_b-1 downto 0)
    );
end dpram;

architecture beh of dpram is
    type mem_t is array(0 to 2**widthad_a - 1) of std_logic_vector(width_a-1 downto 0);
    shared variable mem : mem_t := (others => (others => '0'));
begin
    process(clock_a) begin
        if rising_edge(clock_a) and clocken_a = '1' then
            if wren_a = '1' then mem(to_integer(unsigned(address_a))) := data_a; end if;
            q_a <= mem(to_integer(unsigned(address_a)));
        end if;
    end process;
    process(clock_b) begin
        if rising_edge(clock_b) and clocken_b = '1' then
            if wren_b = '1' then mem(to_integer(unsigned(address_b))) := data_b; end if;
            q_b <= mem(to_integer(unsigned(address_b)));
        end if;
    end process;
end beh;
