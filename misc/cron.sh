#!/bin/sh

# 00 00 * * * /home/jhegarty/misc/crontop.sh

# exit early if any errors
set -e

echo $PATH
. /opt/Xilinx/14.5/ISE_DS/settings64.sh
export LD_LIBRARY_PATH=
export PATH=/opt/Xilinx/14.5/ISE_DS/ISE/bin/lin64:/opt/Xilinx/14.5/ISE_DS/ISE/sysgen/util:/opt/Xilinx/14.5/ISE_DS/ISE/sysgen/bin:/opt/Xilinx/14.5/ISE_DS/ISE/../../../DocNav:/opt/Xilinx/14.5/ISE_DS/PlanAhead/bin:/opt/Xilinx/14.5/ISE_DS/EDK/bin/lin64:/opt/Xilinx/14.5/ISE_DS/EDK/gnu/microblaze/lin64/bin:/opt/Xilinx/14.5/ISE_DS/EDK/gnu/powerpc-eabi/lin64/bin:/opt/Xilinx/14.5/ISE_DS/EDK/gnu/arm/lin/bin:/opt/Xilinx/14.5/ISE_DS/EDK/gnu/microblaze/linux_toolchain/lin64_be/bin:/opt/Xilinx/14.5/ISE_DS/EDK/gnu/microblaze/linux_toolchain/lin64_le/bin:/opt/Xilinx/14.5/ISE_DS/common/bin/lin64:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/home/jhegarty/terra-Linux-x86_64-84bbb0b/bin
echo $PATH

##################
export MODULESHOME=/afs/ir.stanford.edu/class/ee/modules/tcl
source $MODULESHOME/init/bash.in

module load base
#module load vcs
module load syn
module load icc

export ARCH_OVERRIDE=linux

# load in my symbolic libraries to prevent synopsys from complaining
export LD_LIBRARY_PATH="/home/jhegarty/synlib/:$LD_LIBRARY_PATH"
##################

cd /home/jhegarty/rigelcron
rm -Rf /home/jhegarty/rigelcron/rigel
git clone https://github.com/jameshegarty/rigel.git
cd rigel/examples
#make -j64 -k zynq20
# this needs to use less threads or it will exit due to out of memory errors
make -j32 -k zynq100 zynq20 asic || echo "SURPRESS"

# we want to fail if bitstreams were not built
make -j64 -k zynq100bits zynq20bits asic

../misc/fixbadruns.sh

# we want to fail if its still broken
make -j32 -k zynq100 zynq20 asic
