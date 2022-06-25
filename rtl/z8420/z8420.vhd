--
-- z8420.vhd
--
-- Zilog Z80PIO partiality compatible module
-- for MZ-80B on FPGA
--
-- Port A : Output, mode 0 only
-- Port B : Input, mode 0 only
--
-- Nibbles Lab. 2005-2014
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity z8420 is
    Port (
        -- System
        RST_n                : in std_logic;                                -- Only Power On Reset
        -- Z80 Bus Signals
        CLK                  : in std_logic;
        ENA                  : in std_logic;
        BASEL                : in std_logic;
        CDSEL                : in std_logic;
        CE                   : in std_logic;
        RD_n                 : in std_logic;
        WR_n                 : in std_logic;
        IORQ_n               : in std_logic;
        M1_n                 : in std_logic;
        DI                   : in std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);
        IEI                  : in std_logic;
        IEO                  : out std_logic;
        INT_n                : out std_logic;
        -- Port
        A                    : out std_logic_vector(7 downto 0);
        B                    : in std_logic_vector(7 downto 0)
    );
end z8420;

architecture Behavioral of z8420 is

--
-- Port Selecter
--
signal SELAD                 : std_logic;
signal SELBD                 : std_logic;
signal SELAC                 : std_logic;
signal SELBC                 : std_logic;
--
-- Port Register
--
signal AREG                  : std_logic_vector(7 downto 0);             -- Output Register (Port A)
signal DIRA                  : std_logic_vector(7 downto 0);             -- Data Direction (Port A)
signal DDWA                  : std_logic;                                -- Prepare for Data Direction (Port A)
signal IMWA                  : std_logic_vector(7 downto 0);             -- Interrupt Mask Word (Port A)
signal MFA                   : std_logic;                                -- Mask Follows (Port A)
signal VECTA                 : std_logic_vector(7 downto 0);             -- Interrupt Vector (Port A)
signal MODEA                 : std_logic_vector(1 downto 0);             -- Mode Word (Port A)
signal HLA                   : std_logic;                                -- High/Low (Port A)
signal AOA                   : std_logic;                                -- AND/OR (Port A)
signal DIRB                  : std_logic_vector(7 downto 0);             -- Data Direction (Port B)
signal DDWB                  : std_logic;                                -- Prepare for Data Direction (Port B)
signal IMWB                  : std_logic_vector(7 downto 0);             -- Interrupt Mask Word (Port B)
signal MFB                   : std_logic;                                -- Mask Follows (Port B)
signal VECTB                 : std_logic_vector(7 downto 0);             -- Interrupt Vector (Port B)
signal MODEB                 : std_logic_vector(1 downto 0);             -- Mode Word (Port B)
signal HLB                   : std_logic;                                -- High/Low (Port B)
signal AOB                   : std_logic;                                -- AND/OR (Port B)
--
-- Interrupt
--
--signal VECTENA             : std_logic;
signal EIA                   : std_logic;                                -- Interrupt Enable (Port A)
--signal MINTA               : std_logic_vector(7 downto 0);
--signal INTA                : std_logic;
signal VECTENB               : std_logic;
signal EIB                   : std_logic;                                -- Interrupt Enable (Port B)
signal MINTB                 : std_logic_vector(7 downto 0);
signal INTB                  : std_logic;

--
-- Components
--
component Interrupt is
    Port (
        -- System Signal
        RESET                : in  std_logic;
        -- CPU Signals
        DI                   : in  std_logic_vector(7 downto 0);
        IORQ_n               : in  std_logic;                            -- same as Z80
        RD_n                 : in  std_logic;                            -- same as Z80
        M1_n                 : in  std_logic;                            -- same as Z80
        IEI                  : in  std_logic;                            -- same as Z80
        IEO                  : out std_logic;                            -- same as Z80
        INTO_n               : out std_logic;
        -- Control Signals
        VECTEN               : out std_logic;
        INTI                 : in  std_logic;
        INTEN                : in  std_logic
    );
end component;

begin

    --
    -- Instantiation
    --
