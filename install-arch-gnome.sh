#!/bin/bash
# ============================================================
# install-arch-gnome.sh
# Installazione Arch Linux con GNOME
# Autore: Mirko
#
# Caratteristiche:
#   - GNOME come unico DE
#   - Scelta bootloader: GRUB, systemd-boot o Limine
#   - Scelta display server: Wayland o X11
#   - Btrfs con subvolumi
#   - Snapper pre/post pacman
#   - ZRAM swap
#   - Oh My Zsh + Powerlevel10k + Greeter
#   - Gestione batteria affidata a GNOME (nessun TLP/alias)
#
# Fix documentati durante installazione reale:
#   - vconsole.conf prima di mkinitcpio
#   - fstab /boot corretto (vfat, non btrfs subvol)
#   - snapper configurato manualmente (no dbus in chroot)
#   - NetworkManager-wait-online disabilitato
#
# UTILIZZO:
#   curl -O https://raw.githubusercontent.com/mruin/arch-install/main/install-arch-gnome.sh
#   chmod +x install-arch-gnome.sh && ./install-arch-gnome.sh
# ============================================================

set -e

# ============================================================
# COLORI E FUNZIONI
# ============================================================
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
[ -d /sys/firmware/efi/efivars ] || error "Non sei in modalità UEFI. Controlla le impostazioni del BIOS/VM."

# ============================================================
# RACCOLTA PARAMETRI
# ============================================================
section "Configurazione installazione - Arch Linux + GNOME"

# Hostname
read -p "Hostname [archlinux]: " HOSTNAME
HOSTNAME=${HOSTNAME:-archlinux}

# Username
read -p "Nome utente: " USERNAME
while [ -z "$USERNAME" ]; do
    read -p "Nome utente (obbligatorio): " USERNAME
done

# Password utente
read -s -p "Password per $USERNAME: " USER_PASSWORD; echo
read -s -p "Conferma password: " USER_PASSWORD2; echo
while [ "$USER_PASSWORD" != "$USER_PASSWORD2" ]; do
    warn "Password non corrispondenti."
    read -s -p "Password per $USERNAME: " USER_PASSWORD; echo
    read -s -p "Conferma password: " USER_PASSWORD2; echo
done

# Password root
read -s -p "Password root: " ROOT_PASSWORD; echo
read -s -p "Conferma password root: " ROOT_PASSWORD2; echo
while [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD2" ]; do
    warn "Password non corrispondenti."
    read -s -p "Password root: " ROOT_PASSWORD; echo
    read -s -p "Conferma password root: " ROOT_PASSWORD2; echo
done

# Disco
echo ""
info "Dischi disponibili:"
lsblk -d -o NAME,SIZE,MODEL | grep -v loop
echo ""
read -p "Disco di installazione (es. sda, nvme0n1, vda): " DISK_INPUT
DISK="/dev/${DISK_INPUT}"
while [ ! -b "$DISK" ]; do
    warn "Disco $DISK non trovato."
    read -p "Disco di installazione: " DISK_INPUT
    DISK="/dev/${DISK_INPUT}"
done

# Partizioni
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART1="${DISK}p1"
    PART2="${DISK}p2"
else
    PART1="${DISK}1"
    PART2="${DISK}2"
fi

# CPU / microcode
echo ""
echo "Tipo di CPU:"
echo "  1) AMD  (amd-ucode)"
echo "  2) Intel (intel-ucode)"
read -p "Scelta [1/2]: " CPU_CHOICE
[ "$CPU_CHOICE" == "2" ] && UCODE="intel-ucode" || UCODE="amd-ucode"

# Display server
echo ""
echo "Display server:"
echo "  1) Wayland (consigliato)"
echo "  2) X11"
read -p "Scelta [1/2]: " DS_CHOICE
[ "$DS_CHOICE" == "2" ] && DISPLAY_SERVER="x11" || DISPLAY_SERVER="wayland"

# Driver video
echo ""
echo "Driver video:"
echo "  1) VMware/VirtualBox (vesa/vmsvga)"
echo "  2) NVIDIA"
echo "  3) AMD"
echo "  4) Intel"
echo "  5) Nessuno / automatico"
read -p "Scelta [1-5]: " GPU_CHOICE
case "$GPU_CHOICE" in
    1) GPU_PKGS="xf86-video-vesa xf86-video-vmware" ;;
    2) GPU_PKGS="nvidia nvidia-utils nvidia-settings" ;;
    3) GPU_PKGS="xf86-video-amdgpu mesa" ;;
    4) GPU_PKGS="xf86-video-intel mesa" ;;
    *) GPU_PKGS="mesa" ;;
