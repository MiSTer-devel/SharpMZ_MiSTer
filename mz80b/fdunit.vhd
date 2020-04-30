--
-- fdunit.vhd
--
-- Floppy Disk Drive Unit Emulation module
-- for MZ-80B/2000 on FPGA
--
-- Nibbles Lab. 2014
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity fdunit is
    Port (
        RST_n                : in  std_logic;                            -- Reset
        CLK                  : in  std_logic;                            -- System Clock
        -- Interrupt
        INTO                 : out std_logic;                            -- Step Pulse interrupt
        -- FD signals
        FCLK                 : in  std_logic;
        DS_n                 : in  std_logic_vector(4 downto 1);         -- Drive Select
        HS                   : in  std_logic;                            -- Head Select
        MOTOR_n              : in  std_logic;                            -- Motor On
        INDEX_n              : out std_logic;                            -- Index Hole Detect
        TRACK00              : out std_logic;                            -- Track 0
        WPRT_n               : out std_logic;                            -- Write Protect
        STEP_n               : in  std_logic;                            -- Head Step In/Out
        DIREC                : in  std_logic;                            -- Head Step Direction
        WG_n                 : in  std_logic;                            -- Write Gate
        DTCLK                : out std_logic;                            -- Data Clock
        FDI                  : in  std_logic_vector(7 downto 0);         -- Write Data
        FDO                  : out std_logic_vector(7 downto 0);         -- Read Data
        -- Buffer RAM I/F
        BCS_n                : out std_logic;                            -- RAM Request
        BADR                 : out std_logic_vector(22 downto 0);        -- RAM Address
        BWR_n                : out std_logic;                            -- RAM Write Signal
        BDI                  : in  std_logic_vector(7 downto 0);         -- Data Bus Input from RAM
        BDO                  : out std_logic_vector(7 downto 0)          -- Data Bus Output to RAM
        -- HPS Interface
        IOCTL_DOWNLOAD       : in  std_logic;                           -- HPS Downloading to FPGA.
        IOCTL_INDEX          : in  std_logic_vector(7 downto 0);        -- Menu index used to upload file.
        IOCTL_WR             : in  std_logic;                           -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                           -- HPS Read Enable from FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);       -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0);       -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0);       -- HPS Data to be read into HPS.
        IOCTL_INTERRUPT      : out std_logic                            -- HPS Interrupt.
    );
end fdunit;

architecture RTL of fdunit is
--
-- Floppy Signals
--
signal RDO0                  : std_logic_vector(7 downto 0);
signal RDO1                  : std_logic_vector(7 downto 0);
signal IDX_0                 : std_logic;
signal IDX_1                 : std_logic;
signal TRK00_0               : std_logic;
signal TRK00_1               : std_logic;
signal WPRT_0                : std_logic;
signal WPRT_1                : std_logic;
signal FDO0                  : std_logic_vector(7 downto 0);
signal FDO1                  : std_logic_vector(7 downto 0);
signal DTCLK0                : std_logic;
signal DTCLK1                : std_logic;
--
-- Control
--
signal INT0                  : std_logic;
signal INT1                  : std_logic;
--
-- Memory Access
--
signal BCS0_n                : std_logic;
signal BCS1_n                : std_logic;
signal BADR0                 : std_logic_vector(22 downto 0);
signal BADR1                 : std_logic_vector(22 downto 0);
signal BWR0_n                : std_logic;
signal BWR1_n                : std_logic;
signal BDO0                  : std_logic_vector(7 downto 0);
signal BDO1                  : std_logic_vector(7 downto 0);
--
-- Component
--
component fd55b
    generic
    (
        DS_SW                : std_logic_vector(4 downto 1) := "1111";
        REG_ADDR             : std_logic_vector(15 downto 0) := "0000000000000000"
    );
    Port (
        RST_n                : in  std_logic;                            -- Reset
        CLK                  : in  std_logic;                            -- System Clock
        -- Interrupt
        INTO                 : out std_logic;                            -- Step Pulse interrupt
        -- FD signals
        FCLK                 : in std_logic;
        DS_n                 : in std_logic_vector(4 downto 1);          -- Drive Select
        HS                   : in std_logic;                             -- Head Select
        MOTOR_n              : in std_logic;                             -- Motor On
        INDEX_n              : out std_logic;                            -- Index Hole Detect
        TRACK00              : out std_logic;                            -- Track 0
        WPRT_n               : out std_logic;                            -- Write Protect
        STEP_n               : in std_logic;                             -- Head Step In/Out
        DIREC                : in std_logic;                             -- Head Step Direction
        WG_n                 : in std_logic;                             -- Write Gate
        DTCLK                : out std_logic;                            -- Data Clock
        FDI                  : in std_logic_vector(7 downto 0);          -- Write Data
        FDO                  : out std_logic_vector(7 downto 0);         -- Read Data
        -- Buffer RAM I/F
        BCS_n                : out std_logic;                            -- RAM Request
        BADR                 : out std_logic_vector(22 downto 0);        -- RAM Address
        BWR_n                : out std_logic;                            -- RAM Write Signal
        BDI                  : in std_logic_vector(7 downto 0);          -- Data Bus Input from RAM
        BDO                  : out std_logic_vector(7 downto 0)          -- Data Bus Output to RAM
        -- HPS Interface
        IOCTL_DOWNLOAD       : in  std_logic;                            -- HPS Downloading to FPGA.
        IOCTL_INDEX          : in  std_logic_vector(7 downto 0);         -- Menu index used to upload file.
        IOCTL_WR             : in  std_logic;                            -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                            -- HPS Read Enable from FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.
        IOCTL_INTERRUPT      : out std_logic                             -- HPS Interrupt.
    );
