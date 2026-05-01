#!/bin/bash
# ============================================================
# install-arch-gnome-no-zsh-config.sh v2
# Installazione Arch Linux + GNOME (senza configurazione zsh)
# Autore: Mirko
#
# Nota: zsh è installato come shell predefinita ma non configurato.
#       La configurazione (Oh My Zsh, p10k, alias, funzioni, greeter)
#       va applicata separatamente con il repo dot-files.
#
# Bootloader supportati: GRUB, systemd-boot, Limine
# ============================================================

set -e

RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'
CYAN='\e[36m'; BOLD='\e[1m'; RESET='\e[0m'

info()    { echo -e "${GREEN}[INFO]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }
section() {
    echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}  $1${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}\n"
}

# ============================================================
# VERIFICA UEFI
# ============================================================
[ -d /sys/firmware/efi/efivars ] || error "Non sei in modalità UEFI."

# ============================================================
# PARAMETRI
# ============================================================
section "Configurazione"

read -p "Hostname [archlinux]: " HOSTNAME; HOSTNAME=${HOSTNAME:-archlinux}

read -p "Nome utente: " USERNAME
while [ -z "$USERNAME" ]; do read -p "Nome utente (obbligatorio): " USERNAME; done

read -s -p "Password per $USERNAME: " USER_PASSWORD; echo
read -s -p "Conferma: " USER_PASSWORD2; echo
while [ "$USER_PASSWORD" != "$USER_PASSWORD2" ]; do
    warn "Non corrispondono."
    read -s -p "Password per $USERNAME: " USER_PASSWORD; echo
    read -s -p "Conferma: " USER_PASSWORD2; echo
done

read -s -p "Password root: " ROOT_PASSWORD; echo
read -s -p "Conferma: " ROOT_PASSWORD2; echo
while [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD2" ]; do
    warn "Non corrispondono."
    read -s -p "Password root: " ROOT_PASSWORD; echo
    read -s -p "Conferma: " ROOT_PASSWORD2; echo
done

echo ""
info "Dischi disponibili:"; lsblk -d -o NAME,SIZE,MODEL | grep -v loop; echo ""
read -p "Disco (es. sda, nvme0n1): " DISK_INPUT
DISK="/dev/${DISK_INPUT}"
while [ ! -b "$DISK" ]; do
    warn "Disco $DISK non trovato."
    read -p "Disco: " DISK_INPUT; DISK="/dev/${DISK_INPUT}"
done

if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART1="${DISK}p1"; PART2="${DISK}p2"
else
    PART1="${DISK}1"; PART2="${DISK}2"
fi

echo ""
echo "CPU:"; echo "  1) AMD"; echo "  2) Intel"
read -p "Scelta [1/2]: " CPU_CHOICE
[ "$CPU_CHOICE" == "2" ] && UCODE="intel-ucode" || UCODE="amd-ucode"

echo ""
echo "Display server:"; echo "  1) Wayland"; echo "  2) X11"
read -p "Scelta [1/2]: " DS_CHOICE
[ "$DS_CHOICE" == "2" ] && DISPLAY_SERVER="x11" || DISPLAY_SERVER="wayland"
[ "$DISPLAY_SERVER" == "x11" ] && XORG_PKGS="xorg-server xorg-xinit" || XORG_PKGS=""

echo ""
echo "Driver video:"
echo "  1) VirtualBox/VMware"; echo "  2) NVIDIA"
echo "  3) AMD"; echo "  4) Intel"; echo "  5) Automatico"
read -p "Scelta [1-5]: " GPU_CHOICE
case "$GPU_CHOICE" in
    1) GPU_PKGS="xf86-video-vesa xf86-video-vmware" ;;
    2) GPU_PKGS="nvidia nvidia-utils nvidia-settings" ;;
    3) GPU_PKGS="xf86-video-amdgpu mesa" ;;
    4) GPU_PKGS="xf86-video-intel mesa" ;;
    *) GPU_PKGS="mesa" ;;
esac

echo ""
echo "Bootloader:"
echo "  1) GRUB (consigliato)"
echo "  2) systemd-boot"
echo "  3) Limine"
read -p "Scelta [1-3]: " BOOT_CHOICE
case "$BOOT_CHOICE" in
    2) BOOTLOADER="systemd-boot" ;;
    3) BOOTLOADER="limine" ;;
    *) BOOTLOADER="grub" ;;
