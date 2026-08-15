#!/bin/bash
# ============================================================
# install-arch-idefix.sh
# Installazione Arch Linux su disco con Windows 11 esistente
# (elimina la partizione Ubuntu esistente, riusa la ESP condivisa)
#
# Target: ASUS Zenbook UX535QE - Ryzen 9 5900HX, RTX 3050 Ti + AMD iGPU
# Predispone l'ambiente per LLM locali: nvidia-open, CUDA, Ollama
#
# Bootloader: GRUB + os-prober (rileva Windows Boot Manager esistente)
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

[ -d /sys/firmware/efi/efivars ] || error "Non sei in modalità UEFI."

# ============================================================
# PARAMETRI GENERALI
# ============================================================
section "Configurazione - idefix (dual boot Windows)"

read -p "Hostname [idefix]: " HOSTNAME; HOSTNAME=${HOSTNAME:-idefix}

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
read -p "Disco (es. nvme0n1): " DISK_INPUT
DISK="/dev/${DISK_INPUT}"
while [ ! -b "$DISK" ]; do
    warn "Disco $DISK non trovato."
    read -p "Disco: " DISK_INPUT; DISK="/dev/${DISK_INPUT}"
done

PART_PREFIX="$DISK"
[[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]] && PART_PREFIX="${DISK}p"

# ============================================================
# ANALISI PARTIZIONI ESISTENTI
# ============================================================
section "Analisi partizioni esistenti su ${DISK}"

echo -e "${BOLD}Tabella partizioni completa:${RESET}\n"
lsblk -f "$DISK"
echo ""
echo -e "${BOLD}Dettaglio parted (flag, tipo):${RESET}\n"
parted -s "$DISK" print
echo ""

# Individua la ESP esistente (flag "esp")
ESP_GUESS=$(parted -sm "$DISK" print 2>/dev/null | awk -F: '$0 ~ /esp/ {print $1}' | head -1)
if [ -n "$ESP_GUESS" ]; then
    ESP_GUESS="${PART_PREFIX}${ESP_GUESS}"
    info "ESP (EFI System Partition) rilevata: ${CYAN}${ESP_GUESS}${RESET}"
else
    warn "Nessuna ESP rilevata automaticamente."
fi

# Individua possibili partizioni Linux (ext4/btrfs) - candidate Ubuntu
info "Partizioni Linux (ext4/btrfs) rilevate (possibile Ubuntu):"
lsblk -rno NAME,FSTYPE "$DISK" | awk -v pfx="$PART_PREFIX" '$2=="ext4" || $2=="btrfs" {print "  /dev/"$1" ("$2")"}'
echo ""

warn "NON verrà mai toccata alcuna partizione con filesystem ntfs (Windows)."

# ============================================================
# MODALITÀ DI PARTIZIONAMENTO
# ============================================================
section "Modalità di partizionamento"
echo "  1) Automatica guidata (confermi tu quale partizione eliminare)"
echo "  2) Manuale con cfdisk"
read -p "Scelta [1/2]: " PART_MODE

if [ "$PART_MODE" == "2" ]; then
    # ---------- MODALITÀ MANUALE ----------
    info "Apro cfdisk su ${DISK}. Elimina la/le partizioni Ubuntu e crea"
    info "una nuova partizione Linux (tipo 8300) nello spazio liberato."
    info "NON toccare la partizione Windows (ntfs) né la ESP (fat32, flag boot/esp)."
    read -p "Premi Invio per aprire cfdisk..."
    cfdisk "$DISK"

    echo ""
    lsblk -f "$DISK"
    echo ""
    read -p "Nome dispositivo della ESP esistente (es. nvme0n1p1): " ESP_INPUT
    ESP_PART="/dev/${ESP_INPUT}"
    read -p "Nome dispositivo della NUOVA partizione root Arch (es. nvme0n1p5): " ROOT_INPUT
    ROOT_PART="/dev/${ROOT_INPUT}"

