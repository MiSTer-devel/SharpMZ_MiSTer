--
-- mb8876.vhd
--
-- Floppy Disk Controller partiality compatible module
-- for MZ-80B/2000 on FPGA
--
-- Nibbles Lab. 2014-2015
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mb8876 is
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
end mb8876;

architecture RTL of mb8876 is

signal DALI                  : std_logic_vector(7 downto 0);             -- non-inverted Data bus(input)
signal DALO                  : std_logic_vector(7 downto 0);             -- non-inverted Data bus(output)
signal STS                   : std_logic_vector(7 downto 0);             -- Command Register(backup for status)
signal TRACK                 : std_logic_vector(7 downto 0);             -- Track Counter
signal SECTOR                : std_logic_vector(7 downto 0);             -- Sector Counter
signal GAPVAL                : std_logic_vector(7 downto 0);             -- Gap's Value
signal FDIR                  : std_logic_vector(7 downto 0);             -- Bulk Data(pre registered)
signal FDR                   : std_logic_vector(7 downto 0);             -- Bulk Data
signal WDATA                 : std_logic_vector(7 downto 0);             -- Write Data
signal BCOUNT                : std_logic_vector(9 downto 0);              -- Byte Counter
signal DELAY                 : std_logic_vector(16 downto 0);            -- Delay Counter
signal DCSET                 : std_logic_vector(16 downto 0);            -- Next Delay Count Number
signal PCOUNT                : std_logic_vector(4 downto 0);             -- Step Pulse Width
signal BUSY                  : std_logic;                                -- Busy Flag
signal DIRC0                 : std_logic;                                -- Step Direction(current)
signal DIRR                  : std_logic;                                -- Step Direction(registered)
signal E_SEEK                : std_logic;                                -- Seek Error
signal E_RNF                 : std_logic;                                -- Record Not Found Error
signal E_RLOST               : std_logic;                                -- Lost Data Error(read)
signal E_WLOST               : std_logic;                                -- Lost Data Error(write)
signal IDXBUF                : std_logic_vector(2 downto 0);             -- Index Pulse Detect
signal DTBUF                 : std_logic_vector(2 downto 0);             -- Data Enable Detect
signal FDEN                  : std_logic;                                -- Data Enable Detected
signal IDXC                  : std_logic_vector(2 downto 0);             -- Index Pulse Counter
signal RDRQ                  : std_logic;                                -- Read Data Request
signal WDRQ                  : std_logic;                                -- Write Data Request
signal MOVING                : std_logic;                                -- Head Stepping Flag
signal RFND0                 : std_logic;                                -- Record Found Flag(process)
signal RFND                  : std_logic;                                -- Record Found Flag(result)
signal TFND                  : std_logic;                                -- Track Found Flag
signal CMPT                  : std_logic;                                -- Track Compared Flag
signal VFLAG                 : std_logic;                                -- Record Verify Flag
signal UFLAG                 : std_logic;                                -- Track Number Update Flag
signal CFLAG                 : std_logic;                                -- Side Compare Flag
signal MFLAG                 : std_logic;                                -- Multi Record Flag
signal SFLAG                 : std_logic;                                -- Side Flag
--
-- State Machine
--
signal CUR                   : std_logic_vector(5 downto 0);
signal NXT                   : std_logic_vector(5 downto 0);
constant IDLE                : std_logic_vector(5 downto 0) := "000000";
constant REST                : std_logic_vector(5 downto 0) := "000001";
--constant REST1             : std_logic_vector(5 downto 0) := "000010";
--constant REST2             : std_logic_vector(5 downto 0) := "000011";
constant SEEK0               : std_logic_vector(5 downto 0) := "000100";
constant SEEK1               : std_logic_vector(5 downto 0) := "000101";
constant SEEK2               : std_logic_vector(5 downto 0) := "000110";
constant STEP0               : std_logic_vector(5 downto 0) := "000111";
constant STEP1               : std_logic_vector(5 downto 0) := "001000";
constant STEP2               : std_logic_vector(5 downto 0) := "001001";
constant STIN0               : std_logic_vector(5 downto 0) := "001010";
constant STIN1               : std_logic_vector(5 downto 0) := "001011";
constant STIN2               : std_logic_vector(5 downto 0) := "001100";
constant STOT0               : std_logic_vector(5 downto 0) := "001101";
constant STOT1               : std_logic_vector(5 downto 0) := "001110";
constant STOT2               : std_logic_vector(5 downto 0) := "001111";
constant VTRK0               : std_logic_vector(5 downto 0) := "010000";
constant VTRK1               : std_logic_vector(5 downto 0) := "010001";
constant VTRK_ER             : std_logic_vector(5 downto 0) := "010010";
constant RDAT0               : std_logic_vector(5 downto 0) := "010011";
constant RDAT1               : std_logic_vector(5 downto 0) := "010100";
constant RDAT2               : std_logic_vector(5 downto 0) := "010101";
constant RDAT3               : std_logic_vector(5 downto 0) := "010110";
constant RDAT4               : std_logic_vector(5 downto 0) := "010111";
constant RDAT5               : std_logic_vector(5 downto 0) := "011000";
constant WDAT0               : std_logic_vector(5 downto 0) := "011001";
constant WDAT1               : std_logic_vector(5 downto 0) := "011010";
constant WDAT2               : std_logic_vector(5 downto 0) := "011011";
constant WDAT3               : std_logic_vector(5 downto 0) := "011100";
constant WDAT4               : std_logic_vector(5 downto 0) := "011101";
constant WDAT5               : std_logic_vector(5 downto 0) := "011110";
constant RNF_ER              : std_logic_vector(5 downto 0) := "011111";
constant RADR0               : std_logic_vector(5 downto 0) := "100000";
constant RADR1               : std_logic_vector(5 downto 0) := "100001";
constant RADR2               : std_logic_vector(5 downto 0) := "100010";
constant RADR3               : std_logic_vector(5 downto 0) := "100011";
constant CMDQ                : std_logic_vector(5 downto 0) := "100100";
signal CUR2                  : std_logic_vector(4 downto 0);
signal NXT2                  : std_logic_vector(4 downto 0);
constant HUNT                : std_logic_vector(4 downto 0) := "00000";
constant GAP1                : std_logic_vector(4 downto 0) := "00001";
constant SYNC1               : std_logic_vector(4 downto 0) := "00010";
constant ADM1                : std_logic_vector(4 downto 0) := "00011";
constant ID_TRK              : std_logic_vector(4 downto 0) := "00100";
constant ID_HEAD             : std_logic_vector(4 downto 0) := "00101";
constant ID_SECT             : std_logic_vector(4 downto 0) := "00110";
constant ID_FMT              : std_logic_vector(4 downto 0) := "00111";
constant CRC1_1              : std_logic_vector(4 downto 0) := "01000";
constant CRC1_2              : std_logic_vector(4 downto 0) := "01001";
constant GAP2_2              : std_logic_vector(4 downto 0) := "01010";
constant GAP2_1              : std_logic_vector(4 downto 0) := "01011";
constant GAP2                : std_logic_vector(4 downto 0) := "01100";
constant SYNC2               : std_logic_vector(4 downto 0) := "01101";
constant ADM2                : std_logic_vector(4 downto 0) := "01110";
constant DATA                : std_logic_vector(4 downto 0) := "01111";
constant DATA_1              : std_logic_vector(4 downto 0) := "10000";
constant DATA_2              : std_logic_vector(4 downto 0) := "10001";
constant DATA_3              : std_logic_vector(4 downto 0) := "10010";
constant CRC2                : std_logic_vector(4 downto 0) := "10011";

