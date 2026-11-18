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

# --- Сбор данных: выбор диска по номеру ---
info "Поиск доступных дисков...\n"

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

echo
read -rp "Введите номер диска [${DEFAULT_IDX}]: " DISK_CHOICE
DISK_CHOICE="${DISK_CHOICE:-$DEFAULT_IDX}"

# Проверка: число в допустимом диапазоне
if ! [[ "$DISK_CHOICE" =~ ^[0-9]+$ ]] || (( DISK_CHOICE < 1 || DISK_CHOICE > ${#DISKS[@]} )); then
    error "Некорректный номер: $DISK_CHOICE"
fi

IFS='|' read -r DISK_NAME _ _ <<< "${DISKS[$((DISK_CHOICE-1))]}"
DISK="/dev/${DISK_NAME}"
[[ -b "$DISK" ]] || error "Диск $DISK не найден"

echo
info "Выбран диск: $DISK\n"

# Получаем by-id для диска (важно для ZFS)
DISK_ID=$(ls -l /dev/disk/by-id/ | grep -E "/${DISK_NAME}$" | awk '{print $9}' | grep -v -- '-part' | head -n1)
[[ -n "$DISK_ID" ]] || error "Не удалось найти by-id для $DISK"
info "Используем идентификатор: $DISK_ID\n"

# Получаем имя хоста
read -rp "Введите имя хоста (hostname): " HOSTNAME

# --- Разметка диска ---
echo
info "Разметка диска $DISK\n"
echo -e "Cхема разметки (GPT):"
echo -e "EFI - 1G"
echo -e "SWAP - 64G"
echo -e "ZFS - оставшееся место\n"
printf "${YELLOW}[WARN]${NC} Все данные на %s будут уничтожены. " "$DISK"
read -rp "Продолжить (y/N): " CONFIRM
[[ "$CONFIRM" == "y" ]] || error "Отменено пользователем"

echo
wipefs -a "$DISK"
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart "EFI" fat32 0% 1025MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart "SWAP" linux-swap 1025MiB 66561MiB
parted -s "$DISK" mkpart "ZFS" ext4 66561MiB 100%

# Определяем имена разделов (поддержка nvme и sd*)
if [[ "$DISK_NAME" == nvme* ]]; then
    PART_EFI="${DISK}p1"
    PART_SWAP="${DISK}p2"
    PART_ZFS="${DISK}p3"
else
    PART_EFI="${DISK}1"
    PART_SWAP="${DISK}2"
    PART_ZFS="${DISK}3"
fi

# Форматирование EFI и swap
echo
info "Форматирование EFI и SWAP\n"
mkfs.vfat -F 32 "$PART_EFI"
mkswap "$PART_SWAP"
swapon "$PART_SWAP"

# --- Создание ZFS пула ---
echo
info "Создание ZFS пула zroot\n"
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
info "Создание датасетов\n"
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
echo
info "Монтирование датасетов\n"
zfs mount zroot/ROOT/arch
echo -e "zroot/ROOT/arch" 
zfs mount zroot/DATA/home
echo -e "zroot/DATA/home"
# zfs mount zroot/DATA/root
# echo -e "zroot/DATA/root" 
mkdir -p /mnt/boot/efi
mount "$PART_EFI" /mnt/boot/efi
echo -e "/mnt/boot/efi" 

# --- Подключение студийного репозитория ---
echo
read -rp "Подключить студийный репозиторий? (y/N): " STUDIO_REPO_CHOICE
STUDIO_REPO_CHOICE="${STUDIO_REPO_CHOICE:-n}"

if [[ "$STUDIO_REPO_CHOICE" =~ ^[Yy]$ ]]; then
    # Перезаписываем mirrorlist
    echo 'Server = http://192.168.20.15:9129/repo/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist

    # Обновляем базы данных с учетом нового репозитория
    pacman -Syy --noconfirm
else
    # Оптимизация зеркал (reflector) ---
    echo
    read -rp "Оптимизировать зеркала через reflector? (y/N): " REFLECTOR_CHOICE
    REFLECTOR_CHOICE="${REFLECTOR_CHOICE:-n}"

    if [[ "$REFLECTOR_CHOICE" =~ ^[Yy]$ ]]; then
        # Обновляем mirrorlist: 5 самых быстрых HTTPS-зеркал, обновлённых за последние 12 часов
        reflector -l 10 -c "RU,DE,NL,SE" -p https -a 12 --sort rate --save /etc/pacman.d/mirrorlist

        # Принудительно обновляем базы данных pacman под новый mirrorlist
        pacman -Syy --noconfirm
    fi
fi

# --- Установка базовой системы ---
echo
info "Установка базовой системы (pacstrap)\n"
# Определяем производителя CPU
CPU_VENDOR=$(awk -F': ' '/^vendor_id/ {print $2; exit}' /proc/cpuinfo)
case "$CPU_VENDOR" in
    GenuineIntel) DEFAULT_UCODE="intel-ucode"; DEFAULT_CHOICE="2" ;;
    AuthenticAMD) DEFAULT_UCODE="amd-ucode";   DEFAULT_CHOICE="1" ;;
    *)            DEFAULT_UCODE="amd-ucode";   DEFAULT_CHOICE="1"
                  warn "Не удалось определить производителя CPU ($CPU_VENDOR), по умолчанию AMD" ;;
