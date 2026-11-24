#!/usr/bin/env bash
set -euo pipefail
echo

# Включаем шрифт с поддрержкой кириллицы
[[ -f /usr/share/kbd/consolefonts/ter-v20b.psf.gz ]] && setfont ter-v20b

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Функции вывода сообщений
info() { echo -e "${GREEN}[INFO]${NC} $*"; sleep 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; sleep 1; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Проверка прав и окружения ---
[[ $EUID -eq 0 ]] || error "Скрипт нужно запускать от root"
[[ -d /sys/firmware/efi ]] || error "Система должна быть загружена в режиме UEFI"

# Все нужные команды проверяем до вопросов, чтобы не упасть на середине
for cmd in jq openssl parted wipefs zpool zfs zgenhostid pacstrap genfstab arch-chroot; do
    command -v "$cmd" >/dev/null || error "Не найдена команда: $cmd"
done

# --- Сбор данных: выбор диска по номеру ---
info "Поиск доступных дисков..."

# Возвращает полный путь к стабильному симлинку диска (без -partN)
find_disk_link() {
    local real dir link name fallback
    real=$(readlink -f -- "$1")

    for dir in by-id by-path; do
        fallback=""
        for link in /dev/disk/$dir/*; do
            [[ -L $link && $link != *-part* ]] || continue
            [[ $(readlink -f -- "$link") == "$real" ]] || continue

            name=${link##*/}
            if [[ $name =~ ^(wwn-|nvme-eui\.|scsi-3) ]]; then
                fallback=${fallback:-$link}
            else
                printf '%s\n' "$link"
                return 0
            fi
        done
        [[ -n $fallback ]] && { printf '%s\n' "$fallback"; return 0; }
    done
    return 1
}

# --- Вспомогательные функции для сбора параметров ---

# ask_yn VAR "Вопрос"  ->  VAR = y | n  (по умолчанию n)
ask_yn() {
    local __var=$1 __ans
    read -rp "$2 (y/N): " __ans
    if [[ "${__ans:-n}" =~ ^[Yy]$ ]]; then
        printf -v "$__var" '%s' "y"
    else
        printf -v "$__var" '%s' "n"
    fi
}

# ask_choice VAR "Вопрос" "по_умолчанию" "допустимые значения через пробел"
ask_choice() {
    local __var=$1 __ans
    while true; do
        read -rp "$2 [$3]: " __ans
        __ans="${__ans:-$3}"
        if [[ " $4 " == *" $__ans "* ]]; then
            printf -v "$__var" '%s' "$__ans"
            return 0
        fi
        warn "Допустимые значения: $4"
    done
}