begin

    --
    -- Step pulse and Seek wait
    --
    process( MR_n, ZCLK ) begin
        if MR_n='0' then
            DELAY   <= (others=>'0');
            PCOUNT  <= (others=>'0');
            MOVING  <= '0';
            STEP    <= '0';
        elsif ZCLK'event and ZCLK='1' then
            if DELAY="00000000000000000" then
                if CUR=SEEK1 or CUR=STEP1 or CUR=STIN1 or CUR=STOT1 then
                    DELAY   <= DCSET;
                    PCOUNT  <= (others=>'1');
                    MOVING  <= '1';
                else
                    MOVING  <= '0';
                end if;
            else
                DELAY       <= DELAY-'1';
                if PCOUNT="00000" then
                    STEP    <= '0';
                else
                    STEP    <= '1';
                    PCOUNT  <= PCOUNT-'1';
                end if;
            end if;
        end if;
    end process;

    --
    -- Select Step Rate
    --
    process( STS(1 downto 0) ) begin
        case STS(1 downto 0) is                -- r0,r1
            when "00"   => DCSET<=conv_std_logic_vector(24000, 17);        -- 6ms
            when "10"   => DCSET<=conv_std_logic_vector(48000, 17);        -- 12ms
            when "01"   => DCSET<=conv_std_logic_vector(80000, 17);        -- 20ms
            when others => DCSET<=conv_std_logic_vector(120000, 17);    -- 30ms
        end case;
    end process;

    --
    -- FD Data Sync
    --
    process( MR_n, ZCLK ) begin
