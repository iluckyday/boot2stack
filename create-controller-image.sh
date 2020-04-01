#!/bin/bash
set -e

include_apps="systemd,systemd-sysv,sudo,bash-completion,openssh-server,tzdata,tcpdump"

export DEBIAN_FRONTEND=noninteractive
apt-config dump | grep -we Recommends -e Suggests | sed 's/1/0/' | tee /etc/apt/apt.conf.d/99norecommends
apt update
apt install -y debootstrap qemu-system-x86 qemu-utils

MNTDIR=/tmp/debian
mkdir -p ${MNTDIR}

qemu-img create -f raw /tmp/sid.raw 201G
loopx=$(losetup --show -f -P /tmp/sid.raw)
mkfs.ext4 -F -L debian-root -b 1024 -I 128 -O "^has_journal" $loopx
mount $loopx ${MNTDIR}

sed -i 's/ls -A/ls --ignore=lost+found -A/' /usr/sbin/debootstrap
/usr/sbin/debootstrap --no-check-gpg --no-check-certificate --components=main,contrib,non-free --include="$include_apps" sid ${MNTDIR}

mount -t proc none ${MNTDIR}/proc
mount -o bind /sys ${MNTDIR}/sys
mount -o bind /dev ${MNTDIR}/dev

cat << EOF > ${MNTDIR}/etc/fstab
LABEL=debian-root /          ext4    defaults,noatime              0 0
tmpfs             /tmp       tmpfs   mode=1777,size=90%            0 0
tmpfs             /var/log   tmpfs   defaults,noatime              0 0
EOF

cat << EOF > ${MNTDIR}/etc/apt/apt.conf.d/99freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

cat << EOF > ${MNTDIR}/etc/apt/apt.conf.d/99norecommend
APT::Install-Recommends "1";
APT::Install-Suggests "0";
EOF

cat << EOF > ${MNTDIR}/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-exclude /usr/lib/locale/*
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

mkdir -p ${MNTDIR}/etc/initramfs-tools/conf.d
cat << EOF > ${MNTDIR}/etc/initramfs-tools/conf.d/custom
COMPRESS=xz
RUNSIZE=50%
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

DISABLE_SERVICES="e2scrub_all.timer \
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
logrotate.service \
systemd-timesyncd.service \
openvswitch-switch.service \
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

REMOVE_APPS="ifupdown \
build-essential \
gcc-9 \
libgcc-9-dev \
g++-9 \
cpp \
cpp-9 \
iso-codes"

mkdir -p /run/systemd/network
cat << EOFF > /run/systemd/network/20-dhcp.network
[Match]
Name=en*

[Network]
DHCP=ipv4
EOFF

systemctl start systemd-networkd systemd-resolved
sleep 2
apt update
DEBIAN_FRONTEND=noninteractive apt install -y $APPS
dpkg -P --force-depends $REMOVE_APPS
systemctl disable $DISABLE_SERVICES

systemctl stop mysql etcd
rm -rf /var/lib/mysql/{ib*,*log*} /var/lib/etcd/*
rm -rf /etc/hostname /etc/resolv.conf /etc/networks /usr/share/doc /usr/share/man /var/tmp/* /var/cache/apt/*
find /usr -type d -name __pycache__ -prune -exec rm -rf {} +
find /usr/*/locale -mindepth 1 -maxdepth 1 ! -name 'en' -prune -exec rm -rf {} +
find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -prune -exec rm -rf {} +
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

dhcp_nic=$(basename /sys/class/net/en*10)
[ "$dhcp_nic" = "en*10" ] && exit

for (( n=1; n<=5; n++)); do
	dhclient -1 -4 -q $dhcp_nic || continue
	wget -qO /tmp/run.sh http://router/run.sh && break || exit
done

[ -r /tmp/run.sh ] && source /tmp/run.sh && rm -f /tmp/run.sh || exit
EOF
chmod +x ${MNTDIR}/usr/sbin/stack-init.sh

sed -i '/src/d' ${MNTDIR}/etc/apt/sources.list
( umask 226 && echo 'Defaults env_keep+="PYTHONDONTWRITEBYTECODE PYTHONHISTFILE"' > ${MNTDIR}/etc/sudoers.d/env_keep )
ln -sf /usr/share/zoneinfo/Asia/Shanghai ${MNTDIR}/etc/localtime

for i in stack-install.service stack-init.service
do
	ln -sf /etc/systemd/system/$i ${MNTDIR}/etc/systemd/system/multi-user.target.wants/$i
done

mkdir -p ${MNTDIR}/boot/syslinux
cat << EOF > ${MNTDIR}/boot/syslinux/syslinux.cfg
PROMPT 0
TIMEOUT 0
DEFAULT debian

LABEL debian
        LINUX /vmlinuz
        INITRD /initrd.img
        APPEND root=LABEL=debian-root console=ttyS0 quiet
EOF

chroot ${MNTDIR} /bin/bash -c "
export PATH=/bin:/sbin:/usr/bin:/usr/sbin PYTHONDONTWRITEBYTECODE=1 DEBIAN_FRONTEND=noninteractive
sed -i 's/root:\*:/root::/' etc/shadow
apt update
apt install -y -o APT::Install-Recommends=0 -o APT::Install-Suggests=0 linux-image-cloud-amd64 extlinux initramfs-tools
dd if=/usr/lib/EXTLINUX/mbr.bin of=$loopx
extlinux -i /boot/syslinux

sed -i '/src/d' /etc/apt/sources.list
rm -rf /tmp/* /var/tmp/* /var/log/* /var/cache/apt/* /var/lib/apt/lists/*
"

sync ${MNTDIR}
sleep 1
umount ${MNTDIR}/dev ${MNTDIR}/proc ${MNTDIR}/sys
umount ${MNTDIR}
sleep 1
losetup -d $loopx

qemu-system-x86_64 -name stack-c-building -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 4G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=/tmp/sid.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

qemu-img convert -c -f raw -O qcow2 /tmp/sid.raw /dev/shm/stack-c.img
ls -lh /dev/shm/stack-c.img

exit 0
