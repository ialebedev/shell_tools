#!/bin/env python

# pipx install zfslib

import os, subprocess, time
#import zfslib as zfs

GREEN = '\u001b[38;5;46m'
RESET = '\u001b[0m'

def zfsbackup (host):

    print("Started backup scenario for {}\t\t[".format(host) + GREEN + "  OK  " + RESET + "]")

    match host:

        case 'vfxcache01':
            zfs_backup_vfxcache01()
            
        case 'vfx':
            zfs_backup_vfxserver01()

        case 'vfxstorage01':
            zfs_backup_vfxstorage01()

        case 'vfxstorage02':
            zfs_backup_vfxstorage02()

        case _:
            print("No backup scenario for {}.".format(host))


# VFXCACHE01
def zfs_backup_vfxcache01 ():

    datasets = subprocess.check_output(['zfs', 'list']).decode('UTF-8').splitlines()


# VFXSERVER01
def zfs_backup_vfxserver01 ():

    #datasets = subprocess.check_output(['zfs', 'list']).decode('UTF-8').splitlines()
    datasets = subprocess.Popen(['zfs', 'list'], stdout=subprocess.PIPE, close_fds=True)

    print(datasets)


# VFXSTORAGE01
def zfs_backup_vfxstorage01 ():

    datasets = subprocess.check_output(['zfs', 'list']).decode('UTF-8').splitlines()



# VFXSTORAGE02
def zfs_backup_vfxstorage02 ():

    datasets = subprocess.check_output(['zfs', 'list']).decode('UTF-8').splitlines()



# MAIN
def main ():

    HOSTNAME = os.uname()[1]
#    HOSTNAME = 'vfxcache01'

    zfsbackup(HOSTNAME)


if __name__ == '__main__':
    main()
