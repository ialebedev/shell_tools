#!/bin/env python

import os
import sys
import subprocess

from dataclasses import dataclass, field

from colorama import Fore, Style
from datetime import datetime


@dataclass
class Snapshot:
    dataset: str
    name: str = field(
        default_factory=lambda: datetime.now().strftime("%Y.%m.%d_%H:%M:%S")
    )

    def full_name(self) -> str:
        return f"{self.dataset}@{self.name}"


@dataclass
class Dataset:
    name: str
    snapshots: list[Snapshot] = field(default_factory=list)

    def last_snapshot(self) -> Snapshot | None:
        return self.snapshots[-1] if self.snapshots else None

    def prev_snapshot(self) -> Snapshot | None:
        return self.snapshots[-2] if len(self.snapshots) >= 2 else None


@dataclass
class BackupConfig:
    host: str
    pool: str = "zdata"
    target: str = "localhost"
    exclude_keywords: list[str] = field(default_factory=list)
    special_excludes: list[str] = field(default_factory=list)


def message(message: str, status: bool = True):
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
        message(f"Found {pool} pool")
    else:
        message(f"No {pool} pool found", False)
        sys.exit(1)


def get_datasets(pool: str) -> list[Dataset]:
    output = subprocess.run(
        f"zfs list -r -H -t filesystem {pool} -o name",
        shell=True,
        capture_output=True,
        text=True,
        check=True,
    )

    return [Dataset(name=name) for name in output.stdout.splitlines()[1:]]


def filter_datasets(datasets: list[Dataset], config: BackupConfig) -> list[Dataset]:
    filtered = []
    for dataset in datasets:
        if any(keyword in dataset.name for keyword in config.exclude_keywords):
            continue

        if any(exclude == dataset.name for exclude in config.special_excludes):
            continue

        filtered.append(dataset)
    return filtered


def get_snapshots(dataset: Dataset) -> list[Snapshot]:
    output = subprocess.run(
        f"zfs list -H -t snapshot {dataset.name} -o name",
        shell=True,
        capture_output=True,
        text=True,
        check=True,
    )

    dataset.snapshots = [
        Snapshot(dataset=snap.split("@")[0], name=snap.split("@")[1])
        for snap in output.stdout.splitlines()
    ]

    return dataset.snapshots


def diff_snapshots(prev: Snapshot, last: Snapshot) -> bool:
    try:
        diff = subprocess.run(
            f"zfs diff {prev.full_name()} {last.full_name()}",
            shell=True,
            capture_output=True,
            text=True,
            check=True,
        )
        return bool(diff.stdout)
    except subprocess.CalledProcessError as error:
        message(
            f"Failed to compare snapshots {prev.full_name()} and {last.full_name()}",
            False,
        )
        print(f"Error: {error.stderr}")
        sys.exit(1)


def delete_snapshot(snapshot: Snapshot):
    try:
        subprocess.run(
            f"zfs destroy {snapshot.full_name()}",
            shell=True,
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as error:
        message(f"Failed to delete {snapshot}", False)
        print(f"Error: {error.stderr}")


def clean_snapshots(dataset: Dataset):
    while len(dataset.snapshots) > 3:
        delete_snapshot(dataset.snapshots[0])
        message(f"Deleted old snapshot {dataset.snapshots[0].full_name()}")
        dataset.snapshots.pop(0)


def create_snapshot(dataset: Dataset) -> Snapshot:
    snapshot = Snapshot(dataset=dataset.name)
    try:
        subprocess.run(
            f"zfs snapshot {snapshot.full_name()}",
            shell=True,
            capture_output=True,
            text=True,
            check=True,
        )
        dataset.snapshots.append(snapshot)
        return snapshot
    except subprocess.CalledProcessError as error:
        message(f"Failed to create snapshot for {dataset.name}", False)
        print(f"Error: {error.stderr}")
        sys.exit(1)


def send_snapshot(dataset: Dataset, target: str):
    last = dataset.last_snapshot()
    if not last:
        message(f"No snapshots found in {dataset.name}", False)
        return

    if len(dataset.snapshots) == 1:
        message(f"Sent initial snapshot {last.full_name()}")
        return

    prev = dataset.prev_snapshot()
    if diff_snapshots(prev, last):
        message(f"Sent incremental snapshot {last.full_name()}")
    else:
        message(f"No changes in {dataset.name}")
        delete_snapshot(last)
        dataset.snapshots.pop(-1)


def get_backup_config(host: str) -> BackupConfig:
    config = BackupConfig(host=host)

    if host in ("vfserver01", "vfxserver02"):
        config.exclude_keywords = ["Caches", "Trash"]
        config.special_excludes = ["zdata/Projects"]
        config.target = "192.168.20.14" if host == "vfxserver02" else "192.168.20.10"

    elif host in ("vfxcache01", "vfxcache02"):
        config.exclude_keywords = ["Programs", "Projects", "Tools", "Trash"]
        config.special_excludes = ["zdata/Caches"]
        config.target = "192.168.20.15" if host == "vfxcache02" else "192.168.20.11"

    elif host == "vfxstorage01":
        config.target = "192.168.20.13"

    elif host == "vfxstorage02":
        config.target = "192.168.20.12"

    return config


def zfsbackup(host: str):
    message(f"Starting backup scenario for {host}")

    config = get_backup_config(host)
    check_pool(config.pool)

    datasets = get_datasets(config.pool)
    datasets = filter_datasets(datasets, config)

    if datasets:
        message(f"Found datasets in {config.pool}")
    else:
        message(f"No datasets found in {config.pool}", False)
        sys.exit(1)

    for dataset in datasets:
        create_snapshot(dataset)
        get_snapshots(dataset)
        send_snapshot(dataset, config.target)
        clean_snapshots(dataset)


# MAIN
def main():
    HOSTNAME = os.uname()[1]
    HOSTNAME = "vfxserver02"

    zfsbackup(HOSTNAME)


if __name__ == "__main__":
    main()
