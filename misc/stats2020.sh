#!/bin/sh

echo "usage: examplename"

examplename=$1
SOC=$2
output=out/$examplename.zu9vivado$SOC.stats2020.txt
examplepath=out/$examplename

#format: | file | design | designT | dataset | image_size |   clock | expected_cycles | sim_cycles | axi_cycles | CLBs | DSPs | BRAMs | slices | fifo_size | extra |


printf "| " > $output
printf $examplename >> $output
printf "| " >> $output
cat $examplepath.design.txt  >> $output
printf "| " >> $output
cat $examplepath.designT.txt  >> $output
printf "| " >> $output
cat $examplepath.dataset.txt  >> $output
printf "| " >> $output
#identify -ping -format '%[fx:w*h]' $examplepath.$axiname.bmp >> $output
printf "0 " >> $output
printf "| " >> $output
# clock
../rigelLuajit ../misc/extractMetadata.lua $examplepath.metadata.lua MHz |  tr -d '\n' >> $output
printf "| " >> $output
#expected cycles
printf "0 " >> $output
printf "| " >> $output
#simcycles
cat $examplepath.verilator$SOC.cycles.txt  >> $output
printf "| " >> $output
# axi cycles
printf "0 " >> $output
printf "| " >> $output
cat $examplepath.zu9vivado$SOC.clbs.txt  >> $output
printf "| " >> $output
cat $examplepath.zu9vivado$SOC.dsps.txt  >> $output
printf "| " >> $output
cat $examplepath.zu9vivado$SOC.brams.txt  >> $output
printf "| " >> $output
#slices
printf "0 " >> $output
printf "| " >> $output
# fifo_size
printf "0 " >> $output
printf "| " >> $output
# extra
echo "0 " >> $output