# ask_username VAR "Вопрос" [занятые имена...]
ask_username() {
    local __var=$1 __q=$2 __ans __n
    shift 2
    while true; do
        read -rp "$__q: " __ans
        if ! [[ "$__ans" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
            warn "Имя: строчные латинские буквы, цифры, _ и -; начинается с буквы или _; до 32 символов."
            continue
        fi
        for __n in "$@"; do
            if [[ "$__ans" == "$__n" ]]; then
                warn "Имя «$__n» занято, выберите другое."
                continue 2
            fi
        done
        printf -v "$__var" '%s' "$__ans"
        return 0
    done
}

# ask_password_hash VAR "имя пользователя"  ->  VAR = sha512-crypt хеш пароля
ask_password_hash() {
    local __var=$1 __p1 __p2 __h
    while true; do
        read -rsp "Введите пароль для $2: " __p1; echo
        read -rsp "Подтвердите пароль: " __p2; echo
        if [[ -z "$__p1" ]]; then
            warn "Пароль не может быть пустым."
            continue
        fi
        [[ "$__p1" == "$__p2" ]] && break
        warn "Пароли не совпадают. Пожалуйста, попробуйте еще раз."
    done
    __h=$(openssl passwd -6 -stdin <<< "$__p1") || error "Не удалось получить хеш пароля"
    printf -v "$__var" '%s' "$__h"
}

# Собираем список дисков через JSON (надёжно при пробелах в MODEL)
mapfile -t DISKS < <(lsblk -d -n -J -o NAME,SIZE,MODEL,TYPE | jq -r '.blockdevices[] | select(.type=="disk") | "\(.name)|\(.size)|\(.model)"')

if [[ ${#DISKS[@]} -eq 0 ]]; then
    error "Не найдено ни одного диска"
fi

# Определяем индекс nvme0n1 (для значения по умолчанию)
DEFAULT_IDX=""
echo -e "Доступные диски:"
for i in "${!DISKS[@]}"; do
    IFS='|' read -r name size model <<< "${DISKS[$i]}"
    idx=$((i+1))
    printf "  %2d) /dev/%-10s %8s  %s\n" "$idx" "$name" "$size" "$model"
    if [[ "$name" == "nvme0n1" ]]; then
        DEFAULT_IDX="$idx"
    fi
done

# Если nvme0n1 не найден — по умолчанию первый диск
if [[ -z "$DEFAULT_IDX" ]]; then
    DEFAULT_IDX="1"
    warn "nvme0n1 не найден, по умолчанию выбран первый диск\n"
fi

read -rp "Введите номер диска [${DEFAULT_IDX}]: " DISK_CHOICE
DISK_CHOICE="${DISK_CHOICE:-$DEFAULT_IDX}"

# Проверка: число в допустимом диапазоне
if ! [[ "$DISK_CHOICE" =~ ^[0-9]+$ ]] || (( DISK_CHOICE < 1 || DISK_CHOICE > ${#DISKS[@]} )); then
    error "Некорректный номер: $DISK_CHOICE"
fi

IFS='|' read -r DISK_NAME _ _ <<< "${DISKS[$((DISK_CHOICE-1))]}"
DISK="/dev/${DISK_NAME}"
[[ -b "$DISK" ]] || error "Диск $DISK не найден"

info "Выбран диск: $DISK"

# Стабильный путь к диску (важно для ZFS)
DISK_LINK=$(find_disk_link "$DISK") || error "Не найден стабильный путь для $DISK"
info "Используем: $DISK_LINK"

# =====================================================================
# --- Сбор параметров установки: ВСЕ вопросы здесь, дальше ввода не будет ---
# =====================================================================
info "Параметры установки"

# Имя хоста
while true; do
    read -rp "Введите имя хоста (hostname): " HOSTNAME
    [[ "$HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] && break
    warn "Допустимы латинские буквы, цифры и дефис (не первым и не последним), до 63 символов."
done

# --- Репозиторий и зеркала ---
ask_yn STUDIO_REPO_CHOICE "Подключить студийный репозиторий?"
REFLECTOR_CHOICE="n"
if [[ "$STUDIO_REPO_CHOICE" == "n" ]]; then
    ask_yn REFLECTOR_CHOICE "Оптимизировать зеркала через reflector?"
fi

# --- Микрокод процессора ---
# Определяем производителя CPU
CPU_VENDOR=$(awk -F': ' '/^vendor_id/ {print $2; exit}' /proc/cpuinfo)
case "$CPU_VENDOR" in
    GenuineIntel) DEFAULT_CHOICE="2" ;;
    AuthenticAMD) DEFAULT_CHOICE="1" ;;
    *)            DEFAULT_CHOICE="1"
                  warn "Не удалось определить производителя CPU ($CPU_VENDOR), по умолчанию AMD" ;;
esac

echo "Выберите микрокод процессора:"
echo "  1) amd-ucode"
echo "  2) intel-ucode"
ask_choice UCODE_CHOICE "Введите номер" "$DEFAULT_CHOICE" "1 2"
case "$UCODE_CHOICE" in
    1) UCODE="amd-ucode" ;;
    2) UCODE="intel-ucode" ;;
esac

# --- Пользователи ---
info "Учетные записи пользователей"
ask_username USERNAME "Введите имя пользователя (администратора)" root render
ask_password_hash USERHASH "$USERNAME"

ask_yn RENDER_CHOICE "Создать пользователя render (UID 900, основная группа администратора)?"

EXTRA_USERNAME=""
EXTRA_USERHASH=""
ask_yn EXTRA_USER_CHOICE "Создать еще пользователя?"
if [[ "$EXTRA_USER_CHOICE" == "y" ]]; then
    ask_username EXTRA_USERNAME "Введите имя пользователя" root render "$USERNAME"
    ask_password_hash EXTRA_USERHASH "$EXTRA_USERNAME"
fi

# --- Система и софт ---
info "Система и софт"
ask_yn SKEL_CHOICE "Настроить /etc/skel?"

echo "Сетевой менеджер:"
echo "  1) systemd-networkd"
echo "  2) NetworkManager"
ask_choice NET_CHOICE "Выберите сетевой менеджер" "1" "1 2"

ask_yn AFRENDER_CHOICE "Установить софт для afrender?"
ask_yn STATION_CHOICE "Установить софт для vfxstation?"

echo "Драйвер видеокарты:"
echo "  1) Nvidia"
echo "  2) AMD"
echo "  3) Intel"
echo "  4) Nouveau"
echo "  0) Не устанавливать видеодрайвер"
ask_choice GPU_CHOICE "Выберите драйвер видеокарты" "1" "0 1 2 3 4"

# --- Настройка системы ---
info "Настройка системы"
ask_yn NFS_CHOICE "Создать точки монтирования NFS?"
ask_yn LINK_CHOICE "Создать символические ссылки?"
ask_yn SLEEP_CHOICE "Отключить режимы сна и гибернации?"
ask_yn TRIM_CHOICE "Включить TRIM и настроить датчики?"
ask_yn USB_RULES_CHOICE "Запретить пользователям монтировать USB-накопители?"
ask_yn BASEDIR_CHOICE "Создать базовые директории?"

APPS_ICONS_CHOICE="n"
if [[ "$STATION_CHOICE" == "y" ]]; then
    ask_yn APPS_ICONS_CHOICE "Создать иконки для программ?"
fi

# --- Сводка и подтверждение ---
info "Сводка параметров"
GPU_NAMES=("нет" "Nvidia" "AMD" "Intel" "Nouveau")
echo "  Диск: $DISK ($DISK_LINK)"
echo "  Разметка (GPT): EFI 1G, SWAP 64G, ZFS - оставшееся место"
echo "  Имя хоста: $HOSTNAME"
echo "  Администратор: $USERNAME"
echo "  Микрокод: $UCODE"
echo "  Видеодрайвер: ${GPU_NAMES[$GPU_CHOICE]}"
[[ "$NET_CHOICE" == "1" ]] && echo "  Сеть: systemd-networkd" || echo "  Сеть: NetworkManager"

SUMMARY_FLAGS=(
    "Студийный репозиторий|STUDIO_REPO_CHOICE"
    "Зеркала через reflector|REFLECTOR_CHOICE"
    "Пользователь render|RENDER_CHOICE"
    "Дополнительный пользователь|EXTRA_USER_CHOICE"
    "/etc/skel|SKEL_CHOICE"
    "Софт afrender|AFRENDER_CHOICE"
    "Софт vfxstation|STATION_CHOICE"
    "NFS-точки монтирования|NFS_CHOICE"
    "Символические ссылки|LINK_CHOICE"
    "Отключить сон и гибернацию|SLEEP_CHOICE"
    "TRIM и датчики|TRIM_CHOICE"
    "Запрет монтирования USB|USB_RULES_CHOICE"
    "Базовые директории|BASEDIR_CHOICE"
    "Иконки программ|APPS_ICONS_CHOICE"
)
for item in "${SUMMARY_FLAGS[@]}"; do
    label=${item%%|*}
    var=${item##*|}
    [[ "${!var}" == "y" ]] && val="да" || val="нет"
    [[ "$var" == "EXTRA_USER_CHOICE" && "$val" == "да" ]] && val="да ($EXTRA_USERNAME)"
    echo "  $label: $val"
done

# Проверка согласованности выбранных опций (только предупреждения)
if [[ "$AFRENDER_CHOICE" == "y" && "$RENDER_CHOICE" != "y" ]]; then
    warn "afrender.service запускается от пользователя render, а он не будет создан"
fi
if [[ "$AFRENDER_CHOICE" == "y" && "$LINK_CHOICE" != "y" ]]; then
    warn "Для afrender нужна ссылка /opt/cgru, она создаётся только вместе с символическими ссылками"
fi

warn "Все данные на $DISK будут уничтожены."
ask_yn CONFIRM "Всё верно, начать установку?"
[[ "$CONFIRM" == "y" ]] || error "Отменено пользователем"

# --- Разметка диска ---
info "Разметка диска $DISK"
wipefs -a "$DISK"
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart "EFI" fat32 0% 1025MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart "SWAP" linux-swap 1025MiB 66561MiB
parted -s "$DISK" mkpart "ZFS" ext4 66561MiB 100%

# Ждём, пока udev создаст симлинки разделов
partprobe "$DISK"
udevadm settle

PART_EFI="${DISK_LINK}-part1"
PART_SWAP="${DISK_LINK}-part2"
PART_ZFS="${DISK_LINK}-part3"

for p in "$PART_EFI" "$PART_SWAP" "$PART_ZFS"; do
    [[ -e $p ]] || error "Раздел $p не появился"
done

# Форматирование EFI и swap
info "Форматирование EFI и SWAP"
mkfs.vfat -F 32 "$PART_EFI"
mkswap "$PART_SWAP"
swapon "$PART_SWAP"

# Фиксируем hostid ДО создания пула, позже перенесем ее в новую систему
zgenhostid -f

# --- Создание ZFS пула ---
info "Создание ZFS пула zroot"
zpool create -f \
    -o ashift=12 \
    -o autotrim=on \
    -o listsnapshots=on \
    -o cachefile=none \
    -O acltype=posixacl \
    -O relatime=on \
    -O xattr=sa \
    -O dnodesize=auto \
    -O normalization=formD \
    -O compression=on \
    -O utf8only=on \
    -O canmount=off \
    -O devices=off \
    -O mountpoint=none \
    -R /mnt \
    zroot "$PART_ZFS"

# --- Создание датасетов ---
info "Создание датасетов"
zfs create -o mountpoint=none -o canmount=off zroot/ROOT
echo -e "zroot/ROOT" 
zfs create -o mountpoint=none -o canmount=off zroot/DATA
echo -e "zroot/DATA" 
zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/arch
echo -e "zroot/ROOT/arch" 
zfs create -o mountpoint=/home -o canmount=noauto zroot/DATA/home
echo -e "zroot/DATA/home"
# zfs create -o mountpoint=/root -o canmount=noauto zroot/DATA/root
# echo -e "zroot/DATA/root" 
zpool set bootfs=zroot/ROOT/arch zroot

# Монтирование
info "Монтирование датасетов"
zfs mount zroot/ROOT/arch
echo -e "zroot/ROOT/arch" 
zfs mount zroot/DATA/home
echo -e "zroot/DATA/home"
# zfs mount zroot/DATA/root
# echo -e "zroot/DATA/root" 
mkdir -p /mnt/boot/efi
mount "$PART_EFI" /mnt/boot/efi
echo -e "/mnt/boot/efi" 

# --- Подключение студийного репозитория / оптимизация зеркал ---
if [[ "$STUDIO_REPO_CHOICE" =~ ^[Yy]$ ]]; then
    # Перезаписываем mirrorlist
    echo 'Server = http://192.168.20.15:9129/repo/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist

    # Обновляем базы данных с учетом нового репозитория
    pacman -Syy --noconfirm
else
    # Оптимизация зеркал (reflector)
    if [[ "$REFLECTOR_CHOICE" =~ ^[Yy]$ ]]; then
        # Обновляем mirrorlist: 5 самых быстрых HTTPS-зеркал, обновлённых за последние 12 часов
        reflector -l 10 -c "RU,DE,NL,SE" -p https -a 12 --sort rate --save /etc/pacman.d/mirrorlist

        # Принудительно обновляем базы данных pacman под новый mirrorlist
        pacman -Syy --noconfirm
    fi
fi

# --- Установка базовой системы ---
info "Установка базовой системы"
pacstrap -K /mnt base base-devel linux-lts linux-lts-headers linux-firmware \
    "$UCODE" dkms helix bash-completion openssh terminus-font python git \
    reflector rsync efibootmgr

# Переносим hostid из live в установленную систему
cp -f /etc/hostid /mnt/etc/hostid

# --- Генерация fstab ---
info "Генерация /etc/fstab"
genfstab -U /mnt > /mnt/etc/fstab
# Правка fstab (удаляем ZFS-записи, оставляем EFI и swap)
# Исправляем маску EFI (если genfstab поставил 0022)
sed -i -e '/zroot/d' -e '/^$/d' /mnt/etc/fstab || true
sed -i -E '/vfat/s/(fmask|dmask)=0022/\1=0077/g' /mnt/etc/fstab || true

# --- Копирование обновленного mirrorlist в установленную систему ---
if [[ "${REFLECTOR_CHOICE:-n}" =~ ^[Yy]$ ]]; then
    info "Копируем обновлённый mirrorlist в установленную систему"
    cp -f /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
fi

# --- Копирование скрипта в chroot для второго этапа ---
cat > /mnt/root/setup-chroot.sh <<'CHROOT_EOF'
#!/usr/bin/env bash
set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Функции вывода сообщений
info() { echo -e "${GREEN}[INFO]${NC} $*"; sleep 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; sleep 1; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Параметры установки, собранные основным скриптом (все ответы на вопросы)
source /root/install.conf

# 1. Ссылка на helix
info "Ссылка на helix (hx -> helix)"
ln -sf /usr/bin/helix /usr/local/bin/hx

# 2. Часовой пояс
info "Настраиваем часовой пояс на Europe/Moscow"
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

# 3. NTP
IP=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}') || true
if [[ -n "$IP" ]]; then NTP_SERVER="${IP%.*}.1"; else NTP_SERVER="192.168.20.1"; fi
info "Настраиваем NTP сервер ($NTP_SERVER)"
sed -i "s/^#\?NTP=.*/NTP=${NTP_SERVER}/" /etc/systemd/timesyncd.conf
systemctl enable systemd-timesyncd.service

# 4. Локаль
info "Настраиваем локаль"
sed -i 's/#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf

# 5. Консоль
info "Настраиваем консоль"
cat > /etc/vconsole.conf <<'EOF'
KEYMAP=ru
XKBLAYOUT=ru,us
XKBMODEL=pc105
XKBOPTIONS=grp:alt_shift_toggle
FONT=ter-v32b
EOF

# 6. Hostname и Hosts
info "Прописываем hostname и hosts"
echo "$HOSTNAME" >> /etc/hostname
echo "127.0.1.1        ${HOSTNAME}.local       ${HOSTNAME}" >> /etc/hosts
echo "" >> /etc/hosts

echo "192.168.20.10    vfxcache01.local        vfxcache01" >> /etc/hosts
echo "192.168.20.11    vfxserver01.local       vfxserver01" >> /etc/hosts
echo "192.168.20.12    vfxstorage01.local      vfxstorage01" >> /etc/hosts
echo "192.168.20.13    vfxstorage02.local      vfxstorage02" >> /etc/hosts
echo "192.168.20.14    vfxcache02.local        vfxcache02" >> /etc/hosts
echo "192.168.20.15    vfxserver02.local       vfxserver02" >> /etc/hosts

# 7. Настройка /etc/skel
if [[ "$SKEL_CHOICE" =~ ^[Yy]$ ]]; then
    # .bashrc
    ln -sfn /mnt/vfxserver02/Tools/_user_preferences/bashrc /etc/skel/.bashrc

    # Houdini
    ln -sfn /mnt/vfxserver02/Tools/_user_preferences/sesi_licenses.pref /etc/skel/.sesi_licenses.pref

    # Nuke
    mkdir -p /etc/skel/.nuke
    ln -sfn /mnt/vfxserver02/Tools/Nuke/init.py /etc/skel/.nuke/init.py
    ln -sfn /mnt/vfxserver02/Tools/Nuke/menu.py /etc/skel/.nuke/menu.py

    # mpv
    mkdir -p /etc/skel/.config/mpv
    echo loop > /etc/skel/.config/mpv/mpv.conf
fi

# 8. Пользователи
info "Настройка учетных записей пользователей"
useradd -mG wheel,input,audio,video,storage,power,lp -s /bin/bash "$USERNAME"
echo "${USERNAME}:${USERHASH}" | chpasswd -e
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Пароль root
echo "root:${USERHASH}" | chpasswd -e

# Получаем GID основного пользователя (обычно 1000)
MAIN_GID=$(id -g "$USERNAME")

# --- Служебный пользователь render ---
if [[ "$RENDER_CHOICE" =~ ^[Yy]$ ]]; then
    useradd -u 900 -g "$MAIN_GID" -M -s /usr/bin/nologin render
fi

# --- Дополнительный обычный пользователь ---
if [[ "$EXTRA_USER_CHOICE" =~ ^[Yy]$ ]]; then
    useradd -m -g "$MAIN_GID" -G power,video,storage,lp,input,audio -s /bin/bash "$EXTRA_USERNAME"
    echo "${EXTRA_USERNAME}:${EXTRA_USERHASH}" | chpasswd -e
fi

# 10. Подключение студийного репозитория ---
if [[ "$STUDIO_REPO_CHOICE" =~ ^[Yy]$ ]]; then
    # Перезаписываем mirrorlist
    echo 'Server = http://192.168.20.15:9129/repo/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist
    
    # Обновляем базы данных с учетом нового репозитория
    pacman -Syy --noconfirm
fi

# 12. Репозиторий archzfs
info "Добавляем репозиторий archzfs"

ARCHZFS_KEY="3A9917BF0DED5C13F69AC68FABEC0A1208037BE9"
pacman-key --recv-keys "$ARCHZFS_KEY"
pacman-key --finger "$ARCHZFS_KEY"
pacman-key --lsign-key "$ARCHZFS_KEY"

cat >> /etc/pacman.conf <<'EOF'

[archzfs]
Server = https://github.com/archzfs/archzfs/releases/download/experimental
EOF

# 13. Установка приложений
# --- Базовые приложения ---
info "Установка базовых приложений"
PKGS=(zfs-dkms zfs-utils nfs-utils exfat-utils ntfs-3g unrar zip \
      unzip p7zip duf btop tmux eza bat yazi zoxide fzf ethtool \
      numactl ncdu lm_sensors stow) 

# --- Сетевой менеджер ---
if [[ -z "$NET_CHOICE" || "$NET_CHOICE" == "1" ]]; then
    cat > /etc/systemd/network/20-wired.network <<'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
EOF
else
    PKGS+=(networkmanager)
fi

# --- Afanasy render (afrender) ---
if [[ "$AFRENDER_CHOICE" =~ ^[Yy]$ ]]; then
    PKGS+=(glu alsa-lib nss freetype2 fontconfig libglvnd libxv \
    libxmu libxi libxtst libxcomposite libxcursor libxrender \
    libxkbcommon)
fi

# --- vfxstation ---
if [[ "$STATION_CHOICE" =~ ^[Yy]$ ]]; then

    # Основные пакеты
    PKGS+=(plasma-desktop plasma-login-manager plasma-pa \
    plasma-systemmonitor kdeplasma-addons breeze breeze-gtk \
    kde-gtk-config konsole dolphin pipewire pipewire-pulse \
    pipewire-alsa transmission-qt sof-firmware spectacle \
    filelight filezilla firefox firefox-ublock-origin \
    ttf-liberation ark kscreen krename kate okular mpv mediainfo \
    telegram-desktop obsidian powerdevil xclip tesseract-data-rus)

    # Дополнительные пакеты
    PKGS+=(gpu-screen-recorder-ui doublecmd-qt6)

    # Ставим PyQT для запуска CGRU
    if [[ "$AFRENDER_CHOICE" =~ ^[Yy]$ ]]; then
        PKGS+=(python-pyqt5)
    fi

    # Ставим аплет NetworkManager для KDE Plasma
    if [[ -n "$NET_CHOICE" && "$NET_CHOICE" != "1" ]]; then
        PKGS+=(plasma-nm)
    fi
fi

# --- Драйвер видеокарты ---
case "${GPU_CHOICE:-1}" in
    1) PKGS+=(nvidia-open-dkms nvidia-utils opencl-nvidia) ;;
    2) PKGS+=(mesa vulkan-radeon) ;;
    3) PKGS+=(mesa vulkan-intel) ;;
    4) PKGS+=(mesa) ;;
    *) ;;
esac

pacman -Sy --needed --noconfirm "${PKGS[@]}"

# 14. Идентификатор системы для ZFS
[[ -f /etc/hostid ]] || error "Отсутствует /etc/hostid"

# 15. Сервисы
info "Включение systemd сервисов"

if [[ -z "$NET_CHOICE" || "$NET_CHOICE" == "1" ]]; then
    systemctl enable systemd-networkd.service
    systemctl enable systemd-resolved.service
else
    systemctl enable NetworkManager.service
fi

if [[ "$STATION_CHOICE" =~ ^[Yy]$ ]]; then
    systemctl enable plasmalogin.service
fi

systemctl enable sshd.service
systemctl enable zfs.target
systemctl enable zfs-import.target
systemctl enable zfs-import-scan.service
systemctl enable zfs-zed.service

# --- Создание сервиса afrender (если выбран софт для afrender) ---
if [[ "$AFRENDER_CHOICE" =~ ^[Yy]$ ]]; then
    info "Создаём сервис afrender.service"
    cat > /etc/systemd/system/afrender.service <<'EOF'
[Unit]
Description=Afanasy render daemon
Wants=network-online.target
After=network-online.target systemd-user-sessions.service rc-local.service
Before=getty.target
RequiresMountsFor=/mnt/vfxserver02

[Service]
Type=simple
User=render
#Group=render
WorkingDirectory=/opt/cgru
ExecStart=/opt/cgru/start/AFANASY/_afrender.sh -log_nodate
KillMode=process
TimeoutStopSec=3
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable afrender.service
fi

# 16. mkinitcpio
info "Прописываем модули загрузки (zfs) и хуки"

# Формируем список модулей в зависимости от выбранной видеокарты
case "${GPU_CHOICE:-1}" in
    1) GPU_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm" ;;
    2) GPU_MODULES="amdgpu" ;;
    3) GPU_MODULES="i915" ;;
    4) GPU_MODULES="nouveau" ;;
    *) GPU_MODULES="" ;;  # отказ от видеодрайвера — без KMS-модуля
