#!/bin/bash
set -ex

sudo dpkg -i https://mega.nz/linux/MEGAsync/xUbuntu_20.10/amd64/megacmd-xUbuntu_20.10_amd64.deb
mega-login ${MEGA_USER} ${MEGA_PASS}
mega-logout

for f in /dev/shm/stack-*.img; do
FILENAME=$(basename $f)
SIZE=$(du -h $f | awk '{print $1}')
data="$FILENAME-$SIZE-mega"
mega-login ${MEGA_USER} ${MEGA_PASS}
mega-put $f /boot2stack/${FILENAME}
mega-logout
curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
done
