--
-- cmt.vhd
--
-- Sharp PWM Tape I/F and Pseudo-CMT module
-- for MZ-80B/2000 on FPGA
--
-- Nibbles Lab. 2013-2014
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity cmt is
    Port (
        RST_n                : in  std_logic;                            -- Reset
        CLK                  : in  std_logic;                            -- System Clock
        -- Interrupt
        INTO                 : out std_logic;                            -- Tape action interrupt
        -- Z80 Bus
        ZCLK                 : in  std_logic;
--      ZA8                  : in  std_logic_vector(7 downto 0);
--      ZIWR_x               : in  std_logic;
--      ZDI                  : in  std_logic_vector(7 downto 0);
--      ZDO                  : out std_logic_vector(7 downto 0);
        -- Tape signals
        T_END                : out std_logic;                            -- Sense CMT(Motor on/off)
        OPEN_x               : in  std_logic;                            -- Open
        PLAY_x               : in  std_logic;                            -- Play
        STOP_x               : in  std_logic;                            -- Stop
        FF_x                 : in  std_logic;                            -- Fast Foward
        REW_x                : in  std_logic;                            -- Rewind
        APSS_x               : in  std_logic;                            -- APSS
        FFREW                : in  std_logic;                            -- FF/REW mode
        FMOTOR               : in  std_logic;                            -- FF/REW start
        FLATCH               : in  std_logic;                            -- FF/REW latch
        WREADY               : out std_logic;                            -- Write enable
        TREADY               : out std_logic;                            -- Tape exist
--      EXIN                 : in std_logic;                             -- CMT IN from I/O board
        RDATA                : out std_logic;                            -- to 8255
        -- Status Signal
        SCLK                 : in  std_logic;                            -- Slow Clock(31.25kHz)
        MZMODE               : in  std_logic;                            -- Hardware Mode
        DMODE                : in  std_logic                             -- Display Mode
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
end cmt;

architecture RTL of cmt is

--
-- Status
--
signal RPLBUF                : std_logic_vector(2 downto 0);
signal REG_PL                : std_logic;
signal RSTBUF                : std_logic_vector(2 downto 0);
signal REJBUF                : std_logic_vector(2 downto 0);
signal REG_EJ                : std_logic;
signal RREBUF                : std_logic_vector(2 downto 0);
signal REG_RE                : std_logic;
signal RFFBUF                : std_logic_vector(2 downto 0);
signal REG_FF                : std_logic;
signal RASBUF                : std_logic_vector(2 downto 0);
signal REG_AS                : std_logic;
signal RLTBUF                : std_logic_vector(2 downto 0);
signal RFMBUF                : std_logic_vector(2 downto 0);
signal REG_RE_M              : std_logic;
signal REG_FF_M              : std_logic;
signal TAPE                  : std_logic;
signal WP                    : std_logic;
signal MOTOR                 : std_logic;
signal PBIT                  : std_logic;
signal RBYTE                 : std_logic_vector(15 downto 0);
signal PON                   : std_logic;
signal APSS                  : std_logic;
signal FA                    : std_logic;
--
-- Pulse Generator
--
signal POUT                  : std_logic;
signal PCNT                  : std_logic_vector(10 downto 0);
signal PBUSY                 : std_logic;
signal PEXT                  : std_logic_vector(4 downto 0);
----
---- Filters
----
--signal CNT3 : std_logic_vector(1 downto 0);
--signal PL_BTN : std_logic_vector(1 downto 0);
--signal ST_BTN : std_logic_vector(1 downto 0);
--signal T_BTN : std_logic;
----
---- Divider
----
--signal DIV : std_logic_vector(13 downto 0);
----
---- Registers for Z80
----
--signal MADR : std_logic_vector(15 downto 0);
--signal MBYTE : std_logic_vector(15 downto 0);
--signal MCMD : std_logic_vector(7 downto 0);
--signal STAT : std_logic_vector(7 downto 0);

--
-- Components
--
begin
    --
    -- HPS Bus
    --
    process( RST_n, CLK ) begin
        if RST_n='0' then
            WP               <='0';
            MOTOR            <='0';
            TAPE             <='0';
            REG_PL           <='0';
            REG_EJ           <='0';
            REG_FF           <='0';
            REG_RE           <='0';
            REG_AS           <='0';
            REG_FF_M         <='0';
            REG_RE_M         <='0';
            PBIT             <='0';
            PON              <='0';
            FA               <='0';
            PEXT             <=(others=>'0');
        elsif CLK'event and CLK='1' then
            -- Edge Sense
            if MZMODE='0' then
                RPLBUF<=RPLBUF(1 downto 0)&PLAY_x;                       -- MZ-80B
            else
                RPLBUF       <= RPLBUF(1 downto 0)&(not PLAY_x);         -- MZ-2000
            end if;
            if RPLBUF(2 downto 1)="01" then
                REG_PL       <= TAPE;
                REG_AS       <= '0';
            end if;
            if MZMODE='0' then
                RSTBUF       <= RSTBUF(1 downto 0)&STOP_x;               -- MZ-80B
            else
                RSTBUF       <= RSTBUF(1 downto 0)&(not STOP_x);         -- MZ-2000
            end if;
            if RSTBUF(2 downto 1)="01" then
                MOTOR        <= '0';
                REG_AS       <= '0';
                REG_FF       <= '0';
                REG_RE       <= '0';
            end if;
            REJBUF<=REJBUF(1 downto 0)&(not OPEN_x);
            if REJBUF(2 downto 1)="01" then
                REG_EJ       <= '1';
                TAPE         <= '0';
                REG_AS       <= '0';
                REG_FF       <= '0';
                REG_RE       <= '0';
            end if;
            if MZMODE='0' then                                           -- MZ-80B
                RLTBUF       <= RLTBUF(1 downto 0)&FLATCH;
                if RLTBUF(2 downto 1)="01" then
                    REG_RE_M <= not FFREW;
                    REG_FF_M <= FFREW;
                end if;
                RFMBUF<=RFMBUF(1 downto 0)&FMOTOR;
                if RFMBUF(2 downto 1)="01" then
                    REG_RE   <= REG_RE_M and TAPE;
                    REG_FF   <= REG_FF_M and TAPE;
                    REG_AS   <= TAPE;
                end if;
            else                                                         -- MZ-2000
                RREBUF<=RREBUF(1 downto 0)&(not REW_x);
                if RREBUF(2 downto 1)="01" then
                    REG_RE   <= TAPE;
                end if;
                RFFBUF<=RFFBUF(1 downto 0)&(not FF_x);
                if RFFBUF(2 downto 1)="01" then
                    REG_FF   <= TAPE;
                end if;
                RASBUF<=RASBUF(1 downto 0)&(not APSS_x);
                if RASBUF(2 downto 1)="01" then
                    REG_AS   <= TAPE;
                end if;
            end if;
            -- Register
            if IOCTL_RD='1' and IOCTL_WR='1' then
                if IOCTL_ADDR=X"0010" and PBUSY='0' then                 -- MZ_CMT_POUT
                    PBIT     <= IOCTL_DOUT(0);
                    PEXT     <= "11111";
                else
                    PEXT     <= PEXT(3 downto 0)&'0';
                end if;
                if IOCTL_ADDR=X"0011" then                               -- MZ_CMT_STATUS
                    REG_AS   <= REG_AS and (not IOCTL_DOUT(4));
                    REG_RE   <= REG_RE and (not IOCTL_DOUT(3));
                    REG_FF   <= REG_FF and (not IOCTL_DOUT(2));
                    REG_PL   <= REG_PL and (not IOCTL_DOUT(1));
                    REG_EJ   <= REG_EJ and (not IOCTL_DOUT(0));
                end if;
                if IOCTL_ADDR=X"0012" then                               -- MZ_CMT_COUNT
                    RBYTE(7 downto 0)  <= IOCTL_DOUT;
                end if;
                if IOCTL_ADDR=X"0013" then                               -- MZ_CMT_COUNTH
                    RBYTE(15 downto 8) <= IOCTL_DOUT;
                end if;
                if IOCTL_ADDR=X"0014" then                               -- MZ_CMT_CTRL
                    FA       <= IOCTL_DOUT(4);
                    PON      <= IOCTL_DOUT(3);
                    WP       <= IOCTL_DOUT(2);
                    MOTOR    <= IOCTL_DOUT(1);
                    TAPE     <= IOCTL_DOUT(0);
                end if;
            else
                PEXT         <= PEXT(3 downto 0)&'0';
            end if;
        end if;
    end process;

    IOCTL_DIN <= "0000000"&PBUSY                                     when IOCTL_RD='1' and IOCTL_ADDR=X"0010" else    -- MZ_CMT_POUT
                 "000"&REG_AS&REG_RE&REG_FF&REG_PL&REG_EJ when IOCTL_RD='1' and IOCTL_ADDR=X"0011" else    -- MZ_CMT_STATUS
                 "000"&FA&PON&WP&MOTOR&TAPE                     when IOCTL_RD='1' and IOCTL_ADDR=X"0014" else    -- MZ_CMT_CTRL
                 "00000000";
    APSS      <= REG_AS or FA;
    INTO      <= REG_PL or REG_EJ or REG_RE or REG_FF;
    WREADY    <= not WP;
    TREADY    <= not TAPE;
    T_END     <= not MOTOR;
    RDATA     <= POUT or PON;

    --
    -- PWM pulse generate
    --
    process( RST_n, ZCLK ) begin
        if RST_n='0' then
            POUT  <='0';
            PBUSY <='0';
            PCNT  <=(others=>'0');
        elsif ZCLK'event and ZCLK='1' then
            if PEXT(4)='1' then
                if PBIT='0' then
                    PCNT <= "01010011011";    --667
                else
                    PCNT <= "10100110100";    --1332
                end if;
                POUT     <= '1';
                PBUSY    <= '1';
            else
                if POUT='1' and PCNT=0 then
                    if PBIT='0' then
                        PCNT <= "01010011000";    --664
                    else
                        PCNT <= "10100110110";    --1334
                    end if;
                    POUT  <= '0';
                elsif POUT='0' and PCNT=0 then
                    PBUSY <= '0';
                else
                    PCNT  <= PCNT-'1';
                end if;
            end if;
        end if;
    end process;

--    --
--    -- MZ-80B Action for Quick Access
--    --
--    process( reset, ZCLK ) begin
--        if reset='1' then
--            MADR<=(others=>'0');
--            MBYTE<=(others=>'0');
--            MCMD<=(others=>'0');
--            interrupt<='1';
--        elsif ZCLK'event and ZCLK='0' then
--            if ZIWR_x='0' and ZA8(7 downto 3)="10001" then
--                case ZA8(2 downto 0) is
--                    when "000" => MADR(7 downto 0)<=ZDI; interrupt<='1';
--                    when "001" => MADR(15 downto 8)<=ZDI; interrupt<='1';
--                    when "010" => MBYTE(7 downto 0)<=ZDI; interrupt<='1';
--                    when "011" => MBYTE(15 downto 8)<=ZDI; interrupt<='1';
--                    when others => MCMD<=ZDI; interrupt<=not(ZDI(7) or ZDI(6) or ZDI(5) or ZDI(4) or ZDI(3) or ZDI(2) or ZDI(1) or ZDI(0));
--                end case;
--            end if;
--        end if;
--    end process;

--    ZDO<=STAT;

end RTL;
