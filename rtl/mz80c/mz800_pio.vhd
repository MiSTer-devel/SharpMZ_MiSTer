---------------------------------------------------------------------------------------------------------
--
-- Name:            mz800_pio.vhd
-- Description:     Z80 PIO for the MZ-800 (ports FC-FF), synchronous on the system clock.
--
--                  FC = port A control, FD = port B control, FE = port A data, FF = port B data.
--                  On the MZ-800 port A bit 4 is /CTC0 (8253 channel 0) and bit 5 is /VBLN, and
--                  CP/M uses bit mode interrupts on them (IM 2). Port B and the rest of port A go
--                  to the printer.
--
--                  Implemented: the control words (mode, I/O mask, interrupt control and mask,
--                  vector, interrupt enable), bit mode (mode 3) interrupts on the logic condition
--                  becoming true, the vector on interrupt acknowledge (port A before port B), and
--                  data reads and writes. As in mz800emu (pioz80.c), the condition becoming true is
--                  latched while interrupts are disabled and requested once they are enabled
--                  (MZ-1500 BASIC sets up its music timer that way), and writing the I/O or
--                  interrupt mask takes the inputs as they are, without a request. Not implemented: the handshake modes 0-2 (strobe/ready)
--                  and the daisy chain beyond this PIO. RETI (ED 4D on two opcode fetches) is decoded:
--                  an acknowledged port is in service until the RETI and, as on the Z80 PIO (and in mz800emu),
--                  neither it nor the lower priority port B requests meanwhile; a condition becoming true in service
--                  stays pending. Antiriad's vblank handler runs longer than a frame and re-enables interrupts before
--                  its RETI: without this it re-entered itself for ever.
--
-- Copyright:       (c) 2026 SharpMZ MiSTer contributors
--
---------------------------------------------------------------------------------------------------------
-- This source file is free software: you can redistribute it and-or modify
-- it under the terms of the GNU General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mz800_pio is
    port (
        CLK                  : in  std_logic;
        RESET                : in  std_logic;
        CS                   : in  std_logic;                                -- Port FC-FF selected (IORQ, not M1).
        A                    : in  std_logic_vector(1 downto 0);             -- 0 A control, 1 B control, 2 A data, 3 B data.
        RD_n                 : in  std_logic;
        WR_n                 : in  std_logic;
        IORQ_n               : in  std_logic;
        M1_n                 : in  std_logic;
        RD_n_CPU             : in  std_logic := '1';                         -- CPU RD (opcode fetches, for RETI).
        CPU_DIN              : in  std_logic_vector(7 downto 0) := (others => '1'); -- What the CPU reads.
        DI                   : in  std_logic_vector(7 downto 0);
        DO                   : out std_logic_vector(7 downto 0);             -- Register read data or the vector.
        VECTOR_OE            : out std_logic;                                -- Driving the vector (interrupt acknowledge).
        INT_n                : out std_logic;
        PA_IN                : in  std_logic_vector(7 downto 0);
        PB_IN                : in  std_logic_vector(7 downto 0);
        PA_OUT               : out std_logic_vector(7 downto 0);             -- Output registers (printer: PB data, PA7 RDP).
        PB_OUT               : out std_logic_vector(7 downto 0)
    );
end mz800_pio;

architecture rtl of mz800_pio is
    type byte2 is array(0 to 1) of std_logic_vector(7 downto 0);
    type bit2 is array(0 to 1) of std_logic;
    type mode2 is array(0 to 1) of std_logic_vector(1 downto 0);

    signal MODE              : mode2;                                        -- 0 output, 1 input, 2 bidirectional, 3 bit mode.
    signal IOMASK            : byte2;                                        -- Bit mode: 1 = input.
    signal INTMASK           : byte2;                                        -- 0 = bit is monitored.
    signal VECT              : byte2;
    signal OUTREG            : byte2;
    signal IE                : bit2;                                         -- Interrupt enable.
    signal ANDOR             : bit2;                                         -- 1 = AND.
    signal HILO              : bit2;                                         -- 1 = active high.
    signal EXP_IOMASK        : bit2;                                         -- Next control word is the I/O mask.
    signal EXP_INTMASK       : bit2;                                         -- Next control word is the interrupt mask.
    signal COND              : bit2;
    signal COND_LAST         : bit2;
    signal REQ               : bit2;                                         -- Pending and enabled.
    signal PEND              : bit2;
    signal SNAP              : bit2;                                         -- Mask written: take COND without a request.
    signal WR_LAST_n         : std_logic;
    signal INTA              : std_logic;
    signal INTA_LAST         : std_logic;
    signal INTA_PORT         : std_logic;                                    -- Port being acknowledged (0 A, 1 B).
    signal PIN               : byte2;
    signal IUS               : bit2;                                         -- In service: acknowledged, no RETI yet.
    signal OP_M1             : std_logic;                                    -- In an opcode fetch.
    signal OP_DATA           : std_logic_vector(7 downto 0);                 -- Byte of the current opcode fetch.
    signal OP_LAST           : std_logic_vector(7 downto 0);                 -- Byte of the previous opcode fetch.
