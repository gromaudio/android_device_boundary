#!/bin/bash
if [ $# -lt 1 ]; then
	echo "Usage: $0 /dev/diskname [product=nitrogen6x] [--force]"
	exit -1 ;
fi

force='';
if [ $# -ge 2 ]; then
   product=$2;
   if [ $# -ge 3 ]; then
      if [ "x--force" == "x$3" ]; then
         force=yes;
      fi
   fi
else
   product=nitrogen6x;
fi

echo "---------build SD card for product $product";

if ! [ -d out/target/product/$product/data ]; then
   echo "Missing out/target/product/$product";
   exit 1;
fi

removable_disks() {
	for f in `ls /dev/disk/by-path/* | grep -v part` ; do
		diskname=$(basename `readlink $f`);
		type=`cat /sys/class/block/$diskname/device/type` ;
		size=`cat /sys/class/block/$diskname/size` ;
		issd=0 ;
		# echo "checking $diskname/$type/$size" ;
		if [ $size -ge 3906250 ]; then
			if [ $size -lt 72500000 ]; then
				issd=1 ;
			fi
		fi
		if [ "$issd" -eq "1" ]; then
			echo -n "/dev/$diskname ";
			# echo "removable disk /dev/$diskname, size $size, type $type" ;
			#echo -n -e "\tremovable? " ; cat /sys/class/block/$diskname/removable ;
		fi
	done
	echo;
}
diskname=$1
removables=`removable_disks`

for disk in $removables ; do
   echo "removable disk $disk" ;
   if [ "$diskname" = "$disk" ]; then
      matched=1 ;
      break ;
   fi
done

if [ -z "$matched" -a -z "$force" ]; then
   echo "Invalid disk $diskname" ;
   exit -1;
fi

prefix='';

if [[ "$diskname" =~ "mmcblk" ]]; then
   prefix=p
fi

echo "reasonable disk $diskname, partitions ${diskname}${prefix}1..." ;
umount ${diskname}${prefix}*
umount gvfs

dd if=/dev/zero of=${diskname} count=1 bs=1024

sudo sfdisk --force -uM ${diskname} << EOF
,20,B,*
,20,B
,2048,E
,,83
,512,83
,512,83
,10,83
,10,83
EOF

for n in `seq 1 8` ; do
   if ! [ -e ${diskname}${prefix}$n ] ; then
      echo "--------------missing ${diskname}${prefix}$n" ;
      exit 1;
   fi
   sync
done

echo "all partitions present and accounted for!";
sync && sudo sfdisk -R ${diskname}${prefix} && sleep 1

# make partition 4 1500MB long (to allow smallish 4GB cards)
sfdisk ${diskname} -N4 -uM  << EOF
,1500,83
EOF

sync && sudo sfdisk -R ${diskname}${prefix} && sleep 1

echo "------------------making BOOT partition"
mkfs.vfat -n BOOT ${diskname}${prefix}1
echo "------------------making RECOVER partition"
mkfs.vfat -n RECOVER ${diskname}${prefix}2
echo "------------------making DATA partition"
mkfs.ext4 -L DATA ${diskname}${prefix}4
echo "------------------making CACHE partition"
mkfs.ext4 -L CACHE ${diskname}${prefix}6
echo "------------------making VENDOR partition"
mkfs.ext4 -L VENDOR ${diskname}${prefix}7
echo "------------------making MISC partition"
mkfs.ext4 -L MISC ${diskname}${prefix}8

echo "------------------mounting BOOT, RECOVER, DATA partitions"
sync && sleep 1 && sudo sfdisk -R ${diskname}${prefix} && sleep 1

for n in 1 2 4 ; do
   echo "--- mounting ${diskname}${prefix}${n}";
   udisks --mount ${diskname}${prefix}${n}
done

sudo cp -rfv out/target/product/$product/boot/* /media/BOOT/
sudo cp -rfv out/target/product/$product/boot/6x* /media/RECOVER/
sudo cp -rfv out/target/product/$product/boot/uImage /media/RECOVER/
sudo cp -rfv out/target/product/$product/uramdisk-recovery.img /media/RECOVER/uramdisk.img
sudo cp -ravf out/target/product/$product/data/* /media/DATA/

if [ -e ${diskname}${prefix}5 ]; then
   sudo dd if=out/target/product/$product/system.img of=${diskname}${prefix}5
   sudo e2label ${diskname}${prefix}5 SYSTEM
   sudo e2fsck -f ${diskname}${prefix}5
   sudo resize2fs ${diskname}${prefix}5
else
   echo "-----------missing ${diskname}${prefix}5";
fi

sync && sudo umount ${diskname}${prefix}*

