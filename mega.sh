#!/bin/bash
set -ex

git clone https://github.com/meganz/MEGAcmd.git
cd MEGAcmd && git submodule update --init --recursive
sh autogen.sh
./configure
make
sudo make install
sudo ldconfig

mega-login "${MEGA_USER}" "${MEGA_PASS}"

for f in /dev/shm/stack-*.img; do
FILENAME=$(basename $f)
SIZE=$(du -h $f | awk '{print $1}')
data="$FILENAME-$SIZE-mega"
mega-put $f /boot2stack/${FILENAME}
curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
done

mega-logout
