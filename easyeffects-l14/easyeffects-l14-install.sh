#!/bin/bash
# easyeffects-l14: preset EasyEffects dla wbudowanych glosnikow ThinkPad L14 Gen 2a.
# Korektor (16 pasm) odwzorowuje krzywa glosnikow z Windows (plik IR "abc"),
# kompresor wielopasmowy pilnuje basu, limiter chroni przed przesterem.
# Preset trafia do katalogu domowego uzytkownika, ktory uruchomil sudo.
#
# Instalacja:  sudo bash easyeffects-l14-install.sh
# Usuniecie:   sudo bash easyeffects-l14-install.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0"
    exit 1
fi

U="$SUDO_USER"
if [ -z "$U" ] || [ "$U" = "root" ]; then
    echo "Uruchom jako zwykly uzytkownik przez sudo (nie z konta root),"
    echo "zeby preset trafil do Twojego katalogu domowego."
    exit 1
fi
H=$(getent passwd "$U" | cut -d: -f6)
UID_U=$(id -u "$U")
GID_U=$(id -g "$U")

DIR="$(cd "$(dirname "$0")" && pwd)"
NAME=L14-windows
SRC="$DIR/$NAME.json"
# EasyEffects 7 trzyma presety w ~/.config, EasyEffects 8 w ~/.local/share
DIRS="$H/.config/easyeffects/output $H/.local/share/easyeffects/output"

if [ "$1" = "usun" ]; then
    for D in $DIRS; do
        rm -f "$D/$NAME.json"
    done
    echo "Usunieto preset $NAME. W EasyEffects wybierz inny preset albo wylacz efekty."
    exit 0
fi

if [ ! -f "$SRC" ]; then
    echo "Brak pliku $SRC - uruchom skrypt z pobranego repo."
    exit 1
fi

# --- 1. Pakiety: EasyEffects + wtyczki LSP (korektor, kompresor, limiter, filtr) i Calf (bass enhancer) ---
if command -v pacman >/dev/null; then
    pacman -S --needed --noconfirm easyeffects lsp-plugins-lv2 calf || {
        echo "Nie udalo sie zainstalowac pakietow - sprawdz internet i sprobuj ponownie."
        exit 1
    }
fi

# --- 2. Kopiowanie presetu ---
FOUND=0
for D in $DIRS; do
    [ -d "$(dirname "$D")" ] && FOUND=1
done
for D in $DIRS; do
    # jesli EasyEffects jeszcze nie byl uruchamiany, zakladamy oba katalogi
    if [ -d "$(dirname "$D")" ] || [ "$FOUND" -eq 0 ]; then
        install -d -o "$U" -g "$GID_U" "$D"
        install -m 644 -o "$U" -g "$GID_U" "$SRC" "$D/$NAME.json"
        echo "Preset skopiowany: $D/$NAME.json"
    fi
done
# katalogi nadrzedne zalozone przez root musza nalezec do uzytkownika
for P in "$H/.config/easyeffects" "$H/.config" "$H/.local/share/easyeffects" "$H/.local/share" "$H/.local"; do
    [ -d "$P" ] && [ "$(stat -c %u "$P")" = "0" ] && chown "$U:$GID_U" "$P"
done

# --- 3. Wczytanie presetu, jesli EasyEffects juz dziala ---
echo
if pgrep -u "$U" -x easyeffects >/dev/null; then
    runuser -u "$U" -- env XDG_RUNTIME_DIR="/run/user/$UID_U" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_U/bus" \
        easyeffects -l "$NAME" >/dev/null 2>&1 \
        && echo "Preset $NAME wczytany." \
        || echo "Nie udalo sie wczytac automatycznie - w EasyEffects: Presety -> $NAME."
else
    echo "EasyEffects nie jest uruchomiony. Uruchom go i wybierz: Presety -> $NAME."
fi

echo
echo "GOTOWE. Sprawdz w EasyEffects:"
echo "  Korektor: 16 pasm, tryb APO (DR)"
echo "  Kompresor wielopasmowy -> pasmo 0: sidechain Peak, lookahead 5 ms"
echo "Glosnosc reguluj tylko: Limiter -> Input gain (domyslnie +12,5 dB)."
