#!/bin/bash
set -e

include_apps="systemd,systemd-sysv,sudo,bash-completion,openssh-server,tcpdump,isc-dhcp-client,busybox"

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
/usr/sbin/debootstrap --no-check-gpg --no-check-certificate --components=main,contrib,non-free --include="$include_apps" --variant minbase sid ${MNTDIR}

mount -t proc none ${MNTDIR}/proc
mount -o bind /sys ${MNTDIR}/sys
mount -o bind /dev ${MNTDIR}/dev

cat << EOF > ${MNTDIR}/etc/fstab
LABEL=debian-root /          ext4    defaults,noatime              0 0
tmpfs             /run       tmpfs   defaults,size=50%             0 0
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
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOF

cat << EOF > ${MNTDIR}/etc/dpkg/dpkg.cfg.d/99nofiles
path-exclude *__pycache__*
path-exclude *.py[co]
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/bug/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-exclude /usr/lib/locale/*
path-include /usr/share/locale/en*
path-exclude /usr/include/*
path-exclude /usr/lib/x86_64-linux-gnu/perl/*/auto/Encode/CN*
path-exclude /usr/lib/x86_64-linux-gnu/perl/*/auto/Encode/JP*
path-exclude /usr/lib/x86_64-linux-gnu/perl/*/auto/Encode/KR*
path-exclude /usr/lib/x86_64-linux-gnu/perl/*/auto/Encode/TW*
path-exclude *bin/perror
path-exclude *bin/mysqlslap
path-exclude *bin/mysqlbinlog
path-exclude *bin/x86_64-linux-gnu-dwp
path-exclude *bin/mysql_embedded
path-exclude *bin/systemd-analyze
path-exclude *bin/resolve_stack_dump
path-exclude *bin/mysql_tzinfo_to_sql
path-exclude *bin/sqldiff
path-exclude *bin/etcdctl
path-exclude *bin/myisamlog
path-exclude *bin/mysqldump
path-exclude *bin/aria_dump_log
path-exclude *bin/mysqlimport
path-exclude *bin/pdata_tools
path-exclude *bin/aria_ftdump
path-exclude *bin/aria_read_log
path-exclude *bin/myisam_ftdump
path-exclude /usr/lib/x86_64-linux-gnu/ceph*
path-exclude /usr/lib/x86_64-linux-gnu/libicudata.a
path-exclude /lib/modules/*/kernel/drivers/net/ethernet*
path-exclude /usr/share/python-babel-localedata/locale-data*
path-exclude /boot/System.map*
path-exclude /lib/modules/*/fs/ceph*
path-exclude /lib/modules/*/sound*
EOF

mkdir -p ${MNTDIR}/etc/systemd/system-environment-generators
cat << EOF > ${MNTDIR}/etc/systemd/system-environment-generators/20-python
#!/bin/sh
echo 'PYTHONDONTWRITEBYTECODE=1'
echo 'PYTHONSTARTUP=/usr/lib/pythonstartup'
EOF
chmod +x ${MNTDIR}/etc/systemd/system-environment-generators/20-python

cat << EOF > ${MNTDIR}/etc/profile.d/python.sh
#!/bin/sh
export PYTHONDONTWRITEBYTECODE=1 PYTHONSTARTUP=/usr/lib/pythonstartup
EOF

cat << EOF > ${MNTDIR}/usr/lib/pythonstartup
import readline
import time

readline.add_history("# " + time.asctime())
readline.set_history_length(-1)
EOF

cat << EOF > ${MNTDIR}/etc/pip.conf
[global]
download-cache=/tmp
cache-dir=/tmp
EOF

mkdir -p ${MNTDIR}/etc/initramfs-tools/conf.d
cat << EOF > ${MNTDIR}/etc/initramfs-tools/conf.d/custom
#MODULES=dep
COMPRESS=xz
EOF

cat << "EOF" > ${MNTDIR}/usr/sbin/stack-install.sh
#!/bin/bash
set -ex

APPS="python3-systemd \
mariadb-server python3-pymysql \
rabbitmq-server \
memcached python3-memcache \
etcd \
python3-openstackclient \
keystone \
glance \
placement-api \
nova-api nova-conductor nova-novncproxy nova-scheduler \
neutron-server neutron-openvswitch-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent ironic-neutron-agent \
swift swift-proxy \
cinder-api cinder-scheduler \
ironic-api ironic-conductor python3-ironicclient syslinux-common pxelinux ipxe \
manila-api manila-scheduler python3-manilaclient \
barbican-api barbican-keystone-listener barbican-worker \
senlin-api senlin-engine python3-senlinclient \
designate bind9 bind9utils designate-worker designate-producer designate-mdns"

