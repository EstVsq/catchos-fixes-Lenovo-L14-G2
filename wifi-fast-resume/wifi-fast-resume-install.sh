#!/bin/bash
# Instalator obejscia (wersja 4) bledu ath12k / WCN785x (FastConnect 7800):
# po wybudzeniu firmware resetuje kraj do WORLD i WiFi laczy sie ~16 s.
# Gdy kraj wroci, skrypt przerywa dlugi pelny skan i kaze wpa_supplicant
# zeskanowac tylko ostatnio uzywany kanal - NetworkManager laczy sie sam.
#
# Instalacja:  sudo bash wifi-fast-resume-install.sh
# Usuniecie:   sudo bash wifi-fast-resume-install.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0"
    exit 1
fi

WORKER=/usr/local/bin/wifi-fast-resume.sh
HOOK=/usr/lib/systemd/system-sleep/wifi-fast-resume
FREQFILE=/var/lib/wifi-fast-resume.freq

if [ "$1" = "usun" ]; then
    rm -f "$WORKER" "$HOOK" "$FREQFILE" /var/lib/wifi-fast-resume.con
    echo "Usunieto. System wrocil do stanu sprzed poprawki."
    exit 0
fi

# plik z wersji 3, juz niepotrzebny
rm -f /var/lib/wifi-fast-resume.con

# --- 1. Skrypt, ktory po wybudzeniu przyspiesza laczenie ---
cat > "$WORKER" << 'WORKER_EOF'
#!/bin/bash
# Obejscie bledu ath12k/WCN785x: po wybudzeniu firmware resetuje kraj do WORLD.
# Gdy kraj wroci: przerwij pelny skan i zeskanuj przez wpa_supplicant tylko znany kanal.
FREQFILE=/var/lib/wifi-fast-resume.freq
IFACE=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')
[ -z "$IFACE" ] && exit 0
FREQ=$(cat "$FREQFILE" 2>/dev/null)

state() { nmcli -t -f DEVICE,STATE device | awk -F: -v d="$IFACE" '$1==d{print $2}'; }
country() {
    local PHY="phy#$(iw dev "$IFACE" info 2>/dev/null | awk '/wiphy/{print $2}')"
    iw reg get | awk -v p="$PHY" '$1==p{f=1;next} f&&/^country/{sub(":","",$2);print $2;exit}'
}
wpa_scan_freq() {
    local OBJ
    OBJ=$(busctl call fi.w1.wpa_supplicant1 /fi/w1/wpa_supplicant1 fi.w1.wpa_supplicant1 \
          GetInterface s "$IFACE" 2>&1 | awk '{print $2}' | tr -d '"')
    busctl call fi.w1.wpa_supplicant1 "$OBJ" fi.w1.wpa_supplicant1.Interface \
          Scan 'a{sv}' 2 Type s active Channels 'a(uu)' 1 "$1" 20 2>&1
}

START=$(date +%s%N)
ms() { echo $(( ($(date +%s%N)-START)/1000000 )); }
LAST=0
TRY=0
PREV=""
sleep 1
for i in $(seq 1 60); do
    ST=$(state)
    if [ "$ST" = "connected" ]; then
        F=$(iw dev "$IFACE" link | awk '/freq:/{print int($2)}')
        [ -n "$F" ] && echo "$F" > "$FREQFILE"
        logger -t wifi-fast-resume "WiFi polaczone po $(ms) ms (kanal $F MHz)"
        exit 0
    fi
    C=$(country)
    if [ "kraj=$C stan=$ST" != "$PREV" ]; then
        logger -t wifi-fast-resume "DIAG $(ms) ms: kraj=${C:-?} stan=$ST"
        PREV="kraj=$C stan=$ST"
    fi
    NOW=$(date +%s)
    if [ -n "$FREQ" ] && [ -n "$C" ] && [ "$C" != "00" ] && [ "$ST" = "disconnected" ] \
       && [ "$TRY" -lt 5 ] && [ $((NOW-LAST)) -ge 2 ]; then
        LAST=$NOW
        TRY=$((TRY+1))
        if [ "$TRY" -eq 1 ]; then
            iw dev "$IFACE" scan abort >/dev/null 2>&1
            sleep 0.3
        fi
        ERR=$(wpa_scan_freq "$FREQ")
        logger -t wifi-fast-resume "$(ms) ms: skan kanalu $FREQ MHz (proba $TRY) -> ${ERR:-ok}"
    fi
    sleep 0.3
done
logger -t wifi-fast-resume "brak polaczenia po ~20 s, poddaje sie"
WORKER_EOF
chmod 755 "$WORKER"

# --- 2. Podpiecie pod usypianie/wybudzanie ---
cat > "$HOOK" << 'HOOK_EOF'
#!/bin/sh
case "$1" in
    post)
        systemd-run --no-block --collect --unit="wifi-fast-resume-$(date +%s)" /usr/local/bin/wifi-fast-resume.sh
        ;;
esac
HOOK_EOF
chmod 755 "$HOOK"

# --- 3. Zapamietanie obecnego kanalu WiFi ---
IFACE=$(nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="wifi"{print $1; exit}')
F=$(iw dev "$IFACE" link 2>/dev/null | awk '/freq:/{print int($2)}')
if [ -n "$F" ]; then
    echo "$F" > "$FREQFILE"
    echo "Zapamietany kanal: $F MHz (karta $IFACE)"
else
    echo "WiFi teraz nie jest polaczone - kanal zapamieta sie sam po pierwszym polaczeniu."
fi

echo
echo "GOTOWE (wersja 4). Zainstalowano:"
echo "  $WORKER"
echo "  $HOOK"
echo
echo "Test: zamknij klape, odczekaj 20 s, otworz i po polaczeniu wpisz:"
echo "  journalctl -b -t wifi-fast-resume --since \"3 min ago\" --no-pager"
