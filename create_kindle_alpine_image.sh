#!/usr/bin/env bash

# DEPENDENCIES
# qemu-user-static is required to run arm software using the "qemu-arm-static" command (I suppose you use this script on a X86_64 computer)
# Please install it via your package manager (e.g. Ubuntu) or whatever way is appropriate for your distribution (Arch has it in AUR)

# BASIC CONFIGURATION
# REPO: The Alpine repository to use, you can leave it like it is
# MNT: Where you want to mount the image, just make sure /mnt/alpine isn't already used
# IMAGE: The path and name of the image file to be created, you can leave it as is
# IMAGESIZE: How big you want the image to be. If you want to install Chromium, a evince etc. you should go for at least 1400MB
# ALPINESETUP: This are the commands executed inside the Alpine container to set it up. Most notably it installs XFCE desktop environment,
#              and creates a user named "alpine" with password "alpine". The last command is "sh", which allows you to examine the
#              created image/install more packages/whatever. To finish the script just leave the sh shell with "exit"
# STARGUI: This is the script that gets executed inside the container when the GUI is started. Xepyhr is used to render the desktop
#          inside a window, that has the correct name to be displayed in fullscreen by the kindle's awesome windowmanager

# NOW WORKING ON ADDING ANGELFISH INSTEAD OF CHROMIUM
REPO="https://dl-cdn.alpinelinux.org/alpine/"
MNT="/mnt/alpine"
IMAGE="./alpine.ext3"
IMAGESIZE=2048 # Megabytes
ALPINESETUP="source /etc/profile
echo kindle > /etc/hostname
echo \"nameserver 8.8.8.8\" > /etc/resolv.conf
mkdir /run/dbus
apk update
apk upgrade
cat /etc/alpine-release
apk add xorg-server-xephyr xwininfo xdotool xinput dbus-x11 sudo bash nano git
apk add desktop-file-utils gtk-engines consolekit gtk-murrine-engine thunar marco gnome-themes-extra
apk add xfce4 xfce4-terminal
apk add \$(apk search -q ttf- | grep -v '\-doc')
apk add onboard angelfish kirigami2
adduser alpine -D
echo -e \"alpine\nalpine\" | passwd alpine
echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers
addgroup sudo
addgroup alpine sudo
su alpine -s /bin/sh -c \"cd ~
git init
git remote add origin https://github.com/schuhumi/alpine_kindle_dotfiles
git pull origin master
git reset --hard origin/master
dconf load /org/mate/ < ~/.config/org_mate.dconf.dump
dconf load /org/onboard/ < ~/.config/org_onboard.dconf.dump\"

echo 'Adding a desktop icon for the terminal'
echo '[Desktop Entry]
Version=1.0
Type=Application
Name=Terminal
Comment=Use the command line
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
Categories=Utility;TerminalEmulator;' > /usr/share/applications/xfce4-terminal.desktop

echo 'Adding a desktop icon for Angelfish'
echo '[Desktop Entry]
Version=1.0
Type=Application
Name=Angelfish
Comment=Web Browser
Exec=angelfish
Icon=angelfish
Terminal=false
Categories=Network;WebBrowser;' > /usr/share/applications/angelfish.desktop