esac

# Собираем MODULES=(zfs ...)
if [[ -n "$GPU_MODULES" ]]; then
    MODULES_LINE="MODULES=(zfs $GPU_MODULES)"
else
    MODULES_LINE="MODULES=(zfs)"
fi

# Заменяем строку MODULES и HOOKS
sed -i "s/^MODULES=.*/${MODULES_LINE}/" /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard consolefont block zfs filesystems)/' /etc/mkinitcpio.conf

mkinitcpio -P

# 17. Временно отключаем ввод пароля для pacman
# trap удалит файл при ЛЮБОМ выходе из скрипта, включая ошибки
SUDOERS_TMP=/etc/sudoers.d/yay-nopasswd
trap 'rm -f "$SUDOERS_TMP"' EXIT

echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pacman" > "$SUDOERS_TMP"
chmod 440 "$SUDOERS_TMP"
visudo -cf "$SUDOERS_TMP" >/dev/null || error "Некорректный sudoers-файл"

# 18. YAY
info "Установка YAY (пакет yay-bin)"
su - "$USERNAME" -c "git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin && \
cd /tmp/yay-bin && makepkg -si --noconfirm"

# 19. ZFSBootMenu
info "Установка ZFSBootMenu"
su - "$USERNAME" -c "yay -Sy --noconfirm zfsbootmenu perl-boolean"