end component;

begin

    FDD0 : fd55b generic map (
        DS_SW                => "1110",
        REG_ADDR             => X"0040"
    )
    Port map (
        RST_n                => RST_n,                                   -- Reset
        CLK                  => CLK,                                     -- System Clock
        -- Interrupt
        INTO                 => INT0,                                    -- Step Pulse interrupt
        -- FD signals
        FCLK                 => FCLK,
        DS_n                 => DS_n,                                    -- Drive Select
        HS                   => HS,                                      -- Head Select
        MOTOR_n              => MOTOR_n,                                 -- Motor On
        INDEX_n              => IDX_0,                                   -- Index Hole Detect
        TRACK00              => TRK00_0,                                 -- Track 0
        WPRT_n               => WPRT_0,                                  -- Write Protect
        STEP_n               => STEP_n,                                  -- Head Step In/Out
        DIREC                => DIREC,                                   -- Head Step Direction
        WG_n                 => WG_n,                                    -- Write Gate
        DTCLK                => DTCLK0,                                  -- Data Clock
        FDI                  => FDI,                                     -- Write Data
        FDO                  => FDO0,                                    -- Read Data
        -- Buffer RAM I/F
        BCS_n                => BCS0_n,                                  -- RAM Request
        BADR                 => BADR0,                                   -- RAM Address
        BWR_n                => BWR0_n,                                  -- RAM Write Signal
        BDI                  => BDI,                                     -- Data Bus Input from RAM
        BDO                  => BDO0                                     -- Data Bus Output to RAM
        -- HPS Interface
        IOCTL_DOWNLOAD       => IOCTL_DOWNLOAD,                          -- HPS Downloading to FPGA.
        IOCTL_INDEX          => IOCTL_INDEX,                             -- Menu index used to upload file.
        IOCTL_WR             => IOCTL_WR,                                -- HPS Write Enable to FPGA.
        IOCTL_RD             => IOCTL_RD,                                -- HPS Read Enable from FPGA.
        IOCTL_ADDR           => IOCTL_ADDR,                              -- HPS Address in FPGA to write into.
        IOCTL_DOUT           => IOCTL_DOUT,                              -- HPS Data to be written into FPGA.
        IOCTL_DIN            => IOCTL_DIN,                               -- HPS Data to be read into HPS.
        IOCTL_INTERRUPT      => IOCTL_INTERRUPT                          -- HPS Interrupt.
    );

    FDD1 : fd55b generic map (
        DS_SW                => "1101",
        REG_ADDR             => X"0050"
    )
    Port map (
        RST_n                => RST_n,                                   -- Reset
        CLK                  => CLK,                                     -- System Clock
        -- Interrupt
        INTO                 => INT1,                                    -- Step Pulse interrupt
        -- FD signals
        FCLK                 => FCLK,
        DS_n                 => DS_n,                                    -- Drive Select
        HS                   => HS,                                      -- Head Select
        MOTOR_n              => MOTOR_n,                                 -- Motor On
        INDEX_n              => IDX_1,                                   -- Index Hole Detect
        TRACK00              => TRK00_1,                                 -- Track 0
        WPRT_n               => WPRT_1,                                  -- Write Protect
        STEP_n               => STEP_n,                                  -- Head Step In/Out
        DIREC                => DIREC,                                   -- Head Step Direction
        WG_n                 => WG_n,                                    -- Write Gate
        DTCLK                => DTCLK1,                                  -- Data Clock
        FDI                  => FDI,                                     -- Write Data
        FDO                  => FDO1,                                    -- Read Data
        -- Buffer RAM I/F
        BCS_n                => BCS1_n,                                  -- RAM Request
        BADR                 => BADR1,                                   -- RAM Address
        BWR_n                => BWR1_n,                                  -- RAM Write Signal
        BDI                  => BDI,                                     -- Data Bus Input from RAM
        BDO                  => BDO1                                     -- Data Bus Output to RAM
        -- HPS Interface
        IOCTL_DOWNLOAD       => IOCTL_DOWNLOAD,                          -- HPS Downloading to FPGA.
        IOCTL_INDEX          => IOCTL_INDEX,                             -- Menu index used to upload file.
        IOCTL_WR             => IOCTL_WR,                                -- HPS Write Enable to FPGA.
        IOCTL_RD             => IOCTL_RD,                                -- HPS Read Enable from FPGA.
        IOCTL_ADDR           => IOCTL_ADDR,                              -- HPS Address in FPGA to write into.
        IOCTL_DOUT           => IOCTL_DOUT,                              -- HPS Data to be written into FPGA.
        IOCTL_DIN            => IOCTL_DIN,                               -- HPS Data to be read into HPS.
        IOCTL_INTERRUPT      => IOCTL_INTERRUPT                          -- HPS Interrupt.
    );

    INDEX_n  <= IDX_0 and IDX_1;
    TRACK00  <= TRK00_0 and TRK00_1;
    WPRT_n   <= WPRT_0 and WPRT_1;
    FDO      <= FDO0 or FDO1;
    DTCLK    <= DTCLK0 or DTCLK1;
    BCS_n    <= BCS0_n and BCS1_n;
    BADR     <= BADR0 or BADR1;
    BWR_n    <= BWR0_n and BWR1_n;
    BDO      <= BDO0 or BDO1;

    RDO      <= RDO0 or RDO1;
    INTO     <= INT0 or INT1;

end RTL;