esac

# Bootloader
echo ""
echo "Bootloader:"
echo "  1) GRUB (consigliato, massima compatibilità)"
echo "  2) systemd-boot (leggero, nativo UEFI)"
echo "  3) Limine (moderno, veloce)"
read -p "Scelta [1-3]: " BOOT_CHOICE
case "$BOOT_CHOICE" in
    2) BOOTLOADER="systemd-boot" ;;
    3) BOOTLOADER="limine" ;;
    *) BOOTLOADER="grub" ;;
esac

# VirtualBox
echo ""
read -p "Installare VirtualBox Guest Additions? [s/N]: " VBOX_CHOICE
[[ "$VBOX_CHOICE" =~ ^[sS]$ ]] && VBOX_PKG="virtualbox-guest-utils" || VBOX_PKG=""

# ZRAM
read -p "Dimensione ZRAM swap in MB [4096]: " ZRAM_SIZE
ZRAM_SIZE=${ZRAM_SIZE:-4096}

# Plymouth
echo ""
read -p "Installare Plymouth (logo Arch al boot)? [S/n]: " PLYMOUTH_CHOICE
[[ "$PLYMOUTH_CHOICE" =~ ^[nN]$ ]] && INSTALL_PLYMOUTH=false || INSTALL_PLYMOUTH=true

# ============================================================
# RIEPILOGO
# ============================================================
section "Riepilogo configurazione"
echo -e "  Hostname:       ${CYAN}${HOSTNAME}${RESET}"
echo -e "  Utente:         ${CYAN}${USERNAME}${RESET}"
echo -e "  Disco:          ${CYAN}${DISK}${RESET}"
echo -e "  Microcode:      ${CYAN}${UCODE}${RESET}"
echo -e "  Display server: ${CYAN}${DISPLAY_SERVER}${RESET}"
echo -e "  Driver video:   ${CYAN}${GPU_PKGS}${RESET}"
echo -e "  Bootloader:     ${CYAN}${BOOTLOADER}${RESET}"
echo -e "  ZRAM:           ${CYAN}${ZRAM_SIZE}MB${RESET}"
echo -e "  VirtualBox:     ${CYAN}${VBOX_PKG:-No}${RESET}"
echo -e "  Plymouth:       ${CYAN}$( $INSTALL_PLYMOUTH && echo 'Sì (arch-charge-big)' || echo 'No' )${RESET}"
echo ""
warn "ATTENZIONE: Il disco ${DISK} verrà completamente formattato!"
read -p "Continuare? [s/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || error "Installazione annullata."

# ============================================================
# FASE 1 - PREPARAZIONE
# ============================================================
section "Fase 1 - Preparazione"
info "Sincronizzazione orologio..."
timedatectl set-ntp true

# ============================================================
# FASE 2 - PARTIZIONAMENTO
# ============================================================
section "Fase 2 - Partizionamento"
info "Partizionamento di ${DISK}..."
sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System" "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"Linux root"  "$DISK"
partprobe "$DISK"
sleep 2

info "Formattazione partizioni..."
mkfs.fat -F32 "$PART1"
mkfs.btrfs -L "archroot" -f "$PART2"

