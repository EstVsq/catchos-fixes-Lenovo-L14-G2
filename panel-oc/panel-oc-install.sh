#!/bin/bash
# panel-oc: wlasny tryb odswiezania wbudowanej matrycy (odpowiednik CRU z Windowsa).
# Robi kopie EDID matrycy z dodatkowym trybem (wolne miejsce w EDID, deskryptor 3)
# i kaze kernelowi ladowac ja zamiast oryginalu (drm.edid_firmware, Limine + initramfs).
# Tryb domyslny (preferowany) zostaje 60 Hz - po starcie zawsze jest bezpieczne 60 Hz,
# nowy tryb wybierasz recznie (KDE / kscreen-doctor).
#
# Matryca L14 Gen 2a (BOE 0x0AAA), fabrycznie 60 Hz:
#   zegar 147,06 MHz | H: 1920 aktywne, front 48, sync 32, back 150 (razem 2150)
#                    | V: 1080 aktywne, front 3,  sync 6,  back 51  (razem 1140) | +HSync -VSync
#
# Uzycie:
#   sudo bash panel-oc-install.sh 65          - 65 Hz na fabrycznych parametrach (podnosi tylko zegar, jak "LCD native" w CRU)
#   sudo bash panel-oc-install.sh 70 reduced  - 70 Hz z krotszym pionowym wygaszaniem (nizszy zegar pikseli)
#   sudo bash panel-oc-install.sh manual ZEGAR_kHz HFP HSW HBP VFP VSW VBP HPOL VPOL
#        np.: sudo bash panel-oc-install.sh manual 159320 48 32 150 3 6 51 + -
#   sudo bash panel-oc-install.sh usun        - powrot do oryginalnego EDID
# Po kazdej zmianie: reboot.

if [ "$(id -u)" -ne 0 ]; then
    echo "Uruchom przez sudo:  sudo bash $0 ..."
    exit 1
fi

FW=/usr/lib/firmware/edid
ORIG=$FW/panel-original.bin
OUT=$FW/panel-oc.bin
MKCONF=/etc/mkinitcpio.conf.d/panel-oc.conf
LIM=/etc/default/limine
PARAM='KERNEL_CMDLINE[default]+=" drm.edid_firmware=eDP-1:edid/panel-oc.bin"'

if [ "$1" = "usun" ]; then
    sed -i '/drm.edid_firmware=eDP-1:edid\/panel-oc.bin/d' "$LIM"
    rm -f "$MKCONF" "$OUT"
    limine-mkinitcpio >/dev/null && echo "Usunieto. Po restarcie dziala oryginalny EDID (60 Hz). Zrob:  reboot"
    exit 0
fi

[ -n "$1" ] || { sed -n '2,22p' "$0"; exit 1; }
[ -f "$LIM" ] || { echo "Brak $LIM - skrypt obsluguje tylko Limine."; exit 1; }

# ---------------- 1. KOPIA ORYGINALNEGO EDID ----------------
mkdir -p "$FW"
if [ ! -f "$ORIG" ]; then
    if grep -q 'panel-oc.bin' /proc/cmdline; then
        echo "Dziala juz zmieniony EDID, a brak kopii oryginalu ($ORIG). Najpierw: sudo bash $0 usun, reboot."
        exit 1
    fi
    E=$(ls /sys/class/drm/card*-eDP-1/edid 2>/dev/null | head -1)
    [ -n "$E" ] || { echo "Nie znaleziono wbudowanego ekranu eDP-1."; exit 1; }
    head -c 128 "$E" > "$ORIG"
    echo "Zapisano oryginalny EDID: $ORIG"
fi

# ---------------- 2. NOWY EDID ----------------
python3 -I - "$ORIG" "$OUT" "$@" << 'PY_EOF' || exit 1
import sys
src, dst, args = sys.argv[1], sys.argv[2], sys.argv[3:]
b = bytearray(open(src, "rb").read()[:128])
if len(b) != 128 or b[:8] != bytes.fromhex("00ffffffffffff00"):
    sys.exit("Oryginalny EDID jest uszkodzony.")

# fabryczne parametry z pierwszego deskryptora (DTD1)
d = b[54:72]
pclk = (d[0] | d[1] << 8) * 10
ha = d[2] | ((d[4] & 0xf0) << 4); hb = d[3] | ((d[4] & 0x0f) << 8)
va = d[5] | ((d[7] & 0xf0) << 4); vb = d[6] | ((d[7] & 0x0f) << 8)
hfp = d[8] | ((d[11] & 0xc0) << 2); hsw = d[9] | ((d[11] & 0x30) << 4)
vfp = (d[10] >> 4) | ((d[11] & 0x0c) << 2); vsw = (d[10] & 0x0f) | ((d[11] & 0x03) << 4)
hbp, vbp = hb - hfp - hsw, vb - vfp - vsw
hpos, vpos = bool(d[17] & 2), bool(d[17] & 4)

