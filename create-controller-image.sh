#!/bin/bash
set -e

WORKDIR=/tmp/stack
MNTDIR=$WORKDIR/mntc
mkdir -p ${MNTDIR}
cd $WORKDIR

mv disk.raw c.raw
qemu-img resize -f raw c.raw 203G
loopx=$(losetup --show -f -P c.raw)
sgdisk -d 1 $loopx
sgdisk -N 0 $loopx
resize2fs -f ${loopx}p1
tune2fs -O '^has_journal' ${loopx}p1
mount ${loopx}p1 ${MNTDIR}
sleep 1

cat << EOF >> ${MNTDIR}/etc/fstab
tmpfs             /tmp       tmpfs   mode=1777,size=90%            0 0
tmpfs             /var/log   tmpfs   defautls,noatime              0 0
EOF

mkdir -p ${MNTDIR}/root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp" >> ${MNTDIR}/root/.ssh/authorized_keys
chmod 600 ${MNTDIR}/root/.ssh/authorized_keys

mkdir -p ${MNTDIR}/etc/apt/apt.conf.d
cat << EOF > ${MNTDIR}/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

mkdir -p ${MNTDIR}/etc/dpkg/dpkg.cfg.d
cat << EOF > ${MNTDIR}/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
EOF

mkdir -p ${MNTDIR}/etc/systemd/journald.conf.d
cat << EOF > ${MNTDIR}/etc/systemd/journald.conf.d/storage.conf
[Journal]
Storage=volatile
EOF

mkdir -p ${MNTDIR}/etc/systemd/system-environment-generators
cat << EOF > ${MNTDIR}/etc/systemd/system-environment-generators/20-python
#!/bin/bash
echo 'PYTHONDONTWRITEBYTECODE=1'
echo 'PYTHONHISTFILE=/dev/null'
EOF
chmod +x ${MNTDIR}/etc/systemd/system-environment-generators/20-python

cat << EOF > ${MNTDIR}/etc/profile.d/python.sh
#!/bin/bash
export PYTHONDONTWRITEBYTECODE=1 PYTHONHISTFILE=/dev/null
EOF

cat << EOF > ${MNTDIR}/etc/pip.conf
[global]
download-cache=/tmp
cache-dir=/tmp
EOF

cat << EOF > ${MNTDIR}/etc/initramfs-tools/conf.d/custom
COMPRESS=xz
RUNSIZE=50%
EOF

cat << EOF > ${MNTDIR}/root/.bashrc
export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null
EOF

cat << "EOF" > ${MNTDIR}/usr/sbin/stack-install.sh
#!/bin/bash
set -ex

APPS="mariadb-server python3-pymysql \
rabbitmq-server \
memcached python3-memcache \
etcd \
apache2 libapache2-mod-wsgi \
python3-openstackclient \
keystone \
glance \
placement-api \
nova-api nova-conductor nova-novncproxy nova-scheduler \
neutron-server neutron-linuxbridge-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent"

DISABLE_SERVICES="systemd-timesyncd.service openvswitch-switch.service\
mysql.service mariadb.service \
keepalived.service haproxy.service \
memcached.service \
rabbitmq-server.service \
etcd.service \
apache2.service \
keystone.service \
glance-api.service \
nova-api-metadata.service nova-api.service nova-conductor.service nova-novncproxy.service nova-scheduler.service nova-serialproxy.service nova-spicehtml5proxy.service nova-xenvncproxy.service \
neutron-api.service neutron-dhcp-agent.service neutron-l3-agent.service neutron-linuxbridge-agent.service neutron-metadata-agent.service neutron-rpc-server.service \
placement-api.service"

MASK_SERVICES="e2scrub_all.timer \
apt-daily-upgrade.timer \
apt-daily.timer \
logrotate.timer \
man-db.timer \
fstrim.timer \
apparmor.service \
e2scrub@.service \
e2scrub_all.service \
e2scrub_fail@.service \
e2scrub_reap.service \
logrotate.service"

REMOVE_APPS="chrony ifupdown vim unattended-upgrades \
build-essential \
gcc-9 \
libgcc-9-dev \
g++-9 \
cpp \
cpp-9 \
iso-codes"

