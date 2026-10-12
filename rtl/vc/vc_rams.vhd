---------------------------------------------------------------------------------------------------------
--
-- Name:            vc_rams.vhd
-- Description:     Video memories for the v2 VideoController, built on rtl/dpram.vhd.
--
--                  The originals (VideoRAM_DP_3208/3216, ChrGenRAM_DP_3208 in the tranZPUter sources)
--                  are four byte lanes held in shared variables written from two processes, which
--                  GHDL synthesis cannot handle. These keep the same entities and behaviour:
--
--                    - Port A: 32-bit, byte / half-word / word writes; the read word is registered
--                      and the lane for a byte read is selected by the current address. At an
--                      address ending in 10 the upper half-word is returned (the original gave one
--                      byte, which lost plane III in MZ-800 640x200 EXOR/OR/PSET on odd bytes).
--                    - Port B: 8-bit (3208) or 16-bit (3216); registered data, lane selected
--                      combinationally by the current address. The MZ-800 renderer relies on that.
--
--                  Both clocks are clk_sys in this core.
--
-- Copyright:       (c) 2020-2022 Philip Smart <philip.smart@net2net.org> (original entities)
--                  2026 SharpMZ MiSTer contributors (dpram implementation)
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
use ieee.std_logic_1164.all;

package vc_rams_pkg is
    component dpram
        generic (
            init_file        : string  := "";
            widthad_a        : natural;
            width_a          : natural := 8;
            widthad_b        : natural;
            width_b          : natural := 8;
            outdata_reg_a    : string  := "UNREGISTERED";
            outdata_reg_b    : string  := "UNREGISTERED"
        );
        port (
            clock_a          : in  std_logic;
            clocken_a        : in  std_logic := '1';
            address_a        : in  std_logic_vector(widthad_a-1 downto 0);
            data_a           : in  std_logic_vector(width_a-1 downto 0);
            wren_a           : in  std_logic := '1';
            q_a              : out std_logic_vector(width_a-1 downto 0);
            clock_b          : in  std_logic;
            clocken_b        : in  std_logic := '1';
            address_b        : in  std_logic_vector(widthad_b-1 downto 0);
            data_b           : in  std_logic_vector(width_b-1 downto 0);
            wren_b           : in  std_logic := '1';
            q_b              : out std_logic_vector(width_b-1 downto 0)
        );
    end component;

    -- Port A write lane enables and data for a 32-bit word made of four byte lanes.
    function lane_we(we, wbyte, whalf : std_logic; a : std_logic_vector(1 downto 0); lane : natural) return std_logic;
    function lane_data(d : std_logic_vector(31 downto 0); wbyte, whalf : std_logic; lane : natural) return std_logic_vector;
end package;

package body vc_rams_pkg is
    function lane_we(we, wbyte, whalf : std_logic; a : std_logic_vector(1 downto 0); lane : natural) return std_logic is
    begin
        if we = '0' then
            return '0';
        elsif wbyte = '0' and whalf = '0' then
            return '1';                                                        -- Word.
        elsif wbyte = '1' then
            if (lane = 0 and a = "00") or (lane = 1 and a = "01") or (lane = 2 and a = "10") or (lane = 3 and a = "11") then
                return '1';
            end if;
            return '0';
        else                                                                   -- Half word.
            if (lane < 2 and a(1) = '0') or (lane >= 2 and a(1) = '1') then
                return '1';
            end if;
            return '0';
        end if;
    end function;

    function lane_data(d : std_logic_vector(31 downto 0); wbyte, whalf : std_logic; lane : natural) return std_logic_vector is
    begin
        if wbyte = '0' and whalf = '0' then
            return d(lane*8+7 downto lane*8);
        elsif whalf = '1' then
            if lane = 1 or lane = 3 then
                return d(15 downto 8);
            end if;
            return d(7 downto 0);
        end if;
        return d(7 downto 0);
    end function;
end package body;

---------------------------------------------------------------------------------------------------------
-- 32-bit port A, 8-bit port B.
---------------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vc_rams_pkg.all;

entity VideoRAM_DP_3208 is
    generic (
        addrbits             : integer := 16
    );
    port (
        clkA                 : in  std_logic;
        memAAddr             : in  std_logic_vector(addrbits-1 downto 0);
        memAWriteEnable      : in  std_logic;
        memAWriteByte        : in  std_logic;
        memAWriteHalfWord    : in  std_logic;
        memAWrite            : in  std_logic_vector(31 downto 0);
        memARead             : out std_logic_vector(31 downto 0);

        clkB                 : in  std_logic;
        memBAddr             : in  std_logic_vector(addrbits-1 downto 0);
        memBWriteEnable      : in  std_logic;
        memBWrite            : in  std_logic_vector(7 downto 0);
        memBRead             : out std_logic_vector(7 downto 0)
    );
end VideoRAM_DP_3208;

architecture rtl of VideoRAM_DP_3208 is
    type lanes_t is array(0 to 3) of std_logic_vector(7 downto 0);
    signal qa, qb            : lanes_t;
    signal wa, wb            : std_logic_vector(3 downto 0);
    signal word              : std_logic_vector(31 downto 0);
