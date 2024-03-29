#!/bin/bash
set -e

ffsend_ver="$(curl -skL https://api.github.com/repos/timvisee/ffsend/releases/latest | grep -oP '"tag_name": "\
curl -skL -o /tmp/ffsend https://github.com/timvisee/ffsend/releases/download/"$ffsend_ver"/ffsend-"$ffsend_ver"-linux-x64-static
chmod +x /tmp/ffsend

for f in /dev/shm/stack-*.img; do
        SIZE="$(du -h $f | awk '{print $1}')"
        FFSEND_URL=$(/tmp/ffsend -Ifyq upload $f)
        FILE=$(basename $f)
        data="$FILE-$SIZE-${FFSEND_URL}"
        echo $data
        curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data/\
done