# Add previous desktop icons to the alpine user's desktop
# Keep previous ones so they appear in the apps menu as well (bugged as of now btw)
mkdir -p /home/alpine/Desktop
cp /usr/share/applications/xfce4-terminal.desktop /home/alpine/Desktop/
cp /usr/share/applications/angelfish.desktop /home/alpine/Desktop/
cp /usr/share/applications/onboard.desktop /home/alpine/Desktop/
chown -R alpine:alpine /home/alpine/Desktop
# Set desktop files as trusted (otherwise XFCE won't show them)
chmod +x /home/alpine/Desktop/*.desktop

echo \"You're now dropped into an interactive shell in Alpine, feel free to explore and type exit to leave.\"
sh"
STARTGUI='#!/bin/sh
chmod a+w /dev/shm # Otherwise the alpine user cannot use this (needed for chromium)
SIZE=$(xwininfo -root -display :0 | egrep "geometry" | cut -d " "  -f4)
env DISPLAY=:0 Xephyr :1 -title "L:D_N:application_ID:xephyr" -ac -br -screen $SIZE -cc 4 -reset -terminate & sleep 3 && su alpine -c "env DISPLAY=:1 startxfce4"
killall Xephyr'

# ENSURE ROOT
if [ "$(whoami)" != "root" ]; then
    echo "This script needs to be run as root"
    exec sudo -- "$0" "$@"
fi

# GETTING APK-TOOLS-STATIC
echo "Determining version of apk-tools-static"
curl "$REPO/latest-stable/main/armhf/APKINDEX.tar.gz" --output /tmp/APKINDEX.tar.gz
tar -xzvf /tmp/APKINDEX.tar.gz -C /tmp
# Grep for the version in APKINDEX
APKVER="$(cut -d':' -f2 <<<"$(grep -A 5 "P:apk-tools-static" /tmp/APKINDEX | grep "V:")")" 
# Remove what we downloaded and extracted
rm /tmp/APKINDEX /tmp/APKINDEX.tar.gz /tmp/DESCRIPTION
echo "Version of apk-tools-static is: $APKVER"
echo "Downloading apk-tools-static"
curl "$REPO/latest-stable/main/armv7/apk-tools-static-$APKVER.apk" --output "/tmp/apk-tools-static.apk"
tar -xzvf "/tmp/apk-tools-static.apk" -C /tmp

# CREATING IMAGE FILE
# To create the image file, a file full of zeros with the desired size is created using dd. An ext3-filesystem is created in it.
# Also automatic checks are disabled using tune2fs
echo "Creating image file"
dd if=/dev/zero of="$IMAGE" bs=1M count=$IMAGESIZE
mkfs.ext3 "$IMAGE"
tune2fs -i 0 -c 0 "$IMAGE"

# MOUNTING IMAGE
echo "Mounting image"
mkdir -p "$MNT"
mount -o loop -t ext3 "$IMAGE" "$MNT"

# BOOTSTRAPPING ALPINE
echo "Bootstrapping Alpine"
qemu-arm-static /tmp/sbin/apk.static -X "$REPO/edge/main" -U --allow-untrusted --root "$MNT" --initdb add alpine-base

# COMPLETE IMAGE MOUNTING FOR CHROOT
mkdir -p "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/etc" "$MNT/usr/bin"
mount /dev/ "$MNT/dev/" --bind
mount -t proc none "$MNT/proc"
mount -o bind /sys "$MNT/sys"

# CONFIGURE ALPINE
cp /etc/resolv.conf "$MNT/etc/resolv.conf"

mkdir -p "$MNT/etc/apk"
# Here comes a hack because Chromium isn't in edge
echo "$REPO/edge/main/
$REPO/edge/community/
$REPO/edge/testing/
$REPO/latest-stable/community" > "$MNT/etc/apk/repositories"
echo "$STARTGUI" > "$MNT/startgui.sh"
chmod +x "$MNT/startgui.sh"

# CHROOT
# Here we run arm-software inside the Alpine container, and thus we need the qemu-arm-static binary in it
cp $(which qemu-arm-static) "$MNT/usr/bin/"
# Chroot and run the setup as specified at the beginning of the script
echo "Chrooting into Alpine"
chroot /mnt/alpine/ qemu-arm-static /bin/sh -c "$ALPINESETUP"
# Remove the qemu-arm-static binary again, it's not needed on the kindle
rm "$MNT/usr/bin/qemu-arm-static"

# UNMOUNT IMAGE & CLEANUP
# Sync to disc
sync
# Kill remaining processes
kill $(lsof +f -t "$MNT")
# We unmount in reverse order
echo "Unmounting image"
umount "$MNT/sys"
umount "$MNT/proc"
umount -lf "$MNT/dev"
umount "$MNT"
while [[ $(mount | grep "$MNT") ]]; do
	echo "Alpine is still mounted, please wait.."
	sleep 3
	umount "$MNT"
done
echo "Alpine unmounted"

# And remove the apk-tools-static which we extracted to /tmp
echo "Cleaning up"
rm /tmp/apk-tools-static.apk
rm -r /tmp/sbin
