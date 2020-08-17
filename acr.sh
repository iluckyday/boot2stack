#!/bin/bash
set -e

region=us-west-1
namespace=iimage
tag=$(date '+%Y%m%d')

for f in /dev/shm/stack-*.img; do
        filename="$(basename $f)"
        filepath="$(dirname $f)"

        image="$filename:$tag"
        cd $filepath
        tar -c $filename | docker import - registry.${region}.aliyuncs.com/${namespace}/${image}
        echo "$ACR_DOCKER_PASSWORD" | docker login -u "$ACR_DOCKER_USERNAME" --password-stdin registry.${region}.aliyuncs.com
        docker push registry.${region}.aliyuncs.com/${namespace}/${image}
        docker logout registry.${region}.aliyuncs.com
done
