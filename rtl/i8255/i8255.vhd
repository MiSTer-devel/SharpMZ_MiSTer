---------------------------------------------------------------------------------------------------------
--
-- Name:            i8255.vhd
-- Created:         Feb 2007
-- Author(s):       MikeJ (fpgaarcade), refactored and adapted for this emulation by Philip Smart
-- Description:     Sharp MZ series i8255 PPI
--                  This module emulates the Intel i8255 Programmable Peripheral Interface chip.
--
-- Credits:         
-- Copyright:       (c) MikeJ - Feb 2007
--
-- History:         July 2018   - Initial module refactored and updated for this emulation.
--
---------------------------------------------------------------------------------------------------------
--
-- Original copyright notice below:-
--
-- A simulation model of i8255 PIA
-- Copyright (c) MikeJ - Feb 2007
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS CODE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- You are responsible for any legal issues arising from your use of this code.
--
-- The latest version of this file can be found at: www.fpgaarcade.com
--
-- Email support@fpgaarcade.com
--
-- Revision list
--
-- version 001 initial release
--
---------------------------------------------------------------------------------------------------------

library ieee ;
  use ieee.std_logic_1164.all ;
  use ieee.std_logic_unsigned.all;
  use ieee.numeric_std.all;

entity i8255 is
    port (
        RESET                : in    std_logic;
        CLK                  : in    std_logic;
        ENA                  : in    std_logic;                    -- (CPU) clk enable
        ADDR                 : in    std_logic_vector(1 downto 0); -- A1-A0
        DI                   : in    std_logic_vector(7 downto 0); -- D7-D0
        DO                   : out   std_logic_vector(7 downto 0);

        CS_n                 : in    std_logic;
        RD_n                 : in    std_logic;
        WR_n                 : in    std_logic;
    
        PA_I                 : in    std_logic_vector(7 downto 0);
        PA_O                 : out   std_logic_vector(7 downto 0);
        PA_O_OE_n            : out   std_logic_vector(7 downto 0);
    
        PB_I                 : in    std_logic_vector(7 downto 0);
        PB_O                 : out   std_logic_vector(7 downto 0);
        PB_O_OE_n            : out   std_logic_vector(7 downto 0);
    
        PC_I                 : in    std_logic_vector(7 downto 0);
        PC_O                 : out   std_logic_vector(7 downto 0);
        PC_O_OE_n            : out   std_logic_vector(7 downto 0)
    );
end;

architecture RTL of i8255 is

    -- registers
    signal BIT_MASK          : std_logic_vector(7 downto 0);
    signal R_PORTA           : std_logic_vector(7 downto 0);
    signal R_PORTB           : std_logic_vector(7 downto 0);
    signal R_PORTC           : std_logic_vector(7 downto 0);
    signal R_CONTROL         : std_logic_vector(7 downto 0);
    --
    signal PORTA_WE          : std_logic;
    signal PORTB_WE          : std_logic;
    signal PORTA_RE          : std_logic;
    signal PORTB_RE          : std_logic;
    --
    signal PORTA_WE_T1       : std_logic;
    signal PORTB_WE_T1       : std_logic;
    signal PORTA_RE_T1       : std_logic;
    signal PORTB_RE_T1       : std_logic;
    --
    signal PORTA_WE_RISING   : boolean;
    signal PORTB_WE_RISING   : boolean;
    signal PORTA_RE_RISING   : boolean;
    signal PORTB_RE_RISING   : boolean;
    --
    signal GROUPA_MODE       : std_logic_vector(1 downto 0); -- port a/c upper
    signal GROUPB_MODE       : std_logic;                    -- port b/c lower
    --
    signal PORTA_READ        : std_logic_vector(7 downto 0);
    signal PORTB_READ        : std_logic_vector(7 downto 0);
    signal PORTC_READ        : std_logic_vector(7 downto 0);
    signal CONTROL_READ      : std_logic_vector(7 downto 0);
    signal MODE_CLEAR        : std_logic;
    --
    signal A_INTE1           : std_logic;
    signal A_INTE2           : std_logic;
    signal B_INTE            : std_logic;
    --
    signal A_INTR            : std_logic;
    signal A_OBF_L           : std_logic;
    signal A_IBF             : std_logic;
    signal A_ACK_L           : std_logic;
    signal A_STB_L           : std_logic;
    signal A_ACK_L_T1        : std_logic;
    signal A_STB_L_T1        : std_logic;
    --
    signal B_INTR            : std_logic;
    signal B_OBF_L           : std_logic;
    signal B_IBF             : std_logic;
    signal B_ACK_L           : std_logic;
    signal B_STB_L           : std_logic;
    signal B_ACK_L_T1        : std_logic;
    signal B_STB_L_T1        : std_logic;
    --
    signal A_ACK_L_RISING    : boolean;
    signal A_STB_L_RISING    : boolean;
    signal B_ACK_L_RISING    : boolean;
    signal B_STB_L_RISING    : boolean;
    --
    signal PORTA_IPREG       : std_logic_vector(7 downto 0);
    signal PORTB_IPREG       : std_logic_vector(7 downto 0);
