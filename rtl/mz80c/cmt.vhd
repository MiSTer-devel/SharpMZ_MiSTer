---------------------------------------------------------------------------------------------------------
--
-- Name:            cmt.vhd
-- Created:         July 2018
-- Author(s):       Philip Smart
-- Description:     Sharp MZ series PWM Tape Interface.
--                  This module fully emulates the Sharp PWM tape interface. It uses cache ram
--                  to simulate the tape. Data is played out to the Sharp or read from the Sharp
--                  and stored in the ram.
--                  For reading of data from Tape to the Sharp, the HPS or other controller loads a
--                  complete tape into ram and should the Play/Auto function be enabled, playback
--                  starts immediately.
--                  For writing of data from the Sharp to Taoe, the data is stored in ram and the
--                  HPS or other controller, when it gets the completed signal, can read out the ram
--                  and store the data onto a local filesystem.
-- Credits:         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         July 2018   - Initial module written and playback mode tested and debugged.
--                  August 2018 - Record mode written but not yet debugged/completed.
--
---------------------------------------------------------------------------------------------------------
-- This source file is free software: you can redistribute it and-or modify
-- it under the terms of the GNU General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This source file is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http:--www.gnu.org-licenses->.
---------------------------------------------------------------------------------------------------------

library ieee;
library pkgs;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use pkgs.clkgen_pkg.all;
use pkgs.mctrl_pkg.all;
use ieee.numeric_std.all;

entity cmt is
    Port (
        RST                  : in  std_logic;

        -- Clock signals needed by this module.
        CLKBUS               : in  std_logic_vector(CLKBUS_WIDTH);        

        -- Different operations modes.
        CONFIG               : in  std_logic_vector(CONFIG_WIDTH);

        -- Cassette magnetic tape signals.
        CMTBUS               : out std_logic_vector(CMTBUS_WIDTH);
        CMT_READBIT          : in  std_logic;
        CMT_MOTOR            : in  std_logic;

        -- HPS Interface
        IOCTL_DOWNLOAD       : in  std_logic;                            -- HPS Downloading to FPGA.
        IOCTL_UPLOAD         : in  std_logic;                            -- HPS Uploading from FPGA.
        IOCTL_CLK            : in  std_logic;                            -- HPS I/O Clock.
        IOCTL_WR             : in  std_logic;                            -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                            -- HPS Read Enable from FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(15 downto 0);        -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(15 downto 0);        -- HPS Data to be read into HPS.

        -- Debug Status Leds
        DEBUG_STATUS_LEDS    : out std_logic_vector(23 downto 0)         -- 8 leds to display cmt internal status.
    );
end cmt;

architecture RTL of cmt is

--
-- Components
--
component dpram
    generic (
          init_file          :     string;
          widthad_a          :     natural;
          width_a            :     natural;
          widthad_b          :     natural;
          width_b            :     natural;
          outdata_reg_a      :     string := "UNREGISTERED";
          outdata_reg_b      :     string := "UNREGISTERED"
    );
    Port (
          clock_a            : in  std_logic  := '1';
          clocken_a          : in  std_logic  := '1';
          address_a          : in  std_logic_vector (widthad_a-1 downto 0);
          data_a             : in  std_logic_vector (width_a-1 downto 0);
          wren_a             : in  std_logic  := '0';
          q_a                : out std_logic_vector (width_a-1 downto 0);

          clock_b            : in  std_logic;
          clocken_b          : in  std_logic  := '1';
          address_b          : in  std_logic_vector (widthad_b-1 downto 0);
          data_b             : in  std_logic_vector (width_b-1 downto 0);
          wren_b             : in  std_logic  := '0';
          q_b                : out std_logic_vector (width_b-1 downto 0)
      );
end component;

