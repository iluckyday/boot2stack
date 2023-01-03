#!/bin/bash
set -x

sudo apt update
sudo apt install -y rclone

for f in /dev/shm/stack-*.img; do
FILENAME=$(basename $f)
DATE=$(date "+%Y%m%d%H%M%S")
SIZE=$(du -h $f | awk '{print $1}')
data="$FILENAME-$SIZE-mega"
rclone copy $f mega:/boot2stack/"${FILENAME}.${DATE}"
curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
done