if args[0] == "manual":
    if len(args) != 10:
        sys.exit("manual: ZEGAR_kHz HFP HSW HBP VFP VSW VBP HPOL(+/-) VPOL(+/-)")
    pclk = int(args[1]); hfp, hsw, hbp, vfp, vsw, vbp = map(int, args[2:8])
    hpos, vpos = args[8] == "+", args[9] == "+"
else:
    hz = float(args[0].replace(",", "."))
    if not 30 <= hz <= 120:
        sys.exit("Podaj odswiezanie 30-120 Hz.")
    if len(args) > 1 and args[1] == "reduced":
        vbp = 11            # krotsze pionowe wygaszanie (back porch 51 -> 11)
    ht = ha + hfp + hsw + hbp; vt = va + vfp + vsw + vbp
    pclk = round(ht * vt * hz / 10000) * 10   # kHz, krok 10 kHz

ht = ha + hfp + hsw + hbp; vt = va + vfp + vsw + vbp
hb, vb = ht - ha, vt - va
real = pclk * 1000 / (ht * vt)
for name, v, lim in (("HFP", hfp, 1023), ("HSW", hsw, 1023), ("VFP", vfp, 63), ("VSW", vsw, 63), ("HBLANK", hb, 4095), ("VBLANK", vb, 4095)):
    if not 0 <= v <= lim:
        sys.exit(f"{name}={v} poza zakresem EDID (0-{lim}).")
if pclk > 655350:
    sys.exit("Zegar pikseli za duzy.")

t = bytearray(18)
p = pclk // 10
t[0], t[1] = p & 0xff, p >> 8
t[2], t[3], t[4] = ha & 0xff, hb & 0xff, ((ha >> 8) << 4) | (hb >> 8)
t[5], t[6], t[7] = va & 0xff, vb & 0xff, ((va >> 8) << 4) | (vb >> 8)
t[8], t[9] = hfp & 0xff, hsw & 0xff
t[10] = ((vfp & 0x0f) << 4) | (vsw & 0x0f)
t[11] = ((hfp >> 8) << 6) | ((hsw >> 8) << 4) | ((vfp >> 4) << 2) | (vsw >> 4)
t[12:17] = b[66:71]          # rozmiar obrazu w mm i ramki - jak w oryginale
t[17] = 0x18 | (0x04 if vpos else 0) | (0x02 if hpos else 0)

# wolne miejsce: deskryptor 3 (offset 90), jesli pusty; inaczej zastepujemy DTD2
slot = 90 if not any(b[90:108]) else 72
b[slot:slot + 18] = t
b[126] = 0                    # bez bloku rozszerzen (w tej matrycy i tak jest pusty)
b[127] = (256 - sum(b[:127]) % 256) % 256
open(dst, "wb").write(bytes(b))
print(f"Nowy tryb: {ha}x{va} @ {real:.2f} Hz | zegar {pclk/1000:.2f} MHz | "
      f"H {ha}/{hfp}/{hsw}/{hbp} (razem {ht}) | V {va}/{vfp}/{vsw}/{vbp} (razem {vt}) | "
      f"{'+' if hpos else '-'}HSync {'+' if vpos else '-'}VSync | deskryptor {1 + (slot - 54) // 18}")
PY_EOF

# ---------------- 3. INITRAMFS + PARAMETR KERNELA ----------------
mkdir -p "$(dirname "$MKCONF")"
echo "FILES+=($OUT)" > "$MKCONF"
grep -qF 'drm.edid_firmware=eDP-1:edid/panel-oc.bin' "$LIM" || echo "$PARAM" >> "$LIM"
limine-mkinitcpio >/dev/null || { echo "limine-mkinitcpio nie wyszedl."; exit 1; }

if grep -rq 'drm.edid_firmware=eDP-1:edid/panel-oc.bin' /boot --include=limine.conf; then
    echo
    echo "GOTOWE. Zrob restart:  reboot"
    echo "Po restarcie ekran startuje na 60 Hz. Nowy tryb wlaczysz:"
    echo "  kscreen-doctor -o | grep -o 'Modes:.*'      (znajdz numer trybu z nowymi Hz)"
    echo "  kscreen-doctor output.eDP-1.mode.NUMER"
    echo "Jesli cos nie gra:  sudo bash $0 usun  i reboot"
else
    echo "BLAD: parametr nie trafil do /boot/limine.conf."
    exit 1
fi
