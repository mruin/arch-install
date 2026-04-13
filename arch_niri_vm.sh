#!/usr/bin/env bash
# =============================================================================
#  arch_niri_vm.sh
#  Arch Linux – Installazione automatizzata con wizard interattivo
#  Target  : VM UTM su MacBook Air M2 (aarch64)
#  WM/Shell: Niri (Wayland) + Noctalia Shell + Zsh + Oh My Zsh
#  Swap    : zram 4 GB | FS: ext4 | Bootloader: systemd-boot
#
#  Uso:
#    chmod +x arch_niri_vm.sh && ./arch_niri_vm.sh
# =============================================================================

set -eo pipefail

# ── Colori ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
err()    { echo -e "${RED}[✗]${NC} $*"; exit 1; }
info()   { echo -e "${CYAN}[i]${NC} $*"; }
step()   {
    echo ""
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $*${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════${NC}"
}
banner() {
    echo -e "${BLUE}${BOLD}"
    echo "  ╔══════════════════════════════════════════════════╗"
    echo "  ║       arch_niri_vm.sh  —  Installer Wizard      ║"
    echo "  ║   Arch Linux · Niri · Noctalia · Zsh · zram     ║"
    echo "  ╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ── Helper: legge input con default opzionale ─────────────────────────────────
# ask <variabile> <prompt> [default]
ask() {
    local _var=$1
    local _prompt=$2
    local _default=${3:-}
    local _input

    if [[ -n "$_default" ]]; then
        echo -ne "${BOLD}${_prompt}${NC} ${CYAN}[${_default}]${NC}: "
    else
        echo -ne "${BOLD}${_prompt}${NC}: "
    fi

    read -r _input
    # Se vuoto e c'è un default, usa il default
    if [[ -z "$_input" && -n "$_default" ]]; then
        _input="$_default"
    fi
    # Se ancora vuoto, chiede di nuovo
    while [[ -z "$_input" ]]; do
        echo -ne "  ${RED}Campo obbligatorio.${NC} ${BOLD}${_prompt}${NC}: "
        read -r _input
    done
    printf -v "$_var" '%s' "$_input"
}

# ask_password <variabile> <prompt> — input nascosto con conferma
ask_password() {
    local _var=$1
    local _prompt=$2
    local _pw1 _pw2

    while true; do
        echo -ne "${BOLD}${_prompt}${NC}: "
        read -rs _pw1
        echo ""
        echo -ne "${BOLD}Conferma ${_prompt}${NC}: "
        read -rs _pw2
        echo ""
        if [[ "$_pw1" == "$_pw2" ]]; then
            [[ -z "$_pw1" ]] && { warn "La password non può essere vuota."; continue; }
            printf -v "$_var" '%s' "$_pw1"
            break
        else
            warn "Le password non corrispondono, riprova."
        fi
    done
}

# ask_disk — mostra lsblk e chiede di scegliere
ask_disk() {
    echo ""
    info "Dischi disponibili:"
    echo ""
    lsblk -d -o NAME,SIZE,MODEL,TYPE 2>/dev/null || lsblk -d 2>/dev/null || lsblk
    echo ""
    ask DISK "Disco di destinazione (es: /dev/vda, /dev/sda)" "/dev/vda"
    # Aggiunge /dev/ se l'utente ha scritto solo il nome (es: vda)
    if [[ "$DISK" != /dev/* ]]; then
        DISK="/dev/${DISK}"
    fi
    if [[ ! -b "$DISK" ]]; then
        err "Dispositivo $DISK non trovato. Controlla con: lsblk"
    fi
}

# ── Verifica prerequisiti ─────────────────────────────────────────────────────
preflight_checks() {
    step "Verifica prerequisiti"

    [[ $EUID -ne 0 ]]           && err "Esegui questo script come root (es: sudo ./arch_niri_vm.sh)"
    [[ "$(uname -m)" != "aarch64" ]] && err "Questo script è pensato per aarch64 (ARM64). Stai usando l'ISO Arch ARM?"

    log "Verifica connessione internet..."
    ping -c 2 -W 3 archlinux.org &>/dev/null || err "Nessuna connessione internet. Configura la rete e riprova."

    log "Tutti i prerequisiti soddisfatti."
}

# =============================================================================
#  WIZARD INTERATTIVO
# =============================================================================
wizard() {
    banner

    echo -e "${BOLD}Benvenuto! Questo wizard raccoglierà le informazioni necessarie${NC}"
    echo -e "${BOLD}per installare Arch Linux con Niri + Noctalia Shell.${NC}"
    echo ""
    echo -e "  • Lascia ${CYAN}[vuoto]${NC} per accettare il valore suggerito tra parentesi quadre."
    echo -e "  • Le password non verranno mostrate durante la digitazione."
    echo ""
    read -rp "  Premi INVIO per iniziare..."

    # ── Utente ────────────────────────────────────────────────────────────────
    step "1/6  Account utente"

    ask     USERNAME     "Nome utente"       "mirko"
    ask_password ROOT_PASSWORD "Password root"
    ask_password USER_PASSWORD "Password utente ($USERNAME)"

    # ── Hostname ──────────────────────────────────────────────────────────────
    step "2/6  Hostname"

    ask HOSTNAME "Hostname della macchina" "archvm-utm"

    # ── Disco ─────────────────────────────────────────────────────────────────
    step "3/6  Disco di installazione"

    ask_disk

    # ── Localizzazione ────────────────────────────────────────────────────────
    step "4/6  Localizzazione"

    ask TIMEZONE   "Timezone"            "Europe/Rome"
    ask LOCALE     "Locale"              "it_IT.UTF-8"
    ask KEYMAP     "Keymap console"      "it"
    ask XKB_LAYOUT "Layout tastiera (Wayland/X11)" "it"

    # ── Swap zram ─────────────────────────────────────────────────────────────
    step "5/6  Swap zram"

    ask ZRAM_SIZE "Dimensione zram swap in MB" "4096"

    # ── Riepilogo e conferma ──────────────────────────────────────────────────
    step "6/6  Riepilogo configurazione"

    echo ""
    echo -e "  ${BOLD}Utente        :${NC} $USERNAME"
    echo -e "  ${BOLD}Hostname      :${NC} $HOSTNAME"
    echo -e "  ${BOLD}Disco target  :${NC} ${RED}${BOLD}$DISK${NC}  ${RED}← VERRÀ FORMATTATO COMPLETAMENTE${NC}"
    echo -e "  ${BOLD}Timezone      :${NC} $TIMEZONE"
    echo -e "  ${BOLD}Locale        :${NC} $LOCALE"
    echo -e "  ${BOLD}Keymap        :${NC} $KEYMAP  /  XKB: $XKB_LAYOUT"
    echo -e "  ${BOLD}zram swap     :${NC} ${ZRAM_SIZE} MB"
    echo -e "  ${BOLD}Bootloader    :${NC} systemd-boot"
    echo -e "  ${BOLD}Filesystem    :${NC} ext4"
    echo -e "  ${BOLD}WM            :${NC} Niri (Wayland) + Noctalia Shell"
    echo -e "  ${BOLD}Shell         :${NC} Zsh + Oh My Zsh + Powerlevel10k"
    echo ""
    warn "Tutte le partizioni su ${DISK} verranno distrutte."
    echo ""
    echo -ne "  ${BOLD}Sei sicuro di voler procedere? ${RED}(scrivi 'si' per confermare)${NC}: "
    read -r confirm
    [[ "$confirm" != "si" ]] && { echo ""; info "Installazione annullata."; exit 0; }
    echo ""
}

# =============================================================================
#  INSTALLAZIONE
# =============================================================================

install_base() {
    step "Preparazione ambiente live"

    # loadkeys non disponibile in Archboot, si skippa

    log "Aggiornamento clock di sistema..."
    timedatectl set-ntp true 2>/dev/null || true

    log "Aggiornamento keyring pacman..."
    pacman -Sy --noconfirm archlinux-keyring 2>/dev/null || true
}

partition_disk() {
    step "Partizionamento disco: $DISK"

    log "Cancellazione firme esistenti..."
    wipefs -af "$DISK" 2>/dev/null || true
    dd if=/dev/zero of="$DISK" bs=512 count=2048 2>/dev/null || true

    log "Creazione tabella partizioni GPT (EFI 512M + ROOT resto)..."
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart ROOT ext4 513MiB 100%

    sleep 2
    partprobe "$DISK"
    sleep 1

    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"

    log "Formattazione EFI (FAT32)..."
    mkfs.fat -F32 -n ESP "$EFI_PART"

    log "Formattazione ROOT (ext4)..."
    mkfs.ext4 -L ROOT "$ROOT_PART"
}

mount_fs() {
    step "Montaggio filesystem"

    log "Montaggio root su /mnt..."
    mount "$ROOT_PART" /mnt

    log "Montaggio EFI su /mnt/boot..."
    mkdir -p /mnt/boot
    mount "$EFI_PART" /mnt/boot
}

install_packages() {
    step "Installazione sistema base (pacstrap)"

    pacstrap -K /mnt \
        base base-devel \
        linux-aarch64 linux-aarch64-headers linux-firmware \
        efibootmgr \
        networkmanager nm-connection-editor network-manager-applet \
        sudo vim nano git curl wget \
        htop btop \
        man-db man-pages bash-completion \
        zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting \
        openssh rsync zip unzip p7zip which lsof tree
}

generate_fstab() {
    step "Generazione fstab"
    log "Scrittura /etc/fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

write_chroot_script() {
    step "Scrittura script chroot"

    log "Preparazione script di configurazione interno..."

    # Esportiamo tutte le variabili nel here-doc in modo sicuro
    cat > /mnt/root/configure.sh << CHROOT_SCRIPT
#!/usr/bin/env bash
set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "\${GREEN}[+]\${NC} \$*"; }
warn() { echo -e "\${YELLOW}[!]\${NC} \$*"; }
step() {
    echo ""
    echo -e "\${BLUE}\${BOLD}══════════════════════════════════════════════════\${NC}"
    echo -e "\${BLUE}\${BOLD}  \$*\${NC}"
    echo -e "\${BLUE}\${BOLD}══════════════════════════════════════════════════\${NC}"
}

# ── Variabili trasmesse dal wizard ──────────────────────────────────────────
USERNAME="${USERNAME}"
HOSTNAME="${HOSTNAME}"
TIMEZONE="${TIMEZONE}"
LOCALE="${LOCALE}"
KEYMAP="${KEYMAP}"
XKB_LAYOUT="${XKB_LAYOUT}"
ZRAM_SIZE="${ZRAM_SIZE}"
ROOT_PASSWORD="${ROOT_PASSWORD}"
USER_PASSWORD="${USER_PASSWORD}"
ROOT_PART="${ROOT_PART}"

# ===========================================================================
step "chroot 1/10 — Timezone e localizzazione"
# ===========================================================================

log "Impostazione timezone \${TIMEZONE}..."
ln -sf /usr/share/zoneinfo/\${TIMEZONE} /etc/localtime
hwclock --systohc

log "Configurazione locale \${LOCALE}..."
sed -i "s/^#\${LOCALE}/\${LOCALE}/" /etc/locale.gen
grep -q "^en_US.UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

echo "LANG=\${LOCALE}"   > /etc/locale.conf
echo "KEYMAP=\${KEYMAP}" > /etc/vconsole.conf

# ===========================================================================
step "chroot 2/10 — Hostname e /etc/hosts"
# ===========================================================================

echo "\${HOSTNAME}" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   \${HOSTNAME}.localdomain \${HOSTNAME}
EOF

# ===========================================================================
step "chroot 3/10 — Utenti e password"
# ===========================================================================

log "Password root..."
echo "root:\${ROOT_PASSWORD}" | chpasswd

log "Creazione utente \${USERNAME}..."
useradd -m -G wheel,audio,video,storage,optical,input,seat -s /bin/zsh "\${USERNAME}"
echo "\${USERNAME}:\${USER_PASSWORD}" | chpasswd

log "Abilitazione sudo per il gruppo wheel..."
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ===========================================================================
step "chroot 4/10 — Bootloader: systemd-boot"
# ===========================================================================

log "Installazione systemd-boot..."
bootctl install

ROOT_UUID=\$(blkid -s UUID -o value "\${ROOT_PART}")

cat > /boot/loader/loader.conf << EOF
default  arch.conf
timeout  3
console-mode max
editor   no
EOF

cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux-aarch64
initrd  /initramfs-linux-aarch64.img
options root=UUID=\${ROOT_UUID} rw quiet splash loglevel=3
EOF

cat > /boot/loader/entries/arch-fallback.conf << EOF
title   Arch Linux (fallback)
linux   /vmlinuz-linux-aarch64
initrd  /initramfs-linux-aarch64-fallback.img
options root=UUID=\${ROOT_UUID} rw
EOF

log "Generazione initramfs..."
mkinitcpio -P

# ===========================================================================
step "chroot 5/10 — Servizi essenziali"
# ===========================================================================

systemctl enable NetworkManager
systemctl enable sshd
systemctl enable systemd-timesyncd
systemctl enable bluetooth 2>/dev/null || true

# ===========================================================================
step "chroot 6/10 — zram swap (\${ZRAM_SIZE} MB)"
# ===========================================================================

pacman -S --noconfirm zram-generator

cat > /etc/systemd/zram-generator.conf << EOF
[zram0]
zram-size = \${ZRAM_SIZE}
compression-algorithm = zstd
swap-priority = 100
EOF

systemctl enable systemd-zram-setup@zram0.service

# ===========================================================================
step "chroot 7/10 — Wayland, Niri e dipendenze"
# ===========================================================================

pacman -S --noconfirm \
    wayland wayland-protocols xwayland \
    mesa vulkan-virtio libva-mesa-driver mesa-utils \
    libdrm libxkbcommon libinput pixman pango cairo gdk-pixbuf2 \
    dbus polkit polkit-gnome \
    xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr \
    xdg-user-dirs xdg-utils \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber gst-plugin-pipewire \
    qt5-wayland qt6-wayland \
    seatd libseat \
    rust cargo cmake meson ninja pkg-config clang \
    libxcb xcb-util-wm xcb-util-keysyms

systemctl enable seatd

# Applicazioni UI
pacman -S --noconfirm \
    foot \
    firefox \
    thunar thunar-archive-plugin thunar-volman \
    gvfs gvfs-mtp tumbler ffmpegthumbnailer file-roller \
    waybar wofi mako \
    swaylock swayidle wlogout \
    grim slurp wl-clipboard \
    brightnessctl playerctl \
    pavucontrol \
    blueman bluez bluez-utils \
    noto-fonts noto-fonts-emoji noto-fonts-extra \
    ttf-jetbrains-mono ttf-jetbrains-mono-nerd ttf-font-awesome \
    papirus-icon-theme gnome-themes-extra adwaita-icon-theme

# ===========================================================================
step "chroot 8/10 — paru (AUR helper)"
# ===========================================================================

log "Build e installazione paru-bin..."
cd /tmp
git clone https://aur.archlinux.org/paru-bin.git
chown -R "\${USERNAME}:\${USERNAME}" paru-bin
cd paru-bin
sudo -u "\${USERNAME}" makepkg -si --noconfirm
cd /
rm -rf /tmp/paru-bin

log "Installazione niri da AUR..."
sudo -u "\${USERNAME}" paru -S --noconfirm niri || \
    warn "niri non installato — esegui 'paru -S niri' dopo il riavvio"

log "Installazione Noctalia Shell da AUR..."
sudo -u "\${USERNAME}" paru -S --noconfirm noctalia || \
    warn "noctalia non trovato — prova 'paru -Ss noctalia' dopo il riavvio"

# ===========================================================================
step "chroot 9/10 — Zsh + Oh My Zsh + Powerlevel10k"
# ===========================================================================

log "Installazione Oh My Zsh per \${USERNAME}..."
sudo -u "\${USERNAME}" sh -c \
    "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended

ZSH_CUSTOM="/home/\${USERNAME}/.oh-my-zsh/custom"

sudo -u "\${USERNAME}" git clone --quiet \
    https://github.com/zsh-users/zsh-autosuggestions \
    "\${ZSH_CUSTOM}/plugins/zsh-autosuggestions"

sudo -u "\${USERNAME}" git clone --quiet \
    https://github.com/zsh-users/zsh-syntax-highlighting \
    "\${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"

sudo -u "\${USERNAME}" git clone --quiet --depth=1 \
    https://github.com/romkatv/powerlevel10k.git \
    "\${ZSH_CUSTOM}/themes/powerlevel10k"

cat > /home/\${USERNAME}/.zshrc << 'ZSHRC'
# Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    sudo
    archlinux
    colored-man-pages
    command-not-found
    extract
)

source \$ZSH/oh-my-zsh.sh

# ── Alias ──────────────────────────────────────────────────────────────────
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias df='df -h'
alias free='free -h'
alias update='sudo pacman -Syu'
alias aur='paru -Syu'
alias cls='clear'

# ── Wayland env ────────────────────────────────────────────────────────────
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export SDL_VIDEODRIVER=wayland
export _JAVA_AWT_WM_NONREPARENTING=1
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=niri

# ── Avvio automatico Niri su tty1 ─────────────────────────────────────────
if [ -z "\${WAYLAND_DISPLAY:-}" ] && [ "\${XDG_VTNR:-0}" -eq 1 ]; then
    exec niri-session
fi

# Powerlevel10k
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
ZSHRC

chown "\${USERNAME}:\${USERNAME}" /home/\${USERNAME}/.zshrc

# ===========================================================================
step "chroot 10/10 — Config Niri e Waybar"
# ===========================================================================

sudo -u "\${USERNAME}" mkdir -p /home/\${USERNAME}/.config/niri

cat > /home/\${USERNAME}/.config/niri/config.kdl << NIRI_CONF
// Niri config — arch_niri_vm.sh
// Docs: https://github.com/YaLTeR/niri/wiki/Configuration

input {
    keyboard {
        xkb { layout "\${XKB_LAYOUT}"; }
    }
    touchpad {
        tap
        natural-scroll
    }
}

layout {
    gaps 8
    preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
    }
    default-column-width { proportion 0.5; }
    focus-ring {
        width 2
        active-color "#7fc8ff"
        inactive-color "#505050"
    }
    border { off; }
}

animations { slowdown 1.0; }

spawn-at-startup "waybar"
spawn-at-startup "mako"
spawn-at-startup "nm-applet" "--indicator"

binds {
    Mod+Return          { spawn "foot"; }
    Mod+Space           { spawn "wofi" "--show=drun"; }
    Mod+E               { spawn "thunar"; }
    Mod+B               { spawn "firefox"; }
    Print               { spawn "sh" "-c" "grim ~/Pictures/screenshot-\$(date +%Y%m%d-%H%M%S).png"; }
    Mod+Print           { spawn "sh" "-c" "grim -g \"\$(slurp)\" ~/Pictures/screenshot-\$(date +%Y%m%d-%H%M%S).png"; }

    XF86AudioRaiseVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1+"; }
    XF86AudioLowerVolume allow-when-locked=true { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.1-"; }
    XF86AudioMute        allow-when-locked=true { spawn "wpctl" "set-mute"   "@DEFAULT_AUDIO_SINK@" "toggle"; }
    XF86MonBrightnessUp                         { spawn "brightnessctl" "set" "10%+"; }
    XF86MonBrightnessDown                       { spawn "brightnessctl" "set" "10%-"; }

    Mod+Q               { close-window; }
    Mod+F               { maximize-column; }
    Mod+Shift+F         { fullscreen-window; }

    Mod+Left            { focus-column-left; }
    Mod+Right           { focus-column-right; }
    Mod+Up              { focus-window-up; }
    Mod+Down            { focus-window-down; }
    Mod+H               { focus-column-left; }
    Mod+L               { focus-column-right; }
    Mod+K               { focus-window-up; }
    Mod+J               { focus-window-down; }

    Mod+Shift+Left      { move-column-left; }
    Mod+Shift+Right     { move-column-right; }
    Mod+Shift+Up        { move-window-up; }
    Mod+Shift+Down      { move-window-down; }
    Mod+Shift+H         { move-column-left; }
    Mod+Shift+L         { move-column-right; }
    Mod+Shift+K         { move-window-up; }
    Mod+Shift+J         { move-window-down; }

    Mod+1               { focus-workspace 1; }
    Mod+2               { focus-workspace 2; }
    Mod+3               { focus-workspace 3; }
    Mod+4               { focus-workspace 4; }
    Mod+5               { focus-workspace 5; }
    Mod+Shift+1         { move-window-to-workspace 1; }
    Mod+Shift+2         { move-window-to-workspace 2; }
    Mod+Shift+3         { move-window-to-workspace 3; }
    Mod+Shift+4         { move-window-to-workspace 4; }
    Mod+Shift+5         { move-window-to-workspace 5; }

    Mod+R               { switch-preset-column-width; }
    Mod+Minus           { set-column-width "-10%"; }
    Mod+Equal           { set-column-width "+10%"; }

    Mod+Shift+Delete    { spawn "swaylock" "-f" "-c" "000000"; }
    Mod+Shift+E         { spawn "wlogout"; }
    Mod+Shift+R         { reload-config; }
}

window-rule {
    match app-id=r#"foot"#
    default-column-width { proportion 0.5; }
}
window-rule {
    match app-id=r#"firefox"#
    default-column-width { proportion 1.0; }
}
NIRI_CONF

# Waybar
sudo -u "\${USERNAME}" mkdir -p /home/\${USERNAME}/.config/waybar

cat > /home/\${USERNAME}/.config/waybar/config.jsonc << 'WAYBAR_CONF'
{
    "layer": "top",
    "position": "top",
    "height": 30,
    "spacing": 4,
    "modules-left":   ["niri/workspaces", "niri/window"],
    "modules-center": ["clock"],
    "modules-right":  ["pulseaudio", "network", "memory", "cpu", "tray"],

    "niri/workspaces": {
        "format": "{icon}",
        "format-icons": { "active": "●", "default": "○" }
    },
    "niri/window": { "max-length": 50 },
    "clock": {
        "format": "{:%H:%M  %d/%m/%Y}",
        "tooltip-format": "<big>{:%A %d %B %Y}</big>"
    },
    "cpu":     { "format": " {usage}%", "interval": 2 },
    "memory":  { "format": " {}%",      "interval": 5 },
    "network": {
        "format-wifi":       " {essid}",
        "format-ethernet":   " {ipaddr}",
        "format-disconnected": "睊",
        "tooltip-format":    "{ifname}: {ipaddr}"
    },
    "pulseaudio": {
        "format":       "{icon} {volume}%",
        "format-muted": "婢",
        "format-icons": { "default": ["奄", "奔", "墳"] },
        "on-click":     "pavucontrol"
    },
    "tray": { "spacing": 8 }
}
WAYBAR_CONF

cat > /home/\${USERNAME}/.config/waybar/style.css << 'WAYBAR_CSS'
* {
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-size: 13px;
}
window#waybar {
    background-color: rgba(26, 27, 38, 0.95);
    color: #c0caf5;
    border-bottom: 2px solid #7fc8ff;
}
#workspaces button            { padding: 0 8px; color: #565f89; }
#workspaces button.active     { color: #7fc8ff; }
#clock, #cpu, #memory,
#network, #pulseaudio, #tray  { padding: 0 10px; }
WAYBAR_CSS

# Directory XDG
sudo -u "\${USERNAME}" xdg-user-dirs-update
sudo -u "\${USERNAME}" mkdir -p \
    /home/\${USERNAME}/Pictures \
    /home/\${USERNAME}/Downloads \
    /home/\${USERNAME}/Documents \
    /home/\${USERNAME}/.local/share/applications

chown -R "\${USERNAME}:\${USERNAME}" \
    /home/\${USERNAME}/.config \
    /home/\${USERNAME}/.oh-my-zsh 2>/dev/null || true

log "Script chroot completato."
CHROOT_SCRIPT

    chmod +x /mnt/root/configure.sh
}

finalize() {
    step "Smontaggio e riavvio"

    log "Smontaggio filesystem..."
    umount -R /mnt

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║      Installazione completata con successo!          ║${NC}"
    echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}${BOLD}║  Rimuovi l'ISO dalla VM UTM prima di riavviare.     ║${NC}"
    echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}${BOLD}║  Al primo login su tty1 Niri si avvia in auto.      ║${NC}"
    echo -e "${GREEN}${BOLD}║  Esegui:  p10k configure   per personalizzare Zsh   ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -rp "  Premi INVIO per riavviare la macchina..."
    reboot
}

# =============================================================================
#  MAIN
# =============================================================================
main() {
    preflight_checks
    wizard
    install_base
    partition_disk
    mount_fs
    install_packages
    generate_fstab
    write_chroot_script

    step "Esecuzione configurazione in chroot"
    arch-chroot /mnt /root/configure.sh
    rm -f /mnt/root/configure.sh

    finalize
}

main "$@"
