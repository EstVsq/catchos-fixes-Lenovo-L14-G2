#!/bin/bash
# touchpad-intertouch: przelacza touchpad Synaptics z trybu PS/2 na SMBus/RMI4
# (psmouse.synaptics_intertouch=1). Szybsze wybudzanie (~0,9 s -> ~0,6 s),
# zwykle tez lepsza obsluga touchpada.
#
# Instalacja:  sudo bash touchpad-intertouch-install.sh
# Usuniecie:   sudo bash touchpad-intertouch-install.sh usun

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0"
    exit 1
fi

CONF=/etc/modprobe.d/psmouse-intertouch.conf

reload_psmouse() {
    echo "Przeladowuje sterownik touchpada (zniknie na sekunde)..."
    modprobe -r psmouse && modprobe psmouse || echo "Nie udalo sie przeladowac - zadziala po restarcie."
}

if [ "$1" = "usun" ]; then
    rm -f "$CONF"
    reload_psmouse
    echo "Usunieto. Touchpad wrocil do trybu PS/2."
    exit 0
fi

echo 'options psmouse synaptics_intertouch=1' > "$CONF"
reload_psmouse
echo
echo "GOTOWE. Sprawdz, czy touchpad, przyciski i TrackPoint dzialaja normalnie."
echo "Jesli nie:  sudo bash $0 usun"
