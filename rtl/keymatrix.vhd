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
        KEY_SHARP            : in  std_logic := '0';                     -- OSD Keyboard Layout: 0 = PC (a key types its PC legend), 1 = Sharp (by position).

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
-- Minimum key press: every key pressed stays in the matrix until 50 ms after the latest press, so a
-- short tap (a remote or scripted keypress gives make and break back to back) is still seen by software
-- that scans the keyboard only now and then (the MZ-1500 IPL while it probes the Quick Disk).
--
signal HOLD                  : std_logic_vector(119 downto 0);       -- Row r, column c at bit 8r+c.
signal HOLD_CNT              : std_logic_vector(22 downto 0);
constant HOLD_CLKS           : natural := CLK_SYS_HZ / 20;           -- 50 ms.
signal K00, K01, K02, K03, K04, K05, K06, K07, K08, K09, K10, K11, K12, K13, K14 : std_logic_vector(7 downto 0);
--
-- Key code exchange table
--
signal MTEN                  : std_logic_vector(3 downto 0);
signal F_KBDT                : std_logic_vector(7 downto 0);
signal MAP_DATA              : std_logic_vector(7 downto 0);         -- The entry for this key (PC layout: for the PC's SHIFT state).
signal MAP_U                 : std_logic_vector(7 downto 0);         -- PC layout: the entry with the PC's SHIFT up (Sharp layout: the only entry).
signal MAP_S                 : std_logic_vector(7 downto 0);         -- PC layout: the entry with the PC's SHIFT down.
signal KEY_BANK              : std_logic_vector(2 downto 0);
--
-- PC layout. The map has two tables per model, for the PC's SHIFT up and down; an entry's bit 3 is the SHIFT
-- the machine needs for that character. When that differs from the PC's SHIFT, the machine's SHIFT is forced
-- to it while the key is down (and 100 ms after, or to the next key), so @ on a PC types @ even where the
-- machine has @ unshifted on another key. Letters, Return, the cursor keys and so on just pass SHIFT through.
--
signal PC_SHIFT_L            : std_logic;
signal PC_SHIFT_R            : std_logic;
signal PC_SHIFT              : std_logic;
signal SHIFT_KEY             : std_logic;                            -- This event is a PC SHIFT key (12 or 59).
signal MAP_ADDR_U            : std_logic_vector(12 downto 0);
signal MAP_ADDR_S            : std_logic_vector(12 downto 0);
signal FORCE_HELD            : std_logic;                            -- A key that needs another SHIFT is down.
signal FORCE_CNT             : integer range 0 to CLK_SYS_HZ / 10;   -- ... released: SHIFT stays forced 100 ms (or to the next key).
constant FORCE_TAIL_CLKS     : natural := CLK_SYS_HZ / 10;
-- The MZ-80K/80A monitors take SHIFT from a scan before the one that first sees the key, so a key that needs
-- another SHIFT (or follows one that did) reaches the matrix 40 ms after the SHIFT changes, as when typing.
constant KEY_LEAD_CLKS       : natural := CLK_SYS_HZ / 25;
signal PEND_ACT              : std_logic;                            -- A key waiting for its SHIFT lead.
signal PEND_REL              : std_logic;                            -- ... already released (a tap: it shows for the key hold only).
signal PEND_POS              : std_logic_vector(7 downto 0);
signal PEND_CODE             : std_logic_vector(7 downto 0);
signal PEND_CNT              : integer range 0 to CLK_SYS_HZ / 25;
signal HOLD_FIRE             : std_logic;                            -- PC layout: a key reached the matrix (starts the key hold).
signal HOLD_POS              : std_logic_vector(7 downto 0);
signal HOLD_SRC              : std_logic_vector(7 downto 0);
signal FORCE_VAL             : std_logic;
signal FORCE_ACT             : std_logic;
signal FORCE_CODE            : std_logic_vector(7 downto 0);
signal FORCE_POS             : std_logic_vector(7 downto 0);
signal SHIFT_ROW             : integer range 0 to 15;               -- The machine's SHIFT key in the matrix.
signal SHIFT_COL             : integer range 0 to 7;

--
-- HPS access
--
signal IOCTL_KEYMAP_WEN      : std_logic;
signal IOCTL_DIN_KEYMAP      : std_logic_vector(7 downto 0);        -- HPS Data to be read into HPS.

function shift_ovr(v : std_logic_vector(7 downto 0); row, srow, scol : integer; act, val : std_logic) return std_logic_vector is
    variable r : std_logic_vector(7 downto 0) := v;
begin
    if act = '1' and row = srow then
        r(scol) := val;
    end if;
    return r;
end function;

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
        widthad_a            => 13,
        width_a              => 8
    ) 
    PORT MAP (
        -- 0000-07FF Sharp layout (by position), 1000-17FF PC layout with the PC's SHIFT up, 1800-1FFF with it
        -- down; 256 entries per model (KEY_BANK), indexed by E0 flag & scan code (tools/fix_keymap.py).
        -- Port B (once the HPS keymap upload) reads the PC SHIFT down entry alongside.
        clock_a              => CLKBUS(CKMASTER),
        address_a            => MAP_ADDR_U,
        q_a                  => MAP_U,

        clock_b              => CLKBUS(CKMASTER),
        address_b            => MAP_ADDR_S,
        data_b               => (others => '0'),
        wren_b               => '0',
        q_b                  => MAP_S
    );
    IOCTL_DIN_KEYMAP <= (others => '0');

    MAP_ADDR_U <= (not KEY_SHARP) & '0' & KEY_BANK & F_KBDT;
    MAP_ADDR_S <= (not KEY_SHARP) & (not KEY_SHARP) & KEY_BANK & F_KBDT;
    MAP_DATA   <= MAP_S when KEY_SHARP = '0' and PC_SHIFT = '1' else MAP_U;
    PC_SHIFT   <= PC_SHIFT_L or PC_SHIFT_R;
    SHIFT_KEY  <= '1' when F_KBDT = X"12" or F_KBDT = X"59" else '0';
    FORCE_ACT  <= '1' when KEY_SHARP = '0' and (FORCE_HELD = '1' or FORCE_CNT /= 0) else '0';
    HOLD_SRC   <= MAP_DATA when KEY_SHARP = '1' else HOLD_POS;      -- the key the key hold starts for

    -- The machine's SHIFT key: F0 bit 0 on the MZ-80A, row 11 bit 2 on the MZ-80B/2000, row 8 bit 0 on the others.
    SHIFT_ROW  <= 0 when KEY_BANK = "011" else 11 when KEY_BANK(2 downto 1) = "11" else 8;
    SHIFT_COL  <= 2 when KEY_BANK(2 downto 1) = "11" else 0;

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
    process( RST_n, CLKBUS(CKMASTER) )
        -- Press (v = '1') or release the matrix key of a map entry (row in bits 7:4, column in 2:0).
        procedure setk(pos : std_logic_vector(7 downto 0); v : std_logic) is
        begin
            case pos(7 downto 4) is
                when "0000" => SCAN00(conv_integer(pos(2 downto 0))) <= v;
                when "0001" => SCAN01(conv_integer(pos(2 downto 0))) <= v;
                when "0010" => SCAN02(conv_integer(pos(2 downto 0))) <= v;
                when "0011" => SCAN03(conv_integer(pos(2 downto 0))) <= v;
                when "0100" => SCAN04(conv_integer(pos(2 downto 0))) <= v;
                when "0101" => SCAN05(conv_integer(pos(2 downto 0))) <= v;
                when "0110" => SCAN06(conv_integer(pos(2 downto 0))) <= v;
                when "0111" => SCAN07(conv_integer(pos(2 downto 0))) <= v;
                when "1000" => SCAN08(conv_integer(pos(2 downto 0))) <= v;
                when "1001" => SCAN09(conv_integer(pos(2 downto 0))) <= v;
                when "1010" => SCAN10(conv_integer(pos(2 downto 0))) <= v;
                when "1011" => SCAN11(conv_integer(pos(2 downto 0))) <= v;
                when "1100" => SCAN12(conv_integer(pos(2 downto 0))) <= v;
                when "1101" => SCAN13(conv_integer(pos(2 downto 0))) <= v;
                when "1110" => SCAN14(conv_integer(pos(2 downto 0))) <= v;
                when others => null;                                     -- FF: not a Sharp key
            end case;
        end procedure;
    begin
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
            PC_SHIFT_L <= '0';
            PC_SHIFT_R <= '0';
            FORCE_HELD <= '0';
            FORCE_CNT  <= 0;
            FORCE_VAL  <= '0';
            FORCE_CODE <= (others=>'0');
            FORCE_POS  <= (others=>'1');
            PEND_ACT   <= '0';
            PEND_REL   <= '0';
            PEND_POS   <= (others=>'1');
            PEND_CODE  <= (others=>'0');
            PEND_CNT   <= 0;
            HOLD_FIRE  <= '0';
            HOLD_POS   <= (others=>'1');

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1' then
            if FORCE_CNT /= 0 then
                FORCE_CNT <= FORCE_CNT - 1;
            end if;
            HOLD_FIRE <= '0';
            if PEND_ACT = '1' then
                if PEND_CNT /= 0 then
                    PEND_CNT <= PEND_CNT - 1;
                else
                    PEND_ACT <= '0';
                    if PEND_REL = '0' then
                        setk(PEND_POS, '1');
                    end if;
                    HOLD_FIRE <= '1';
                    HOLD_POS  <= PEND_POS;
                end if;
            end if;
            if CLKBUS(CKENCPU) = '1' then
                MTEN           <= MTEN(2 downto 0) & KEY_VALID;
                if KEY_VALID='1' then
                    if(KEY_EXTENDED='1') then
                        FLGE0  <= '1';
                    end if;
                    if(KEY_PRESS='0') then
                        FLGF0  <= '1';
                    end if;
                    -- hps_io gives the E0 (extended) flag with each key, so index the map with it directly.
                    -- (FLGE0 above was for a byte-wise PS/2 stream and was always cleared here, so extended
                    -- keys only ever reached their non-extended entry.)
                    if(PS2_KEY(7 downto 0) = X"AA" ) then
                        F_KBDT <= X"EF";
                    else
                        F_KBDT <= KEY_EXTENDED & PS2_KEY(6 downto 0);
                    end if;
                end if;

                if MTEN(3)='1' then
                    FLGF0 <= '0';
                    if KEY_SHARP = '1' or SHIFT_KEY = '1' then
                        -- Sharp layout, and the PC SHIFT keys in either layout: the key at its position.
                        setk(MAP_U, not FLGF0);
                        -- MZ-80K/80C/1200/80A banks: bit 3 also presses SHIFT for the keys that need it (cursor, INST,
                        -- CLR): F8 bit 0 on the MZ-80K/80C/1200, F0 bit 0 on the MZ-80A.
                        if KEY_SHARP = '1' and KEY_BANK(2) = '0' and MAP_U(3) = '1' and MAP_U /= X"FF" then
                            if KEY_BANK = "011" then SCAN00(0) <= not FLGF0; else SCAN08(0) <= not FLGF0; end if;
                        end if;
                        if SHIFT_KEY = '1' then
                            if F_KBDT = X"12" then PC_SHIFT_L <= not FLGF0; else PC_SHIFT_R <= not FLGF0; end if;
                        end if;
                    elsif FLGF0 = '1' then
                        -- PC layout, key up: release it whichever SHIFT it went down with.
                        setk(MAP_U, '0');
                        setk(MAP_S, '0');
                        if PEND_ACT = '1' and PEND_CODE = F_KBDT then
                            PEND_REL <= '1';
                        end if;
                        if FORCE_HELD = '1' and FORCE_CODE = F_KBDT then
                            setk(FORCE_POS, '0');
                            FORCE_HELD <= '0';
                            FORCE_CNT  <= FORCE_TAIL_CLKS;
                        end if;
                    elsif MAP_DATA /= X"FF" then
                        -- PC layout, key down. A key still held with a forced SHIFT is let go first. If this key
                        -- needs another SHIFT, or SHIFT was forced up to now, the SHIFT changes first and the key
                        -- follows after the lead; otherwise it goes straight into the matrix.
                        if FORCE_HELD = '1' then
                            setk(FORCE_POS, '0');
                        end if;
                        if MAP_DATA(3) /= PC_SHIFT or FORCE_HELD = '1' or FORCE_CNT /= 0 then
                            PEND_ACT  <= '1';
                            PEND_REL  <= '0';
                            PEND_POS  <= MAP_DATA;
                            PEND_CODE <= F_KBDT;
                            PEND_CNT  <= KEY_LEAD_CLKS;
                        else
                            setk(MAP_DATA, '1');
                            HOLD_FIRE <= '1';
                            HOLD_POS  <= MAP_DATA;
                        end if;
                        if MAP_DATA(3) /= PC_SHIFT then
                            FORCE_HELD <= '1';
                            FORCE_VAL  <= MAP_DATA(3);
                            FORCE_CODE <= F_KBDT;
                            FORCE_POS  <= MAP_DATA;
                        else
                            FORCE_HELD <= '0';
                        end if;
                        FORCE_CNT <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process( RST_n, CLKBUS(CKMASTER) ) begin
        if RST_n = '0' then
            HOLD     <= (others => '0');
            HOLD_CNT <= (others => '0');
        elsif rising_edge(CLKBUS(CKMASTER)) then
            if (KEY_SHARP = '1' and CLKBUS(CKENCPU) = '1' and MTEN(3) = '1' and FLGF0 = '0') or (KEY_SHARP = '0' and HOLD_FIRE = '1') then
                if HOLD_SRC(7 downto 4) /= "1111" then                         -- FF: not a Sharp key
                    HOLD(conv_integer(HOLD_SRC(7 downto 4)) * 8 + conv_integer(HOLD_SRC(2 downto 0))) <= '1';
                    if KEY_SHARP = '1' and KEY_BANK(2) = '0' and MAP_DATA(3) = '1' then    -- SHIFT, as above.
                        if KEY_BANK = "011" then HOLD(0) <= '1'; else HOLD(64) <= '1'; end if;
                    end if;
                end if;
                HOLD_CNT <= conv_std_logic_vector(HOLD_CLKS, HOLD_CNT'length);
            elsif HOLD_CNT /= 0 then
                HOLD_CNT <= HOLD_CNT - 1;
            else
                HOLD     <= (others => '0');
            end if;
        end if;
    end process;

    -- The rows the machine reads, with its SHIFT forced while a PC layout key needs it.
    K00 <= shift_ovr(SCAN00 or HOLD(7 downto 0), 0, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K01 <= shift_ovr(SCAN01 or HOLD(15 downto 8), 1, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K02 <= shift_ovr(SCAN02 or HOLD(23 downto 16), 2, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K03 <= shift_ovr(SCAN03 or HOLD(31 downto 24), 3, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K04 <= shift_ovr(SCAN04 or HOLD(39 downto 32), 4, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K05 <= shift_ovr(SCAN05 or HOLD(47 downto 40), 5, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K06 <= shift_ovr(SCAN06 or HOLD(55 downto 48), 6, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K07 <= shift_ovr(SCAN07 or HOLD(63 downto 56), 7, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K08 <= shift_ovr(SCAN08 or HOLD(71 downto 64), 8, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K09 <= shift_ovr(SCAN09 or HOLD(79 downto 72), 9, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K10 <= shift_ovr(SCAN10 or HOLD(87 downto 80), 10, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K11 <= shift_ovr(SCAN11 or HOLD(95 downto 88), 11, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K12 <= shift_ovr(SCAN12 or HOLD(103 downto 96), 12, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K13 <= shift_ovr(SCAN13 or HOLD(111 downto 104), 13, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);
    K14 <= shift_ovr(SCAN14 or HOLD(119 downto 112), 14, SHIFT_ROW, SHIFT_COL, FORCE_ACT, FORCE_VAL);

    PA_L : for I in 0 to 7 generate
        SCANLL(I) <= K00(I) or K01(I) or K02(I) or K03(I) or K04(I) or
                     K05(I) or K06(I) or K07(I) or K08(I) or K09(I) or
                     K10(I) or K11(I) or K12(I) or K13(I) or K14(I);
    end generate PA_L;

    --
    -- response from key access
    --
    PB <= (not SCANLL) when STALL='0' and CONFIG(MZ_B)='1'  else
          (not K00) when PA="0000"                       else
          (not K01) when PA="0001"                       else
          (not K02) when PA="0010"                       else
          (not K03) when PA="0011"                       else
          (not K04) when PA="0100"                       else
          (not K05) when PA="0101"                       else
          (not K06) when PA="0110"                       else
          (not K07) when PA="0111"                       else
          (not K08) when PA="1000"                       else
          (not K09) when PA="1001"                       else
          (not K10) when PA="1010"                       else
          (not K11) when PA="1011"                       else
          (not K12) when PA="1100"                       else
          (not K13) when PA="1101"                       else (others=>'1');

    -- Setup key extension signals to use in mapping.
    --
    KEY_PRESS        <= PS2_KEY(9);
    KEY_EXTENDED     <= PS2_KEY(8);
    KEY_VALID        <= '1' when KEY_FLAG /= PS2_KEY(10)
                        else '0';

    -- Break detect is connected to SCAN line 3, bit 7. When the strobe is set to 03H and the break key is pressed
    -- this signal will go low and detected in the IPL.
    BREAKDETECT      <= not K03(7);

    --
    -- HPS access to reload keymap.
    --
    IOCTL_KEYMAP_WEN <= '1'                          when IOCTL_ADDR(24 downto 16) = "000100011" and IOCTL_WR = '1'
                        else '0';
    IOCTL_DIN        <= X"000000" & IOCTL_DIN_KEYMAP when IOCTL_ADDR(24 downto 16) = "000100011" and IOCTL_RD = '1'
                        else
                        (others=>'0');

end Behavioral;
