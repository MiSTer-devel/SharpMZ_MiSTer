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
--                  For writing of data from the Sharp to Tape, the data is stored in ram and the
--                  HPS or other controller, when it gets the completed signal, can read out the ram
--                  and store the data onto a local filesystem.
-- Credits:         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         July 2018    - Initial module written and playback mode tested and debugged.
--                  August 2018  - Record mode written but not yet debugged/completed.
--                  October 2018 - Added APSS for MZ80B emulation.
--                                 Major rework of read (MZ Write) logic.
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
use pkgs.config_pkg.all;
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
        CMT_BUS_OUT          : out std_logic_vector(CMT_BUS_OUT_WIDTH);
        CMT_BUS_IN           : in  std_logic_vector(CMT_BUS_IN_WIDTH);

        -- HPS Interface
        IOCTL_DOWNLOAD       : in  std_logic;                            -- HPS Downloading to FPGA.
        IOCTL_UPLOAD         : in  std_logic;                            -- HPS Uploading from FPGA.
        IOCTL_CLK            : in  std_logic;                            -- HPS I/O Clock.
        IOCTL_WR             : in  std_logic;                            -- HPS Write Enable to FPGA.
        IOCTL_RD             : in  std_logic;                            -- HPS Read Enable from FPGA.
        IOCTL_ADDR           : in  std_logic_vector(24 downto 0);        -- HPS Address in FPGA to write into.
        IOCTL_DOUT           : in  std_logic_vector(31 downto 0);        -- HPS Data to be written into FPGA.
        IOCTL_DIN            : out std_logic_vector(31 downto 0);        -- HPS Data to be read into HPS.

        -- Debug Status Leds
        DEBUG_STATUS_LEDS    : out std_logic_vector(31 downto 0)         -- 32 leds to display cmt internal status.
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
signal IOCTL_CS_ASCII_n      :     std_logic;
signal IOCTL_TAPEHDR_WEN     :     std_logic;
signal IOCTL_TAPEDATA_WEN    :     std_logic;
signal IOCTL_ASCII_WEN       :     std_logic;
signal IOCTL_DIN_HDR         :     std_logic_vector(7 downto 0);
signal IOCTL_DIN_DATA        :     std_logic_vector(7 downto 0);
signal IOCTL_DIN_ASCII       :     std_logic_vector(7 downto 0);
-- CMT Control signals.
signal CMT_BUS_OUTi          :     std_logic_vector(CMT_BUS_OUT_WIDTH);      -- CMT bus output.
signal BUTTONS_LAST          :     std_logic_vector(1 downto 0);             -- Virtual buttons last sample, used to detect changes.
signal PLAY_READY_SET_CNT    :     integer range 0 to 32000000   := 0;       -- 1 second timer from last cache upload to PLAY_READY being set.
signal PLAY_READY_CLR_CNT    :     unsigned(21 downto 0);                    -- 2 second timer from motor being stopped to PLAY_READY being cleared.
signal PLAY_READY            :     std_logic;                                -- Cache loaded, playback ready to commence.
signal PLAY_READY_CLR        :     std_logic;                                -- Clear PLAY_READY signal.
signal PLAY_BUTTON           :     std_logic;                                -- Virtual Play button.
signal PLAYING               :     std_logic_vector(2 downto 0);             -- Playing state, 3 cycle, 0 = inactive, 1 = active, msb = most recent.
signal RECORD_READY          :     std_logic;                                -- Record buffer full (data received from MZ). Active = 1
signal RECORD_READY_SET      :     std_logic;                                -- Trigger to activate the RECORD_READY signal.
signal RECORD_READY_SEQ      :     std_logic_vector(1 downto 0);             -- Setup and hold sequencer.
signal RECORD_BUTTON         :     std_logic;                                -- Virtual Record button.
signal RECORDING             :     std_logic;                                -- Signal indicating a Record is underway, Active = 1.
signal RECSEQ                :     std_logic_vector(2 downto 0);             -- Signal, 3 cycles, indicating 
signal MOTOR_TOGGLE          :     std_logic_vector(1 downto 0);             -- Signal indicating if the MZ wants to start or toggle the motor.
signal APSS_TIMER_CNT        :     unsigned(20 downto 0);                    -- 1 second virtual APSS SEEK time.
signal WRITEBIT              :     std_logic;                                -- Tape data signal sent to the MZ (for playback).
signal READBIT               :     std_logic;                                -- Tape data signal eminating from the MZ (for recording).
signal TAPE_MOTOR_ON_n       :     std_logic;                                -- Virtual motor signal, tape motor running = 0.
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
signal XMIT_ASCII_RAM_ADDR   :     std_logic_vector(8 downto 0);             -- Address for the Sharp Ascii to Ascii conversion table.
signal XMIT_RAM_COUNT        :     unsigned(15 downto 0);
signal XMIT_RAM_CHKSUM_CNT   :     unsigned(1 downto 0);
signal XMIT_RAM_CHECKSUM     :     std_logic_vector(15 downto 0);
signal XMIT_RAM_TYPE         :     std_logic;
signal XMIT_RAM_STATE        :     integer range 0 to 7 := 0;
signal XMIT_RAM_SR           :     std_logic_vector(8 downto 0);
signal XMIT_RAM_BIT_CNT      :     integer range 0 to 8 := 0;
signal XMIT_TAPE_SIZE        :     unsigned(15 downto 0);
-- RAM control signals.
signal RAM_ADDR              :     std_logic_vector(15 downto 0);            -- Multiplexed (Header, Data) RAM address
signal RAM_DATAIN            :     std_logic_vector(7 downto 0);             -- Multiplexed RAM data in.
signal HDR_RAM_DATAOUT       :     std_logic_vector(7 downto 0);             -- Header RAM data output.
signal HDR_RAM_WEN           :     std_logic;                                -- Header RAM data write enable.
signal DATA_RAM_DATAOUT      :     std_logic_vector(7 downto 0);             -- Data RAM data output.
signal DATA_RAM_WEN          :     std_logic;                                -- Data RAM data write enable.
signal ASCII_RAM_ADDR        :     std_logic_vector(8 downto 0);             -- Multiplexed RAM address for the Ascii conversion table.
signal ASCII_RAM_DATAOUT     :     std_logic_vector(7 downto 0);             -- Sharp Ascii to Ascii conversion output.
--
-- Main process Finite State Machine variables.
signal TAPE_READ_STATE       :     integer range 0 to 15       := 0;
signal TAPE_READ_SEQ         :     std_logic_vector(2 downto 0);             -- Setup and hold sequencer.
-- Receiver (for recording) signals.
signal RCV_RAM_SUCCESS       :     std_logic;
signal RCV_RAM_ADDR          :     std_logic_vector(15 downto 0);
signal RCV_ASCII_RAM_ADDR    :     std_logic_vector(8 downto 0);             -- Address for the Sharp Ascii to Ascii conversion table.
signal RCV_RAM_STATE         :     integer range 0 to 8 := 0;
signal RCV_RAM_CHECKSUM      :     std_logic_vector(15 downto 0);
signal RCV_TAPE_SIZE         :     std_logic_vector(15 downto 0);
signal RCV_RAM_TRY           :     integer range 0 to 1;
signal RCV_BYTE_AVAIL        :     std_logic;
signal RCV_BYTE_CLR          :     std_logic;
signal RCV_BYTE              :     std_logic_vector(7 downto 0);
signal RCV_LOAD              :     std_logic;
signal RCV_DONE              :     std_logic;
signal RCV_CLR               :     std_logic;
signal RCV_ERROR             :     std_logic;
signal RCV_STATE             :     integer range 0 to 9;
signal RCV_BLOCK             :     integer range 0 to 1;
signal RCV_TYPE              :     integer range 0 to 1;
signal RCV_TMH_CNT           :     integer range 0 to 40;
signal RCV_TML_CNT           :     integer range 0 to 40;
signal RCV_DATASIZE          :     unsigned(15 downto 0);
signal RCV_SR                :     std_logic_vector(7 downto 0);
signal RCV_CHECKSUM          :     std_logic_vector(15 downto 0);
signal RCV_SEQ               :     std_logic_vector(1 downto 0);             -- Setup and hold sequencer.
signal RCV_CNT               :     unsigned(15 downto 0); 
signal TMH_CNT               :     integer range 0 to 40;
signal TML_CNT               :     integer range 0 to 40;
signal DATA_CNT              :     unsigned(15 downto 0);
signal SPC_CNT               :     integer range 0 to 256;
signal BIT_CNT               :     unsigned(2 downto 0);

