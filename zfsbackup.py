#!/bin/env python

import os
import sys
import subprocess

from colorama import Fore, Style
from datetime import datetime


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

    message(f"No {pool} pool found", False)

    return False


def get_datasets(pool: str) -> list[str]:
    output = subprocess.run(
        "zfs list -r " + pool + " | grep -v @",
        shell=True,
        capture_output=True,
        text=True,
    )
    lines = output.stdout.splitlines()

    datasets = [line.split()[0] for line in lines[2:]]
    if datasets:
        message(f"Found datasets in {pool}", True)
    else:
        message(f"No datasets found in {pool}", False)

    return datasets


def filter_datasets(datasets: list[str], keywords: list[str]) -> list[str]:
    return [
        dataset for dataset in datasets if not any(word in dataset for word in keywords)
    ]


def filter_datasets_for_backup(host: str, datasets: list[str]) -> list[str]:
    match host:
        case "vfxserver02":
            datasets = filter_datasets(datasets, ["Caches", "Trash"])
        case "vfxcache02":
            datasets = filter_datasets(
                datasets, ["Programs", "Projects", "Tools", "Trash"]
            )
        case _:
            datasets = filter_datasets(datasets, ["Trash"])

    message("Filtered datasets for backup", True)

    return datasets


def create_snapshots(datasets: list[str]) -> list[str]:
    snapshots = []
    for dataset in datasets:
        try:
            snapshot = f"{dataset}@{datetime.today().strftime('%Y.%m.%d_%H:%M:%S')}"
            subprocess.run(
                f"zfs snapshot {snapshot}",
                shell=True,
                capture_output=True,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as error:
            message(f"Failed to create snapshot for {dataset}", False)
            print(f"Error: {error.stderr}")
        else:
            snapshots.append(snapshot)
            message(f"Created snapshot for {dataset}", True)

    return snapshots


def zfsbackup(host):
    message(f"Starting backup scenario for {host}", True)

    if check_pool("zdata"):
        datasets = get_datasets("zdata")
    else:
        sys.exit()

    datasets = filter_datasets_for_backup(host, datasets)

    snapshots = create_snapshots(datasets)

    # for dataset in datasets:
    #     print(dataset)

    # for snapshot in snapshots:
    #     print(snapshot)


# MAIN
def main():
    HOSTNAME = os.uname()[1]
    HOSTNAME = "vfxserver02"

    zfsbackup(HOSTNAME)


if __name__ == "__main__":
    main()