esac

echo ""
read -p "VirtualBox Guest Additions? [s/N]: " VBOX_CHOICE
[[ "$VBOX_CHOICE" =~ ^[sS]$ ]] && VBOX_PKG="virtualbox-guest-utils" || VBOX_PKG=""

read -p "Dimensione ZRAM in MB [4096]: " ZRAM_SIZE; ZRAM_SIZE=${ZRAM_SIZE:-4096}

echo ""
read -p "Installare Plymouth (logo Arch al boot)? [S/n]: " PLYMOUTH_CHOICE
[[ "$PLYMOUTH_CHOICE" =~ ^[nN]$ ]] && INSTALL_PLYMOUTH=false || INSTALL_PLYMOUTH=true

# ============================================================
# RIEPILOGO
# ============================================================
section "Riepilogo"
echo -e "  Hostname:       ${CYAN}${HOSTNAME}${RESET}"
echo -e "  Utente:         ${CYAN}${USERNAME}${RESET}"
echo -e "  Disco:          ${CYAN}${DISK}${RESET}"
echo -e "  CPU/Microcode:  ${CYAN}${UCODE}${RESET}"
echo -e "  Display server: ${CYAN}${DISPLAY_SERVER}${RESET}"
echo -e "  Driver video:   ${CYAN}${GPU_PKGS}${RESET}"
echo -e "  Bootloader:     ${CYAN}${BOOTLOADER}${RESET}"
echo -e "  ZRAM:           ${CYAN}${ZRAM_SIZE}MB${RESET}"
[ -n "$VBOX_PKG" ] && echo -e "  VirtualBox:     ${CYAN}Sì${RESET}"
$INSTALL_PLYMOUTH && echo -e "  Plymouth:       ${CYAN}Sì${RESET}" || echo -e "  Plymouth:       ${CYAN}No${RESET}"
echo ""
warn "Il disco ${DISK} verrà completamente formattato!"
read -p "Continuare? [s/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || error "Annullato."

# ============================================================
# PARTIZIONAMENTO
# ============================================================
section "Partizionamento"
timedatectl set-ntp true
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 "$DISK"
sgdisk -n 2:0:0     -t 2:8300 "$DISK"
partprobe "$DISK"; sleep 2
mkfs.fat -F32 "$PART1"
mkfs.btrfs -L "archroot" -f "$PART2"

# ============================================================
# SUBVOLUMI BTRFS
# ============================================================
section "Subvolumi BTRFS"
mount "$PART2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
umount /mnt

# ============================================================
# MOUNT
# ============================================================
section "Mount"
BTRFS_OPTS="noatime,compress=zstd,space_cache=v2"
mount -o "${BTRFS_OPTS},subvol=@"          "$PART2" /mnt
mkdir -p /mnt/{boot,home,.snapshots,var/log,var/cache}
mount -o "${BTRFS_OPTS},subvol=@home"      "$PART2" /mnt/home
mount -o "${BTRFS_OPTS},subvol=@snapshots" "$PART2" /mnt/.snapshots
mount -o "${BTRFS_OPTS},subvol=@log"       "$PART2" /mnt/var/log
mount -o "${BTRFS_OPTS},subvol=@cache"     "$PART2" /mnt/var/cache
mount "$PART1" /mnt/boot

# ============================================================
# PACCHETTI BASE
# ============================================================
section "Installazione pacchetti"

case "$BOOTLOADER" in
    grub)         BOOT_PKGS="grub efibootmgr" ;;
    systemd-boot) BOOT_PKGS="efibootmgr" ;;
    limine)       BOOT_PKGS="limine efibootmgr" ;;
esac

pacstrap -K /mnt \
    base base-devel \
    linux-zen linux-zen-headers linux-firmware \
    ${UCODE} btrfs-progs \
    zsh zsh-completions \
    networkmanager \
    vim git curl wget \
    zram-generator \
    snapper snap-pac \
    sudo openssh \
    pacman-contrib \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    bluez bluez-utils \
    gnome gnome-extra \
    ${XORG_PKGS} \
    ${GPU_PKGS} \
    ${BOOT_PKGS} \
    ${VBOX_PKG}