else
    # ---------- MODALITÀ AUTOMATICA ----------
    [ -n "$ESP_GUESS" ] || error "Impossibile procedere in automatico senza una ESP rilevata. Usa la modalità manuale."

    read -p "Confermi che la ESP è ${ESP_GUESS}? [S/n]: " ESP_CONFIRM
    if [[ "$ESP_CONFIRM" =~ ^[nN]$ ]]; then
        read -p "Nome dispositivo della ESP corretta (es. nvme0n1p1): " ESP_INPUT
        ESP_PART="/dev/${ESP_INPUT}"
    else
        ESP_PART="$ESP_GUESS"
    fi

    echo ""
    read -p "Nome dispositivo della partizione Ubuntu da ELIMINARE (es. nvme0n1p5): " UBUNTU_INPUT
    UBUNTU_PART="/dev/${UBUNTU_INPUT}"

    UBUNTU_FSTYPE=$(lsblk -no FSTYPE "$UBUNTU_PART" 2>/dev/null || echo "")
    [ "$UBUNTU_FSTYPE" == "ntfs" ] && error "STOP: ${UBUNTU_PART} è ntfs (Windows). Operazione annullata per sicurezza."
    [ -z "$UBUNTU_FSTYPE" ] && error "Impossibile leggere il filesystem di ${UBUNTU_PART}. Operazione annullata."

    echo ""
    warn "Stai per ELIMINARE ${UBUNTU_PART} (filesystem: ${UBUNTU_FSTYPE}) e ricrearla per Arch."
    read -p "Confermi in modo esplicito digitando ELIMINA: " CONFIRM_DELETE
    [ "$CONFIRM_DELETE" == "ELIMINA" ] || error "Conferma non ricevuta. Operazione annullata."

    UBUNTU_NUM=$(echo "$UBUNTU_INPUT" | grep -oE '[0-9]+$')
    info "Elimino la partizione numero ${UBUNTU_NUM} e ricreo come Linux filesystem..."
    parted -s "$DISK" rm "$UBUNTU_NUM"
    parted -s "$DISK" mkpart primary btrfs 0% 100%
    warn "Se lo spazio libero non corrisponde esattamente alla vecchia partizione Ubuntu,"
    warn "interrompi ora (Ctrl+C) e ripeti in modalità manuale con cfdisk per un controllo preciso."
    sleep 3
    partprobe "$DISK"; sleep 2

    ROOT_PART="${PART_PREFIX}$(parted -sm "$DISK" print | tail -1 | cut -d: -f1)"
fi

info "ESP che verrà usata:  ${CYAN}${ESP_PART}${RESET} (non verrà formattata)"
info "Root Arch (nuova):    ${CYAN}${ROOT_PART}${RESET} (verrà formattata btrfs)"
echo ""
warn "ULTIMA CONFERMA: ${ROOT_PART} verrà formattata. ${ESP_PART} verrà solo montata."
read -p "Procedere? [s/N]: " FINAL_CONFIRM
[[ "$FINAL_CONFIRM" =~ ^[sS]$ ]] || error "Annullato."

# ============================================================
# CPU / GPU / ALTRE OPZIONI
# ============================================================
section "Opzioni hardware"

echo "CPU:"; echo "  1) AMD"; echo "  2) Intel"
read -p "Scelta [1/2]: " CPU_CHOICE
[ "$CPU_CHOICE" == "2" ] && UCODE="intel-ucode" || UCODE="amd-ucode"

echo ""
echo "Display server:"; echo "  1) Wayland"; echo "  2) X11"
read -p "Scelta [1/2]: " DS_CHOICE
[ "$DS_CHOICE" == "2" ] && DISPLAY_SERVER="x11" || DISPLAY_SERVER="wayland"
[ "$DISPLAY_SERVER" == "x11" ] && XORG_PKGS="xorg-server xorg-xinit" || XORG_PKGS=""

