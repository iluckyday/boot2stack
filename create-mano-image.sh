#!/bin/bash
set -x

release=$(curl -sSkL https://www.debian.org/releases/ | grep -oP 'codenamed <em>\K(.*)(?=</em>)')
release="sid"
include_apps="systemd,systemd-resolved,dbus,systemd-sysv,sudo,openssh-server,wget,xz-utils,parallel,busybox"
include_apps+=",linux-image-cloud-amd64,extlinux,initramfs-tools"

export DEBIAN_FRONTEND=noninteractive
apt-config dump | grep -we Recommends -e Suggests | sed 's/1/0/' | tee /etc/apt/apt.conf.d/99norecommends
apt update
apt install -y debootstrap qemu-system-x86 qemu-utils

MNTDIR=/tmp/debian
mkdir -p ${MNTDIR}

qemu-img create -f raw /tmp/debian.raw 5G
loopx=$(losetup --show -f -P /tmp/debian.raw)
mkfs.ext4 -F -L debian-root -b 1024 -I 128 -O "^has_journal" $loopx
mount $loopx ${MNTDIR}

sed -i 's/ls -A/ls --ignore=lost+found -A/' /usr/sbin/debootstrap
/usr/sbin/debootstrap --no-check-gpg --no-check-certificate --components=main,contrib,non-free --include="$include_apps" ${release} ${MNTDIR}

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
path-exclude /usr/lib/x86_64-linux-gnu/perl/*/auto/Encode/CN*
path-exclude /usr/lib/x86_64-linux-gnu/perl/*/auto/Encode/JP*
path-exclude /usr/lib/x86_64-linux-gnu/perl/*/auto/Encode/KR*
path-exclude /usr/lib/x86_64-linux-gnu/perl/*/auto/Encode/TW*
path-exclude *bin/x86_64-linux-gnu-dwp
path-exclude /usr/lib/x86_64-linux-gnu/ceph*
path-exclude /usr/lib/x86_64-linux-gnu/libicudata.a
path-exclude /lib/modules/*/kernel/drivers/net/ethernet*
path-exclude /usr/share/python-babel-localedata/locale-data*
path-exclude /boot/System.map*
path-exclude /lib/modules/*/fs/ceph*
path-exclude /lib/modules/*/sound*
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
echo 'PYTHONSTARTUP=/usr/lib/pythonstartup'
EOF
chmod +x ${MNTDIR}/etc/systemd/system-environment-generators/20-python

cat << EOF > ${MNTDIR}/etc/profile.d/python.sh
#!/bin/bash
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
COMPRESS=xz
EOF

cat << "EOF" > ${MNTDIR}/usr/sbin/stack-install.sh
#!/bin/bash
set -x
APPS="git python3-pip build-essential python3-dev python3-memcache python3-systemd \
swift swift-proxy \
cinder-api cinder-scheduler \
barbican-api barbican-keystone-listener barbican-worker \
mistral-api mistral-engine mistral-event-engine mistral-executor \
ironic-api ironic-conductor python3-ironicclient syslinux-common pxelinux ipxe \
manila-api manila-scheduler python3-manilaclient \
senlin-api senlin-engine python3-senlinclient \
designate bind9 bind9utils designate-worker designate-producer designate-mdns \
vitrage-api vitrage-collector vitrage-graph vitrage-ml vitrage-notifier vitrage-persistor vitrage-snmp-parsing \
masakari-api masakari-engine \
heat-api heat-api-cfn heat-engine \
aodh-api aodh-evaluator aodh-notifier aodh-listener aodh-expirer \
magnum-api magnum-conductor \
"
#octavia

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
named.service \
bind9.service \
rsync.service \
swift-proxy.service \
cinder-api.service cinder-scheduler.service \
ironic-api.service ironic-conductor.service ironic-neutron-agent.service xinetd.service \
manila-api.service manila-scheduler.service \
barbican-api.service barbican-keystone-listener.service barbican-worker.service \
senlin-api.service senlin-engine.service \
designate-central.service designate-api.service designate-worker.service designate-producer.service designate-mdns.service \
mistral-api.service mistral-engine.service mistral-event-engine.service mistral-executor.service \
vitrage-api.service vitrage-collector.service vitrage-graph.service vitrage-ml.service vitrage-notifier.service vitrage-persistor.service vitrage-snmp-parsing.service \
masakari-api.service masakari-engine.service \
heat-api.service heat-api-cfn.service heat-engine.service \
aodh-api.service aodh-evaluator.service aodh-notifier.service aodh-listener.service aodh-expirer.service \
magnum-api.service magnum-conductor.service \
"

MASK_SERVICES="sysstat-collect.timer \
apt-daily-upgrade.timer \
apt-daily.timer \
dpkg-db-backup.timer \
sysstat-summary.timer \
e2scrub_all.timer \
fstrim.timer \
logrotate.timer \
"

STOP_SERVICES="e2scrub_all.timer \
apt-daily-upgrade.timer \
apt-daily.timer \
logrotate.timer \
man-db.timer \
fstrim.timer \
apparmor.service \
cron.service \
e2scrub@.service \
e2scrub_all.service \
e2scrub_fail@.service \
e2scrub_reap.service \
logrotate.service \
systemd-timesyncd.service \
"

STOP_APPS_SERVICES="
cinder-api=cinder-api.service
cinder-scheduler=cinder-scheduler.service
ironic-api=ironic-api.service
ironic-conductor=ironic-conductor.service
ironic-neutron-agent=ironic-neutron-agent.service
manila-api=manila-api.service
manila-scheduler=manila-scheduler.service
barbican-api=barbican-api.service
barbican-keystone-listener=barbican-keystone-listener.service
barbican-worker=barbican-worker.service
senlin-api=senlin-api.service
senlin-engine=senlin-engine.service
designate-central=designate-central.service
designate-api=designate-api.service
designate-worker=designate-worker.service
designate-producer=designate-producer.service
designate-mdns=designate-mdns.service
mistral-api=mistral-api.service
mistral-engine=mistral-engine.service
mistral-event-engine=mistral-event-engine.service
mistral-executor=mistral-executor.service
vitrage-api=vitrage-api.service
vitrage-collector=vitrage-collector.service
vitrage-graph=vitrage-graph.service
vitrage-ml=vitrage-ml.service
vitrage-notifier=vitrage-notifier.service
vitrage-persistor=vitrage-persistor.service
vitrage-snmp-parsing=vitrage-snmp-parsing.service
masakari-api=masakari-api.service
masakari-engine=masakari-engine.service
heat-api=heat-api.service
heat-api-cfn=heat-api.service
heat-engine=heat-api.service
aodh-api=aodh-api.service
aodh-evaluator=aodh-evaluator.service
aodh-notifier=aodh-notifier.service
aodh-listener=aodh-listener.service
aodh-expirer=aodh-expirer.service
magnum-api=magnum-api.service
magnum-conductor=magnum-conductor.service
"

cat << "AEOF" > /tmp/stopservices.sh
#!/bin/sh

apps=$1

for app in $apps; do
	a=${app%=*}
	s=${app#*=}
	if dpkg -s $a 2>/dev/null | grep -q "Status: install ok installed"; then
		systemctl --no-block --quiet --force stop ${s/,/ } 2>/dev/null || true
	else
		echo $a not installed yet
	fi
done
AEOF

REMOVE_APPS="ifupdown build-essential python3-dev iso-codes \
gcc-gversion \
libgcc-gversion-dev \
g++-gversion \
cpp \
cpp-gversion \
"
mkdir -p /run/systemd/network
cat << EOFF > /run/systemd/network/20-dhcp.network
[Match]
Name=en*
[Network]
DHCP=ipv4
EOFF
systemctl daemon-reload
systemctl start systemd-networkd systemd-resolved
sleep 2
rm -f /var/lib/dpkg/info/libc-bin.postinst /var/lib/dpkg/info/man-db.postinst /var/lib/dpkg/info/dbus.postinst /var/lib/dpkg/info/initramfs-tools.postinst

systemctl --no-block --quiet --force stop $STOP_SERVICES || true
systemd-run --service-type=oneshot --on-unit-active=120 --on-boot=10 /bin/bash /tmp/stopservices.sh "$STOP_APPS_SERVICES"

apt update
DEBIAN_FRONTEND=noninteractive apt install -y $APPS || true

echo Install Tacker
export GIT_SSL_NO_VERIFY=1
cd /tmp
git clone --depth=1 https://opendev.org/openstack/tacker
cd /tmp/tacker
pip3 install -r requirements.txt
python3 setup.py install
cp etc/systemd/system/tacker.service etc/systemd/system/tacker-conductor.service /etc/systemd/system
#DEBIAN_FRONTEND=noninteractive apt install -y python3-openstackclient python3-tackerclient

apt remove -y --purge git git-man

gv=$(dpkg -l | grep "GNU C compiler" | awk '/gcc-/ {gsub("gcc-","",$2);print $2}')
dpkg -P --force-depends ${REMOVE_APPS//gversion/$gv}
for SVC in $DISABLE_SERVICES
do
	systemctl disable $SVC
done
systemctl mask $MASK_SERVICES

rm -rf /etc/hostname /etc/resolv.conf /etc/networks /usr/share/doc /usr/share/man /var/tmp/* /var/cache/apt/* /var/lib/*/*.sqlite
rm -rf /usr/bin/systemd-analyze /usr/bin/perl*.* /usr/bin/sqlite3 /usr/share/misc/pci.ids /usr/share/mysql /usr/share/ieee-data /usr/share/sphinx /usr/share/python-wheels /usr/share/fonts/truetype /usr/lib/udev/hwdb.d /usr/lib/udev/hwdb.bin
rm -rf /etc/rc*.d/S*tftpd-hpa
find /usr -type d -name __pycache__ -prune -exec rm -rf {} +
find /usr -type d -name tests -prune -exec rm -rf {} +
find /usr/*/locale -mindepth 1 -maxdepth 1 ! -name 'en' -prune -exec rm -rf {} +
find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'Etc' -a ! -name '*UTC' -a ! -name '*UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -prune -exec rm -rf {} +
dd if=/dev/zero of=/tmp/bigfile || true
sync
sync
rm /tmp/bigfile
sync
sync
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
set -x
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
dd if=/usr/lib/EXTLINUX/mbr.bin of=$loopx
extlinux -i /boot/syslinux
sed -i '/src/d' /etc/apt/sources.list
rm -rf /tmp/* /var/tmp/* /var/log/* /var/cache/apt/* /var/lib/apt/lists/*
"

sync ${MNTDIR}
sleep 1
sync ${MNTDIR}
sleep 1
sync ${MNTDIR}
sleep 1
umount ${MNTDIR}/dev
sleep 1
umount ${MNTDIR}/proc
sleep 1
umount ${MNTDIR}/sys
sleep 1
killall -r provjobd || true
sleep 1
umount ${MNTDIR}
sleep 1
losetup -d $loopx

qemu-system-x86_64 -name stack-m-building -machine q35,accel=kvm:xen:hax:hvf:whpx:tcg -smp "$(nproc)" -m 6G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=/tmp/debian.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

qemu-img convert -c -f raw -O qcow2 /tmp/debian.raw /dev/shm/stack-m.img

exit 0