# Пароль для pacman больше не нужен: дальше всё выполняется от root
rm -f "$SUDOERS_TMP"

zfs set org.zfsbootmenu:commandline="rw spl.spl_hostid=$(hostid) loglevel=3" zroot/ROOT
mkdir -p /boot/efi/EFI/zbm

CONFIG=/etc/zfsbootmenu/config.yaml
[[ -f "$CONFIG" ]] || error "Файл $CONFIG не найден"

# Global: ManageImages: false -> true
sed -i '/^Global:/,/^[A-Za-z]/ s/^\(\s*ManageImages:\s*\)false/\1true/' "$CONFIG"

# Components: Enabled: true -> false
sed -i '/^Components:/,/^[A-Za-z]/ s/^\(\s*Enabled:\s*\)true/\1false/' "$CONFIG"

# EFI: Enabled: false -> true (критично для генерации EFI-бинарника!)
sed -i '/^EFI:/,/^[A-Za-z]/ s/^\(\s*Enabled:\s*\)false/\1true/' "$CONFIG"

# Kernel: CommandLine: ro loglevel=0 -> rw loglevel=3
sed -i '/^Kernel:/,/^[A-Za-z]/ s|^\(\s*CommandLine:\s*\).*|\1rw loglevel=3|' "$CONFIG"