echo ""
echo "Desktop Environment:"
echo "  0) Nessuno (CLI)"; echo "  1) GNOME"; echo "  2) KDE Plasma"
echo "  3) Cinnamon"; echo "  4) XFCE"
read -p "Scelta [0-4]: " DE_CHOICE
case "$DE_CHOICE" in
    1) DE_NAME="GNOME";     DE_PKGS="gnome gnome-extra";                              DE_SERVICE="gdm" ;;
    2) DE_NAME="KDE Plasma";DE_PKGS="plasma-meta kde-applications-meta sddm";          DE_SERVICE="sddm" ;;
    3) DE_NAME="Cinnamon";  DE_PKGS="cinnamon cinnamon-sounds cinnamon-wallpapers gnome-terminal lightdm lightdm-gtk-greeter nemo-fileroller"; DE_SERVICE="lightdm"; XORG_PKGS="xorg-server xorg-xinit"; DISPLAY_SERVER="x11" ;;
    4) DE_NAME="XFCE";      DE_PKGS="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"; DE_SERVICE="lightdm"; XORG_PKGS="xorg-server xorg-xinit"; DISPLAY_SERVER="x11" ;;
    *) DE_NAME=""; DE_PKGS=""; DE_SERVICE="" ;;
esac

echo ""
read -p "VirtualBox Guest Additions? [s/N]: " VBOX_CHOICE
[[ "$VBOX_CHOICE" =~ ^[sS]$ ]] && VBOX_PKG="virtualbox-guest-utils" || VBOX_PKG=""

read -p "Dimensione ZRAM in MB [4096]: " ZRAM_SIZE; ZRAM_SIZE=${ZRAM_SIZE:-4096}

echo ""
read -p "Installare Plymouth (logo Arch al boot)? [S/n]: " PLYMOUTH_CHOICE
[[ "$PLYMOUTH_CHOICE" =~ ^[nN]$ ]] && INSTALL_PLYMOUTH=false || INSTALL_PLYMOUTH=true

# ============================================================
# LLM LOCALI - NVIDIA / CUDA / OLLAMA
# ============================================================
section "Ambiente LLM locali (GPU ibrida NVIDIA/AMD)"

info "GPU rilevata: NVIDIA RTX 3050 Ti + AMD Radeon integrata (Optimus)."
info "Driver: nvidia-open (Ampere è pienamente supportata)."
info "Per il compute CUDA non serve configurare PRIME render offload:"
info "la GPU NVIDIA resta disponibile per CUDA/Ollama indipendentemente"
info "da quale scheda gestisce il display."

GPU_PKGS="nvidia-open nvidia-utils nvidia-settings libva-mesa-driver mesa vulkan-radeon"
LLM_PKGS="cuda"

# ============================================================
# RIEPILOGO
# ============================================================
section "Riepilogo"
echo -e "  Hostname:       ${CYAN}${HOSTNAME}${RESET}"
echo -e "  Utente:         ${CYAN}${USERNAME}${RESET}"
echo -e "  ESP (riusata):  ${CYAN}${ESP_PART}${RESET}"
echo -e "  Root Arch:      ${CYAN}${ROOT_PART}${RESET}"
echo -e "  CPU/Microcode:  ${CYAN}${UCODE}${RESET}"
echo -e "  Display server: ${CYAN}${DISPLAY_SERVER}${RESET}"
[ -n "$DE_NAME" ] && echo -e "  DE:             ${CYAN}${DE_NAME}${RESET}" || echo -e "  DE:             ${CYAN}Nessuno (CLI)${RESET}"
echo -e "  GPU:            ${CYAN}nvidia-open + CUDA + Ollama${RESET}"
echo -e "  Bootloader:     ${CYAN}GRUB + os-prober (rileva Windows)${RESET}"
echo -e "  ZRAM:           ${CYAN}${ZRAM_SIZE}MB${RESET}"
$INSTALL_PLYMOUTH && echo -e "  Plymouth:       ${CYAN}Sì${RESET}" || echo -e "  Plymouth:       ${CYAN}No${RESET}"
echo ""
warn "Windows NON verrà toccato. Solo ${ROOT_PART} verrà formattata."
read -p "Procedere con l'installazione? [s/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[sS]$ ]] || error "Annullato."

