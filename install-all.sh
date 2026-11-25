#!/bin/bash
# Instaluje wszystkie poprawki naraz (np. po swiezej instalacji CachyOS).
#   sudo bash install-all.sh
# Usuwa wszystkie poprawki:
#   sudo bash install-all.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0"
    exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"

if [ "$1" = "usun" ]; then
    bash "$DIR/wifi-fast-resume/wifi-fast-resume-install.sh" usun
    bash "$DIR/ath12k-ccfix/ath12k-ccfix-install.sh" usun
    bash "$DIR/iommu-fix/iommu-fix-install.sh" usun
    echo
    echo "Wszystko usuniete. Zrob restart:  reboot"
    exit 0
fi

echo "=== 0/3 Pakiety potrzebne do budowania sterownika ==="
pacman -S --needed --noconfirm linux-cachyos-headers clang llvm lld python curl tar xz make || {
    echo "Nie udalo sie zainstalowac pakietow - sprawdz internet i sprobuj ponownie."
    exit 1
}

echo
echo "=== 1/3 Szybkie wybudzanie systemu (iommu=pt) ==="
bash "$DIR/iommu-fix/iommu-fix-install.sh" || echo "!!! iommu-fix nie wyszedl - patrz wyzej"

echo
echo "=== 2/3 Poprawiony sterownik WiFi ath12k (kraj po wybudzeniu) ==="
bash "$DIR/ath12k-ccfix/ath12k-ccfix-install.sh" || echo "!!! ath12k-ccfix nie wyszedl - patrz wyzej"

echo
echo "=== 3/3 Szybkie laczenie WiFi po wybudzeniu ==="
bash "$DIR/wifi-fast-resume/wifi-fast-resume-install.sh" || echo "!!! wifi-fast-resume nie wyszedl - patrz wyzej"

echo
echo "KONIEC. Zrob restart:  reboot"
