#!/bin/bash
# lte-modem: uruchamia modem LTE Quectel EM120R-GL (PCI 1eac:1001) w ThinkPad L14 Gen 2a.
#  1. wlacza ModemManager (domyslnie wylaczony w CachyOS),
#  2. wlacza zdejmowanie blokady FCC (skrypt ModemManagera dla 1eac:xxxx),
#  3. w samym modemie: gniazdo SIM nr 1 i wylaczone wykrywanie karty przez styk
#     (AT+QUIMSLOT=1, AT+QSIMDET=0,0) - bez tego modem zglasza "sim-missing",
#  4. tworzy polaczenie NetworkManagera "LTE" (IPv4, laczy sie samo; WiFi ma pierwszenstwo).
#
# Instalacja:  sudo bash lte-modem-install.sh [APN]      (domyslnie APN: a2mobile.pl)
# Usuniecie:   sudo bash lte-modem-install.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0 [APN]"
    exit 1
fi

CON=LTE
FCCDIR=/etc/ModemManager/fcc-unlock.d
FCCAVAIL=/usr/share/ModemManager/fcc-unlock.available.d

# --- modem Quectel na PCI (vendor 0x1eac) ---
modem_id() {
    for d in /sys/bus/pci/devices/*; do
        if [ "$(cat "$d/vendor" 2>/dev/null)" = "0x1eac" ]; then
            echo "1eac:$(sed 's/^0x//' "$d/device")"
            return 0
        fi
    done
    return 1
}

# --- port AT modemu ---
at_port() { ls /dev/wwan*at0 2>/dev/null | head -1; }

# wysyla komende AT, wypisuje odpowiedz (ModemManager musi byc zatrzymany)
at() {
    local P
    P=$(at_port)
    [ -n "$P" ] || return 1
    exec 3<>"$P"
    printf "%s\r" "$1" >&3
    timeout "${2:-2}" cat <&3
    exec 3>&-
}

ID=$(modem_id)

# ---------------- USUWANIE ----------------
if [ "$1" = "usun" ]; then
    nmcli connection delete "$CON" 2>/dev/null
    [ -n "$ID" ] && rm -f "$FCCDIR/$ID"
    systemctl stop ModemManager
    if [ -n "$(at_port)" ]; then
        echo "Przywracam wykrywanie karty SIM w modemie (AT+QSIMDET=1,1)..."
        at "AT+QSIMDET=1,1" | grep -q OK && echo "OK"
    fi
    systemctl disable ModemManager
    echo "Usunieto. ModemManager wylaczony, polaczenie $CON usuniete."
    exit 0
fi

APN="${1:-a2mobile.pl}"

if [ -z "$ID" ]; then
    echo "Nie znaleziono modemu Quectel (PCI 1eac:xxxx) - pomijam."
    exit 0
fi
echo "Modem: $ID, APN: $APN"

# ---------------- 1. PAKIETY ----------------
pacman -S --needed --noconfirm modemmanager networkmanager >/dev/null || {
    echo "Nie udalo sie zainstalowac modemmanager - sprawdz internet."
    exit 1
}

# ---------------- 2. BLOKADA FCC ----------------
if [ -e "$FCCAVAIL/$ID" ]; then
    mkdir -p "$FCCDIR"
    ln -sfn "$FCCAVAIL/$ID" "$FCCDIR/$ID"
    echo "Blokada FCC: zdejmowanie wlaczone ($FCCDIR/$ID)"
else
    echo "UWAGA: ModemManager nie ma skryptu FCC dla $ID - modem moze nie wlaczyc radia."
fi

# ---------------- 3. USTAWIENIA KARTY SIM W MODEMIE ----------------
modprobe mhi_wwan_ctrl 2>/dev/null
modprobe mhi_wwan_mbim 2>/dev/null
systemctl stop ModemManager 2>/dev/null
for i in $(seq 1 20); do [ -n "$(at_port)" ] && break; sleep 0.5; done

if [ -z "$(at_port)" ]; then
    echo "UWAGA: brak portu AT modemu (/dev/wwan*at0) - pomijam ustawienia SIM."
else
    SLOT=$(at "AT+QUIMSLOT?" | grep -o 'QUIMSLOT: [0-9]' | grep -o '[0-9]$')
    DET=$(at "AT+QSIMDET?" | grep -o 'QSIMDET: [0-9],[0-9]' | sed 's/QSIMDET: //')
    echo "Modem teraz: gniazdo SIM=$SLOT, wykrywanie SIM=$DET"
    if [ "$SLOT" != "1" ]; then
        at "AT+QUIMSLOT=1" 3 | grep -q OK && echo "Ustawiono gniazdo SIM nr 1"
    fi
    if [ "$DET" != "0,0" ]; then
        at "AT+QSIMDET=0,0" | grep -q OK && echo "Wylaczono wykrywanie karty przez styk (QSIMDET=0,0)"
    fi
fi

# ---------------- 4. MODEMMANAGER ----------------
systemctl enable --now ModemManager
echo "Czekam, az ModemManager wykryje modem..."
for i in $(seq 1 30); do
    mmcli -L 2>/dev/null | grep -q Modem && break
    sleep 1
done

# ---------------- 5. POLACZENIE LTE ----------------
if nmcli -t -f NAME connection show | grep -qx "$CON"; then
    nmcli connection modify "$CON" gsm.apn "$APN" ipv6.method disabled connection.autoconnect yes
    echo "Zaktualizowano polaczenie $CON (APN $APN)"
else
    nmcli connection add type gsm ifname '*' con-name "$CON" gsm.apn "$APN" \
        ipv6.method disabled connection.autoconnect yes >/dev/null
    echo "Utworzono polaczenie $CON (APN $APN)"
fi

echo
mmcli -m any 2>/dev/null | grep -E 'state:|power state|signal quality|operator name|sim slot' \
    || echo "ModemManager jeszcze nie widzi modemu - sprawdz za chwile:  mmcli -m any"
echo
echo "GOTOWE. Polaczenie '$CON' laczy sie samo (WiFi ma pierwszenstwo)."
echo "Recznie:  nmcli connection up $CON"