# ============================================================
# FORMATTAZIONE E SUBVOLUMI
# ============================================================
section "Formattazione e subvolumi BTRFS"
timedatectl set-ntp true

mkfs.btrfs -L "archroot" -f "$ROOT_PART"

mount "$ROOT_PART" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
umount /mnt

BTRFS_OPTS="noatime,compress=zstd,space_cache=v2"
mount -o "${BTRFS_OPTS},subvol=@"          "$ROOT_PART" /mnt
mkdir -p /mnt/{boot,home,.snapshots,var/log,var/cache}
mount -o "${BTRFS_OPTS},subvol=@home"      "$ROOT_PART" /mnt/home
mount -o "${BTRFS_OPTS},subvol=@snapshots" "$ROOT_PART" /mnt/.snapshots
mount -o "${BTRFS_OPTS},subvol=@log"       "$ROOT_PART" /mnt/var/log
mount -o "${BTRFS_OPTS},subvol=@cache"     "$ROOT_PART" /mnt/var/cache

# ESP esistente: SOLO mount, mai formattata
mount "$ESP_PART" /mnt/boot
info "ESP montata senza formattazione (Windows Boot Manager preservato)."

# ============================================================
# PACCHETTI
# ============================================================
section "Installazione pacchetti"

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
    grub efibootmgr os-prober ntfs-3g \
    ${DE_PKGS} \
    ${XORG_PKGS} \
    ${GPU_PKGS} \
    ${LLM_PKGS} \
    ${VBOX_PKG}

# ============================================================
# FSTAB
# ============================================================
section "fstab"
genfstab -U /mnt >> /mnt/etc/fstab
info "fstab generato (ESP esistente, nessun fix necessario)."

# ============================================================
# CHROOT - CONFIGURAZIONE SISTEMA
# ============================================================
section "Configurazione sistema"

arch-chroot /mnt /bin/bash -e << CHROOT
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc

echo "it_IT.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=it_IT.UTF-8" > /etc/locale.conf

# FIX: vconsole prima di mkinitcpio
echo "KEYMAP=it" > /etc/vconsole.conf

echo "${HOSTNAME}" > /etc/hostname

sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
mkinitcpio -P

cat > /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = ${ZRAM_SIZE}
compression-algorithm = zstd
swap-priority = 100
EOF

echo "root:${ROOT_PASSWORD}" | chpasswd
useradd -m -G wheel -s /bin/zsh ${USERNAME}
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable NetworkManager
systemctl enable sshd
systemctl enable bluetooth
systemctl disable NetworkManager-wait-online.service
$([ -n "${DE_SERVICE}" ] && echo "systemctl enable ${DE_SERVICE}")
$([ -n "${VBOX_PKG}" ] && echo "systemctl enable vboxservice")

# Ollama - servizio systemd sempre attivo
systemctl enable ollama

# GRUB con os-prober per rilevare Windows Boot Manager
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
if ! grep -q "^GRUB_DISABLE_OS_PROBER=false" /etc/default/grub; then
    echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
fi

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
# GRUB - installazione (fuori chroot per evitare problemi di quoting)
# ============================================================
section "Installazione GRUB con os-prober"

arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
info "GRUB installato. Verifica che Windows Boot Manager compaia nel grub.cfg:"
grep -i "windows" /mnt/boot/grub/grub.cfg && info "Windows rilevato correttamente." || warn "Windows non rilevato nel grub.cfg - verifica manualmente dopo il boot con 'sudo grub-mkconfig -o /boot/grub/grub.cfg'"