-- HPS Control signals.
signal IOCTL_CS_HDR_n        :     std_logic;
signal IOCTL_CS_DATA_n       :     std_logic;
signal IOCTL_TAPEHDR_WEN     :     std_logic;
signal IOCTL_TAPEDATA_WEN    :     std_logic;
signal IOCTL_DIN_HDR         :     std_logic_vector(7 downto 0);
signal IOCTL_DIN_DATA        :     std_logic_vector(7 downto 0);
--
signal CMTBUSi               :     std_logic_vector(CMTBUS_WIDTH);
signal BUTTONS_LAST          :     std_logic_vector(1 downto 0);
signal PLAY_READY_CNT        :     integer range 0 to 224000000  := 0;   -- 2 second timer.
signal PLAY_READY            :     std_logic;
signal PLAY_READY_CLR        :     std_logic;
signal PLAY_READY_SEQ        :     std_logic_vector(1 downto 0);             -- Setup and hold sequencer.
signal PLAY_BUTTON           :     std_logic;
signal PLAYING               :     std_logic_vector(2 downto 0);
signal RECORD_READY          :     std_logic;
signal RECORD_READY_SET      :     std_logic;
signal RECORD_READY_SEQ      :     std_logic_vector(1 downto 0);             -- Setup and hold sequencer.
signal RECORD_BUTTON         :     std_logic;
signal RECORDING             :     std_logic_vector(2 downto 0);
signal MOTOR_CLK             :     std_logic_vector(1 downto 0);
signal MOTOR_SENSE           :     std_logic;
signal WRITEBIT              :     std_logic;
signal READBIT               :     std_logic;
signal TAPE_MOTOR_ON_n       :     std_logic;
-- Bit receiver signals.
signal RCV_BIT               :     std_logic;                                -- Received bit after PWM demodulation coming from MZ.
signal RCV_AVAIL             :     std_logic;                                -- Received bit is available and valid.
signal RCV_SEQ               :     std_logic_vector(2 downto 0);             -- Setup and hold sequencer.
signal RCV_COUNT             :     integer range -3095 to 3095  := 0;
-- Bit transmitter signals.
signal XMIT_DONE             :     std_logic;                                -- Transmit of bit complete.
signal XMIT_SEQ              :     std_logic_vector(2 downto 0);             -- Setup and hold sequencer.
signal XMIT_LOAD_1           :     std_logic;                                -- Load bit and start transmission selector 1.
signal XMIT_LOAD_2           :     std_logic;                                -- Load bit and start transmission selector 2.
signal XMIT_BIT_1            :     std_logic;                                -- Transmit bit for XMIT_LOAD_2 to be PWM modulated and sent to MZ.
signal XMIT_BIT_2            :     std_logic;                                -- Working bit for active XMIT_BIT.
signal XMIT_COUNT            :     integer range -7999 to 8000 := 0;
signal XMIT_LIMIT            :     integer range -7999 to 8000 := 0;
-- Bit padding transmitter signals.
signal XMIT_PADDING_LOAD     :     std_logic;
signal XMIT_PADDING_BIT      :     std_logic;
signal XMIT_PADDING_DONE     :     std_logic;
signal XMIT_PADDING_CNT1     :     integer range 0 to 32767   := 0;
signal XMIT_PADDING_CNT2     :     integer range 0 to 32767   := 0;
signal XMIT_PADDING_LEVEL1   :     std_logic;
signal XMIT_PADDING_LEVEL2   :     std_logic;
signal PADDING_SEQ           :     std_logic_vector(2 downto 0);             -- Setup and hold sequencer.
signal PADDING_CNT1          :     integer range 0 to 32767   := 0;
signal PADDING_CNT2          :     integer range 0 to 32767   := 0;
signal PADDING_LEVEL1        :     std_logic;
signal PADDING_LEVEL2        :     std_logic;
-- Cache RAM header/data transmitter signals.
signal XMIT_RAM_LOAD         :     std_logic;
signal XMIT_RAM_DONE         :     std_logic;
signal XMIT_RAM_SEQ          :     std_logic_vector(2 downto 0);             -- Setup and hold sequencer.
signal XMIT_RAM_ADDR         :     std_logic_vector(15 downto 0);
signal XMIT_RAM_COUNT        :     unsigned(15 downto 0);
signal XMIT_RAM_CHKSUM_CNT   :     unsigned(1 downto 0);
signal XMIT_RAM_CHECKSUM     :     std_logic_vector(15 downto 0);
signal XMIT_RAM_TYPE         :     std_logic;
signal XMIT_RAM_STATE        :     integer range 0 to 7 := 0;
signal XMIT_RAM_SR           :     std_logic_vector(8 downto 0);
signal XMIT_RAM_BITCNT       :     integer range 0 to 8 := 0;
signal XMIT_TAPE_SIZE        :     unsigned(15 downto 0);
-- RAM control signals.
signal RAM_ADDR              :     std_logic_vector(15 downto 0);
signal RAM_DATAIN            :     std_logic_vector(7 downto 0);
signal HDR_RAM_DATAOUT       :     std_logic_vector(7 downto 0);
signal HDR_RAM_WEN           :     std_logic;
signal DATA_RAM_DATAOUT      :     std_logic_vector(7 downto 0);
signal DATA_RAM_WEN          :     std_logic;
--
signal RCV_PADDING_LOAD      :     std_logic;
signal RCV_PADDING_DONE      :     std_logic;
signal RCV_PADDING_CNT       :     integer range 0 to 30000 := 0;
signal RCV_PADDING_LEVEL     :     std_logic;
signal RCV_PADDING_SEQ       :     std_logic_vector(2 downto 0);             -- Setup and hold sequencer.
signal PADDING_CNT           :     integer range 0 to 30000 := 0;
signal PADDING_LEVEL         :     std_logic;
--
signal RCV_RAM_LOAD          :     std_logic;
signal RCV_RAM_DONE          :     std_logic;
signal RCV_RAM_SUCCESS       :     std_logic;
signal RCV_RAM_ADDR          :     std_logic_vector(15 downto 0);
signal RCV_RAM_STATE         :     integer range 0 to 10 := 0;
signal RCV_RAM_TYPE          :     std_logic;
signal RCV_RAM_RETRIES       :     std_logic;
signal RCV_RAM_COUNT         :     unsigned(15 downto 0);
signal RCV_RAM_CHECKSUM      :     std_logic_vector(15 downto 0);
signal RCV_RAM_CNT_CKSUM     :     std_logic;
signal RCV_RAM_CALC_CKSUM    :     std_logic_vector(15 downto 0);
signal RCV_RAM_SEQ           :     std_logic_vector(2 downto 0);             -- Setup and hold sequencer.
signal RCV_RAM_SR            :     std_logic_vector(8 downto 0);
signal RCV_RAM_BITCNT        :     integer range 0 to 8 := 0;
signal RCV_TAPE_SIZE         :     unsigned(15 downto 0);
-- Main process Finite State Machine variables.
signal TAPE_READ_STATE       :     integer range 0 to 15       := 0;
signal TAPE_READ_SEQ         :     std_logic_vector(2 downto 0);             -- Setup and hold sequencer.
signal TAPE_WRITE_STATE      :     integer range 0 to 15       := 0;
signal TAPE_WRITE_SEQ        :     std_logic_vector(2 downto 0);             -- Setup and hold sequencer.
--
begin

    -- Wired signals between this CMT unit and the MZ/MCtrl bus.
    --
    CMTBUSi(pkgs.mctrl_pkg.WRITEBIT)     <= WRITEBIT;                    -- Write a bit to the MZ PIO.
    CMTBUSi(pkgs.mctrl_pkg.READBIT)      <= CMT_READBIT;                 -- Read a bit from the MZ PIO.
    CMTBUSi(pkgs.mctrl_pkg.SENSE)        <= MOTOR_SENSE;                 -- Indiate current state of Motor, 0 if not running, 1 if running.
    CMTBUSi(pkgs.mctrl_pkg.ACTIVE)       <= PLAYING(2) or RECORDING(2); 
    CMTBUSi(pkgs.mctrl_pkg.PLAY_READY)   <= PLAY_READY;
    CMTBUSi(pkgs.mctrl_pkg.PLAYING)      <= PLAYING(2);
    CMTBUSi(pkgs.mctrl_pkg.RECORD_READY) <= RECORD_READY;
    CMTBUSi(pkgs.mctrl_pkg.RECORDING)    <= RECORDING(1);
    CMTBUSi(pkgs.mctrl_pkg.MOTOR)        <= TAPE_MOTOR_ON_n;
    --
    READBIT                              <= CMT_READBIT; 
    MOTOR_CLK(1)                         <= CMT_MOTOR;
    CMTBUS                               <= CMTBUSi;

    -- Mux Signals from different sources.
    RAM_ADDR                            <= RCV_RAM_ADDR when RECORDING(1) = '1' else XMIT_RAM_ADDR;
    IOCTL_CS_HDR_n                      <= '0' when IOCTL_ADDR(24 downto 8)  = "00000010100000000" else '1';
    IOCTL_CS_DATA_n                     <= '0' when IOCTL_ADDR(24 downto 16) = "000000110"         else '1';
    IOCTL_TAPEHDR_WEN                   <= '1' when IOCTL_CS_HDR_n  = '0' and IOCTL_WR = '1'       else '0';
    IOCTL_TAPEDATA_WEN                  <= '1' when IOCTL_CS_DATA_n = '0' and IOCTL_WR = '1'       else '0';
    IOCTL_DIN                           <= X"00" & IOCTL_DIN_HDR  when IOCTL_CS_HDR_n = '0'
                                           else
                                           X"00" & IOCTL_DIN_DATA when IOCTL_CS_DATA_n = '0'
                                           else
                                           (others => '0');

    TAPEHDR : dpram
    GENERIC MAP (
        init_file            => null,
        widthad_a            => 7,
        width_a              => 8,
        widthad_b            => 7,
        width_b              => 8
    )
    PORT MAP (
        clock_a              => CLKBUS(CKMEM),
        clocken_a            => '1',
        address_a            => RAM_ADDR(6 downto 0),
        data_a               => RAM_DATAIN,
        wren_a               => HDR_RAM_WEN,
        q_a                  => HDR_RAM_DATAOUT,

        clock_b              => IOCTL_CLK,
        address_b            => IOCTL_ADDR(6 downto 0),
        data_b               => IOCTL_DOUT(7 downto 0),
        wren_b               => IOCTL_TAPEHDR_WEN,
        q_b                  => IOCTL_DIN_HDR
    );

    TAPEDATA : dpram
    GENERIC MAP (
        init_file            => null,
        widthad_a            => 16,
        width_a              => 8,
        widthad_b            => 16,
        width_b              => 8
    )
    PORT MAP (
        clock_a              => CLKBUS(CKMEM),
        clocken_a            => '1',
        address_a            => RAM_ADDR,
        data_a               => RAM_DATAIN,
        wren_a               => DATA_RAM_WEN,
        q_a                  => DATA_RAM_DATAOUT,

        clock_b              => IOCTL_CLK,
        address_b            => IOCTL_ADDR(15 downto 0),
        data_b               => IOCTL_DOUT(7 downto 0),
        wren_b               => IOCTL_TAPEDATA_WEN,
        q_b                  => IOCTL_DIN_DATA
    );

    --------------------------------------------------------------------
    -- TAPE HEADER FORMAT
    --------------------------------------------------------------------
    -- LGAP | LTM | L | HDR  | CHKH | L | 256S | HDRC  | CHKH | L
    -- SGAP | STM | L | FILE | CHKF | L | 256S | FILEC | CHKF | L
    -- LGAP  is a long GAP
    -- SGAP  is a short GAP
    -- LTM   is a long tapemark - 40 long pulses then 40 short pulses
    -- STM   is a short tapemark - 20 long pulses then 20 short puses 
    -- HDR   is the tapeheader
    -- HDRC  is a copy of the tapeheader
    -- FILE  is the file
    -- FILEC is a copy of the file
    -- CHKH  is a 2 byte checksum of the tape header or its copy
    -- CHKF  is a 2 byte checksum of the file or its copy
    -- L     is 1 long pulse
    -- 256S contains 256 short pulses
    --------------------------------------------------------------------

    -- Process to determine CMT state according to inputs. ie. If we are STOPPED, PLAYING or RECORDING.
    -- This is determined by the input switches in CONFIG(BUTTOS), 00 = Off, 01 = Play, 02 = Record and 03 = Auto.
    -- Auto mode indicates the CMT logic has to determine wether it is PLAYING or RECORDING. The default is PLAYING
    -- but if a bit is received from the MZ then we switch to RECORDING until a full tape dump has been received.
    --
    process( RST, CLKBUS(CKCPU), CONFIG(BUTTONS), MOTOR_CLK ) begin
        if RST='1' then
            TAPE_MOTOR_ON_n         <= '1';
            MOTOR_SENSE             <= '0';
            PLAY_BUTTON             <= '0';
            RECORD_BUTTON           <= '0';
            BUTTONS_LAST            <= "00";
            PLAYING                 <= "000";
            RECORDING               <= "000";
            MOTOR_CLK(0)            <= '0';

        elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU)='1' then
                
            -- Store last state so we detect change.
            BUTTONS_LAST                <= CONFIG(BUTTONS);
            MOTOR_CLK(0)                <= MOTOR_CLK(1);

            -- Store last state so we can detect a switch to recording or play mode.
            RECORDING(1 downto 0)       <= RECORDING(2 downto 1);
            PLAYING(1 downto 0)         <= PLAYING(2 downto 1);

            -- Process the buttons and adapt signals accordingly.
            --
            if BUTTONS_LAST /= CONFIG(BUTTONS) then
                case CONFIG(BUTTONS) is
                    when "00" => -- Off
                        PLAY_BUTTON     <= '0';
                        RECORD_BUTTON   <= '0';
                        TAPE_MOTOR_ON_n <= '1';
                    when "10" => -- Record
                        PLAY_BUTTON     <= '0';
                        RECORD_BUTTON   <= '1';
                        TAPE_MOTOR_ON_n <= '0';
                    when "01"|"11" => -- Play/Auto
                        -- Assume playback mode for Auto unless activity is detected from the MZ,
                        -- in which case switch to Recording.
                        PLAY_BUTTON     <= '1';
                        RECORD_BUTTON   <= '0';
                        TAPE_MOTOR_ON_n <= '0';
                end case;
            end if;
            
            -- If in auto mode and data starts being received from the MZ, enter record mode.
            --
            if CONFIG(BUTTONS) = "11" and RCV_AVAIL = '1' then
                PLAY_BUTTON             <= '0';
                RECORD_BUTTON           <= '1';
                TAPE_MOTOR_ON_n         <= '0';
            end if;

            -- If the motor is running then setup the state according to the buttons pressed and the data availability.
            --
            if TAPE_MOTOR_ON_n = '0'    and PLAY_BUTTON = '1'   and PLAY_READY = '1' then
                PLAYING(2)              <= '1';
                RECORDING(2)            <= '0';
                MOTOR_SENSE             <= '1';
            elsif TAPE_MOTOR_ON_n = '0' and RECORD_BUTTON = '1' then
                PLAYING(2)              <= '0';
                RECORDING(2)            <= '1';
                MOTOR_SENSE             <= '1';
            elsif CONFIG(BUTTONS) /= "11" then
                PLAYING(2)              <= '0';
                RECORDING(2)            <= '0';
                MOTOR_SENSE             <= not TAPE_MOTOR_ON_n;
            end if;

            -- MZ motor on/off toggle. A high pulse on MOTOR_CLK will toggle the motor state.
            --
            if MOTOR_CLK = "10" then
                TAPE_MOTOR_ON_n <= not TAPE_MOTOR_ON_n;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------------------------------------------------
    -- Write To Tape logic.
    --
    -- This block concentrates all the logic required to receive data from the MZ into RAM (virtual tape).
    -- Viewed from the CMT, it is the reception of data from computer onto tape.
    ----------------------------------------------------------------------------------------------------------------------

    -- Trigger, when a write occurs to ram, start a counter. Each write resets the counter. After 1 second of
    -- no further writes, then the ram data is ready to play.
    -- Clear funtionality allows the logic to clear the ready signal to indicate data has been processed.
    --
    process( RST, IOCTL_CLK, IOCTL_TAPEHDR_WEN, IOCTL_TAPEDATA_WEN, IOCTL_CS_HDR_n, IOCTL_CS_DATA_n )
    begin
        if RST = '1' then
            PLAY_READY           <= '0';
            PLAY_READY_CNT       <= 0;
            PLAY_READY_SEQ       <= "00";
            RECORD_READY         <= '0';
            RECORD_READY_SEQ     <= "00";

        elsif IOCTL_CLK'event and IOCTL_CLK = '1' then

            -- Sample clear signal and hold. Shift right 2 bits, msb = latest value.
            PLAY_READY_SEQ(0)    <= PLAY_READY_SEQ(1);
            PLAY_READY_SEQ(1)    <= PLAY_READY_CLR;

            -- Sample record complete signal and hold. Shift righ 2 bits, msb = latest value.
            RECORD_READY_SEQ(0)  <= RECORD_READY_SEQ(1);
            RECORD_READY_SEQ(1)  <= RECORD_READY_SET;

            -- If the external clear is triggered, reset ready signal.
            if PLAY_READY_SEQ = "10" then
                PLAY_READY       <= '0';
                PLAY_READY_CNT   <= 0;

            -- Every write to ram resets the counter.
            elsif IOCTL_TAPEHDR_WEN = '1' or IOCTL_TAPEDATA_WEN = '1' then
                PLAY_READY       <= '0';
                PLAY_READY_CNT   <= 1;

            -- 1 second timer, if no new writes have occurred to RAM, then set the ready flag.
            elsif PLAY_READY_CNT >= 112000000 then
                PLAY_READY_CNT   <= 0;
                PLAY_READY       <= '1';
            end if;

            -- Set RECORD_READY if fsm determines a full tape message received.
            if RECORD_READY_SEQ = "10" then
                RECORD_READY     <= '1';

            -- HPS access resets signal.
            elsif IOCTL_CS_HDR_n = '0' or IOCTL_CS_DATA_n = '0' then
                RECORD_READY     <= '0';

            -- If the fsm resets the signal then clear the flag as it will be receiving a new tape message.
            elsif RECORD_READY_SEQ = "00" then
                RECORD_READY     <= '0';
            end if;

            -- Increment counters if enabled.
            if PLAY_READY_CNT >= 1 then
                PLAY_READY_CNT <= PLAY_READY_CNT + 1;
            end if;
        end if;
    end process;


    -- State machine to represent the tape drive WRITE mode (MZ -> RAM) using cache memory as the tape, which is read by the HPS after data is stored.
    --
    process( RST, CLKBUS(CKCPU), RECORDING ) begin
        -- For reset, hold machine in reset.
        if RST = '1' then
            RECORD_READY_SET <= '0';
            TAPE_WRITE_STATE <= 15;
            TAPE_WRITE_SEQ   <= "000";
            RCV_PADDING_LOAD <= '0';
            RCV_PADDING_LEVEL<= '0';
            RCV_PADDING_CNT  <= 0;
            RCV_RAM_LOAD     <= '0';
            RCV_RAM_TYPE     <= '0';

        elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU) = '1' then

            -- If recording is inactive, hold state variables in reset.
            if RECORDING = "00" then
                RECORD_READY_SET <= '0';
                TAPE_WRITE_STATE <= 15;
                TAPE_WRITE_SEQ   <= "000";
                RCV_PADDING_LOAD <= '0';
                RCV_PADDING_LEVEL<= '0';
                RCV_PADDING_CNT  <= 0;
                RCV_RAM_LOAD     <= '0';
                RCV_RAM_TYPE     <= '0';

            -- Change in recording state, start fsm to receive data from the MZ and store in the cache RAM ready for HPS upload.
            elsif RECORDING = "10" then
                if TAPE_WRITE_STATE = 15 then
                    TAPE_WRITE_STATE      <= 0;
                    RCV_RAM_TYPE          <= '0';
                end if;

            elsif RECORDING = "11" then
                
                -- Sample the done signal, when setup and stable, we can continue.
                TAPE_WRITE_SEQ(1 downto 0)<= TAPE_WRITE_SEQ(2 downto 1);
                TAPE_WRITE_SEQ(2)         <= (RCV_PADDING_LOAD or RCV_RAM_LOAD) and (RCV_PADDING_DONE and RCV_RAM_DONE);

                -- If reception has just been started and acknowledged by the DONE flag being reset, reset the activation strobe.
                --
                if TAPE_WRITE_SEQ = "111" then
                    RCV_PADDING_LOAD      <= '0';
                    RCV_RAM_LOAD          <= '0';
                end if;

                -- If reception is in progress, run the FSM.
                --
                if RCV_PADDING_LOAD = '0' and RCV_RAM_LOAD = '0' then

                    -- Default is to move onto next state per clock cycle, unless modified by the state action.
                    TAPE_WRITE_STATE      <= TAPE_WRITE_STATE + 1;

                    -- Execute current state.
                    case TAPE_WRITE_STATE is
        
                        -- As the Gap (Short/Long) is a continuous stream of '0' pulses, we can wait for 1000 '0' pulses then move onto the tapemark.
                        --
                        when 0 =>
                            RCV_PADDING_CNT      <= 1000;
                            RCV_PADDING_LEVEL    <= '0';
                            RCV_PADDING_LOAD     <= '1';       -- Wait for 100 '1' pulses from MZ.
                        when 1 => 
                            if RCV_PADDING_DONE = '0' then
                                TAPE_WRITE_STATE <= 1;
                            end if;
                        -- Wait for Tapemark, 40 long/short pulses for Header, 20 long/short pulses for Data.
                        when 2 =>
                            -- Header = 0, Data = 1
                            if RCV_RAM_TYPE = '0' then
                                -- Setup to receive a Long Tape Mark.
                                RCV_PADDING_CNT  <= 40;
                                RCV_PADDING_LEVEL<= '1';
                            else
                                -- Setup to receive a Short Tape Mark.
                                RCV_PADDING_CNT  <= 20;
                                RCV_PADDING_LEVEL<= '1';
                            end if;
                            RCV_PADDING_LOAD     <= '1';
                        when 3 => 
                            if RCV_PADDING_DONE = '0' then
                                TAPE_WRITE_STATE <= 3;
                            end if;
                        when 4 =>
                            -- Header = 0, Data = 1
                            if RCV_RAM_TYPE = '0' then
                                -- Setup to receive a Long Tape Mark.
                                RCV_PADDING_CNT  <= 40;
                                RCV_PADDING_LEVEL<= '0';
                            else
                                -- Setup to receive a Short Tape Mark.
                                RCV_PADDING_CNT  <= 20;
                                RCV_PADDING_LEVEL<= '0';
                            end if;
                            RCV_PADDING_LOAD     <= '1';
                        when 5 => 
                            if RCV_PADDING_DONE = '0' then
                                TAPE_WRITE_STATE <= 5;
                            end if;
                        -- Wait for single long pulse.
                        when 6 =>
                            RCV_PADDING_LEVEL    <= '1';
                            RCV_PADDING_CNT      <= 1;
                            RCV_PADDING_LOAD     <= '1';
                        when 7 => 
                            if RCV_PADDING_DONE = '0' then
                                TAPE_WRITE_STATE <= 7;
                            end if;

                        -- Now read in the header/data (MZ writing to RAM tape).
                        when 8 =>
                            RECORD_READY_SET     <= '0';
                            RCV_RAM_RETRIES      <= '1';
                        when 9 => 
                            RCV_RAM_LOAD         <= '1';
                        when 10 =>
                            if RCV_RAM_DONE = '0' then
                                TAPE_WRITE_STATE <= 10;
                            end if;
                        when 11 =>
                            if RCV_RAM_SUCCESS = '0' then
                                -- In the event the data block read checksum fails, perform 1 retry before pausing the FSM.
                                if RCV_RAM_RETRIES = '1' then
                                    RCV_RAM_RETRIES  <= '0';
                                    TAPE_WRITE_STATE <= 9;
                                else
                                    -- Nothing can be done, checksum errors shouldnt occur, so just exit.
                                    TAPE_WRITE_STATE <= 15;
                                end if;
                            end if;
                                
                        -- Wait for single long pulse.
                        when 12 =>
                            RCV_PADDING_LEVEL <= '1';
                            RCV_PADDING_CNT   <= 1;
                            RCV_PADDING_LOAD  <= '1';
                        when 13 => 
                            if RCV_PADDING_DONE = '0' then
                                TAPE_WRITE_STATE <= 13;
                            end if;

                        -- If we have received the header, switch to receive the data.
                        -- On completion, signal hps to read memory by setting status flag and start recording fsm again.
                        when 14 =>
                            if RCV_RAM_TYPE = '0' then
                                RCV_RAM_TYPE     <= '1';
                                TAPE_WRITE_STATE <= 0;
                            else
                                RECORD_READY_SET <= '1';
                                TAPE_WRITE_STATE <= 15;
                            end if;

                        -- Final state, stay until reset.
                        when 15 =>
                            TAPE_WRITE_STATE <= 15;
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- Process to recieve the header/data blocks and checksum from the MZ and store it into the cache RAM. ie. MZ -> RAM.
    -- The bit stream is assumed to be at the correct point and the data is serialised and loaded into the RAM.
    --
    -- RCV_RAM_DONE is high when the tape header and checksum have been received.
    --
    -- RCV_RAM_LOAD       =           = Start receiving the tape data and checksum.
    -- RCV_RAM_DONE       =           = Tape data and checksum recieved
    -- RCV_RAM_SUCCESS    =           = Tape data and checksum recieved, checksums match.
    -- CLKBUS(CKCPU)      =           = Base clock for encoding/decoding of pwm pulse.
    --
    process( RST, RCV_RAM_LOAD, CLKBUS(CKCPU) ) begin
        if RST = '1' then
            RCV_RAM_DONE            <= '0';
            RCV_RAM_SUCCESS         <= '0';
            RCV_RAM_ADDR            <= std_logic_vector(to_unsigned(0, 16));
            RCV_RAM_COUNT           <= to_unsigned(0, 16);                   -- Count of bytes to transmit, excludes checksum.
            RCV_RAM_CHECKSUM        <= std_logic_vector(to_unsigned(0, 16));
            RCV_RAM_STATE           <= 0;
            RCV_RAM_SEQ             <= "000";

        elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU) = '1' then

            -- Sample load signal and hold. Shift right 3 bits, msb = latest value.
            RCV_RAM_SEQ(1 downto 0) <= RCV_RAM_SEQ(2 downto 1);
            RCV_RAM_SEQ(2)          <= RCV_RAM_LOAD;

            -- If load is stable, acknowledge by bringing DONE low and start process.
            if RCV_RAM_SEQ = "111" then
                RCV_RAM_DONE        <= '0';
                RCV_RAM_SUCCESS     <= '0';

            -- When RCV_RAM_LOAD is asserted and setled, sample parameters, set address and count for the given ram block and commence de-serialisation.
            --
            elsif RCV_RAM_SEQ = "110" then
                if RCV_RAM_TYPE = '0' then
                    RCV_RAM_COUNT   <= to_unsigned(128, 16);
                else
                    RCV_RAM_COUNT   <= RCV_TAPE_SIZE;
                end if;
                RCV_RAM_ADDR        <= std_logic_vector(to_unsigned(0, 16));
                HDR_RAM_WEN         <= '0';
                DATA_RAM_WEN        <= '0';
                RCV_RAM_CNT_CKSUM   <= '1';
                RCV_RAM_CALC_CKSUM  <= std_logic_vector(to_unsigned(0, 16));
                RCV_RAM_STATE       <= 0;

            -- If the DONE signal is low, then run the actual process, raising DONE when complete.                 
            elsif RCV_RAM_DONE = '0' then

                -- FSM to implement the receiption of data from MZ and storage in cache RAM>
                case(RCV_RAM_STATE) is
                    when 0 => 
                    when 1 =>
                        RCV_RAM_BITCNT <= 8;

                    -- Store 1 bit.
                    when 2 =>
                        if RCV_AVAIL = '1' then
                            -- Only store the data bits, 1st bit is just padding.
                            if RCV_RAM_BITCNT < 8 then
                                if RCV_BIT = '1' then
                                    RCV_RAM_CALC_CKSUM <= RCV_RAM_CALC_CKSUM + 1;
                                end if;
                                RCV_RAM_SR             <= RCV_RAM_SR(7 downto 0) & RCV_BIT;
                            end if;
                            RCV_RAM_STATE        <= 3;
                        end if;
                    when 3 =>
                        -- At end of transmission, load the full byte into RAM and make ready for next incoming byte.
                        if RCV_RAM_BITCNT = 0 then
                            RCV_RAM_COUNT    <= RCV_RAM_COUNT - 1;
                            RCV_RAM_STATE    <= 4;

                            -- For the header, extract the size of the tape data block and the load address.
                            --
                            if RCV_RAM_TYPE = '0' then
                                if RCV_RAM_ADDR = 18 then
                                    RCV_TAPE_SIZE(7 downto 0)  <= unsigned(RCV_RAM_SR(7 downto 0));
                                elsif RCV_RAM_ADDR = 19 then
                                    RCV_TAPE_SIZE(15 downto 8) <= unsigned(RCV_RAM_SR(7 downto 0));
                                end if;
                            end if;
                        else
                            RCV_RAM_BITCNT <= RCV_RAM_BITCNT - 1;
                            RCV_RAM_STATE  <= 2;
                        end if;
                    when 4 =>
                        if RCV_RAM_COUNT = 0 and RCV_RAM_CNT_CKSUM = '1' then
                            RCV_RAM_CHECKSUM(15 downto 8) <= RCV_RAM_SR(7 downto 0);
                            RCV_RAM_CNT_CKSUM  <= '0';
                            RCV_RAM_STATE      <= 1;
                        elsif RCV_RAM_COUNT = 0 and RCV_RAM_CNT_CKSUM = '0' then
                            RCV_RAM_CHECKSUM(7 downto 0) <= RCV_RAM_SR(7 downto 0);
                            RCV_RAM_STATE      <= 8;
                        else
                            RAM_DATAIN         <= RCV_RAM_SR(7 downto 0);
                            RCV_RAM_STATE      <= 5;
                        end if;
                    when 5 =>
                        -- Assert Write to load data into RAM.
                        if RCV_RAM_TYPE = '0' then
                            HDR_RAM_WEN        <= '1';
                        else
                            DATA_RAM_WEN       <= '1';
                        end if;
                        RCV_RAM_STATE          <= 6;
                    when 6 =>
                        -- Deassert write.
                        if RCV_RAM_TYPE = '0' then
                            HDR_RAM_WEN        <= '0';
                        else
                            DATA_RAM_WEN       <= '0';
                        end if;
                        RCV_RAM_STATE          <= 7;
                    when 7 =>
                        -- Once write transaction has completed, update the RAM address.
                        RCV_RAM_ADDR           <= RCV_RAM_ADDR + 1;
                        -- Receive the next byte which will be Checksum MSB.
                        RCV_RAM_STATE          <= 1;
                    when 8 =>
                        -- Compare checksums, raise SUCCESS flag if they match.
                        if RCV_RAM_CHECKSUM = RCV_RAM_CALC_CKSUM then
                            RCV_RAM_SUCCESS    <= '1';
                        end if;
                        RCV_RAM_STATE          <= 9;
                    when 9 =>
                        RCV_RAM_DONE           <= '1';
                    when others =>
                end case;
            end if;
        end if;
    end process;

    -- Process to read a sequence of identical bits. This is for GAP, Tape Marks and Pulse Sequences which seperate the
    -- meaningful data blocks in the tape stream.
    --
    -- RCV_PADDING_LOAD   =           = Load the counter and level and commence counting required number of bits.
    -- RCV_PADDING_LEVEL  =           = Level of the bit to detect, 0 = 0 (low), 1 = 1 (high). A bit received opposite to what we are detecting resets the count.
    -- RCV_PADDING_CNT    =           = Number of bits of RCV_PADDING_LEVEL to receive.
    -- CLKBUS(CKMEM)      =           = Base clock for encoding/decoding of pwm pulse.
    -- RCV_PADDING_DONE   =           = Status, 0 = counting or idle, 1 = done, number of required bits received.
    --
    process( RST, CLKBUS(CKMEM), RCV_PADDING_LOAD ) begin
        if RST = '1' then
            PADDING_CNT      <= 0;
            PADDING_LEVEL    <= '0';
            RCV_PADDING_DONE <= '0';
            RCV_PADDING_SEQ  <= "000";

        elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU) = '1' then
         
            -- Sample incoming LOAD and hold. Detect when a sample is required.
            RCV_PADDING_SEQ(1 downto 00) <= RCV_PADDING_SEQ(2 downto 1);
            RCV_PADDING_SEQ(2)           <= RCV_PADDING_LOAD;

            -- If load is stable, acknowldge by bringing DONE low and start the process.
            if RCV_PADDING_SEQ = "111" then
                RCV_PADDING_DONE    <= '0';

            -- When the load signal goes high, sample the count and level and prepare for counting.
            --
            elsif RCV_PADDING_SEQ = "110" then
                PADDING_CNT         <= RCV_PADDING_CNT;
                PADDING_LEVEL       <= RCV_PADDING_LEVEL;

            -- If DONE is low, we are processing.
            elsif RCV_PADDING_DONE = '0' then

                -- On activation of received data available, sample bit. If sampled bit is same as level, decrement counter otherwise reset counter.
                --
                if RCV_AVAIL = '1' then
                    if RCV_BIT = PADDING_LEVEL then
                        PADDING_CNT <= PADDING_CNT - 1;
                    else
                        PADDING_CNT <= RCV_PADDING_CNT;
                    end if;

                    -- When counter reaches zero, raise the DONE flag as operation is complete.
                    --
                    if PADDING_CNT = 0 then
                        RCV_PADDING_DONE <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Process to read a bit (PWM decode) from the MZ output.
    -- Basically we detect when the bit rises then start counting a fixed period of time. Once the period has
    -- elapsed, we sample the data and indicate it is available.
    --
    -- RCV_BIT       = TO TAPE = Decoded bit received from MZ.
    -- RCV_AVAIL     = TO TAPE = RCV_BIT = 1 received and valid.
    -- READBIT       = FROM MZ = Encoded bit transmitted by MZ.
    -- CLKBUS(CKMEM) =         = Base clock for encoding/decoding of pwm pulse.
    --
    -- Machine          Time uS   Description         N
    --  MZ80KCA/700     368.00    Reading point       736
    -- Machine          Time uS   Description         N-80K   N-700
    --  MZ80KCA/700     464.00    Long Pulse Start    1856    3248
    --                  494.00    Long Pulse End      1976    3458
    --                  240.00    Short Pulse Start   960     1680
    --                  264.00    Short Pulse End     1056    1848
    --                  368.00    Reading point.      1472    2576
    --  MZ80B           333.00    Long Pulse Start    2664
    --                  334.00    Long Pulse End      2672
    --                  166.75    Short Pulse Start   1334
    --                  166.00    Short Pulse End     1328
    --                  255.00    Reading point.      2040
    --
    process( RST, CLKBUS(CKMEM), READBIT) begin
        if RST = '1' then
            RCV_AVAIL    <= '0';
            RCV_COUNT    <= 1;
            RCV_BIT      <= '0';
            RCV_SEQ      <= "000";

        elsif CLKBUS(CKMEM)'event and CLKBUS(CKMEM) = '1' then

            -- Sample incoming bit and hold. Detect when a valid transmission starts.
            RCV_SEQ(1 downto 0) <= RCV_SEQ(2 downto 1);
            RCV_SEQ(2)          <= READBIT;

            -- A rising edge indicates the start of the data. We measure in from this edge the following
            -- amount of time, then sample the bit as the 'read' value.
            --
            if RCV_SEQ = "100" then
                -- Indicate data is being sampled, when = 1 data available.
                RCV_AVAIL    <= '0';

                -- Pulse periods for MZ80C type machines
                if CONFIG(MZ_80C) = '1' then
                    RCV_COUNT <= -1472;
                elsif CONFIG(MZ700) = '1' then
                    RCV_COUNT <= -2576;
                else
                    RCV_COUNT <= -2040;
                end if;

            elsif RCV_COUNT <= 0 then

                if RCV_AVAIL = '0' and RCV_COUNT = 0 then
                    RCV_BIT   <= READBIT;
                    RCV_AVAIL <= '1';
                else
                    RCV_COUNT  <= RCV_COUNT + 1;
                end if;

            end if;
        end if;
    end process;


    ----------------------------------------------------------------------------------------------------------------------
    -- Read From Tape logic (write to MZ).
    -- Definitions: Read  = Read from virtual tape (RAM).
    --              Write = Write into virtual tape (RAM).
    --              Xmit  = Transmit from CMT to MZ.
    --              Rcv   = Receive from MZ into CMT.
    --              Thus you read Read from tape and transmit to MZ, or Receive from MZ and write onto virtual tape.
    --              Playing is when the CMT is reading from tape, Recording is when the CMT is writing to tape.
    --
    -- This block concentrates all the logic required to deliver data from RAM (virtual tape) to the MZ.
    -- Viewed from the CMT, it is the transmission of data from tape to computer.
    ----------------------------------------------------------------------------------------------------------------------

    -- State machine to represent the tape drive READ mode (RAM -> MZ) using cache memory as the tape, which is populated by the HPS.
    --
    process( RST, CLKBUS(CKCPU), PLAYING ) begin
        -- For reset, hold machine in reset.
        if RST = '1' then 
            PLAY_READY_CLR                  <= '0';
            TAPE_READ_STATE                 <=  0;
            TAPE_READ_SEQ                   <= "000";
            XMIT_PADDING_LOAD               <= '0';
            XMIT_RAM_LOAD                   <= '0';
            XMIT_RAM_TYPE                   <= '0';

        elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU) = '1' then

             -- If not in playing mode, clear necessary signals and wait.
            if PLAYING = "000" then
                PLAY_READY_CLR              <= '0';

            -- If playing has been suspended, on 3rd clock determine the next state, setup and clear necessary signals.
            elsif PLAYING = "001" then
                XMIT_PADDING_LOAD           <= '0';
                XMIT_RAM_LOAD               <= '0';

                -- If the data block was received on first attempt, MZ will stop the motor, so skip the second block.
                if XMIT_RAM_TYPE = '0' and TAPE_READ_STATE > 6 and TAPE_READ_STATE < 15 then
                    TAPE_READ_STATE <= 14;
                else
                    PLAY_READY_CLR  <= '1';
                    TAPE_READ_STATE <= 15;
                end if;

            -- Change in play state, start fsm to play out the ram contents when the HPS upload has completed.
            elsif PLAYING = "110" then
                if TAPE_READ_STATE = 15 then
                    TAPE_READ_STATE         <= 0;
                    XMIT_RAM_TYPE           <= '0';
                    PLAY_READY_CLR          <= '0';
                end if;

            -- If playing, run the FSM.
            elsif PLAYING = "111" then
                
                -- Sample the done signal, when setup and stable, we can continue.
                TAPE_READ_SEQ(1 downto 0) <= TAPE_READ_SEQ(2 downto 1);
                TAPE_READ_SEQ(2)          <= (XMIT_PADDING_LOAD or XMIT_RAM_LOAD) and (XMIT_PADDING_DONE and XMIT_RAM_DONE);

                -- If a transmission has just been started and acknowledged by the DONE flag being reset, reset the activation strobe.
                --
                if TAPE_READ_SEQ(0) = '1' then
                    XMIT_PADDING_LOAD     <= '0';
                    XMIT_RAM_LOAD         <= '0';
                end if;

                -- If a transmission is in progress, run the FSM.
                --
                if XMIT_PADDING_LOAD = '0' and XMIT_RAM_LOAD = '0' then

                    -- Default is to move onto next state per clock cycle, unless modified by the state action.
                    TAPE_READ_STATE       <= TAPE_READ_STATE + 1;

                    -- Execute current state.
                    case TAPE_READ_STATE is

                    -- Section 1 - Header
                        --
                        when 0 => 
                            -- Header = 0, Data = 1
                            if XMIT_RAM_TYPE = '0' then
                                -- Setup to send a Long Gap.
                                if CONFIG(MZ_80C) = '1' or CONFIG(MZ700) = '1' then
                                    XMIT_PADDING_CNT1 <= 22000;
                                else
                                    XMIT_PADDING_CNT1 <= 10000;
                                end if;
                            else
                                if CONFIG(MZ_80C) = '1' or CONFIG(MZ700) = '1' then
                                    XMIT_PADDING_CNT1 <= 11000;
                                else
                                    XMIT_PADDING_CNT1 <= 10000;
                                end if;
                            end if;
                            XMIT_PADDING_LEVEL1    <= '0';                     -- Short Pulses
                            XMIT_PADDING_CNT2      <= 0;
                            XMIT_PADDING_LEVEL2    <= '0';
                            XMIT_PADDING_LOAD      <= '1';
    
                        when 1 =>
                            -- Wait for the padding transmission to complete.
                            if XMIT_PADDING_DONE = '0' then
                                TAPE_READ_STATE    <= 1;
                            end if;
    
                        when 2 =>
                            -- Header = 0, Data = 1
                            if XMIT_RAM_TYPE = '0' then
                                -- Setup to send a Long Tape Mark.
                                XMIT_PADDING_CNT1  <= 40;
                                XMIT_PADDING_CNT2  <= 40;
                            else
                                -- Setup to send a Short Tape Mark.
                                XMIT_PADDING_CNT1  <= 20;
                                XMIT_PADDING_CNT2  <= 20;
                            end if;
                            XMIT_PADDING_LEVEL1    <= '1';                     -- Long Pulses
                            XMIT_PADDING_LEVEL2    <= '0';                     -- Short Pulses
                            XMIT_PADDING_LOAD      <= '1';
    
                        when 3 =>
                            if XMIT_PADDING_DONE = '0' then
                                TAPE_READ_STATE    <= 3;
                            end if;
    
                        when 4 =>
                            -- Setup to send a Long Pulse.
                            XMIT_PADDING_CNT1      <= 1;
                            XMIT_PADDING_LEVEL1    <= '1';                     -- Long Pulse
                            XMIT_PADDING_CNT2      <= 0;
                            XMIT_PADDING_LEVEL2    <= '0';
                            XMIT_PADDING_LOAD      <= '1';
    
                        when 5 =>
                            if XMIT_PADDING_DONE = '0' then
                                TAPE_READ_STATE    <= 5;
                            end if;
    
                        -- Send the header and checksum for header.
                        when 6 =>
                            XMIT_RAM_LOAD          <= '1';                     -- Send First copy of header/data.
    
                        when 7 =>
                            if XMIT_RAM_DONE = '0' then                        -- If first copy successfully received, MZ will issue a motor stop.
                                TAPE_READ_STATE    <= 7;
                            end if;
    
                        when 8 =>
                            -- Setup to send 256 short pulse padding.
                            XMIT_PADDING_CNT1      <= 256;
                            XMIT_PADDING_LEVEL1    <= '0';
                            XMIT_PADDING_CNT2      <= 0;
                            XMIT_PADDING_LEVEL2    <= '0';
                            XMIT_PADDING_LOAD      <= '1';
    
                        when 9 =>
                            if XMIT_PADDING_DONE = '0' then
                                TAPE_READ_STATE    <= 9;
                            end if;
    
                        -- Resend the header/data as backup copy.
                        when 10 => 
                            XMIT_RAM_LOAD          <= '1';                     -- If required, send second copy of header/data.
    
                        when 11 =>
                            if XMIT_RAM_DONE = '0' then
                                TAPE_READ_STATE    <= 11;
                            end if;
    
                        when 12 =>
                            -- Setup to send a Long Pulse.
                            XMIT_PADDING_CNT1      <= 1;
                            XMIT_PADDING_LEVEL1    <= '1';
                            XMIT_PADDING_CNT2      <= 0;
                            XMIT_PADDING_LEVEL2    <= '0';
                            XMIT_PADDING_LOAD      <= '1';
    
                        when 13 =>
                            if XMIT_PADDING_DONE = '0' then
                                TAPE_READ_STATE    <= 13;
                            end if;
        
                        -- Switch to data if we have just transmitted the header, else terminate the process.
                        when 14 => 
                            if XMIT_RAM_TYPE = '0' then
                                XMIT_RAM_TYPE      <= '1';
                                TAPE_READ_STATE    <= 0;
                            else
                                PLAY_READY_CLR     <= '1';
                            end if;
    
                        -- Clear the Play Ready strobe and wait at this state until external actions reset the state.
                        when 15 =>
                            PLAY_READY_CLR         <= '0';
                            TAPE_READ_STATE        <= 15;
                    end case;
            end if;
        end if;
    end if;
