#!/bin/bash

# get configuration from the file
[ -n "$1" ] && [ -f "$1" ] && source "$1" || exit 1

# prepare
trap "exit 1" INT
ISOMNTDIR=$LIVEDIR/mnt
EXTRACTDIR=$LIVEDIR/extract-cd
EDITDIR=$LIVEDIR/edit
sudo aptitude install -y squashfs-tools genisoimage || exit 1

# mount livecd
mkdir $LIVEDIR && cd $LIVEDIR || exit 1
mkdir $ISOMNTDIR || exit 1
sudo mount -o loop $ISODIR/ubuntu-${VERSION}.iso $ISOMNTDIR || exit 1

# extract squashfs
mkdir $EXTRACTDIR || exit 1
rsync --exclude=/casper/filesystem.squashfs -a $ISOMNTDIR/ $EXTRACTDIR
sudo unsquashfs $ISOMNTDIR/casper/filesystem.squashfs
sudo mv squashfs-root $EDITDIR

# umount livecd
sudo umount $ISOMNTDIR

# copy resolv.conf
sudo cp /etc/resolv.conf $EDITDIR/etc/

# mount dev
sudo mount --bind /dev/ $EDITDIR/dev

# configure new live cd
[ -n "$PROXY" ] && echo -e "$PROXY" | sudo tee -a $EDITDIR/etc/environment
[ -n "$TIMEZONE" ] && echo "TZ=$TIMEZONE" | sudo tee -a $EDITDIR/etc/environment

# create customization script and run it in chroot
cat >> $EDITDIR/tmp/customize.sh << EOF
#!/bin/bash

# mount proc, sysfs, devpts
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts

# prepare choot
export HOME=/root
export LC_ALL=C
dpkg-divert --local --rename --add /sbin/initctl
ln -s /bin/true /sbin/initctl

# install packages
( which software-properties-gtk && software-properties-gtk -e universe && software-properties-gtk -e multiverse ) || \
( which software-properties-kde && software-properties-kde -e universe && software-properties-kde -e multiverse ) || \
sudoedit /etc/apt/sources.list
aptitude update
[ "$UPTODATE" -eq "1" ] && aptitude full-upgrade -y
aptitude install -Ry $PACKAGES

# clean
aptitude clean
rm -rf /tmp/* ~/.bash_history
rm /etc/resolv.conf
rm /sbin/initctl
dpkg-divert --rename --remove /sbin/initctl

# umount proc, sysfs, devpts
umount /proc
umount /sys
umount /dev/pts

# exit from chroot
exit
EOF

# make customization script executable
chmod +x $EDITDIR/tmp/customize.sh

# chroot and run customization script
sudo chroot $EDITDIR su -lc /tmp/customize.sh

# umount dev
sudo umount $EDITDIR/dev

# regenerate manifest
chmod +w $EXTRACTDIR/casper/filesystem.manifest
sudo chroot $EDITDIR dpkg-query -W --showformat='${Package} ${Version}\n' > $EXTRACTDIR/casper/filesystem.manifest
sudo cp $EXTRACTDIR/casper/filesystem.manifest $EXTRACTDIR/casper/filesystem.manifest-desktop
sudo sed -i '/ubiquity/d' $EXTRACTDIR/casper/filesystem.manifest-desktop
sudo sed -i '/casper/d' $EXTRACTDIR/casper/filesystem.manifest-desktop

# compress filesystem
[ -f $EXTRACTDIR/casper/filesystem.squashfs ] && \
     sudo rm $EXTRACTDIR/casper/filesystem.squashs
sudo mksquashfs $EDITDIR $EXTRACTDIR/casper/filesystem.squashfs

# set an image name in $EXTRACTDIR/README.diskdefines
sudoedit $EXTRACTDIR/README.diskdefines

# remove old md5sum.txt and calculate new md5 sums
cd $EXTRACTDIR
sudo rm md5sum.txt
find -type f -print0 | sudo xargs -0 md5sum | grep -v isolinux/boot.cat | sudo tee md5sum.txt

# create iso
sudo mkisofs -D -r -V "$IMAGE_NAME" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ../ubuntu-$VERSION-custom.iso .