# ============================================================
# CHROOT - CONFIGURAZIONE UTENTE (Oh My Zsh + Greeter)
# ============================================================
section "Configurazione utente"

arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << 'USERCHROOT'
set -e
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone --depth=1 https://github.com/romkatv/powerlevel10k ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k

sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' ~/.zshrc
sed -i 's/plugins=(git)/plugins=(git sudo archlinux zsh-autosuggestions zsh-syntax-highlighting history-substring-search colored-man-pages)/' ~/.zshrc

cat > ~/.zsh_aliases << 'EOF'
alias aggiorna='paru -Syu'
alias cat='bat'
alias htop='btop'
alias llm='ollama run'
alias llmlist='ollama list'
alias gpu='nvidia-smi'
EOF

cat >> ~/.zshrc << 'EOF'

[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases

function salias() {
    if [[ "$1" == *"="* ]]; then
        local alias_name="${1%%=*}"
        local alias_value="${1#*=}"
        if grep -q "^alias ${alias_name}=" ~/.zsh_aliases; then
            echo "Alias '${alias_name}' esiste già. Sovrascrivere? [y/N]"
            read answer
            [[ "$answer" == "y" || "$answer" == "Y" ]] && sed -i "/^alias ${alias_name}=/d" ~/.zsh_aliases || return 1
        fi
        echo "alias ${alias_name}='${alias_value}'" >> ~/.zsh_aliases
        builtin alias "${alias_name}=${alias_value}"
        echo "✓ Alias salvato: ${alias_name}='${alias_value}'"
    else
        echo "Uso: salias nome='comando'"
    fi
}

function lista() {
    echo ""
    printf "%-20s %s\n" "ALIAS" "COMANDO"
    printf "%-20s %s\n" "────────────────────" "──────────────────────────────────────"
    sort ~/.zsh_aliases | while IFS= read -r line; do
        local name="${line#alias }"
        local cmd="${name#*=\'}"
        cmd="${cmd%\'}"
        name="${name%%=*}"
        printf "%-20s %s\n" "$name" "$cmd"
    done
    echo ""
}

function paru() {
    command paru "$@"
    if [[ "$*" == *"-S"* || "$*" == *"-U"* || "$*" == *"-u"* ]]; then
        echo "\n🔍 Controllo riavvio..."
        sudo needrestart -r l
    fi
}
EOF

cat > ~/.greeter.zsh << 'EOF'
#!/usr/bin/env zsh
local reset="\e[0m" bold="\e[1m" cyan="\e[36m" green="\e[32m"
local yellow="\e[33m" white="\e[97m" gray="\e[90m"
local sep="${gray}$(printf '─%.0s' {1..60})${reset}"
local hostname=$(cat /etc/hostname)
local username=$(whoami)
local datetime=$(date "+%A %d %B %Y, %H:%M")
local uptime_raw=$(uptime -p | sed 's/up //')
local ram_used=$(free -h | awk '/^Mem:/ {print $3}')
local ram_total=$(free -h | awk '/^Mem:/ {print $2}')
local ip_local=$(ip -4 addr show scope global | awk '/inet/ {print $2}' | cut -d'/' -f1 | paste -sd ',' -)
local ip_ext=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "N/D")
local disk_size=$(df -h / | awk 'NR==2 {print $2}')
local disk_used=$(df -h / | awk 'NR==2 {print $3}')
local disk_pct=$(df -h / | awk 'NR==2 {print $5}')
local snapshots=$(sudo btrfs subvolume list / 2>/dev/null | grep -c "snapshot" || echo "N/D")
local updates=$(checkupdates 2>/dev/null | wc -l)
local aur_updates=$(paru -Qua 2>/dev/null | wc -l)
local total_updates=$((updates + aur_updates))
local updates_str; [[ $total_updates -eq 0 ]] && updates_str="Sistema aggiornato" || updates_str="${total_updates} pacchetti pronti"
local reboot_str
needrestart -k 2>&1 | grep -q "Running kernel seems to be up-to-date" && reboot_str="Nessun riavvio richiesto" || reboot_str="${yellow}Riavvio consigliato${reset}"
local gpu_str=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | awk -F',' '{print $1"% GPU, "$2"/"$3" MiB VRAM"}')
[ -z "$gpu_str" ] && gpu_str="N/D"
echo ""
echo -e "${sep}"
echo -e "    ${bold}${white}Benvenuto su ${cyan}${hostname}${white}, ${green}${username}${reset}"
echo -e "    ${gray}${datetime}${reset}"
echo -e "${sep}"
echo -e "${bold}${white}Stato Sistema:${reset}"
echo -e "  󱄢  ${white}Uptime:     ${reset} ${uptime_raw}"
echo -e "  󰍛  ${white}RAM:        ${reset} ${ram_used}/${ram_total}"
echo -e "  󰖟  ${white}IP Locale:  ${reset} ${ip_local}"
echo -e "  󰩠  ${white}IP Esterno: ${reset} ${ip_ext}"
echo -e "  󰢮  ${white}GPU NVIDIA: ${reset} ${gpu_str}"
echo -e "${bold}${white}Archiviazione BTRFS:${reset}"
echo -e "  󱗆  ${white}Root (/):   ${reset} ${disk_used}/${disk_size} (${disk_pct})"
echo -e "  󱘊  ${white}Snapshots:  ${reset} ${snapshots} attivi"
echo -e "  󰚰  ${white}Updates:    ${reset} ${updates_str}"
echo -e "  󰜉  ${white}Riavvio:    ${reset} ${reboot_str}"
echo -e "${sep}"
echo ""
EOF

