#!/bin/sh

cd /home/jhegarty/rigelcron

DATE=`date +%Y-%m-%d`

if /home/jhegarty/rigel/misc/cron.sh > $DATE.txt 2>&1; then
  echo "OK"
  mv $DATE.txt $DATE.ok.txt
else
  echo "FAIL"
  mv $DATE.txt $DATE.fail.txt
fi
