#!/bin/bash
set -e

user="$DOCKERHUB_USER"
image=temp

for f in /dev/shm/stack-*.img; do
        filename="$(basename $f)"
        filepath="$(dirname $f)"
        SIZE=$(du -h $f | awk '{print $1}')

        tag="${filename}_$(date '+%Y%m%d')"
        tag_latest="${filename}_latest"
        cd $filepath
        tar -c $filename | docker import - ${user}/${image}:${tag}
        docker tag ${user}/${image}:${tag} ${user}/${image}:${tag_latest}
        echo "$DOCKERHUB_PASS" | docker login -u "$user" --password-stdin
        docker push ${user}/${image}:${tag}
        docker push ${user}/${image}:${tag_latest}
        docker logout
        data="$user-$image-$tag-$SIZE"
        curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
done