generate-zbm

# 20. EFI запись
info "Создание загрузочной записи в EFI"
efibootmgr --disk "${DISK}" --part 1 --create --label "ZFSBootMenu" \
    --loader '\EFI\zbm\vmlinuz-linux-lts.EFI' \
    --unicode "spl_hostid=$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid" \
    --verbose

# 21. Отключаем root
info "Отключаем учетную запись root"
passwd -l root

# 22. Создание сервисов монтирования серверов по NFS
if [[ "$NFS_CHOICE" =~ ^[Yy]$ ]]; then
    # Ассоциативный массив: "имя_хоста" = "IP_адрес"
    declare -A NFS_SERVERS=(
        ["vfxcache01"]="192.168.20.10"
        ["vfxserver01"]="192.168.20.11"
        ["vfxstorage01"]="192.168.20.12"
        ["vfxstorage02"]="192.168.20.13"
        ["vfxcache02"]="192.168.20.14"
        ["vfxserver02"]="192.168.20.15"
    )

    # Хосты, для которых сервисы будут включены
    AUTOMOUNT_HOSTS=("vfxserver02" "vfxcache02" "vfxstorage02")

    for HOST in "${!NFS_SERVERS[@]}"; do
        IP="${NFS_SERVERS[$HOST]}"
        MOUNT_POINT="/mnt/${HOST}"
        UNIT_NAME="$(systemd-escape -p --suffix=mount "${MOUNT_POINT}")"
        UNIT_FILE="/etc/systemd/system/${UNIT_NAME}"

        cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Mount ${HOST}
