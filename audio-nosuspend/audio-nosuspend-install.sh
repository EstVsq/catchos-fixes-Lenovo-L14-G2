#!/bin/bash
# audio-nosuspend: bez krotkiego "blep"/trzasku na poczatku dzwieku (np. start filmu na YouTube).
# Przyczyna: gdy nic nie gra (tez na ulamek sekundy przy przewijaniu filmu), PipeWire
# pauzuje karte, a po 5 s ja usypia; sterownik snd_hda_intel wylacza zasilanie kodeka Realtek.
# Po wznowieniu karta odgrywa resztke starego dzwieku z wlasnego bufora / trzeszczy,
# a EasyEffects (limiter +12,5 dB) to jeszcze wzmacnia.
# Poprawka:
#   - WirePlumber: wbudowane wyjscie (pci-0000_07_00.6) nigdy nie jest pauzowane ani usypiane
#     (gra cisze zamiast pauzy, wiec w buforze karty nie zostaje stary dzwiek),
#   - snd_hda_intel power_save=0 (kodek zawsze zasilony; TLP tez, jesli jest),
# Koszt: ok. 0,1-0,3 W wiecej.
#
# Instalacja:  sudo bash audio-nosuspend-install.sh
# Usuniecie:   sudo bash audio-nosuspend-install.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0"
    exit 1
fi
U="$SUDO_USER"
if [ -z "$U" ] || [ "$U" = "root" ]; then
    echo "Uruchom jako zwykly uzytkownik przez sudo (nie z konta root)."
    exit 1
fi
H=$(getent passwd "$U" | cut -d: -f6)
UID_U=$(id -u "$U")
GID_U=$(id -g "$U")

MODPROBE=/etc/modprobe.d/audio-nosuspend.conf
TLPCONF=/etc/tlp.d/50-audio-nosuspend.conf
WPDIR="$H/.config/wireplumber/wireplumber.conf.d"
WPCONF="$WPDIR/51-audio-nosuspend.conf"
PS=/sys/module/snd_hda_intel/parameters/power_save

asuser() {
    runuser -u "$U" -- env XDG_RUNTIME_DIR="/run/user/$UID_U" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_U/bus" "$@"
}

if [ "$1" = "usun" ]; then
    PREV=$(sed -n 's/^# poprzednio power_save=\([0-9]*\).*/\1/p' "$MODPROBE" 2>/dev/null)
    rm -f "$MODPROBE" "$TLPCONF" "$WPCONF"
    [ -w "$PS" ] && echo "${PREV:-1}" > "$PS"
    command -v tlp >/dev/null && tlp start >/dev/null 2>&1
    asuser systemctl --user restart wireplumber
    echo "Usunieto audio-nosuspend (power_save=${PREV:-1})."
    exit 0
fi

# --- 1. Kodek zawsze zasilony ---
PREV=$(cat "$PS" 2>/dev/null)
cat > "$MODPROBE" <<EOF
# audio-nosuspend: kodek Realtek nie wylacza zasilania (bez trzasku przy starcie dzwieku)
# poprzednio power_save=${PREV:-1}
options snd_hda_intel power_save=0
EOF
[ -w "$PS" ] && echo 0 > "$PS"

if command -v tlp >/dev/null; then
    mkdir -p /etc/tlp.d
    cat > "$TLPCONF" <<'EOF'
# audio-nosuspend: TLP nie wlacza oszczedzania energii karty dzwiekowej
SOUND_POWER_SAVE_ON_AC=0
SOUND_POWER_SAVE_ON_BAT=0
EOF
    tlp start >/dev/null 2>&1
fi

# --- 2. WirePlumber: wbudowane wyjscie bez usypiania ---
for d in "$H/.config" "$H/.config/wireplumber" "$WPDIR"; do
    [ -d "$d" ] || install -d -o "$U" -g "$GID_U" "$d"
done
cat > "$WPCONF" <<'EOF'
# audio-nosuspend: wbudowana karta dzwiekowa L14 nie jest usypiana
monitor.alsa.rules = [
  {
    matches = [
      { node.name = "~alsa_output.pci-0000_07_00.6.*" }
    ]
    actions = {
      update-props = {
        node.pause-on-idle = false
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
EOF
chown "$U:$GID_U" "$WPCONF"; chmod 644 "$WPCONF"

echo "Restart WirePlumber..."
asuser systemctl --user restart wireplumber
sleep 2

# --- 3. Sprawdzenie ---
echo
echo "power_save: $(cat "$PS" 2>/dev/null)   (oczekiwane: 0)"
T=$(asuser pactl list sinks 2>/dev/null | grep -A60 'Name: alsa_output.pci-0000_07_00.6' | grep -m1 'session.suspend-timeout-seconds' | grep -o '[0-9]\+')
echo "usypianie wyjscia: session.suspend-timeout-seconds = ${T:-brak}   (oczekiwane: 0)"
P=$(asuser pactl list sinks 2>/dev/null | grep -A60 'Name: alsa_output.pci-0000_07_00.6' | grep -m1 'node.pause-on-idle' | grep -o 'true\|false')
echo "pauzowanie wyjscia: node.pause-on-idle = ${P:-brak}   (oczekiwane: false)"
echo
echo "GOTOWE. Przewin kilka razy film na YouTube - nie powinno byc \"blepu\"."
