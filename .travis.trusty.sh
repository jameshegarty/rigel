#!/bin/sh

apt-get install luajit
apt-get install verilator
wget https://github.com/zdevito/terra/releases/download/release-2016-02-26/terra-Linux-x86_64-2fa8d0a.zip
unzip terra-Linux-x86_64-2fa8d0a.zip
ln -s /home/travis/build/jameshegarty/rigel/terra-Linux-x86_64-2fa8d0a/bin/terra /usr/bin/terra
