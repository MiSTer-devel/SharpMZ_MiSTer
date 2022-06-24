--
-- sysctrl.vhd
--
-- SHARP MZ-80B/2000 series compatible logic, system control module
-- for Altera DE0
--
-- Nibbles Lab. 2014
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity sysctrl is
  port(
        RST_n                : in  std_logic;                            -- Reset
        CLK                  : in  std_logic;                            -- System Clock
        -- Push Button
        BUTTON               : in std_logic_vector(2 downto 0);          -- Pushbutton[2:0]
        -- Switch
        SW                   : in std_logic_vector(9 downto 0);          -- Toggle Switch[9:0]
        -- PS/2 Keyboard Data
        KBEN                 : in std_logic;                             -- PS/2 Keyboard Data Valid
        KBDT                 : in std_logic_vector(7 downto 0);          -- PS/2 Keyboard Data
        -- Interrupt
        INTL                 : out std_logic;                            -- Interrupt Signal Output
        I_CMT                : in std_logic;                             -- from CMT
        I_FDD                : in std_logic;                             -- from FD unit
        -- Others
        URST_n               : out std_logic;                            -- Universal Reset
        ARST_n               : out std_logic;                            -- All Reset
        ZRST                 : out std_logic;                            -- Z80 Reset
        CLK50                : in std_logic;                             -- 50MkHz
        SCLK                 : in std_logic;                             -- 31.25kHz
        ZBREQ                : out std_logic;                            -- Z80 Bus Request
        ZBACK                : in std_logic;                             -- Z80 Bus Acknowridge
        BST_n                : in std_logic;                             -- BOOT start request from Z80
        BOOTM                : out std_logic;                            -- BOOT mode
        F_BTN                : out std_logic                             -- Function Button
        -- HPS Interface
        IOCTL_DOWNLOAD       : in  std_logic;                            -- HPS Downloading to FPGA.
        IOCTL_INDEX          : in  std_logic_vector(7 downto 0);         -- Menu index used to upload file.
        IOCTL_WR             : in  std_logic;                            -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                            -- HPS Read Enable from FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0)         -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.
        IOCTL_INTERRUPT      : out std_logic                             -- HPS Interrupt.
  );
end sysctrl;

architecture rtl of sysctrl is

--
-- Reset & Filters
--
signal URSTi                 : std_logic;                                -- Universal Reset
signal BUF                   : std_logic_vector(7 downto 0) := "00000000";
signal CNT5                  : std_logic_vector(4 downto 0);
signal SR_BTN                : std_logic_vector(7 downto 0);
signal ZR_BTN                : std_logic_vector(7 downto 0);
signal F_BTNi                : std_logic;
--
-- Interrupt
--
signal IRQ_KB                : std_logic;
signal IE_KB                 : std_logic;
signal IKBBUF                : std_logic_vector(2 downto 0);
signal IRQ_FB                : std_logic;
signal IE_FB                 : std_logic;
signal IFBBUF                : std_logic_vector(2 downto 0);
signal IRQ_CT                : std_logic;
signal IE_CT                 : std_logic;
signal ICTBUF                : std_logic_vector(2 downto 0);
signal IRQ_FD                : std_logic;
signal IE_FD                 : std_logic;
signal IFDBUF                : std_logic_vector(2 downto 0);
--
-- Control for Z80
--
signal ZRSTi                 : std_logic;
signal BOOTMi                : std_logic := '1';