end process;

-- Process to read the tape data blocks and checksum from RAM and transmit it to the MZ.
--
-- The ram is serialised and written to the MZ. A checksum (count of 1's) is calculated and transmitted 
-- immediately after the data.
-- XMIT_READ_DONE is high when the tape header and checksum transmission are complete.
-- Normally, XMIT_RAM_LOAD is asserted high and then wait until XMIT_DONE goes high, finally deassert XMIT_RAM_LOAD to low.
--
-- XMIT_LOAD_2        =           = Load signal to commence bit transmission.
-- XMIT_BIT_2         =           = Input into bit transmitter of bit value to be sent. 
-- XMIT_RAM_DONE      =           = Transmission of RAM block complete (= 1).
-- XMIT_RAM_TYPE      =           = 0 - Header, 1 = Data
-- XMIT_RAM_ADDR      =           = Address of the RAM to be transmitted. RAM can be header or data ram block
-- XMIT_RAM_COUNT     =           = Count of bytes to be sent, 0 = end.
-- XMIT_RAM_CHECKSUM  =           = Sum of number of 1's transmitted.
-- XMIT_RAM_STATE     =           = State machine current state.
-- CLKBUS(CKCPU)      =           = Base clock for encoding/decoding of pwm pulse.
--
process( RST, CLKBUS(CKCPU), XMIT_RAM_LOAD, XMIT_RAM_TYPE ) begin
    if RST = '1' then
         XMIT_RAM_DONE        <= '1';                                  -- Default state is DONE, data transmitted. Set to 0 when transmission in progress.
         XMIT_LOAD_2          <= '0';                                  -- LOAD signal to the bit writer. 1 = start bit transmission.
         --
         XMIT_BIT_2           <= '0';                                  -- Level of bit to transmit.
         XMIT_RAM_ADDR        <= std_logic_vector(to_unsigned(0, 16)); -- Address of cache memory for next byte.
         XMIT_RAM_COUNT       <= to_unsigned(0, 16);                   -- Count of bytes to transmit, excludes checksum.
         XMIT_RAM_CHKSUM_CNT  <= to_unsigned(0, 2);                    -- Count of checksum bytes to transmit.
         XMIT_RAM_CHECKSUM    <= std_logic_vector(to_unsigned(0, 16)); -- Calculated checksum, count of all 1's in data bytes.
         XMIT_RAM_STATE       <= 0;                                    -- FSM state.
         XMIT_RAM_SEQ         <= "000";

    elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU) = '1' then

        -- Sample load signal and hold. Shift right 3 bits, msb = latest value.
        XMIT_RAM_SEQ(1 downto 0) <= XMIT_RAM_SEQ(2 downto 1);
        XMIT_RAM_SEQ(2)          <= XMIT_RAM_LOAD;

        -- If load is stable, acknowledge by bringing DONE low and start process.
        if XMIT_RAM_SEQ = "111" then
            XMIT_RAM_DONE <= '0';

        -- When XMIT_RAM_LOAD is asserted and setled, sample parameters, set address and count for the given ram block and commence serialisation.
        --
        elsif XMIT_RAM_SEQ = "110" then
             if XMIT_RAM_TYPE = '0' then
                 XMIT_RAM_COUNT     <= to_unsigned(128, 16);
             else
                 XMIT_RAM_COUNT     <= XMIT_TAPE_SIZE;
             end if;
             XMIT_RAM_CHKSUM_CNT    <= to_unsigned(1, 2);
             XMIT_RAM_ADDR          <= std_logic_vector(to_unsigned(0, 16));
             XMIT_RAM_CHECKSUM      <= std_logic_vector(to_unsigned(0, 16));
             XMIT_RAM_STATE         <= 1;
             XMIT_LOAD_2            <= '0';

        -- If the DONE signal is low, then run the actual process, raising DONE when complete.
        elsif XMIT_RAM_DONE = '0' then

            -- Simple FSM to implement transmission of RAM contents according to MZ Tape Protocol.
            case(XMIT_RAM_STATE) is
                when 0 => 
                when 1 =>
                    if XMIT_RAM_COUNT = 0 and XMIT_RAM_CHKSUM_CNT = 1 then
                        XMIT_RAM_SR <= '1' & XMIT_RAM_CHECKSUM(15 downto 8);
                    elsif XMIT_RAM_COUNT = 0 and XMIT_RAM_CHKSUM_CNT = 0 then
                        XMIT_RAM_SR <= '1' & XMIT_RAM_CHECKSUM(7 downto 0);
                    else
                        -- Extract the size of the tape data block and the load address if this is the header.
                        --
                        if XMIT_RAM_TYPE = '0' then
                            if XMIT_RAM_ADDR = 18 then 
                                XMIT_TAPE_SIZE(7 downto 0)  <= unsigned(HDR_RAM_DATAOUT);
                            elsif XMIT_RAM_ADDR = 19 then
                                XMIT_TAPE_SIZE(15 downto 8) <= unsigned(HDR_RAM_DATAOUT);
                            end if;
                            XMIT_RAM_SR <= '1' & HDR_RAM_DATAOUT;
                        else
                            XMIT_RAM_SR <= '1' & DATA_RAM_DATAOUT;
                            end if;
                    end if;
                    XMIT_RAM_BITCNT    <= 8;      -- 9 bits to transmit, pre 1 + 8 bits of data byte.
                    XMIT_RAM_STATE     <= 2;
                when 2 =>
                    XMIT_BIT_2         <= XMIT_RAM_SR(8);
                    XMIT_LOAD_2        <= '1';
                    if XMIT_RAM_SR(8) = '1' and XMIT_RAM_BITCNT < 8 and XMIT_RAM_COUNT > 0 then
                        XMIT_RAM_CHECKSUM  <= XMIT_RAM_CHECKSUM + 1;
                    end if;
                    XMIT_RAM_SR        <= XMIT_RAM_SR(7 downto 0) & '0';
                    XMIT_RAM_STATE     <= 3;
                when 3 => 
                    -- As we are using the same clock freq, need to wait until XMIT_DONE is set to 0, indicating transmission in progress.
                    if XMIT_LOAD_2 = '1' and XMIT_DONE = '0' then
                        XMIT_LOAD_2    <= '0';
                        XMIT_RAM_STATE <= 4;
                    end if;
                when 4 =>
                    -- Wait until the DONE signal is asserted before continuing.
                    if XMIT_DONE = '1' then
                        XMIT_RAM_STATE <= 5;
                    end if;
                when 5 =>
                    XMIT_BIT_2         <= '0';                   -- Reset bit..
                    if XMIT_RAM_BITCNT = 0 then
                        if XMIT_RAM_COUNT = 0 and XMIT_RAM_CHKSUM_CNT = 0 then
                            XMIT_RAM_STATE <= 6;
                        else
                            if XMIT_RAM_COUNT > 0 then
                                XMIT_RAM_COUNT <= XMIT_RAM_COUNT - 1;
                                XMIT_RAM_ADDR  <= XMIT_RAM_ADDR + 1;
                            elsif XMIT_RAM_COUNT = 0 and XMIT_RAM_CHKSUM_CNT > 0 then
                                XMIT_RAM_CHKSUM_CNT <= XMIT_RAM_CHKSUM_CNT - 1;
                            end if;
                            XMIT_RAM_STATE <= 1;
                        end if;
                    else
                        XMIT_RAM_BITCNT <= XMIT_RAM_BITCNT - 1;
                        XMIT_RAM_STATE  <= 2;
                    end if;
                when others => XMIT_RAM_DONE <= '1';
            end case;
        end if;
    end if;
