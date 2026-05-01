# arch-install

Script di installazione automatica per Arch Linux, sviluppati e testati su hardware reale.

## Script disponibili

| Script | Descrizione |
|--------|-------------|
| `install-arch.sh` | Installazione completa con scelta DE (GNOME, KDE, Cinnamon, XFCE, Niri+Noctalia) |
| `install-arch-gnome.sh` | Installazione dedicata GNOME con scelta bootloader (GRUB, systemd-boot, Limine) |
| `install-arch-gnome-no-zsh-config.sh` | Come sopra, senza configurazione zsh — da completare con dot-files |

---

## Requisiti

- Boot da [Arch Linux ISO](https://archlinux.org/download/) in modalità **UEFI**
- Connessione internet (WiFi o Ethernet)
- Disco da almeno **20GB**

---

## Guida al primo avvio dalla live ISO

### 1. Imposta la tastiera italiana

```bash
loadkeys it
```

### 2. Connessione Ethernet

Se sei collegato via cavo, la rete è già attiva. Verifica con:

```bash
ping -c 3 archlinux.org
```

### 3. Connessione WiFi

```bash
iwctl
```

Dentro iwctl:

```bash
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "NomeDellaRete"
```

Digita la password quando richiesta, poi esci:

```bash
exit
```

Verifica la connessione:

```bash
ping -c 3 archlinux.org
```

### 4. Scarica ed esegui lo script

#### Installazione completa (con scelta DE)

```bash
curl -O https://raw.githubusercontent.com/mruin/arch-install/main/install-arch.sh
chmod +x install-arch.sh
./install-arch.sh
```

#### Installazione GNOME (con scelta bootloader)

```bash
curl -O https://raw.githubusercontent.com/mruin/arch-install/main/install-arch-gnome.sh
chmod +x install-arch-gnome.sh
./install-arch-gnome.sh
```

#### Installazione GNOME senza configurazione zsh

Installa il sistema completo lasciando zsh privo di configurazione, da applicare in seguito con il repo dot-files.

Se vuoi lo **sfondo Limine** (`archcustom.png`), clona il repo invece di scaricare il solo script:

```bash
git clone https://github.com/mruin/arch-install
cd arch-install
bash install-arch-gnome-no-zsh-config.sh
```

---

## Cosa configurano gli script

### Sistema base (entrambi gli script)

- Filesystem **btrfs** con subvolumi: `@`, `@home`, `@snapshots`, `@log`, `@cache`
- Kernel **linux-zen**
- **ZRAM** swap con compressione zstd
- **Snapper** con snapshot automatici pre/post ogni operazione pacman
- Locale e tastiera italiani
- SSH abilitato
- NetworkManager

### Shell

- **zsh** + Oh My Zsh + Powerlevel10k
- Plugin: git, sudo, archlinux, autosuggestions, syntax-highlighting, history-substring-search, colored-man-pages
- Greeter di benvenuto con info sistema (uptime, RAM, IP, disco, snapshot, aggiornamenti)
- Funzione `salias` per salvare alias persistenti
- Funzione `lista` per visualizzare gli alias
- Wrapper `paru` con controllo automatico riavvio dopo aggiornamenti

### Pacchetti aggiuntivi

- `paru` — AUR helper
- `bat` — sostituto di `cat`
- `btop` — sostituto di `htop`
- `needrestart` — controllo riavvio kernel

---

## Opzioni interattive

### `install-arch.sh`

| Opzione | Scelte disponibili |
|---------|-------------------|
| CPU | AMD / Intel |
| Disco | Qualsiasi (nvme, sata, virtio) |
| DE | Nessuno, GNOME, KDE Plasma, Cinnamon, XFCE, Niri+Noctalia |
| Display server | Wayland / X11 |
| Driver video | VirtualBox, NVIDIA, AMD, Intel, automatico |
| Tipo macchina | Desktop/VM, Laptop ASUS, ThinkPad Intel, ThinkPad AMD |
| VirtualBox Guest Additions | Sì / No |
| ZRAM | Dimensione in MB (default: 3072) |

### `install-arch-gnome.sh` e `install-arch-gnome-no-zsh-config.sh`

| Opzione | Scelte disponibili |
|---------|-------------------|
| CPU | AMD / Intel |
| Disco | Qualsiasi (nvme, sata, virtio) |
| Display server | Wayland / X11 |
| Driver video | VirtualBox, NVIDIA, AMD, Intel, automatico |
| Bootloader | GRUB, systemd-boot, Limine |
| VirtualBox Guest Additions | Sì / No |
| ZRAM | Dimensione in MB (default: 4096) |
| Plymouth | Sì / No (tema arch-charge-big) |

#### Limine — funzionalità extra (solo `no-zsh-config`)

- Palette terminale **Catppuccin Mocha**
- Sfondo personalizzato (`archcustom.png`) se presente nella stessa cartella dello script
- `interface_branding:` vuoto (rimuove il branding Limine)
- Group entry (`/+Arch Linux (zen)` → `//Kernel zen`)
- `/etc/default/limine` preconfigurato per `limine-snapper-sync`

Dopo il primo boot, installa manualmente la sincronizzazione snapshot:

```bash
paru -S limine-snapper-sync
```

---

## Supporto hardware specifico

### Laptop ASUS

- Battery limit all'80% via `asus-nb-wmi`
- Alias `battery-limit` (blocca all'80%) e `battery-full` (sblocca al 100%)
- Persistente al riavvio tramite udev

### Laptop Lenovo ThinkPad Intel (T14 Gen1 e simili)

- `thermald` per gestione termica Intel
- `TLP` ottimizzato per ThinkPad con profili AC/batteria
- Battery threshold start 75% / stop 80% gestito da TLP
- Retroilluminazione tastiera persistente al boot (livello 1)
- `acpi_call` per battery threshold
- Driver Intel: `mesa`, `vulkan-intel`, `intel-media-driver`, `libva-intel-driver`
- Audio: `pipewire` + `wireplumber`
- Bluetooth: `bluez`

---

## Post installazione

### Ricompila paru al primo boot

`paru-bin` viene installato dallo script ma può fallire con errore `libalpm.so` per incompatibilità di versione. Ricompila da sorgente:

```bash
cd /tmp && git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si --noconfirm
```

### Configura il prompt al primo login

```bash
paru -S ttf-nerd-fonts-symbols noto-fonts-emoji
p10k configure
```

### Niri + Noctalia Shell

Dopo il primo boot con Niri, installa Noctalia Shell:

```bash
paru -S noctalia-shell
```

Poi decommmenta la riga in `~/.config/niri/config.kdl`:

```
spawn-at-startup "qs" "-c" "noctalia-shell"
```

Riavvia niri con `Mod+Shift+E`.

---

## Fix documentati durante installazione reale

Durante lo sviluppo sono stati documentati e risolti questi problemi:

- **fstab /boot errato**: `genfstab` può generare una riga `/boot` come subvolume btrfs invece della partizione EFI vfat — causa moduli kernel non caricabili dopo aggiornamento. Risolto con sostituzione automatica.
- **vconsole.conf mancante**: va creato prima di `mkinitcpio`, altrimenti genera un warning durante la build.
- **Snapper in chroot**: `snapper create-config` fallisce in chroot per mancanza di dbus. Risolto con configurazione manuale.
- **NetworkManager-wait-online**: disabilitato per evitare timeout al boot quando la rete non è subito disponibile.
- **Binario Noctalia**: il binario corretto è `qs`, non `noctalia-qs`.
- **p10k instant prompt**: impostato `POWERLEVEL9K_INSTANT_PROMPT=quiet` per evitare warning con il greeter.

---

## Ripristino da snapshot

In caso di problemi dopo un aggiornamento, avvia dalla live ISO e ripristina:

```bash
# Monta il filesystem al top level
mount -o subvolid=5 /dev/sdX2 /mnt

# Elimina subvolumi annidati se presenti
btrfs subvolume delete /mnt/@/var/lib/portables 2>/dev/null || true
btrfs subvolume delete /mnt/@/var/lib/machines 2>/dev/null || true

# Elimina @ corrente e ripristina dallo snapshot desiderato
btrfs subvolume delete /mnt/@
btrfs subvolume snapshot /mnt/@snapshots/NUM/snapshot /mnt/@

# Monta e reinstalla GRUB
mount -o subvol=@ /dev/sdX2 /mnt
mount /dev/sdX1 /mnt/boot
mount -o subvol=@home /dev/sdX2 /mnt/home
mount -o subvol=@snapshots /dev/sdX2 /mnt/.snapshots
mount -o subvol=@log /dev/sdX2 /mnt/var/log
mount -o subvol=@cache /dev/sdX2 /mnt/var/cache
arch-chroot /mnt
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
exit
reboot
```

> Sostituisci `sdX1` e `sdX2` con le tue partizioni reali, e `NUM` con il numero dello snapshot pre-aggiornamento.

---

## Testato su

| Hardware | Stato |
|----------|-------|
| VirtualBox VM (AMD Ryzen 9 5900HX) | ✅ |
| Asus VivoBook S15 S530F | ✅ |
| Lenovo ThinkPad T14 Gen1 Intel (i5-10310U) | ✅ |
