#!/bin/bash
# ath12k-ccfix: poprawka sterownika WiFi Qualcomm WCN785x (FastConnect 7800, ath12k)
# Po wybudzeniu firmware karty startuje od nowa z krajem WORLD i dopiero po ~7 s
# sam odczytuje kraj z routera. Poprawka od razu po wybudzeniu wysyla mu ostatni
# znany kraj (tak jak w ath11k, commit 7f0343b7b871).
#
# Instalacja:  sudo bash ath12k-ccfix-install.sh
# Usuniecie:   sudo bash ath12k-ccfix-install.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0"
    exit 1
fi

BUILDER=/usr/local/sbin/ath12k-ccfix-build
HOOK=/etc/pacman.d/hooks/90-ath12k-ccfix.hook
DEPMODCONF=/etc/depmod.d/ath12k-ccfix.conf

reload_wifi() {
    echo "Przeladowuje sterownik WiFi (WiFi zniknie na kilkanascie sekund)..."
    modprobe -r ath12k_wifi7 2>/dev/null
    modprobe -r ath12k 2>/dev/null
    sleep 1
    modprobe ath12k_wifi7
}

# ---------------- USUWANIE ----------------
if [ "$1" = "usun" ]; then
    rm -f "$BUILDER" "$HOOK" "$DEPMODCONF"
    for d in /usr/lib/modules/*/updates/ath12k-ccfix; do
        [ -d "$d" ] || continue
        K=$(basename "$(dirname "$(dirname "$d")")")
        rm -rf "$d"
        depmod -a "$K"
    done
    reload_wifi
    echo
    echo "Usunieto. Dziala oryginalny sterownik:"
    modinfo -n ath12k ath12k_wifi7
    exit 0
fi

has_wcn785x() {
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = "0x17cb" ] && \
        [ "$(cat "$d/device" 2>/dev/null)" = "0x1107" ] && return 0
    done
    return 1
}

# ---------------- CZY JEST KARTA WCN785x (WiFi 7, PCI 17cb:1107)? ----------------
if ! has_wcn785x; then
    echo "Nie znaleziono karty WiFi 7 Qualcomm WCN785x (FastConnect 7800, PCI 17cb:1107)."
    echo "Ta poprawka jest tylko dla tej karty - pomijam."
    exit 0
fi

# ---------------- SPRAWDZENIE NARZEDZI ----------------
MISSING=""
for t in curl tar xz python3 make depmod; do
    command -v "$t" >/dev/null || MISSING="$MISSING $t"
done
if [ -n "$MISSING" ]; then
    echo "Brakuje programow:$MISSING"
    echo "Zainstaluj je:  sudo pacman -S --needed curl tar xz python make kmod"
    exit 1
fi

# ---------------- 1. SKRYPT BUDUJACY ----------------
mkdir -p "$(dirname "$BUILDER")"
cat > "$BUILDER" << 'BUILD_EOF'
#!/bin/bash
# Buduje poprawiony sterownik ath12k dla podanego kernela (albo --all dla wszystkich).
# Przy jakimkolwiek bledzie zostaje oryginalny sterownik.
set -o pipefail

build_one() {
    local KVER="$1"
    local KDIR="/usr/lib/modules/$KVER/build"
    local DEST="/usr/lib/modules/$KVER/updates/ath12k-ccfix"

    if [ ! -f "$KDIR/Makefile" ]; then
        echo "[$KVER] brak naglowkow kernela - pomijam"
        return 0
    fi
    if ! find "/usr/lib/modules/$KVER/kernel" -name 'ath12k_wifi7.ko*' 2>/dev/null | grep -q .; then
        echo "[$KVER] ten kernel nie ma sterownika ath12k_wifi7 - pomijam"
        return 0
    fi
    if [ -f "$DEST/.built" ]; then
        echo "[$KVER] poprawiony sterownik juz zbudowany"
        return 0
    fi
    if grep -q '^CONFIG_MODULE_SIG_FORCE=y' "$KDIR/.config"; then
        echo "[$KVER] kernel wymaga podpisanych modulow - pomijam"
        return 1
    fi

    local BASE="${KVER%%-*}"
    case "$BASE" in *rc*) echo "[$KVER] kernel testowy (rc) - pomijam"; return 1 ;; esac
    # 7.4.0 -> 7.4 (tak nazywa sie archiwum na kernel.org)
    if [ "$(echo "$BASE" | tr -cd . | wc -c)" = "2" ] && [ "${BASE##*.}" = "0" ]; then
        BASE="${BASE%.0}"
    fi
    local MAJOR="${BASE%%.*}"
    local URL="https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${BASE}.tar.xz"
    local WORK
    WORK=$(mktemp -d /tmp/ath12k-ccfix.XXXXXX)

    fail() {
        echo "[$KVER] BLAD: $1"
        echo "[$KVER] zostaje oryginalny sterownik WiFi."
        rm -rf "$DEST"
        depmod -a "$KVER"
        rm -rf "$WORK"
        return 1
    }

    echo "[$KVER] pobieram zrodla kernela $BASE (ok. 150 MB, chwile potrwa)..."
    if ! curl -fL --retry 3 --progress-bar "$URL" | \
         tar -xJf - -C "$WORK" --strip-components=1 "linux-${BASE}/drivers/net/wireless/ath"; then
        fail "nie udalo sie pobrac/rozpakowac $URL"; return 1
    fi

    local SRC="$WORK/drivers/net/wireless/ath/ath12k"
    echo "[$KVER] nakladam poprawke..."
    if ! python3 - "$SRC/core.c" << 'PY_EOF'
import sys
p = sys.argv[1]
s = open(p).read()
if "ath12k-ccfix" in s:
    sys.exit(0)
anchor_fn = "int ath12k_core_resume(struct ath12k_base *ab)\n{"
anchor_ret = "\n\treturn 0;\n}\nEXPORT_SYMBOL(ath12k_core_resume);"
if s.count(anchor_fn) != 1 or s.count(anchor_ret) != 1:
    sys.exit("nie znaleziono miejsca na poprawke (kod sterownika sie zmienil)")
helper = (
    "/* ath12k-ccfix: firmware is reinitialized on resume and falls back to the\n"
    " * WORLD regdomain until an 11d scan finishes (~7 s). Restore the last known\n"
    " * country code right away (same approach as ath11k commit 7f0343b7b871).\n"
    " */\n"
    "static void ath12k_core_restore_cc_on_resume(struct ath12k_base *ab)\n"
    "{\n"
    "\tstruct wmi_set_current_country_arg arg = {};\n"
    "\tstruct ath12k *ar;\n"
    "\tint ret, i;\n"
    "\n"
    "\tif (!ab->hw_params->current_cc_support)\n"
    "\t\treturn;\n"
    "\n"
    "\tfor (i = 0; i < ab->num_radios; i++) {\n"
    "\t\tar = ab->pdevs[i].ar;\n"
    "\t\tif (!ar || !ar->alpha2[0] || !ar->alpha2[1] ||\n"
    "\t\t    (ar->alpha2[0] == '0' && ar->alpha2[1] == '0'))\n"
    "\t\t\tcontinue;\n"
    "\n"
    "\t\tmemcpy(&arg.alpha2, ar->alpha2, 2);\n"
    "\t\tar->ah->regd_updated = false;\n"
    "\t\treinit_completion(&ar->regd_update_completed);\n"
    "\n"
    "\t\tret = ath12k_wmi_send_set_current_country_cmd(ar, &arg);\n"
    "\t\tif (ret)\n"
    "\t\t\tath12k_warn(ab, \"ath12k-ccfix: failed to restore country code %c%c: %d\\n\",\n"
    "\t\t\t\t    arg.alpha2[0], arg.alpha2[1], ret);\n"
    "\t\telse\n"
    "\t\t\tdev_info(ab->dev, \"ath12k-ccfix: restored country code %c%c after resume\\n\",\n"
    "\t\t\t\t arg.alpha2[0], arg.alpha2[1]);\n"
    "\t}\n"
    "}\n"
    "\n"
)
s = s.replace(anchor_fn, helper + anchor_fn)
s = s.replace(anchor_ret,
    "\n\tath12k_core_restore_cc_on_resume(ab);\n\n\treturn 0;\n}\nEXPORT_SYMBOL(ath12k_core_resume);")
