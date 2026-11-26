#!/bin/bash
# scx-lavd: planista procesora scx_lavd (sched-ext) zamiast domyslnego BORE.
# Robiony przez Igalia dla Valve (Steam Deck): pierwszenstwo dla "pilnych" watkow
# (gra, dzwiek, obraz, wejscie) - mniej przyciec pod obciazeniem. Tryb autopilot
# przy malym obciazeniu usypia nieuzywane rdzenie (troche dluzej na baterii).
# Gdy planista sie wysypie, kernel sam wraca do BORE - nic sie nie zawiesza.
#
# Instalacja:  sudo bash scx-lavd-install.sh [planista]   (domyslnie scx_lavd, np. scx_bpfland)
# Usuniecie:   sudo bash scx-lavd-install.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0"
    exit 1
fi

CONF=/etc/scx_loader.toml

if [ "$1" = "usun" ]; then
    systemctl disable --now scx_loader 2>/dev/null
    rm -f "$CONF"
    echo "Usunieto. Dziala domyslny planista kernela (BORE)."
    exit 0
fi

SCHED="${1:-scx_lavd}"

if [ ! -d /sys/kernel/sched_ext ]; then
    echo "Ten kernel nie obsluguje sched-ext (brak /sys/kernel/sched_ext) - pomijam."
    exit 0
fi

# planisci + scx_loader (w nowszych wersjach scx_loader jest w osobnym pakiecie scx-tools)
pacman -S --needed --noconfirm scx-scheds >/dev/null || { echo "Nie udalo sie zainstalowac scx-scheds."; exit 1; }
if ! systemctl cat scx_loader.service >/dev/null 2>&1; then
    pacman -S --needed --noconfirm scx-tools >/dev/null 2>&1
fi
if ! systemctl cat scx_loader.service >/dev/null 2>&1; then
    echo "Brak uslugi scx_loader - nie umiem wlaczyc planisty na stale."
    exit 1
fi
if ! command -v "$SCHED" >/dev/null; then
    echo "Nie ma planisty $SCHED. Dostepne:"; ls /usr/bin/scx_* 2>/dev/null | xargs -n1 basename
    exit 1
fi

printf 'default_sched = "%s"\ndefault_mode = "Auto"\n' "$SCHED" > "$CONF"
systemctl enable scx_loader >/dev/null 2>&1
systemctl restart scx_loader
sleep 3

echo "sched-ext: $(cat /sys/kernel/sched_ext/state 2>/dev/null), planista: $(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo '?')"
echo "GOTOWE. $SCHED wlacza sie przy kazdym starcie."
echo "Powrot do BORE:  sudo bash $0 usun"
