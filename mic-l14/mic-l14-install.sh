#!/bin/bash
# mic-l14: mikrofon wbudowany (Realtek ALC257) bez przesteru na calym zakresie suwaka.
# Problem: suwak 100% = Capture +30 dB + Internal Mic Boost +30 dB = +60 dB -> przester juz od ~30%.
# Poprawka (nadpisanie profilu ALSA w katalogu domowym, pliki systemowe bez zmian):
#   - Internal Mic Boost / Int Mic Boost zawsze 0 dB,
#   - Capture ograniczone do kroku 54 (+23,25 dB) -> suwak 100% = dawne 25%,
#   - Mic Boost dla mikrofonu z gniazda (zestaw sluchawkowy) zawsze 0 dB.
#
# Instalacja:  sudo bash mic-l14-install.sh
# Usuniecie:   sudo bash mic-l14-install.sh usun

LIMIT=54          # krok Capture 0-63, 54 = +23,25 dB
SYS=/usr/share/alsa-card-profile/mixer/paths

if [ "$(id -u)" -eq 0 ]; then
    U="$SUDO_USER"
    if [ -z "$U" ] || [ "$U" = "root" ]; then
        echo "Uruchom jako zwykly uzytkownik przez sudo (nie z konta root)."
        exit 1
    fi
else
    U="$(id -un)"
fi
H=$(getent passwd "$U" | cut -d: -f6)
UID_U=$(id -u "$U")
GID_U=$(id -g "$U")
DST="$H/.config/alsa-card-profile/paths"

asuser() {
    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$U" -- env XDG_RUNTIME_DIR="/run/user/$UID_U" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_U/bus" "$@"
    else
        "$@"
    fi
}

restart_audio() {
    echo "Restart WirePlumber..."
    asuser systemctl --user restart wireplumber
    for _ in $(seq 1 20); do
        SRC=$(asuser pactl list short sources 2>/dev/null | awk '{print $2}' | grep '^alsa_input' | head -1)
        [ -n "$SRC" ] && break
        sleep 0.5
    done
}

if [ "$1" = "usun" ]; then
    rm -f "$DST/analog-input-internal-mic.conf" "$DST/analog-input-mic.conf"
    restart_audio
    echo "Usunieto poprawke mikrofonu. Ustaw glosnosc mikrofonu na ok. 25%, zeby nie przesterowywal."
    exit 0
fi

for f in analog-input-internal-mic.conf analog-input-mic.conf; do
    [ -f "$SYS/$f" ] || { echo "Brak $SYS/$f - czy jest zainstalowany pipewire?"; exit 1; }
done

for d in "$H/.config" "$H/.config/alsa-card-profile" "$DST"; do
    [ -d "$d" ] || install -d -o "$U" -g "$GID_U" "$d"
done

# 1. Mikrofon wbudowany: boost na zero, Capture z limitem
awk -v limit="$LIMIT" '
    /^\[/ {
        sec = $0
        print
        if (sec == "[Element Capture]") print "volume-limit = " limit
        next
    }
    (sec == "[Element Internal Mic Boost]" || sec == "[Element Int Mic Boost]") && /^volume *=/ {
        print "volume = zero"; next
    }
    sec == "[Element Capture]" && /^volume-limit *=/ { next }
    { print }
' "$SYS/analog-input-internal-mic.conf" > "$DST/analog-input-internal-mic.conf"

# 2. Mikrofon z gniazda: tylko boost na zero
awk '
    /^\[/ { sec = $0; print; next }
    sec == "[Element Mic Boost]" && /^volume *=/ { print "volume = zero"; next }
    { print }
' "$SYS/analog-input-mic.conf" > "$DST/analog-input-mic.conf"

chown "$U:$GID_U" "$DST"/analog-input-internal-mic.conf "$DST"/analog-input-mic.conf
chmod 644 "$DST"/analog-input-internal-mic.conf "$DST"/analog-input-mic.conf

# sprawdzenie, czy edycja sie udala
if ! grep -q "^volume-limit = $LIMIT" "$DST/analog-input-internal-mic.conf" \
   || ! awk '/^\[/{s=$0} s=="[Element Internal Mic Boost]" && /^volume = zero/{ok=1} END{exit !ok}' "$DST/analog-input-internal-mic.conf"; then
    echo "Nie udalo sie zmodyfikowac profilu - zmienila sie struktura pliku $SYS/analog-input-internal-mic.conf."
    rm -f "$DST/analog-input-internal-mic.conf" "$DST/analog-input-mic.conf"
    exit 1
fi
echo "Profil mikrofonu zapisany w $DST"

# 3. Restart i ustawienie suwaka na 100% (= dawne 25%)
restart_audio
if [ -n "$SRC" ]; then
    asuser pactl set-source-mute "$SRC" 0
    asuser pactl set-source-volume "$SRC" 100%
    sleep 1
    CARD=$(asuser pactl list sources | awk -v s="Name: $SRC" 'index($0,s){f=1} f && /alsa.card = /{gsub(/[^0-9]/,"",$3); print $3; exit}')
    echo
    echo "Mikrofon: $SRC, suwak 100%"
    if [ -n "$CARD" ] && command -v amixer >/dev/null; then
        amixer -c "$CARD" sget 'Capture' | grep -m1 'Front Left'
        amixer -c "$CARD" sget 'Internal Mic Boost' 2>/dev/null | grep -m1 'Front Left'
    fi
    echo "Oczekiwane: Capture 54 [23.25dB], Internal Mic Boost 0 [0.00dB]."
else
    echo "Nie znaleziono mikrofonu po restarcie - sprawdz: pactl list short sources"
fi
echo
echo "GOTOWE. Suwak mikrofonu: 100% = poziom, ktory wczesniej dawalo 25%."