begin

    --
    -- Avalon Bus
    --
    process( RST_n, CLK ) begin
        if RST_n='0' then
            IRQ_KB   <= '0';
            IRQ_FB   <= '0';
            IRQ_CT   <= '0';
            IRQ_FD   <= '0';
            IKBBUF   <= (others=>'0');
            IFBBUF   <= (others=>'0');
            ICTBUF   <= (others=>'0');
            IFDBUF   <= (others=>'0');
            IE_KB    <= '0';
            IE_FB    <= '0';
            IE_CT    <= '0';
            IE_FD    <= '0';
            ZBREQ    <= '1';
            BOOTMi   <= '1';
            ZRSTi    <= '0';
        elsif CLK'event and CLK='1' then
            -- Edge Sense
            IKBBUF<=IKBBUF(1 downto 0)&(KBEN and ((not ZBACK) or BOOTMi));
            if IKBBUF(2 downto 1)="01" then
                IRQ_KB      <= IE_KB;
            end if;
            IFBBUF          <= IFBBUF(1 downto 0)&F_BTNi;
            if IFBBUF(2 downto 1)="01" then
                IRQ_FB      <= IE_FB;
            end if;
            ICTBUF          <= ICTBUF(1 downto 0)&I_CMT;
            if ICTBUF(2 downto 1)="01" then
                IRQ_CT      <= IE_CT;
            end if;
            IFDBUF          <= IFDBUF(1 downto 0)&I_FDD;
            if IFDBUF(2 downto 1)="01" then
                IRQ_FD      <= IE_FD;
            end if;
            -- Register
            if IOCTL_RD='1' and IOCTL_WR='1' then
                if IOCTL_ADDR=X"0005" then    -- MZ_SYS_IREQ
                    IRQ_KB  <= IRQ_KB and (not IOCTL_DOUT(0));    -- I_KBD 0x01
                    IRQ_FB  <= IRQ_FB and (not IOCTL_DOUT(1));    -- I_FBTN 0x02
                    IRQ_CT  <= IRQ_CT and (not IOCTL_DOUT(2));    -- I_CMT 0x04
                    IRQ_FD  <= IRQ_FD and (not IOCTL_DOUT(3));    -- I_FDD 0x08
                end if;
                if IOCTL_ADDR=X"0006" then    -- MZ_SYS_IENB
                    IE_KB   <= IOCTL_DOUT(0);    -- I_KBD 0x01
                    IE_FB   <= IOCTL_DOUT(1);    -- I_FBTN 0x02
                    IE_CT   <= IOCTL_DOUT(2);    -- I_CMT 0x04
                    IE_FD   <= IOCTL_DOUT(3);    -- I_FDD 0x08
                end if;
                if IOCTL_ADDR=X"0007" then    -- MZ_SYS_CTRL (Control for Z80)
                    ZBREQ   <= IOCTL_DOUT(0);
                    ZRSTi   <= IOCTL_DOUT(1);
                    BOOTMi  <= IOCTL_DOUT(2);
                end if;
            end if;
        end if;
    end process;

    IOCTL_DIN <= "00000"&BUTTON                     when IOCTL_RD='1' and IOCTL_ADDR=X"0000" else    -- MZ_SYS_BUTTON
                 SW(7 downto 0)                     when IOCTL_RD='1' and IOCTL_ADDR=X"0002" else    -- MZ_SYS_SW70
                 "000000"&SW(9)&SW(8)               when IOCTL_RD='1' and IOCTL_ADDR=X"0003" else    -- MZ_SYS_SW98
                 KBDT                               when IOCTL_RD='1' and IOCTL_ADDR=X"0004" else    -- MZ_SYS_KBDT
                 "0000"&IRQ_FD&IRQ_CT&IRQ_FB&IRQ_KB when IOCTL_RD='1' and IOCTL_ADDR=X"0005" else    -- MZ_SYS_IREQ
                 "0000"&IE_FD&IE_CT&IE_FB&IE_KB     when IOCTL_RD='1' and IOCTL_ADDR=X"0006" else    -- MZ_SYS_IENB
                 "000000"&(not BST_n)&ZBACK         when IOCTL_RD='1' and IOCTL_ADDR=X"0007" else    -- MZ_SYS_STATUS
                 "00000000";

    INTL <= IRQ_KB or IRQ_FB or IRQ_CT or IRQ_FD;

    --
    -- Filter and Asynchronous Reset with automatic
    --
    URST_n <= URSTi;
    process( CLK50 ) begin
        if( CLK50'event and CLK50='1' ) then
            if BUF=X"80" then
                URSTi  <= '1';
            else
                BUF    <= BUF+'1';
                URSTi  <= '0';
            end if;
        end if;
    end process;

    process( URSTi, SCLK ) begin
        if URSTi='0' then
            CNT5       <= (others=>'0');
            SR_BTN     <= (others=>'1');
            ZR_BTN     <= (others=>'1');
        elsif SCLK'event and SCLK='1' then
            if CNT5="11111" then
                SR_BTN <= SR_BTN(6 downto 0)&(BUTTON(1) or (not BUTTON(0)));    -- only BUTTON1
                ZR_BTN <= ZR_BTN(6 downto 0)&((not BUTTON(1)) or BUTTON(0));    -- only BUTTON0
                CNT5   <= (others=>'0');
            else
                CNT5<=CNT5+'1';
            end if;
        end if;
    end process;
    F_BTNi  <= '1' when SR_BTN="00000000" else '0';
    F_BTN   <= F_BTNi;
    ARST_n  <= URSTi ;
    ZRST    <= '0' when (ZR_BTN="00000000" and ZBACK='1') or ZRSTi='0' or URSTi='0' else '1';

    BOOTM   <= BOOTMi;

end rtl;
