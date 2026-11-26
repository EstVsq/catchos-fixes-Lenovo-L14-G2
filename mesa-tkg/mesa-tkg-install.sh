#!/bin/bash
# mesa-tkg: sterownik grafiki Mesa (wersja rozwojowa, mesa-git-tkg od Frogging-Family)
# zbudowany pod ten laptop: tylko sterowniki AMD, -O3 -march=native, bez rusticl i LTO.
#
# Zabezpieczenie: Mesa korzysta z biblioteki LLVM. Gdy pacman aktualizuje LLVM do nowej
# wersji glownej, stara biblioteka znika i pulpit by nie wstal. Hook pacmana przed
# aktualizacja kopiuje stara biblioteke LLVM (/usr/local/lib/mesa-tkg-llvm), wiec sterownik
# dziala dalej, a pacman przypomina o przebudowie.
#
# Instalacja / zabezpieczenie:  sudo bash mesa-tkg-install.sh
# Przebudowa (nowsza Mesa):     sudo bash mesa-tkg-install.sh przebuduj
# Powrot do zwyklej Mesy:       sudo bash mesa-tkg-install.sh usun

if [ "$(id -u)" -ne 0 ] || [ -z "$SUDO_USER" ] || [ "$SUDO_USER" = "root" ]; then
    echo "Uruchom jako zwykly uzytkownik przez sudo:  sudo bash $0"
    exit 1
fi

U="$SUDO_USER"
UHOME=$(getent passwd "$U" | cut -d: -f6)
SRC="$UHOME/mesa-tkg"
CFG="$UHOME/.config/frogminer/mesa-git.cfg"
KEEP=/usr/local/sbin/mesa-tkg-keep-llvm
CHECK=/usr/local/sbin/mesa-tkg-check
HOOKPRE=/etc/pacman.d/hooks/40-mesa-tkg-keep-llvm.hook
HOOKPOST=/etc/pacman.d/hooks/95-mesa-tkg-check.hook
LDCONF=/etc/ld.so.conf.d/mesa-tkg-llvm.conf

has_lib32() { pacman -Q lib32-mesa >/dev/null 2>&1 || pacman -Q lib32-mesa-tkg-git >/dev/null 2>&1; }

# ---------------- USUWANIE: powrot do zwyklej Mesy ----------------
if [ "$1" = "usun" ]; then
    PKGS="mesa vulkan-radeon"
    pacman -Q lib32-mesa-tkg-git >/dev/null 2>&1 && PKGS="$PKGS lib32-mesa lib32-vulkan-radeon"
    echo "Instaluje zwykla Mese ($PKGS). Na pytanie o usuniecie mesa-tkg-git odpowiedz: y"
    pacman -S $PKGS || exit 1
    rm -f "$KEEP" "$CHECK" "$HOOKPRE" "$HOOKPOST" "$LDCONF"
    rm -rf /usr/local/lib/mesa-tkg-llvm /usr/local/lib32/mesa-tkg-llvm
    ldconfig
    echo
    echo "Usunieto. Dziala zwykla Mesa. Zrob restart:  reboot"
    echo "(Zrodla zostaly w $SRC - mozesz je usunac: rm -rf ~/mesa-tkg)"
    exit 0
fi

# ---------------- 1. ZABEZPIECZENIE LLVM ----------------
cat > "$KEEP" << 'KEEP_EOF'
#!/bin/bash
# Przed aktualizacja LLVM: kopia biblioteki libLLVM, z ktorej korzysta mesa-tkg.
for arch in lib lib32; do
    G=$(ls /usr/$arch/libgallium-*.so 2>/dev/null | head -1)
    [ -n "$G" ] || continue
    pacman -Qo "$G" 2>/dev/null | grep -q 'mesa-tkg-git' || continue
    NEED=$(readelf -d "$G" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(libLLVM[^]]*\)\].*/\1/p' | head -1)
    [ -n "$NEED" ] || continue
    if [ -e "/usr/$arch/$NEED" ]; then
        mkdir -p "/usr/local/$arch/mesa-tkg-llvm"
        cp -L "/usr/$arch/$NEED" "/usr/local/$arch/mesa-tkg-llvm/$NEED"
        echo "mesa-tkg: zachowano kopie $arch/$NEED (sterownik zadziala po aktualizacji LLVM)"
    fi
done
exit 0
KEEP_EOF
chmod 755 "$KEEP"

cat > "$CHECK" << 'CHECK_EOF'
#!/bin/bash
# Po aktualizacji: czy mesa-tkg korzysta z kopii starego LLVM? Jesli tak - przypomnij o przebudowie.
ldconfig
OLD=0
for arch in lib lib32; do
    G=$(ls /usr/$arch/libgallium-*.so 2>/dev/null | head -1)
    [ -n "$G" ] || continue
    pacman -Qo "$G" 2>/dev/null | grep -q 'mesa-tkg-git' || continue
    NEED=$(readelf -d "$G" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(libLLVM[^]]*\)\].*/\1/p' | head -1)
    [ -n "$NEED" ] || continue
    if [ ! -e "/usr/$arch/$NEED" ]; then
        if [ -e "/usr/local/$arch/mesa-tkg-llvm/$NEED" ]; then
            OLD=1
        else
            echo "!!! mesa-tkg: BRAK $NEED - pulpit moze nie wstac. Przebuduj teraz (ponizej) albo wroc do zwyklej Mesy."
            OLD=1
        fi
    else
        # sterownik zgodny z obecnym LLVM - stare kopie niepotrzebne
        find "/usr/local/$arch/mesa-tkg-llvm" -name 'libLLVM*' ! -name "$NEED" -delete 2>/dev/null
        rm -f "/usr/local/$arch/mesa-tkg-llvm/$NEED"
    fi