# ============================================================
# FASE 3 - SUBVOLUMI BTRFS
# ============================================================
section "Fase 3 - Subvolumi BTRFS"
mount "$PART2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
umount /mnt

# ============================================================
# FASE 4 - MOUNT
# ============================================================
section "Fase 4 - Mount filesystem"
BTRFS_OPTS="noatime,compress=zstd,space_cache=v2"
mount -o "${BTRFS_OPTS},subvol=@"          "$PART2" /mnt
mkdir -p /mnt/{boot,home,.snapshots,var/log,var/cache}
mount -o "${BTRFS_OPTS},subvol=@home"      "$PART2" /mnt/home
mount -o "${BTRFS_OPTS},subvol=@snapshots" "$PART2" /mnt/.snapshots
mount -o "${BTRFS_OPTS},subvol=@log"       "$PART2" /mnt/var/log
mount -o "${BTRFS_OPTS},subvol=@cache"     "$PART2" /mnt/var/cache
# IMPORTANTE: /boot deve essere la partizione EFI vfat, NON un subvol btrfs
mount "$PART1" /mnt/boot

# ============================================================
# FASE 5 - INSTALLAZIONE PACCHETTI
# ============================================================
section "Fase 5 - Installazione sistema"

# Pacchetti GNOME
if [ "$DISPLAY_SERVER" == "x11" ]; then
    GNOME_PKGS="gnome gnome-extra xorg-server xorg-xinit"
else
    GNOME_PKGS="gnome gnome-extra"
fi

# Pacchetti bootloader
case "$BOOTLOADER" in
    grub)         BOOT_PKGS="grub efibootmgr" ;;
    systemd-boot) BOOT_PKGS="efibootmgr" ;;
    limine)       BOOT_PKGS="limine efibootmgr" ;;
esac

BASE_PKGS="base base-devel linux-zen linux-zen-headers linux-firmware ${UCODE} btrfs-progs zsh zsh-completions networkmanager vim git curl wget zram-generator snapper snap-pac sudo openssh pacman-contrib pipewire pipewire-pulse pipewire-alsa wireplumber bluez bluez-utils ${VBOX_PKG} ${GNOME_PKGS} ${GPU_PKGS} ${BOOT_PKGS}"

pacstrap -K /mnt $BASE_PKGS

# ============================================================
# FASE 6 - FSTAB
# ============================================================
section "Fase 6 - Generazione fstab"
genfstab -U /mnt >> /mnt/etc/fstab

# FIX: rimuovi eventuale riga /boot errata come btrfs subvol
info "Fix fstab /boot..."
BOOT_UUID=$(blkid -s UUID -o value "$PART1")
sed -i '/\/boot.*btrfs/d' /mnt/etc/fstab
echo "UUID=${BOOT_UUID}  /boot  vfat  rw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro  0 2" >> /mnt/etc/fstab

# ============================================================
# FASE 7 - CONFIGURAZIONE SISTEMA IN CHROOT
# ============================================================
section "Fase 7 - Configurazione sistema"

arch-chroot /mnt /bin/bash << CHROOT
set -e

# Timezone
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc

# Locale
echo "it_IT.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=it_IT.UTF-8" > /etc/locale.conf

# FIX: vconsole.conf prima di mkinitcpio
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