open(p, "w").write(s)
PY_EOF
    then
        fail "nie udalo sie nalozyc poprawki"; return 1
    fi

    local LLVMARG=""
    grep -q '^CONFIG_CC_IS_CLANG=y' "$KDIR/.config" && LLVMARG="LLVM=1"

    echo "[$KVER] buduje sterownik (1-3 minuty)..."
    if ! make -C "$KDIR" M="$SRC" $LLVMARG -j"$(nproc)" modules > "$WORK/build.log" 2>&1; then
        tail -40 "$WORK/build.log"
        fail "kompilacja nie wyszla (log powyzej)"; return 1
    fi
    if [ ! -f "$SRC/ath12k.ko" ] || [ ! -f "$SRC/wifi7/ath12k_wifi7.ko" ]; then
        fail "po kompilacji brakuje plikow ath12k.ko / ath12k_wifi7.ko"; return 1
    fi

    mkdir -p "$DEST"
    install -m644 "$SRC/ath12k.ko" "$SRC/wifi7/ath12k_wifi7.ko" "$DEST/"
    touch "$DEST/.built"
    depmod -a "$KVER"
    rm -rf "$WORK"
    echo "[$KVER] GOTOWE - poprawiony sterownik zainstalowany."
    return 0
}

if [ "$1" = "--all" ]; then
    for d in /usr/lib/modules/*/; do
        K=$(basename "$d")
        # sprzatanie po usunietych kernelach
        if [ ! -f "$d/vmlinuz" ]; then
            rm -rf "$d/updates/ath12k-ccfix"
            rmdir "$d/updates" "$d" 2>/dev/null
            continue
        fi
        build_one "$K"
    done
    exit 0
fi

build_one "${1:-$(uname -r)}"
BUILD_EOF
chmod 755 "$BUILDER"

# ---------------- 2. PIERWSZENSTWO POPRAWIONEGO MODULU ----------------
mkdir -p "$(dirname "$DEPMODCONF")"
cat > "$DEPMODCONF" << 'DEPMOD_EOF'
# ath12k-ccfix: poprawiony sterownik WiFi ma pierwszenstwo przed oryginalnym
override ath12k * updates/ath12k-ccfix
override ath12k_wifi7 * updates/ath12k-ccfix
DEPMOD_EOF

# ---------------- 3. HOOK PACMANA (automatyczna przebudowa po aktualizacji kernela) ----------------
mkdir -p "$(dirname "$HOOK")"
cat > "$HOOK" << 'HOOK_EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux-cachyos-headers

[Action]
Description = ath12k-ccfix: buduje poprawiony sterownik WiFi dla nowego kernela...
When = PostTransaction
Exec = /usr/local/sbin/ath12k-ccfix-build --all
HOOK_EOF

# ---------------- 4. BUDOWA DLA OBECNEGO KERNELA ----------------
echo "=== Buduje poprawiony sterownik dla kernela $(uname -r) ==="
if ! "$BUILDER" "$(uname -r)"; then
    echo
    echo "Nie wyszlo - nic nie zostalo zmienione w sterowniku WiFi."
    echo "Wklej mi caly wynik powyzej."
    exit 1
fi

echo
reload_wifi
sleep 2
echo
echo "=== Uzywany sterownik (powinno byc .../updates/ath12k-ccfix/...) ==="
modinfo -n ath12k ath12k_wifi7
echo
echo "GOTOWE. Test: zamknij klape, odczekaj 20 s, otworz i po polaczeniu WiFi wpisz:"
echo "  journalctl -k -b | grep ccfix"
echo "  journalctl -b -t wifi-fast-resume --no-pager | tail -4"
