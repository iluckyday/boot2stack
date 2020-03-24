#!/bin/bash
set -ex

mkdir -p /tmp/stack && cd /tmp/stack
version=$(curl -skL https://cloud.debian.org/images/cloud/sid/daily | awk '/href/ {s=$0} END {print s}' | awk -F'"' '{sub(/\//,"",$2);print $2}')
curl -skL https://cloud.debian.org/images/cloud/sid/daily/${version}/debian-sid-nocloud-amd64-daily-${version}.tar.xz | tar -xJ
