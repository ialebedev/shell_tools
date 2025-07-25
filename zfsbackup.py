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
    output = subprocess.run(
        "zpool list -H -o name", shell=True, capture_output=True, text=True
    )
    pools = output.stdout.splitlines()

    if pool in pools:
        message(f"Found {pool} pool", True)
        return True
    else:
        message(f"No {pool} pool found", False)
        return False


def get_datasets(pool: str) -> list[str]:
    datasets = subprocess.run(
        f"zfs list -r -H -t filesystem {pool} -o name",
        shell=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()[1:]

    if datasets:
        message(f"Found datasets in {pool}", True)
    else:
        message(f"No datasets found in {pool}", False)

    return datasets


def get_snapshots(dataset: str) -> list[str]:
    snapshots = subprocess.run(
        f"zfs list -H -t snapshot {dataset} -o name",
        shell=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()

    return snapshots


def filter_datasets(datasets: list[str], keywords: list[str]) -> list[str]:
    return [
        dataset for dataset in datasets if not any(word in dataset for word in keywords)
    ]


def filter_datasets_for_backup(host: str, datasets: list[str]) -> list[str]:
    match host:
        case "vfxserver02":
            datasets = filter_datasets(datasets, ["Caches", "Trash"])
            exclude = "zdata/Projects"
            if exclude in datasets:
                datasets.remove(exclude)
        case "vfxcache02":
            datasets = filter_datasets(
                datasets, ["Programs", "Projects", "Tools", "Trash"]
            )
            exclude = "zdata/Caches"
            if exclude in datasets:
                datasets.remove(exclude)
        case _:
            datasets = filter_datasets(datasets, ["Trash"])

    message("Filtered datasets for backup", True)

    return datasets


def create_snapshots(datasets: list[str]) -> list[str]:
    snapshots = []
    for dataset in datasets:
        try:
            last_snapshot = get_snapshots(dataset)[-1]
            new_snapshot = f"{dataset}@{datetime.today().strftime('%Y.%m.%d_%H:%M:%S')}"
            subprocess.run(
                f"zfs snapshot {new_snapshot}",
                shell=True,
                capture_output=True,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as error:
            message(f"Failed to create snapshot for {dataset}", False)
            print(f"Error: {error.stderr}")
        else:
            snapshots.append(last_snapshot)
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
