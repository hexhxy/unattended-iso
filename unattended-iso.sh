#!/bin/bash
##############################################################################
# Copyright (c) 2016-2017 HUAWEI TECHNOLOGIES CO.,LTD and others.
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Apache License, Version 2.0
# which accompanies this distribution, and is available at
# http://www.apache.org/licenses/LICENSE-2.0
##############################################################################
set -e

CURRENT_DIR=$(cd "$(dirname "$0")";pwd)
RELEASE=(14.04.5 14.04.4 14.04.3 14.04.2 14.04.1)

sudo -v
if [ $? -ne 0 ]; then
    echo "No root privilege, exiting..."
    exit 1
fi

if [[ ! -f /etc/redhat-release ]]; then
    sudo apt-get install -y wget mkisofs
else
    sudo yum install -y wget mkisofs
fi

TEMP=`getopt -o v: --long version: -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$TEMP"
while :; do
    case "$1" in
        -v|--version) export OS_VERSION=$2; shift 2;;
        --) shift; break;;
        *) echo "Internal error!" ; exit 1;;
    esac
done

OS_VERSION=${OS_VERSION:-14.04.5}
for i in ${RELEASE[@]}
do
    if [[ $i =~ $OS_VERSION.* ]]; then
        OS_VERSION=$i
        OS_FOUND="true"
        break
    fi
done

if [[ $OS_FOUND != "true" ]]; then
    echo "Unsupported OS Version"
    exit 1
fi

mkdir -p $CURRENT_DIR/build_iso $CURRENT_DIR/output

if [[ $OS_VERSION == "14.04.5" ]]; then
    ISO_URL=http://releases.ubuntu.com/14.04/ubuntu-14.04.5-server-amd64.iso
else
    ISO_URL=http://old-releases.ubuntu.com/releases/$OS_VERSION/ubuntu-$OS_VERSION-server-amd64.iso
fi

wget -nc $ISO_URL -O $CURRENT_DIR/build_iso/ubuntu-$OS_VERSION-server-amd64.iso || true

mkdir -p $CURRENT_DIR/build_iso/org_iso

if grep -qs $CURRENT_DIR/build_iso/org_iso /proc/mounts; then
    umount $CURRENT_DIR/build_iso/org_iso
fi

mount -o loop $CURRENT_DIR/build_iso/ubuntu-$OS_VERSION-server-amd64.iso $CURRENT_DIR/build_iso/org_iso

if [ -d $CURRENT_DIR/build_iso/new_iso ]; then
    rm -rf $CURRENT_DIR/build_iso/new_iso
fi

cp -rT $CURRENT_DIR/build_iso/org_iso $CURRENT_DIR/build_iso/new_iso
cp -rT $CURRENT_DIR/auto.seed $CURRENT_DIR/build_iso/new_iso/preseed/auto.seed

echo en > $CURRENT_DIR/build_iso/new_iso/isolinux/lang
sed -i -r 's/timeout\s+[0-9]+/timeout 1/g' $CURRENT_DIR/build_iso/new_iso/isolinux/isolinux.cfg

seed_md5=`md5sum $CURRENT_DIR/build_iso/new_iso/preseed/auto.seed | awk '{print $1}'`

sed -i "/label install/ilabel autoinstall\n\
  menu label ^Autoinstall Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed vga=788 initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/auto.seed preseed/file/checksum=$seed_md5 --" $CURRENT_DIR/build_iso/new_iso/isolinux/txt.cfg

pushd ./build_iso/new_iso
mkisofs -D -r -V "AUTO_UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $CURRENT_DIR/output/ubuntu-$OS_VERSION-server-amd64-unattended.iso .
popd