esac

echo "Выберите микрокод процессора:"
echo "  1) amd-ucode"
echo "  2) intel-ucode"
echo
read -rp "Введите номер [${DEFAULT_CHOICE}]: " UCODE_CHOICE
UCODE_CHOICE="${UCODE_CHOICE:-$DEFAULT_CHOICE}"
echo

case "$UCODE_CHOICE" in
    1) UCODE="amd-ucode" ;;
    2) UCODE="intel-ucode" ;;
    *) error "Некорректный выбор: $UCODE_CHOICE" ;;
esac
sleep 1

pacstrap -K /mnt base base-devel linux-lts linux-lts-headers linux-firmware \
    "$UCODE" dkms helix bash-completion openssh terminus-font python git \
    reflector rsync efibootmgr

# --- Генерация fstab ---
echo
info "Генерация /etc/fstab\n"
genfstab -U /mnt > /mnt/etc/fstab
# Правка fstab (удаляем ZFS-записи, оставляем EFI и swap)
# Исправляем маску EFI (если genfstab поставил 0022)
sed -i -e '/zroot/d' -e '/^$/d' /mnt/etc/fstab || true
sed -i -E '/vfat/s/(fmask|dmask)=0022/\1=0077/g' /mnt/etc/fstab || true

# --- Копирование обновленного mirrorlist в установленную систему ---
if [[ "${REFLECTOR_CHOICE:-n}" =~ ^[Yy]$ ]]; then
    echo
    info "Копируем обновлённый mirrorlist в установленную систему\n"
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

# Данные, переданные извне
HOSTNAME="$1"
DISK="$2"

# 1. Ссылка на helix
info "Ссылка на helix (hx -> helix)\n"
ln -sf /usr/bin/helix /usr/local/bin/hx

# 2. Часовой пояс
info "Настраиваем часовой пояс на Europe/Moscow\n"
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc

# 3. NTP
info "Настраиваем NTP сервер (192.168.20.1)\n"
sed -i 's/^#\?NTP=.*/NTP=192.168.20.1/' /etc/systemd/timesyncd.conf
systemctl enable systemd-timesyncd.service

# 4. Локаль
echo
info "Настраиваем локаль\n"
sed -i 's/#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=ru_RU.UTF-8" > /etc/locale.conf

# 5. Консоль
echo
info "Настраиваем консоль\n"
cat > /etc/vconsole.conf <<'EOF'
KEYMAP=ru
XKBLAYOUT=ru,us
XKBMODEL=pc105
XKBOPTIONS=grp:alt_shift_toggle
FONT=ter-v32b
EOF

