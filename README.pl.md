# catchos-fixes-Lenovo-L14-G2

[English](README.md) | **Polski**

Poprawki dla **CachyOS** na **ThinkPad L14 Gen 2a (AMD, typ 20X6)** z kartą WiFi
**Qualcomm FastConnect 7800 (WCN785x, sterownik ath12k)**.

> **Poprawki WiFi (`ath12k-ccfix`, `wifi-fast-resume`) są tylko dla karty WiFi 7 Qualcomm
> WCN785x / FastConnect 7800** (np. Quectel NCM865 / QCNCM865, PCI ID `17cb:1107`), założonej
> zamiast fabrycznej karty WiFi. Z każdą inną kartą nie są potrzebne – `install-all.sh` sam
> wykrywa kartę i je pomija. `iommu-fix` i `easyeffects-l14` działają niezależnie od karty WiFi.
>
> Sprawdź, jaką masz kartę:
> ```
> lspci -nn | grep -i network
> ```
> Jeśli w linijce jest `[17cb:1107]`, masz tę kartę.

| Poprawka | Problem | Przed | Po |
|---|---|---|---|
| `iommu-fix` | Wybudzanie z uśpienia blokuje się na ~10 s (błąd BIOS-u Lenovo przy NVMe + IOMMU) | ~12 s | ~1,8 s |
| `ath12k-ccfix` | Po wybudzeniu firmware WiFi zapomina kraj i przez ~7 s go odgaduje | 16 s | — |
| `wifi-fast-resume` | NetworkManager długo skanuje 6 GHz zamiast od razu się połączyć | — | razem z ath12k-ccfix: **~1,2 s** do WiFi |
| `touchpad-intertouch` | Touchpad Synaptics działa w starym trybie PS/2 i wolno się budzi | ~0,92 s | ~0,62 s |
| `ryzen-power` | Lenovo ogranicza Ryzen 7 PRO 5850U do 25 W pod dłuższym obciążeniem (przy temperaturze ledwie ~70 °C) | 2,92 GHz wszystkie rdzenie | **3,12 GHz (+7%)**, 30 W |
| `lte-modem` | Modem LTE Quectel EM120R-GL jest niewidoczny (ModemManager wyłączony, blokada FCC) i zgłasza `sim-missing` mimo włożonej karty | brak LTE | LTE łączy się samo |
| `easyeffects-l14` | Głośniki brzmią płasko i piskliwie (brak strojenia Dolby z Windows), przy podgłaśnianiu przester | przester ponad 6 dB przez 13% czasu | **0%**, krzywa z Windows ±0,17 dB |

---

## Instalacja po świeżej instalacji systemu (od A do Z)

Wszystkie komendy działają w fish.

**1. Zainstaluj git i GitHub CLI:**
```
sudo pacman -S --needed git github-cli
```

**2. Zaloguj się do GitHuba** (repo jest prywatne):
```
gh auth login
```
Wybierz po kolei: `GitHub.com` → `HTTPS` → `Yes` → `Login with a web browser`.
Skopiuj pokazany kod, wciśnij Enter, w przeglądarce wklej kod i zatwierdź.

**3. Pobierz repo:**
```
gh repo clone EstVsq/catchos-fixes-Lenovo-L14-G2 ~/catchos-fixes
```

**4. Zainstaluj wszystko naraz** (razem z presetem EasyEffects):
```
cd ~/catchos-fixes
```
```
sudo bash install-all.sh
```
Potrwa kilka minut (pobiera źródła kernela ok. 150 MB i kompiluje sterownik WiFi).

**5. Restart:**
```
reboot
```

**6. Test:** zamknij klapę, odczekaj 20 s, otwórz i po połączeniu WiFi:
```
journalctl -k -b | grep ccfix
```
```
journalctl -b -t wifi-fast-resume --no-pager | tail -3
```
Powinno być `restored country code PL after resume` i `WiFi polaczone po ~1700 ms`.

> Bez `gh`: na github.com wejdź w repo → zielony przycisk **Code** → **Download ZIP**,
> rozpakuj do `~/catchos-fixes` i od kroku 4 tak samo.

---

## Preset EasyEffects dla głośników (`easyeffects-l14`)

Sam preset (bez reszty poprawek):
```
cd ~/catchos-fixes
```
```
sudo bash easyeffects-l14/easyeffects-l14-install.sh
```
Skrypt instaluje EasyEffects z wtyczkami (`lsp-plugins-lv2`, `calf`) i kopiuje preset
`L14-windows` do Twojego katalogu domowego. Jeśli EasyEffects działa, od razu go wczytuje;
jeśli nie – uruchom EasyEffects i wybierz **Presety → L14-windows**.