--  INT0 : Interrupt port map (
--       -- System Signal
--       RESET => RST_n,
--       -- CPU Signals
--       IORQ_n => IORQ_n,
--       RD_n => RD_n,
--       M1_n => M1_n,
--       IEI => IEI,
--       IEO => IEO,
--       INTO_n => INTA_n,
--       -- Control Signals
--       VECTEN => VECTENA,
--       INTI => INTA,
--       INTEN => EIA
--   );

    INT1 : Interrupt port map (
        -- System Signal
        RESET                => RST_n,
        -- CPU Signals
        DI                   => DI,
        IORQ_n               => IORQ_n,
        RD_n                 => RD_n,
        M1_n                 => M1_n,
        IEI                  => IEI,
        IEO                  => IEO,
        INTO_n               => INT_n,    --INTB_n,
        -- Control Signals
        VECTEN               => VECTENB,
        INTI                 => INTB,
        INTEN                => EIB
    );

    --
    -- Port select for Output
    --
    SELAD <= '1' when BASEL='0' and CDSEL='0' else '0';
    SELBD <= '1' when BASEL='1' and CDSEL='0' else '0';
    SELAC <= '1' when BASEL='0' and CDSEL='1' else '0';
    SELBC <= '1' when BASEL='1' and CDSEL='1' else '0';

    --
    -- Output
    --
    process( RST_n, CLK, ENA ) begin
        if RST_n='0' then
            AREG    <= (others=>'0');
            MODEA   <= "01";
            DDWA    <= '0';
            MFA     <= '0';
            EIA     <= '0';
--          B<=(others=>'0');
            MODEB   <= "01";
            DDWB    <= '0';
            MFB     <= '0';
            EIB     <= '0';
        elsif CLK'event and CLK='0' then
            if ENA = '1' then
                if CE='0' and WR_n='0' then
                    if SELAD='1' then
                        AREG      <=DI;
                    end if;
    --              if SELBD='1' then
    --                  B<=DI;
    --              end if;
                    if SELAC='1' then
                        if DDWA='1' then
                            DIRA  <=DI;
                            DDWA  <='0';
                        elsif MFA='1' then
                            IMWA  <=DI;
                            MFA   <='0';
                        elsif DI(0)='0' then
                            VECTA <=DI;
                        elsif DI(3 downto 0)="1111" then
                            MODEA <=DI(7 downto 6);
                            DDWA  <=DI(7) and DI(6);
                        elsif DI(3 downto 0)="0111" then
                            MFA   <=DI(4);
                            HLA   <=DI(5);
                            AOA   <=DI(6);
                            EIA   <=DI(7);
                        elsif DI(3 downto 0)="0011" then
                            EIA   <=DI(7);
                        end if;
                    end if;
                    if SELBC='1' then
                        if DDWB='1' then
                            DIRB  <=DI;
                            DDWB  <='0';
                        elsif MFB='1' then
                            IMWB  <=DI;
                            MFB   <='0';
                        elsif DI(0)='0' then
                            VECTB <=DI;
                        elsif DI(3 downto 0)="1111" then
                            MODEB <=DI(7 downto 6);
                            DDWB  <=DI(7) and DI(6);
                        elsif DI(3 downto 0)="0111" then
                            MFB   <=DI(4);
                            HLB   <=DI(5);
                            AOB   <=DI(6);
                            EIB   <=DI(7);
                        elsif DI(3 downto 0)="0011" then
                            EIB   <=DI(7);
                        end if;
                    end if;
                end if;
             end if;
        end if;
    end process;
    A<=AREG;

    --
    -- Input select
    --
    DO<=AREG  when RD_n='0' and CE='0' and SELAD='1' else
         B     when RD_n='0' and CE='0' and SELBD='1' else
--       VECTA when VECTENA='1' else
         VECTB when VECTENB='1' else (others=>'0');

    --
    -- Interrupt select
    --
    INTMASK : for I in 0 to 7 generate
--      MINTA(I)<=(A(I) xnor HLA) and (not IMWA(I)) when AOA='0' else
--                   (A(I) xnor HLA) or IMWA(I);
        MINTB(I)<=(B(I) xnor HLB) and (not IMWB(I)) when AOB='0' else
                     (B(I) xnor HLB) or IMWB(I);
    end generate INTMASK;
--    INTA<=MINTA(7) or MINTA(6) or MINTA(5) or MINTA(4) or MINTA(3) or MINTA(2) or MINTA(1) or MINTA(0) when AOA='0' else
--            MINTA(7) and MINTA(6) and MINTA(5) and MINTA(4) and MINTA(3) and MINTA(2) and MINTA(1) and MINTA(0);
    INTB<=MINTB(7) or MINTB(6) or MINTB(5) or MINTB(4) or MINTB(3) or MINTB(2) or MINTB(1) or MINTB(0) when AOB='0' else
            MINTB(7) and MINTB(6) and MINTB(5) and MINTB(4) and MINTB(3) and MINTB(2) and MINTB(1) and MINTB(0);

end Behavioral;
