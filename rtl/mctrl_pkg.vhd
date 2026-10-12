---------------------------------------------------------------------------------------------------------
--
-- Name:            mctrl_pkg.vhd
-- Description:     Sharp MZ series machine control: CONFIG bit map and CMT bus definitions.
--                  Split out of mctrl.vhd so packages can be analysed before the entities that use them.
--
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- This source file is free software: you can redistribute it and-or modify it under the terms
-- of the GNU General Public License as published by the Free Software Foundation, either
-- version 3 of the License, or (at your option) any later version.
---------------------------------------------------------------------------------------------------------

package mctrl_pkg is

    -- Config Bus
    --
    subtype  CONFIG_WIDTH is integer range 72 downto 0;


    -- Mode signals indicating type of machine we are emulating.
    --
    constant MZ80K           : integer := 0;                             -- Machine is an MZ80K
    constant MZ80C           : integer := 1;                             -- Machine is an MZ80C
    constant MZ1200          : integer := 2;                             -- Machine is an MZ1200
    constant MZ80A           : integer := 3;                             -- Machine is an MZ80A
    constant MZ700           : integer := 4;                             -- Machine is an MZ700
    constant MZ800           : integer := 5;                             -- Machine is an MZ800
    constant MZ80B           : integer := 6;                             -- Machine is an MZ80B
    constant MZ2000          : integer := 7;                             -- Machine is an MZ2000
    subtype  CURRENTMACHINE  is integer range 7 downto 0;                -- Range of bits to indicate current machine, only 1 bit is set at a time.
    constant MZ_KC           : integer := 8;                             -- Machine is an MZ80K/MZ80C Series
    constant MZ_A            : integer := 9;                             -- Machine is an MZ1200/MZ80A Series
    constant MZ_B            : integer := 10;                            -- Machine is an MZ2000/MZ80B Series
    constant MZ_80B          : integer := 11;                            -- Machine is an MZ2000/MZ80B Series
    constant MZ_80C          : integer := 12;                            -- Machine is an MZ80K/MZ80C/MZ1200/MZ80A Series

    -- Type of display to emulate.
    --
    constant NORMAL          : integer := 13;                            -- Normal 40 x 25 character monochrome display.
    constant NORMAL80        : integer := 14;                            -- Normal 80 x 25 character monochrome display.
    constant COLOUR          : integer := 15;                            -- Colour 40 x 25 character display.
    constant COLOUR80        : integer := 16;                            -- Colour 80 x 25 character display.
    subtype  VGAMODE         is integer range 18 downto 17;              -- Output display to 640x400 or 640x480, double up pixels as required.

    -- Option Roms Enable (some machines by design dont have them, but this emulation allows them to be enabled if needed).
    --
    subtype  USERROM         is integer range 26 downto 19;              -- User ROM E800 - EFFF enable per machine.
    subtype  FDCROM          is integer range 34 downto 27;              -- FDC ROM F000 - FFFF enable per machine.

    subtype  GRAMIOADDR      is integer range 39 downto 35;

    -- Various configurable settings.
    --
    constant AUDIOSRC        : integer := 40;                            -- Audio source, 0 = sound generator, 1 = tape audio.
    subtype  TURBO           is integer range 43 downto 41;              -- 2MHz/4MHz/8MHz/16MHz/32MHz switch (various).
    subtype  FASTTAPE        is integer range 46 downto 44;              -- Speed of tape read/write.
    subtype  BUTTONS         is integer range 48 downto 47;              -- Various external buttons, such as CMT play/record.
    constant PCGRAM          : integer := 49;                            -- PCG ROM(0) or RAM(1) based.
    constant VRAMWAIT        : integer := 50;                            -- Insert video wait states on CPU access as per original design.
    constant VRAMDISABLE     : integer := 51;                            -- Disable the Video RAM from display output.
    constant GRAMDISABLE     : integer := 52;                            -- Disable the graphics RAM from display output.
    constant MENUENABLE      : integer := 53;                            -- Enable the OSD menu on display output.
    constant STATUSENABLE    : integer := 54;                            -- Enable the OSD menu on display output.
    constant BOOT_RESET      : integer := 55;                            -- MZ80B/2000 Boot IPL Reset Enable.
    constant CMTASCII_IN     : integer := 56;                            -- Enable CMT conversion of Sharp Ascii <-> Ascii on receipt of data from Sharp.
    constant CMTASCII_OUT    : integer := 57;                            -- Enable CMT conversion of Sharp Ascii <-> Ascii on sending data to Sharp.

    -- Derivative settings to program the clock generator.
    --
    subtype  CPUSPEED        is integer range 61 downto 58;              -- Active CPU Speed.
    subtype  VIDSPEED        is integer range 64 downto 62;              -- Active Video Speed.
    subtype  PERSPEED        is integer range 66 downto 65;              -- Active Peripheral Speed.
    subtype  RTCSPEED        is integer range 68 downto 67;              -- Active RTC Speed.
    subtype  SNDSPEED        is integer range 70 downto 69;              -- Active Sound Speed.

    -- MZ-800 rear mode switch, read by the IPL through IN CE bit 1.
    constant MZ800_MODE      : integer := 71;
    constant IS_MZ1500       : integer := 72;                            -- MZ-1500: an MZ-700 (CONFIG(MZ700) set) with PCG, palette, 2 PSGs, PIO, QD.

    -- CMT Bus
    --
    subtype  CMT_BUS_OUT_WIDTH  is integer range 13 downto 0;
    subtype  CMT_BUS_IN_WIDTH   is integer range 7 downto 0;

    -- CMT exported Signals.
    --
    constant PLAY_READY      : integer := 0;                             -- Tape play back buffer, 0 = empty, 1 = full.
    constant PLAYING         : integer := 1;                             -- Tape playback, 0 = stopped, 1 = in progress.
    constant RECORD_READY    : integer := 2;                             -- Tape record buffer full, 0 = empty, 1 = full.
    constant RECORDING       : integer := 3;                             -- Tape recording, 0 = stopped, 1 = in progress.
    constant ACTIVE          : integer := 4;                             -- Tape transfer in progress, 0 = no activity, 1 = activity.
    constant SENSE           : integer := 5;                             -- Tape state Sense out.
    constant WRITEBIT        : integer := 6;                             -- Write bit to MZ.
    constant TAPEREADY       : integer := 7;                             -- Tape is loaded in deck when L = 0.
    constant WRITEREADY      : integer := 8;                             -- Write is prohibited when L = 0.
    constant APSS_SEEK       : integer := 9;                             -- Start to seek the next program according to APSS_DIR
    constant APSS_DIR        : integer := 10;                            -- Direction for APSS Seek, 0 = Rewind, 1 = Forward.
    constant APSS_EJECT      : integer := 11;                            -- Eject cassette.
    constant APSS_PLAY       : integer := 12;                            -- Play cassette.
    constant APSS_STOP       : integer := 13;                            -- Stop playing/rwd/ff of cassette.

    -- CMT imported Signals.
    --
    constant READBIT         : integer := 0;                             -- Receive bit from MZ.
    constant REEL_MOTOR      : integer := 1;                             -- APSS Reel Motor on/off.
    constant STOP            : integer := 2;                             -- Stop the motor.
    constant PLAY            : integer := 3;                             -- Play cassette.
    constant SEEK            : integer := 4;                             -- Seek cassette using DIRECTION (L = Rewind, H = FF).
    constant DIRECTION       : integer := 5;                             -- Seek direction, L = Rewind, H = Fast Forward.
    constant EJECT           : integer := 6;                             -- Eject the cassette.
    constant WRITEENABLE     : integer := 7;                             -- Enable writing to cassette.

    -- Debug Bus
    --
    subtype  DEBUG_WIDTH is integer range 15 downto 0;

    -- Debugging signals.
    --
    subtype  LEDS_BANK       is integer range 2 downto 0;
    subtype  LEDS_SUBBANK    is integer range 5 downto 3;
    constant LEDS_ON         : integer := 6;
    constant ENABLED         : integer := 7;
    subtype  SMPFREQ         is integer range 11 downto 8;
    subtype  CPUFREQ         is integer range 15 downto 12;
end mctrl_pkg;