begin
    --
    -- mode 0     - basic input/output
    -- mode 1     - strobed input/output
    -- mode 2/3 - bi-directional bus
    --
    -- control word (write)
    --
    -- D7        mode set flag                1 = active
    -- D6..5 GROUPA mode selection (mode 0,1,2)
    -- D4        GROUPA porta                 1 = input, 0 = output
    -- D3        GROUPA portc upper     1 = input, 0 = output
    -- D2        GROUPB mode selection (mode 0 ,1)
    -- D1        GROUPB portb                 1 = input, 0 = output
    -- D0        GROUPB portc lower     1 = input, 0 = output
    --
    -- D7        bit set/reset                0 = active
    -- D6..4 x
    -- D3..1 bit select
    -- d0        1 = set, 0 - reset
    --
    -- all output registers including status are reset when mode is changed
    --    1. Port A:
    --    All Modes: Output data is cleared, input data is not cleared.

    --    2. Port B:
    --    Mode 0: Output data is cleared, input data is not cleared.
    --    Mode 1 and 2: Both output and input data are cleared.

    --    3. Port C:
    --    Mode 0:Output data is cleared, input data is not cleared.
    --    Mode 1 and 2: IBF and INTR are cleared and OBF# is set.
    --    Outputs in Port C which are not used for handshaking or interrupt signals are cleared.
    --    Inputs such as STB#, ACK#, or "spare" inputs are not affected. The interrupts for Ports A and B are disabled.

    P_BIT_MASK : process(DI)
    begin
        BIT_MASK                            <= x"01";
        case DI(3 downto 1) is
            when "000"  => BIT_MASK         <= x"01";
            when "001"  => BIT_MASK         <= x"02";
            when "010"  => BIT_MASK         <= x"04";
            when "011"  => BIT_MASK         <= x"08";
            when "100"  => BIT_MASK         <= x"10";
            when "101"  => BIT_MASK         <= x"20";
            when "110"  => BIT_MASK         <= x"40";
            when "111"  => BIT_MASK         <= x"80";
            when others => null;
        end case;
    end process;

    P_WRITE_REG_RESET : process(RESET, CLK)
        variable R_PORTC_masked : std_logic_vector(7 downto 0);
        variable R_PORTC_setclr : std_logic_vector(7 downto 0);
    begin
        if (RESET = '1') then
            R_PORTA                         <= x"00";
            R_PORTB                         <= x"00";
            R_PORTC                         <= x"00";
            R_CONTROL                       <= x"9B"; -- 10011011
            MODE_CLEAR                      <= '1';

        elsif CLK'event and CLK = '1' then

            R_PORTC_masked := (not BIT_MASK) and R_PORTC;
            for i in 0 to 7 loop
                R_PORTC_setclr(i) := BIT_MASK(i) and DI(0);
            end loop;

            if (ENA = '1') then
                MODE_CLEAR                  <= '0';
                if (CS_n = '0') and (WR_n = '0') then
                    case ADDR is
                        when "00" => R_PORTA<= DI;
                        when "01" => R_PORTB<= DI;
                        when "10" => R_PORTC<= DI;

                        when "11" =>
                            if (DI(7) = '0') then -- set/clr
                                R_PORTC     <= R_PORTC_masked or R_PORTC_setclr;
                            else
                                --MODE_CLEAR <= '1';
                                --R_PORTA        <= x"00";
                                --R_PORTB        <= x"00"; -- clear port b input reg
                                --R_PORTC        <= x"00"; -- clear control sigs
                                R_CONTROL   <= DI; -- load new mode
                            end if;
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    P_DECODE_CONTROL : process(R_CONTROL)
    begin
        GROUPA_MODE                         <= R_CONTROL(6 downto 5);
        GROUPB_MODE                         <= R_CONTROL(2);
    end process;

    P_READ : process(ADDR, PORTA_READ, PORTB_READ, PORTC_READ, CONTROL_READ)
    begin
        DO <= x"00"; -- default
        --if (CS_n = '0') and (RD_n = '0') then -- not required
            case ADDR is
                when "00"   => DO           <= PORTA_READ;
                when "01"   => DO           <= PORTB_READ;
                when "10"   => DO           <= PORTC_READ;
                when "11"   => DO           <= CONTROL_READ;
                when others => null;
            end case;
        --end if;
    end process;
    CONTROL_READ(7)                         <= '1'; -- always 1
    CONTROL_READ(6 downto 0)                <= R_CONTROL(6 downto 0);

    P_RW_CONTROL : process(CS_n, RD_n, WR_n, ADDR)
    begin
        PORTA_WE                            <= '0';
        PORTB_WE                            <= '0';
        PORTA_RE                            <= '0';
        PORTB_RE                            <= '0';

        if (CS_n = '0') and (ADDR     = "00") then
            PORTA_WE                        <= not WR_n;
            PORTA_RE                        <= not RD_n;
        end if;

        if (CS_n = '0') and (ADDR     = "01") then
            PORTB_WE                        <= not WR_n;
            PORTB_RE                        <= not RD_n;
        end if;
    end process;

    P_RW_CONTROL_REG : process(RESET, CLK)
    begin
        if RESET = '1' then
                PORTA_WE_T1                 <= '0';
                PORTB_WE_T1                 <= '0';
                PORTA_RE_T1                 <= '0';
                PORTB_RE_T1                 <= '0';
                A_STB_L_T1                  <= '0';
                A_ACK_L_T1                  <= '0';
                B_STB_L_T1                  <= '0';
                B_ACK_L_T1                  <= '0';

        elsif CLK'event and CLK = '1' then
            if (ENA = '1') then
                PORTA_WE_T1                 <= PORTA_WE;
                PORTB_WE_T1                 <= PORTB_WE;
                PORTA_RE_T1                 <= PORTA_RE;
                PORTB_RE_T1                 <= PORTB_RE;

                A_STB_L_T1                  <= A_STB_L;
                A_ACK_L_T1                  <= A_ACK_L;
                B_STB_L_T1                  <= B_STB_L;
                B_ACK_L_T1                  <= B_ACK_L;
            end if ;
        end if;
    end process;

    PORTA_WE_RISING                         <= (PORTA_WE = '0') and (PORTA_WE_T1 = '1'); -- falling as inverted
    PORTB_WE_RISING                         <= (PORTB_WE = '0') and (PORTB_WE_T1 = '1'); --    "
    PORTA_RE_RISING                         <= (PORTA_RE = '0') and (PORTA_RE_T1 = '1'); -- falling as inverted
    PORTB_RE_RISING                         <= (PORTB_RE = '0') and (PORTB_RE_T1 = '1'); --    "
    --
    A_STB_L_RISING                          <= (A_STB_L = '1') and (A_STB_L_T1 = '0');
    A_ACK_L_RISING                          <= (A_ACK_L = '1') and (A_ACK_L_T1 = '0');
    B_STB_L_RISING                          <= (B_STB_L = '1') and (B_STB_L_T1 = '0');
    B_ACK_L_RISING                          <= (B_ACK_L = '1') and (B_ACK_L_T1 = '0');
    --
    -- GROUP A
    -- in mode 1
    --
    -- d4=1 (porta = input)
    --     pc7,6 io (d3=1 input, d3=0 output)
    --     pc5 output A_IBF
    --     pc4 input  A_STB_L
    --     pc3 output A_INTR
    --
    -- d4=0 (porta = output)
    --     pc7 output A_OBF_L
    --     pc6 input  A_ACK_L
    --     pc5,4 io (d3=1 input, d3=0 output)
    --     pc3 output A_INTR
    --
    -- GROUP B
    -- in mode 1
    -- d1=1 (portb = input)
    --     pc2 input  B_STB_L
    --     pc1 output B_IBF
    --     pc0 output B_INTR
    --
    -- d1=0 (portb = output)
    --     pc2 input  B_ACK_L
    --     pc1 output B_OBF_L
    --     pc0 output B_INTR


    -- WHEN AN INPUT
    --
    -- stb_l a low on this input latches input data
    -- ibf     a high on this output indicates data latched. set by stb_l and reset by rising edge of RD_L
    -- intr    a high on this output indicates interrupt. set by stb_l high, ibf high and inte high. reset by falling edge of RD_L
    -- inte A controlled by bit/set PC4
    -- inte B controlled by bit/set PC2

    -- WHEN AN OUTPUT
    --
    -- obf_l output will go low when cpu has written data
    -- ack_l input - a low on this clears obf_l
    -- intr    output set when ack_l is high, obf_l is high and inte is one. reset by falling edge of WR_L
    -- inte A controlled by bit/set PC6
    -- inte B controlled by bit/set PC2

    -- GROUP A
    -- in mode 2
    --
    -- porta = IO
    --
    --    control bits 2..0 still control groupb/c lower 2..0
    --
    --
    --    PC7 output a_obf
    --    PC6 input    A_ACK_L
    --    PC5 output A_IBF
    --    PC4 input    A_STB_L
    --    PC3 is still interrupt out
    P_CONTROL_FLAGS : process(RESET, CLK)
        variable we     : boolean;
        variable set1   : boolean;
        variable set2   : boolean;
    begin
        if (RESET = '1') then
            A_OBF_L                         <= '1';
            A_INTE1                         <= '0';
            A_IBF                           <= '0';
            A_INTE2                         <= '0';
            A_INTR                          <= '0';
            --
            B_INTE                          <= '0';
            B_OBF_L                         <= '1';
            B_IBF                           <= '0';
            B_INTR                          <= '0';
        elsif rising_edge(CLK) then
            we := (CS_n = '0') and (WR_n = '0') and (ADDR = "11") and (DI(7) = '0');

            if (ENA = '1') then
                if (MODE_CLEAR = '1') then
                    A_OBF_L                 <= '1';
                    A_INTE1                 <= '0';
                    A_IBF                   <= '0';
                    A_INTE2                 <= '0';
                    A_INTR                  <= '0';
                    --
                    B_INTE                  <= '0';
                    B_OBF_L                 <= '1';
                    B_IBF                   <= '0';
                    B_INTR                  <= '0';
                else
                    if (BIT_MASK(7) = '1') and we then
                        A_OBF_L             <= DI(0);
                    else
                        if PORTA_WE_RISING then
                            A_OBF_L         <= '0';
                        elsif (A_ACK_L = '0') then
                            A_OBF_L         <= '1';
                        end if;
                    end if;
                    --
                    if (BIT_MASK(6) = '1') and we then
                        A_INTE1             <= DI(0);
                    end if; -- bus set when mode1 & input?
                    --
                    if (BIT_MASK(5) = '1') and we then
                        A_IBF               <= DI(0);
                    else
                        if PORTA_RE_RISING then
                            A_IBF           <= '0';
                        elsif (A_STB_L = '0') then
                            A_IBF           <= '1';
                        end if;
                    end if;
                    --
                    if (BIT_MASK(4) = '1') and we then
                        A_INTE2             <= DI(0);
                    end if; -- bus set when mode1 & output?
                    --
                    set1 := A_ACK_L_RISING and (A_OBF_L = '1') and (A_INTE1 = '1');
                    set2 := A_STB_L_RISING and (A_IBF   = '1') and (A_INTE2 = '1');
                    --
                    if (BIT_MASK(3) = '1') and we then
                        A_INTR              <= DI(0);
                    else
                        if (GROUPA_MODE(1) = '1') then
                            if (PORTA_WE = '1') or (PORTA_RE = '1') then
                                 A_INTR     <= '0';
                             elsif set1 or set2 then
                                 A_INTR     <= '1';
                             end if;
                        else
                            if (R_CONTROL(4) = '0') then -- output
                                if (PORTA_WE = '1') then -- falling ?
                                    A_INTR  <= '0';
                                elsif set1 then
                                    A_INTR  <= '1';
                                end if;
                            elsif (R_CONTROL(4) = '1') then -- input
                                if (PORTA_RE = '1') then -- falling ?
                                    A_INTR  <= '0';
                                elsif set2 then
                                    A_INTR  <= '1';
                                end if;
                            end if;
                        end if;
                    end if;
                    --
                    if (BIT_MASK(2) = '1') and we then
                        B_INTE              <= DI(0);
                    end if; -- bus set?

                    if (BIT_MASK(1) = '1') and we then
                        B_OBF_L             <= DI(0);
                    else
                        if (R_CONTROL(1) = '0') then -- output
                            if PORTB_WE_RISING then
                                B_OBF_L     <= '0';
                            elsif (B_ACK_L = '0') then
                                B_OBF_L     <= '1';
                            end if;
                        else
                            if PORTB_RE_RISING then
                                B_IBF       <= '0';
                            elsif (B_STB_L = '0') then
                                B_IBF       <= '1';
                            end if;
                        end if;
                    end if;

                    if (BIT_MASK(0) = '1') and we then
                        B_INTR              <= DI(0);
                    else
                        if (R_CONTROL(1) = '0') then -- output
                            if (PORTB_WE = '1') then -- falling ?
                                B_INTR      <= '0';
                            elsif B_ACK_L_RISING and (B_OBF_L = '1') and (B_INTE = '1') then
                                B_INTR      <= '1';
                            end if;
                        else
                            if (PORTB_RE = '1') then -- falling ?
                                B_INTR      <= '0';
                            elsif B_STB_L_RISING and (B_IBF = '1') and (B_INTE = '1') then
                                B_INTR      <= '1';
                            end if;
                        end if;
                    end if;

                end if;
            end if;
        end if;
    end process;

    P_PORTA : process(R_PORTA, R_CONTROL, GROUPA_MODE, PA_I, PORTA_IPREG, A_ACK_L)
    begin
        -- D4 GROUPA porta 1 = input, 0 = output
        PA_O                                <= x"FF"; -- if not driven, float high
        PA_O_OE_n                           <= x"FF";
        PORTA_READ                          <= x"00";

        if (GROUPA_MODE = "00") then -- simple io
        PA_O                                <= R_CONTROL; -- x"5F"; -- if not driven, float high
            if (R_CONTROL(4) = '0') then -- output
                PA_O                        <= R_PORTA;
                PA_O_OE_n                   <= x"00";
            end if;
            PORTA_READ                      <= PA_I;
        elsif (GROUPA_MODE = "01") then -- strobed
            if (R_CONTROL(4) = '0') then -- output
                PA_O                        <= R_PORTA;
                PA_O_OE_n                   <= x"00";
            end if;
            PORTA_READ                      <= PORTA_IPREG;
        else -- if (GROUPA_MODE(1) = '1') then -- bi dir
            if (A_ACK_L = '0') then -- output enable
                PA_O                        <= R_PORTA;
                PA_O_OE_n                   <= x"00";
            end if;
            PORTA_READ                      <= PORTA_IPREG; -- latched dat
        end if;

    end process;

    P_PORTB : process(R_PORTB, R_CONTROL, GROUPB_MODE, PB_I, PORTB_IPREG)
    begin
        PB_O                                <= x"FF"; -- if not driven, float high
        PB_O_OE_n                           <= x"FF";
        PORTB_READ                          <= x"00";

        if (GROUPB_MODE = '0') then -- simple io
            if (R_CONTROL(1) = '0') then -- output
                PB_O                        <= R_PORTB;
                PB_O_OE_n                   <= x"00";
            end if;
            PORTB_READ                      <= PB_I;
        else -- strobed mode
            if (R_CONTROL(1) = '0') then -- output
                PB_O                        <= R_PORTB;
                PB_O_OE_n                   <= x"00";
            end if;
            PORTB_READ                      <= PORTB_IPREG;
        end if;
    end process;

    P_PORTC_OUT : process(R_PORTC, R_CONTROL, GROUPA_MODE, GROUPB_MODE, A_OBF_L, A_IBF, A_INTR,B_OBF_L, B_IBF, B_INTR)
    begin
        PC_O                                <= x"FF"; -- if not driven, float high
        PC_O_OE_n                           <= x"FF";

        -- bits 7..4
        if (GROUPA_MODE = "00") then -- simple io
            if (R_CONTROL(3) = '0') then -- output
                PC_O(7 downto 4)            <= R_PORTC(7 downto 4);
                PC_O_OE_n(7 downto 4)       <= x"0";
            end if;
        elsif (GROUPA_MODE = "01") then -- mode1

            if (R_CONTROL(4) = '0') then -- port a output
                PC_O(7)                     <= A_OBF_L;
                PC_O_OE_n(7)                <= '0';
                -- 6 is ack_l input
                if (R_CONTROL(3) = '0') then -- port c output
                    PC_O(5 downto 4)        <= R_PORTC(5 downto 4);
                    PC_O_OE_n(5 downto 4)   <= "00";
                end if;
            else -- port a input
                if (R_CONTROL(3) = '0') then -- port c output
                    PC_O(7 downto 6)        <= R_PORTC(7 downto 6);
                    PC_O_OE_n(7 downto 6)   <= "00";
                end if;
                PC_O(5)                     <= A_IBF;
                PC_O_OE_n(5)                <= '0';
                -- 4 is stb_l input
            end if;

        else -- if (GROUPA_MODE(1) = '1') then -- mode2
            PC_O(7)                         <= A_OBF_L;
            PC_O_OE_n(7)                    <= '0';
            -- 6 is ack_l input
            PC_O(5)                         <= A_IBF;
            PC_O_OE_n(5)                    <= '0';
            -- 4 is stb_l input
        end if;

        -- bit 3 (controlled by group a)
        if (GROUPA_MODE = "00") then -- group a steals this bit
            --if (GROUPB_MODE = '0') then -- we will let bit 3 be driven, data sheet is a bit confused about this
            if (R_CONTROL(0) = '0') then -- ouput (note, groupb control bit)
                PC_O(3)                     <= R_PORTC(3);
                PC_O_OE_n(3)                <= '0';
            end if;
            --
        else -- stolen
            PC_O(3)                         <= A_INTR;
            PC_O_OE_n(3)                    <= '0';
        end if;

        -- bits 2..0
        if (GROUPB_MODE = '0') then -- simple io
            if (R_CONTROL(0) = '0') then -- output
                PC_O(2 downto 0)            <= R_PORTC(2 downto 0);
                PC_O_OE_n(2 downto 0)       <= "000";
            end if;
        else
            -- mode 1
            -- 2 is input
            if (R_CONTROL(1) = '0') then -- output
                PC_O(1)                     <= B_OBF_L;
                PC_O_OE_n(1)                <= '0';
            else -- input
                PC_O(1)                     <= B_IBF;
                PC_O_OE_n(1)                <= '0';
            end if;
            PC_O(0)                         <= B_INTR;
            PC_O_OE_n(0)                    <= '0';
        end if;
    end process;

    P_PORTC_IN : process(R_PORTC, PC_I, R_CONTROL, GROUPA_MODE, GROUPB_MODE, A_IBF, B_OBF_L, A_OBF_L, A_INTE1, A_INTE2, A_INTR, B_INTE, B_IBF, B_INTR)
    begin
        PORTC_READ                          <= x"00";
        A_STB_L                             <= '1';
        A_ACK_L                             <= '1';
        B_STB_L                             <= '1';
        B_ACK_L                             <= '1';

        if (GROUPA_MODE = "01") then -- mode1 or 2
            if (R_CONTROL(4) = '0') then -- port a output
                A_ACK_L                     <= PC_I(6);
            else -- port a input
                A_STB_L                     <= PC_I(4);
            end if;
        elsif (GROUPA_MODE(1) = '1') then -- mode 2
            A_ACK_L                         <= PC_I(6);
            A_STB_L                         <= PC_I(4);
        end if;

        if (GROUPB_MODE = '1') then
            if (R_CONTROL(1) = '0') then -- output
                B_ACK_L                     <= PC_I(2);
            else -- input
                B_STB_L                     <= PC_I(2);
            end if;
        end if;

        if (GROUPA_MODE = "00") then -- simple io
            PORTC_READ(7 downto 3)          <= PC_I(7 downto 3);
        elsif (GROUPA_MODE = "01") then
            if (R_CONTROL(4) = '0') then -- port a output
                PORTC_READ(7 downto 3)      <= A_OBF_L & A_INTE1 & PC_I(5 downto 4) & A_INTR;
            else -- input
                PORTC_READ(7 downto 3)      <= PC_I(7 downto 6)  & A_IBF & A_INTE2 & A_INTR;
            end if;
        else -- mode 2
            PORTC_READ(7 downto 3)          <= A_OBF_L & A_INTE1 & A_IBF & A_INTE2 & A_INTR;
        end if;

        if (GROUPB_MODE = '0') then -- simple io
            PORTC_READ(2 downto 0)          <= PC_I(2 downto 0);
        else
            if (R_CONTROL(1) = '0') then -- output
                PORTC_READ(2 downto 0)      <= B_INTE & B_OBF_L & B_INTR;
            else -- input
                PORTC_READ(2 downto 0)      <= B_INTE & B_IBF   & B_INTR;
            end if;
        end if;
    end process;

    P_IPREG : process(RESET, CLK)
    begin
        if RESET = '1' then
            PORTA_IPREG                     <= (others => '0');
            PORTB_IPREG                     <= (others => '0');
            PORTB_IPREG                     <= (others => '0');

        elsif CLK'event and CLK = '1' then
            --     pc4 input    A_STB_L
            --     pc2 input    B_STB_L

            if (ENA = '1') then
                if (A_STB_L = '0') then
                    PORTA_IPREG             <= PA_I;
                end if;

                if (MODE_CLEAR = '1') then
                    PORTB_IPREG             <= (others => '0');
                elsif (B_STB_L = '0') then
                    PORTB_IPREG             <= PB_I;
                end if;
            end if;
        end if;
    end process;

end architecture RTL;
