#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import time


# TIMEZONE
def setup_timezone():
    print("\nSetting up /etc/systemd/timesyncd.conf")
    with open("/etc/systemd/timesyncd.conf", "r+") as f:
        data = f.read()
        data = data.replace("#NTP=", "NTP=192.168.20.1")

        f.seek(0)
        f.write(data)
        f.truncate()

    os.system("timedatectl set-timezone Europe/Moscow")
    os.system("timedatectl set-ntp true")
    os.system("hwclock --systohc")
    time.sleep(1)


# LOCALE
def setup_locale():
    os.system("localectl set-locale LANG=ru_RU.UTF-8")
    os.system('localectl set-x11-keymap ru,us pc105 "" grp:alt_shift_toggle')
    os.system("echo FONT=ter-v20b >> /etc/vconsole.conf")
    time.sleep(1)


# MOUNT SERVERS
def setup_automount():
    if not os.path.exists("/mnt/vfxserver01"):
        os.mkdir("/mnt/vfxserver01", 0o755)

    if not os.path.exists("/mnt/vfxcache01"):
        os.mkdir("/mnt/vfxcache01", 0o755)

    if not os.path.exists("/mnt/vfxstorage01"):
        os.mkdir("/mnt/vfxstorage01", 0o755)

    if not os.path.exists("/mnt/vfxstorage02"):
        os.mkdir("/mnt/vfxstorage02", 0o755)

    if not os.path.exists("/mnt/vfxserver02"):
        os.mkdir("/mnt/vfxserver02", 0o755)

    if not os.path.exists("/mnt/vfxcache02"):
        os.mkdir("/mnt/vfxcache02", 0o755)

    os.system("mount -t nfs 192.168.20.15:/mnt/vfxserver02 /mnt/vfxserver02")
    os.system(
        "cp -v /mnt/vfxserver02/Tools/_configuration_files/etc/systemd/system/mnt-* /etc/systemd/system/"
    )
    time.sleep(1)

    os.system("umount /mnt/vfxserver02")
    time.sleep(1)

    os.system("systemctl daemon-reload")
    # os.system('systemctl enable --now mnt-vfxcache01.mount')
    # os.system('systemctl enable --now mnt-vfxserver01.mount')
    # os.system('systemctl enable --now mnt-vfxstorage01.mount')
    os.system("systemctl enable --now mnt-vfxstorage02.mount")
    os.system("systemctl enable --now mnt-vfxcache02.mount")
    os.system("systemctl enable --now mnt-vfxserver02.mount")
    time.sleep(1)

    print("Setting up automount ... Done")


