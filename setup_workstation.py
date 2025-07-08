#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import stat
import sys
import subprocess


# DISKs INFO
def get_volumes():

    # Get the list of DEVICES
    lsblk = subprocess.check_output('lsblk').decode('UTF-8').splitlines()

    devs = []
    for line in lsblk:
        if line.find('nvme') > 1:
            devs.append(line[2:])

    vols = []
    for line in devs:
        parts = line.split()
        if len(parts) >= 6:
            volume = {
                'name': parts[0],
                'size': parts[3],
                'mountpoint': parts[6] if len(parts) > 6 else None
            }
            vols.append(volume)

    # Print list of found VOLUMEs
    print('\n' + '=' * 40)
    print('Found VOLUMEs:')
    print('=' * 40)

    for volume in vols:
        if len(volume['name']) <= 8:
            print(volume['name'], '\t\t', volume['size'], '\t\t', volume['mountpoint'])
        else:
            print(volume['name'], '\t', volume['size'], '\t\t', volume['mountpoint'])

    return vols


# FORMAT VOLUMES
def format_volumes(vols):

    # Check for mounted VOLUMEs
    for volume in vols:
        if volume['mountpoint'] is not None:
            if input('\nWARNING! Some volumes are mounted. Continue? [y/N] ').lower() == 'y':
                break
            else:
                sys.exit()

    # Format VOLUMEs
    print('=' * 40)
    print('Format VOLUMEs:')
    print('=' * 40)

    for volume in vols:
        if volume['mountpoint'] is None:
            match volume['name']:
                case 'nvme0n1p1':
                    if input('Format /dev/nvme0n1p1? [y/N] ').lower() == 'y':
                        os.system('mkfs.vfat /dev/nvme0n1p1')
                        print('Format /dev/nvme0n1p1 as FAT32')
                case 'nvme0n1p2':
                    if input('\nFormat /dev/nvme0n1p2? [y/N] ').lower() == 'y':
                        os.system('mkswap /dev/nvme0n1p2')
                        print('Format /dev/nvme0n1p2 as SWAP')
                case _:
                    if input('\nFormat /dev/' + volume['name'] + '? [y/N] ').lower() == 'y':
                        os.system('mkfs.ext4 /dev/' + volume['name'])
                        print('Format /dev/' + volume['name'] + ' as EXT4')
        else:
            print('The ' + volume['name'] +' is mounted. Skipping!')


# MOUNT VOLUMEs
def mount_volumes(hostname):

    # Mount VOLUMEs
    print('=' * 40)
    print('Mount VOLUMEs:')
    print('=' * 40)

    print('Mounting /dev/nvme0n1p2 at SWAP')
    os.system('swapon /dev/nvme0n1p2')
    print('\nMounting /dev/nvme0n1p3 at /mnt')
    os.system('mount /dev/nvme0n1p3 /mnt')

    dirs = ['boot', 'var', 'tmp', 'home', hostname]
    for dir in dirs:
        match dir:
            case 'boot':
                path = '/mnt/boot'
                print('\nCreating ' + path)
                os.makedirs(path, exist_ok=True)
                print('Mounting /dev/nvme0n1p1 at ' + path)
                os.system('mount /dev/nvme0n1p1 ' + path)
            case 'var':
                path = '/mnt/var'
                print('\nCreating ' + path)
                os.makedirs(path, exist_ok=True)
                print('Mounting /dev/nvme0n1p4 at ' + path)
                os.system('mount /dev/nvme0n1p4 ' + path)
            case 'tmp':
                path = '/mnt/tmp'
                print('\nCreating ' + path)
                os.makedirs(path, exist_ok=True, mode=0o777)
                print('Mounting /dev/nvme0n1p5 at ' + path)
                os.system('mount /dev/nvme0n1p5 ' + path)
            case 'home':
                path = '/mnt/home'
                print('\nCreating ' + path)
                os.makedirs(path, exist_ok=True)
                print('Mounting /dev/nvme0n1p6 at ' + path)
                os.system('mount /dev/nvme0n1p6 ' + path)
            case _:
                path = '/mnt/mnt/' + hostname
                print('\nCreating ' + path)
                os.makedirs(path, exist_ok=True)
                print('Mounting /dev/nvme0n1p7 at ' + path)
                os.system('mount /dev/nvme0n1p7 ' + path)


