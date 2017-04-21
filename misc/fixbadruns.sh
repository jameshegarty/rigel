#!/bin/sh

#make -j32 -k zynq100  || echo "SURPRESS"

#make -j32 zynq100bits 

for i in `seq 1 4`;
do

echo "ROUND"
echo $i

for f in out/*.zynq100.raw;
do
echo $f | sed "s/raw/correct.txt/" | xargs test ! -e && echo $f && rm $f
done

for f in out/*.zynq100.bmp;
do
echo $f | sed "s/bmp/correct.txt/" | xargs test ! -e && echo $f && rm $f
done

for f in out/*.axi.raw;
do
echo $f | sed "s/raw/correct.txt/" | xargs test ! -e && echo $f && rm $f
done

for f in out/*.axi.bmp;
do
echo $f | sed "s/bmp/correct.txt/" | xargs test ! -e && echo $f && rm $f
done

make -k zynq100 zynq20

done
