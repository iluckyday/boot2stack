#!/bin/bash
set -e

for f in /dev/shm/stack-*.img; do
        SIZE="$(du -h $f | awk '{print $1}')"
        TRANSFER_URL=$(curl -skT $f https://transfer.sh)
        FILE=$(basename $f)
        data="$FILE-$SIZE-${TRANSFER_URL}"
        echo $data
        curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
done
