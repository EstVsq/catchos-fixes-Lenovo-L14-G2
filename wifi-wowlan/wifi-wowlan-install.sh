#!/bin/bash
# wifi-wowlan: wlacza WoWLAN (budzenie przez WiFi, wyzwalacz: magic packet) dla karty
# Qualcomm WCN785x. Z wlaczonym WoWLAN sterownik ath12k nie wylacza karty calkowicie
# przy usypianiu, wiec po wybudzeniu firmware nie startuje od nowa (oszczednosc ~0,76 s)
# i nie zapomina kraju. Laptop dalej wchodzi w najglebszy sen (s0i3).
# Regula udev wlacza WoWLAN automatycznie przy kazdym pojawieniu sie karty.
#
# Instalacja:  sudo bash wifi-wowlan-install.sh
# Usuniecie:   sudo bash wifi-wowlan-install.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0"
    exit 1
fi

RULE=/etc/udev/rules.d/90-wifi-wowlan.rules

# karty ath12k (WCN785x) w systemie: nazwy interfejsow i phy
wifi_phys() {
    for n in /sys/class/net/*; do
        [ -e "$n/phy80211/name" ] || continue
        drv=$(basename "$(readlink -f "$n/device/driver")" 2>/dev/null)
        case "$drv" in ath12k*) cat "$n/phy80211/name" ;; esac
    done
}

if [ "$1" = "usun" ]; then
    rm -f "$RULE"
    udevadm control --reload
    for p in $(wifi_phys); do iw phy "$p" wowlan disable; done
    echo "Usunieto. WoWLAN wylaczone."
    exit 0
fi

if ! command -v iw >/dev/null; then
    echo "Brakuje programu iw:  sudo pacman -S --needed iw"
    exit 1
fi

cat > "$RULE" << 'RULE_EOF'
# wifi-wowlan: WoWLAN (magic packet) dla kart ath12k - firmware nie startuje od nowa po wybudzeniu
ACTION=="add", SUBSYSTEM=="net", ENV{DEVTYPE}=="wlan", DRIVERS=="ath12k*", RUN+="/bin/sh -c '/usr/bin/iw phy $$(cat /sys/class/net/%k/phy80211/name) wowlan enable magic-packet'"
RULE_EOF
udevadm control --reload

PHYS=$(wifi_phys)
if [ -z "$PHYS" ]; then
    echo "Nie znaleziono karty ath12k - regula zapisana, zadziala po jej pojawieniu sie."
    exit 0
fi
for p in $PHYS; do
    iw phy "$p" wowlan enable magic-packet
    echo "[$p] $(iw phy "$p" wowlan show | head -1)"
done

echo
echo "GOTOWE. WoWLAN wlacza sie teraz automatycznie przy kazdym starcie."
