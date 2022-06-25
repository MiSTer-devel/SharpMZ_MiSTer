--
-- mz1e05.vhd
--
-- Floppy Disk Interface Emulation module
-- for MZ-80B/2000 on FPGA
--
-- Nibbles Lab. 2014
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mz1e05 is
    Port (
        -- CPU Signals
        ZRST_n               : in  std_logic;
        ZCLK                 : in  std_logic;
        ZADR                 : in  std_logic_vector(7 downto 0);         -- CPU Address Bus(lower)
        ZRD_n                : in  std_logic;                            -- CPU Read Signal
        ZWR_n                : in  std_logic;                            -- CPU Write Signal
        ZIORQ_n              : in  std_logic;                            -- CPU I/O Request
        ZDI                  : in  std_logic_vector(7 downto 0);         -- CPU Data Bus(in)
        ZDO                  : out std_logic_vector(7 downto 0);         -- CPU Data Bus(out)
        SCLK                 : in  std_logic;                            -- Slow Clock
        -- FD signals
        DS_n                 : out std_logic_vector(4 downto 1);         -- Drive Select
        HS                   : out std_logic;                            -- Head Select
        MOTOR_n              : out std_logic;                            -- Motor On
        INDEX_n              : in  std_logic;                            -- Index Hole Detect
        TRACK00              : in  std_logic;                            -- Track 0
        WPRT_n               : in  std_logic;                            -- Write Protect
        STEP_n               : out std_logic;                            -- Head Step In/Out
        DIREC                : out std_logic;                            -- Head Step Direction
        WGATE_n              : out std_logic;                            -- Write Gate
        DTCLK                : in  std_logic;                            -- Data Clock
        FDI                  : in  std_logic_vector(7 downto 0);         -- Read Data
        FDO                  : out std_logic_vector(7 downto 0)          -- Write Data
    );
end mz1e05;

architecture RTL of mz1e05 is
--
-- Signals
--
signal CSFDC_n               : std_logic;
signal CSDC                  : std_logic;
signal CSDD                  : std_logic;
signal CSDE                  : std_logic;
signal DDEN                  : std_logic;
signal READY                 : std_logic;
signal STEP                  : std_logic;
signal DIRC                  : std_logic;
signal WG                    : std_logic;
signal RCOUNT                : std_logic_vector(12 downto 0);
--
-- Component
--
component mb8876
    Port (
        -- CPU Signals
        ZCLK                 : in  std_logic;
        MR_n                 : in  std_logic;
        A                    : in  std_logic_vector(1 downto 0);         -- CPU Address Bus
        RE_n                 : in  std_logic;                            -- CPU Read Signal
        WE_n                 : in  std_logic;                            -- CPU Write Signal
        CS_n                 : in  std_logic;                            -- CPU Chip Select
        DALI_n               : in  std_logic_vector(7 downto 0);         -- CPU Data Bus(in)
        DALO_n               : out std_logic_vector(7 downto 0);         -- CPU Data Bus(out)
--      DALI                 : in std_logic_vector(7 downto 0);          -- CPU Data Bus(in)
--      DALO                 : out std_logic_vector(7 downto 0);         -- CPU Data Bus(out)
        -- FD signals
        DDEN_n               : in  std_logic;                            -- Double Density
        IP_n                 : in  std_logic;                            -- Index Pulse
        READY                : in  std_logic;                            -- Drive Ready
        TR00_n               : in  std_logic;                            -- Track 0
        WPRT_n               : in  std_logic;                            -- Write Protect
        STEP                 : out std_logic;                            -- Head Step In/Out
        DIRC                 : out std_logic;                            -- Head Step Direction
        WG                   : out std_logic;                            -- Write Gate
        DTCLK                : in  std_logic;                            -- Data Clock
        FDI                  : in  std_logic_vector(7 downto 0);         -- Read Data
        FDO                  : out std_logic_vector(7 downto 0)          -- Write Data
    );
end component;

begin

    --
    -- Instantiation
    --
    FDC0 : mb8876 Port map(
        -- CPU Signals
        ZCLK                 => ZCLK,
        MR_n                 => ZRST_n,
        A                    => ZADR(1 downto 0),                        -- CPU Address Bus
        RE_n                 => ZRD_n,                                   -- CPU Read Signal
        WE_n                 => ZWR_n,                                   -- CPU Write Signal
        CS_n                 => CSFDC_n,                                 -- CPU Chip Select
        DALI_n               => ZDI,                                     -- CPU Data Bus(in)
        DALO_n               => ZDO,                                     -- CPU Data Bus(out)
--      DALI                 => ZDI,                                     -- CPU Data Bus(in)
--      DALO                 => ZDO,                                     -- CPU Data Bus(out)
        -- FD signals
        DDEN_n               => DDEN,                                    -- Double Density
        IP_n                 => INDEX_n,                                 -- Index Pulse
        READY                => READY,                                   -- Drive Ready
        TR00_n               => TRACK00,                                 -- Track 0
        WPRT_n               => WPRT_n,                                  -- Write Protect
        STEP                 => STEP,                                    -- Head Step In/Out
        DIRC                 => DIRC,                                    -- Head Step Direction
        WG                   => WG,                                      -- Write Gate
        DTCLK                => DTCLK,                                   -- Data Clock
        FDI                  => FDI,                                     -- Read Data
        FDO                  => FDO                                      -- Write Data
    );

    --
    -- Registers
    --
    process( ZRST_n, ZCLK ) begin
        if ZRST_n='0' then
            MOTOR_n<='1';
            HS<='0';
            DS_n<="1111";
            DDEN<='0';
        elsif ZCLK'event and ZCLK='0' then
            if ZWR_n='0' then
                if CSDC='1' then
                    MOTOR_n<=not ZDI(7);
                    case ZDI(2 downto 0) is
                        when "100" => DS_n<="1110";
                        when "101" => DS_n<="1101";
                        when "110" => DS_n<="1011";
                        when "111" => DS_n<="0111";
                        when others => DS_n<="1111";
                    end case;
                end if;
                if CSDD='1' then
                    HS<=not ZDI(0);
                end if;
                if CSDE='1' then
                    DDEN<=ZDI(0);
                end if;
            end if;
        end if;
    end process;

    CSFDC_n<='0' when ZIORQ_n='0' and ZADR(7 downto 2)="110110" else '1';
    CSDC<='1' when ZIORQ_n='0' and ZADR=X"DC" else '0';
    CSDD<='1' when ZIORQ_n='0' and ZADR=X"DD" else '0';
    CSDE<='1' when ZIORQ_n='0' and ZADR=X"DE" else '0';

    --
    -- Ready Signal
    --
    process( ZRST_n, SCLK ) begin
        if ZRST_n='0' then
            RCOUNT<=(others=>'0');
            READY<='0';
        elsif SCLK'event and SCLK='0' then
            if INDEX_n='0' then
                RCOUNT<=(others=>'1');
            else
                if RCOUNT="0000000000000" then
                    READY<='0';
                else
                    RCOUNT<=RCOUNT-'1';
                    READY<='1';
                end if;
            end if;
        end if;
    end process;

    --
    -- FDC signals
    --
    STEP_n<=not STEP;
    DIREC<=not DIRC;
    WGATE_n<=not WG;

end RTL;
