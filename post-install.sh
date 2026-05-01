#!/bin/bash
# ============================================================
# post-install.sh
# Da eseguire al primo boot dopo install-arch-gnome-no-zsh-config.sh
# ============================================================

set -e

RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'
CYAN='\e[36m'; BOLD='\e[1m'; RESET='\e[0m'

info()    { echo -e "${GREEN}[INFO]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
section() {
    echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}  $1${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}\n"
}

# ============================================================
# PULIZIA PARU-BIN
# ============================================================
section "Pulizia paru-bin"

for pkg in paru-bin-debug paru-bin; do
    if pacman -Q "$pkg" &>/dev/null; then
        info "Rimozione $pkg..."
        sudo pacman -R --noconfirm "$pkg"
    fi
done

rm -rf /tmp/paru
info "Pulizia completata."

# ============================================================
# INSTALLAZIONE PARU
# ============================================================
section "Installazione paru"

cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm
cd && rm -rf /tmp/paru
info "paru installato."

# ============================================================
# LIMINE-SNAPPER-SYNC
# ============================================================
section "Limine-Snapper-Sync"

BOOTLOADER=$([ -d /boot/EFI/limine ] && echo "limine" || echo "altro")

if [ "$BOOTLOADER" = "limine" ]; then
    paru -S --noconfirm limine-snapper-sync
    info "limine-snapper-sync installato."
else
    warn "Limine non rilevato, limine-snapper-sync saltato."
fi

# ============================================================
# FINE
# ============================================================
section "Post-installazione completata!"
echo -e "  ${GREEN}✓${RESET} paru installato"
[ "$BOOTLOADER" = "limine" ] && echo -e "  ${GREEN}✓${RESET} limine-snapper-sync installato"
echo ""
warn "Passo successivo: esegui lo script dot-files per configurare zsh, Oh My Zsh, p10k e alias."
