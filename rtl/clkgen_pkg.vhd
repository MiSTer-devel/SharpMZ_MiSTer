---------------------------------------------------------------------------------------------------------
--
-- Name:            clkgen_pkg.vhd
-- Description:     Sharp MZ series clock bus index definitions.
--                  Split out of clkgen.vhd so packages can be analysed before the entities that use them.
--
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- This source file is free software: you can redistribute it and-or modify it under the terms
-- of the GNU General Public License as published by the Free Software Foundation, either
-- version 3 of the License, or (at your option) any later version.
---------------------------------------------------------------------------------------------------------

package clkgen_pkg is
    constant CLK_SYS_HZ      : natural := 70937600;                      -- clk_sys (4 x 17.7344 MHz), as clkgen's CLK_HZ.


    -- Clock bus, various clocks on a single bus construct.
    --
    subtype  CLKBUS_WIDTH is integer range 9 downto 0;

    -- Indexes to the various clocks on the bus.
    --
    constant CKMASTER               : integer := 0;
    constant CKSOUND                : integer := 1;                      -- Sound clock.
    constant CKRTC                  : integer := 2;                      -- RTC clock.
    constant CKENVIDEO              : integer := 3;                      -- Video clock enable.
    constant CKVIDEO                : integer := 4;                      -- Video clock.
    constant CKIOP                  : integer := 5;
    constant CKENCPU                : integer := 6;                      -- CPU clock enable.
    constant CKENLEDS               : integer := 7;                      -- LEDS display clock enable.
    constant CKENPERIPH             : integer := 8;                      -- Peripheral clock enable.
    constant CKENPSG                : integer := 9;                      -- MZ-800 PSG clock enable, 3.54688 MHz (not affected by turbo).
end clkgen_pkg;
