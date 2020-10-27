#!/bin/bash
set -ex

sudo apt update
sudo apt install -y libcrypto++-dev libz-dev libsqlite3-dev libssl-dev libcurl4-gnutls-dev libreadline-dev libpcre++-dev libsodium-dev libc-ares-dev libfreeimage-dev libavcodec-dev libavutil-dev libavformat-dev libswscale-dev libmediainfo-dev libzen-dev libuv1-dev

git clone https://github.com/meganz/MEGAcmd.git
cd MEGAcmd && git submodule update --init --recursive
sh autogen.sh
./configure
make -j 2
sudo make install
sudo ldconfig

mega-login "${MEGA_USER}" "${MEGA_PASS}"

for f in /dev/shm/stack-*.img; do
FILENAME=$(basename $f)
DATE=$(date "+%Y%m%d%H%M%S")
SIZE=$(du -h $f | awk '{print $1}')
data="$FILENAME-$SIZE-mega"
mega-put -c $f /boot2stack/"${FILENAME}.${DATE}"
curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
done

mega-logout
