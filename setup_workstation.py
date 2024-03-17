#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os, sys, subprocess


# DISKs INFO
def get_volumes():

    # Get the list of DEVICES
    lsblk = subprocess.check_output('lsblk').decode('UTF-8').splitlines()

#    lsblk = 'sdg1        8:97   0  12,5T  0 part \nsdh           8:112  0  12,7T  0 disk \n└─sdh1        8:113  0  12,5T  0 part \nsdi           8:128  0  12,7T  0 disk \n└─sdi1        8:129  0  12,5T  0 part \nsdj           8:144  0  12,7T  0 disk \n└─sdj1        8:145  0  12,5T  0 part \nsdk           8:160  0  12,7T  0 disk \n└─sdk1        8:161  0  12,5T  0 part \nsdl           8:176  0  12,7T  0 disk \n└─sdl1        8:177  0  12,5T  0 part \nsdm           8:192  1     0B  0 disk \nsr0          11:0    1  1024M  0 rom  \nnvme1n1     259:0    0 232,9G  0 disk \n├─nvme1n1p1 259:1    0    75G  0 part \n└─nvme1n1p2 259:2    0 157,9G  0 part \nnvme0n1     259:3    0 476,9G  0 disk \n├─nvme0n1p1 259:4    0     1G  0 part \n├─nvme0n1p2 259:5    0   256G  0 part \n├─nvme0n1p3 259:6    0    40G  0 part \n├─nvme0n1p4 259:7    0    40G  0 part \n├─nvme0n1p5 259:8    0    40G  0 part \n└─nvme0n1p6 259:9    0  99,9G  0 part \n'
 #   lsblk = lsblk.splitlines()

    devs = []
    for line in lsblk:
        if not line.find('├') or not line.find('└'):
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
    print('=' * 40)
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
        if volume['mountpoint'] != None:
            if input('\nWARNING! Some volumes are mounted. Continue? [y/N] ').lower() == 'y':
                break
            else:
                sys.exit()

    # Format VOLUMEs
    print('=' * 40)
    print('Format VOLUMEs:')
    print('=' * 40)

    for volume in vols:
        if volume['mountpoint'] == None:
            match volume['name']:
                case 'nvme0n1p1':
                    if input('Format /dev/nvme0n1p1? [y/N] ').lower() == 'y':
#                        os.system('mkfs.vfat /dev/nvme0n1p1')
                        print('Formatting /dev/nvme0n1p1 as FAT32')
                case 'nvme0n1p2':
                    if input('Format /dev/nvme0n1p2? [y/N] ').lower() == 'y':
#                        os.system('mkswap /dev/nvme0n1p2')
                        print('Formatting /dev/nvme0n1p2 as SWAP')
                case _:
                    if input('Format /dev/' + volume['name'] + '? [y/N] ').lower() == 'y':
#                        os.system('mkfs.ext4 /dev/' + volume['name'])
                        print('Formatting /dev/' + volume['name'] + ' as EXT4')
        else:
            print('The ' + volume['name'] +' is mounted. Skipping!')


# MOUNT VOLUMEs
def mount_volumes(hostname):

    # Mount VOLUMEs
    print('=' * 40)
    print('Mount VOLUMEs:')
    print('=' * 40)

    print('Mounting /dev/nvme0n1p2 at SWAP')
#    os.system('swapon /dev/nvme0n1p2')
    print('Mounting /dev/nvme0n1p3 at /mnt')
#    os.system('mount /dev/nvme0n1p3 /mnt')
    print('Creating /mnt/boot')
#    os.mkdir('/mnt/boot')
    print('Mounting /dev/nvme0n1p1 at /mnt/boot')
#    os.system('mount /dev/nvme0n1p1 /mnt/boot')
    print('Creating /mnt/var')
#    os.mkdir('/mnt/var')
    print('Mounting /dev/nvme0n1p4 at /mnt/boot')
#    os.system('mount /dev/nvme0n1p4 /mnt/var')
    print('Creating /mnt/tmp')
#    os.mkdir('/mnt/tmp', 0o777)
    print('Mounting /dev/nvme0n1p5 at /mnt/tmp')
#    os.system('mount /dev/nvme0n1p5 /mnt/tmp')
    print('Creating /mnt/home')
#    os.mkdir('/mnt/home')
    print('Mounting /dev/nvme0n1p6 at /mnt/home')