Wants=network-online.target
After=network-online.target
Before=remote-fs.target

[Mount]
What=${IP}:/mnt/${HOST}
Where=${MOUNT_POINT}
Type=nfs
Options=_netdev,hard,noatime,nodiratime,rw
TimeoutSec=10
LazyUnmount=true
ForceUnmount=true
DirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF

        # Включаем в автозагрузку только для выбранных хостов
        if [[ " ${AUTOMOUNT_HOSTS[*]} " =~ " ${HOST} " ]]; then
            systemctl enable "$UNIT_NAME"
        fi
    done
fi

# 23. Создание символических ссылок
if [[ "$LINK_CHOICE" =~ ^[Yy]$ ]]; then

    ln -sfn /mnt/vfxserver02/Programs /soft
    
    mkdir -p /etc/opt

    ln -sfn /soft/cgru/cgru /opt/cgru
    ln -sfn /soft/isl /opt/isl
    ln -sfn /soft/isl /etc/opt/isl
    ln -sfn /soft/OFX /usr/OFX
    ln -sfn /soft/houdini /opt/houdini
    ln -sfn /soft/foundry /usr/local/foundry

    ln -sfn /lib/libidn.so.12 /lib/libidn.so.11
    ln -sfn /lib/libtiff.so.6 /lib/libtiff.so.5
    ln -sfn /lib/libcrypt.so.2 /lib/libcrypt.so.1
    ln -sfn /lib/libpython3.14.so.1.0 /lib/libpython3.11.so.1.0
