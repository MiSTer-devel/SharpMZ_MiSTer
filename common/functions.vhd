---------------------------------------------------------------------------------------------------------
--
-- Name:            functions.vhd
-- Created:         October 2018
-- Author(s):       Philip Smart
-- Description:     Collection of re-usable functions for the SharpMZ Project.
--
-- Credits:         
-- Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
--
-- History:         October 2018   - Initial module written.
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
library IEEE;
library pkgs;
use IEEE.STD_LOGIC_1164.ALL;
--use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.numeric_std.all;

package functions_pkg is

  -- Function to reverse the order of the bits in a standard logic vector.
  -- ie. 1010 becomes 0101
  function reverse_vector(slv:std_logic_vector) return std_logic_vector; 

  -- Function to convert an integer (0 or 1) into std_logic.
  --
  function to_std_logic(i : in integer) return std_logic;

end functions_pkg;

package body functions_pkg is

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

end functions_pkg;
