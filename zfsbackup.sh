#!/bin/bash
#
# zfsbackup — снапшотит датасеты пула zdata и отправляет их на удалённый
# сервер через zfs send/receive, если есть изменения. Если изменений нет —
# снапшот просто удаляется.
#
# Использование:
#   ./zfsbackup <remote_ip> [dataset1 dataset2 ...]
#
# Если список датасетов не передан аргументами — берётся из массива
# DATASETS ниже.
#
# Требования:
#   - passwordless SSH (по ключу) с этого сервера на remote_ip под REMOTE_USER
#   - на удалённом сервере должен существовать пул REMOTE_POOL
#   - права на zfs snapshot/send/destroy локально и zfs receive удалённо
#     (либо root, либо настроено через `zfs allow`)

set -evo pipefail

POOL="zdata"
REMOTE_POOL="zdata"
REMOTE_USER="master"
SNAP_PREFIX="autobackup"
LOCKFILE="/var/run/zfsbackup.lock"
LOGFILE="/var/log/zfsbackup.log"

# Список датасетов по умолчанию (без имени пула, только "хвост").               
# Например для zdata/Projects/POSTKINO указываем просто "POSTKINO".
DATASETS=(
    "Programs"
    "9thPlanet"
    "Chaika"
    "POSTKINO"
    "TECZON"
    "VVP"
    "Tools"
)

usage() {
    echo "Использование: $0 <remote_ip> [dataset1 dataset2 ...]" >&2
    echo "Если датасеты не переданы, то используем список DATASETS" >&2
    exit 1
}