fi

# 24. Отключение режимов сна и гибернации
if [[ "$SLEEP_CHOICE" =~ ^[Yy]$ ]]; then
    systemctl mask suspend.target hibernate.target suspend-then-hibernate.target hybrid-sleep.target
fi

# 25. Настройка TRIM и датчиков (lm_sensors)
if [[ "$TRIM_CHOICE" =~ ^[Yy]$ ]]; then
    systemctl enable fstrim.timer
    sensors-detect --auto
fi

# 26. Блокировка монтирования USB для обычных пользователей
if [[ "$USB_RULES_CHOICE" =~ ^[Yy]$ ]]; then
    # Создаем директорию (в Arch она обычно уже есть, но на всякий случай)
    mkdir -p /etc/polkit-1/rules.d

    # Создаем файл правил
    cat > /etc/polkit-1/rules.d/10-usb-mount.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (
        action.id == "org.freedesktop.udisks2.filesystem-mount" ||
        action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
        action.id == "org.freedesktop.udisks2.filesystem-mount-other-seat"
    ) {
        // Только для root (или uid 0)
        return subject.isInGroup("wheel") ? polkit.Result.YES : polkit.Result.NO;
    }
});
EOF
fi

# 27. Создание базовых директорий
if [[ "$BASEDIR_CHOICE" =~ ^[Yy]$ ]]; then

    mkdir -p -m 0755 "/mnt/$HOSTNAME"
    mkdir -p -m 0777 "/mnt/$HOSTNAME/Temp" \
                     "/mnt/$HOSTNAME/Temp/Media" \
                     "/mnt/$HOSTNAME/Temp/MoTemp" \
                     "/mnt/$HOSTNAME/Temp/Blender" \
                     "/mnt/$HOSTNAME/Temp/Houdini" \
                     "/mnt/$HOSTNAME/Temp/Nuke" \
                     "/mnt/$HOSTNAME/Temp/Nuke/nuke-u900" \
                     "/mnt/$HOSTNAME/Temp/Nuke/nuke-u1000" \
                     "/mnt/$HOSTNAME/Temp/Nuke/nuke-u1001" \
                     "/mnt/$HOSTNAME/Temp/Nuke/nuke-u1002"
fi

