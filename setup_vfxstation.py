#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os, shutil, time, re, socket
from subprocess import call, Popen, PIPE

def setup_automount ():

    if not os.path.exists('/mnt/vfxserver01'):
        os.makedir('/mnt/vfxserver01', 0o755)

    if not os.path.exists('/mnt/vfxbackup01'):
        os.makedir('/mnt/vfxbackup01', 0o755)

    f = open('/home/master/fstab', 'a')
    f.write('\n# SERVERS\n')
    f.write('192.168.20.10:/mnt/vfxbackup01\t\t\t\t/mnt/vfxbackup01\tnfs\t_netdev,x-systemd.mount-timeout=10,hard,intr,noatime\t0 0\n')
    f.write('192.168.20.11:/mnt/vfxserver01\t\t\t\t/mnt/vfxbackup01\tnfs\t_netdev,x-systemd.mount-timeout=10,hard,intr,noatime\t0 0\n')
    f.close()

    time.sleep(1)
    print('Setting up automount ... Done')

def setup_pacman_cache ():

    path = '/home/master/1'
    try:
        shutil.rmtree(path)
    except OSError as e:
        print("Error: %s : %s" % (path, e.strerror))

    f = open('/home/master/fstab', 'a')
    f.write('\n# PACMAN CACHE\n')
    f.write('192.168.20.11:/mnt/vfxserver01/Tool/_caches/pacman\t/var/cache/pacman\tnfs\t_netdev,x-systemd.mount-timeout=0,hard,intr,noatime\t0 0\n')
    f.close()

    time.sleep(1)
    print('Setting up pacman cache ... Done')

def install_soft ():
    print("Installing soft ... Done")

def link_soft ():
    print("Creating links ... Done")

def stop_sleep_suspend_and_hibernate ():
    print("Stopping sleep, suspend, hibernate modes ... Done")

def create_users (master, render, user):
    print("Creating users ... Done")

def create_base_directories ():
    print("Creating base directories ... Done")

def main ():

    if input('Setup automount? [y/N]: ').lower() == 'y':
        setup_automount()

    if input('Mount pacman cache directory from server? [y/N] ').lower() == 'y':
        setup_pacman_cache()

if __name__ == '__main__':
    main()
