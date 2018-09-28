#!/bin/bash

BASE=`basename $1`

echo "Converting ${BASE}.bin to Memory Initialization File ${BASE}.mif..."
srec_cat ${BASE}.bin -binary  -Output ${BASE}.mif -Memory_Initialization_File