end process;

-- Process to send padding from CMT to MZ.
--
-- This process transmits a set of pulses to represent the Gap, Tape Mark, Short Seperator or Long pulse of an MZ tape
-- message. XMIT_PADDING_LOAD when high starts the generation, XMIT_PADDING_DONE is set high when generation completes.
-- Normally, the invoker process sets up the number of bits and level in the parameters:

-- XMIT_PADDING_CNT1   = Internal = If > 0, then transmit this number of bits first.
-- XMIT PADDING_LEVEL1 = Internal = Level of the bit to transmit CNT1 times.
-- XMIT PADDING_CNT2   = Internal = If > 0, then tramsit this number of bits second.
-- XMIT_PADDING_LEVEL2 = Internal = Level of the bit to transmit CNT2 times.
--
-- After completion of transmission, the Done signal is asserted high:
-- XMIT_PADDING_DONE   = Internal = 0 when transmission in progress, 1 when transmission completed.
--
-- Clocks:
-- CLKBUS(CKCPU)       = Internal = Base clock for encoding/decoding of pwm pulse.
--
process( RST, CLKBUS(CKCPU), XMIT_PADDING_LOAD ) begin
    if RST = '1' then
         XMIT_PADDING_DONE    <= '1';          -- PADDING transmission complete signal, DONE = 1 when complete, 0 during transmit.
         XMIT_LOAD_1          <= '0';          -- LOAD signal to bit transmitted, loads required bit when = 1 for 1 cycle. 
         PADDING_CNT1         <= 0;
         PADDING_LEVEL1       <= '0';
         PADDING_CNT2         <= 0;
         PADDING_LEVEL2       <= '0';
         PADDING_SEQ          <= "000";

    elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU) = '1' then

        -- Sample load signal and hold. Shift right 3 bits, msb = latest value.
        PADDING_SEQ(1 downto 0) <= PADDING_SEQ(2 downto 1);
        PADDING_SEQ(2)          <= XMIT_PADDING_LOAD;

        -- If LOAD active for 3 periods, bring DONE low to acknowledge LOAD signal and start processing.
        --
        if PADDING_SEQ = "111" then
            XMIT_PADDING_DONE <= '0';
        end if;

        -- If LOAD active for 2 periods, sample and store the provided parameters.
        --
        if PADDING_SEQ = "110" then
            -- Sample the parameters XMIT_PADDING_CNT1, XMIT_PADDING_CNT2, XMIT_PADDING_LEVEL1, XMIT_PADDING_LEVEL2 and
            -- write out the number of Level1 @ Cnt1, Level2 @ Cnt2 bits.
            PADDING_CNT1      <= XMIT_PADDING_CNT1;
            PADDING_LEVEL1    <= XMIT_PADDING_LEVEL1;
            PADDING_CNT2      <= XMIT_PADDING_CNT2;
            PADDING_LEVEL2    <= XMIT_PADDING_LEVEL2;
            XMIT_LOAD_1       <= '0';
        end if;

        -- If DONE is low, we are processing.
        if XMIT_PADDING_DONE = '0' then

            -- Reset strobe when acknowledged by XMIT_DONE going low.
            if XMIT_LOAD_1 = '1' and XMIT_DONE = '0' then
                XMIT_LOAD_1 <= '0';

            -- If we arent loading a padding sequence, then we are either waiting for a Done signal 
            -- or need to commence a new transmission.
            --
            elsif XMIT_LOAD_1 = '0' then

                -- If transmission buffer empty, setup next bit to transmit.
                --
                if XMIT_DONE = '1' then

                    -- Set the completion flag if the counters expire or PLAYING is disabled.
                    --.
                    if PLAYING = "000" or (PADDING_CNT1 = 0 and PADDING_CNT2 = 0) then
                        -- Final wait for done on the last bit before setting our done flag.
                        XMIT_PADDING_DONE  <= '1';

                    -- First, transmit the nummber of Counter 1 bits defined in Level 1.
                    elsif PADDING_CNT1 > 0 then
                        XMIT_BIT_1         <= PADDING_LEVEL1;    -- Set the mux input bit according to input level, 
                        XMIT_LOAD_1        <= '1';               -- Set the mux input to commence xmit.
                        PADDING_CNT1       <= PADDING_CNT1 - 1;  -- Decrement counter as this bit is now being transmitted.
    
                    -- Then transmit the number of Counter 2 bits defined in Level 2.
                    elsif PADDING_CNT2 > 0 then
                        XMIT_BIT_1         <= PADDING_LEVEL2;   
                        XMIT_LOAD_1        <= '1';
                        PADDING_CNT2       <= PADDING_CNT2 - 1;
                    end if;
                end if;
            end if;
        end if;
    end if;