DISABLE_SERVICES="e2scrub_all.timer \
apt-daily-upgrade.timer \
apt-daily.timer \
logrotate.timer \
man-db.timer \
fstrim.timer \
apparmor.service \
cron.service \
rsyslog.service \
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
placement-api.service \
nova-api-metadata.service nova-api.service nova-conductor.service nova-novncproxy.service nova-scheduler.service nova-serialproxy.service nova-spicehtml5proxy.service nova-xenvncproxy.service \
neutron-api.service neutron-dhcp-agent.service neutron-l3-agent.service neutron-openvswitch-agent.service neutron-metadata-agent.service neutron-rpc-server.service ironic_neutron_agent.service \
rsync.service \
swift-proxy.service \
cinder-api.service cinder-scheduler.service \
ironic-api.service ironic-conductor.service ironic-neutron-agent.service xinetd.service \
manila-api.service manila-scheduler.service \
barbican-api.service barbican-keystone-listener.service barbican-worker.service \
senlin-api.service senlin-engine.service \
designate-central.service designate-api.service designate-worker.service designate-producer.service designate-mdns.service"

REMOVE_APPS="tzdata"

mkdir -p /run/systemd/network
cat << EOFF > /run/systemd/network/20-dhcp.network
[Match]
Name=en*

[Network]
DHCP=ipv4
EOFF

systemctl start systemd-networkd systemd-resolved
sleep 2

rm -f /var/lib/dpkg/info/libc-bin.postinst /var/lib/dpkg/info/man-db.postinst /var/lib/dpkg/info/dbus.postinst /var/lib/dpkg/info/initramfs-tools.postinst

apt update
DEBIAN_FRONTEND=noninteractive apt install -y $APPS

cat /var/log/nova/*

dpkg -P --force-depends $REMOVE_APPS
systemctl disable $DISABLE_SERVICES

pip install websocket-client

systemctl stop mysql etcd rabbitmq-server
sleep 5
rm -rf /var/lib/mysql/{ib*,*log*} /var/lib/etcd/* /var/lib/rabbitmq/*
rm -rf /etc/hostname /etc/resolv.conf /etc/networks /usr/share/doc /usr/share/man /var/lib/*/*.sqlite /var/lib/openvswitch/conf.db
rm -rf /usr/bin/systemd-analyze /usr/bin/perl*.* /usr/bin/sqlite3 /usr/share/misc/pci.ids /usr/share/mysql /usr/share/ieee-data /usr/share/sphinx /usr/share/python-wheels /usr/share/fonts/truetype /usr/lib/udev/hwdb.d /usr/lib/udev/hwdb.bin
find /usr -type d -name __pycache__ -prune -exec rm -rf {} +
find /usr -type d -name tests -prune -exec rm -rf {} +
find /usr/*/locale -mindepth 1 -maxdepth 1 ! -name 'en' -prune -exec rm -rf {} +
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
ExecStartPost=/bin/rm -f /etc/systemd/system/stack-init.service /etc/systemd/system/multi-user.target.wants/stack-init.service /usr/sbin/stack-init.sh
RemainAfterExit=true
EOF

cat << "EOF" > ${MNTDIR}/usr/sbin/stack-init.sh
#!/bin/bash
set -ex

dhcp_nic=$(basename /sys/class/net/en*10)
[ "$dhcp_nic" = "en*10" ] && exit 1

for (( n=1; n<=5; n++)); do
	dhclient -1 -4 -q $dhcp_nic || continue
	wget -qO /tmp/run.sh http://router/run.sh && break || exit 1
done

[ -r /tmp/run.sh ] && source /tmp/run.sh && rm -f /tmp/run.sh || exit 1
EOF
chmod +x ${MNTDIR}/usr/sbin/stack-init.sh

sed -i '/src/d' ${MNTDIR}/etc/apt/sources.list
( umask 226 && echo 'Defaults env_keep+="PYTHONDONTWRITEBYTECODE PYTHONHISTFILE"' > ${MNTDIR}/etc/sudoers.d/env_keep )

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
sed -i 's/root:\*:/root::/' /etc/shadow
apt update
apt install -y -o APT::Install-Recommends=0 -o APT::Install-Suggests=0 linux-image-cloud-amd64 extlinux initramfs-tools
#apt install -y -o APT::Install-Recommends=0 -o APT::Install-Suggests=0 linux-image-amd64 extlinux initramfs-tools
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

#qemu-system-x86_64 -name stack-c-building -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 4G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=/tmp/sid.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0
qemu-system-x86_64 -name stack-c-building -machine q35,accel=kvm:xen:hax:hvf:whpx:tcg -smp "$(nproc)" -m 5G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=/tmp/sid.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

sleep 2

qemu-img convert -c -f raw -O qcow2 /tmp/sid.raw /dev/shm/stack-c.img

exit 0
