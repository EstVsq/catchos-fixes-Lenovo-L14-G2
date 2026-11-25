#!/bin/bash
# easyeffects-l14: preset EasyEffects dla wbudowanych glosnikow ThinkPad L14 Gen 2a.
# Korektor (16 pasm) odwzorowuje krzywa glosnikow z Windows (plik IR "abc"),
# kompresor wielopasmowy pilnuje basu, limiter chroni przed przesterem.
# Ustawia tez EasyEffects tak, zeby nie odlaczal filtrow w ciszy (bez "blepu").
# Preset mikrofonu L14-mikrofon: filtr 90 Hz, odszumianie RNNoise, korektor (wyraznosc mowy),
# kompresor glosu i limiter.
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
MIC=L14-mikrofon
MIC_DIRS="$H/.config/easyeffects/input $H/.local/share/easyeffects/input"
# EasyEffects 8: po tylu sekundach ciszy odlacza filtry, a przy starcie dzwieku podlacza
# je z powrotem -> krotki "blep". Duza wartosc = filtry zostaja podlaczone.
EECFG="$H/.config/easyeffects/db/easyeffectsrc"
TIMEOUT=3600

if [ "$1" = "usun" ]; then
    for D in $DIRS; do
        rm -f "$D/$NAME.json"
    done
    for D in $MIC_DIRS; do
        rm -f "$D/$MIC.json"
    done
    # przywrocenie domyslnego odlaczania filtrow (usuniecie wpisow = wartosc domyslna EasyEffects)
    [ -f "$EECFG" ] && sed -i '/^outputInactivityTimeout=/d; /^inputInactivityTimeout=/d' "$EECFG"
    echo "Usunieto presety $NAME i $MIC. W EasyEffects wybierz inny preset albo wylacz efekty."
    exit 0
fi

if [ ! -f "$SRC" ]; then
    echo "Brak pliku $SRC - uruchom skrypt z pobranego repo."
    exit 1
fi

# --- 1. Pakiety: EasyEffects + wtyczki LSP (korektor, kompresor, limiter, filtr) i Calf (bass enhancer) ---
if command -v pacman >/dev/null; then
    pacman -S --needed --noconfirm easyeffects lsp-plugins-lv2 calf rnnoise || {
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
for D in $MIC_DIRS; do
    if [ -d "$(dirname "$D")" ] || [ "$FOUND" -eq 0 ]; then
        install -d -o "$U" -g "$GID_U" "$D"
        install -m 644 -o "$U" -g "$GID_U" "$DIR/$MIC.json" "$D/$MIC.json"
        echo "Preset skopiowany: $D/$MIC.json"
    fi
done
# katalogi nadrzedne zalozone przez root musza nalezec do uzytkownika
for P in "$H/.config/easyeffects" "$H/.config" "$H/.local/share/easyeffects" "$H/.local/share" "$H/.local"; do
    [ -d "$P" ] && [ "$(stat -c %u "$P")" = "0" ] && chown "$U:$GID_U" "$P"
done

# --- 3. EasyEffects nie odlacza filtrow w ciszy (bez "blepu" przy starcie dzwieku) ---
set_ee() {   # $1 = sekcja, $2 = klucz, $3 = wartosc
    [ -f "$EECFG" ] || : > "$EECFG"
    awk -v g="[$1]" -v k="$2" -v v="$3" '
        /^\[/ { if (ing && !done) { print k "=" v; done = 1 }; ing = ($0 == g) }
        ing && index($0, k "=") == 1 { if (!done) { print k "=" v; done = 1 }; next }
        { print }
        END { if (!done) { if (!ing) print g; print k "=" v } }
    ' "$EECFG" > "$EECFG.tmp" && mv "$EECFG.tmp" "$EECFG"
}
for d in "$H/.config" "$H/.config/easyeffects" "$H/.config/easyeffects/db"; do
    [ -d "$d" ] || install -d -o "$U" -g "$GID_U" "$d"
done
set_ee EffectsPipelines outputInactivityTimeout "$TIMEOUT"
set_ee EffectsPipelines inputInactivityTimeout "$TIMEOUT"
chown "$U:$GID_U" "$EECFG"
echo "EasyEffects: filtry odlaczane dopiero po $TIMEOUT s ciszy ($EECFG)"
if pgrep -u "$U" -x easyeffects >/dev/null; then
    echo "  -> zamknij EasyEffects (menu -> Zakoncz) i uruchom ponownie, zeby to zadzialalo."
fi

# --- 4. Wczytanie presetow, jesli EasyEffects juz dziala ---
echo
if pgrep -u "$U" -x easyeffects >/dev/null; then
    for N in "$NAME" "$MIC"; do
        runuser -u "$U" -- env XDG_RUNTIME_DIR="/run/user/$UID_U" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_U/bus" \
            easyeffects -l "$N" >/dev/null 2>&1 \
            && echo "Preset $N wczytany." \
            || echo "Nie udalo sie wczytac automatycznie - w EasyEffects: Presety -> $N."
    done
else
    echo "EasyEffects nie jest uruchomiony. Uruchom go i wybierz:"
    echo "  Wyjscie (glosniki): Presety -> $NAME"
    echo "  Wejscie (mikrofon): Presety -> $MIC"
fi

echo
echo "GOTOWE. Sprawdz w EasyEffects:"
echo "  Wyjscie: Korektor 16 pasm, tryb APO (DR);"
echo "           Kompresor wielopasmowy -> pasmo 0: sidechain Peak, lookahead 5 ms"
echo "  Glosnosc glosnikow reguluj tylko: Limiter -> Input gain (domyslnie +12,5 dB)."
echo "  Wejscie: Filtr 90 Hz -> RNNoise -> Korektor -> Kompresor -> Limiter"
echo "  Glosnosc mikrofonu reguluj tylko: Kompresor -> Makeup (domyslnie +13 dB)."
