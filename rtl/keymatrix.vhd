---------------------------------------------------------------------------------------------------------
--
-- Name:            keymatrix.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     Keyboard module to convert PS2 key codes into Sharp scan matrix key connections.
--                  For each scan output (10 lines) sent by the Sharp, an 8bit response is read in 
--                  and the bits set indicate keys pressed. This allows for multiple keys to be pressed
--                  at the same time. The PS2 scan code is mapped via a rom and the output is used to drive
--                  the data in lines of the 8255.
--
-- Credits:         Nibbles Lab (c) 2005-2012
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         July 2018   - Initial module written, originally based on the Nibbles Lab code but
--                                rewritten to match the overall design of this emulation.
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
library pkgs;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;

entity keymatrix is
    Port (
        RST_n                : in  std_logic;

        -- i8255
        PA                   : in  std_logic_vector(3 downto 0);
        PB                   : out std_logic_vector(7 downto 0);
        STALL                : in  std_logic;
        BREAKDETECT          : out std_logic;

        -- PS/2 Keyboard Data
        PS2_KEY              : in  std_logic_vector(10 downto 0);        -- PS2 Key data.

        -- Different operations modes.
        CONFIG               : in  std_logic_vector(CONFIG_WIDTH);

        -- Clock signals used by this module.
        CLKBUS               : in  std_logic_vector(CLKBUS_WIDTH);

        -- HPS Interface
        IOCTL_DOWNLOAD       : in  std_logic;                            -- HPS Downloading to FPGA.
        IOCTL_UPLOAD         : in  std_logic;                            -- HPS Uploading from FPGA.
        IOCTL_CLK            : in  std_logic;                            -- HPS I/O Clock.
        IOCTL_WR             : in  std_logic;                            -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                            -- HPS Read Enable from FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(31 downto 0);        -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(31 downto 0)         -- HPS Data to be read into HPS.
    );
end keymatrix;

architecture Behavioral of keymatrix is

--
-- prefix flag
--
signal FLGF0                 : std_logic;
signal FLGE0                 : std_logic;
--
-- MZ-series matrix registers
--
signal SCAN00                : std_logic_vector(7 downto 0);
signal SCAN01                : std_logic_vector(7 downto 0);
signal SCAN02                : std_logic_vector(7 downto 0);
signal SCAN03                : std_logic_vector(7 downto 0);
signal SCAN04                : std_logic_vector(7 downto 0);
signal SCAN05                : std_logic_vector(7 downto 0);
signal SCAN06                : std_logic_vector(7 downto 0);
signal SCAN07                : std_logic_vector(7 downto 0);
signal SCAN08                : std_logic_vector(7 downto 0);
signal SCAN09                : std_logic_vector(7 downto 0);
signal SCAN10                : std_logic_vector(7 downto 0);
signal SCAN11                : std_logic_vector(7 downto 0);
signal SCAN12                : std_logic_vector(7 downto 0);
signal SCAN13                : std_logic_vector(7 downto 0);
signal SCAN14                : std_logic_vector(7 downto 0);
signal SCANLL                : std_logic_vector(7 downto 0);
--
-- Key code exchange table
--
signal MTEN                  : std_logic_vector(3 downto 0);
signal F_KBDT                : std_logic_vector(7 downto 0);
signal MAP_DATA              : std_logic_vector(7 downto 0);
signal KEY_BANK              : std_logic_vector(2 downto 0);

--
-- HPS access
--
signal IOCTL_KEYMAP_WEN      : std_logic;
signal IOCTL_DIN_KEYMAP      : std_logic_vector(7 downto 0);        -- HPS Data to be read into HPS.

signal KEY_EXTENDED          : std_logic;
signal KEY_FLAG              : std_logic;
signal KEY_PRESS             : std_logic;
signal KEY_VALID             : std_logic;
--
-- Components
--
component dprom
    GENERIC (
          init_file          : string;
          widthad_a          : natural;
          width_a            : natural
    );
    PORT
    (
          address_a          : IN STD_LOGIC_VECTOR (widthad_a-1 DOWNTO 0);
          address_b          : IN STD_LOGIC_VECTOR (widthad_a-1 DOWNTO 0);
          clock_a            : IN STD_LOGIC ;
          clock_b            : IN STD_LOGIC ;
--        data_a             : IN STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);
          data_b             : IN STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);