--    process( MR_n, DTCLK ) begin
        if MR_n='0' then
            FDR<=(others=>'0');
            CUR2<=HUNT;
            BCOUNT<=(others=>'0');
        elsif ZCLK'event and ZCLK='1' then
--        elsif DTCLK'event and DTCLK='1' then
--            FDIRR<=FDIR;
            if FDEN='1' then
                if MOVING='1' then
                    CUR2<=HUNT;
                else
                    CUR2<=NXT2;
                end if;
                FDR<=FDI;
                if CUR2=ID_FMT then
                    case FDR(1 downto 0) is
                        when "00" => BCOUNT<="0001111101";
                        when "01" => BCOUNT<="0011111101";
                        when "10" => BCOUNT<="0111111101";
                        when others => BCOUNT<="1111111101";
                    end case;
                end if;
                if CUR2=DATA then
                    BCOUNT<=BCOUNT-'1';
                end if;
            end if;
        end if;
    end process;

    process( CUR2, IP_n, FDI, GAPVAL, BCOUNT ) begin
        case CUR2 is
            when HUNT =>
                if IP_n='0' and FDI=GAPVAL then
                    NXT2<=GAP1;
                else
                    NXT2<=HUNT;
                end if;
            when GAP1 =>
                if FDI=X"00" then
                    NXT2<=SYNC1;
                else
                    NXT2<=GAP1;
                end if;
            when SYNC1 =>
                if FDI=X"FE" then
                    NXT2<=ADM1;
                else
                    NXT2<=SYNC1;
                end if;
            when ADM1 =>
                NXT2<=ID_TRK;
            when ID_TRK =>
                NXT2<=ID_HEAD;
            when ID_HEAD =>
                NXT2<=ID_SECT;
            when ID_SECT =>
                NXT2<=ID_FMT;
            when ID_FMT =>
                NXT2<=CRC1_1;
            when CRC1_1 =>
                NXT2<=CRC1_2;
            when CRC1_2 =>
                NXT2<=GAP2_2;
            when GAP2_2 =>
                NXT2<=GAP2_1;
            when GAP2_1 =>
                NXT2<=GAP2;
            when GAP2 =>
                if FDI=X"00" then
                    NXT2<=SYNC2;
                else
                    NXT2<=GAP2;
                end if;
            when SYNC2 =>
                if FDI=X"FB" then
                    NXT2<=DATA;
                else
                    NXT2<=SYNC2;
                end if;
            when DATA =>
                if BCOUNT="0000000000" then
                    NXT2<=DATA_1;
                else
                    NXT2<=DATA;
                end if;
            when DATA_1 =>
                    NXT2<=DATA_2;
            when DATA_2 =>
                    NXT2<=DATA_3;
            when DATA_3 =>
                    NXT2<=CRC2;
            when CRC2 =>
                if FDI=GAPVAL then
                    NXT2<=GAP1;
                else
                    NXT2<=CRC2;
                end if;
            when others =>
                NXT2<=HUNT;
        end case;
    end process;

    GAPVAL<=X"4E" when DDEN_n='0' else X"FF";

    --
    -- FD data sample timing
    --
    process( MR_n, ZCLK ) begin
        if MR_n='0' then
            DTBUF<=(others=>'0');
            FDEN<='0';
        elsif ZCLK'event and ZCLK='1' then
            DTBUF<=DTBUF(1 downto 0)&DTCLK;
            if DTBUF(2 downto 1)="01" then
                FDEN<='1';
            else
                FDEN<='0';
            end if;
        end if;
    end process;

    --
    -- DRQ
    --
    process( MR_n, ZCLK ) begin
        if MR_n='0' then
            E_RLOST<='0';
            E_WLOST<='0';
            RDRQ<='0';
            WDRQ<='0';
        elsif ZCLK'event and ZCLK='1' then
            -- Reset
            if CUR=RDAT0 then
                E_RLOST<='0';
                RDRQ<='0';
            end if;
            if CUR=WDAT0 then
                E_WLOST<='0';
                WDRQ<='0';
            end if;
            if CUR=CMDQ then
                if RDRQ='1' then
                    E_RLOST<='1';
                end if;
                if WDRQ='1' then
                    E_WLOST<='1';
                end if;
                RDRQ<='0';
                WDRQ<='0';
            end if;
            -- DRQ on (Read)
            if (CUR=RDAT3 and (CUR2=DATA or CUR2=DATA_1 or CUR2=DATA_2)) or (CUR=RADR2 and (CUR2=ADM1 or CUR2=ID_TRK or CUR2=ID_HEAD or CUR2=ID_SECT or CUR2=ID_FMT or CUR2=CRC1_1)) then
                if FDEN='1' then
                    RDRQ<='1';
                    if RDRQ='1' then
                        E_RLOST<='1';
                    end if;
                end if;
            end if;
            -- Write
            if CUR=WDAT3 and (CUR2=DATA or CUR2=GAP2_1 or (CUR2=SYNC2 and FDI=X"FB")) then
                if FDEN='1' then
                    WDRQ<='1';
                    if WDRQ='1' then
                        E_WLOST<='1';
                    end if;
                end if;
            end if;
            -- DRQ off
            if CS_n='0' and A="11" then
                if WE_n='1' then
                    -- Read
                    RDRQ<='0';
                else
                    -- Write
                    WDRQ<='0';
                end if;
            end if;
        end if;
    end process;

    --
    -- Index Pulse Counter with ID check
    --
    process( MR_n, ZCLK ) begin
        if MR_n='0' then
            IDXC<=(others=>'0');
            IDXBUF<=(others=>'1');
            RFND0<='0';
            RFND<='0';
            TFND<='0';
            CMPT<='0';
        elsif ZCLK'event and ZCLK='1' then
            -- stand by
            if CUR=VTRK0 then
                TFND<='0';
                CMPT<='0';
            end if;
            -- count or reset
            IDXBUF<=IDXBUF(1 downto 0)&IP_n;
            if CUR=RDAT0 or CUR=WDAT0 then
                IDXC<=(others=>'0');
            else
                if IDXBUF(2 downto 1)="10" then
                    IDXC<=IDXC+'1';
                end if;
            end if;
            -- find and compare ID
            if FDEN='1' then
                if CUR2=ID_TRK then
                    if FDR=TRACK then
                        RFND0<='1';
                        TFND<='1';
                    else
                        RFND0<='0';
                        TFND<='0';
                    end if;
                    CMPT<='1';
                end if;
                if CUR2=ID_HEAD then
                    if CFLAG='1' then
                        if FDR(0)/=SFLAG then
                            RFND0<='0';
                        end if;
                    end if;
                end if;
                if CUR2=ID_SECT then
                    if FDR=SECTOR then
                        if RFND0='1' then
                            IDXC<=(others=>'0');
                        end if;
                    else
                        RFND0<='0';
                    end if;
                end if;
                if CUR2=GAP2_2 then
                    RFND<=RFND0;
                end if;
                if CUR2=CRC2 then
                    RFND<='0';
                end if;
            end if;
        end if;
    end process;

    --
    -- Compatibility
    --
    DALI<=not DALI_n;
    DALO_n<=not DALO when CS_n='0' and RE_n='0' else (others=>'0');

    --
    -- CPU Interface and State movement
    --
    process( MR_n, ZCLK ) begin
        if MR_n='0' then
            STS<=(others=>'0');
            E_SEEK<='0';
            E_RNF<='0';
            TRACK<=(others=>'0');
            SECTOR<=X"01";
            WDATA<=(others=>'0');
            CUR<=IDLE;
            DIRR<='0';
            FDO<=(others=>'0');
        elsif ZCLK'event and ZCLK='1' then
            -- Registers
            if CS_n='0' then
                if WE_n='0' then
                    case A is
                        when "00" =>
                            if DALI(7 downto 4)="1101" then
                                if BUSY='0' then
                                    STS<=DALI;
                                end if;
                            else
                                STS<=DALI;
                            end if;
                        when "01" =>
                            if BUSY='0' then
                                TRACK<=DALI;
                            end if;
                        when "10" =>
                            if BUSY='0' then
                                SECTOR<=DALI;
                            end if;
                        when others =>
                            if CUR=WDAT3 then
                                FDO<=DALI;
                            else
                                WDATA<=DALI;
                            end if;
                    end case;
                end if;
            end if;

            -- State Machine
            if CS_n='0' and WE_n='0' and A="00" and DALI(7 downto 4)="1101" then
                CUR<=CMDQ;    -- Force Interrupt
            else
                CUR<=NXT;
            end if;
            --
            -- Save Step Direction
            if CUR=SEEK1 or CUR=STEP1 or CUR=STIN1 or CUR=STOT1 then
                DIRR<=DIRC0;
            end if;
            -- Seek Error
            if CUR=SEEK0 or CUR=STEP0 or CUR=STIN0 or CUR=STOT0 then
                E_SEEK<='0';
            end if;
            if CUR=VTRK_ER then
                E_SEEK<='1';
            end if;
            -- Restore
            if CUR=REST then
                TRACK<=(others=>'1');
                WDATA<=(others=>'0');
            end if;
            -- Step
            if (UFLAG='1' and (CUR=STIN1 or (CUR=STEP1 and DIRC0='1'))) or (CUR=SEEK1 and DIRC0='1') then
                TRACK<=TRACK+'1';
            elsif    (UFLAG='1' and (CUR=STOT1 or (CUR=STEP1 and DIRC0='0'))) or (CUR=SEEK1 and DIRC0='0') then
                TRACK<=TRACK-'1';
            end if;
            if (DIRC0='0' and (CUR=SEEK2 or CUR=STEP2)) or CUR=STOT2 then
                if TR00_n='0' then
                    TRACK<=(others=>'0');
                end if;
            end if;
            -- Multi Read/Write
            if CUR=RDAT5 or CUR=WDAT5 then
                SECTOR<=SECTOR+'1';
            end if;
            -- Record Not Found Error
            if CUR=RDAT0 or CUR=WDAT0 then
                E_RNF<='0';
            end if;
            if CUR=RNF_ER then
                E_RNF<='1';
            end if;
            -- Read Address function
            if CUR=RADR2 and CUR2=ID_TRK then
                SECTOR<=FDR;
            end if;

        end if;
    end process;

    VFLAG<=STS(2);
    UFLAG<=STS(4);
    CFLAG<=STS(1);
    MFLAG<=STS(4);
    SFLAG<=STS(3);

    --
    -- State Machine
    --
    process( CUR, CS_n, WE_n, A, DALI(7 downto 4), TR00_n, VFLAG, MOVING, TRACK, WDATA, CMPT, TFND, RFND, DIRR, IDXC, MFLAG, E_RLOST , E_WLOST ) begin
        case CUR is
            when IDLE =>
                if CS_n='0' and WE_n='0' and A="00" then
                    case DALI(7 downto 4) is
                        when "0000" => NXT<=REST;
                        when "0001" => NXT<=SEEK0;
                        when "0010"|"0011" => NXT<=STEP0;
                        when "0100"|"0101" => NXT<=STIN0;
                        when "0110"|"0111" => NXT<=STOT0;
                        when "1000"|"1001" => NXT<=RDAT0;
                        when "1010"|"1011" => NXT<=WDAT0;
                        when "1100" => NXT<=RADR0;
                        when others => NXT<=IDLE;
                    end case;
                else
                    NXT<=IDLE;
                end if;

            -- TYPE I / Restore command
            when REST =>
                NXT<=SEEK1;

            -- TYPE I / Seek command
            when SEEK0 =>
                if TRACK=WDATA then
                    if VFLAG='1' then
                        NXT<=VTRK0;
                    else
                        NXT<=CMDQ;
                    end if;
                else
                    NXT<=SEEK1;
                end if;
            when SEEK1 =>
                NXT<=SEEK2;
            when SEEK2 =>
                if MOVING='0' then
                    NXT<=SEEK0;
                else
                    NXT<=SEEK2;
                end if;

            -- TYPE I / Step command
            when STEP0 =>
                if DIRR='0' and TR00_n='0' then
                    if VFLAG='1' then
                        NXT<=VTRK0;
                    else
                        NXT<=CMDQ;
                    end if;
                else
                    NXT<=STEP1;
                end if;
            when STEP1 =>
                NXT<=STEP2;
            when STEP2 =>
                if MOVING='0' then
                    if VFLAG='1' then
                        NXT<=VTRK0;
                    else
                        NXT<=CMDQ;
                    end if;
                else
                    NXT<=STEP2;
                end if;

            -- TYPE I / Step In command
            when STIN0 =>
                NXT<=STIN1;
            when STIN1 =>
                NXT<=STIN2;
            when STIN2 =>
                if MOVING='0' then
                    if VFLAG='1' then
                        NXT<=VTRK0;
                    else
                        NXT<=CMDQ;
                    end if;
                else
                    NXT<=STIN2;
                end if;

            -- TYPE I / Step Out command
            when STOT0 =>
                if TR00_n='0' then
                    if VFLAG='1' then
                        NXT<=VTRK0;
                    else
                        NXT<=CMDQ;
                    end if;
                else
                    NXT<=STOT1;
                end if;
            when STOT1 =>
                NXT<=STOT2;
            when STOT2 =>
                if MOVING='0' then
                    if VFLAG='1' then
                        NXT<=VTRK0;
                    else
                        NXT<=CMDQ;
                    end if;
                else
                    NXT<=STOT2;
                end if;

            -- Verify Track Number(TYPE I)
            when VTRK0 =>
                NXT<=VTRK1;
            when VTRK1 =>
                if CMPT='0' then
                    NXT<=VTRK1;
                else
                    if TFND='0' then
                        NXT<=VTRK_ER;
                    else
                        NXT<=CMDQ;
                    end if;
                end if;
            when VTRK_ER =>
                NXT<=CMDQ;

            -- TYPE II / Read Data command
            when RDAT0 =>
                NXT<=RDAT1;
            when RDAT1 =>
                if CUR2=GAP1 then
                    NXT<=RDAT2;
                else
                    NXT<=RDAT1;
                end if;
            when RDAT2 =>
                if RFND='1' then
                    NXT<=RDAT3;
                else
                    if IDXC="0110" then
                        NXT<=RNF_ER;
                    else
                        NXT<=RDAT2;
                    end if;
                end if;
            when RDAT3 =>
                if E_RLOST='1' then
                    NXT<=CMDQ;
                else
                    if CUR2=CRC2 then
                        NXT<=RDAT4;
                    else
                        NXT<=RDAT3;
                    end if;
                end if;
            when RDAT4 =>
                if MFLAG='0' then
                    NXT<=CMDQ;
                else
                    NXT<=RDAT5;
                end if;
            when RDAT5 =>
                NXT<=RDAT0;

            -- TYPE II / Write Data command
            when WDAT0 =>
                NXT<=WDAT1;
            when WDAT1 =>
                if CUR2=GAP1 then
                    NXT<=WDAT2;
                else
                    NXT<=WDAT1;
                end if;
            when WDAT2 =>
                if RFND='1' then
                    NXT<=WDAT3;
                else
                    if IDXC="0110" then
                        NXT<=RNF_ER;
                    else
                        NXT<=WDAT2;
                    end if;
                end if;
            when WDAT3 =>
                if E_WLOST='1' then
                    NXT<=CMDQ;
                else
                    if CUR2=CRC2 then
                        NXT<=WDAT4;
                    else
                        NXT<=WDAT3;
                    end if;
                end if;
            when WDAT4 =>
                if MFLAG='0' then
                    NXT<=CMDQ;
                else
                    NXT<=WDAT5;
                end if;
            when WDAT5 =>
                NXT<=WDAT0;

            -- Record Not Found(TYPE II)
            when RNF_ER =>
                NXT<=CMDQ;

            -- TYPE III / Read Address command
            when RADR0 =>
                NXT<=RADR1;
            when RADR1 =>
                if CUR2=GAP1 then
                    NXT<=RADR2;
                else
                    NXT<=RADR1;
                end if;
            when RADR2 =>
                if E_RLOST='1' then
                    NXT<=CMDQ;
                else
