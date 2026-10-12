---------------------------------------------------------------------------------------------------------
--
-- Name:            VideoController_pkg.vhd
-- Created:         June 2020
-- Author(s):       Philip Smart
-- Description:     Sharp MZ700 Video Module v1.1 FPGA configuration file.
--                                                     
--                  This module contains parameters for the Sharp MZ series Video Module found on the
--                  tranZPUter700 card.
--
-- Credits:         
-- Copyright:       (c) 2018-21 Philip Smart <philip.smart@net2net.org>
--
-- History:         June 2020 - Initial creation.
--                  Oct 2020  - Split off from the Sharp MZ80A Video Module, the Video Module for the 
--                              Sharp MZ700 has the same roots but different control functionality. The
--                              MZ700 version resides within the tranZPUter memory and not the mainboard
--                              allowing for generally easier control. The MZ80A and MZ700 graphics logic
--                              should be pretty much identical.
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
use ieee.numeric_std.all;
use ieee.math_real.all;

package VideoController_pkg is

    ------------------------------------------------------------ 
    -- Constants
    ------------------------------------------------------------ 

    -- Potential logic state constants.
    constant YES                      : std_logic := '1';
    constant NO                       : std_logic := '0';
    constant HI                       : std_logic := '1';
    constant LO                       : std_logic := '0';
    constant ONE                      : std_logic := '1';
    constant ZERO                     : std_logic := '0';
    constant HIZ                      : std_logic := 'Z';

    -- Target video hardware modes.
    constant MODE_MZ80K               : integer   := 0;
    constant MODE_MZ80C               : integer   := 1;
    constant MODE_MZ1200              : integer   := 2;
    constant MODE_MZ80A               : integer   := 3;
    constant MODE_MZ700               : integer   := 4;
    constant MODE_MZ800               : integer   := 5;
    constant MODE_MZ1500              : integer   := 6;
    constant MODE_MZ80B               : integer   := 7;
    constant MODE_MZ2000              : integer   := 8;
    constant MODE_MZ2200              : integer   := 9;
    constant MODE_MZ2500              : integer   := 10;

    -- Underlying host hardware mode. Based on the CPLD configuration each CPLD map dedicated to one host type.
    -- These definitions should match those in the coreMZ_pkg, they are duplicated as the Video Controller can be used standalone
    -- or with other builds.
    constant MODE_HOST_MZ80K          : integer   := 0;
    constant MODE_HOST_MZ80C          : integer   := 1;
    constant MODE_HOST_MZ1200         : integer   := 2;
    constant MODE_HOST_MZ80A          : integer   := 3;
    constant MODE_HOST_MZ700          : integer   := 4;
    constant MODE_HOST_MZ800          : integer   := 5;
    constant MODE_HOST_MZ80B          : integer   := 6;
    constant MODE_HOST_MZ2000         : integer   := 7;
    constant MODE_HOST_IOP            : integer   := 14;          -- I/O Processor.
    constant MODE_HOST_EMUMZ          : integer   := 15;          -- Sharp MZ Series FPGA Emulation.

    ------------------------------------------------------------ 
    -- Configurable parameters.
    ------------------------------------------------------------ 
    -- Target hardware.
    constant CPLD_HOST_HW             : integer   := MODE_MZ700;

    -- Target video hardware.
    constant CPLD_HAS_FPGA_VIDEO      : std_logic := '1';

    -- Version of hdl.
    constant CPLD_VERSION             : integer   := 2;

    ------------------------------------------------------------ 
    -- Function prototypes
    ------------------------------------------------------------ 
    -- Find the maximum of two integers.
    function IntMax(a : in integer; b : in integer) return integer;

    -- Find the number of bits required to represent an integer.
    function log2ceil(arg : positive) return natural;

    -- Function to calculate the number of whole 'clock' cycles in a given time period, the period being in ns.
    function clockTicks(period : in integer; clock : in integer) return integer;

    -- Function to reverse the order of the bits in a standard logic vector.
    -- ie. 1010 becomes 0101
    function reverse_vector(slv:std_logic_vector) return std_logic_vector; 

    -- Function to convert an integer (0 or 1) into std_logic.
    --
    function to_std_logic(i : in integer) return std_logic;

    -- Function to return the value of a bit as an integer for array indexing etc.
    function bit_to_integer( s : std_logic ) return natural;   

    ------------------------------------------------------------ 
    -- Records
    ------------------------------------------------------------ 

    ------------------------------------------------------------ 
    -- Components
    ------------------------------------------------------------

end VideoController_pkg;

------------------------------------------------------------ 
-- Function definitions.
------------------------------------------------------------ 
package body VideoController_pkg is
    
    -- Find the maximum of two integers.
    function IntMax(a : in integer; b : in integer) return integer is
    begin
        if a > b then
            return a;
        else
            return b;
        end if;
        return a;
    end function IntMax;

    -- Find the number of bits required to represent an integer.
    function log2ceil(arg : positive) return natural is
        variable tmp : positive     := 1;
        variable log : natural      := 0;
    begin
        if arg = 1 then
            return 0;
        end if;

        while arg > tmp loop
            tmp := tmp * 2;
            log := log + 1;
        end loop;
        return log;
    end function;

    -- Function to calculate the number of whole 'clock' cycles in a given time period, the period being in ns.
    function clockTicks(period : in integer; clock : in integer) return integer is
        variable ticks         : real;
        variable fracTicks     : real;
    begin
        ticks         := (Real(period) * Real(clock)) / 1000000000.0;
        fracTicks     := ticks - CEIL(ticks);
        if fracTicks > 0.0001 then
            return Integer(CEIL(ticks + 1.0));
        else
            return Integer(CEIL(ticks));
        end if;
    end function;

    function reverse_vector(slv:std_logic_vector) return std_logic_vector is 
       variable target : std_logic_vector(slv'high downto slv'low); 
    begin 
      for idx in slv'high downto slv'low loop 
        target(idx) := slv(slv'low + (slv'high-idx)); 
      end loop; 
      return target; 
    end reverse_vector;

    function to_std_logic(i : in integer) return std_logic is
    begin
      if i = 0 then
        return '0';
      end if;
      return '1';
    end function;

    -- Function to return the value of a bit as an integer for array indexing etc.
    function bit_to_integer( s : std_logic ) return natural is
    begin
        if s = '1' then
            return 1;
        else
            return 0;
        end if;
    end function;
end package body;
