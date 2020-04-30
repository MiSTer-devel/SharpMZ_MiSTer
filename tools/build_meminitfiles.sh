#!/bin/bash
#########################################################################################################
##
## Name:            build_meminitfiles.sh
## Created:         August 2018
## Author(s):       Philip Smart
## Description:     Sharp MZ series combined rom build script.
##                  This script takes the necessary ROM files and builds the required combined
##                  rom files for the emulator and converts them to MIF format.
##                  Change the names below if you want this script to build combined MIF files with
##                  different content.
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

ROMTOOL=../tools/romtool.pl
ROMDIR=../software/roms
MIFDIR=../software/mif
MZFDIR=../software/mzf
ASMDIR=../software/asm

${ROMTOOL} --command=KEYMAP                                 \
           --a_keymap=${ROMDIR}/key_80a.rom                 \
           --b_keymap=${ROMDIR}/key_80b.rom                 \
           --c_keymap=${ROMDIR}/key_80c.rom                 \
           --k_keymap=${ROMDIR}/key_80k.rom                 \
           --7_keymap=${ROMDIR}/key_700.rom                 \
           --8_keymap=${ROMDIR}/key_700.rom                 \
           --12_keymap=${ROMDIR}/key_1200.rom               \
           --20_keymap=${ROMDIR}/key_80b.rom                \
           --binout=${ROMDIR}/combined_keymap.rom           \
           --mifout=${MIFDIR}/combined_keymap.mif
${ROMTOOL} --command=64KRAM                                 \
           --ramchecker=${MZFDIR}/hi-ramcheck.mzf           \
           --a_mrom=${ROMDIR}/monitor_SA1510.rom            \
           --mzf=${MZFDIR}/tapecheck.mzf                    \
           --binout=${ROMDIR}/combined_mainmemory.rom       \
           --mifout=${MIFDIR}/combined_mainmemory.mif
${ROMTOOL} --command=MONROM                                 \
           --a_mrom=${ROMDIR}/monitor_SA1510.rom            \
           --b_mrom=${ROMDIR}/IPL.rom                       \
           --c_mrom=${ROMDIR}/NEWMON.rom                    \
           --k_mrom=${ROMDIR}/SP1002.rom                    \
           --7_mrom=${ROMDIR}/monitor_1Z-013A.rom           \
           --8_mrom=${ROMDIR}/monitor_1Z-013A.rom           \
           --12_mrom=${ROMDIR}/SP1002.rom                   \
           --20_mrom=${ROMDIR}/IPL.rom                     \
           --a_80c_mrom=${ROMDIR}/monitor_80c_SA1510.rom    \
           --b_80c_mrom=${ROMDIR}/IPL.rom                   \
           --c_80c_mrom=${ROMDIR}/NEWMON.rom                \
           --k_80c_mrom=${ROMDIR}/SP1002.rom                \
           --7_80c_mrom=${ROMDIR}/monitor_80c_1Z-013A.rom   \
           --8_80c_mrom=${ROMDIR}/monitor_80c_1Z-013A.rom   \
           --12_80c_mrom=${ROMDIR}/SP1002.rom               \
           --20_80c_mrom=${ROMDIR}/IPL.rom                  \
           --a_userrom=${ROMDIR}/userrom.rom                \
           --b_userrom=${ROMDIR}/userrom.rom                \
           --c_userrom=${ROMDIR}/userrom.rom                \
           --k_userrom=${ROMDIR}/userrom.rom                \
           --7_userrom=${ROMDIR}/userrom.rom                \
           --8_userrom=${ROMDIR}/userrom.rom                \
           --12_userrom=${ROMDIR}/userrom.rom               \
           --20_userrom=${ROMDIR}/userrom.rom               \
           --a_fdcrom=${ROMDIR}/fdcrom.rom                  \
           --b_fdcrom=${ROMDIR}/fdcrom.rom                  \
           --c_fdcrom=${ROMDIR}/fdcrom.rom                  \
           --k_fdcrom=${ROMDIR}/fdcrom.rom                  \
           --7_fdcrom=${ROMDIR}/fdcrom.rom                  \
           --8_fdcrom=${ROMDIR}/fdcrom.rom                  \
           --12_fdcrom=${ROMDIR}/fdcrom.rom                 \
           --20_fdcrom=${ROMDIR}/fdcrom.rom                 \
           --binout=${ROMDIR}/combined_mrom.rom             \
           --mifout=${MIFDIR}/combined_mrom.mif
${ROMTOOL} --command=CGROM                                  \
           --a_cgrom=${ROMDIR}/mz-80acg.rom                 \
           --b_cgrom=${ROMDIR}/MZFONT.rom                   \
           --c_cgrom=${ROMDIR}/MZ80K_cgrom.rom              \
           --k_cgrom=${ROMDIR}/MZ80K_cgrom.rom              \
           --7_cgrom=${ROMDIR}/MZ700_cgrom.rom              \
           --8_cgrom=${ROMDIR}/MZ700_cgrom.rom              \
           --12_cgrom=${ROMDIR}/mz-80acg.rom                \
           --20_cgrom=${ROMDIR}/MZFONT.rom                  \
           --binout=${ROMDIR}/combined_cgrom.rom            \
           --mifout=${MIFDIR}/combined_cgrom.mif