begin
    LANES: for i in 0 to 3 generate
        wa(i) <= lane_we(memAWriteEnable, memAWriteByte, memAWriteHalfWord, memAAddr(1 downto 0), i);
        wb(i) <= '1' when memBWriteEnable = '1' and memBAddr(1 downto 0) = std_logic_vector(to_unsigned(i, 2)) else '0';
        RAM: dpram
            generic map (widthad_a => addrbits-2, width_a => 8, widthad_b => addrbits-2, width_b => 8)
            port map (
                clock_a   => clkA, address_a => memAAddr(addrbits-1 downto 2),
                data_a    => lane_data(memAWrite, memAWriteByte, memAWriteHalfWord, i), wren_a => wa(i), q_a => qa(i),
                clock_b   => clkB, address_b => memBAddr(addrbits-1 downto 2),
                data_b    => memBWrite, wren_b => wb(i), q_b => qb(i)
            );
    end generate;

    word     <= qa(3) & qa(2) & qa(1) & qa(0);
    memARead <= word                  when memAAddr(1 downto 0) = "00" else
                X"000000" & qa(1)     when memAAddr(1 downto 0) = "01" else
                X"0000" & qa(3) & qa(2) when memAAddr(1 downto 0) = "10" else   -- Upper half-word (MZ-800 640x200 read-modify-write).
                X"000000" & qa(3);
    memBRead <= qb(0) when memBAddr(1 downto 0) = "00" else
                qb(1) when memBAddr(1 downto 0) = "01" else
                qb(2) when memBAddr(1 downto 0) = "10" else
                qb(3);
end rtl;

---------------------------------------------------------------------------------------------------------
-- 32-bit port A, 16-bit port B (VRAM: character and attribute bytes read together).
---------------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.vc_rams_pkg.all;

entity VideoRAM_DP_3216 is
    generic (
        addrbits             : integer := 16
    );
    port (
        clkA                 : in  std_logic;
        memAAddr             : in  std_logic_vector(addrbits-1 downto 0);
        memAWriteEnable      : in  std_logic;
        memAWriteByte        : in  std_logic;
        memAWriteHalfWord    : in  std_logic;
        memAWrite            : in  std_logic_vector(31 downto 0);
        memARead             : out std_logic_vector(31 downto 0);

        clkB                 : in  std_logic;
        memBAddr             : in  std_logic_vector(addrbits-2 downto 0);
        memBWriteEnable      : in  std_logic;
        memBWrite            : in  std_logic_vector(15 downto 0);
        memBRead             : out std_logic_vector(15 downto 0)
    );
end VideoRAM_DP_3216;

architecture rtl of VideoRAM_DP_3216 is
    type lanes_t is array(0 to 3) of std_logic_vector(7 downto 0);
    signal qa, qb            : lanes_t;
    signal wa, wb            : std_logic_vector(3 downto 0);
    signal word              : std_logic_vector(31 downto 0);
begin
    LANES: for i in 0 to 3 generate
        wa(i) <= lane_we(memAWriteEnable, memAWriteByte, memAWriteHalfWord, memAAddr(1 downto 0), i);
        -- Lanes 0/1 hold the even 16-bit word, lanes 2/3 the odd one.
        wb(i) <= '1' when memBWriteEnable = '1' and ((i < 2 and memBAddr(0) = '0') or (i >= 2 and memBAddr(0) = '1')) else '0';
        RAM: dpram
            generic map (widthad_a => addrbits-2, width_a => 8, widthad_b => addrbits-2, width_b => 8)
            port map (
                clock_a   => clkA, address_a => memAAddr(addrbits-1 downto 2),
                data_a    => lane_data(memAWrite, memAWriteByte, memAWriteHalfWord, i), wren_a => wa(i), q_a => qa(i),
                clock_b   => clkB, address_b => memBAddr(addrbits-2 downto 1),
                data_b    => memBWrite((i mod 2)*8+7 downto (i mod 2)*8), wren_b => wb(i), q_b => qb(i)
            );
    end generate;

    word     <= qa(3) & qa(2) & qa(1) & qa(0);
    memARead <= word                  when memAAddr(1 downto 0) = "00" else
                X"000000" & qa(1)     when memAAddr(1 downto 0) = "01" else
                X"0000" & qa(3) & qa(2) when memAAddr(1 downto 0) = "10" else   -- Upper half-word (MZ-800 640x200 read-modify-write).
                X"000000" & qa(3);
    memBRead <= qb(1) & qb(0) when memBAddr(0) = '0' else
                qb(3) & qb(2);
end rtl;

---------------------------------------------------------------------------------------------------------
-- Character generator RAM (PCG). Same shape as VideoRAM_DP_3208; the original carried an inline
-- MZ-80A font, which this core loads from its combined CG ROM instead.
---------------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity ChrGenRAM_DP_3208 is
    generic (
        addrbits             : integer := 16
    );
    port (
        clkA                 : in  std_logic;
        memAAddr             : in  std_logic_vector(addrbits-1 downto 0);
        memAWriteEnable      : in  std_logic;
        memAWriteByte        : in  std_logic;
        memAWriteHalfWord    : in  std_logic;
        memAWrite            : in  std_logic_vector(31 downto 0);
        memARead             : out std_logic_vector(31 downto 0);

        clkB                 : in  std_logic;
        memBAddr             : in  std_logic_vector(addrbits-1 downto 0);
        memBWriteEnable      : in  std_logic;
        memBWrite            : in  std_logic_vector(7 downto 0);
        memBRead             : out std_logic_vector(7 downto 0)
    );
end ChrGenRAM_DP_3208;

architecture rtl of ChrGenRAM_DP_3208 is
begin
    RAM: entity work.VideoRAM_DP_3208
        generic map (addrbits => addrbits)
        port map (
            clkA => clkA, memAAddr => memAAddr, memAWriteEnable => memAWriteEnable, memAWriteByte => memAWriteByte,
            memAWriteHalfWord => memAWriteHalfWord, memAWrite => memAWrite, memARead => memARead,
            clkB => clkB, memBAddr => memBAddr, memBWriteEnable => memBWriteEnable, memBWrite => memBWrite, memBRead => memBRead
        );
end rtl;
