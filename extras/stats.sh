#!/bin/sh

echo "usage: builddir examplepath examplename axicyclespath output"
echo "eg: out/build100_pointwise out/pointwise pointwise axi100 out/pointwise.stats.txt"

builddir=$1
examplepath=$2
examplename=$3
axiname=$4
output=$5

printf $examplename > $output
printf ", " >> $output
printf $axiname >> $output
printf ", " >> $output
grep Slices $builddir/OUT_par.txt | grep -P -o "[0-9]+" | head -1 | tr -d '\n' >> $output
printf ", " >> $output
grep Maximum $builddir/OUT_trce.txt  | grep -P -o "[0-9.]+" | tail -1 | tr -d '\n' >> $output
printf ", " >> $output
cat $examplepath.cycles.txt >> $output
printf ", " >> $output
cat $examplepath.sim.cycles.txt  >> $output
printf ", " >> $output
cat $examplepath.$axiname.cycles.txt >> $output
printf ", " >> $output
identify -ping -format '%[fx:w*h]' $examplepath.$axiname.bmp >> $output
printf ", " >> $output
cat $examplepath.design.txt  >> $output
printf ", " >> $output
cat $examplepath.designT.txt  >> $output
