#!/bin/bash
# ============================================================
# resume-idefix.sh
# Continua l'installazione idefix DOPO che le partizioni
# sono già state create/montate a mano su /mnt.
#
# Prerequisiti prima di lanciare questo script:
#   - $ROOT_PART montato su /mnt con subvolumi @/@home/ecc
#   - $ESP_PART montata su /mnt/boot
# ============================================================
set -e

RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'
CYAN='\e[36m'; BOLD='\e[1m'; RESET='\e[0m'
info()    { echo -e "${GREEN}[INFO]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══ $1 ══${RESET}\n"; }

mountpoint -q /mnt || error "/mnt non è montato. Monta prima root e boot."
mountpoint -q /mnt/boot || error "/mnt/boot (ESP) non è montato."

section "Parametri"
read -p "Hostname [idefix]: " HOSTNAME; HOSTNAME=${HOSTNAME:-idefix}
read -p "Nome utente: " USERNAME
read -s -p "Password utente: " USER_PASSWORD; echo
read -s -p "Password root: " ROOT_PASSWORD; echo
read -p "Disco (es. nvme0n1): " DISK_INPUT; DISK="/dev/${DISK_INPUT}"
read -p "Partizione ESP (es. nvme0n1p1): " ESP_INPUT; ESP_PART="/dev/${ESP_INPUT}"
echo "CPU: 1) AMD 2) Intel"; read -p "Scelta [1/2]: " CPU_CHOICE
[ "$CPU_CHOICE" == "2" ] && UCODE="intel-ucode" || UCODE="amd-ucode"
read -p "Dimensione ZRAM MB [4096]: " ZRAM_SIZE; ZRAM_SIZE=${ZRAM_SIZE:-4096}

DE_PKGS="gnome gnome-extra"
DE_SERVICE="gdm"
GPU_PKGS="nvidia-open nvidia-utils nvidia-settings libva-mesa-driver mesa vulkan-radeon"
LLM_PKGS="cuda"
ROOT_UUID=$(blkid -s UUID -o value $(findmnt -no SOURCE /mnt))

section "Pacchetti (skip se già installati)"
pacstrap -K /mnt \
    base base-devel linux-zen linux-zen-headers linux-firmware \
    ${UCODE} btrfs-progs zsh zsh-completions networkmanager \
    vim git curl wget zram-generator snapper snap-pac sudo openssh \
    pacman-contrib pipewire pipewire-pulse pipewire-alsa wireplumber \
    bluez bluez-utils grub efibootmgr os-prober ntfs-3g \
    ${DE_PKGS} ${GPU_PKGS} ${LLM_PKGS}

section "fstab"
if ! grep -q "^UUID" /mnt/etc/fstab 2>/dev/null; then
    genfstab -U /mnt >> /mnt/etc/fstab
fi
info "fstab pronto."

section "Configurazione sistema (chroot)"
arch-chroot /mnt /bin/bash -e << CHROOT
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc
echo "it_IT.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=it_IT.UTF-8" > /etc/locale.conf
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

systemctl enable NetworkManager sshd bluetooth ${DE_SERVICE}
systemctl disable NetworkManager-wait-online.service
systemctl enable ollama

sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
grep -q "^GRUB_DISABLE_OS_PROBER=false" /etc/default/grub || echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub

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

section "GRUB + os-prober"
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
grep -qi windows /mnt/boot/grub/grub.cfg && info "Windows rilevato nel menu GRUB." || warn "Windows non rilevato - verifica dopo il boot."

section "Utente: Oh My Zsh + greeter"
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
            echo "Alias esiste. Sovrascrivere? [y/N]"
            read answer
            [[ "$answer" == "y" ]] && sed -i "/^alias ${alias_name}=/d" ~/.zsh_aliases || return 1
        fi
        echo "alias ${alias_name}='${alias_value}'" >> ~/.zsh_aliases
        builtin alias "${alias_name}=${alias_value}"
        echo "✓ Salvato"
    fi
}
function lista() {
    sort ~/.zsh_aliases | while IFS= read -r line; do
        local name="${line#alias }"; local cmd="${name#*=\'}"; cmd="${cmd%\'}"; name="${name%%=*}"
        printf "%-20s %s\n" "$name" "$cmd"
    done
}
function paru() {
    command paru "$@"
    [[ "$*" == *"-S"* || "$*" == *"-u"* ]] && sudo needrestart -r l
}
EOF

cat > ~/.greeter.zsh << 'EOF'
#!/usr/bin/env zsh
local reset="\e[0m" bold="\e[1m" cyan="\e[36m" green="\e[32m" yellow="\e[33m" white="\e[97m" gray="\e[90m"
local sep="${gray}$(printf '─%.0s' {1..60})${reset}"
local hostname=$(cat /etc/hostname)
local username=$(whoami)
local gpu_str=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | awk -F',' '{print $1"% GPU, "$2"/"$3" MiB"}')
[ -z "$gpu_str" ] && gpu_str="N/D"
echo ""
echo -e "${sep}"
echo -e "    ${bold}${white}Benvenuto su ${cyan}${hostname}${white}, ${green}${username}${reset}"
echo -e "${sep}"
echo -e "  GPU NVIDIA: ${gpu_str}"
echo -e "${sep}"
echo ""
EOF
chmod +x ~/.greeter.zsh
sed -i '1s/^/source ~\/.greeter.zsh\n/' ~/.zshrc
USERCHROOT

section "paru + pacchetti extra"
arch-chroot /mnt /bin/su - ${USERNAME} -s /bin/bash << 'PARUEOF'
set -e
cd /tmp && git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si --noconfirm
cd && rm -rf /tmp/paru
sudo pacman -S --noconfirm ollama-cuda needrestart bat btop
gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'it')]" 2>/dev/null || true
PARUEOF

section "Fatto!"
echo -e "${GREEN}✓${RESET} Installazione completata."
warn "Rimuovi ISO e riavvia con: umount -R /mnt && reboot"
