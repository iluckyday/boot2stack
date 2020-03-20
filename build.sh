#!/bin/bash
set -e

DEBIAN_RELEASE=sid

WORKDIR=/tmp/stack
MNTCDIR=$WORKDIR/mntc
MNTUDIR=$WORKDIR/mntu
mkdir -p {${MNTCDIR},${MNTUDIR}}
cd $WORKDIR

version=$(curl -skL https://cdimage.debian.org/cdimage/cloud/$DEBIAN_RELEASE/daily | awk '/href/ {s=$0} END {print s}' | awk -F'"' '{sub(/\//,"",$6);print $6}')
curl -skL https://cdimage.debian.org/cdimage/cloud/$DEBIAN_RELEASE/daily/${version}/debian-sid-nocloud-amd64-daily-${version}.tar.xz | tar -xJ

cp disk.raw c.raw
mv disk.raw u.raw
qemu-img resize -f raw c.raw 203G
qemu-img resize -f raw u.raw 203G
loopcx=$(losetup --show -f -P c.raw)
sgdisk -d 1 $loopcx
sgdisk -N 0 $loopcx
resize2fs -f ${loopcx}p1
tune2fs -O '^has_journal' ${loopcx}p1
mount ${loopcx}p1 ${MNTCDIR}
sleep 1

loopux=$(losetup --show -f -P u.raw)
sgdisk -d 1 $loopux
sgdisk -N 0 $loopux
resize2fs -f ${loopux}p1
tune2fs -O '^has_journal' ${loopux}p1
mount ${loopux}p1 ${MNTUDIR}
sleep 1

cat << EOF >> ${MNTCDIR}/etc/fstab
tmpfs             /tmp     tmpfs mode=1777,size=90%            0 0
EOF
cat << EOF >> ${MNTUDIR}/etc/fstab
tmpfs             /tmp     tmpfs mode=1777,size=90%            0 0
EOF

mkdir -p ${MNTCDIR}/root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp" >> ${MNTCDIR}/root/.ssh/authorized_keys
chmod 600 ${MNTCDIR}/root/.ssh/authorized_keys
mkdir -p ${MNTUDIR}/root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp" >> ${MNTUDIR}/root/.ssh/authorized_keys
chmod 600 ${MNTUDIR}/root/.ssh/authorized_keys

mkdir -p ${MNTCDIR}/etc/apt/apt.conf.d
cat << EOF > ${MNTCDIR}/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF
mkdir -p ${MNTUDIR}/etc/apt/apt.conf.d
cat << EOF > ${MNTUDIR}/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

mkdir -p ${MNTCDIR}/etc/dpkg/dpkg.cfg.d
cat << EOF > ${MNTCDIR}/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
EOF
mkdir -p ${MNTUDIR}/etc/dpkg/dpkg.cfg.d
cat << EOF > ${MNTUDIR}/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
EOF

mkdir -p ${MNTCDIR}/etc/systemd/journald.conf.d
cat << EOF > ${MNTCDIR}/etc/systemd/journald.conf.d/storage.conf
[Journal]
Storage=volatile
EOF
mkdir -p ${MNTUDIR}/etc/systemd/journald.conf.d
cat << EOF > ${MNTUDIR}/etc/systemd/journald.conf.d/storage.conf
[Journal]
Storage=volatile
EOF

mkdir -p ${MNTCDIR}/etc/systemd/system-environment-generators
cat << EOF > ${MNTCDIR}/etc/systemd/system-environment-generators/20-python
#!/bin/sh
echo 'PYTHONDONTWRITEBYTECODE=1'
echo 'PYTHONHISTFILE=/dev/null'
EOF
chmod +x ${MNTCDIR}/etc/systemd/system-environment-generators/20-python
mkdir -p ${MNTUDIR}/etc/systemd/system-environment-generators
cat << EOF > ${MNTUDIR}/etc/systemd/system-environment-generators/20-python
#!/bin/sh
echo 'PYTHONDONTWRITEBYTECODE=1'
echo 'PYTHONHISTFILE=/dev/null'
EOF
chmod +x ${MNTUDIR}/etc/systemd/system-environment-generators/20-python

cat << EOF > ${MNTCDIR}/etc/profile.d/python.sh
#!/bin/sh
export PYTHONDONTWRITEBYTECODE=1 PYTHONHISTFILE=/dev/null
EOF
cat << EOF > ${MNTUDIR}/etc/profile.d/python.sh
#!/bin/sh
export PYTHONDONTWRITEBYTECODE=1 PYTHONHISTFILE=/dev/null
EOF

cat << EOF > ${MNTCDIR}/etc/pip.conf
[global]
download-cache=/tmp
cache-dir=/tmp
EOF
cat << EOF > ${MNTUDIR}/etc/pip.conf
[global]
download-cache=/tmp
cache-dir=/tmp
EOF

cat << EOF > ${MNTCDIR}/root/.bashrc
export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null
EOF
cat << EOF > ${MNTUDIR}/root/.bashrc
export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null
EOF

cat << "EOF" > ${MNTCDIR}/usr/sbin/stack-install.sh
#!/bin/sh
set -e

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
DISABLE_SERVICES="radvd.service \
haproxy.service \
mariadb.service \
memcached.service \
rabbitmq-server.service \
etcd.service \
apache2.service \
keystone.service \
glance-api.service \
nova-api-metadata.service nova-api.service nova-conductor.service nova-novncproxy.service nova-scheduler.service nova-serialproxy.service nova-spicehtml5proxy.service nova-xenvncproxy.service \
neutron-api.service neutron-dhcp-agent.service neutron-l3-agent.service neutron-linuxbridge-agent.service neutron-metadata-agent.service neutron-rpc-server.service \
placement-api.service"

REMOVE_APPS="ifupdown gcc"

DEBIAN_FRONTEND=noninteractive
apt update
apt install -y $APPS
apt remove --purge -y $REMOVE_APPS
systemctl disable $DISABLE_SERVICES

rm -rf /etc/hostname /etc/resolv.conf /usr/share/doc /usr/share/man /tmp/* /var/tmp/* /var/cache/apt/*
find / ! -path /proc ! -path /sys -type d -name __pycache__ -exec rm -rf {} + || true
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' -exec rm -rf {} + || true
find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -exec rm -rf {} + || true
EOF
chmod +x ${MNTCDIR}/usr/sbin/stack-install.sh

cat << "EOF" > ${MNTUDIR}/usr/sbin/stack-install.sh
#!/bin/sh
set -e

APPS="python3-openstackclient \
nova-compute \
neutron-linuxbridge-agent"
DISABLE_SERVICES="nova-compute neutron-linuxbridge-agent"
REMOVE_APPS="ifupdown gcc"

DEBIAN_FRONTEND=noninteractive
apt update
apt install -y $APPS
apt remove --purge -y $REMOVE_APPS
systemctl disable $DISABLE_SERVICES

rm -rf /etc/hostname /etc/resolv.conf /usr/share/doc /usr/share/man /tmp/* /var/tmp/* /var/cache/apt/*
find / ! -path /proc ! -path /sys -type d -name __pycache__ -exec rm -rf {} + || true
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' -exec rm -rf {} + || true
find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -exec rm -rf {} + || true
EOF
chmod +x ${MNTUDIR}/usr/sbin/stack-install.sh

cat << "EOF" > ${MNTCDIR}/etc/systemd/system/stack-install.service
[Unit]
Description=stack install script
After=network.target
SuccessAction=poweroff-force

[Service]
Type=oneshot
#StandardOutput=journal+console
ExecStart=/usr/sbin/stack-install.sh
ExecStartPost=/bin/rm -f /etc/systemd/system/stack-install.service /etc/systemd/system/multi-user.target.wants/stack-install.service /usr/sbin/stack-install.sh
EOF
cat << "EOF" > ${MNTUDIR}/etc/systemd/system/stack-install.service
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

cat << EOF > ${MNTCDIR}/etc/systemd/system/stack-init.service
[Unit]
Description=stack init script
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/stack-init.sh
RemainAfterExit=true
EOF
cat << EOF > ${MNTUDIR}/etc/systemd/system/stack-init.service
[Unit]
Description=stack init script
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/stack-init.sh
RemainAfterExit=true
EOF

cat << "EOF" > ${MNTCDIR}/usr/sbin/stack-init.sh
#!/bin/sh

dhcp_nic=$(basename /sys/class/net/en*20)
if [ -z "$dhcp_nic" ]
then
	exit
fi

ii=0
while [ $ii -lt 5 ]; do
((ii++))
udhcpc -n -q -f -i $dhcp_nic > /dev/null 2>&1 || continue
curl -skLo /tmp/run.sh http://router/run.sh
if [ $? -eq 0 ]; then
	break
fi
sleep 1
done

[ -r /tmp/run.sh ] && source /tmp/run.sh && rm -f /tmp/run.sh || exit
EOF
chmod +x ${MNTCDIR}/usr/sbin/stack-init.sh
cat << "EOF" > ${MNTUDIR}/usr/sbin/stack-init.sh
#!/bin/sh

dhcp_nic=$(basename /sys/class/net/en*20)
if [ -z "$dhcp_nic" ]
then
	exit
fi

ii=0
while [ $ii -lt 5 ]; do
((ii++))
udhcpc -n -q -f -i $dhcp_nic > /dev/null 2>&1 || continue
curl -skLo /tmp/run.sh http://router/run.sh
if [ $? -eq 0 ]; then
	break
fi
sleep 1
done

[ -r /tmp/run.sh ] && source /tmp/run.sh && rm -f /tmp/run.sh || exit
EOF
chmod +x ${MNTUDIR}/usr/sbin/stack-init.sh

echo 'deb http://deb.debian.org/debian sid main contrib non-free' > ${MNTCDIR}/etc/apt/sources.list
echo 'deb http://deb.debian.org/debian sid main contrib non-free' > ${MNTUDIR}/etc/apt/sources.list

for i in stack-install.service stack-init.service
do
	ln -sf /etc/systemd/system/$i ${MNTCDIR}/etc/systemd/system/multi-user.target.wants/$i
	ln -sf /etc/systemd/system/$i ${MNTUDIR}/etc/systemd/system/multi-user.target.wants/$i
done

chroot ${MNTCDIR} ssh-keygen -A
chroot ${MNTUDIR} ssh-keygen -A
sync ${MNTCDIR}
sync ${MNTUDIR}
sleep 1
umount ${MNTCDIR}
umount ${MNTUDIR}
sleep 1
losetup -d {$loopcx,$loopux}

qemu-system-x86_64 -name stack-c-building -daemonize -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 4G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=$WORKDIR/c.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0
qemu-system-x86_64 -name stack-u-building -daemonize -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 4G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=$WORKDIR/u.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

#qemu-system-x86_64 -name stack-c-building -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 4G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=$WORKDIR/c.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0
#qemu-system-x86_64 -name stack-u-building -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 4G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=$WORKDIR/u.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0
while [[ pgrep -f "stack-c-building" >/dev/null || pgrep -f "stack-u-building" >/dev/null ]]
do
	echo Building ...
	sleep 300
done

echo "Original image size:"
du -h $WORKDIR/{c,u}.raw

echo Converting ...
qemu-img convert -f raw -c -O qcow2 $WORKDIR/c.raw /dev/shm/stack-c.img
qemu-img convert -f raw -c -O qcow2 $WORKDIR/u.raw /dev/shm/stack-u.img

echo "Compressed image size:"
du -h /dev/shm/stack-{c,u}.img

exit 0