# Bootloader
$(case "$BOOTLOADER" in
    grub)
        echo 'grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB'
        echo 'grub-mkconfig -o /boot/grub/grub.cfg'
        ;;
    systemd-boot)
        echo 'bootctl install'
        echo 'ROOT_UUID=$(blkid -s UUID -o value /dev/'${DISK_INPUT}'2)'
        echo 'cat > /boot/loader/loader.conf << EOF'
        echo 'default arch-zen.conf'
        echo 'timeout 3'
        echo 'console-mode max'
        echo 'editor no'
        echo 'EOF'
        echo 'cat > /boot/loader/entries/arch-zen.conf << EOF'
        echo 'title   Arch Linux (zen)'
        echo 'linux   /vmlinuz-linux-zen'
        echo 'initrd  /'"${UCODE}"'.img'
        echo 'initrd  /initramfs-linux-zen.img'
        echo 'options root=UUID=${ROOT_UUID} rw quiet loglevel=3'
        echo 'EOF'
        ;;
    limine)
        echo 'ROOT_UUID=$(blkid -s UUID -o value /dev/'${DISK_INPUT}'2)'
        # Limine UEFI - copia i file EFI nella partizione EFI
        echo 'mkdir -p /boot/EFI/limine'
        echo 'cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/'
        echo 'cp /usr/share/limine/limine-uefi-cd.bin /boot/EFI/limine/'
        # Registra Limine come voce di boot EFI
        echo 'efibootmgr --create --disk /dev/'${DISK_INPUT}' --part 1 --label "Limine" --loader /EFI/limine/BOOTX64.EFI'
        echo 'cat > /boot/limine.conf << EOF'
        echo 'timeout: 3'
        echo 'default_entry: 1'
        echo ''
        echo '/Arch Linux (zen)'
        echo '    protocol: linux'
        echo '    kernel_path: boot():/vmlinuz-linux-zen'
        echo '    module_path: boot():/'${UCODE}'.img'
        echo '    module_path: boot():/initramfs-linux-zen.img'
        echo '    cmdline: root=UUID=${ROOT_UUID} rw quiet loglevel=3'
        echo 'EOF'
        ;;
esac)

# Password root
echo "root:${ROOT_PASSWORD}" | chpasswd

# Utente
useradd -m -G wheel -s /bin/zsh ${USERNAME}
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# Sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Servizi
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable gdm
systemctl enable bluetooth
$([ -n "${VBOX_PKG}" ] && echo "systemctl enable vboxservice" || echo "true")
systemctl disable NetworkManager-wait-online.service

# Tastiera italiana per GNOME
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'it')]" 2>/dev/null || true

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

# Permesso sudo btrfs per greeter
echo "${USERNAME} ALL=(ALL) NOPASSWD: /usr/bin/btrfs subvolume list /" > /etc/sudoers.d/greeter

CHROOT

# ============================================================
# FASE 8 - CONFIGURAZIONE UTENTE
# ============================================================
section "Fase 8 - Configurazione utente"

arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << USERCHROOT
set -e

# Oh My Zsh
sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Plugin
git clone https://github.com/zsh-users/zsh-autosuggestions \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone --depth=1 https://github.com/romkatv/powerlevel10k \${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k

# Tema e plugin
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
sed -i 's/plugins=(git)/plugins=(git sudo archlinux zsh-autosuggestions zsh-syntax-highlighting history-substring-search colored-man-pages)/' ~/.zshrc

# File alias
cat > ~/.zsh_aliases << 'EOF'
alias aggiorna='paru -Syu'
alias cat='bat'
alias htop='btop'
EOF

# Funzioni e greeter
cat >> ~/.zshrc << 'EOF'