# 6. Прописываем hostname и hosts
info "Прописываем hostname и hosts\n"
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
read -rp "Настроить /etc/skel? (y/N): " SKEL_CHOICE
SKEL_CHOICE="${SKEL_CHOICE:-n}"

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
echo
info "Настройка учетных записей пользователей\n"
read -rp "Введите имя пользователя (администратора): " USERNAME

while true; do
    echo
    read -rsp "Введите пароль для $USERNAME: " USERPASS; echo
    read -rsp "Подтвердите пароль: " USERPASS_CONFIRM; echo
    
    if [[ "$USERPASS" == "$USERPASS_CONFIRM" ]]; then
        break
    fi
    
    echo
    warn "Пароли не совпадают. Пожалуйста, попробуйте еще раз."
done

useradd -mG wheel,input,audio,video,storage,power,lp -s /bin/bash "$USERNAME"
echo "${USERNAME}:${USERPASS}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Пароль root
echo "root:${USERPASS}" | chpasswd

# Получаем GID основного пользователя (обычно 1000)
MAIN_GID=$(id -g "$USERNAME")

# --- Служебный пользователь render ---
echo
read -rp "Создать пользователя render (UID 900, GID $MAIN_GID)? (y/N): " RENDER_CHOICE
RENDER_CHOICE="${RENDER_CHOICE:-n}"

if [[ "$RENDER_CHOICE" =~ ^[Yy]$ ]]; then
    useradd -u 900 -g "$MAIN_GID" -M -s /usr/bin/nologin render
fi

# --- Дополнительный обычный пользователь ---
echo
read -rp "Создать еще пользователя? (y/N): " EXTRA_USER_CHOICE
EXTRA_USER_CHOICE="${EXTRA_USER_CHOICE:-n}"

if [[ "$EXTRA_USER_CHOICE" =~ ^[Yy]$ ]]; then
    echo
    read -rp "Введите имя пользователя: " EXTRA_USERNAME

    while true; do
        echo
        read -rsp "Введите пароль для $EXTRA_USERNAME: " EXTRA_USERPASS; echo
        read -rsp "Подтвердите пароль: " EXTRA_USERPASS_CONFIRM; echo
        
        if [[ "$EXTRA_USERPASS" == "$EXTRA_USERPASS_CONFIRM" ]]; then
            break
        fi

        echo
        warn "Пароли не совпадают. Пожалуйста, попробуйте еще раз."
    done
    
    useradd -m -g "$MAIN_GID" -G power,video,storage,lp,input,audio -s /bin/bash "$EXTRA_USERNAME"
    echo "${EXTRA_USERNAME}:${EXTRA_USERPASS}" | chpasswd
fi

# 10. Подключение студийного репозитория ---
echo
read -rp "Подключить студийный репозиторий? (y/N): " STUDIO_REPO_CHOICE
STUDIO_REPO_CHOICE="${STUDIO_REPO_CHOICE:-n}"

if [[ "$STUDIO_REPO_CHOICE" =~ ^[Yy]$ ]]; then
    # Перезаписываем mirrorlist
    echo 'Server = http://192.168.20.15:9129/repo/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist
    
    # Обновляем базы данных с учетом нового репозитория
    pacman -Syy --noconfirm
fi

# 12. Добавляем репозиторий archzfs
echo
info "Добавляем репозиторий archzfs\n"
echo -e '\n[archzfs]\nSigLevel = Never' >> /etc/pacman.conf
echo -e '\nServer = https://github.com/archzfs/archzfs/releases/download/experimental' >> /etc/pacman.conf

# 13. Установка приложений
# --- Базовые приложения ---
info "Установка базовых приложений\n"
PKGS=(zfs-dkms zfs-utils nfs-utils exfat-utils ntfs-3g unrar zip \
      unzip p7zip duf btop tmux eza bat yazi zoxide fzf ethtool \
      numactl ncdu lm_sensors) 

# --- Сетевой менеджер ---
echo "  1) systemd-networkd"
echo "  2) NetworkManager"
echo
read -rp "Выберите сетевой менеджер [1]: " NET_CHOICE

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
echo
read -rp "Установить софт для afrender? (y/N): " AFRENDER_CHOICE
AFRENDER_CHOICE="${AFRENDER_CHOICE:-n}"

