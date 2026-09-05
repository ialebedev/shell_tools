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

# Включаем строгий режим обработки ошибок и логирования в скрипте
set -eo pipefail
# -e (errexit) моментально останавливает скрипт при любой ошибке
# -o в связке с pipefail означает строгий контроль ошибок внутри конвейеров
# -v (verbose) подробный вывод

POOL="zdata"
REMOTE_POOL="zdata"
REMOTE_USER="master"
SNAP_PREFIX=""
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5"
LOCKFILE="/tmp/zfsbackup.lock"
LOGFILE="/tmp/zfsbackup.log"

# Список датасетов по умолчанию (без имени пула, только "хвост").               
# Например для zdata/Projects/POSTKINO указываем просто "POSTKINO".
DATASETS=(
    "Programs"
    "Caches/9thPlanet"
    "Caches/Chaika"
    "Caches/POSTKINO"
    "Caches/TECZON"
    "Caches/VVP"
    "Projects/9thPlanet"
    "Projects/Chaika"
    "Projects/POSTKINO"
    "Projects/TECZON"
    "Projects/VVP"
    "Tools"
)

usage() {
    echo "Использование: $0 <remote_ip> [dataset1 dataset2 ...]" >&2
    echo "Если датасеты не переданы, то используем список DATASETS" >&2
    exit 1
}

# Если число переданых параметров < 1, то вызываем usage
[[ $# -lt 1 ]] && usage

REMOTE_IP=$1

# Сдвигаем аргументы влева (удаляем первый элемент)
shift

# Если парамметры еще есть, то считаем, что передали датасеты
if [[ $# -gt 0 ]]; then
    DATASETS=("$@")
fi

# Функция логирования
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOGFILE"
}

# Защита от повторного запуска
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    log "Скрипт уже выполняется (lock: $LOCKFILE). Выхожу"
    exit 1
fi

# Функция проверки SSH и наличия ZFS
check_ssh() {
    ssh $SSH_OPTS "${REMOTE_USER}@${REMOTE_IP}" "zfs list >/dev/null 2>&1"
}

log "===== Запуск бэкапа на ${REMOTE_IP} ====="

if ! check_ssh; then
    log "ОШИБКА: нет доступа по SSH к ${REMOTE_IP}, либо ZFS там недоступен"
    exit 1
fi

# Функция работы с датасетом
process_dataset() {
    local ds="$1"
    local full_ds="${POOL}/${ds}"
    local remote_ds="${REMOTE_POOL}/${ds}"
    local ts new_snap prev_snap written

    log "== Обработка ${full_ds} =="

    if ! zfs list "$full_ds" >/dev/null 2>&1; then
        log "ОШИБКА: датасет $full_ds не существует. Пропускаем"
        return 1
    fi

    # Ищем крайний снапшот с нашим префиксом
    prev_snap=$(zfs list -t snapshot -o name -s creation -H -r "$full_ds" 2>/dev/null \
                | grep -E "^${full_ds}@" | tail -n1 || true)


    # Формируем название нового снапшота
    ts=$(date +%Y.%m.%d_%H:%M:%S)
    new_snap="${full_ds}@${SNAP_PREFIX}${ts}"

    # Создаем снапшот
    if ! zfs snapshot "$new_snap"; then
        log "ОШИБКА: не удалось создать снапшот $new_snap"
        return 1
    fi

    # Проверяем, были ли изменения с прошлого снапшота
    # или с момента создания датасета, если снапшотов еще не было
    written=$(zfs get -Hpo value written "$new_snap")

    if [[ "$written" -eq 0 && -n "$prev_snap" ]]; then
        log "Изменений нет в ${full_ds}. Удаляем $new_snap"
        zfs destroy "$new_snap"
        return 0
    fi

    log "Обнаружены изменения в ${full_ds}, отправляем на ${REMOTE_IP}"

    if [[ -z "$prev_snap" ]]; then
        # Первая отправка датасета - полный поток
        if zfs send -Lv "$new_snap" \
             | ssh $SSH_OPTS "${REMOTE_USER}@${REMOTE_IP}" "zfs receive -d ${remote_ds}"; then
            log "OK: полная отправка ${new_snap} завершена успешно"
        else
            log "ОШИБКА при полной отправке ${new_snap}. Откатываем локальный снапшот"
            zfs destroy "$new_snap"
            return 1
        fi
    else
        # Инкрементальная отправка снапшота
        if zfs send -Lvi "$prev_snap" "$new_snap" \
             | ssh $SSH_OPTS "${REMOTE_USER}@${REMOTE_IP}" "zfs receive -d ${remote_ds}"; then
            log "OK: инкрементальная отправка ${prev_snap} -> ${new_snap} завершена успешно"    
        else
            log "ОШИБКА при отправке ${new_snap}, удалеяем его. Оставляем предыдущий снапшот"
            zfs destroy "$new_snap"
            return 1
        fi
    fi

    return 0
}

# Запускаем обработку датасетов
FAILED=0
for ds in "${DATASETS[@]}"; do
    if ! process_dataset "$ds"; then
        FAILED=1
    fi
done

log "===== Бэкап завершен (код возврата: ${FAILED}) ====="

exit $FAILED