# File alias personalizzati
[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases

# Alias manager
function salias() {
    if [[ "\$1" == *"="* ]]; then
        local alias_name="\${1%%=*}"
        local alias_value="\${1#*=}"
        if grep -q "^alias \${alias_name}=" ~/.zsh_aliases; then
            echo "Alias '\${alias_name}' esiste già. Vuoi sovrascriverlo? [y/N]"
            read answer
            if [[ "\$answer" == "y" || "\$answer" == "Y" ]]; then
                sed -i "/^alias \${alias_name}=/d" ~/.zsh_aliases
            else
                return 1
            fi
        fi
        echo "alias \${alias_name}='\${alias_value}'" >> ~/.zsh_aliases
        builtin alias "\${alias_name}=\${alias_value}"
        echo "✓ Alias salvato: \${alias_name}='\${alias_value}'"
    else
        echo "Uso: salias nome='comando'"
    fi
}

# Lista alias formattata
function lista() {
    echo ""
    printf "%-20s %s\n" "ALIAS" "COMANDO"
    printf "%-20s %s\n" "────────────────────" "──────────────────────────────────────"
    sort ~/.zsh_aliases | while IFS= read -r line; do
        local name="\${line#alias }"
        local cmd="\${name#*=\'}"
        cmd="\${cmd%\'}"
        name="\${name%%=*}"
        printf "%-20s %s\n" "\$name" "\$cmd"
    done
    echo ""
}

# Wrapper paru con check riavvio
function paru() {
    command paru "\$@"
    if [[ "\$*" == *"-S"* || "\$*" == *"-U"* || "\$*" == *"-u"* ]]; then
        echo "\n🔍 Controllo se è necessario un riavvio..."
        sudo needrestart -r l
    fi
}
EOF

# Greeter
cat > ~/.greeter.zsh << 'EOF'
#!/usr/bin/env zsh
local reset="\e[0m"
local bold="\e[1m"
local cyan="\e[36m"
local green="\e[32m"
local yellow="\e[33m"
local white="\e[97m"
local gray="\e[90m"

local sep="\${gray}\$(printf '─%.0s' {1..60})\${reset}"
local hostname=\$(cat /etc/hostname)
local username=\$(whoami)
local datetime=\$(date "+%A %d %B %Y, %H:%M")
local uptime_raw=\$(uptime -p | sed 's/up //')
local ram_used=\$(free -h | awk '/^Mem:/ {print \$3}')
local ram_total=\$(free -h | awk '/^Mem:/ {print \$2}')
local ip_local=\$(ip -4 addr show scope global | awk '/inet/ {print \$2}' | cut -d'/' -f1 | paste -sd ',' -)
local ip_ext=\$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "N/D")
local disk_size=\$(df -h / | awk 'NR==2 {print \$2}')
local disk_used=\$(df -h / | awk 'NR==2 {print \$3}')
local disk_pct=\$(df -h / | awk 'NR==2 {print \$5}')
local snapshots=\$(sudo btrfs subvolume list / 2>/dev/null | grep -c "snapshot" || echo "N/D")
local updates=\$(checkupdates 2>/dev/null | wc -l)
local aur_updates=\$(paru -Qua 2>/dev/null | wc -l)
local total_updates=\$((updates + aur_updates))
local updates_str
if [[ \$total_updates -eq 0 ]]; then
    updates_str="Sistema aggiornato"
else
    updates_str="\${total_updates} pacchetti pronti"
fi
local reboot_str
if needrestart -k 2>&1 | grep -q "Running kernel seems to be up-to-date"; then
    reboot_str="Nessun riavvio richiesto"
else
    reboot_str="\${yellow}Riavvio consigliato\${reset}"
fi

echo ""
echo -e "\${sep}"
echo -e "    \${bold}\${white}Benvenuto su \${cyan}\${hostname}\${white}, \${green}\${username}\${reset}"
echo -e "    \${gray}\${datetime}\${reset}"
echo -e "\${sep}"
echo -e "\${bold}\${white}Stato Sistema:\${reset}"
echo -e "  󱄢  \${white}Uptime:     \${reset} \${uptime_raw}"
echo -e "  󰍛  \${white}RAM:        \${reset} \${ram_used}/\${ram_total}"
echo -e "  󰖟  \${white}IP Locale:  \${reset} \${ip_local}"
echo -e "  󰩠  \${white}IP Esterno: \${reset} \${ip_ext}"
echo -e "\${bold}\${white}Archiviazione BTRFS:\${reset}"
echo -e "  󱗆  \${white}Root (/):   \${reset} \${disk_used}/\${disk_size} (\${disk_pct})"
echo -e "  󱘊  \${white}Snapshots:  \${reset} \${snapshots} attivi"
echo -e "  󰚰  \${white}Updates:    \${reset} \${updates_str}"
echo -e "  󰜉  \${white}Riavvio:    \${reset} \${reboot_str}"
echo -e "\${sep}"
echo ""
EOF