if [[ "$AFRENDER_CHOICE" =~ ^[Yy]$ ]]; then
    PKGS+=(glu alsa-lib nss freetype2 fontconfig libglvnd libxv \
    libxmu libxi libxtst libxcomposite libxcursor libxrender \
    libxkbcommon)
fi

# --- vfxstation ---
echo
read -rp "Установить софт для vfxstation? (y/N): " STATION_CHOICE
STATION_CHOICE="${STATION_CHOICE:-n}"

if [[ "$STATION_CHOICE" =~ ^[Yy]$ ]]; then

    # Основные пакеты
    PKGS+=(plasma-desktop plasma-login-manager plasma-pa \
    plasma-systemmonitor kdeplasma-addons breeze breeze-gtk \
    kde-gtk-config konsole dolphin pipewire pipewire-pulse \
    pipewire-alsa transmission-qt sof-firmware spectacle \
    filelight filezilla firefox firefox-ublock-origin \
    ttf-liberation ark kscreen krename kate okular mpv mediainfo \
    telegram-desktop obsidian powerdevil xclip)

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
echo "  1) Nvidia"
echo "  2) AMD"
echo "  3) Intel"
echo "  4) Nouveau"
echo "  *) Не устанавливать видеодрайвер"
echo
read -rp "Выберите драйвер видеокарты [1]: " GPU_CHOICE

case "${GPU_CHOICE:-1}" in
    1) PKGS+=(nvidia-open-dkms nvidia-utils opencl-nvidia) ;;
    2) PKGS+=(mesa vulkan-radeon) ;;
    3) PKGS+=(mesa vulkan-intel) ;;
    4) PKGS+=(mesa) ;;
    *) ;;
esac
echo

pacman -Sy --needed --noconfirm "${PKGS[@]}"

# 14. Идентификатор системы для ZFS
echo
info "Создание идентификатора системы (hostid)\n"
zgenhostid "$(hostid)"
# mkdir -p /etc/zfs/zfs-list.cache
# touch /etc/zfs/zfs-list.cache/zroot

# 15. Сервисы
info "Включение systemd сервисов\n"

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
    info "Создаём сервис afrender.service\n"
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
echo
info "Прописываем модули загрузки (zfs) и хуки (zfs)\n"

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
echo "$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/yay-nopasswd
chmod 440 /etc/sudoers.d/yay-nopasswd

# 18. YAY
echo
info "Установка YAY (пакет yay-bin)\n"
su - "$USERNAME" -c "git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin && \
cd /tmp/yay-bin && makepkg -si --noconfirm"

# 19. ZFSBootMenu
echo
info "Установка ZFSBootMenu\n"
su - "$USERNAME" -c "yay -Sy --noconfirm zfsbootmenu perl-boolean"
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
echo
info "Создание загрузочной записи в EFI\n"
efibootmgr --disk "${DISK}" --part 1 --create --label "ZFSBootMenu" \
    --loader '\EFI\zbm\vmlinuz-linux-lts.EFI' \
    --unicode "spl_hostid=$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid" \
    --verbose

# 21. Возвращаем ввод пароля для pacman
rm -f /etc/sudoers.d/yay-nopasswd

# 22. Отключаем учетную запись root
echo
info "Отключаем учетную запись root\n"
passwd -l root

# 23. Создание сервисов монтирования серверов по NFS
echo
read -rp "Создать точки монтирования NFS? (y/N): " NFS_CHOICE
NFS_CHOICE="${NFS_CHOICE:-n}"

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

# 24. Создание символических ссылок
echo
read -rp "Создать символические ссылки? (y/N): " LINK_CHOICE
LINK_CHOICE="${LINK_CHOICE:-n}"

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

# 25. Отключение режимов сна и гибернации
echo
read -rp "Отключить режимы сна и гибернации? (y/N): " SLEEP_CHOICE
SLEEP_CHOICE="${SLEEP_CHOICE:-n}"

