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
    bash "$DIR/easyeffects-l14/easyeffects-l14-install.sh" usun
    bash "$DIR/touchpad-intertouch/touchpad-intertouch-install.sh" usun
    bash "$DIR/lte-modem/lte-modem-install.sh" usun
    bash "$DIR/wifi-fast-resume/wifi-fast-resume-install.sh" usun
    bash "$DIR/ath12k-ccfix/ath12k-ccfix-install.sh" usun
    bash "$DIR/iommu-fix/iommu-fix-install.sh" usun
    echo
    echo "Wszystko usuniete. Zrob restart:  reboot"
    exit 0
fi

echo "=== 0/6 Pakiety potrzebne do budowania sterownika ==="
pacman -S --needed --noconfirm linux-cachyos-headers clang llvm lld python curl tar xz make || {
    echo "Nie udalo sie zainstalowac pakietow - sprawdz internet i sprobuj ponownie."
    exit 1
}

echo
echo "=== 1/6 Szybkie wybudzanie systemu (iommu=pt) ==="
bash "$DIR/iommu-fix/iommu-fix-install.sh" || echo "!!! iommu-fix nie wyszedl - patrz wyzej"

has_wcn785x() {
    for d in /sys/bus/pci/devices/*; do
        [ "$(cat "$d/vendor" 2>/dev/null)" = "0x17cb" ] && \
        [ "$(cat "$d/device" 2>/dev/null)" = "0x1107" ] && return 0
    done
    return 1
}

# Poprawki WiFi (2 i 3) tylko dla karty WiFi 7 Qualcomm WCN785x (PCI 17cb:1107)
if has_wcn785x; then
    echo
    echo "=== 2/6 Poprawiony sterownik WiFi ath12k (kraj po wybudzeniu) ==="
    bash "$DIR/ath12k-ccfix/ath12k-ccfix-install.sh" || echo "!!! ath12k-ccfix nie wyszedl - patrz wyzej"

    echo
    echo "=== 3/6 Szybkie laczenie WiFi po wybudzeniu ==="
    bash "$DIR/wifi-fast-resume/wifi-fast-resume-install.sh" || echo "!!! wifi-fast-resume nie wyszedl - patrz wyzej"
else
    echo
    echo "=== 2/6 i 3/6 POMINIETE: brak karty WiFi 7 Qualcomm WCN785x (PCI 17cb:1107) ==="
    echo "Poprawki WiFi sa tylko dla tej karty (np. Quectel NCM865 / QCNCM865)."
fi

echo
echo "=== 4/6 Touchpad w trybie SMBus/RMI4 (szybsze wybudzanie) ==="
bash "$DIR/touchpad-intertouch/touchpad-intertouch-install.sh" || echo "!!! touchpad-intertouch nie wyszedl - patrz wyzej"

echo
echo "=== 5/6 Modem LTE Quectel EM120R-GL (ModemManager, FCC, SIM, polaczenie LTE) ==="
bash "$DIR/lte-modem/lte-modem-install.sh" || echo "!!! lte-modem nie wyszedl - patrz wyzej"

echo
echo "=== 6/6 Preset EasyEffects dla glosnikow (krzywa z Windows) ==="
bash "$DIR/easyeffects-l14/easyeffects-l14-install.sh" || echo "!!! easyeffects-l14 nie wyszedl - patrz wyzej"

echo
echo "KONIEC. Zrob restart:  reboot"
