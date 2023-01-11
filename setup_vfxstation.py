#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os, shutil, time

# MOUNT SERVERS
def setup_automount ():

    if not os.path.exists('/mnt/vfxserver01'):
        os.mkdir('/mnt/vfxserver01', 0o755)

    if not os.path.exists('/mnt/vfxbackup01'):
        os.mkdir('/mnt/vfxbackup01', 0o755)

    f = open('/etc/fstab', 'a')
    f.write('\n# SERVERS\n')
    f.write('192.168.20.10:/mnt/vfxbackup01\t\t\t\t/mnt/vfxbackup01\tnfs\t_netdev,x-systemd.mount-timeout=10,hard,intr,noatime\t0 2\n')
    f.write('192.168.20.11:/mnt/vfxserver01\t\t\t\t/mnt/vfxserver01\tnfs\t_netdev,x-systemd.mount-timeout=10,hard,intr,noatime\t0 2\n')
    f.close()

    os.system('systemctl daemon-reload')
    os.system('mount -a')

    time.sleep(1)
    print('Setting up automount ... Done')

# MOUNT PACMAN CACHE
def setup_pacman_cache ():

    path = '/var/cache/pacman/pkg'

    if os.path.exists(path):
        if input('Pacman cache directory is not empty. Do you want to clear it? [y/N]: ').lower() == 'y':
            try:
                shutil.rmtree(path)
            except OSError as e:
                print("Error: %s : %s" % (path, e.strerror))

    f = open('/etc/fstab', 'a')
    f.write('\n# PACMAN CACHE\n')
    f.write('192.168.20.11:/mnt/vfxserver01/Tools/_caches/pacman\t/var/cache/pacman\tnfs\t_netdev,x-systemd.mount-timeout=0,hard,intr,noatime\t0 2\n')
    f.close()

    os.system('systemctl daemon-reload')
    os.system('mount -a')

    time.sleep(1)
    print('Setting up pacman cache ... Done')

# SOFT
def install_soft ():

    # COMMON SOFT
    os.system('pacman -S --needed --noconfirm sudo man tmux rsync bash-completion exfat-utils ntfs-3g unrar unzip p7zip dkms linux-lts-headers duf htop')

    # SOFT FOR AFRENDER
    if input('Install soft for afrender? [y/N] ').lower() == 'y':
        os.system('pacman -S --needed --noconfirm glu alsa-lib libglvnd libxv libxmu libxi libxrender libxkbcommon ttf-liberation')
        time.sleep(1)

        # AFRENDER SERVICE
        if not os.path.exists('/usr/lib/systemd/system/afrender.service'):
            if input('Setup afrender sevice? [y/N] ').lower() == 'y':

                path = '/mnt/vfxserver01/Tools/_configuration_files/usr/lib/systemd/system/afrender.service'

                if os.path.exists(path):
                    try:
                        os.system('cp -r /mnt/vfxserver01/Tools/_configuration_files/usr/lib/systemd/system/afrender.service /usr/lib/systemd/system/')
                        os.symlink('/usr/lib/systemd/system/afrender.service', '/etc/systemd/system/multi-user.target.wants/afrender.service')
                        os.system('systemctl enable afrender')
                        time.sleep(1)
                    except OSError as e:
                        print("Error: %s : %s" % (path, e.strerror))

        print("Installing soft for afrender ... Done")

    # SOFT FOR VFXSTATION
    if input('Install soft for vfxstation? [y/N] ').lower() == 'y':
        os.system('pacman -S --needed --noconfirm sddm plasma-desktop plasma-pa plasma-systemmonitor kdeplasma-addons breeze breeze-gtk kde-gtk-config konsole dolphin pulseaudio pulseaudio-alsa gwenview okular spectacle simplescreenrecorder filezilla firefox firefox-adblock-plus ttf-dejavu ttf-liberation ttf-bitstream-vera cantarell-fonts ark kscreen krename kate ktorrent kolourpaint kdenlive mpv mediainfo inkscape python-pyqt5 python-lxml telegram-desktop nvidia-lts opencl-nvidia pyside2 qt5-xmlpatterns zenity hddtemp psensor')

        f = open('/etc/sddm.conf', 'w')
        f.write('[Theme]\nCurrent=breeze\n\n')
        f.write('[Users]\nMaximumUid=99999\nMinimumUid=99999')
        f.close()

        os.system('systemctl enable sddm')
        time.sleep(1)
        print("Installing software for vfxstation ... Done")