begin
    PIN(0)                   <= PA_IN;
    PA_OUT                   <= OUTREG(0);
    PB_OUT                   <= OUTREG(1);
    PIN(1)                   <= PB_IN;
    INTA                     <= '1' when M1_n = '0' and IORQ_n = '0' else '0';

    -- Bit mode interrupt condition per port.
    COND_GEN: for p in 0 to 1 generate
        process(PIN, HILO, INTMASK, IOMASK, MODE, ANDOR)
            variable act : std_logic_vector(7 downto 0);
            variable mon : std_logic_vector(7 downto 0);
        begin
            if HILO(p) = '1' then act := PIN(p); else act := not PIN(p); end if;
            mon := (not INTMASK(p)) and IOMASK(p);
            if MODE(p) /= "11" or mon = x"00" then
                COND(p)      <= '0';
            elsif ANDOR(p) = '1' then
                if (act and mon) = mon then COND(p) <= '1'; else COND(p) <= '0'; end if;
            else
                if (act and mon) /= x"00" then COND(p) <= '1'; else COND(p) <= '0'; end if;
            end if;
        end process;
    end generate;

    process(CLK) begin
        if rising_edge(CLK) then
            if RESET = '1' then
                for p in 0 to 1 loop
                    MODE(p)          <= "01";
                    IOMASK(p)        <= x"FF";
                    INTMASK(p)       <= x"FF";
                    VECT(p)          <= x"00";
                    OUTREG(p)        <= x"00";
                    IE(p)            <= '0';
                    ANDOR(p)         <= '0';
                    HILO(p)          <= '0';
                    EXP_IOMASK(p)    <= '0';
                    EXP_INTMASK(p)   <= '0';
                    COND_LAST(p)     <= '0';
                    PEND(p)          <= '0';
                    SNAP(p)          <= '0';
                    IUS(p)           <= '0';
                end loop;
                OP_M1                <= '0';
                OP_DATA              <= x"00";
                OP_LAST              <= x"00";
                WR_LAST_n            <= '1';
                INTA_LAST            <= '0';
                INTA_PORT            <= '0';
            else
                WR_LAST_n            <= WR_n;
                INTA_LAST            <= INTA;

                -- Requests: the condition becoming true (served once interrupts are enabled).
                for p in 0 to 1 loop
                    COND_LAST(p)     <= COND(p);
                    SNAP(p)          <= '0';
                    if COND(p) = '1' and COND_LAST(p) = '0' and SNAP(p) = '0' and EXP_INTMASK(p) = '0' then
                        PEND(p)      <= '1';
                    end if;
                end loop;

                -- Acknowledge: port A has priority; the request is served at the end of the cycle.
                if INTA = '1' and INTA_LAST = '0' then
                    if REQ(0) = '1' then INTA_PORT <= '0'; else INTA_PORT <= '1'; end if;
                end if;
                if INTA = '0' and INTA_LAST = '1' then
                    if INTA_PORT = '0' then PEND(0) <= '0'; IUS(0) <= '1'; else PEND(1) <= '0'; IUS(1) <= '1'; end if;
                end if;

                -- RETI (ED 4D): the opcode byte is taken while RD is low in an M1 memory read; at the end of the M1
                -- the previous and this byte are checked. It ends the service of the highest priority port in service.
                OP_M1                <= '0';
                if M1_n = '0' and IORQ_n = '1' and RD_n_CPU = '0' then
                    OP_DATA          <= CPU_DIN;
                    OP_M1            <= '1';
                end if;
                if OP_M1 = '1' and not (M1_n = '0' and IORQ_n = '1' and RD_n_CPU = '0') then
                    OP_LAST          <= OP_DATA;
                    if OP_LAST = x"ED" and OP_DATA = x"4D" then
                        if IUS(0) = '1' then IUS(0) <= '0'; elsif IUS(1) = '1' then IUS(1) <= '0'; end if;
                    end if;
                end if;

                -- Register writes.
                if CS = '1' and WR_n = '0' and WR_LAST_n = '1' then
                    if A(1) = '1' then
                        OUTREG(to_integer(unsigned(A(0 downto 0))))     <= DI;
                    else
                        for p in 0 to 1 loop
                            if to_integer(unsigned(A(0 downto 0))) = p then
                                if EXP_IOMASK(p) = '1' then
                                    IOMASK(p)        <= DI;
                                    EXP_IOMASK(p)    <= '0';
                                    SNAP(p)          <= '1';
                                elsif EXP_INTMASK(p) = '1' then
                                    INTMASK(p)       <= DI;
                                    EXP_INTMASK(p)   <= '0';
                                    SNAP(p)          <= '1';
                                elsif DI(0) = '0' then
                                    VECT(p)          <= DI;
                                elsif DI(3 downto 0) = "1111" then
                                    MODE(p)          <= DI(7 downto 6);
                                    if DI(7 downto 6) = "11" then EXP_IOMASK(p) <= '1'; end if;
                                elsif DI(3 downto 0) = "0111" then
                                    IE(p)            <= DI(7);
                                    ANDOR(p)         <= DI(6);
                                    HILO(p)          <= DI(5);
                                    EXP_INTMASK(p)   <= DI(4);
                                    PEND(p)          <= '0';
                                elsif DI(3 downto 0) = "0011" then
                                    IE(p)            <= DI(7);
                                end if;
                            end if;
                        end loop;
                    end if;
                end if;
            end if;
        end if;
    end process;

    REQ(0)                   <= PEND(0) and IE(0) and not IUS(0);
    REQ(1)                   <= PEND(1) and IE(1) and not IUS(0) and not IUS(1);
    INT_n                    <= '0' when REQ(0) = '1' or REQ(1) = '1' else '1';
    VECTOR_OE                <= '1' when INTA = '1' and (REQ(0) = '1' or REQ(1) = '1') else '0';
    DO                       <= VECT(0) when INTA = '1' and REQ(0) = '1' else
                                VECT(1) when INTA = '1' else
                                (PA_IN and IOMASK(0)) or (OUTREG(0) and not IOMASK(0)) when A = "10" and MODE(0) = "11" else
                                PA_IN                                                  when A = "10" else
                                (PB_IN and IOMASK(1)) or (OUTREG(1) and not IOMASK(1)) when A = "11" and MODE(1) = "11" else
                                PB_IN                                                  when A = "11" else
                                x"FF";
end rtl;
