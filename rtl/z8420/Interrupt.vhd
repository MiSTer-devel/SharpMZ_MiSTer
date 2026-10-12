--
-- Interrupt.vhd
--
-- Z80 Daisy-Chain Interrupt Logic for FPGA
--
-- Nibbles Lab. 2013-2014
--
-- 2026: made synchronous to CLK (clk_sys). INTR, INTA and FETCH were used as
-- clocks; they are now edge-detected on CLK. FETCH samples the data bus from
-- the previous CLK, because the CPU data mux stops selecting the opcode as soon
-- as RD_n rises.
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity Interrupt is
    Port (
        -- System Signal
        CLK                  : in  std_logic;
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
end Interrupt;

architecture Behavioral of Interrupt is

-----------------------------------------------------------------------------------
-- Signals
-----------------------------------------------------------------------------------

signal IREQ                  : std_logic;
signal IRES                  : std_logic;
signal INTR                  : std_logic;
signal IAUTH                 : std_logic;
signal AUTHRES               : std_logic;
signal IED1                  : std_logic;
signal IED2                  : std_logic;
signal ICB                   : std_logic;
signal I4D                   : std_logic;
signal FETCH                 : std_logic;
signal INTA                  : std_logic;
signal IENB                  : std_logic;
signal iINT                  : std_logic;
signal iIEO                  : std_logic;
signal INTR_D                : std_logic := '0';
signal INTA_D                : std_logic := '0';
signal FETCH_D               : std_logic := '1';
signal DI_D                  : std_logic_vector(7 downto 0);

begin

    --
    -- External signals
    --
    INTO_n  <= iINT;
    IEO     <= iIEO;

    --
    -- Internal signals
    --
    iINT    <= '0' when IEI='1' and IREQ='1' and IAUTH='0' else '1';
    iIEO    <= not (((not IED1) and IREQ) or IAUTH or (not IEI));
    INTA    <= ((not M1_n) and (not IORQ_n) and IEI);
    AUTHRES <= RESET or (IEI and IED2 and I4D);
    FETCH   <= M1_n or RD_n;
    IRES    <= RESET or INTA;
    INTR    <= M1_n and (INTI and INTEN);
    VECTEN  <= '1' when INTA='1' and IEI='1' and IAUTH='1' else '0';

    --
    -- Keep Interrupt Request
    --
    process( CLK ) begin
        if rising_edge(CLK) then
            INTR_D   <= INTR;
            INTA_D   <= INTA;
            FETCH_D  <= FETCH;
            DI_D     <= DI;

            -- Interrupt request, set on the rising edge of INTR.
            if IRES='1' then
                IREQ     <= '0';
            elsif INTR='1' and INTR_D='0' then
                IREQ     <= '1';
            end if;

            -- Acknowledge: capture the request as it was before INTA.
            if AUTHRES='1' then
                IAUTH    <= '0';
            elsif INTA='1' and INTA_D='0' then
                IAUTH    <= IREQ;
            end if;

            -- Opcode decode at the end of each M1 read (RETI = ED 4D).
            if RESET='1' then
                IED1     <= '0';
                IED2     <= '0';
                ICB      <= '0';
                I4D      <= '0';
            elsif FETCH='1' and FETCH_D='0' then
                IED2     <= IED1;
                if DI_D=X"ED" and ICB='0' then
                    IED1 <= '1';
                else
                    IED1 <= '0';
                end if;
                if DI_D=X"CB" then
                    ICB  <= '1';
                else
                    ICB  <= '0';
                end if;
                if DI_D=X"4D" then
                    I4D  <= IEI;
                else
                    I4D  <= '0';
                end if;
            end if;
        end if;
    end process;

end Behavioral;
