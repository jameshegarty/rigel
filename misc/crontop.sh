#!/bin/sh

cd /home/jhegarty/rigelcron

DATE=`date +%Y-%m-%d-time-%H-%M`

if /home/jhegarty/rigel/misc/cron.sh > $DATE.txt 2>&1; then
  echo "OK"
  mv $DATE.txt $DATE.ok.txt
  git add $DATE.ok.txt
else
  echo "FAIL"
  mv $DATE.txt $DATE.fail.txt
  git add $DATE.fail.txt
fi

git commit -m "build status"
git push