--
begin
    -- Wired signals between this CMT unit and the MZ/MCtrl bus.
    --
    CMT_BUS_OUTi(pkgs.mctrl_pkg.WRITEBIT)     <= WRITEBIT;                    -- Write a bit to the MZ PIO.
    CMT_BUS_OUTi(pkgs.mctrl_pkg.SENSE)        <= not TAPE_MOTOR_ON_n;         -- Indiate current state of Motor, 0 if not running, 1 if running.
    CMT_BUS_OUTi(pkgs.mctrl_pkg.ACTIVE)       <= PLAYING(2) or RECORDING; 
    CMT_BUS_OUTi(pkgs.mctrl_pkg.PLAY_READY)   <= PLAY_READY;
    CMT_BUS_OUTi(pkgs.mctrl_pkg.PLAYING)      <= PLAYING(2);
    CMT_BUS_OUTi(pkgs.mctrl_pkg.RECORD_READY) <= RECORD_READY;
    CMT_BUS_OUTi(pkgs.mctrl_pkg.RECORDING)    <= RECORDING;
    --
    READBIT                                   <= CMT_BUS_IN(pkgs.mctrl_pkg.READBIT); -- Read a bit from the MZ PIO.
    MOTOR_TOGGLE(1)                           <= CMT_BUS_IN(PLAY);
    CMT_BUS_OUT                               <= CMT_BUS_OUTi;

    -- Mux Signals from different sources.
    RAM_ADDR                                  <= RCV_RAM_ADDR                when RECORDING = '1'
                                                 else
                                                 XMIT_RAM_ADDR;
    ASCII_RAM_ADDR                            <= RCV_ASCII_RAM_ADDR          when RECORDING = '1'
                                                 else
                                                 XMIT_ASCII_RAM_ADDR;
    IOCTL_CS_HDR_n                            <= '0'                         when IOCTL_ADDR(24 downto 16) = "001000000"
                                                 else '1';
    IOCTL_CS_DATA_n                           <= '0'                         when IOCTL_ADDR(24 downto 16) = "001000001"
                                                 else '1';
    IOCTL_CS_ASCII_n                          <= '0'                         when IOCTL_ADDR(24 downto 16) = "001000010"
                                                 else '1';
    IOCTL_TAPEHDR_WEN                         <= '1'                         when IOCTL_CS_HDR_n  = '0'   and IOCTL_WR = '1'
                                                 else '0';
    IOCTL_TAPEDATA_WEN                        <= '1'                         when IOCTL_CS_DATA_n = '0'   and IOCTL_WR = '1'
                                                 else '0';
    IOCTL_ASCII_WEN                           <= '1'                         when IOCTL_CS_ASCII_n  = '0' and IOCTL_WR = '1'
                                                 else '0';
    IOCTL_DIN                                 <= X"000000" & IOCTL_DIN_HDR   when IOCTL_CS_HDR_n  = '0'
                                                 else
                                                 X"000000" & IOCTL_DIN_DATA  when IOCTL_CS_DATA_n = '0'
                                                 else
                                                 X"000000" & IOCTL_DIN_ASCII when IOCTL_CS_ASCII_n = '0'
                                                 else
                                                 (others => '0');

    -- Header Cache RAM.
    -- Storage of the tape header for play and record operations.
    TAPEHDR : dpram
    GENERIC MAP (
        init_file            => null,
        widthad_a            => 7,
        width_a              => 8,
        widthad_b            => 7,
        width_b              => 8
    )
    PORT MAP (
        clock_a              => CLKBUS(CKMASTER), --CLKBUS(CKMEM),
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

    -- Data Cache RAM.
    -- Storage of the tape data for play and record operations.
    -- Maximum size of 64K as this is the limit that can be accommodated by the MZ software.
    TAPEDATA : dpram
    GENERIC MAP (
        init_file            => null,
        widthad_a            => 16,
        width_a              => 8,
        widthad_b            => 16,
        width_b              => 8
    )
    PORT MAP (
        clock_a              => CLKBUS(CKMASTER), --CLKBUS(CKMEM),
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

    -- Sharp Ascii <-> Ascii conversion table.
    -- Filenames are generally in Sharp Ascii format which is incompatible with modern
    -- systems, ie. name of files on a file system, so conversion is needed in both directions.
    ADCNV : dpram
    GENERIC MAP (
        init_file            => "./software/mif/ascii_conv.mif",
        widthad_a            => 9,
        width_a              => 8,
        widthad_b            => 9,
        width_b              => 8
    )
    PORT MAP (
        clock_a              => CLKBUS(CKMASTER), --CLKBUS(CKMEM),
        clocken_a            => '1',
        address_a            => ASCII_RAM_ADDR(8 downto 0),
        data_a               => (others => '0'),
        wren_a               => '0',
        q_a                  => ASCII_RAM_DATAOUT,

        clock_b              => IOCTL_CLK,
        address_b            => IOCTL_ADDR(8 downto 0),
        data_b               => IOCTL_DOUT(7 downto 0),
        wren_b               => IOCTL_ASCII_WEN,
        q_b                  => IOCTL_DIN_ASCII
    );


    -- MZ80B/2000 control signals.
    --
    -- A0 MOTORON     Activates reel motor
    -- A1 DIRECTION   Prepares for FF state (prepares for REW with L)
    -- A2 PLAY        plays cassette
    -- A3 STOP        Stops casette operation
    -- B4 WRITEREADY  Pawl applied to prohibit writing casette tape
    -- B5 TAPEREADY   Indicates tape is set in the casette deck
    -- B6 WRITEBIT    Input terminal for casette data
    -- B7 BREAKDETECT Detects break key during casette play
    -- C4 EJECT       Starts eject operation
    -- C5 SEEK        Latches ready state for FF and REW
    -- C6 WRITEENABLE Sets head amp to READ state (WRITE with L)
    -- C7 READBIT     Outpus data to be written into casette
    --
    -- DIRECTION clocked by SEEK, if DIRECTION = L when SEEK pulses high, then tape rewinds on activation of MOTORON.
    -- If DIRECTION is high, then tape will fast forward. MOTORON, when pulsed high, activates the motor to go forward/backward.
    -- PLAY pulsed high activates the play motor.which cancels a FF/REW event.
    -- STOP when High, stops the Play/FF/REW events.
    -- TAPEREADY when high indicates tape drive present and ready.
    -- EJECT when Low, ejects the tape.
    -- WRITEENABLE when Low enables record, otherwise when High enables play.
    -- READBIT is the data to write to tape.
    -- WRITEBIT is the data read from tape.
    -- WRITEREADY when Low blocks recording.

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

    -----------------------------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------------------- CMT control ---------------------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------------------------

    -- Process to determine CMT state according to inputs. ie. If we are STOPPED, PLAYING or RECORDING.
    -- This is determined by the input switches in CONFIG(BUTTOS), 00 = Off, 01 = Play, 02 = Record and 03 = Auto.
    -- Auto mode indicates the CMT logic has to determine wether it is PLAYING or RECORDING. The default is PLAYING
    -- but if a bit is received from the MZ then we switch to RECORDING until a full tape dump has been received.
    --
    process( RST, CLKBUS(CKMASTER), CONFIG(BUTTONS), MOTOR_TOGGLE, CMT_BUS_IN) begin
        if RST='1' then
            TAPE_MOTOR_ON_n                         <= '1';
            PLAY_BUTTON                             <= '0';
            RECORD_BUTTON                           <= '0';
            BUTTONS_LAST                            <= "00";
            PLAYING                                 <= "000";
            RECORDING                               <= '0';
            MOTOR_TOGGLE(0)                         <= '0';
            APSS_TIMER_CNT                          <= (others => '0');
            CMT_BUS_OUTi(APSS_SEEK)                 <= '0';
            CMT_BUS_OUTi(APSS_DIR)                  <= '0';
            CMT_BUS_OUTi(APSS_EJECT)                <= '0';
            CMT_BUS_OUTi(APSS_PLAY)                 <= '0';
            CMT_BUS_OUTi(APSS_STOP)                 <= '1';

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1' then

            if CLKBUS(CKENCPU) = '1' then

                -- Store last state so we detect change.
                BUTTONS_LAST                            <= CONFIG(BUTTONS);
                MOTOR_TOGGLE(0)                         <= MOTOR_TOGGLE(1);
    
                -- Store last state so we can detect a switch to recording or play mode.
                PLAYING(1 downto 0)                     <= PLAYING(2 downto 1);
    
                -- The MZ80C series use a manual cassette deck with motor automation, so we
                -- need to simulate buttons and the states therein.
                --
                if CONFIG(MZ_80C) = '1' then
    
                    -- Process the buttons and adapt signals accordingly.
                    --
                    if BUTTONS_LAST /= CONFIG(BUTTONS) then
                        case CONFIG(BUTTONS) is
                            when "00" => -- Off
                                PLAY_BUTTON             <= '0';
                                RECORD_BUTTON           <= '0';
                                TAPE_MOTOR_ON_n         <= '1';
                                CMT_BUS_OUTi(TAPEREADY) <= '1';                         -- Indicates tape ejected.
                                CMT_BUS_OUTi(WRITEREADY)<= '1';                         -- Indicates write mechanism disabled.
                            when "10" => -- Record
                                PLAY_BUTTON             <= '0';
                                RECORD_BUTTON           <= '1';
                                TAPE_MOTOR_ON_n         <= '0';
                                CMT_BUS_OUTi(TAPEREADY) <= '0';                         -- Indicates tape loaded, active Low.
                                CMT_BUS_OUTi(WRITEREADY)<= '1';                         -- Indicates write mechanism enabled.
                            when "01"|"11" => -- Play/Auto
                                -- Assume playback mode for Auto unless activity is detected from the MZ,
                                -- in which case switch to Recording.
                                PLAY_BUTTON             <= '1';
                                RECORD_BUTTON           <= '0';
                                TAPE_MOTOR_ON_n         <= '0';
                                CMT_BUS_OUTi(TAPEREADY) <= '0';                         -- Indicates tape loaded, active Low.
                                CMT_BUS_OUTi(WRITEREADY)<= '0';                         -- Indicates write mechanism disabled.
                        end case;
                    end if;
    
                    -- Once a recording becomes available to save, disable recording state.
                    --
                    if RECORD_READY = '1' then
                        RECORDING                       <= '0';
                    end if;
        
                    -- If in auto mode and data starts being received from the MZ, enter record mode. Once record
                    -- mode completes, switch back to play mode.
                    --
                    if CONFIG(BUTTONS) = "11" then
                        if RCV_SEQ = "11" or RECORDING = '1' then
                            PLAY_BUTTON                 <= '0';
                            RECORD_BUTTON               <= '1';
                            CMT_BUS_OUTi(WRITEREADY)    <= '1';                         -- Indicates write mechanism disabled.
                        else
                            PLAY_BUTTON                 <= '1';
                            RECORD_BUTTON               <= '0';
                        end if;
                    end if;
    
                    -- If the motor is running then setup the state according to the buttons pressed and the data availability.
                    --
                    if TAPE_MOTOR_ON_n = '0'    and PLAY_BUTTON = '1'   and PLAY_READY = '1' then
                        PLAYING(2)                      <= '1';
                        RECORDING                       <= '0';
                    elsif TAPE_MOTOR_ON_n = '0' and RECORD_BUTTON = '1' then
                        PLAYING(2)                      <= '0';
                        RECORDING                       <= '1';
                    else
                        PLAYING(2)                      <= '0';
                        RECORDING                       <= '0';
                    end if;
        
                    -- The play motor is controlled by an on/off toggle. A high pulse on MOTOR_TOGGLE will toggle the motor state.
                    --
                    if MOTOR_TOGGLE = "10" then
                        TAPE_MOTOR_ON_n                 <= not TAPE_MOTOR_ON_n;
                    end if;
        
                -- The MZ80B uses a fully automated APSS cassette deck, so just take actions on
                -- the signals sent.
                --
                else
                    -- Tape is always ready and able to write.
                    --
                    CMT_BUS_OUTi(TAPEREADY)             <= '0';                         -- Indicates tape loaded, active low.
                    CMT_BUS_OUTi(WRITEREADY)            <= '1';                         -- Indicates write mechanism disabled.
    
                    -- If seek pulses high, store the direction.
                    --
                    if CMT_BUS_IN(pkgs.mctrl_pkg.SEEK) = '1' then
                        CMT_BUS_OUTi(APSS_DIR)          <= CMT_BUS_IN(pkgs.mctrl_pkg.DIRECTION);
                    end if;
        
                    -- If Eject goes active, latch and invert it for reading.
                    --
                    if CMT_BUS_IN(pkgs.mctrl_pkg.EJECT) = '0' then
                        CMT_BUS_OUTi(APSS_EJECT)        <= '1';
                        CMT_BUS_OUTi(APSS_SEEK)         <= '0';
                        CMT_BUS_OUTi(APSS_PLAY)         <= '0';
                        CMT_BUS_OUTi(APSS_STOP)         <= '0';
                    end if;
        
                    -- The play motor is started/stopped by the PLAY/STOP signals.
                    --
                    if MOTOR_TOGGLE = "11"  and CMT_BUS_IN(pkgs.mctrl_pkg.STOP) = '0' then
                        TAPE_MOTOR_ON_n                 <= '0';
                        CMT_BUS_OUTi(APSS_PLAY)         <= '1';
                        CMT_BUS_OUTi(APSS_EJECT)        <= '0';
                        CMT_BUS_OUTi(APSS_SEEK)         <= '0';
                        CMT_BUS_OUTi(APSS_STOP)         <= '0';
    
                    elsif MOTOR_TOGGLE /= "11" and CMT_BUS_IN(pkgs.mctrl_pkg.STOP) = '1' then
                        TAPE_MOTOR_ON_n                 <= '1';
                        CMT_BUS_OUTi(APSS_STOP)         <= '1';
                        CMT_BUS_OUTi(APSS_PLAY)         <= '0';
                        CMT_BUS_OUTi(APSS_EJECT)        <= '0';
                        CMT_BUS_OUTi(APSS_SEEK)         <= '0';
    
                    -- If REEL_MOTOR pulses high, then engage APSS seek.
                    --
                    elsif CMT_BUS_IN(REEL_MOTOR) = '1' then
                        CMT_BUS_OUTi(APSS_SEEK)         <= '1';
                        CMT_BUS_OUTi(APSS_EJECT)        <= '0';
                        CMT_BUS_OUTi(APSS_PLAY)         <= '0';
                        CMT_BUS_OUTi(APSS_STOP)         <= '0';
                        APSS_TIMER_CNT                  <= to_unsigned(1, 21);
                    end if;
    
                    -- If the APSS SEEK action has been started, reset it after 1 second to simulate the real action.
                    --
                    if APSS_TIMER_CNT > 0 then
                        APSS_TIMER_CNT                  <= APSS_TIMER_CNT + 1;
                    end if;
                    if APSS_TIMER_CNT = X"FFFFF" then
                        CMT_BUS_OUTi(APSS_SEEK)         <= '0';
                    end if;
    
                    -- Update the status as to wether we are playing, recording or idle.
                    --
                    PLAYING(2)                          <= PLAY_READY and CMT_BUS_OUTi(APSS_PLAY);
                    RECORDING                           <= not CMT_BUS_IN(pkgs.mctrl_pkg.WRITEENABLE) and CMT_BUS_OUTi(APSS_PLAY);
                end if;
            end if;
        end if;
    end process;

    -- Trigger, when a write occurs to ram, start a counter. Each write resets the counter. After 1 second of
    -- no further writes, then the ram data is ready to play.
    -- Clear funtionality allows the logic to clear the ready signal to indicate data has been processed.
    --
    process( RST, IOCTL_CLK, IOCTL_TAPEHDR_WEN, IOCTL_TAPEDATA_WEN, IOCTL_CS_HDR_n, IOCTL_CS_DATA_n )
    begin
        if RST = '1' then
            PLAY_READY                              <= '0';
            PLAY_READY_SET_CNT                      <= 0;
            RECORD_READY                            <= '0';
            RECORD_READY_SEQ                        <= "00";

        elsif IOCTL_CLK'event and IOCTL_CLK = '1' then

            -- Sample record complete signal and hold. Shift righ 2 bits, msb = latest value.
            RECORD_READY_SEQ(0)                     <= RECORD_READY_SEQ(1);
            RECORD_READY_SEQ(1)                     <= RECORD_READY_SET;

            -- If the external clear is triggered, reset ready signal.
            if PLAY_READY_CLR = '1' then
                PLAY_READY                          <= '0';
                PLAY_READY_SET_CNT                  <= 0;

            -- Every write to ram resets the counter.
            elsif IOCTL_TAPEHDR_WEN = '1' or IOCTL_TAPEDATA_WEN = '1' then
                PLAY_READY                          <= '0';
                PLAY_READY_SET_CNT                  <= 1;

            -- 1 second timer, if no new writes have occurred to RAM, then set the ready flag.
            elsif PLAY_READY_SET_CNT >= 32000000 then
                PLAY_READY_SET_CNT                  <= 0;
                PLAY_READY                          <= '1';
            end if;

            -- Set RECORD_READY if fsm determines a full tape message received.
            if RECORD_READY_SEQ = "10" then
                PLAY_READY                          <= '0';
                RECORD_READY                        <= '1';

            -- HPS access resets signal.
            elsif IOCTL_CS_HDR_n = '0' or IOCTL_CS_DATA_n = '0' then
                RECORD_READY                        <= '0';

            -- If the fsm resets the signal then clear the flag as it will be receiving a new tape message.
            elsif RECORD_READY_SEQ = "00" then
                RECORD_READY                        <= '0';
            end if;

            -- Increment counters if enabled.
            if PLAY_READY_SET_CNT >= 1 then
                PLAY_READY_SET_CNT                  <= PLAY_READY_SET_CNT + 1;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------------------------------------------------
    -------------------------------------------- Read from MZ (Write to Tape) logic ---------------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------------------------

    ----------------------------------------------------------------------------------------------------------------------
    -- Write To Tape logic.
    --
    -- This block concentrates all the logic required to receive data from the MZ into RAM (virtual tape).
    -- Viewed from the CMT, it is the reception of data from computer onto tape.
    ----------------------------------------------------------------------------------------------------------------------

    -- Process to receive the header/data blocks and checksum from the MZ and store it into the cache RAM. ie. MZ -> RAM.
    -- The bit stream is assumed to be at the correct point and the data is serialised and loaded into the RAM.
    --
    process( RST, CLKBUS(CKMASTER) )
    begin
        if RST = '1' then
            RCV_RAM_SUCCESS                         <= '0';
            RCV_RAM_ADDR                            <= (others => '0');
            RCV_RAM_CHECKSUM                        <= (others => '0');
            RCV_RAM_STATE                           <= 0;
            RCV_RAM_TRY                             <= 0;
            RCV_LOAD                                <= '0';
            RCV_CLR                                 <= '1';
            RCV_BYTE_CLR                            <= '0';
            RCV_TMH_CNT                             <= 0;
            RCV_TML_CNT                             <= 0;
            RCV_DATASIZE                            <= to_unsigned(0, 16);
            RCV_TAPE_SIZE                           <= (others => '0');
            RECORD_READY_SET                        <= '0';

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER) = '1' then

            if CLKBUS(CKENCPU) = '1' then

                -- Store the recording state to trigger events on changes.
                RECSEQ(1 downto 0)                      <= RECSEQ(2 downto 1);
                RECSEQ(2)                               <= RECORDING;
    
                -- If Receiver clear state is active, reset, only active for one clock.
                --
                if RCV_CLR = '1' then
                    RCV_CLR                             <= '0';
                end if;
    
                -- If a load command was executed, when the DONE signal goes inactive, acknowledging the command, reset
                -- the load signal.
                if RCV_LOAD = '1' and RCV_DONE = '0' then
                    RCV_LOAD                            <= '0';
                end if;
    
                -- If an error occurs, reset to the very beginning.
                if RCV_ERROR = '1' then
                    RCV_RAM_STATE                       <= 1;
                    RCV_TYPE                            <= 0;
                    RCV_CLR                             <= '1';
                end if;
    
                -- At the end of a recording run, make a full reset ready for next save.
                --
                if RECSEQ = "001" then
                    RCV_RAM_SUCCESS                     <= '0';
                    RCV_RAM_ADDR                        <= (others => '0');
                    RCV_RAM_CHECKSUM                    <= (others => '0');
                    RCV_RAM_STATE                       <= 0;
                    RCV_RAM_TRY                         <= 0;
                    RCV_LOAD                            <= '0';
                    RCV_CLR                             <= '1';
                    RCV_BYTE_CLR                        <= '0';
                    RCV_TMH_CNT                         <= 0;
                    RCV_TML_CNT                         <= 0;
                    RCV_DATASIZE                        <= to_unsigned(0, 16);
    
                -- If recording mode starts, setup required state.
                elsif RECSEQ = "100" then
                    RECORD_READY_SET                    <= '0';
                    RCV_RAM_STATE                       <= 1;
        
                -- If recording, run the FSM.
                elsif RECSEQ = "111" then
    
                    -- FSM to implement the receiption of data from MZ and storage in cache RAM>
                    case(RCV_RAM_STATE) is
                        when 0 => 
                            RCV_RAM_STATE               <= 0;
    
                        -- Load up parameters for the Header or Data block according to expected type.
                        when 1 =>
                            if RCV_TYPE = 0 then
                                RCV_TMH_CNT             <= 40;
                                RCV_TML_CNT             <= 40;
                                RCV_DATASIZE            <= to_unsigned(128 + 2, 16);    -- 2 Additional bytes for the checksum.
                            else
                                RCV_TMH_CNT             <= 20;
                                RCV_TML_CNT             <= 20;
                                RCV_DATASIZE            <= unsigned(RCV_TAPE_SIZE + 2);
                            end if;
                            RCV_RAM_SUCCESS             <= '0';
                            RCV_RAM_ADDR                <= (others => '0');
                            RCV_RAM_CHECKSUM            <= (others => '0');
                            RCV_RAM_STATE               <= 2;
                            RCV_RAM_TRY                 <= 0;
                            RCV_LOAD                    <= '1';
                            RCV_BYTE_CLR                <= '0';
                            HDR_RAM_WEN                 <= '0';
                            DATA_RAM_WEN                <= '0';
    
                        -- As data bytes become available, assemble them into RAM. The last
                        -- 2 bytes are the checksum. If this is the header, then byes 18 and 19
                        -- are the data block size to be received next.
                        when 2 =>
                            if RCV_BYTE_AVAIL = '1' then
                                RCV_BYTE_CLR            <= '1';
    
                                -- During header reception, bytes 18 and 19 represent the size of the data segment.
                                --
                                if RCV_TYPE = 0 and RCV_RAM_SUCCESS = '0' then
                                    if RCV_RAM_ADDR = 18 then
                                        RCV_TAPE_SIZE(7 downto 0)  <= RCV_BYTE;
                                    elsif RCV_RAM_ADDR = 19 then
                                        RCV_TAPE_SIZE(15 downto 8) <= RCV_BYTE;
                                    end if;
                                end if;
    
                                -- If all data received, then next 2 bytes are the checksums.
                                if RCV_RAM_ADDR = std_logic_vector(RCV_DATASIZE - 2) then
                                    RCV_RAM_CHECKSUM(15 downto 8)  <= RCV_BYTE;
                                    RCV_RAM_STATE       <= 6;
                                elsif RCV_RAM_ADDR = std_logic_vector(RCV_DATASIZE - 1) then
                                    RCV_RAM_CHECKSUM(7 downto 0)   <= RCV_BYTE;
                                    if RCV_RAM_TRY = 0 then
                                        RCV_RAM_STATE   <= 8;
                                    else
                                        RCV_RAM_STATE   <= 7;
                                    end if;
                                elsif RCV_RAM_TRY = 1 and RCV_RAM_SUCCESS = '1' then
                                    RCV_RAM_STATE       <= 6;
    
                                -- If enabled, convert the filename to standard ascii.
                                elsif RCV_TYPE = 0 and CONFIG(MZ_80C) = '1' and CONFIG(CMTASCII_IN) = '1' and RCV_RAM_ADDR >= std_logic_vector(to_unsigned(1, 9)) and RCV_RAM_ADDR <= std_logic_vector(to_unsigned(17,9)) then
                                    RCV_ASCII_RAM_ADDR  <= '0' & RCV_BYTE;
                                    RCV_RAM_STATE       <= 3;    
                                else
                                    RAM_DATAIN          <= RCV_BYTE;
                                    RCV_RAM_STATE       <= 4;
                                end if;
                             end if;
    
                        -- Byte to be written is mapped via the Sharp Ascii <-> Ascii lookup table.
                        when 3 =>
                            RAM_DATAIN                  <= ASCII_RAM_DATAOUT;
                            RCV_RAM_STATE               <= 4;
    
                        -- Assert Write to load data into RAM.
                        when 4 =>
                            if RCV_TYPE = 0 then
                                HDR_RAM_WEN             <= '1';
                            else
                                DATA_RAM_WEN            <= '1';
                            end if;
                            RCV_RAM_STATE               <= 5;
    
                        -- Deassert write.
                        when 5 =>
                            HDR_RAM_WEN                 <= '0';
                            DATA_RAM_WEN                <= '0';
                            RCV_RAM_STATE               <= 6;
    
                        when 6 =>
                            -- Once write transaction has completed, update the RAM address.
                            RCV_RAM_ADDR                <= RCV_RAM_ADDR + 1;
                            -- Receive the next byte.
                            RCV_RAM_STATE               <= 2;
    
                        when 7 =>
                            if RCV_DONE = '1' then
                                RCV_RAM_STATE           <= 8;
                            end if;
    
                        -- Compare checksums, raise SUCCESS flag if they match.
                        when 8 =>
                            if RCV_RAM_SUCCESS = '0' and RCV_RAM_CHECKSUM = RCV_CHECKSUM then
                                RCV_RAM_SUCCESS         <= '1';
                            end if;
                            if RCV_RAM_TRY = 0 then
                                RCV_RAM_TRY             <= 1;
                                RCV_RAM_ADDR            <= (others => '0');
                                RCV_RAM_STATE           <= 2;
                            elsif RCV_TYPE = 0 and RCV_DONE = '1' then
                                RCV_RAM_TRY             <= 0;
                                RCV_TYPE                <= 1;      -- Receive data
                                RCV_RAM_STATE           <= 1;
                                RECSEQ                  <= "001";
                              --RCV_CLR                 <= '1';
                            else
                                RCV_RAM_STATE           <= 1;      -- Start waiting for a new header.
                                RCV_CLR                 <= '1';
                                RCV_TYPE                <= 0;      -- Receive header
                                RECORD_READY_SET        <= '1';
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process;


    -- Process to read a bit (PWM decode) from the MZ output and process it according to the expected MZ Tape format framing.
    -- Basically we detect when the bit rises then start counting a fixed period of time. Once the period has
    -- elapsed, we sample the data and indicate it is available.
    -- The bit is then fed through an FSM which evaluates the value and the position in order to setup the correct framing and
    -- commence data extraction. The data is then provided byte by byte to the external process which assembles it into memory
    -- and checks the checksums.
    --
    process( RST, CLKBUS(CKMASTER), READBIT )
    begin
        if RST = '1' then
            RCV_CNT                                 <= (others => '0');
            RCV_SEQ                                 <= "00";
            RCV_ERROR                               <= '0';
            RCV_STATE                               <= 0;
            RCV_DONE                                <= '1';
            RCV_BLOCK                               <= 0;
            RCV_BYTE_AVAIL                          <= '0';
            RCV_BYTE                                <= (others => '0');
            RCV_SR                                  <= (others => '0');
            RCV_CHECKSUM                            <= (others => '0');
            TMH_CNT                                 <= 0;
            TML_CNT                                 <= 0;
            DATA_CNT                                <= (others => '0');
            SPC_CNT                                 <= 0;
            BIT_CNT                                 <= (others => '0');

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER) = '1' then

            if CLKBUS(CKENCPU) = '1' then

                -- Sample incoming bit and hold. Detect when a valid transmission starts.
                RCV_SEQ(0)                              <= RCV_SEQ(1);
                RCV_SEQ(1)                              <= READBIT;
    
                -- Clear byte available flag?
                --
                if RCV_BYTE_CLR = '1' then
                    RCV_BYTE_AVAIL                      <= '0';
                end if;
    
                -- Countdown measurement timer until till we reach 0 to take a sample.
                if RCV_CNT > 0 then
                    RCV_CNT                             <= RCV_CNT - 1;
                end if;
    
                -- If external request made to read a tape block, sample the parameters and set the state machine running.
                -- Same is applicable for a clear, when we receive the clear, reload the parameters and run from start.
                --
                if RCV_LOAD = '1' or RCV_CLR = '1' then
                    RCV_DONE                            <= '0';
                    RCV_CNT                             <= (others => '0');
                    RCV_SEQ                             <= (others => '0');
                    RCV_ERROR                           <= '0';
                    if RCV_CLR = '1' then
                        RCV_STATE                       <= 0;
                    else
                        RCV_STATE                       <= 1;
                    end if;
                    RCV_BLOCK                           <= 0;
                    TMH_CNT                             <= RCV_TMH_CNT;
                    TML_CNT                             <= RCV_TML_CNT;
                    DATA_CNT                            <= RCV_DATASIZE;
                    SPC_CNT                             <= 256;                 -- 256 short pulses (0) between data blocks.
                    BIT_CNT                             <= "111";               -- 7 .. 0 = 8 bits
                    RCV_BYTE_AVAIL                      <= '0';
                    RCV_BYTE                            <= (others => '0');
                    RCV_SR                              <= (others => '0');
                    RCV_CHECKSUM                        <= (others => '0');
                end if;
    
                -- A rising edge on the incoming data line indicates the start of data. We measure in from this edge the following
                -- amount of time, then sample the bit as the 'read' value.
                --
                if RCV_SEQ = "10" then
                    -- Pulse periods for MZ80C type machines
                    if CONFIG(MZ_KC) = '1' or CONFIG(MZ_A) = '1' then
                        RCV_CNT                         <= to_unsigned(736, 16);     -- 368uS @ 2Mhz
                    elsif CONFIG(MZ700) = '1' then
                        RCV_CNT                         <= to_unsigned(1302, 16);    -- 368uS @ 3.54MHz
                    else
                        RCV_CNT                         <= to_unsigned(1020, 16);    -- 255uS @ 4MHz
                    end if;
                end if;
    
                -- Sample bit and set flag.
                if RCV_CNT = 1 then
    
                    -- State machine clocked by reception of bits.
                    --
                    case RCV_STATE is
    
                        -- Parking state.
                        when 0  =>
                            RCV_STATE                   <= 0;
    
                        -- Long or Short Gap. Actual number is not so important as some bits can be lost on initial startup. 
                        -- The purpose of the gap is to synchronise and we use it to fine tune our sampling.
                        when 1  =>
                            if READBIT = '1' then
                                RCV_STATE               <= 2;
                                TMH_CNT                 <= TMH_CNT - 1;
                            end if;
    
                        -- Long or Short Tape Mark part 1.
                        when 2  =>
                            if TMH_CNT > 0 and READBIT = '1' then
                                TMH_CNT                 <= TMH_CNT - 1;
                                if TMH_CNT = 1 then
                                    RCV_STATE           <= 3;
                                end if;
                            elsif READBIT = '0' then
                                RCV_ERROR               <= '1';
                                RCV_STATE               <= 0;
                            end if;
    
                        -- Long or Short Tape Mark part 2.
                        when 3  =>
                            if TML_CNT > 0 and READBIT = '0' then
                                TML_CNT                 <= TML_CNT - 1;
                                if TML_CNT = 1 then
                                    RCV_STATE           <= 4;
                                end if;
                            elsif READBIT = '1' then
                                RCV_ERROR               <= '1';
                                RCV_STATE               <= 0;
                            end if;
    
                        -- Single long pulse.
                        when 4  =>
                            if READBIT = '1' then
                                RCV_CHECKSUM            <= (others => '0');
                                RCV_STATE               <= 5;
                            else
                                RCV_ERROR               <= '1';
                                RCV_STATE               <= 0;
                            end if;
    
                        -- Each byte is preceded by a single long pulse.
                        when 5  =>
                            if READBIT = '1' then
                                RCV_STATE               <= 6;
                            else
                                RCV_ERROR               <= '1';
                                RCV_STATE               <= 0;
                            end if;
    
                        -- Store 1 bit.
                        when 6 =>
                            -- Count each 1 as sum represents the checksum.
                            if READBIT = '1' and DATA_CNT > 2 then
                                RCV_CHECKSUM            <= RCV_CHECKSUM + 1;
                            end if;
                            RCV_SR                      <= RCV_SR(6 downto 0) & READBIT;
                            BIT_CNT                     <= BIT_CNT - 1;
    
                            -- If this was the last bit, make byte available and then move to next state.
                            if BIT_CNT = "000" then
                                RCV_BYTE                <= RCV_SR(6 downto 0) & READBIT;
                                RCV_BYTE_AVAIL          <= '1';
                                DATA_CNT                <= DATA_CNT - 1;
    
                                -- All bytes been received?
                                if DATA_CNT = 1 then
                                    RCV_STATE           <= 8;
                                else
                                    RCV_STATE           <= 5;       -- Back to get next byte.
                                end if;
                            end if;
    
                        when 7 =>
    
                        -- Single long pulse.
                        when 8 =>
                            if READBIT = '1' then
                                -- If this is the second copy received, then finish.
                                if RCV_BLOCK = 1 then
                                    RCV_STATE           <= 0;
                                    RCV_DONE            <= '1';
                                else
                                    RCV_STATE           <= 9;
                                end if;
                            else
                                RCV_ERROR               <= '1';
                                RCV_STATE               <= 9;       -- Bit is less important, flag the error but assembler can check the checksum to verify.
                            end if;
    
                        -- 256 Short padding block to seperate the data blocks.
                        when 9 =>
                            if SPC_CNT > 0 and READBIT = '0' then
                                SPC_CNT                 <= SPC_CNT - 1;
    
                                -- Last space byte, move to next block receipt.
                                if SPC_CNT = 1 then
                                    RCV_BLOCK           <= 1;
                                    DATA_CNT            <= RCV_DATASIZE;
                                    RCV_STATE           <= 5;   -- Go back to retrieve second copy.
                                end if;
                            elsif READBIT = '1' then
                                RCV_ERROR               <= '1';
                                RCV_STATE               <= 0;
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------------------------------------------------------------------------------
    ---------------------------------------- Write to MZ (Playback from Tape) logic ---------------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------------------------

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
    process( RST, CLKBUS(CKMASTER), PLAYING ) begin
        -- For reset, hold machine in reset.
        if RST = '1' then 
            PLAY_READY_CLR                          <= '0';
            PLAY_READY_CLR_CNT                      <= (others => '0');
            TAPE_READ_STATE                         <=  0;
            TAPE_READ_SEQ                           <= "000";
            XMIT_PADDING_LOAD                       <= '0';
            XMIT_RAM_LOAD                           <= '0';
            XMIT_RAM_TYPE                           <= '0';

        elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER) = '1' then

            if CLKBUS(CKENCPU) = '1' then

                -- 2 second after the tape motor goes off clear the PLAY_READY signal, indicating cache tape is no
                -- longer in use.
                --
                if PLAY_READY_CLR_CNT = X"1EFFFF" then
                    PLAY_READY_CLR                      <= '1';
    
                -- A short time after activation (22 bits expiration), clear the reset signal so as to allow
                -- further loads to take place.
                --
                elsif PLAY_READY_CLR_CNT = X"1FFFFF" then
                    PLAY_READY_CLR_CNT                  <= (others => '0');
                    PLAY_READY_CLR                      <= '0';
                end if;
    
                -- If the PLAY_READY reset timer is running (> 0), increment until we reach timeout.
                --
                if PLAY_READY_CLR_CNT > 0 then
                    PLAY_READY_CLR_CNT                  <= PLAY_READY_CLR_CNT + 1;
                end if;
                
                -- If playing has been suspended, on 3rd clock determine the next state, setup and clear necessary signals.
                if PLAYING = "001" then
                    XMIT_PADDING_LOAD                   <= '0';
                    XMIT_RAM_LOAD                       <= '0';
                    PLAY_READY_CLR_CNT                  <= to_unsigned(1, 22);
    
                    -- If the data block was received on first attempt, MZ will stop the motor, so skip the second block.
                    if XMIT_RAM_TYPE = '0' and TAPE_READ_STATE > 6 and TAPE_READ_STATE < 15 then
                        TAPE_READ_STATE                 <= 14;
                    else
                        TAPE_READ_STATE                 <= 15;
                    end if;
    
                -- Change in play state, start fsm to play out the ram contents when the HPS upload has completed.
                elsif PLAYING = "110" then
                    if TAPE_READ_STATE = 15 then
                        TAPE_READ_STATE                 <= 0;
                        XMIT_RAM_TYPE                   <= '0';
                    end if;
                    PLAY_READY_CLR_CNT                  <= (others => '0');
    
                -- If playing, run the FSM.
                elsif PLAYING = "111" then
                    
                    -- Sample the done signal, when setup and stable, we can continue.
                    TAPE_READ_SEQ(1 downto 0)           <= TAPE_READ_SEQ(2 downto 1);
                    TAPE_READ_SEQ(2)                    <= (XMIT_PADDING_LOAD or XMIT_RAM_LOAD) and (XMIT_PADDING_DONE and XMIT_RAM_DONE);
    
                    -- If a transmission has just been started and acknowledged by the DONE flag being reset, reset the activation strobe.
                    --
                    if TAPE_READ_SEQ(0) = '1' then
                        XMIT_PADDING_LOAD               <= '0';
                        XMIT_RAM_LOAD                   <= '0';
                    end if;
    
                    -- If a transmission is in progress, run the FSM.
                    --
                    if XMIT_PADDING_LOAD = '0' and XMIT_RAM_LOAD = '0' then
    
                        -- Default is to move onto next state per clock cycle, unless modified by the state action.
                        TAPE_READ_STATE                 <= TAPE_READ_STATE + 1;
    
                        -- Execute current state.
                        case TAPE_READ_STATE is
    
                        -- Section 1 - Header
                            --
                            when 0 => 
                                -- Header = 0, Data = 1
                                if XMIT_RAM_TYPE = '0' then
                                    -- Setup to send a Long Gap.
                                    if CONFIG(MZ_80C) = '1' or CONFIG(MZ700) = '1' then
                                        XMIT_PADDING_CNT1<= 22000;
                                    else
                                        XMIT_PADDING_CNT1<= 10000;
                                    end if;
                                else
                                    if CONFIG(MZ_80C) = '1' or CONFIG(MZ700) = '1' then
                                        XMIT_PADDING_CNT1<= 11000;
                                    else
                                        XMIT_PADDING_CNT1<= 10000;
                                    end if;
                                end if;
                                XMIT_PADDING_LEVEL1     <= '0';                     -- Short Pulses
                                XMIT_PADDING_CNT2       <= 0;
                                XMIT_PADDING_LEVEL2     <= '0';
                                XMIT_PADDING_LOAD       <= '1';
        
                            when 1 =>
                                -- Wait for the padding transmission to complete.
                                if XMIT_PADDING_DONE = '0' then
                                    TAPE_READ_STATE     <= 1;
                                end if;
        
                            when 2 =>
                                -- Header = 0, Data = 1
                                if XMIT_RAM_TYPE = '0' then
                                    -- Setup to send a Long Tape Mark.
                                    XMIT_PADDING_CNT1   <= 40;
                                    XMIT_PADDING_CNT2   <= 40;
                                else
                                    -- Setup to send a Short Tape Mark.
                                    XMIT_PADDING_CNT1   <= 20;
                                    XMIT_PADDING_CNT2   <= 20;
                                end if;
                                XMIT_PADDING_LEVEL1     <= '1';                     -- Long Pulses
                                XMIT_PADDING_LEVEL2     <= '0';                     -- Short Pulses
                                XMIT_PADDING_LOAD       <= '1';
        
                            when 3 =>
                                if XMIT_PADDING_DONE = '0' then
                                    TAPE_READ_STATE     <= 3;
                                end if;
        
                            when 4 =>
                                -- Setup to send a Long Pulse.
                                XMIT_PADDING_CNT1       <= 1;
                                XMIT_PADDING_LEVEL1     <= '1';                     -- Long Pulse
                                XMIT_PADDING_CNT2       <= 0;
                                XMIT_PADDING_LEVEL2     <= '0';
                                XMIT_PADDING_LOAD       <= '1';
        
                            when 5 =>
                                if XMIT_PADDING_DONE = '0' then
                                    TAPE_READ_STATE     <= 5;
                                end if;
        
                            -- Send the header and checksum for header.
                            when 6 =>
                                XMIT_RAM_LOAD           <= '1';                     -- Send First copy of header/data.
        
                            when 7 =>
                                if XMIT_RAM_DONE = '0' then                        -- If first copy successfully received, MZ will issue a motor stop.
                                    TAPE_READ_STATE     <= 7;
                                end if;
        
                            when 8 =>
                                -- Setup to send 256 short pulse padding.
                                XMIT_PADDING_CNT1       <= 256;
                                XMIT_PADDING_LEVEL1     <= '0';
                                XMIT_PADDING_CNT2       <= 0;
                                XMIT_PADDING_LEVEL2     <= '0';
                                XMIT_PADDING_LOAD       <= '1';
        
                            when 9 =>
                                if XMIT_PADDING_DONE = '0' then
                                    TAPE_READ_STATE     <= 9;
                                end if;
        
                            -- Resend the header/data as backup copy.
                            when 10 => 
                                XMIT_RAM_LOAD           <= '1';                     -- If required, send second copy of header/data.
        
                            when 11 =>
                                if XMIT_RAM_DONE = '0' then
                                    TAPE_READ_STATE     <= 11;
                                end if;
        
                            when 12 =>
                                -- Setup to send a Long Pulse.
                                XMIT_PADDING_CNT1       <= 1;
                                XMIT_PADDING_LEVEL1     <= '1';
                                XMIT_PADDING_CNT2       <= 0;
                                XMIT_PADDING_LEVEL2     <= '0';
                                XMIT_PADDING_LOAD       <= '1';
        
                            when 13 =>
                                if XMIT_PADDING_DONE = '0' then
                                    TAPE_READ_STATE     <= 13;
                                end if;
            
                            -- Switch to data if we have just transmitted the header, else terminate the process.
                            when 14 => 
                                if XMIT_RAM_TYPE = '0' then
                                    XMIT_RAM_TYPE       <= '1';
                                    TAPE_READ_STATE     <= 0;
                                end if;
        
                            -- Clear the Play Ready strobe and wait at this state until external actions reset the state.
                            when 15 =>
                                TAPE_READ_STATE         <= 15;
                        end case;
                end if;
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
-- CLKBUS(CKMASTER)   =           = Base clock for encoding/decoding of pwm pulse.
--
process( RST, CLKBUS(CKMASTER), XMIT_RAM_LOAD, XMIT_RAM_TYPE ) begin
    if RST = '1' then
         XMIT_RAM_DONE                              <= '1';                                  -- Default state is DONE, data transmitted. Set to 0 when transmission in progress.
         XMIT_LOAD_2                                <= '0';                                  -- LOAD signal to the bit writer. 1 = start bit transmission.
         --
         XMIT_BIT_2                                 <= '0';                                  -- Level of bit to transmit.
         XMIT_RAM_ADDR                              <= std_logic_vector(to_unsigned(0, 16)); -- Address of cache memory for next byte.
         XMIT_RAM_COUNT                             <= to_unsigned(0, 16);                   -- Count of bytes to transmit, excludes checksum.
         XMIT_RAM_CHKSUM_CNT                        <= to_unsigned(0, 2);                    -- Count of checksum bytes to transmit.
         XMIT_RAM_CHECKSUM                          <= std_logic_vector(to_unsigned(0, 16)); -- Calculated checksum, count of all 1's in data bytes.
         XMIT_RAM_STATE                             <= 0;                                    -- FSM state.
         XMIT_RAM_SEQ                               <= "000";

    elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER) = '1' then

        if CLKBUS(CKENCPU) = '1' then

            -- Sample load signal and hold. Shift right 3 bits, msb = latest value.
            XMIT_RAM_SEQ(1 downto 0)                    <= XMIT_RAM_SEQ(2 downto 1);
            XMIT_RAM_SEQ(2)                             <= XMIT_RAM_LOAD;
    
            -- If load is stable, acknowledge by bringing DONE low and start process.
            if XMIT_RAM_SEQ = "111" then
                XMIT_RAM_DONE                           <= '0';
    
            -- When XMIT_RAM_LOAD is asserted and setled, sample parameters, set address and count for the given ram block and commence serialisation.
            --
            elsif XMIT_RAM_SEQ = "110" then
                 if XMIT_RAM_TYPE = '0' then
                     XMIT_RAM_COUNT                     <= to_unsigned(128, 16);
                 else
                     XMIT_RAM_COUNT                     <= XMIT_TAPE_SIZE;
                 end if;
                 XMIT_RAM_CHKSUM_CNT                    <= to_unsigned(1, 2);
                 XMIT_RAM_ADDR                          <= std_logic_vector(to_unsigned(0, 16));
                 XMIT_RAM_CHECKSUM                      <= std_logic_vector(to_unsigned(0, 16));
                 XMIT_RAM_STATE                         <= 1;
                 XMIT_LOAD_2                            <= '0';
    
            -- If the DONE signal is low, then run the actual process, raising DONE when complete.
            elsif XMIT_RAM_DONE = '0' then
    
                -- Simple FSM to implement transmission of RAM contents according to MZ Tape Protocol.
                case(XMIT_RAM_STATE) is
                    when 0 => 
                    when 1 =>
                        XMIT_RAM_BIT_CNT                <= 8;      -- 9 bits to transmit, pre 1 + 8 bits of data byte.
                        XMIT_RAM_STATE                  <= 3;
    
                        if XMIT_RAM_COUNT = 0 and XMIT_RAM_CHKSUM_CNT = 1 then
                            XMIT_RAM_SR                 <= '1' & XMIT_RAM_CHECKSUM(15 downto 8);
                        elsif XMIT_RAM_COUNT = 0 and XMIT_RAM_CHKSUM_CNT = 0 then
                            XMIT_RAM_SR                 <= '1' & XMIT_RAM_CHECKSUM(7 downto 0);
                        else
                            -- Extract the size of the tape data block and the load address if this is the header.
                            --
                            if XMIT_RAM_TYPE = '0' then
                                if XMIT_RAM_ADDR = 18 then 
                                    XMIT_TAPE_SIZE(7 downto 0)  <= unsigned(HDR_RAM_DATAOUT);
                                elsif XMIT_RAM_ADDR = 19 then
                                    XMIT_TAPE_SIZE(15 downto 8) <= unsigned(HDR_RAM_DATAOUT);
                                -- If enabled, convert the filename to sharp ascii.
                                elsif CONFIG(MZ_80C) = '1' and CONFIG(CMTASCII_OUT) = '1' and XMIT_RAM_ADDR >= std_logic_vector(to_unsigned(1, 9)) and XMIT_RAM_ADDR <= std_logic_vector(to_unsigned(17,9)) then
                                    XMIT_ASCII_RAM_ADDR <= '1' & HDR_RAM_DATAOUT;
                                    XMIT_RAM_STATE      <= 2;    
                                end if;
                                XMIT_RAM_SR             <= '1' & HDR_RAM_DATAOUT;
                            else
                                XMIT_RAM_SR             <= '1' & DATA_RAM_DATAOUT;
                            end if;
                        end if;
                    -- Byte to be output is mapped via the Sharp Ascii <-> Ascii lookup table.
                    when 2 =>
                            XMIT_RAM_SR                 <= '1' & ASCII_RAM_DATAOUT;
                            XMIT_RAM_STATE              <= 3;
                    when 3 =>
                        XMIT_BIT_2                      <= XMIT_RAM_SR(8);
                        XMIT_LOAD_2                     <= '1';
                        if XMIT_RAM_SR(8) = '1' and XMIT_RAM_BIT_CNT < 8 and XMIT_RAM_COUNT > 0 then
                            XMIT_RAM_CHECKSUM           <= XMIT_RAM_CHECKSUM + 1;
                        end if;
                        XMIT_RAM_SR                     <= XMIT_RAM_SR(7 downto 0) & '0';
                        XMIT_RAM_STATE                  <= 4;
                    when 4 => 
                        -- As we are using the same clock freq, need to wait until XMIT_DONE is set to 0, indicating transmission in progress.
                        if XMIT_LOAD_2 = '1' and XMIT_DONE = '0' then
                            XMIT_LOAD_2                 <= '0';
                            XMIT_RAM_STATE              <= 5;
                        end if;
                    when 5 =>
                        -- Wait until the DONE signal is asserted before continuing.
                        if XMIT_DONE = '1' then
                            XMIT_RAM_STATE              <= 6;
                        end if;
                    when 6 =>
                        XMIT_BIT_2                      <= '0';                   -- Reset bit..
                        if XMIT_RAM_BIT_CNT = 0 then
                            if XMIT_RAM_COUNT = 0 and XMIT_RAM_CHKSUM_CNT = 0 then
                                XMIT_RAM_STATE          <= 7;
                            else
                                if XMIT_RAM_COUNT > 0 then
                                    XMIT_RAM_COUNT      <= XMIT_RAM_COUNT - 1;
                                    XMIT_RAM_ADDR       <= XMIT_RAM_ADDR + 1;
                                elsif XMIT_RAM_COUNT = 0 and XMIT_RAM_CHKSUM_CNT > 0 then
                                    XMIT_RAM_CHKSUM_CNT <= XMIT_RAM_CHKSUM_CNT - 1;
                                end if;
                                XMIT_RAM_STATE          <= 1;
                            end if;
                        else
                            XMIT_RAM_BIT_CNT            <= XMIT_RAM_BIT_CNT - 1;
                            XMIT_RAM_STATE              <= 3;
                        end if;
                    when others => XMIT_RAM_DONE        <= '1';
                end case;
            end if;
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
-- CLKBUS(CKMASTER)    = Internal = Base clock for encoding/decoding of pwm pulse.
--
process( RST, CLKBUS(CKMASTER), XMIT_PADDING_LOAD ) begin
    if RST = '1' then
         XMIT_PADDING_DONE                          <= '1';          -- PADDING transmission complete signal, DONE = 1 when complete, 0 during transmit.
         XMIT_LOAD_1                                <= '0';          -- LOAD signal to bit transmitted, loads required bit when = 1 for 1 cycle. 
         PADDING_CNT1                               <= 0;
         PADDING_LEVEL1                             <= '0';
         PADDING_CNT2                               <= 0;
         PADDING_LEVEL2                             <= '0';
         PADDING_SEQ                                <= "000";

    elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER) = '1' then

        if CLKBUS(CKENCPU) = '1' then

            -- Sample load signal and hold. Shift right 3 bits, msb = latest value.
            PADDING_SEQ(1 downto 0)                     <= PADDING_SEQ(2 downto 1);
            PADDING_SEQ(2)                              <= XMIT_PADDING_LOAD;
    
            -- If LOAD active for 3 periods, bring DONE low to acknowledge LOAD signal and start processing.
            --
            if PADDING_SEQ = "111" then
                XMIT_PADDING_DONE                       <= '0';
            end if;
    
            -- If LOAD active for 2 periods, sample and store the provided parameters.
            --
            if PADDING_SEQ = "110" then
                -- Sample the parameters XMIT_PADDING_CNT1, XMIT_PADDING_CNT2, XMIT_PADDING_LEVEL1, XMIT_PADDING_LEVEL2 and
                -- write out the number of Level1 @ Cnt1, Level2 @ Cnt2 bits.
                PADDING_CNT1                            <= XMIT_PADDING_CNT1;
                PADDING_LEVEL1                          <= XMIT_PADDING_LEVEL1;
                PADDING_CNT2                            <= XMIT_PADDING_CNT2;
                PADDING_LEVEL2                          <= XMIT_PADDING_LEVEL2;
                XMIT_LOAD_1                             <= '0';
            end if;
    
            -- If DONE is low, we are processing.
            if XMIT_PADDING_DONE = '0' then
    
                -- Reset strobe when acknowledged by XMIT_DONE going low.
                if XMIT_LOAD_1 = '1' and XMIT_DONE = '0' then
                    XMIT_LOAD_1                         <= '0';
    
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
                            XMIT_PADDING_DONE           <= '1';
    
                        -- First, transmit the nummber of Counter 1 bits defined in Level 1.
                        elsif PADDING_CNT1 > 0 then
                            XMIT_BIT_1                  <= PADDING_LEVEL1;    -- Set the mux input bit according to input level, 
                            XMIT_LOAD_1                 <= '1';               -- Set the mux input to commence xmit.
                            PADDING_CNT1                <= PADDING_CNT1 - 1;  -- Decrement counter as this bit is now being transmitted.
        
                        -- Then transmit the number of Counter 2 bits defined in Level 2.
                        elsif PADDING_CNT2 > 0 then
                            XMIT_BIT_1                  <= PADDING_LEVEL2;   
                            XMIT_LOAD_1                 <= '1';
                            PADDING_CNT2                <= PADDING_CNT2 - 1;
                        end if;
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
-- XMIT_LOAD_1     = FROM TAPE = When high, Bit available on XMIT_BIT_1 to encode and transmit to MZ.
-- XMIT_LOAD_2     = FROM TAPE = When high, Bit available on XMIT_BIT_2 to encode and transmit to MZ.
-- XMIT_DONE       = TO TAPE   = When high, transmission of bit complete. Resets to 0 on active XMIT_LOAD signal.
-- WRITEBIT        = FROM MZ   = Encoded bit tranmitted to MZ.
-- CLKBUS(CKMASTER)=           = Base clock for encoding/decoding of pwm pulse.
--
-- Machine          Time uS   Description         N-80K(CKMEM)   N-80K(CPU)   N-700(CPU)     N-700(CKMEM)
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
process( RST, CLKBUS(CKMASTER), XMIT_LOAD_1, XMIT_LOAD_2 ) begin
    -- When RESET is high, hold in reset mode.
    if RST = '1' then
        XMIT_DONE                                   <= '1';                    -- Completion signal, 0 when transmitting, 1 when done.
        WRITEBIT                                    <= '0';                    -- Bit facing towards MZ input.
        XMIT_LIMIT                                  <= 0;                      -- End of pulse.
        XMIT_COUNT                                  <= 0;                      -- Pulse start, bit set to 1, reset to 0 on counter = 0
        XMIT_SEQ                                    <= "000";

    elsif CLKBUS(CKMASTER)'event and CLKBUS(CKMASTER)='1' then

        if CLKBUS(CKENCPU) = '1' then

            -- Sample load signal and hold. Shift right 3 bits, msb = latest value.
            XMIT_SEQ(1 downto 0)                        <= XMIT_SEQ(2 downto 1);
            XMIT_SEQ(2)                                 <= XMIT_LOAD_1 or XMIT_LOAD_2;
    
            -- If load is stable, acknowledge by bringing DONE low and start process.
            if XMIT_SEQ = "111" then
                XMIT_DONE                               <= '0';
                WRITEBIT                                <= '1';
    
            -- Store run values on 2nd clock cycle of LOAD being active.
            elsif XMIT_SEQ = "110" then
    
                -- Pulse periods for MZ80C type machines
                if CONFIG(MZ_KC) = '1' or CONFIG(MZ_A) = '1' then
                    if (XMIT_LOAD_1 = '1' and XMIT_BIT_1 = '1') or (XMIT_LOAD_2 = '1' and XMIT_BIT_2 = '1') then
                        XMIT_LIMIT                      <=  988;     --  1976;
                        XMIT_COUNT                      <= -928;     -- -1856;
                    else
                        XMIT_LIMIT                      <=  528;     --  1056;
                        XMIT_COUNT                      <= -480;     --  -960;
                    end if;
                elsif CONFIG(MZ700) = '1' then
                -- Pulse periods for MZ700 type machines
                    if (XMIT_LOAD_1 = '1' and XMIT_BIT_1 = '1') or (XMIT_LOAD_2 = '1' and XMIT_BIT_2 = '1') then
                        XMIT_LIMIT                      <= 1729;     --  3458;
                        XMIT_COUNT                      <= -1624;    -- -3248;
                    else
                        XMIT_LIMIT                      <=  924;     --  1848;
                        XMIT_COUNT                      <= -840;     -- -1680;
                    end if;
                else
                -- Pulse periods for MZ80B type machines
                    if (XMIT_LOAD_1 = '1' and XMIT_BIT_1 = '1') or (XMIT_LOAD_2 = '1' and XMIT_BIT_2 = '1') then
                        XMIT_LIMIT                      <=  1336;    --  2672;
                        XMIT_COUNT                      <= -1332;    -- -2664;
                    else
                        XMIT_LIMIT                      <=  664;     --  1328;
                        XMIT_COUNT                      <= -667;     -- -1334;
                    end if;
                end if;
    
            -- On expiration of timer, signal completion.
            elsif XMIT_COUNT = XMIT_LIMIT then
                XMIT_DONE                               <= '1';
             
            -- If the counter is running, format the output pulse.
            elsif XMIT_COUNT /= XMIT_LIMIT then
                -- At zero, we have elapsed the correct high period for the write bit, now bring it low for the remaining period.
                if XMIT_COUNT = 0 then
                    WRITEBIT                            <= '0';
                end if;
                XMIT_COUNT                              <= XMIT_COUNT + 1;
            end if;
        end if;
    end if;