DELETE_MODULES="
fs/udf
fs/adfs
fs/affs
fs/ocfs2
fs/jfs
fs/ubifs
fs/gfs2
fs/cifs
fs/befs
fs/erofs
fs/hpfs
fs/f2fs
fs/xfs
fs/freevxfs
fs/hfsplus
fs/minix
fs/coda
fs/dlm
fs/afs
fs/omfs
fs/9p
fs/reiserfs
fs/bfs
fs/qnx6
fs/nilfs2
fs/btrfs
fs/jbd2
fs/efs
fs/ceph
fs/hfs
fs/jffs2
fs/orangefs
fs/ufs
net/wireless
net/mpls
net/wimax
net/l2tp
net/nfc
net/tipc
net/appletalk
net/rds
net/dccp
net/netrom
net/lapb
net/mac80211
net/6lowpan
net/sunrpc
net/rxrpc
net/atm
net/psample
net/rose
net/ax25
net/8021q
net/9p
net/bluetooth
net/ife
net/ceph
net/phonet
drivers/media
drivers/mfd
drivers/hid
drivers/nfc
drivers/dca
drivers/thunderbolt
drivers/firmware
drivers/xen
drivers/spi
drivers/i2c
drivers/uio
drivers/hv
drivers/ptp
drivers/pcmcia
drivers/isdn
drivers/atm
drivers/w1
drivers/hwmon
drivers/virt
drivers/dax
drivers/parport
drivers/ssb
drivers/infiniband
drivers/gpu
drivers/bluetooth
drivers/video
drivers/android
drivers/nvme
drivers/gnss
drivers/firewire
drivers/leds
drivers/net/fddi
drivers/net/hyperv
drivers/net/xen-netback
drivers/net/wireless
drivers/net/ipvlan
drivers/net/slip
drivers/net/usb
drivers/net/team
drivers/net/ppp
drivers/net/bonding
drivers/net/can
drivers/net/phy
drivers/net/vmxnet3
drivers/net/ieee802154
drivers/net/fjes
drivers/net/hippi
drivers/net/wan
drivers/net/plip
drivers/net/appletalk
drivers/net/wimax
drivers/net/arcnet
drivers/net/hamradio
sound
"

apt update
DEBIAN_FRONTEND=noninteractive apt install -y $APPS
apt remove --purge -y $REMOVE_APPS
systemctl disable $DISABLE_SERVICES
systemctl mask $MASK_SERVICES

rm -rf /etc/hostname /etc/resolv.conf /etc/network /usr/share/doc /usr/share/man /tmp/* /var/log/* /var/tmp/* /var/cache/apt/*
find /usr -type d -name __pycache__ -prune -exec rm -rf {} + || true
find /usr/*/locale -mindepth 1 -maxdepth 1 ! -name 'en' -prune -exec rm -rf {} + || true
find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -prune -exec rm -rf {} + || true
for m in $DELETE_MODULES; do
	rm -rf /lib/modules/*/kernel/$m
done
EOF
chmod +x ${MNTDIR}/usr/sbin/stack-install.sh

cat << "EOF" > ${MNTDIR}/etc/systemd/system/stack-install.service
[Unit]
Description=stack install script
After=network.target
SuccessAction=poweroff-force

[Service]
Type=oneshot
StandardOutput=journal+console
ExecStart=/usr/sbin/stack-install.sh
ExecStartPost=/bin/rm -f /etc/systemd/system/stack-install.service /etc/systemd/system/multi-user.target.wants/stack-install.service /usr/sbin/stack-install.sh
EOF

cat << EOF > ${MNTDIR}/etc/systemd/system/stack-init.service
[Unit]
Description=stack init script
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/stack-init.sh
RemainAfterExit=true
EOF

cat << "EOF" > ${MNTDIR}/usr/sbin/stack-init.sh
#!/bin/bash
set -ex

dhcp_nic=$(basename /sys/class/net/en*20)
[ "$dhcp_nic" = "en*20" ] && exit

for (( n=1; n<=5; n++)); do
	dhclient -1 -4 -q $dhcp_nic || continue
	curl -skLo /tmp/run.sh http://router/run.sh && break || exit
done

[ -r /tmp/run.sh ] && source /tmp/run.sh && rm -f /tmp/run.sh || exit
EOF
chmod +x ${MNTDIR}/usr/sbin/stack-init.sh

sed -i '/src/d' ${MNTDIR}/etc/apt/sources.list
sed -i 's/timeout=5/timeout=0/' ${MNTDIR}/boot/grub/grub.cfg
( umask 226 && echo 'Defaults env_keep+="PYTHONDONTWRITEBYTECODE PYTHONHISTFILE"' > ${MNTDIR}/etc/sudoers.d/env_keep )
ln -sf ../usr/share/zoneinfo/Asia/Shanghai /etc/localtime

for i in stack-install.service stack-init.service
do
	ln -sf /etc/systemd/system/$i ${MNTDIR}/etc/systemd/system/multi-user.target.wants/$i
done

chroot ${MNTDIR} ssh-keygen -A
sync ${MNTDIR}
sleep 1
umount ${MNTDIR}
sleep 1
losetup -d $loopx

qemu-system-x86_64 -name stack-c-building -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 8G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=$WORKDIR/c.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0
qemu-img convert -f raw -O qcow2 $WORKDIR/c.raw /dev/shm/stack-c.img

ls -lh /dev/shm/stack-c.img
