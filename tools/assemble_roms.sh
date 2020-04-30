#!/bin/bash
#########################################################################################################
##
## Name:            assemble_roms.sh
## Created:         August 2018
## Author(s):       Philip Smart
## Description:     Sharp MZ series ROM assembly tool
##                  This script takes Sharp MZ ROMS in assembler format and compiles/assembles them
##                  into a ROM file using the GLASS Z80 assembler.
##
## Credits:         
## Copyright:       (c) 2018 Philip Smart <philip.smart@net2net.org>
##
## History:         August 2018   - Initial script written.
##
#########################################################################################################
## This source file is free software: you can redistribute it and#or modify
## it under the terms of the GNU General Public License as published
## by the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## This source file is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program.  If not, see <http://www.gnu.org/licenses/>.
#########################################################################################################

JARDIR=../tools
ASM=glass.jar
BUILDROMLIST="IPL monitor_SA1510 monitor_80c_SA1510 monitor_mz-1r12 quickdisk_mz-1e05 quickdisk_mz-1e14 monitor_1Z-013A monitor_80c_1Z-013A"
BUILDMZFLIST="hi-ramcheck sharpmz-test"
ASMDIR=../software/asm
ROMDIR=../software/roms
MZFDIR=../software/mzf

# Go through list and build image.
#
for f in ${BUILDROMLIST} ${BUILDMZFLIST}
do
    echo "Assembling: $f..."

    # Assemble the source.
    echo "java -jar ${JARDIR}/${ASM} ${ASMDIR}/${f}.asm ${ASMDIR}/${f}.obj ${ASMDIR}/${f}.sym"
    java -jar ${JARDIR}/${ASM} ${ASMDIR}/${f}.asm ${ASMDIR}/${f}.obj ${ASMDIR}/${f}.sym

    # On successful compile, perform post actions else go onto next build.
    #
    if [ $? = 0 ]
    then
        # The object file is binary, no need to link, copy according to build group.
        if [[ ${BUILDROMLIST} = *"${f}"* ]]; then
            echo "Copy ${ASMDIR}/${f}.obj to ${ROMDIR}/${f}.rom"
            cp ${ASMDIR}/${f}.obj ${ROMDIR}/${f}.rom
        else
            echo "Copy ${ASMDIR}/${f}.obj to ${MZFDIR}/${f}.mzf"
            cp ${ASMDIR}/${f}.obj ${MZFDIR}/${f}.mzf
        fi
    fi
done
