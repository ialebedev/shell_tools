#!/bin/env python

# uv add zfslib

import os
import sys
import subprocess

from colorama import Fore, Style


def message(message: str, status: bool):
    if status:
        print(f"{message:<70}[ {Fore.GREEN} OK {Style.RESET_ALL} ]")
    else:
        print(f"{message:<70}[ {Fore.RED}Fail{Style.RESET_ALL} ]")


def check_pool(pool: str) -> bool:
    output = subprocess.run("zpool list", shell=True, capture_output=True, text=True)
    lines = output.stdout.splitlines()

    for line in lines[1:]:
        if pool == line.split()[0]:
            message(f"Found {pool} pool", True)
            return True

    message(f"No {pool} pool found. Exit", False)

    return False


def get_datasets(pool: str) -> list[str]:
    output = subprocess.run(
        "zfs list -r " + pool, shell=True, capture_output=True, text=True
    )
    lines = output.stdout.splitlines()

    datasets = [line.split()[0] for line in lines[2:]]
    if datasets:
        message(f"Found datasets in {pool}", True)

        # for dataset in datasets:
        #     print(dataset)
    else:
        message(f"No datasets found in {pool}. Exit", False)

    return datasets


def zfsbackup(host):
    message(f"Starting backup scenario for {host}", True)

    if check_pool("zdata"):
        datasets = get_datasets("zdata")
    else:
        sys.exit()        



# MAIN
def main():
    HOSTNAME = os.uname()[1]

    zfsbackup(HOSTNAME)


if __name__ == "__main__":
    main()
