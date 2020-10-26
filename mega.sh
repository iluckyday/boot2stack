#!/bin/bash
set -ex

sudo apt update
sudo apt install -y megatools

for f in /dev/shm/stack-*.img; do
FILENAME=$(basename $f)
SIZE=$(du -h $f | awk '{print $1}')
data="$FILENAME-$SIZE-mega"
megaput -u ${MEGA_USER} -p ${MEGA_PASS} --no-ask-password --path /Root/boot2stack/${FILENAME} $f
curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
done