if [[ "$SLEEP_CHOICE" =~ ^[Yy]$ ]]; then
    systemctl mask suspend.target hibernate.target suspend-then-hibernate.target hybrid-sleep.target
fi

# 26. Настройка TRIM и датчиков (lm_sensors)
echo
read -rp "Включить TRIM и настроить датчики? (y/N): " TRIM_CHOICE
TRIM_CHOICE="${TRIM_CHOICE:-n}"

if [[ "$TRIM_CHOICE" =~ ^[Yy]$ ]]; then
    systemctl enable fstrim.timer
    sensors-detect
fi

# 27. Блокировка монтирования USB для обычных пользователей
echo
read -rp "Запретить пользователям монтировать USB-накопители? (y/N): " USB_RULES_CHOICE
USB_RULES_CHOICE="${USB_RULES_CHOICE:-n}"

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

# 28. Создание базовых директорий
echo
read -rp "Создать базовые директории? (y/N): " BASEDIR_CHOICE
BASEDIR_CHOICE="${BASEDIR_CHOICE:-n}"

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

# 29. Создание иконок программ
# Выполняется только если ранее был выбран софт для vfxstation
if [[ "$STATION_CHOICE" =~ ^[Yy]$ ]]; then
    echo
    read -rp "Создать иконки для программ? (y/N): " APPS_ICONS_CHOICE
    APPS_ICONS_CHOICE="${APPS_ICONS_CHOICE:-n}"

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

# 30. Включаем автомонтирование датасетов 
echo
info "Включаем автомонтирование датасетов /home и /root"
zfs set canmount=on zroot/DATA/home
# zfs set canmount=on zroot/DATA/root

# 31. Генерируем кэш для пула zroot
echo
info "Генерируем кэш для пула zroot"
mkdir -p /etc/zfs/zfs-list.cache
# zfs list -H -o name,mountpoint,canmount,atime,relatime,devices,exec,readonly,setuid,nbmand,encroot,keylocation,org.openzfs.systemd:requires,org.openzfs.systemd:requires-mounts-for,org.openzfs.systemd:before,org.openzfs.systemd:after,org.openzfs.systemd:wanted-by,org.openzfs.systemd:required-by,org.openzfs.systemd:nofail,org.openzfs.systemd:ignore > /etc/zfs/zfs-list.cache/zroot

zfs list -H -o name,mountpoint,canmount,atime,relatime,devices,exec,readonly,setuid,nbmand,\
encroot,keylocation,org.openzfs.systemd:requires,org.openzfs.systemd:requires-mounts-for,\
org.openzfs.systemd:before,org.openzfs.systemd:after,org.openzfs.systemd:wanted-by,\
org.openzfs.systemd:required-by,org.openzfs.systemd:nofail,org.openzfs.systemd:ignore\
 | sed -e 's|/mnt/|/|g' -e 's|/mnt$|/|g' > /etc/zfs/zfs-list.cache/zroot

CHROOT_EOF
chmod +x /mnt/root/setup-chroot.sh

# --- Запуск второго этапа в chroot ---
info "Запуск конфигурации в arch-chroot\n"
arch-chroot /mnt /root/setup-chroot.sh "$HOSTNAME" "$DISK"

# --- Настройка resolv.conf для systemd-resolved (вне chroot) ---
if [[ -f /mnt/etc/systemd/network/20-wired.network ]]; then
    # Удаляем старый файл
    rm -f /mnt/etc/resolv.conf
    # Создаем ссылку с относительным путем (рекомендация ArchWiki)
    ln -sf ../run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
fi

# --- Настройка Pacman ---
echo
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
# Формат с дефисами/точками (рекомендуемый):
# TIMESTAMP=$(date +'%Y.%m.%d_%H.%M.%S')

# Формат строго с двоеточиями (как в вашем примере):
TIMESTAMP=$(date +'%Y.%m.%d_%H:%M:%S')

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
echo
info "Установка завершена. Размонтирование дисков.\n"
umount -R /mnt
zpool export zroot
