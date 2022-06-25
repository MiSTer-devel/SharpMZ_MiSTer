--
-- fd55b.vhd
--
-- Floppy Disk Drive Emulation module
-- for MZ-80B/2000 on FPGA
--
-- Nibbles Lab. 2014-2015
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity fd55b is
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
        IOCTL_DOWNLOAD       : in  std_logic;                            -- HPS Downloading to FPGA.
        IOCTL_INDEX          : in  std_logic_vector(7 downto 0);         -- Menu index used to upload file.
        IOCTL_WR             : in  std_logic;                            -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                            -- HPS Read Enable from FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.
        IOCTL_INTERRUPT      : out std_logic                             -- HPS Interrupt.
    );
end fd55b;

architecture RTL of fd55b is

--
-- Signals
--
signal DS                    : std_logic;                                -- Drive Select
signal HS_n                  : std_logic;                                -- Side One Select
signal DIV                   : std_logic_vector(6 downto 0);             -- Divider
signal SS                    : std_logic;                                -- ROM Address multiplexer
signal PC                    : std_logic_vector(4 downto 0);             -- ROM Address
signal OP                    : std_logic_vector(7 downto 0);             -- OP code
signal ROMOUT                : std_logic_vector(31 downto 0);            -- ROM Data
signal TRACK                 : std_logic_vector(5 downto 0);             -- Track Number
signal MF                    : std_logic;                                -- Modify Flag
signal PHASE                 : std_logic;                                -- Phase of Process
signal SSIZE                 : std_logic_vector(3 downto 0);             -- Sector Size
signal FDOi                  : std_logic_vector(7 downto 0);             -- Output Data(internal)
signal WP                    : std_logic;                                -- Write Protect Flag
signal DISK                  : std_logic;                                -- Disk Exist
signal D88                   : std_logic;                                -- D88 flag(more 16bytes)
signal RSTBUF                : std_logic_vector(2 downto 0);             -- Step Pulse Shift Register
signal REG_ST                : std_logic;                                -- Step Pulse Detect
signal CS                    : std_logic;                                -- Chip Select
signal RSEL                  : std_logic_vector(4 downto 0);             -- Register Select
signal HSEL                  : std_logic;                                -- Register Select by Head
signal GAP3                  : std_logic_vector(7 downto 0);             -- GAP3 length
signal GAP4                  : std_logic_vector(15 downto 0);            -- GAP4 length
signal BADRi                 : std_logic_vector(22 downto 0);            -- RAM Address(internal)
signal BDOi                  : std_logic_vector(7 downto 0);             -- RAM Write Data(internal)
signal OUTEN                 : std_logic;                                -- Drive Selected, Disk Inserted, Motor On
---- Register set of side 0
signal DDEN0                 : std_logic;                                -- density 0=FM,1=MFM side0
signal COUNT0                : std_logic_vector(10 downto 0);            -- Timing Counter(Count down)
signal PSECT0                : std_logic_vector(3 downto 0);             -- Phisical Sector Number
signal LSECT0                : std_logic_vector(7 downto 0);             -- Logical Sector Number
signal MAXSECT0              : std_logic_vector(3 downto 0);             -- Number of Sectors side0
signal TRADR0                : std_logic_vector(22 downto 0);            -- Track data top address side0
signal FDO0i                 : std_logic_vector(7 downto 0);             -- Output Data(internal)
signal PC0                   : std_logic_vector(4 downto 0);             -- ROM Address
signal ROMOUT0               : std_logic_vector(31 downto 0);            -- ROM Data
signal OP0                   : std_logic_vector(7 downto 0);             -- OP code
signal FDAT0                 : std_logic_vector(7 downto 0);             -- Format Data
signal PHASE0                : std_logic;                                -- Phase of Process
signal DCLK0                 : std_logic;                                -- Data Clock(internal)
signal FIRST0                : std_logic;                                -- First Action
signal MF0                   : std_logic;                                -- Modify Flag
signal LSEL0                 : std_logic_vector(3 downto 0);             -- ID register select
signal LSEC00                : std_logic_vector(7 downto 0);             -- Logical Sector Number table side0
signal LSEC01                : std_logic_vector(7 downto 0);
signal LSEC02                : std_logic_vector(7 downto 0);
signal LSEC03                : std_logic_vector(7 downto 0);
signal LSEC04                : std_logic_vector(7 downto 0);
signal LSEC05                : std_logic_vector(7 downto 0);
signal LSEC06                : std_logic_vector(7 downto 0);
signal LSEC07                : std_logic_vector(7 downto 0);
signal LSEC08                : std_logic_vector(7 downto 0);
signal LSEC09                : std_logic_vector(7 downto 0);
signal LSEC0A                : std_logic_vector(7 downto 0);
signal LSEC0B                : std_logic_vector(7 downto 0);
signal LSEC0C                : std_logic_vector(7 downto 0);
signal LSEC0D                : std_logic_vector(7 downto 0);
signal LSEC0E                : std_logic_vector(7 downto 0);
signal LSEC0F                : std_logic_vector(7 downto 0);
signal BADR0i                : std_logic_vector(22 downto 0);            -- RAM Address(internal)
signal BDO0i                 : std_logic_vector(7 downto 0);             -- RAM Write Data(internal)
signal INDEX0_n              : std_logic;                                -- Index Pulse(internal)
signal IPCNT0                : std_logic_vector(2 downto 0);             -- Index Pulse Counter
signal GAP30                 : std_logic_vector(7 downto 0);             -- GAP3 length
signal GAP40                 : std_logic_vector(15 downto 0);            -- GAP4 length
---- Register set of side 1
signal DDEN1                 : std_logic;                                -- density 0=FM,1=MFM side1
signal COUNT1                : std_logic_vector(10 downto 0);            -- Timing Counter(Count down)
signal PSECT1                : std_logic_vector(3 downto 0);             -- Phisical Sector Number
signal LSECT1                : std_logic_vector(7 downto 0);             -- Logical Sector Number
signal MAXSECT1              : std_logic_vector(3 downto 0);             -- Number of Sectors side1
signal TRADR1                : std_logic_vector(22 downto 0);            -- Track data top address side1
signal FDO1i                 : std_logic_vector(7 downto 0);             -- Output Data(internal)
signal PC1                   : std_logic_vector(4 downto 0);             -- ROM Address
signal ROMOUT1               : std_logic_vector(31 downto 0);            -- ROM Data
signal OP1                   : std_logic_vector(7 downto 0);             -- OP code
signal FDAT1                 : std_logic_vector(7 downto 0);             -- Format Data
signal PHASE1                : std_logic;                                -- Phase of Process
signal DCLK1                 : std_logic;                                -- Data Clock(internal)
signal FIRST1                : std_logic;                                -- First Action
signal MF1                   : std_logic;                                -- Modify Flag
signal LSEL1                 : std_logic_vector(3 downto 0);             -- ID register select
signal LSEC10                : std_logic_vector(7 downto 0);             -- Logical Sector Number table side1
signal LSEC11                : std_logic_vector(7 downto 0);
signal LSEC12                : std_logic_vector(7 downto 0);
signal LSEC13                : std_logic_vector(7 downto 0);
signal LSEC14                : std_logic_vector(7 downto 0);
signal LSEC15                : std_logic_vector(7 downto 0);
signal LSEC16                : std_logic_vector(7 downto 0);
signal LSEC17                : std_logic_vector(7 downto 0);
signal LSEC18                : std_logic_vector(7 downto 0);
signal LSEC19                : std_logic_vector(7 downto 0);
signal LSEC1A                : std_logic_vector(7 downto 0);
signal LSEC1B                : std_logic_vector(7 downto 0);
signal LSEC1C                : std_logic_vector(7 downto 0);
signal LSEC1D                : std_logic_vector(7 downto 0);
signal LSEC1E                : std_logic_vector(7 downto 0);
signal LSEC1F                : std_logic_vector(7 downto 0);
signal BADR1i                : std_logic_vector(22 downto 0);            -- RAM Address(internal)
signal BDO1i                 : std_logic_vector(7 downto 0);             -- RAM Write Data(internal)
signal INDEX1_n              : std_logic;                                -- Index Pulse(internal)
signal IPCNT1                : std_logic_vector(2 downto 0);             -- Index Pulse Counter
signal GAP31                 : std_logic_vector(7 downto 0);             -- GAP3 length
signal GAP41                 : std_logic_vector(15 downto 0);            -- GAP4 length

