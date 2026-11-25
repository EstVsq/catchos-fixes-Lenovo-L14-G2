#!/bin/bash
# iommu-fix: dopisuje parametr kernela iommu=pt (bootloader Limine, CachyOS).
# Omija blad BIOS-u Lenovo: przy wybudzaniu z s2idle procedura SMI dla dysku NVMe
# przy wlaczonym IOMMU blokuje wybudzanie na ~10 s. Kernel ma na to poprawke
# (amd_pmc), ale nie obejmuje typu 20X6 (ThinkPad L14 Gen 2a).
#
# Instalacja:  sudo bash iommu-fix-install.sh
# Usuniecie:   sudo bash iommu-fix-install.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0"
    exit 1
fi

F=/etc/default/limine
LINE='KERNEL_CMDLINE[default]+=" iommu=pt"'

if [ ! -f "$F" ]; then
    echo "Nie znaleziono $F - ten skrypt obsluguje tylko bootloader Limine."
    echo "Przy innym bootloaderze dopisz parametr iommu=pt recznie."
    exit 1
fi

if [ "$1" = "usun" ]; then
    sed -i '/^KERNEL_CMDLINE\[default\]+=" iommu=pt"$/d' "$F"
    limine-mkinitcpio
    echo
    echo "Usunieto iommu=pt. Zrob restart:  reboot"
    exit 0
fi

PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
case "$PRODUCT" in
    20X6*|20X5*) ;;
    *) echo "UWAGA: to nie jest ThinkPad L14 Gen 2a (typ: $PRODUCT). Poprawka byla robiona pod ten model." ;;
esac

if grep -qF "$LINE" "$F"; then
    echo "iommu=pt jest juz w $F - nic nie zmieniam."
else
    cp "$F" "$F.bak"
    echo "$LINE" >> "$F"
    echo "Dopisano iommu=pt (kopia zapasowa: $F.bak)."
    limine-mkinitcpio
fi

echo
if grep -rq 'iommu=pt' /boot --include=limine.conf; then
    echo "OK: iommu=pt jest w konfiguracji startowej Limine."
    if grep -qw 'iommu=pt' /proc/cmdline; then
        echo "iommu=pt juz dziala (jest w /proc/cmdline)."
    else
        echo "Zrob restart, zeby zadzialalo:  reboot"
    fi
else
    echo "BLAD: iommu=pt nie trafilo do /boot/limine.conf - sprawdz wynik limine-mkinitcpio powyzej."
    exit 1
fi