Sprawdź w EasyEffects:
- **Korektor:** 16 pasm, tryb **APO (DR)**
- **Kompresor wielopasmowy → pasmo 0:** sidechain **Peak**, lookahead **5 ms**

Głośność reguluj **tylko** suwakiem **Limiter → Input gain** (domyślnie +12,5 dB).

| Problem | Co zmienić |
|---|---|
| Wszystko za cicho | Limiter → Input gain **+13,5** |
| Bas za słaby | Kompresor wielopasmowy → pasmo 0 → Threshold **-15** |
| Bas „charczy” | Kompresor wielopasmowy → pasmo 0 → Threshold **-21** |

Preset jest pod **wbudowane głośniki** – na słuchawkach wybierz inny preset albo wyłącz efekty.

Łańcuch: Korektor → Bass enhancer → Filtr 165 Hz → Stereo Tools → Kompresor wielopasmowy → Limiter.
- **Korektor:** 16 pasm dopasowanych do odpowiedzi impulsowej głośników z Windows (192 próbki, 48 kHz);
  błąd maks. 0,17 dB. Same cięcia (szczyt 0 dB), więc korektor sam nie przesteruje.
- **Kompresor wielopasmowy:** pasmo basu (< 300 Hz) działa jak ogranicznik basu (Peak, lookahead 5 ms),
  żeby stopa perkusji nie ściszała całej muzyki w limiterze. Strojone na nagraniach radia i YouTube.
- **Limiter:** tylko bezpiecznik – na głośnym radiu ścisza > 6 dB przez 0% czasu (było 13%).

---

## Limit mocy 30 W (`ryzen-power`)

Podnosi limit mocy procesora (PPT SLOW) z 25 W ustawionych przez Lenovo do **30 W** – to maksimum, które
ten laptop przyjmuje (STAPM ma twardy sufit 30 W; 35 W jest od razu obcinane do 30). Zmierzone przy
obciążeniu wszystkich 16 wątków: 2,92 → 3,12 GHz (**+7%**), ~85 °C po 3 minutach, wentylator ~4150 zamiast
~3100 obr./min. Procesor i grafika dzielą jeden budżet mocy, więc grafika też trochę zyskuje.
Przy zwykłej pracy (przeglądarka, edytor) różnicy nie ma.

Działa **tylko na zasilaczu i w trybie zasilania „Wydajność”**; na baterii i w innych trybach obowiązują
limity Lenovo. Sprawdzane przy starcie, po wybudzeniu i co 20 s (Lenovo potrafi przywrócić swoje limity).
Jeśli brakuje `ryzenadj`, instalator buduje go ze źródeł (github.com/FlyGoat/RyzenAdj).

Sprawdzenie:
```
sudo ryzenadj -i 2>/dev/null | grep -E 'STAPM LIMIT|PPT LIMIT (FAST|SLOW)'
```
```
journalctl -t ryzen-power
```
Wartości (W, °C) są na początku pliku `/usr/local/sbin/ryzen-power-apply`.

## Modem LTE (`lte-modem`)

Tylko dla modemu **Quectel EM120R-GL** (PCI `1eac:1001`); bez niego skrypt nic nie robi.
`install-all.sh` ustawia go z APN `a2mobile.pl`. Z inną kartą/operatorem podaj swój APN:
```
sudo bash lte-modem/lte-modem-install.sh internet
```
Skrypt włącza ModemManager, zdejmowanie blokady FCC, ustawia w modemie gniazdo SIM nr 1 i wyłącza
wykrywanie karty przez styk (bez tego modem zgłasza `sim-missing` mimo włożonej karty) oraz tworzy
połączenie NetworkManagera **LTE** (IPv4, łączy się samo; WiFi ma pierwszeństwo).

Sprawdzenie:
```
mmcli -m any | grep -E 'state:|signal quality|operator name'
```
`connected` + nazwa operatora = działa. Używaj `-m any`, nie `-m 0` – po każdym uśpieniu modem dostaje nowy numer.

> Nie znasz APN? Połącz się raz i odczytaj, co przydzieliła sieć:
> `sudo systemctl stop ModemManager`, potem
> `sudo bash -c 'exec 3<>/dev/wwan0at0; printf "AT+CGCONTRDP=1\r" >&3; timeout 3 cat <&3'`
> (APN to trzecie pole), na koniec `sudo systemctl start ModemManager`.

## Co z nowym kernelem?

Nic nie trzeba robić:

- **iommu-fix** – parametr siedzi w `/etc/default/limine`, a Limine dodaje go do każdego nowego kernela.
- **ath12k-ccfix** – hook pacmana (`/etc/pacman.d/hooks/90-ath12k-ccfix.hook`) po każdej aktualizacji
  `linux-cachyos-headers` sam pobiera źródła nowego kernela, nakłada poprawkę i buduje sterownik.
  Aktualizacja kernela trwa przez to kilka minut dłużej i **wymaga internetu**.
  Jeśli budowa się nie uda (np. kod sterownika się zmienił), automatycznie działa oryginalny
  sterownik – WiFi działa, tylko po wybudzeniu łączy się wolniej (~8 s).
- **wifi-fast-resume** – zwykły skrypt, nie zależy od kernela.
- **touchpad-intertouch** – opcja modułu (`/etc/modprobe.d/psmouse-intertouch.conf`), nie zależy od kernela.
- **ryzen-power** – usługa i timer systemd, nie zależy od kernela.
- **lte-modem** – ustawienia siedzą w ModemManagerze, NetworkManagerze i w samym modemie, nie zależą od kernela.

Sprawdzenie, który sterownik WiFi działa:
```
modinfo -n ath12k ath12k_wifi7
```
Ścieżka z `updates/ath12k-ccfix` = poprawiony. Z `kernel/drivers/...` = oryginalny.

Ręczne przebudowanie (np. gdy aktualizacja szła bez internetu):
```
sudo /usr/local/sbin/ath12k-ccfix-build
```
Potem restart albo przeładowanie WiFi:
```
sudo modprobe -r ath12k_wifi7; sudo modprobe ath12k_wifi7
```

Kernel LTS (`linux-cachyos-lts`) nie jest objęty poprawką sterownika – działa na oryginalnym.

---

## Usuwanie

Wszystko naraz:
```
sudo bash install-all.sh usun
```
Albo pojedynczo, np.:
```
sudo bash ath12k-ccfix/ath12k-ccfix-install.sh usun
```

---

## Szczegóły techniczne

- **iommu-fix:** BIOS Lenovo ma procedurę SMI uruchamianą przy przejściu NVMe z D3 do D0 przy
  wybudzaniu z s2idle; z włączonym tłumaczeniem IOMMU wstrzymuje ona wybudzanie na ~10,25 s
  (nvme, xhci, renesas, hda blokują się w `pci_pm_resume_noirq`). Kernel ma obejście w `amd_pmc`
  (lista `fwbug_list`), ale dopasowuje model po typie maszyny i nie obejmuje `20X6`.
  Docelowo: zgłosić dopisanie `20X6` do `drivers/platform/x86/amd/pmc/pmc-quirks.c`.
- **ath12k-ccfix:** po wybudzeniu firmware WCN785x jest uruchamiane od nowa z regdomain WORLD
  i odzyskuje kraj dopiero po skanie 802.11d (~7 s). Poprawka w `ath12k_core_resume()` wysyła
  od razu ostatni znany kraj przez `ath12k_wmi_send_set_current_country_cmd()` –
  tak samo jak w ath11k (commit `7f0343b7b871`).
  Ostatni prawdziwy kraj jest zapamiętywany osobno (z wyniku skanu 802.11d), bo gdy NetworkManager
  rozłącza WiFi przed uśpieniem, cfg80211 resetuje regdomain i `ar->alpha2` zmienia się na `00`.
- **wifi-fast-resume:** po wybudzeniu czeka na kraj, przerywa pełny skan i zleca wpa_supplicant
  skan tylko ostatnio używanego kanału, więc NetworkManager łączy się od razu.
- **touchpad-intertouch:** `psmouse.synaptics_intertouch=1` – touchpad idzie przez SMBus (RMI4) zamiast PS/2;
  na PS/2 zostaje tylko TrackPoint (`serio_resume` ~0,6 s).
- **ryzen-power:** profil Lenovo „performance” ustawia STAPM 30 W, PPT FAST 30 W, PPT SLOW 25 W, Tctl 100 °C,
  StapmTimeConst 1 s. Pod pełnym obciążeniem procesor stoi na PPT SLOW = 25,0 W przy ~70 °C, czyli hamuje
  go limit mocy. `ryzenadj` ustawia SLOW 30 / FAST 35 / Tctl 95; STAPM powyżej 30 W i `--stapm-time`
  SMU odrzuca. Powrót do limitów Lenovo = chwilowa zmiana `platform_profile`, po której firmware ustawia je od nowa.
- **lte-modem:** modem ma dwa gniazda SIM i domyślnie włączone wykrywanie karty przez styk
  (`AT+QSIMDET: 1,1`); w tym laptopie styk zgłasza „brak karty”, więc SIM nie jest zasilana
  (`+CPIN: ERROR 10`). `AT+QUIMSLOT=1` + `AT+QSIMDET=0,0` zapisują się w pamięci modemu.
  `AT+CEER: Requested service option not subscribed` = zły APN – a2mobile wymaga `a2mobile.pl`.