chmod +x ~/.greeter.zsh
sed -i '1s/^/source ~\/.greeter.zsh\n/' ~/.zshrc
USERCHROOT

# ============================================================
# PARU + PACCHETTI AGGIUNTIVI
# ============================================================
section "Installazione paru"

arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << 'PARUINSTALL'
set -e
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm
cd && rm -rf /tmp/paru
PARUINSTALL

section "Pacchetti aggiuntivi (needrestart, bat, btop, ollama-cuda)"

arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << 'POSTINSTALL'
set -e
sudo pacman -S --noconfirm ollama-cuda needrestart bat btop
POSTINSTALL

# Tastiera italiana se GNOME
if [ "$DE_SERVICE" == "gdm" ]; then
    arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << 'GNOMECONF'
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'it')]" 2>/dev/null || true
GNOMECONF
fi

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
    arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet splash"/' /etc/default/grub
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    info "Plymouth configurato."
fi

# ============================================================
# FINE
# ============================================================
section "Installazione completata!"
echo -e "  ${GREEN}✓${RESET} Sistema installato (Windows preservato)"
[ -n "$DE_NAME" ] && echo -e "  ${GREEN}✓${RESET} ${DE_NAME}"
echo -e "  ${GREEN}✓${RESET} GRUB + os-prober (dual boot Windows)"
echo -e "  ${GREEN}✓${RESET} nvidia-open + CUDA + ollama-cuda (servizio attivo)"
echo -e "  ${GREEN}✓${RESET} Oh My Zsh + Powerlevel10k + greeter (con stato GPU)"
echo -e "  ${GREEN}✓${RESET} Snapper + ZRAM ${ZRAM_SIZE}MB"
echo ""
warn "Rimuovi l'ISO prima del riavvio."
warn "Al primo login: paru -S ttf-nerd-fonts-symbols && p10k configure"
warn "Testa la GPU con: nvidia-smi   |   testa Ollama con: ollama run llama3"
echo ""
read -p "Riavviare ora? [s/N]: " REBOOT_NOW
[[ "$REBOOT_NOW" =~ ^[sS]$ ]] && umount -R /mnt && reboot || echo -e "\nEsegui: ${CYAN}umount -R /mnt && reboot${RESET}"
