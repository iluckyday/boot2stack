#!/bin/bash
set -e

DEBIAN_RELEASE=sid

WORKDIR=/tmp/stack
MNTDIR=$WORKDIR/mnt
mkdir -p $MNTDIR
cd $WORKDIR

version=$(curl -skL https://cdimage.debian.org/cdimage/cloud/$DEBIAN_RELEASE/daily | awk '/href/ {s=$0} END {print s}' | awk -F'"' '{sub(/\//,"",$6);print $6}')
curl -skL https://cdimage.debian.org/cdimage/cloud/$DEBIAN_RELEASE/daily/${version}/debian-sid-nocloud-amd64-daily-${version}.tar.xz | tar -xJ

qemu-img resize -f raw disk.raw 203G
loopx=$(losetup --show -f -P disk.raw)
sgdisk -d 1 $loopx
sgdisk -N 0 $loopx
resize2fs -f ${loopx}p1
tune2fs -O '^has_journal' ${loopx}p1
mount ${loopx}p1 $MNTDIR
sleep 1

cat << EOF >> ${MNTDIR}/etc/fstab
tmpfs             /tmp     tmpfs mode=1777,strictatime,nosuid,nodev,size=90% 0 0
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
#!/bin/sh
echo 'PYTHONDONTWRITEBYTECODE=1'
echo 'PYTHONHISTFILE=/dev/null'
EOF
chmod +x ${MNTDIR}/etc/systemd/system-environment-generators/20-python

cat << EOF > ${MNTDIR}/etc/profile.d/python.sh
#!/bin/sh
export PYTHONDONTWRITEBYTECODE=1 PYTHONHISTFILE=/dev/null
EOF

cat << EOF > ${MNTDIR}/etc/pip.conf
[global]
download-cache=/tmp
cache-dir=/tmp
EOF

cat << EOF > ${MNTDIR}/root/.bashrc
export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null
EOF

cat << EOF > ${MNTDIR}/etc/stack-install.conf
APPS="mariadb-server python3-pymysql rabbitmq-server memcached python3-memcache etcd apache2 libapache2-mod-wsgi python3-openstackclient keystone glance placement-api nova-api nova-conductor nova-novncproxy nova-scheduler neutron-server neutron-linuxbridge-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent"
EOF

cat << EOF > ${MNTDIR}/etc/systemd/system/stack-install.service
[Unit]
Description=stack init script
After=network.target
ConditionFileNotEmpty=/etc/stack-install.conf

[Service]
Type=oneshot
StandardOutput=journal+console
Environment=DEBIAN_FRONTEND=noninteractive
EnvironmentFile=/etc/stack-install.conf
ExecStart=/usr/bin/apt update
ExecStart=/usr/bin/apt install -y ${APPS}
ExecStartPost=/bin/rm -f /etc/systemd/system/stack-install.service /etc/systemd/system/multi-user.target.wants/stack-install.service /etc/stack-install.conf
RemainAfterExit=true
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

cat << EOF > ${MNTDIR}/usr/sbin/stack-init.sh
#!/bin/sh

ii=0
while [ $ii -lt 5 ]; do
((ii++))
dhcp_nic=$(ls -d /sys/class/net/en*20 | awk -F'/' '{print $5}')
udhcpc -n -q -f -i $dhcp_nic > /dev/null 2>&1 || continue
curl -skLo /tmp/run.sh http://router/run.sh
if [ $? -eq 0 ]; then
	break
fi
sleep 1
done

[ -r /tmp/run.sh ] && source /tmp/run.sh && rm -f /tmp/run.sh || exit
EOF
chmod +x ${MNTDIR}/usr/sbin/stack-init.sh

sed -i '/src/d' ${MNTDIR}/etc/apt/sources.list
rm -rf ${MNTDIR}/etc/hostname ${MNTDIR}/etc/resolv.conf ${MNTDIR}/tmp/apt ${MNTDIR}/usr/share/doc ${MNTDIR}/usr/share/man ${MNTDIR}/tmp/* ${MNTDIR}/var/tmp/* ${MNTDIR}/var/cache/apt/*
find ${MNTDIR}/ ! -path /proc ! -path /sys -type d -name __pycache__ exec rm -rf {} + || true
find ${MNTDIR}/usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' exec rm -rf {} + || true
find ${MNTDIR}/usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -exec rm -rf {} + || true

for i in apt-daily.timer apt-daily-upgrade.timer
do
	ln -sf /dev/null ${MNTDIR}/etc/systemd/system/$i
done

for i in stack-install.service stack-init.service
do
	ln -sf /etc/systemd/system/$i ${MNTDIR}/etc/systemd/system/multi-user.target.wants/$i
done

chroot $MNTDIR ssh-keygen -A
sync ${MNTDIR}
sleep 1
umount ${MNTDIR}
sleep 1
losetup -d $loopx

qemu-system-x86_64 -name devstack-building -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 6G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=$WORKDIR/disk.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

while pgrep -f "devstack-building" >/dev/null
do
	echo Building ...
	sleep 300
done

echo "Original image size:"
ls -lh $WORKDIR/disk.raw

echo Converting ...
qemu-img convert -f raw -c -O qcow2 $WORKDIR/disk.raw /dev/shm/devstack.cmp.img

echo "Compressed image size:"
ls -lh /dev/shm/devstack.cmp.img
exit 1