done
ldconfig
if [ "$OLD" = "1" ]; then
    echo
    echo "=============================================================="
    echo " mesa-tkg: LLVM zostalo zaktualizowane. Sterownik dziala na kopii"
    echo " starej biblioteki. Przebuduj go, kiedy ci wygodnie:"
    echo "   cd ~/catchos-fixes && sudo bash mesa-tkg/mesa-tkg-install.sh przebuduj"
    echo "=============================================================="
fi
exit 0
CHECK_EOF
chmod 755 "$CHECK"

mkdir -p /etc/pacman.d/hooks
cat > "$HOOKPRE" << 'PRE_EOF'
[Trigger]
Operation = Upgrade
Operation = Remove
Type = Package
Target = llvm-libs
Target = lib32-llvm-libs

[Action]
Description = mesa-tkg: zachowuje stara biblioteke LLVM dla sterownika grafiki...
When = PreTransaction
Exec = /usr/local/sbin/mesa-tkg-keep-llvm
PRE_EOF

cat > "$HOOKPOST" << 'POST_EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = llvm-libs
Target = lib32-llvm-libs
Target = mesa-tkg-git
Target = lib32-mesa-tkg-git

[Action]
Description = mesa-tkg: sprawdza zgodnosc sterownika grafiki z LLVM...
When = PostTransaction
Exec = /usr/local/sbin/mesa-tkg-check
POST_EOF

printf '/usr/local/lib/mesa-tkg-llvm\n/usr/local/lib32/mesa-tkg-llvm\n' > "$LDCONF"
echo "Zabezpieczenie LLVM zainstalowane (hooki pacmana)."

# ---------------- 2. CZY BUDOWAC? ----------------
if pacman -Q mesa-tkg-git >/dev/null 2>&1 && [ "$1" != "przebuduj" ]; then
    echo
    echo "mesa-tkg-git juz jest zainstalowana: $(pacman -Q mesa-tkg-git)"
    echo "Przebudowa (nowsza Mesa / po aktualizacji LLVM):  sudo bash $0 przebuduj"
    exit 0
fi

# ---------------- 3. KONFIGURACJA ----------------
pacman -S --needed --noconfirm base-devel git >/dev/null || { echo "Nie udalo sie zainstalowac base-devel/git"; exit 1; }

if [ -d "$SRC/.git" ]; then
    sudo -u "$U" -H git -C "$SRC" pull -q || { echo "git pull nie wyszedl"; exit 1; }
else
    sudo -u "$U" -H git clone -q https://github.com/Frogging-Family/mesa-git.git "$SRC" || { echo "git clone nie wyszedl"; exit 1; }
fi

if [ ! -f "$CFG" ]; then
    sudo -u "$U" -H mkdir -p "$(dirname "$CFG")"
    sudo -u "$U" -H cp "$SRC/customization.cfg" "$CFG"
    sudo -u "$U" -H sed -i \
        -e 's/^_gallium_drivers=.*/_gallium_drivers="radeonsi,llvmpipe,softpipe,zink"/' \
        -e 's/^_vulkan_drivers=.*/_vulkan_drivers="amd,swrast"/' \
        -e 's/^_lto=.*/_lto="false"/' \
        -e 's/^_rusticl=.*/_rusticl="false"/' \
        -e 's/^_NUKR=.*/_NUKR="true"/' "$CFG"
    has_lib32 || sudo -u "$U" -H sed -i 's/^_lib32=.*/_lib32=false/' "$CFG"
    echo '_custom_opt_flags="-march=native -O3"' | sudo -u "$U" -H tee -a "$CFG" >/dev/null
    echo "Utworzono konfiguracje: $CFG"
else
    echo "Konfiguracja juz istnieje: $CFG (nie zmieniam)"
fi

# ---------------- 4. BUDOWA (jako zwykly uzytkownik) ----------------
echo
echo "=== Buduje mesa-tkg (15-30 min, laptop bedzie glosny) ==="
if ! sudo -u "$U" -H bash -c "cd '$SRC' && makepkg -s -f --noconfirm"; then
    echo "Kompilacja nie wyszla - nic nie zostalo zmienione w sterowniku."
    exit 1
fi

mapfile -t PKGFILES < <(sudo -u "$U" -H bash -c "cd '$SRC' && makepkg --packagelist" | grep -v -- '-debug-')
EXIST=()
for f in "${PKGFILES[@]}"; do [ -f "$f" ] && EXIST+=("$f"); done
if [ ${#EXIST[@]} -eq 0 ]; then
    echo "Nie znaleziono zbudowanych paczek."; exit 1
fi

echo
echo "=== Instaluje: ${EXIST[*]##*/} ==="
if pacman -Q mesa-tkg-git >/dev/null 2>&1; then
    pacman -U --noconfirm "${EXIST[@]}" || exit 1
else
    echo "Na pytanie o zastapienie mesa / vulkan-radeon odpowiedz: y"
    pacman -U "${EXIST[@]}" || exit 1
fi

echo
echo "GOTOWE: $(pacman -Q mesa-tkg-git). Zrob restart:  reboot"
