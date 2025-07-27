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


def check_pool(pool: str):
    output = subprocess.run(
        "zpool list -H -o name", shell=True, capture_output=True, text=True
    )
    pools = output.stdout.splitlines()

    if pool in pools:
        message(f"Found {pool} pool", True)
    else:
        message(f"No {pool} pool found", False)
        sys.exit(1)


def get_datasets(pool: str) -> list[str]:
    datasets = subprocess.run(
        f"zfs list -r -H -t filesystem {pool} -o name",
        shell=True,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()[1:]

    if datasets:
        message(f"Found datasets in {pool}", True)
    else:
        message(f"No datasets found in {pool}", False)
        sys.exit(1)

    return datasets


def get_snapshots(dataset: str) -> list[str]:
    snapshots = subprocess.run(
        f"zfs list -H -t snapshot {dataset} -o name",
        shell=True,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()

    return snapshots


def diff_snapshots(prev: str, last: str) -> bool:
    try:
        diff = subprocess.run(
            f"zfs diff {prev} {last}",
            shell=True,
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as error:
        message(f"Failed to compare snapshots {prev} and {last}", False)
        print(f"Error: {error.stderr}")
        sys.exit(1)
    else:
        if diff.stdout:
            return True
        else:
            return False


def delete_snapshot(snapshot: str):
    try:
        subprocess.run(
            f"zfs destroy {snapshot}",
            shell=True,
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as error:
        message(f"Failed to delete {snapshot}", False)
        print(f"Error: {error.stderr}")
    else:
        message(f"Deleted {snapshot}", True)


def send_snapshots(datasets: list[str], target: str):
    for dataset in datasets:
        snapshots = get_snapshots(dataset)
        if not snapshots:
            message(f"No snapshots found in {dataset}", False)
            continue

        last_snapshot = snapshots[-1]
        if len(snapshots) == 1:
            # print(f"{dataset}\nPrev snapshot = None\nLast = {last_snapshot}")
            # print(f"zfs send -Lv {last_snapshot} | ssh {target} zfs receive -d zdata")
            message(f"Sent {last_snapshot}", True)
            continue

        if len(snapshots) >= 2:
            prev_snapshot = snapshots[-2]
            # print(f"{dataset}\nPrev snapshot = {prev_snapshot}\nLast = {last_snapshot}")
            # print(
            #     f"zfs send -Lvi {prev_snapshot} {last_snapshot} | ssh {target} zfs receive -d zdata"
            # )
            if diff_snapshots(prev_snapshot, last_snapshot):
                message(f"Sent {last_snapshot}", True)
            else:
                delete_snapshot(last_snapshot)


def filter_datasets(datasets: list[str], keywords: list[str]) -> list[str]:
    return [
        dataset for dataset in datasets if not any(word in dataset for word in keywords)
    ]


def filter_datasets_for_backup(host: str, datasets: list[str]) -> list[str]:
    match host:
        case "vfxserver01" | "vfxserver02":
            datasets = filter_datasets(datasets, ["Caches", "Trash"])
            exclude = "zdata/Projects"
            if exclude in datasets:
                datasets.remove(exclude)
        case "vfxcache01" | "vfxcache02":
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
            sys.exit(1)
        else:
            snapshots.append(snapshot)
            message(f"Created snapshot for {dataset}", True)

    return snapshots


def zfsbackup(host):
    message(f"Starting backup scenario for {host}", True)

    check_pool("zdata")

    datasets = get_datasets("zdata")
    datasets = filter_datasets_for_backup(host, datasets)

    # for dataset in datasets:
    # print(dataset)

    snapshots = create_snapshots(datasets)

    # for snapshot in snapshots:
    # print(snapshot)

    match host:
        case "vfxcache01":
            target = "192.68.20.11"
        case "vfxserver01":
            target = "192.168.20.10"
        case "vfxcache02":
            target = "192.168.20.15"
        case "vfxserver02":
            target = "192.168.20.14"
        case "vfxstorage01":
            target = "192.168.20.13"
        case "vfxstorage02":
            target = "192.168.20.12"
        case _:
            target = "localhost"

    send_snapshots(datasets, target)


# MAIN
def main():
    HOSTNAME = os.uname()[1]
    HOSTNAME = "vfxcache02"

    zfsbackup(HOSTNAME)


if __name__ == "__main__":
    main()