begin

    --
    -- Format Direction Table
    --
    process( PC ) begin
        case( PC ) is
            -- FM
            when "00000" => ROMOUT<="1111"&"0000"&"11111111"&"0000000000001111";
            when "00001" => ROMOUT<="1111"&"0000"&"00000000"&"0000000000000101";
            when "00010" => ROMOUT<="1111"&"0000"&"11111110"&"0000000000000000";
            when "00011" => ROMOUT<="0010"&"0000"&"00000000"&"0000000000000011";
            when "00100" => ROMOUT<="1111"&"0000"&"00000000"&"0000000000000001";
            when "00101" => ROMOUT<="1111"&"0000"&"11111111"&"0000000000001010";
            when "00110" => ROMOUT<="1111"&"0000"&"00000000"&"0000000000000101";
            when "00111" => ROMOUT<="0100"&"0000"&"11111011"&"00000"&SSIZE&"0000000";
            when "01000" => ROMOUT<="1111"&"0000"&"00000000"&"0000000000000001";
            when "01001" => ROMOUT<="1100"&"0001"&"11111111"&"00000000"&GAP3;
            when "01010" => ROMOUT<="0000"&"0000"&"11111111"&GAP4;
            -- MFM
            when "10000" => ROMOUT<="1111"&"0000"&"01001110"&"0000000000011111";
            when "10001" => ROMOUT<="1111"&"0000"&"00000000"&"0000000000001011";
            when "10010" => ROMOUT<="1111"&"0000"&"10100001"&"0000000000000010";
            when "10011" => ROMOUT<="1111"&"0000"&"11111110"&"0000000000000000";
            when "10100" => ROMOUT<="0010"&"0000"&"00000000"&"0000000000000011";
            when "10101" => ROMOUT<="1111"&"0000"&"00000000"&"0000000000000001";
            when "10110" => ROMOUT<="1111"&"0000"&"01001110"&"0000000000010101";
            when "10111" => ROMOUT<="1111"&"0000"&"00000000"&"0000000000001011";
            when "11000" => ROMOUT<="1111"&"0000"&"10100001"&"0000000000000010";
            when "11001" => ROMOUT<="0100"&"0000"&"11111011"&"00000"&SSIZE&"0000000";
            when "11010" => ROMOUT<="1111"&"0000"&"00000000"&"0000000000000001";
            when "11011" => ROMOUT<="1100"&"0001"&"01001110"&"00000000"&GAP3;
            when "11100" => ROMOUT<="0000"&"0000"&"01001110"&GAP4;
            when others => ROMOUT<=(others=>'0');
        end case;
    end process;

    --
    -- Decode Sector size from Sector ID
    --
    process( SS, LSECT0(1 downto 0), LSECT1(1 downto 0) ) begin
        case( SS ) is
            when '0' =>
                case( LSECT0(1 downto 0) ) is
                    when "00"   => SSIZE<="0001";
                    when "01"   => SSIZE<="0010";
                    when "10"   => SSIZE<="0100";
                    when others => SSIZE<="1000";
                end case;
            when others =>
                case( LSECT1(1 downto 0) ) is
                    when "00"   => SSIZE<="0001";
                    when "01"   => SSIZE<="0010";
                    when "10"   => SSIZE<="0100";
                    when others => SSIZE<="1000";
                end case;
        end case;
    end process;

    --
    -- Select GAP3/GAP4 length
    --
    GAP3 <= GAP30 when SS='0' else GAP31;
    GAP4 <= GAP40 when SS='0' else GAP41;

    --
    -- FDT access
    --
    process( RST_n, FCLK ) begin
        if RST_n='0' then
            SS<='0';
        elsif FCLK'event and FCLK='1' then
            SS<=not SS;
            if SS='0' then
                ROMOUT0<=ROMOUT;
            else
                ROMOUT1<=ROMOUT;
            end if;
        end if;
    end process;
    PC<=PC0 when SS='0' else PC1;

    --
    -- Sector Table
    --
    process( PSECT0, LSEC00, LSEC01, LSEC02, LSEC03, LSEC04, LSEC05, LSEC06, LSEC07, LSEC08, LSEC09, LSEC0A, LSEC0B, LSEC0C, LSEC0D, LSEC0E, LSEC0F ) begin
        case PSECT0 is
            when "0000" => LSECT0<=LSEC00;
            when "0001" => LSECT0<=LSEC01;
            when "0010" => LSECT0<=LSEC02;
            when "0011" => LSECT0<=LSEC03;
            when "0100" => LSECT0<=LSEC04;
            when "0101" => LSECT0<=LSEC05;
            when "0110" => LSECT0<=LSEC06;
            when "0111" => LSECT0<=LSEC07;
            when "1000" => LSECT0<=LSEC08;
            when "1001" => LSECT0<=LSEC09;
            when "1010" => LSECT0<=LSEC0A;
            when "1011" => LSECT0<=LSEC0B;
            when "1100" => LSECT0<=LSEC0C;
            when "1101" => LSECT0<=LSEC0D;
            when "1110" => LSECT0<=LSEC0E;
            when others => LSECT0<=LSEC0F;
        end case;
    end process;
    process( PSECT1, LSEC10, LSEC11, LSEC12, LSEC13, LSEC14, LSEC15, LSEC16, LSEC17, LSEC18, LSEC19, LSEC1A, LSEC1B, LSEC1C, LSEC1D, LSEC1E, LSEC1F ) begin
        case PSECT1 is
            when "0000" => LSECT1<=LSEC10;
            when "0001" => LSECT1<=LSEC11;
            when "0010" => LSECT1<=LSEC12;
            when "0011" => LSECT1<=LSEC13;
            when "0100" => LSECT1<=LSEC14;
            when "0101" => LSECT1<=LSEC15;
            when "0110" => LSECT1<=LSEC16;
            when "0111" => LSECT1<=LSEC17;
            when "1000" => LSECT1<=LSEC18;
            when "1001" => LSECT1<=LSEC19;
            when "1010" => LSECT1<=LSEC1A;
            when "1011" => LSECT1<=LSEC1B;
            when "1100" => LSECT1<=LSEC1C;
            when "1101" => LSECT1<=LSEC1D;
            when "1110" => LSECT1<=LSEC1E;
            when others => LSECT1<=LSEC1F;
        end case;
    end process;

    --
    -- Clock Divider
    --
    process( RST_n, FCLK ) begin
        if RST_n='0' then
            DIV<=(others=>'0');
            DCLK0<='0';
            DCLK1<='0';
        elsif FCLK'event and FCLK='1' then
            DIV<=DIV+'1';
            if DIV(5 downto 0)="111111" then
                if MOTOR_n='0' and (DDEN0='1' or (DDEN0='0' and DIV(6)='1')) then
                    DCLK0<='1';
                else
                    DCLK0<='0';
                end if;
                if MOTOR_n='0' and (DDEN1='1' or (DDEN1='0' and DIV(6)='1')) then
                    DCLK1<='1';
                else
                    DCLK1<='0';
                end if;
            else
                DCLK0<='0';
                DCLK1<='0';
            end if;
        end if;
    end process;

    --
    -- Track Sequencer
    --
    process( RST_n, FCLK ) begin
        if RST_n='0' then
            -- Side 0
            PHASE0<='0';
            COUNT0<=(others=>'0');
            PSECT0<=(others=>'0');
            PC0(3 downto 0)<=(others=>'0');
            BADR0i<=(others=>'0');
            BDO0i<=(others=>'0');
            INDEX0_n<='1';
            IPCNT0<=(others=>'1');
            -- Side 1
            PHASE1<='0';
            COUNT1<=(others=>'0');
            PSECT1<=(others=>'0');
            PC1(3 downto 0)<=(others=>'0');
            BADR1i<=(others=>'0');
            BDO1i<=(others=>'0');
            INDEX1_n<='1';
            IPCNT1<=(others=>'1');
        elsif FCLK'event and FCLK='1' then
            -- Disk Removed
            if DISK='0' then
                MF0<='0';
                MF1<='0';
            end if;
            -- Sequencer
            -- Side 0
            if DCLK0='1' then
                PHASE0<=not PHASE0;
                if PHASE0='0' then
                    case OP0(7 downto 4) is
                        when "0010" =>    -- ID
                            case COUNT0(1 downto 0) is
                                when "11" =>
                                    FDO0i<="00"&TRACK;
                                when "10" =>
                                    FDO0i<="0000000"&LSECT0(7);
                                when "01" =>
                                    FDO0i<="000"&LSECT0(6 downto 2);
                                when others =>
                                    FDO0i<="000000"&LSECT0(1 downto 0);
                            end case;
                        when "0100" =>    -- DATA
                            if FIRST0='1' then
                                FDO0i<=FDAT0;
                            else
                                FDO0i<=BDI;
                                BADR0i<=BADR0i+'1';
                            end if;
                        when "0000" =>    -- JMP
                            if COUNT0="00000000000" then
                                PC0(3 downto 0)<=OP0(3 downto 0);
                            end if;
                            FDO0i<=FDAT0;
                        when "1100" =>    -- LOOP
                            if COUNT0="00000000000" then
                                if PSECT0=MAXSECT0 then
                                    PSECT0<=(others=>'0');
                                else
                                    PC0(3 downto 0)<=OP0(3 downto 0);
                                    PSECT0<=PSECT0+'1';
                                end if;
                            end if;
                            FDO0i<=FDAT0;
                        when others =>    -- NOP
                            FDO0i<=FDAT0;
                    end case;
                else    -- PHASE='1'
                    if COUNT0="00000000000" then
                        OP0<=ROMOUT0(31 downto 24);
                        FDAT0<=ROMOUT0(23 downto 16);
                        COUNT0<=ROMOUT0(10 downto 0);
                        FIRST0<='1';
                        PC0(3 downto 0)<=PC0(3 downto 0)+'1';
                        if PC0(3 downto 0)="0000" then
                            BADR0i<=TRADR0;
                        end if;
                        if OP0(7 downto 4)="0100" and D88='1' then    -- DATA
                            BADR0i<=BADR0i+"10000";
                        end if;
                    else
                        FIRST0<='0';
                        COUNT0<=COUNT0-'1';
                        if OP0(7 downto 4)="0100" then    -- DATA
                            if WG_n='0' and WP='0' then
                                BDO0i<=FDI;
                                MF0<='1';
                            end if;
                        end if;
                    end if;
                end if;
                -- Index Pulse
                if PC0(3 downto 0)="0000" then
                    IPCNT0<=(others=>'0');
                    INDEX0_n<='0';
                else
                    if IPCNT0="111" then
                        INDEX0_n<='1';
                    else
                        IPCNT0<=IPCNT0+'1';
                    end if;
                end if;
            end if;
            -- Side 1
            if DCLK1='1' then
                PHASE1<=not PHASE1;
                if PHASE1='0' then
                    case OP1(7 downto 4) is
                        when "0010" =>    -- ID
                            case COUNT1(1 downto 0) is
                                when "11" =>
                                    FDO1i<="00"&TRACK;
                                when "10" =>
                                    FDO1i<="0000000"&LSECT1(7);
                                when "01" =>
                                    FDO1i<="000"&LSECT1(6 downto 2);
                                when others =>
                                    FDO1i<="000000"&LSECT1(1 downto 0);
                            end case;
                        when "0100" =>    -- DATA
                            if FIRST1='1' then
                                FDO1i<=FDAT1;
                            else
                                FDO1i<=BDI;
                                BADR1i<=BADR1i+'1';
                            end if;
                        when "0000" =>    -- JMP
                            if COUNT1="00000000000" then
                                PC1(3 downto 0)<=OP1(3 downto 0);
                            end if;
                            FDO1i<=FDAT1;
                        when "1100" =>    -- LOOP
                            if COUNT1="00000000000" then
                                if PSECT1=MAXSECT1 then
                                    PSECT1<=(others=>'0');
                                else
                                    PC1(3 downto 0)<=OP1(3 downto 0);
                                    PSECT1<=PSECT1+'1';
                                end if;
                            end if;
                            FDO1i<=FDAT1;
                        when others =>    -- NOP
                            FDO1i<=FDAT1;
                    end case;
                else    -- PHASE='1'
                    if COUNT1="00000000000" then
                        OP1<=ROMOUT1(31 downto 24);
                        FDAT1<=ROMOUT1(23 downto 16);
                        COUNT1<=ROMOUT1(10 downto 0);
                        FIRST1<='1';
                        PC1(3 downto 0)<=PC1(3 downto 0)+'1';
                        if PC1(3 downto 0)="0000" then
                            BADR1i<=TRADR1;
                        end if;
                        if OP1(7 downto 4)="0100" and D88='1' then    -- DATA
                            BADR1i<=BADR1i+"10000";
                        end if;
                    else
                        FIRST1<='0';
                        COUNT1<=COUNT1-'1';
                        if OP1(7 downto 4)="0100" then    -- DATA
                            if WG_n='0' and WP='0' then
                                BDO1i<=FDI;
                                MF1<='1';
                            end if;
                        end if;
                    end if;
                end if;
                -- Index Pulse
                if PC1(3 downto 0)="0000" then
                    IPCNT1<=(others=>'0');
                    INDEX1_n<='0';
                else
                    if IPCNT1="111" then
                        INDEX1_n<='1';
                    else
                        IPCNT1<=IPCNT1+'1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    PC0(4)    <= DDEN0;
    PC1(4)    <= DDEN1;
    MF        <= MF0 or MF1;

    DS        <= not((DS_n(1) or DS_SW(1)) and (DS_n(2) or DS_SW(2)) and (DS_n(3) or DS_SW(3)) and (DS_n(4) or DS_SW(4)));
    OUTEN     <= '1' when DS='1' and DISK='1' and MOTOR_n='0' else '0';
    HS_n      <= not HS;

    WPRT_n    <= not WP when DS='1' and DISK='1' else '1';
    TRACK00   <= '0' when TRACK="000000" and DS='1' else '1';
    FDO       <= FDOi when DS='1' and DISK='1' else (others=>'0');
    DTCLK     <= not PHASE when OUTEN='1' else '0';

    --
    -- Select Output with Head Select
    --
    process( HS_n, PHASE0, FDO0i, INDEX0_n, OP0, BADR0i, BDO0i, PHASE1, FDO1i, INDEX1_n, OP1, BADR1i, BDO1i ) begin
        if HS_n='0' then
            PHASE   <= PHASE0;
            FDOi    <= FDO0i;
            BADRi   <= BADR0i;
            BDOi    <= BDO0i;
            INDEX_n <= INDEX0_n or (not (DS and DISK));
            OP      <= OP0;
        else
            PHASE   <= PHASE1;
            FDOi    <= FDO1i;
            BADRi   <= BADR1i;
            BDOi    <= BDO1i;
            INDEX_n <= INDEX1_n or (not (DS and DISK));
            OP      <= OP1;
        end if;
    end process;

    BCS_n <= '0' when PHASE='0' and OP(7 downto 4)="0100" and OUTEN='1' else '1';    -- DATA
    BWR_n <= '0' when PHASE='0' and OP(7 downto 4)="0100" and WG_n='0' and WP='0' and OUTEN='1' else '1';    -- DATA
    BADR  <= BADRi when DS='1' else (others=>'0');
    BDO   <= BDOi when DS='1' else (others=>'0');

    --
    -- Avalon Bus
    --
    process( RST_n, CLK ) begin
        if RST_n='0' then
            DISK   <='0';
            DDEN0  <='0';
            DDEN1  <='0';
            REG_ST <='0';
            TRACK  <=(others=>'0');
            WP     <='0';
        elsif CLK'event and CLK='1' then
            -- Edge Sense
            RSTBUF             <= RSTBUF(1 downto 0)&((not STEP_n) and DS);
            if RSTBUF(2 downto 1)="01" then
                REG_ST         <= '1';
            end if;
            -- Register
            if IOCTL_RD='1' and IOCTL_WR='1' and CS='1' then
                case RSEL is
                    when "00000"|"00001" =>                              -- MZ_FDx_CTRL
                        D88    <= IOCTL_DOUT(2);
                        WP     <= IOCTL_DOUT(1);
                        DISK   <= IOCTL_DOUT(0);
                    when "00010"|"00011" =>                              -- MZ_FDx_TRK
                        TRACK  <= IOCTL_DOUT(5 downto 0);
                    when "00100"|"00101" =>                              -- MZ_FDx_STEP
                        REG_ST <= REG_ST and (not IOCTL_DOUT(0));
                    when "00110"|"00111" =>                              -- MZ_FDx_HSEL
                        HSEL   <= IOCTL_DOUT(0);
                    when "01000" =>                                      -- MZ_FDx_ID
                        case LSEL0 is
                            when "0000" => LSEC00<=IOCTL_DOUT;
                            when "0001" => LSEC01<=IOCTL_DOUT;
                            when "0010" => LSEC02<=IOCTL_DOUT;
                            when "0011" => LSEC03<=IOCTL_DOUT;
                            when "0100" => LSEC04<=IOCTL_DOUT;
                            when "0101" => LSEC05<=IOCTL_DOUT;
                            when "0110" => LSEC06<=IOCTL_DOUT;
                            when "0111" => LSEC07<=IOCTL_DOUT;
                            when "1000" => LSEC08<=IOCTL_DOUT;
                            when "1001" => LSEC09<=IOCTL_DOUT;
                            when "1010" => LSEC0A<=IOCTL_DOUT;
                            when "1011" => LSEC0B<=IOCTL_DOUT;
                            when "1100" => LSEC0C<=IOCTL_DOUT;
                            when "1101" => LSEC0D<=IOCTL_DOUT;
                            when "1110" => LSEC0E<=IOCTL_DOUT;
                            when others => LSEC0F<=IOCTL_DOUT;
                        end case;
                    when "01001" =>
                        case LSEL1 is
                            when "0000" => LSEC10<=IOCTL_DOUT;
                            when "0001" => LSEC11<=IOCTL_DOUT;
                            when "0010" => LSEC12<=IOCTL_DOUT;
                            when "0011" => LSEC13<=IOCTL_DOUT;
                            when "0100" => LSEC14<=IOCTL_DOUT;
                            when "0101" => LSEC15<=IOCTL_DOUT;
                            when "0110" => LSEC16<=IOCTL_DOUT;
                            when "0111" => LSEC17<=IOCTL_DOUT;
                            when "1000" => LSEC18<=IOCTL_DOUT;
                            when "1001" => LSEC19<=IOCTL_DOUT;
                            when "1010" => LSEC1A<=IOCTL_DOUT;
                            when "1011" => LSEC1B<=IOCTL_DOUT;
                            when "1100" => LSEC1C<=IOCTL_DOUT;
                            when "1101" => LSEC1D<=IOCTL_DOUT;
                            when "1110" => LSEC1E<=IOCTL_DOUT;
                            when others => LSEC1F<=IOCTL_DOUT;
                        end case;
                    when "01010" => LSEL0                      <=IOCTL_DOUT(3 downto 0);    -- MZ_FDx_LSEL
                    when "01011" => LSEL1                      <=IOCTL_DOUT(3 downto 0);
                    when "01100" => DDEN0                      <=IOCTL_DOUT(0);             -- MZ_FDx_DDEN
                    when "01101" => DDEN1                      <=IOCTL_DOUT(0);
                    when "01110" => MAXSECT0                   <=IOCTL_DOUT(3 downto 0);    -- MZ_FDx_MAXS
                    when "01111" => MAXSECT1                   <=IOCTL_DOUT(3 downto 0);
                    when "10000" => TRADR0(7 downto 0)         <=IOCTL_DOUT;                -- MZ_FDx_TA0
                    when "10010" => TRADR0(15 downto 8)        <=IOCTL_DOUT;                -- MZ_FDx_TA1
                    when "10100" => TRADR0(22 downto 16)       <=IOCTL_DOUT(6 downto 0);    -- MZ_FDx_TA2
                    when "10001" => TRADR1(7 downto 0)         <=IOCTL_DOUT;
                    when "10011" => TRADR1(15 downto 8)        <=IOCTL_DOUT;
                    when "10101" => TRADR1(22 downto 16)       <=IOCTL_DOUT(6 downto 0);
                    when "11000" => GAP30                      <=IOCTL_DOUT;                -- MZ_FDx_G30
                    when "11001" => GAP31                      <=IOCTL_DOUT;
                    when "11100" => GAP40(7 downto 0)          <=IOCTL_DOUT;                -- MZ_FDx_G40
                    when "11110" => GAP40(15 downto 8)         <=IOCTL_DOUT;                -- MZ_FDx_G41
                    when "11101" => GAP41(7 downto 0)          <=IOCTL_DOUT;
                    when "11111" => GAP41(15 downto 8)         <=IOCTL_DOUT;
                    when others  =>
                end case;
            end if;
        end if;
    end process;

    CS         <= '1' when IOCTL_ADDR(15 downto 4)=REG_ADDR(15 downto 4) else '0';
    RSEL       <= IOCTL_ADDR(3 downto 0)&HSEL;

    IOCTL_DIN  <= "0000"&MF&D88&WP&DISK    when IOCTL_RD='1' and CS='1' and IOCTL_ADDR(3 downto 0)="0000" else    -- MZ_FDx_CTRL
                  "000000"&DIREC&REG_ST    when IOCTL_RD='1' and CS='1' and IOCTL_ADDR(3 downto 0)="0010" else    -- MZ_FDx_STEP
                  "00000000";
    INTO       <= REG_ST;

end RTL;