# SOFT
def install_soft():
    # REFLECTOR
    os.system("reflector -l 5 -c Russia --sort rate --save /etc/pacman.d/mirrorlist")

    # COMMON SOFT
    os.system(
        "pacman -S --needed --noconfirm sudo man tmux rsync bash-completion exfat-utils ntfs-3g unrar unzip p7zip dkms duf htop eza bat yazi zoxide fzf util-linux ethtool numactl"
    )

    # SOFT FOR AFRENDER
    if input("Install soft for afrender? [y/N] ").lower() == "y":
        os.system(
            "pacman -S --needed --noconfirm glu alsa-lib nss freetype2 fontconfig libglvnd libxv libxmu libxi libxtst libxcomposite libxcursor libxrender libxkbcommon ttf-liberation"
        )
        time.sleep(1)

        # AFRENDER SERVICE
        if not os.path.exists("/usr/lib/systemd/system/afrender.service"):
            if input("Setup afrender sevice? [y/N] ").lower() == "y":
                path = "/mnt/vfxserver02/Tools/_configuration_files/etc/systemd/system/afrender.service"

                if os.path.exists(path):
                    try:
                        os.system(
                            "cp -v /mnt/vfxserver02/Tools/_configuration_files/etc/systemd/system/afrender.service /etc/systemd/system/"
                        )
                        os.system(
                            "cp -v /mnt/vfxserver02/Tools/_configuration_files/etc/systemd/system/stop_hserver.service /etc/systemd/system/"
                        )
                        os.system("systemctl enable afrender.service")
                        os.system("systemctl enable stop_hserver.service")
                        time.sleep(1)
                    except OSError as e:
                        print("Error: %s : %s" % (path, e.strerror))

        print("Installing soft for afrender ... Done")

    # SOFT FOR VFXSTATION
    if input("Install soft for vfxstation? [y/N] ").lower() == "y":
        os.system(
            "pacman -S --needed --noconfirm sddm plasma-desktop plasma-x11-session plasma-pa plasma-systemmonitor kdeplasma-addons breeze breeze-gtk kde-gtk-config konsole dolphin pipewire pipewire-pulse okular spectacle filezilla firefox firefox-ublock-origin ttf-dejavu ttf-liberation ttf-bitstream-vera cantarell-fonts ark kscreen krename kate ktorrent kolourpaint kdenlive mpv mediainfo inkscape python-pyqt5 python-lxml telegram-desktop nvidia-open-dkms nvidia-utils opencl-nvidia qt5-xmlpatterns hddtemp psensor obsidian doublecmd-qt6"
        )

        f = open("/etc/sddm.conf", "w")
        f.write("[Theme]\nCurrent=breeze\n\n")
        f.write("[Users]\nMaximumUid=99999\nMinimumUid=99999\n\n")
        f.write("[General]\nDisplayServer=x11\n")
        f.close()

        os.system("systemctl enable sddm")
        time.sleep(1)
        print("Installing software for vfxstation ... Done")


# LINKING SOFT
def link_soft():
    os.symlink("/mnt/vfxserver02/Programs", "/soft")

    os.remove("/etc/skel/.bashrc")
    os.symlink("/mnt/vfxserver02/Tools/_user_preferences/bashrc", "/etc/skel/.bashrc")

    # Nuke Preferences
    os.mkdir("/etc/skel/.nuke")
    os.symlink("/mnt/vfxserver02/Tools/Nuke/menu.py", "/etc/skel/.nuke/menu.py")
    os.symlink("/mnt/vfxserver02/Tools/Nuke/init.py", "/etc/skel/.nuke/init.py")

    # Houdini Preferences
    os.symlink(
        "/mnt/vfxserver02/Tools/_user_preferences/sesi_licenses.pref",
        "/etc/skel/.sesi_licenses.pref",
    )

    # Soft
    os.mkdir("/etc/opt")
    os.symlink("/soft/cgru/cgru", "/opt/cgru")
    os.symlink("/soft/isl", "/opt/isl")
    os.symlink("/soft/isl", "/etc/opt/isl")
    os.symlink("/soft/OFX", "/usr/OFX")
    os.symlink("/soft/houdini", "/opt/houdini")
    os.symlink("/soft/foundry", "/usr/local/foundry")
    os.symlink("/soft/nuke/Nuke15.1v3", "/usr/local/Nuke15.1v3")

    # Additional links
    os.symlink("/lib/libidn.so.12", "/lib/libidn.so.11")
    os.symlink("/lib/libcrypt.so.2", "/lib/libcrypt.so.1")
    os.symlink("/lib/libpython3.13.so.1.0", "/lib/libpython3.9.so.1.0")

    time.sleep(1)
    print("Linking software ... Done")


# SUSPEND & HIBERNATE
def stop_sleep_suspend_and_hibernate():
    os.system(
        "systemctl mask suspend.target hibernate.target suspend-then-hibernate.target hybrid-sleep.target"
    )

    time.sleep(1)
    print("Stopping sleep, suspend, hibernate modes ... Done")


# TRIM & SENSORS
def setup_trim_and_sensors():
    os.system("sensors-detect")
    os.system("systemctl enable fstrim.timer")

    time.sleep(1)
    print("Enabling TRIM and lm_sensors ... Done")