# ============================================================
# FSTAB
# ============================================================
section "fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# FIX: rimuovi riga /boot btrfs errata e aggiungi quella vfat corretta
BOOT_UUID=$(blkid -s UUID -o value "$PART1")
sed -i '/\/boot.*btrfs/d' /mnt/etc/fstab
echo "UUID=${BOOT_UUID}  /boot  vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro  0 2" >> /mnt/etc/fstab
info "fstab corretto."

# ============================================================
# CHROOT - CONFIGURAZIONE SISTEMA
# ============================================================
section "Configurazione sistema"

# Salva variabili per uso in chroot
ROOT_UUID=$(blkid -s UUID -o value "$PART2")

arch-chroot /mnt /bin/bash -e << CHROOT
# Timezone e orologio
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc

# Locale
echo "it_IT.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=it_IT.UTF-8" > /etc/locale.conf

# FIX: vconsole prima di mkinitcpio
echo "KEYMAP=it" > /etc/vconsole.conf

# Hostname
echo "${HOSTNAME}" > /etc/hostname

# mkinitcpio con btrfs
sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
mkinitcpio -P

# ZRAM
cat > /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = ${ZRAM_SIZE}
compression-algorithm = zstd
swap-priority = 100
EOF

# Password root
echo "root:${ROOT_PASSWORD}" | chpasswd

# Utente
useradd -m -G wheel -s /bin/zsh ${USERNAME}
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Servizi
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable gdm
systemctl enable bluetooth
systemctl disable NetworkManager-wait-online.service
$([ -n "${VBOX_PKG}" ] && echo "systemctl enable vboxservice")

# Snapper
mkdir -p /etc/snapper/configs
cat > /etc/snapper/configs/root << 'EOF'
SUBVOLUME="/"
FSTYPE="btrfs"
QGROUP=""
SPACE_LIMIT="0.5"
FREE_LIMIT="0.2"
ALLOW_USERS=""
ALLOW_GROUPS=""
SYNC_ACL="no"
BACKGROUND_COMPARISON="yes"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="10"
NUMBER_LIMIT_IMPORTANT="5"
TIMELINE_CREATE="no"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="0"
TIMELINE_LIMIT_DAILY="0"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"
EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
EOF
echo 'SNAPPER_CONFIGS="root"' > /etc/conf.d/snapper
systemctl enable snapper-cleanup.timer
echo "${USERNAME} ALL=(ALL) NOPASSWD: /usr/bin/btrfs subvolume list /" > /etc/sudoers.d/greeter
CHROOT

# ============================================================
# BOOTLOADER
# ============================================================
section "Installazione bootloader: ${BOOTLOADER}"

ROOT_UUID=$(blkid -s UUID -o value "$PART2")

case "$BOOTLOADER" in
    grub)
        arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        info "GRUB installato."
        ;;

    systemd-boot)
        arch-chroot /mnt bootctl install

        cat > /mnt/boot/loader/loader.conf << 'EOF'
default arch-zen.conf
timeout 3
console-mode max
editor no
EOF

        cat > /mnt/boot/loader/entries/arch-zen.conf << EOF
title   Arch Linux (zen)
linux   /vmlinuz-linux-zen
initrd  /${UCODE}.img
initrd  /initramfs-linux-zen.img
options root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@ rw quiet loglevel=3
EOF
        info "systemd-boot installato."
        ;;

    limine)
        # Sfondo: cerca archcustom.png nella stessa directory dello script
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "${SCRIPT_DIR}/archcustom.png" ]; then
            cp "${SCRIPT_DIR}/archcustom.png" /mnt/boot/archcustom.png
            LIMINE_WALLPAPER="wallpaper: boot():/archcustom.png"
            info "Sfondo archcustom.png copiato in /boot/"
        else
            LIMINE_WALLPAPER=""
            warn "archcustom.png non trovato accanto allo script — nessuno sfondo impostato."
        fi

        # Installa file EFI
        mkdir -p /mnt/boot/EFI/limine
        cp /mnt/usr/share/limine/BOOTX64.EFI /mnt/boot/EFI/limine/

        # Registra voce EFI
        efibootmgr --create \
            --disk "$DISK" \
            --part 1 \
            --label "Limine" \
            --loader /EFI/limine/BOOTX64.EFI \
            --unicode

        # Crea limine.conf con palette Catppuccin Mocha, sfondo e group entry
        cat > /mnt/boot/limine.conf << EOF
