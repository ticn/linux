#!/bin/bash

# wget -qO- https://raw.githubusercontent.com/ngxson/public-assets/main/install-windows-gcp.sh | sudo bash

IMAGE_URL="https://huggingface.co/datasets/uzvme/xiaoheiyangmao/resolve/main/Tiny_10_202301.vhd.gz"

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

apt update && apt install -y util-linux curl wget nano sudo fdisk wget pigz

echo ""
echo ""
echo "    DOWNLOADING WINDOWS IMAGE FILE..."
echo ""
echo ""

wget -O Tiny_10_202301.vhd.gz $IMAGE_URL

# get all block devices, sort by SIZE to get the biggest device
DESTINATION_DEVICE="$(lsblk -x SIZE -o NAME,SIZE | tail -n1 | cut -d ' ' -f 1)"

# check if the disk already has multiple partitions
NB_PARTITIONS=$(lsblk | grep -c "$DESTINATION_DEVICE")
if [ "$NB_PARTITIONS" -gt 1 ]; then
    echo "ERROR: Device $DESTINATION_DEVICE already has some partitions."
    echo "Please make sure that $DESTINATION_DEVICE is an empty disk"
    exit 1
fi

echo ""
echo ""
echo "    COPYING IMAGE FILE... (may take about 5 minutes)"
echo "    Do NOT close this terminal until it finishes"
echo ""
echo ""

# then, use dd to copy image
echo "Destination device is $DESTINATION_DEVICE"
echo "Running dd command..."
pigz -dc ./Tiny_10_202301.vhd.gz | sudo dd of="/dev/$DESTINATION_DEVICE" bs=4M

echo ""
echo ""
echo "    COPY OK"
echo ""
echo ""

# print the partition table
echo "Partition table:"
fdisk -l

echo ""
echo ""
echo "    === ALL DONE ==="
echo ""
echo ""