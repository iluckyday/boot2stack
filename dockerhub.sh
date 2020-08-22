#!/bin/bash
set -e

user="$DOCKERHUB_USER"
image=temp

for f in /dev/shm/stack-*.img; do
        filename="$(basename $f)"
        filepath="$(dirname $f)"

        tag="${filename}_$(date '+%Y%m%d')"
        tag_latest="${filename}_latest"
        cd $filepath
        tar -c $filename | docker import - ${user}/${image}:${tag}
        docker tag ${user}/${image}:${tag} ${user}/${image}:${tag_latest}
        echo "$DOCKERHUB_PASS" | docker login -u "$user" --password-stdin
        docker push ${user}/${image}:${tag}
        docker push ${user}/${image}:${tag_latest}
        docker logout
done
