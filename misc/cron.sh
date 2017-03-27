#!/bin/sh

# 00 00 * * * /home/jhegarty/misc/crontop.sh

# exit early if any errors
set -e

cd /home/jhegarty/rigelcron
rm -Rf /home/jhegarty/rigelcron/rigel
git clone https://github.com/jameshegarty/rigel.git
cd rigel/examples
make -j64 axibits
make axi