end process;

-- Process to write a bit (PWM encode) to the MZ input.
-- The timings are as follows with a default SCLK of 2MHz. For faster operation, MZ clock is boosted
-- and the SCLK is also boosted on a 1:1 relationship, thus the dividers are halved per boost.
--
-- XMIT_LOAD_1   = FROM TAPE = When high, Bit available on XMIT_BIT_1 to encode and transmit to MZ.
-- XMIT_LOAD_2   = FROM TAPE = When high, Bit available on XMIT_BIT_2 to encode and transmit to MZ.
-- XMIT_DONE     = TO TAPE   = When high, transmission of bit complete. Resets to 0 on active XMIT_LOAD signal.
-- WRITEBIT      = FROM MZ   = Encoded bit tranmitted to MZ.
-- CLKBUS(CKCPU) =           = Base clock for encoding/decoding of pwm pulse.
--
-- Machine          Time uS   Description         N-80K(CKMEM)   N-80K(CKCPU)  N-700(CKCPU)   N-700(CKMEM)
--  MZ80KCA/700     464.00    Long Pulse Start    1856            928          1624           3248
--                  494.00    Long Pulse End      1976            988          1729           3458
--                  240.00    Short Pulse Start    960            480           840           1680
--                  264.00    Short Pulse End     1056            528           924           1848
--                  368.00    Read point.         1472            736          1288           2576
--  MZ80B           333.00    Long Pulse Start    2664           1332
--                  334.00    Long Pulse End      2672           1336
--                  166.75    Short Pulse Start   1334            667
--                  166.00    Short Pulse End     1328            664
--                  255.00    Read point.         2040           1020
--
process( RST, CLKBUS(CKCPU), XMIT_LOAD_1, XMIT_LOAD_2 ) begin
    -- When RESET is high, hold in reset mode.
    if RST = '1' then
        XMIT_DONE      <= '1';                    -- Completion signal, 0 when transmitting, 1 when done.
        WRITEBIT       <= '0';                    -- Bit facing towards MZ input.
        XMIT_LIMIT     <= 0;                      -- End of pulse.
        XMIT_COUNT     <= 0;                      -- Pulse start, bit set to 1, reset to 0 on counter = 0
        XMIT_SEQ       <= "000";

    elsif CLKBUS(CKCPU)'event and CLKBUS(CKCPU)='1' then

        -- Sample load signal and hold. Shift right 3 bits, msb = latest value.
        XMIT_SEQ(1 downto 0) <= XMIT_SEQ(2 downto 1);
        XMIT_SEQ(2)          <= XMIT_LOAD_1 or XMIT_LOAD_2;

        -- If load is stable, acknowledge by bringing DONE low and start process.
        if XMIT_SEQ = "111" then
            XMIT_DONE    <= '0';
            WRITEBIT     <= '1';

        -- Store run values on 2nd clock cycle of LOAD being active.
        elsif XMIT_SEQ = "110" then

            -- Pulse periods for MZ80C type machines
            if CONFIG(MZ_KC) = '1' or CONFIG(MZ_A) = '1' then
                if (XMIT_LOAD_1 = '1' and XMIT_BIT_1 = '1') or (XMIT_LOAD_2 = '1' and XMIT_BIT_2 = '1') then
                    XMIT_LIMIT <=  988;     --  1976;
                    XMIT_COUNT <= -928;     -- -1856;
                else
                    XMIT_LIMIT <=  528;     --  1056;
                    XMIT_COUNT <= -480;     --  -960;
                end if;
            elsif CONFIG(MZ700) = '1' then
            -- Pulse periods for MZ700 type machines
                if (XMIT_LOAD_1 = '1' and XMIT_BIT_1 = '1') or (XMIT_LOAD_2 = '1' and XMIT_BIT_2 = '1') then
                    XMIT_LIMIT <= 1729;     --  3458;
                    XMIT_COUNT <= -1624;    -- -3248;
                else
                    XMIT_LIMIT <=  924;     --  1848;
                    XMIT_COUNT <= -840;     -- -1680;
                end if;
            else
            -- Pulse periods for MZ80B type machines
                if (XMIT_LOAD_1 = '1' and XMIT_BIT_1 = '1') or (XMIT_LOAD_2 = '1' and XMIT_BIT_2 = '1') then
                    XMIT_LIMIT <=  1336;    --  2672;
                    XMIT_COUNT <= -1332;    -- -2664;
                else
                    XMIT_LIMIT <=  664;     --  1328;
                    XMIT_COUNT <= -667;     -- -1334;
                end if;
            end if;

        -- On expiration of timer, signal completion.
        elsif XMIT_COUNT = XMIT_LIMIT then
            XMIT_DONE      <= '1';
         
        -- If the counter is running, format the output pulse.
        elsif XMIT_COUNT /= XMIT_LIMIT then
            -- At zero, we have elapsed the correct high period for the write bit, now bring it low for the remaining period.
            if XMIT_COUNT = 0 then
                WRITEBIT   <= '0';
            end if;
            XMIT_COUNT <= XMIT_COUNT + 1;
        end if;
    end if;