# PACSTRAP & Configuration
def pacstrap(hostname):

    os.system('reflector -l 5 -c Russia --sort rate --save /etc/pacman.d/mirrorlist')
    
    print('=' * 40)
    print('PACSTRAP & Configuration:')
    print('=' * 40)

    if input('Choose ucode type: 1 - AMD, 2 - Intel? [1 - default] ').lower() == '2':
        ucode = 'intel-ucode'
    else:
        ucode = 'amd-ucode'

    print('Installing base packages')
    os.system('pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware python helix nfs-utils dkms bash-completion man openssh rsync reflector terminus-font wget ' + ucode)

    print('\nGenerating /etc/fstab')
    os.system('genfstab -U /mnt >> /mnt/etc/fstab')
        
    print('\nSetting up /etc/hostname')
    with open('/mnt/etc/hostname', 'w') as f:
        f.write(hostname + '\n')

    print('\nSetting up /etc/hosts')
    with open('/mnt/etc/hosts', 'a') as f:
        f.write('\n127.0.0.1\tlocalhost'.expandtabs())
        f.write('\n::1\t\tlocalhost'.expandtabs())
        f.write(('\n127.0.1.1\t' + hostname + '.local\t\t' + hostname + '\n').expandtabs())
        f.write('\n192.168.20.10\tvfxcache01.local\tvfxcache01'.expandtabs())
        f.write('\n192.168.20.11\tvfxserver01.local\tvfxserver01'.expandtabs())
        f.write('\n192.168.20.12\tvfxstorage01.local\tvfxstorage01'.expandtabs())
        f.write('\n192.168.20.13\tvfxstorage02.local\tvfxstorage02'.expandtabs())
        f.write('\n192.168.20.14\tvfxcache02.local\tvfxcache02'.expandtabs())
        f.write('\n192.168.20.15\tvfxserver02.local\tvfxserver02\n'.expandtabs())

    print('\nSetting up /etc/modprobe.d/blacklist.conf')
    with open('/mnt/etc/modprobe.d/blacklist.conf', 'w') as f:
        f.write('blacklist nouveau\n')
        f.write('options nouveau modeset=0\n')

    print('\nSetting up systemd services')
    with open('/mnt/etc/systemd/network/20-wired.network', 'w') as f:
        f.write('[Match]\n')
        f.write('Name=enp*\n\n')
        f.write('[Network]\n')
        f.write('DHCP=yes\n')
    os.system('arch-chroot /mnt systemctl enable systemd-networkd.service')
    os.system('arch-chroot /mnt systemctl enable systemd-resolved.service')
    os.system('arch-chroot /mnt systemctl enable sshd.service')
            
    print('\nSetting up /etc/pacman.conf')
    with open('/mnt/etc/pacman.conf', 'r+') as f:
        data = f.read()
        data = data.replace('#Color', 'Color')
        data = data.replace('#ParallelDownloads', 'ParallelDownloads')

        f.seek(0)
        f.write(data)
        f.truncate()

    print('\nSetting root password')
    os.system('arch-chroot /mnt passwd')

    print('Setting up systemd-boot')
    os.system('arch-chroot /mnt bootctl install')

    blkid = subprocess.check_output('blkid').decode('UTF-8').splitlines()
    uuid = ''
    for line in blkid:
        if 'nvme0n1p3' in line:
            uuid = line.split()[1]
            break

    with open('/mnt/boot/loader/loader.conf', 'w') as f:
        f.write('timeout 3\n')
        f.write('console-mode max\n')
        f.write('editor yes\n')
        f.write('default arch.conf\n')

    with open('/mnt/boot/loader/entries/arch.conf', 'w') as f:
        f.write('title   Arch Linux\n')
        f.write('linux   /vmlinuz-linux-lts\n')
        f.write('initrd  /initramfs-linux-lts.img\n')
        f.write('initrd  /' + ucode + '.img\n')
        f.write('options root=' + uuid + ' rw nowatchdog loglevel=3 nvidia_drm.modeset=1\n')

    with open('/mnt/boot/loader/entries/arch-fallback.conf', 'w') as f:
        f.write('title   Arch Linux (fallback)\n')
        f.write('linux   /vmlinuz-linux-lts\n')
        f.write('initrd  /initramfs-linux-lts-fallback.img\n')
        f.write('initrd  /' + ucode + '.img\n')
        f.write('options root=' + uuid + ' rw nowatchdog\n')
        
    print('\nCopy setup_vfxstation.py to /root')
    os.system('arch-chroot /mnt wget https://raw.githubusercontent.com/ialebedev/shell_tools/main/setup_vfxstation.py -P /root')
    os.chmod('/mnt/root/setup_vfxstation.py', stat.S_IRWXU)

    print('\nSetting up /etc/resolv.conf')
    with open('/mnt/etc/resolv.conf', 'a') as f:
        f.write('\nnameserver 192.168.20.1\n')

    print('\nSetting up /usr/local/bin/hx')
    os.system('arch-chroot ln -s /usr/bin/helix /usr/local/bin/hx')
    
    print('\nUnmountting /mnt')
    os.system('umount -R /mnt')

    print('\nFinished!\n\nSystem ready to reboot.')


# MAIN
def main ():

    os.system('timedatectl set-ntp true')

    while True:
        hostname = input('\nPlease enter the hostname for this station: ')
        if input('The hostname is ' + hostname + '. Correct? [y/N] ').lower() == 'y':
            break
    
    vols = get_volumes()

    if input('\nFormat disks? [y/N] ').lower() == 'y':
        format_volumes(vols)

    if input('\nMount disks? [y/N] ').lower() == 'y':
        mount_volumes(hostname)
        
    if input('\nStart pacstrap and configuration? [y/N]: ').lower() == 'y':
        pacstrap(hostname)

if __name__ == '__main__':
    main()
