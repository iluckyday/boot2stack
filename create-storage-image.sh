#!/bin/bash
set -x

#########################
# exit 0
# target_core_mod: use normal kernel
#########################

release=$(curl -sSkL https://www.debian.org/releases/ | grep -oP 'codenamed <em>\K(.*)(?=</em>)')
release="sid"
include_apps="systemd,systemd-resolved,dbus,systemd-sysv,sudo,openssh-server,xz-utils"
include_apps+=",linux-image-cloud-amd64,extlinux,initramfs-tools"

export DEBIAN_FRONTEND=noninteractive
apt-config dump | grep -we Recommends -e Suggests | sed 's/1/0/' | tee /etc/apt/apt.conf.d/99norecommends
apt update
apt install -y debootstrap qemu-system-x86 qemu-utils

MNTDIR=/tmp/debian
mkdir -p ${MNTDIR}

#qemu-img create -f raw /tmp/debian.raw 201G
qemu-img create -f raw /tmp/debian.raw 2G
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
path-exclude /usr/include/*
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

APPS="python3-systemd xfsprogs rsync swift swift-account swift-container swift-object cinder-volume tgt manila-share nfs-kernel-server"

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
tgt.service \
rsync.service \
swift-object-auditor.service swift-object-reconstructor.service swift-object-replicator.service swift-object-updater.service swift-object.service swift-account-auditor.service swift-account-reaper.service swift-account-replicator.service swift-account.service swift-container-auditor.service swift-container-reconciler.service swift-container-replicator.service swift-container-sharder.service swift-container-sync.service swift-container-updater.service swift-container.service \
cinder-volume.service \
manila-share.service"

REMOVE_APPS="ifupdown iso-codes"

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
dpkg -P --force-depends ${REMOVE_APPS}
systemctl disable $DISABLE_SERVICES

rm -rf /etc/hostname /etc/resolv.conf /etc/networks /usr/share/doc /usr/share/man /var/tmp/* /var/cache/apt/* /var/lib/*/*.sqlite
rm -rf /usr/bin/systemd-analyze /usr/bin/perl*.* /usr/bin/sqlite3 /usr/share/misc/pci.ids /usr/share/mysql /usr/share/ieee-data /usr/share/sphinx /usr/share/python-wheels /usr/share/fonts/truetype /usr/lib/udev/hwdb.d /usr/lib/udev/hwdb.bin
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
sed -i 's/root:\*:/root::/' etc/shadow
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

qemu-system-x86_64 -name stack-s-building -machine q35,accel=kvm:xen:hax:hvf:whpx:tcg -smp "$(nproc)" -m 4G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=/tmp/debian.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

qemu-img convert -c -f raw -O qcow2 /tmp/debian.raw /dev/shm/stack-s.img

exit 0