# BLOCK USB MOUNT FOR USERS
def block_mount():
    os.system(
        "cp -v /mnt/vfxserver02/Tools/_configuration_files/etc/polkit-1/rules.d/10-usb-mount.rules /etc/polkit-1/rules.d/"
    )

    time.sleep(1)
    print("Blocking USB mount for regular users ... Done")


# USERS
def create_users():
    if input("Create master user? (Y/n) ").lower() in {"y", ""}:
        os.system(
            "useradd -G wheel,power,video,storage,lp,input,audio -s /bin/bash -m master"
        )
        os.system("passwd master")

    if input("Create render user? (Y/n) ").lower() in {"y", ""}:
        os.system("useradd -g 1000 -s /bin/bash -m render")

    if input("Create user? (Y/n) ").lower() in {"y", ""}:
        user = input("Enter user name: ").lower()
        os.system(
            "useradd -g 1000 -G  power,video,storage,lp,input,audio -s /bin/bash -m "
            + user
        )
        os.system("passwd " + user)

    time.sleep(1)
    print("Creating users ... Done")


# BASE DIRECTORIES
def create_base_directories():
    hostname = os.uname().nodename

    os.mkdir("/mnt/" + hostname + "/Temp", 0o777)
    os.mkdir("/mnt/" + hostname + "/Temp/Media", 0o777)
    os.mkdir("/mnt/" + hostname + "/Temp/MoTemp", 0o777)
    os.mkdir("/mnt/" + hostname + "/Temp/Blender", 0o777)
    os.mkdir("/mnt/" + hostname + "/Temp/Houdini", 0o777)
    os.mkdir("/mnt/" + hostname + "/Temp/Nuke", 0o777)
    os.mkdir("/mnt/" + hostname + "/Temp/Nuke/nuke-u1000", 0o777)
    os.mkdir("/mnt/" + hostname + "/Temp/Nuke/nuke-u1001", 0o777)
    os.mkdir("/mnt/" + hostname + "/Temp/Nuke/nuke-u1002", 0o777)

    os.system("chmod -R 777 /mnt/" + hostname + "/Temp")

    time.sleep(1)
    print("Creating base directories ... Done")


# MENU ICONS
def create_icons():
    icons_path = "/mnt/vfxserver02/Tools/_configuration_files/usr/share/applications/"

    if os.path.exists(icons_path):
        try:
            icons = os.listdir(icons_path)

            for icon in icons:
                src = icons_path + icon
                des = "/usr/share/applications/" + icon

                if not os.path.exists(des):
                    os.symlink(src, des)

        except OSError as e:
            print("Error: %s : %s" % (icons_path, e.strerror))

    time.sleep(1)
    print("Creating menu icons ... Done")


# MAIN
def main():
    if input("Setup timezone? [y/N]: ").lower() == "y":
        setup_timezone()

    if input("Setup locale? [y/N]: ").lower() == "y":
        setup_locale()

    if input("Setup automount? [y/N]: ").lower() == "y":
        setup_automount()

    if input("Install software? [y/N] ").lower() == "y":
        install_soft()

    if input("Create links to the programs? [y/N] ").lower() == "y":
        link_soft()

    if input("Disable suspend & hibernate modes? [y/N] ").lower() == "y":
        stop_sleep_suspend_and_hibernate()

    if input("Enable TRIM and lm_sensors? [y/N] ").lower() == "y":
        setup_trim_and_sensors()

    if input("Disable USB mount for regular users? [y/N] ").lower() == "y":
        block_mount()

    if input("Create users? [y/N] ").lower() == "y":
        create_users()

    if input("Create base directories? [y/N] ").lower() == "y":
        create_base_directories()

    if input("Create menu icons for applications? [y/N] ").lower() == "y":
        create_icons()


if __name__ == "__main__":
    main()