end process;

DEBUG_STATUS_LEDS(0)  <= WRITEBIT;
DEBUG_STATUS_LEDS(1)  <= XMIT_DONE;
DEBUG_STATUS_LEDS(2)  <= XMIT_LOAD_1;
DEBUG_STATUS_LEDS(3)  <= XMIT_LOAD_2;
DEBUG_STATUS_LEDS(4)  <= XMIT_PADDING_LOAD;
DEBUG_STATUS_LEDS(5)  <= XMIT_PADDING_DONE;
DEBUG_STATUS_LEDS(6)  <= XMIT_RAM_LOAD;
DEBUG_STATUS_LEDS(7)  <= XMIT_RAM_DONE;

DEBUG_STATUS_LEDS(8)  <= PLAY_READY;
DEBUG_STATUS_LEDS(9)  <= PLAY_READY_CLR;
DEBUG_STATUS_LEDS(10) <= PLAYING(2);
DEBUG_STATUS_LEDS(11) <= PLAYING(1);
DEBUG_STATUS_LEDS(12) <= PLAYING(0);
DEBUG_STATUS_LEDS(13) <= RECORDING(2);
DEBUG_STATUS_LEDS(14) <= RECORDING(1);
DEBUG_STATUS_LEDS(15) <= RECORDING(0);

DEBUG_STATUS_LEDS(16) <= READBIT;
DEBUG_STATUS_LEDS(17) <= RCV_AVAIL;
DEBUG_STATUS_LEDS(18) <= RECORD_READY;
DEBUG_STATUS_LEDS(19) <= RCV_RAM_TYPE;
DEBUG_STATUS_LEDS(20) <= RCV_PADDING_LOAD;
DEBUG_STATUS_LEDS(21) <= RCV_PADDING_DONE;
DEBUG_STATUS_LEDS(22) <= RCV_RAM_LOAD;
DEBUG_STATUS_LEDS(23) <= RCV_RAM_DONE;
--DEBUG_STATUS_LEDS(19 downto 16) <= std_logic_vector(to_unsigned(TAPE_READ_STATE, 4));
--DEBUG_STATUS_LEDS(22 downto 20) <= TAPE_READ_SEQ; --PADDING_SEQ;
--DEBUG_STATUS_LEDS(23 downto 19) <= XMIT_RAM_SEQ;

end RTL;
