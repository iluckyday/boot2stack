#!/bin/bash
set -ex

ngrok_run () {
echo "travis:travis" | sudo chpasswd
curl -skL -o /tmp/ngrok.zip https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip
unzip -d /tmp /tmp/ngrok.zip
chmod +x /tmp/ngrok
/tmp/ngrok authtoken $NGROK_TOKEN
/tmp/ngrok tcp 22 --log stdout --log-level debug
}

#ngrok_run

git clone https://github.com/meganz/MEGAcmd.git
cd MEGAcmd && git submodule update --init --recursive
sh autogen.sh
./configure
make
sudo make install
sudo ldconfig

mega-login "${MEGA_USER}" "${MEGA_PASS3}"

for f in /dev/shm/stack-*.img; do
FILENAME=$(basename $f)
SIZE=$(du -h $f | awk '{print $1}')
data="$FILENAME-$SIZE-mega"
mega-login "${MEGA_USER}" "${MEGA_PASS}"
mega-put $f /boot2stack/${FILENAME}
mega-logout
curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
done