--        wren_a             : IN STD_LOGIC;
          wren_b             : IN STD_LOGIC;
          q_a                : OUT STD_LOGIC_VECTOR (width_a-1 DOWNTO 0);
          q_b                : OUT STD_LOGIC_VECTOR (width_a-1 DOWNTO 0)
    );
end component;

begin
    --
    -- Instantiation
    --
    -- 0 = MZ80K  KEYMAP = 256Bytes -> 0000:00ff 0000 bytes padding
    -- 1 = MZ80C  KEYMAP = 256Bytes -> 0100:01ff 0000 bytes padding
    -- 2 = MZ1200 KEYMAP = 256Bytes -> 0200:02ff 0000 bytes padding
    -- 3 = MZ80A  KEYMAP = 256Bytes -> 0300:03ff 0000 bytes padding
    -- 4 = MZ700  KEYMAP = 256Bytes -> 0400:04ff 0000 bytes padding
    -- 5 = MZ80B  KEYMAP = 256Bytes -> 0500:05ff 0000 bytes padding

    MAP0 : dprom
    GENERIC MAP (
      --init_file            => "./software/mif/key_80k_80b.mif",
        init_file            => "./software/mif/combined_keymap.mif",
        widthad_a            => 11,
        width_a              => 8
    ) 
    PORT MAP (
        clock_a              => CLKBUS(CKMASTER),
        address_a            => KEY_BANK & F_KBDT,
--      data_a               => IOCTL_DOUT(7 DOWNTO 0),
--      wren_a               => 
        q_a                  => MAP_DATA,

        clock_b              => IOCTL_CLK,
        address_b            => IOCTL_ADDR(10 DOWNTO 0),
        data_b               => IOCTL_DOUT(7 DOWNTO 0),
        wren_b               => IOCTL_KEYMAP_WEN,
        q_b                  => IOCTL_DIN_KEYMAP
    );

    -- Store changes to the key valid flag in a flip flop.
    process( CLKBUS(CKMASTER) ) begin
        if rising_edge(CLKBUS(CKMASTER)) then
            if CLKBUS(CKENCPU) = '1' then
                KEY_FLAG <= PS2_KEY(10);
            end if;
        end if;
    end process;

    -- Set the key mapping to use according to selected machine.
    --
    process( RST_n, CLKBUS(CKMASTER) ) begin
        if RST_n = '0' then
            KEY_BANK <= "000";
        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1' then
            if CLKBUS(CKENCPU) = '1' then
                if CONFIG(MZ80K)  = '1' then                                 -- Key map for MZ80K
                    KEY_BANK <= "000";
                elsif CONFIG(MZ80C)  = '1' then                              -- Key map for MZ80C
                    KEY_BANK <= "001";
                elsif CONFIG(MZ1200) = '1' then                              -- Key map for MZ1200
                    KEY_BANK <= "010";
                elsif CONFIG(MZ80A)  = '1' then                              -- Key map for MZ80A
                    KEY_BANK <= "011";
                elsif CONFIG(MZ700)  = '1' then                              -- Key map for MZ700
                    KEY_BANK <= "100";
                elsif CONFIG(MZ800)  = '1' then                              -- Key map for MZ800
                    KEY_BANK <= "101";
                elsif CONFIG(MZ80B)  = '1' then                              -- Key map for MZ80B
                    KEY_BANK <= "110";
                elsif CONFIG(MZ2000) = '1' then                              -- Key map for MZ2000
                    KEY_BANK <= "111";
                end if;
            end if;
        end if;
    end process;

    --
    -- Convert
    --
    process( RST_n, CLKBUS(CKMASTER) ) begin
        if RST_n = '0' then
            SCAN00   <= (others=>'0');
            SCAN01   <= (others=>'0');
            SCAN02   <= (others=>'0');
            SCAN03   <= (others=>'0');
            SCAN04   <= (others=>'0');
            SCAN05   <= (others=>'0');
            SCAN06   <= (others=>'0');
            SCAN07   <= (others=>'0');
            SCAN08   <= (others=>'0');
            SCAN09   <= (others=>'0');
            SCAN10   <= (others=>'0');
            SCAN11   <= (others=>'0');
            SCAN12   <= (others=>'0');
            SCAN13   <= (others=>'0');
            SCAN14   <= (others=>'0');
            FLGF0    <= '0';
            FLGE0    <= '0';
            MTEN     <= (others=>'0');

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1' then
            if CLKBUS(CKENCPU) = '1' then
                MTEN           <= MTEN(2 downto 0) & KEY_VALID;
                if KEY_VALID='1' then
                    if(KEY_EXTENDED='1') then
                        FLGE0  <= '1';
                    end if;
                    if(KEY_PRESS='0') then
                        FLGF0  <= '1';
                    end if;
                    if(PS2_KEY(7 downto 0) = X"AA" ) then
                        F_KBDT <= X"EF";
                    else
                        F_KBDT <= FLGE0 & PS2_KEY(6 downto 0); FLGE0<='0';
                    end if;
                end if;
    
                if MTEN(3)='1' then
                    case MAP_DATA(7 downto 4) is                                 
                        when "0000" => SCAN00(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "0001" => SCAN01(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "0010" => SCAN02(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "0011" => SCAN03(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "0100" => SCAN04(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "0101" => SCAN05(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "0110" => SCAN06(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "0111" => SCAN07(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "1000" => SCAN08(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "1001" => SCAN09(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "1010" => SCAN10(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "1011" => SCAN11(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "1100" => SCAN12(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "1101" => SCAN13(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                        when "1110" => SCAN14(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0;
                        when others => SCAN14(conv_integer(MAP_DATA(2 downto 0))) <= not FLGF0; FLGF0 <= '0';
                    end case;
                end if;
            end if;
        end if;
    end process;

    PA_L : for I in 0 to 7 generate
        SCANLL(I) <= SCAN00(I) or SCAN01(I) or SCAN02(I) or SCAN03(I) or SCAN04(I) or
                     SCAN05(I) or SCAN06(I) or SCAN07(I) or SCAN08(I) or SCAN09(I) or
                     SCAN10(I) or SCAN11(I) or SCAN12(I) or SCAN13(I) or SCAN14(I);
    end generate PA_L;

    --
    -- response from key access
    --
    PB <= (not SCANLL) when STALL='0' and CONFIG(MZ_B)='1'  else
          (not SCAN00) when PA="0000"                       else
          (not SCAN01) when PA="0001"                       else
          (not SCAN02) when PA="0010"                       else
          (not SCAN03) when PA="0011"                       else
          (not SCAN04) when PA="0100"                       else
          (not SCAN05) when PA="0101"                       else
          (not SCAN06) when PA="0110"                       else
          (not SCAN07) when PA="0111"                       else
          (not SCAN08) when PA="1000"                       else
          (not SCAN09) when PA="1001"                       else
          (not SCAN10) when PA="1010"                       else
          (not SCAN11) when PA="1011"                       else
          (not SCAN12) when PA="1100"                       else
          (not SCAN13) when PA="1101"                       else (others=>'1');

    -- Setup key extension signals to use in mapping.
    --
    KEY_PRESS        <= PS2_KEY(9);
    KEY_EXTENDED     <= PS2_KEY(8);
    KEY_VALID        <= '1' when KEY_FLAG /= PS2_KEY(10)
                        else '0';

    -- Break detect is connected to SCAN line 3, bit 7. When the strobe is set to 03H and the break key is pressed
    -- this signal will go low and detected in the IPL.
    BREAKDETECT      <= not SCAN03(7);

    --
    -- HPS access to reload keymap.
    --
    IOCTL_KEYMAP_WEN <= '1'                          when IOCTL_ADDR(24 downto 16) = "000100011" and IOCTL_WR = '1'
                        else '0';
    IOCTL_DIN        <= X"000000" & IOCTL_DIN_KEYMAP when IOCTL_ADDR(24 downto 16) = "000100011" and IOCTL_RD = '1'
                        else
                        (others=>'0');

end Behavioral;
