#!/bin/bash -x

rm -f *.bak
rm -f *.orig
rm -f *.rej
rm -f *~
rm -fr db
rm -fr incremental_db
rm -fr output_files
rm -fr simulation
rm -fr greybox_tmp
rm -fr hc_output
rm -fr .qsys_edit
rm -fr hps_isw_handoff
rm -fr sys\.qsys_edit
rm -fr sys\vip
#rm build_id.v
rm -f c5_pin_model_dump.txt
rm -f PLLJ_PLLSPE_INFO.txt
rm -f *.qws
rm -f *.ppf
rm -f *.ddb
rm -f *.csv
rm -f *.cmp
rm -f *.sip
rm -f *.spd
rm -f *.bsf
rm -f *.f
rm -f *.sopcinfo
rm -f *.xml
rm -f *.cdf
rm -f *.rpt
rm -f new_rtl_netlist
rm -f old_rtl_netlist
rm -f software/asm/*.obj
rm -f software/asm/*.sym
(cd ../Main_MiSTer; make clean)
