#!/bin/bash
# ryzen-power: podnosi limit mocy Ryzen 7 PRO 5850U z 25 W do 30 W (sufit tego laptopa)
# - tylko na zasilaczu i w trybie zasilania "Wydajnosc" (performance),
# - na baterii / w innych trybach wracaja limity Lenovo,
# - sprawdzane przy starcie, po wybudzeniu i co 20 s (Lenovo potrafi przywrocic swoje limity).
# Zmierzone: wszystkie rdzenie 2,92 -> 3,12 GHz (+7%), ~85 C po 3 min, glosniejszy wentylator.
#
# Instalacja:  sudo bash ryzen-power-install.sh
# Usuniecie:   sudo bash ryzen-power-install.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0"
    exit 1
fi

APPLY=/usr/local/sbin/ryzen-power-apply
SVC=/etc/systemd/system/ryzen-power.service
TIMER=/etc/systemd/system/ryzen-power.timer

# ---------------- USUWANIE ----------------
if [ "$1" = "usun" ]; then
    systemctl disable --now ryzen-power.timer 2>/dev/null
    systemctl disable ryzen-power.service 2>/dev/null
    [ -x "$APPLY" ] && "$APPLY" --stock
    rm -f "$APPLY" "$SVC" "$TIMER" /run/ryzen-power.state
    systemctl daemon-reload
    echo "Usunieto. Dzialaja limity Lenovo."
    echo "(Program ryzenadj zostal w systemie - usuniesz go: sudo rm -f /usr/local/bin/ryzenadj)"
    exit 0
fi

if ! grep -q 'AMD Ryzen' /proc/cpuinfo; then
    echo "To nie jest procesor AMD Ryzen - pomijam."
    exit 0
fi
if [ ! -e /sys/firmware/acpi/platform_profile ]; then
    echo "Brak /sys/firmware/acpi/platform_profile (trybow zasilania) - pomijam."
    exit 0
fi

# ---------------- 1. RYZENADJ ----------------
if ! command -v ryzenadj >/dev/null; then
    echo "=== Buduje ryzenadj ze zrodel (github.com/FlyGoat/RyzenAdj) ==="
    pacman -S --needed --noconfirm base-devel cmake pciutils git >/dev/null || {
        echo "Nie udalo sie zainstalowac narzedzi do budowania - sprawdz internet."; exit 1; }
    W=$(mktemp -d /tmp/ryzenadj.XXXXXX)
    if git clone -q --depth 1 https://github.com/FlyGoat/RyzenAdj "$W/src" &&
       cmake -S "$W/src" -B "$W/build" -DCMAKE_BUILD_TYPE=Release >/dev/null &&
       cmake --build "$W/build" -j"$(nproc)" >/dev/null; then
        install -m755 "$W/build/ryzenadj" /usr/local/bin/ryzenadj
        rm -rf "$W"
        echo "ryzenadj zainstalowany w /usr/local/bin"
    else
        rm -rf "$W"
        echo "Nie udalo sie zbudowac ryzenadj."; exit 1
    fi
fi

if ! ryzenadj -i 2>/dev/null | grep -q 'PPT LIMIT SLOW'; then
    echo "ryzenadj nie moze odczytac limitow procesora - pomijam."
    exit 1
fi

# ---------------- 2. SKRYPT USTAWIAJACY ----------------
cat > "$APPLY" << 'APPLY_EOF'
#!/bin/bash
# ryzen-power-apply: 30 W na zasilaczu w trybie "performance", limity Lenovo w pozostalych przypadkach.
#   ryzen-power-apply          - sprawdz stan i ustaw
#   ryzen-power-apply --stock  - wymus powrot do limitow Lenovo
STAPM=30000     # dlugotrwaly (procesor i tak nie przyjmuje wiecej niz 30 W)
SLOW=30000      # kilkusekundowy (Lenovo: 25 W)
FAST=35000      # chwilowy zryw (Lenovo: 30 W)
TEMP=95         # maks. temperatura (Lenovo: 100)
STATE=/run/ryzen-power.state
PP=/sys/firmware/acpi/platform_profile

on_ac() {
    for s in /sys/class/power_supply/*; do
        [ "$(cat "$s/type" 2>/dev/null)" = "Mains" ] && [ "$(cat "$s/online" 2>/dev/null)" = "1" ] && return 0
    done
    return 1
}

# przywraca limity Lenovo: chwilowa zmiana trybu zmusza firmware do ponownego ustawienia
stock() {
    local P
    P=$(cat "$PP")
    if [ "$P" = "balanced" ]; then echo performance > "$PP"; else echo balanced > "$PP"; fi
    sleep 0.5
    echo "$P" > "$PP"
    echo stock > "$STATE"
    logger -t ryzen-power "limity Lenovo (tryb $P, zasilacz: $(on_ac && echo tak || echo nie))"
}

if [ "$1" = "--stock" ]; then
    stock
    exit 0
fi

if on_ac && [ "$(cat "$PP")" = "performance" ]; then
    CUR=$(ryzenadj -i 2>/dev/null | awk -F'|' '/PPT LIMIT SLOW/{gsub(/ /,"",$3); print int($3)}')
    if [ "$CUR" != "$((SLOW / 1000))" ]; then
        ryzenadj --stapm-limit=$STAPM --slow-limit=$SLOW --fast-limit=$FAST --tctl-temp=$TEMP >/dev/null 2>&1
        echo boost > "$STATE"
        logger -t ryzen-power "ustawiono $((SLOW / 1000)) W (bylo ${CUR:-?} W)"
    fi
else
    [ "$(cat "$STATE" 2>/dev/null)" = "boost" ] && stock
fi
APPLY_EOF
chmod 755 "$APPLY"

# ---------------- 3. USLUGA + TIMER ----------------
cat > "$SVC" << 'SVC_EOF'
[Unit]
Description=ryzen-power: 30 W na zasilaczu w trybie Wydajnosc
After=power-profiles-daemon.service suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ryzen-power-apply

[Install]
WantedBy=multi-user.target suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
SVC_EOF

cat > "$TIMER" << 'TIMER_EOF'
[Unit]
Description=ryzen-power: sprawdzanie limitow co 20 s

[Timer]
OnBootSec=15s
OnUnitActiveSec=20s
AccuracySec=1s

[Install]
WantedBy=timers.target
TIMER_EOF

systemctl daemon-reload
systemctl enable ryzen-power.service >/dev/null 2>&1
systemctl enable --now ryzen-power.timer >/dev/null 2>&1
systemctl start ryzen-power.service

echo
echo "Tryb zasilania: $(cat /sys/firmware/acpi/platform_profile)"
ryzenadj -i 2>/dev/null | grep -E 'STAPM LIMIT|PPT LIMIT (FAST|SLOW)|THM LIMIT'
echo
echo "GOTOWE. Na zasilaczu w trybie 'Wydajnosc' limit to 30 W, w innych przypadkach limity Lenovo."
echo "Log:  journalctl -t ryzen-power"