end process;

-- Only enable debugging LEDS if enabled in the config package.
--
DEBUGCMT: if DEBUG_ENABLE = 1 generate
    DEBUG_STATUS_LEDS(0)                            <= WRITEBIT;
    DEBUG_STATUS_LEDS(1)                            <= XMIT_DONE;
    DEBUG_STATUS_LEDS(2)                            <= XMIT_LOAD_1;
    DEBUG_STATUS_LEDS(3)                            <= XMIT_LOAD_2;
    DEBUG_STATUS_LEDS(4)                            <= XMIT_PADDING_LOAD;
    DEBUG_STATUS_LEDS(5)                            <= XMIT_PADDING_DONE;
    DEBUG_STATUS_LEDS(6)                            <= XMIT_RAM_LOAD;
    DEBUG_STATUS_LEDS(7)                            <= XMIT_RAM_DONE;
    
    DEBUG_STATUS_LEDS(8)                            <= PLAY_READY;
    DEBUG_STATUS_LEDS(9)                            <= PLAY_READY_CLR;
    DEBUG_STATUS_LEDS(10)                           <= PLAYING(2);
    DEBUG_STATUS_LEDS(11)                           <= PLAYING(1);
    DEBUG_STATUS_LEDS(12)                           <= PLAYING(0);
    DEBUG_STATUS_LEDS(13)                           <= '0';
    DEBUG_STATUS_LEDS(14)                           <= '0';
    DEBUG_STATUS_LEDS(15)                           <= RECORDING;
    
    DEBUG_STATUS_LEDS(16)                           <= READBIT;
    DEBUG_STATUS_LEDS(17)                           <= RCV_ERROR;
    DEBUG_STATUS_LEDS(18)                           <= '0';
    DEBUG_STATUS_LEDS(19)                           <= RCV_CLR;
    DEBUG_STATUS_LEDS(20)                           <= RCV_DONE;
    DEBUG_STATUS_LEDS(21)                           <= RCV_LOAD;
    DEBUG_STATUS_LEDS(22)                           <= RCV_BYTE_CLR;
    DEBUG_STATUS_LEDS(23)                           <= RCV_BYTE_AVAIL;

    DEBUG_STATUS_LEDS(24)                           <= CMT_BUS_IN(pkgs.mctrl_pkg.STOP);
    DEBUG_STATUS_LEDS(25)                           <= CMT_BUS_IN(pkgs.mctrl_pkg.PLAY);
    DEBUG_STATUS_LEDS(26)                           <= CMT_BUS_IN(pkgs.mctrl_pkg.SEEK);
    DEBUG_STATUS_LEDS(27)                           <= CMT_BUS_IN(pkgs.mctrl_pkg.DIRECTION);
    DEBUG_STATUS_LEDS(28)                           <= CMT_BUS_IN(pkgs.mctrl_pkg.EJECT);
    DEBUG_STATUS_LEDS(29)                           <= CMT_BUS_IN(pkgs.mctrl_pkg.WRITEENABLE);
    DEBUG_STATUS_LEDS(31 downto 30)                 <= CONFIG(BUTTONS);
end generate;
DEBUGCMT1: if DEBUG_ENABLE = 0 generate
    DEBUG_STATUS_LEDS                               <= (others => '0');
end generate;

end RTL;