# 28. Создание иконок программ
# Выполняется только если ранее был выбран софт для vfxstation
if [[ "$STATION_CHOICE" =~ ^[Yy]$ ]]; then
    if [[ "$APPS_ICONS_CHOICE" =~ ^[Yy]$ ]]; then
        # Базовый путь к исходным файлам
        APPS_SRC="/mnt/vfxserver02/Tools/_configuration_files/usr/share/applications"

        ln -sfn "${APPS_SRC}/Aspera.desktop" "/usr/share/applications/Aspera.desktop"
        ln -sfn "${APPS_SRC}/Cerebro.desktop" "/usr/share/applications/Cerebro.desktop"
        ln -sfn "${APPS_SRC}/CGRU.desktop" "/usr/share/applications/CGRU.desktop"
        ln -sfn "${APPS_SRC}/Cube.desktop" "/usr/share/applications/Cube.desktop"
        ln -sfn "${APPS_SRC}/DJV.desktop" "/usr/share/applications/DJV.desktop"
        ln -sfn "${APPS_SRC}/EffectsCraft.desktop" "/usr/share/applications/EffectCraft.desktop"
        ln -sfn "${APPS_SRC}/FilmCraft.desktop" "/usr/share/applications/FilmCraft.desktop"
        ln -sfn "${APPS_SRC}/Fusion.desktop" "/usr/share/applications/Fusion.desktop"
        ln -sfn "${APPS_SRC}/Krita.desktop" "/usr/share/applications/Krita.desktop"
        ln -sfn "${APPS_SRC}/LightCraft.desktop" "/usr/share/applications/LightCraft.desktop"
        ln -sfn "${APPS_SRC}/PhotoCraft.desktop" "/usr/share/applications/PhotoCraft.desktop"
        ln -sfn "${APPS_SRC}/Quixel.desktop" "/usr/share/applications/Quixel.desktop"
        ln -sfn "${APPS_SRC}/SolidCraft.desktop" "/usr/share/applications/SolidCraft.desktop"
    fi
fi

# 29. Включаем автомонтирование датасетов 
info "Включаем автомонтирование датасетов /home и /root"
zfs set canmount=on zroot/DATA/home
# zfs set canmount=on zroot/DATA/root

# 30. Кэш для пула
info "Генерируем кэш для пула zroot"
mkdir -p /etc/zfs/zfs-list.cache
zfs list -H -o name,mountpoint,canmount,atime,relatime,devices,exec,readonly,setuid,nbmand,\
encroot,keylocation,org.openzfs.systemd:requires,org.openzfs.systemd:requires-mounts-for,\
org.openzfs.systemd:before,org.openzfs.systemd:after,org.openzfs.systemd:wanted-by,\
org.openzfs.systemd:required-by,org.openzfs.systemd:nofail,org.openzfs.systemd:ignore\
 | sed -e 's|/mnt/|/|g' -e 's|/mnt$|/|g' > /etc/zfs/zfs-list.cache/zroot

CHROOT_EOF
chmod +x /mnt/root/setup-chroot.sh

# --- Передача параметров во второй этап ---
# Файл с ответами (включая хеши паролей) доступен только root и удаляется
# при финальной очистке /mnt/root
CONF_VARS=(
    HOSTNAME DISK
    USERNAME USERHASH EXTRA_USER_CHOICE EXTRA_USERNAME EXTRA_USERHASH RENDER_CHOICE
    STUDIO_REPO_CHOICE SKEL_CHOICE NET_CHOICE AFRENDER_CHOICE STATION_CHOICE GPU_CHOICE
    NFS_CHOICE LINK_CHOICE SLEEP_CHOICE TRIM_CHOICE USB_RULES_CHOICE BASEDIR_CHOICE
    APPS_ICONS_CHOICE
)
install -m 600 /dev/null /mnt/root/install.conf
declare -p "${CONF_VARS[@]}" > /mnt/root/install.conf

# --- Запуск второго этапа в chroot ---
info "Запуск конфигурации в arch-chroot"
arch-chroot /mnt /root/setup-chroot.sh

# --- Настройка resolv.conf для systemd-resolved (вне chroot) ---
if [[ -f /mnt/etc/systemd/network/20-wired.network ]]; then
    # Удаляем старый файл
    rm -f /mnt/etc/resolv.conf
    # Создаем ссылку с относительным путем (рекомендация ArchWiki)
    ln -sf ../run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
fi

# --- Настройка Pacman ---
info "Настройка Pacman"
sed -i 's/^#Color/Color/' /mnt/etc/pacman.conf

mkdir -p /mnt/etc/pacman.d/hooks

cat > /mnt/etc/pacman.d/hooks/00-system-snapshot.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Создание системного snapshot перед изменением пакетов...
When = PreTransaction
Exec = /usr/local/bin/system_snapshot
EOF

cat > /mnt/usr/local/bin/system_snapshot <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "ОШИБКА: Этот скрипт должен быть запущен с правами root (sudo)." >&2
   exit 1
fi

# Формирование временной метки
TIMESTAMP=$(date +'%Y.%m.%d_%H.%M.%S')

# Список целевых датасетов
DATASETS=(
    "zroot/ROOT/arch"
    "zroot/DATA/home"
    # "zroot/DATA/root"
)

for ds in "${DATASETS[@]}"; do
    # Проверяем существование датасета перед созданием снимка
    if zfs list "$ds" >/dev/null 2>&1; then
        echo "Создание снимка: ${ds}@${TIMESTAMP}"
        zfs snapshot "${ds}@${TIMESTAMP}"
    else
        echo "ПРЕДУПРЕЖДЕНИЕ: Датасет $ds не найден, пропуск." >&2
    fi
done
EOF
chmod 755 /mnt/usr/local/bin/system_snapshot

# --- Очищаем /mnt/root ---
rm -rf /mnt/root/{*,.*}

# --- Завершение ---
info "Установка завершена. Размонтирование дисков.\n"
umount -R /mnt
zpool export zroot