#    os.system('mount /dev/nvme0n1p6 /mnt/home')
    print('Creating /mnt/mnt/' + hostname)
#    os.makedirs('/mnt/mnt/' + hostname)
    print('Mounting /dev/nvme0n1p7 at /mnt/mnt/' + hostname)
#    os.system('mount /dev/nvme0n1p7 /mnt/mnt/' + hostname)


# PACSTRAP
def pacstrap(hostname):

    print('=' * 40)
    print('PACSTRAP:')
    print('=' * 40)

    print('Install base packages')
#    os.system('pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware python neovim nfs-utils dkms bash-completion man openssh rsync reflector terminus-font')

    if input('\nChoose ucode type: 1 - AMD, 2 - Intel? [1 - default] ').lower() == '2':
        print('Installing intel-ucode')
#        os.system('pacstrap /mnt intel-ucode')
        ucode = 'intel-ucode.img'
    else:
        print('Install amd-ucode')
#        os.system('pacstrap /mnt amd-ucode')
        ucode = 'amd-ucode.img'

    print('\nGenerate /etc/fstab')
#    os.system('genfstab -U /mnt >> /mnt/etc/fstab')

    print('Arch-Chroot /mnt')
#    os.system('arch-chroot /mnt')

    print('Link /etc/localtime')
#    os.system('ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime')

    print('Sync hardware clock')
#    os.system('hwclock --systohc')

    print('Mount vfxserver01/Tools at /mnt')
#    os.system('mount -t nfs 192.168.20.11:/mnt/vfxserver01/Tools /mnt')

    print('Setup locale to ru_RU.UTF-8')
#    os.system('cp -v /mnt/_configuration_files/etc/locale* /etc')
#    os.system('cp -v /mnt/_configuration_files/etc/vconsole.conf /etc')
#    locale-gen

    print('Setup hostname')
#    with open('/etc/hostname', 'w') as f:
#        f.write(hostname)

    print('Setup /etc/modprobe.d/blacklist.conf')
#    os.system('cp -v /mnt/_configuration_files/etc/modprobe.d/blacklist.conf /etc')

    print('Setup /etc/systemd/system/systemd-networkd.service')
#    os.system('cp -v /mnt/_configuration_files/etc/systemd/network/20-wired.network /etc/systemd/network')
#    os.system('systemctl enable systemd-networkd.service')

    print('Setup /etc/systemd/system/systemd-resolved.service')
#    os.system('systemctl enable systemd-resolved.service')

    print('Setup /etc/systemd/system/sshd.service')
#    os.system('systemctl enable sshd.service')

    print('Setup /etc/systemd/system/systemd-timesyncd.service')
#    os.system('cp -v /mnt/_configuration_files/etc/systemd/timesyncd.conf /etc/systemd')

    print('Setup /etc/pacman.d/mirrorlist via Reflector')
#    os.system('reflector -c Russia --sort rate --save /etc/pacman.d/mirrorlist')

    print('Set root password')
#    os.system('passwd')

    print('Setup bootloader')
#    os.system('bootctl install')
#    os.system('cp -v /mnt/_configuration_files/boot/loader/loader.conf /boot/loader')

    blkid = subprocess.check_output('blkid').decode('UTF-8').splitlines()
    uuid = ''
    for line in blkid:
        if line.find('nvme0n1p3'):
            uuid = line.split()[1]
            break

#    with open('/boot/loader/entries/arch.conf', 'w') as f:
#        f.write('title   Arch Linux\n')
#        f.write('linux   /vmlinuz-linux-lts\n')
#        f.write('initrd  /initramfs-linux-lts.img\n')
#        f.write('initrd  /' + ucode + '\n')
#        f.write('options root=' + uuid + ' rw nowatchdog loglevel=3 nvidia_drm.modeset=1')

    print('Copy setup_vfxstation.py to /root')
#    os.system('cp -v /mnt/_shell_tools/setup_vfxstation.py /root')

    print('Unmount /mnt/vfxserver01')
#    os.system('umount /mnt')

    print('Exit')
#    os.system('exit')

    print('Unmount /mnt')
#    os.system('umount -R /mnt')

    print('\nFinished!\nSystem ready to reboot.')


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
        
    if input('\nStart pacstrap? [y/N]: ').lower() == 'y':
        pacstrap(hostname)

if __name__ == '__main__':
    main()
