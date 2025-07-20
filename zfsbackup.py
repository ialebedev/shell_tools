#!/bin/env python

# uv add zfslib

import os
import subprocess

from colorama import Fore, Style


def get_pools() -> []:
    output = subprocess.run("zpool list", shell=True, capture_output=True, text=True)
    lines = output.stdout.splitlines()

    pools = [line.split()[0] for line in lines[1:]]
    print(f"Found ZFS pools: {', '.join(pools)}")

    return pools

def get_datasets(pools: list[str]) -> list[str]:
    for pool in pools:
        output = subprocess.run("zfs list", shell=True, capture_output=True, text=True)
        lines = output.stdout.splitlines()

        datasets = [line.split()[0] for line in lines[1:]]
        print(f"Found ZFS datasets: {', '.join(datasets)}")
    

def zfsbackup(host):
    print(
        f"Starting backup scenario for {host}\t\t[ {Fore.GREEN} OK {Style.RESET_ALL} ]"
    )

    pools = get_pools()
    datasets = get_datasets(pools)
    

# MAIN
def main():
    HOSTNAME = os.uname()[1]

    zfsbackup(HOSTNAME)


if __name__ == "__main__":
    main()