# LINKING SOFT
def link_soft ():

    os.symlink('/mnt/vfxserver01/Programs', '/soft')

    os.remove('/etc/skel/.bashrc')
    os.symlink('/mnt/vfxserver01/Tools/_user_preferences/bashrc', '/etc/skel/.bashrc')

    # Nuke Preferences
    os.mkdir('/etc/skel/.nuke')
    os.symlink('/mnt/vfxserver01/Tools/Nuke/menu.py', '/etc/skel/.nuke/menu.py')
    os.symlink('/mnt/vfxserver01/Tools/Nuke/init.py', '/etc/skel/.nuke/init.py')
    os.symlink('/mnt/vfxserver01/Tools/Nuke/ToolSet', '/etc/skel/.nuke/ToolSet')

    # Houdini Preferences
    os.symlink('/mnt/vfxserver01/Tools/_user_preferences/sesi_licenses.pref', '/etc/skel/.sesi_licenses.pref')

    # Soft
    os.mkdir('/etc/opt')
    os.symlink('/soft/cgru/cgru', '/opt/cgru')
    os.symlink('/soft/isl', '/opt/isl')
    os.symlink('/soft/isl', '/etc/opt/isl')
    os.symlink('/soft/OFX', '/usr/OFX')
    os.symlink('/soft/houdini', '/opt/houdini')
    os.symlink('/soft/foundry', '/usr/local/foundry')
    os.symlink('/soft/nuke/Nuke13.2v5', '/usr/local/Nuke13.2v5')

    # Additional links
    os.symlink('/lib/libidn.so.12', '/lib/libidn.so.11')
    os.symlink('/lib/libcrypt.so.2', '/lib/libcrypt.so.1')
    os.symlink('/lib/libpython3.10.so', '/lib/libpython3.9.so.1.0')

    time.sleep(1)
    print("Linking software ... Done")

# SUSPEND & HIBERNATE
def stop_sleep_suspend_and_hibernate ():

    os.system('systemctl mask suspend.target hibernate.target suspend-then-hibernate.target hybrid-sleep.target')

    time.sleep(1)
    print("Stopping sleep, suspend, hibernate modes ... Done")

# USERS
def create_users ():

    if input('Create master user? (Y/n) ').lower() in {'y', ''}:
        os.system('useradd -G wheel,power,video,storage,lp,input,audio -s /bin/bash -m master')
        os.system('passwd master')

    if input('Create render user? (Y/n) ').lower() in {'y', ''}:
        os.system('useradd -g 1000 -s /bin/bash -m render')

    if input('Create user? (Y/n) ').lower() in {'y', ''}:
        user = input('Enter user name: ').lower()
        os.system('useradd -g 1000 -G  power,video,storage,lp,input,audio -s /bin/bash -m ' + user)
        os.system('passwd ' +  user)

    time.sleep(1)
    print("Creating users ... Done")

# BASE DIRECTORIES
def create_base_directories ():

    hostname = os.uname().nodename

    os.mkdir('/mnt/' + hostname + '/Temp', 0o777)
    os.mkdir('/mnt/' + hostname + '/Temp/Media', 0o777)
    os.mkdir('/mnt/' + hostname + '/Temp/MoTemp', 0o777)
    os.mkdir('/mnt/' + hostname + '/Temp/Blender', 0o777)
    os.mkdir('/mnt/' + hostname + '/Temp/Houdini', 0o777)
    os.mkdir('/mnt/' + hostname + '/Temp/Nuke', 0o777)
    os.mkdir('/mnt/' + hostname + '/Temp/Nuke/nuke-u1000', 0o777)
    os.mkdir('/mnt/' + hostname + '/Temp/Nuke/nuke-u1001', 0o777)
    os.mkdir('/mnt/' + hostname + '/Temp/Nuke/nuke-u1002', 0o777)

    os.system('chmod -R 777 /mnt/' + hostname + '/Temp')

    time.sleep(1)
    print("Creating base directories ... Done")

# MENU ICONS
def create_icons ():

    icons_path = '/mnt/vfxserver01/Tools/_configuration_files/usr/share/applications/'

    if os.path.exists(icons_path):

        try:
            icons = os.listdir(icons_path)

            for icon in icons:

                src = icons_path + icon
                des = '/usr/share/applications/' + icon

                if not os.path.exists(des):
                    os.symlink(src, des)

        except OSError as e:
            print("Error: %s : %s" % (icons_path, e.strerror))

    time.sleep(1)
    print("Creating menu icons ... Done")

# MAIN
def main ():

    if input('Setup automount? [y/N]: ').lower() == 'y':
        setup_automount()

    if input('Setup pacman cache directory? [y/N] ').lower() == 'y':
        setup_pacman_cache()

    if input('Install software? [y/N] ').lower() == 'y':
        install_soft()

    if input('Create links to the programs? [y/N] ').lower() == 'y':
        link_soft()

    if input('Disable suspend & hibernate modes? [y/N] ').lower() == 'y':
        stop_sleep_suspend_and_hibernate()

    if input('Create users? [y/N] ').lower() == 'y':
        create_users()

    if input('Create base directories? [y/N] ').lower() == 'y':
        create_base_directories()

    if input('Create menu icons for applications? [y/N] ').lower() == 'y':
        create_icons()

if __name__ == '__main__':
    main()