term_palette: 1e1e2e;f38ba8;a6e3a1;24ffff;89b4fa;f5c2e7;24ffff;24ffff
term_palette_bright: 24ffff;f38ba8;a6e3a1;24ffff;89b4fa;f5c2e7;24ffff;24ffff
term_foreground: 24ffff
term_foreground_bright: f38ba8
term_background_bright: 585b70
timeout: 10
${LIMINE_WALLPAPER}
interface_branding:
default_entry: Arch Linux (zen)/Kernel zen

/+Arch Linux (zen)

  //Kernel zen
  protocol: linux
  kernel_path: boot():/vmlinuz-linux-zen
  module_path: boot():/${UCODE}.img
  module_path: boot():/initramfs-linux-zen.img
  cmdline: root=UUID=${ROOT_UUID} rootfstype=btrfs rootflags=subvol=@ rw quiet loglevel=3
EOF

        # Configura /etc/default/limine per limine-snapper-sync
        cat > /mnt/etc/default/limine << 'LIMINEDEFAULT'
ROOT_SNAPSHOTS_PATH=/@snapshots
TARGET_OS_NAME=+Arch Linux (zen)
LIMINEDEFAULT

        info "Limine installato."
        ;;
esac

# ============================================================
# PARU
# ============================================================
section "Installazione paru"

arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << 'PARUINSTALL'
set -e
cd /tmp
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin
makepkg -si --noconfirm
cd && rm -rf /tmp/paru-bin
PARUINSTALL


# ============================================================
# TASTIERA GNOME
# ============================================================
arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << 'GNOMECONF'
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'it')]" 2>/dev/null || true
GNOMECONF

# ============================================================
# PLYMOUTH (opzionale)
# ============================================================
if [ "$INSTALL_PLYMOUTH" = true ]; then
    section "Plymouth"
    arch-chroot /mnt pacman -S --noconfirm plymouth

    arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << 'PLYMOUTHEOF'
paru -S --noconfirm plymouth-theme-arch-charge-big
PLYMOUTHEOF

    arch-chroot /mnt bash -c "sed -i 's/sd-vconsole block/sd-vconsole plymouth block/' /etc/mkinitcpio.conf"
    arch-chroot /mnt plymouth-set-default-theme -R arch-charge-big

    case "$BOOTLOADER" in
        grub)
            arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet splash"/' /etc/default/grub
            arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
            ;;
        systemd-boot)
            sed -i 's/rw quiet loglevel=3/rw quiet splash loglevel=3/' /mnt/boot/loader/entries/arch-zen.conf
            ;;
        limine)
            sed -i 's/rw quiet loglevel=3/rw quiet splash loglevel=3/' /mnt/boot/limine.conf
            ;;
    esac
    info "Plymouth configurato."
fi

# ============================================================
# FINE
# ============================================================
section "Installazione completata!"
echo -e "  ${GREEN}✓${RESET} Sistema installato"
echo -e "  ${GREEN}✓${RESET} GNOME + GDM"
echo -e "  ${GREEN}✓${RESET} Bootloader: ${CYAN}${BOOTLOADER}${RESET}"
echo -e "  ${GREEN}✓${RESET} Utente ${CYAN}${USERNAME}${RESET} configurato"
echo -e "  ${GREEN}✓${RESET} zsh installato (configurazione da applicare con dot-files)"
echo -e "  ${GREEN}✓${RESET} paru installato"
echo -e "  ${GREEN}✓${RESET} Snapper"
echo -e "  ${GREEN}✓${RESET} ZRAM ${ZRAM_SIZE}MB"
$INSTALL_PLYMOUTH && echo -e "  ${GREEN}✓${RESET} Plymouth arch-charge-big"
[ "$BOOTLOADER" = "limine" ] && warn "Dopo il primo boot installa manualmente: paru -S limine-snapper-sync"
echo ""
warn "Prima del riavvio: rimuovi la ISO dal lettore!"
warn "Dopo il primo login: esegui lo script dot-files per configurare zsh, Oh My Zsh, p10k e alias."
echo ""
read -p "Riavviare ora? [s/N]: " REBOOT_NOW
[[ "$REBOOT_NOW" =~ ^[sS]$ ]] && umount -R /mnt && reboot || echo -e "\nEsegui: ${CYAN}umount -R /mnt && reboot${RESET}"