--                    if CUR2=CRC1_2 then
                    if CUR2=GAP2_2 then
--                        NXT<=RADR3;
                        NXT<=CMDQ;
                    else
                        NXT<=RADR2;
                    end if;
                end if;
--            when RADR3 =>
--                NXT<=RADR0;

            when CMDQ =>
                NXT<=IDLE;
            when others =>
                NXT<=IDLE;
        end case;
    end process;

    --
    -- State Action
    --
    -- Busy
    BUSY<='0' when CUR=IDLE else '1';
    -- Step Direction
    process( CUR, TRACK, WDATA, DIRR ) begin
        case CUR is
            when SEEK0|SEEK1|SEEK2 =>
                if TRACK>WDATA then
                    DIRC0<='0';
                elsif TRACK<WDATA then
                    DIRC0<='1';
                else
                    DIRC0<=DIRR;
                end if;
            when STEP0|STEP1|STEP2 =>
                DIRC0<=DIRR;
            when STIN0|STIN1|STIN2 =>
                DIRC0<='1';
            when STOT0|STOT1|STOT2 =>
                DIRC0<='0';
            when others=>
                DIRC0<=DIRR;
        end case;
    end process;
    -- Write Gate
    WG<='1' when CUR=WDAT3 and (CUR2=DATA or CUR2=DATA_1 or (CUR2=SYNC2 and (FDI=X"FB" or FDR=X"FB"))) else '0';

    DALO<=    -- TYPE I Status
            (not READY)&(not WPRT_n)&'1'&E_SEEK&'0'&(not TR00_n)&(not IP_n)&BUSY when A="00" and CS_n='0' and RE_n='0' and STS(7)='0' else
                -- TYPE II Status
            (not READY)&"00"&E_RNF&'0'&E_RLOST&RDRQ&BUSY                         when A="00" and CS_n='0' and RE_n='0' and (STS(7 downto 5)="100" or STS(7 downto 4)="1100") else
            (not READY)&(not WPRT_n)&'0'&E_RNF&'0'&E_WLOST&WDRQ&BUSY             when A="00" and CS_n='0' and RE_n='0' and STS(7 downto 5)="101" else
                -- TYPE III Status
        --    (not READY)&"00"&E_RNF&'0'&E_RLOST&RDRQ&BUSY                       when A="00" and CS_n='0' and RE_n='0' and STS(7 downto 4)="1100" else
                -- TYPE IV Status
            (not READY)&(not WPRT_n)&"100"&(not TR00_n)&(not IP_n)&'0'           when A="00" and CS_n='0' and RE_n='0' and STS(7 downto 4)="1101" else
                -- Registers
            TRACK                                                                when A="01" and CS_n='0' and RE_n='0' else
            SECTOR                                                               when A="10" and CS_n='0' and RE_n='0' else
            FDR                                                                  when A="11" and CS_n='0' and RE_n='0' and RDRQ='1' else
            WDATA                                                                when A="11" and CS_n='0' and RE_n='0' else
                -- Not Access
            "00000000";
    DIRC<=DIRC0;

end RTL;