chmod +x ~/.greeter.zsh
sed -i '1s/^/source ~\/.greeter.zsh\n/' ~/.zshrc

# FIX: p10k instant prompt warning
if [ -f ~/.p10k.zsh ]; then
    sed -i 's/typeset -g POWERLEVEL9K_INSTANT_PROMPT=verbose/typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet/' ~/.p10k.zsh
fi

USERCHROOT

# ============================================================
# FASE 9 - PARU
# ============================================================
section "Fase 9 - Installazione paru"

arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << PARUINSTALL
set -e
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm
cd ~ && rm -rf /tmp/paru
PARUINSTALL

# ============================================================
# FASE 10 - PACCHETTI AGGIUNTIVI
# ============================================================
section "Fase 10 - Pacchetti aggiuntivi"

arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << POSTINSTALL
set -e
paru -S --noconfirm needrestart bat btop
POSTINSTALL

# ============================================================
# FASE 11 - PLYMOUTH (opzionale)
# ============================================================
if [ "$INSTALL_PLYMOUTH" = true ]; then
    section "Fase 11 - Plymouth"
    info "Installazione Plymouth..."
    arch-chroot /mnt pacman -S --noconfirm plymouth

    arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << PLYMOUTHEOF
paru -S --noconfirm plymouth-theme-arch-charge-big
PLYMOUTHEOF

    arch-chroot /mnt bash -c "sed -i 's/sd-vconsole block/sd-vconsole plymouth block/' /etc/mkinitcpio.conf"
    arch-chroot /mnt plymouth-set-default-theme -R arch-charge-big

    case "$BOOTLOADER" in
        grub)
            arch-chroot /mnt bash -c "sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet\"/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet splash\"/' /etc/default/grub"
            arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
            ;;
        systemd-boot)
            arch-chroot /mnt bash -c "sed -i 's/options root=/options quiet splash loglevel=3 root=/' /boot/loader/entries/arch-zen.conf"
            ;;
        limine)
            arch-chroot /mnt bash -c "sed -i 's/cmdline: root=/cmdline: quiet splash loglevel=3 root=/' /boot/limine.conf"
            ;;
    esac
    info "Plymouth configurato con tema arch-charge-big."
fi

# ============================================================
# FINE
# ============================================================
section "Installazione completata!"
echo -e "  ${GREEN}✓${RESET} Sistema installato"
echo -e "  ${GREEN}✓${RESET} GNOME con GDM"
echo -e "  ${GREEN}✓${RESET} Bootloader: ${CYAN}${BOOTLOADER}${RESET}"
echo -e "  ${GREEN}✓${RESET} Display server: ${CYAN}${DISPLAY_SERVER}${RESET}"
echo -e "  ${GREEN}✓${RESET} Oh My Zsh + Powerlevel10k"
echo -e "  ${GREEN}✓${RESET} Snapper (snapshot pre/post pacman)"
echo -e "  ${GREEN}✓${RESET} ZRAM ${ZRAM_SIZE}MB"
$INSTALL_PLYMOUTH && echo -e "  ${GREEN}✓${RESET} Plymouth arch-charge-big"
echo ""
warn "Ricorda:"
echo -e "  1) Rimuovere l'ISO prima del riavvio"
echo -e "  2) Al primo login terminale: ${CYAN}p10k configure${RESET}"
echo -e "  3) Installa Nerd Fonts: ${CYAN}paru -S ttf-nerd-fonts-symbols${RESET}"
echo ""
read -p "Vuoi riavviare ora? [s/N]: " REBOOT_NOW
[[ "$REBOOT_NOW" =~ ^[sS]$ ]] && umount -R /mnt && reboot || echo -e "\nEsegui ${CYAN}umount -R /mnt && reboot${RESET} quando pronto."
