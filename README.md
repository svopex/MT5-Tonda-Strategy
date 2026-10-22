# Tondova obchodni strategie

Automatická obchodní strategie (Expert Advisor) pro MetaTrader 5. Vychází ze zadání
v `docs/prompt.md` a z indikátorů pro TradingView `docs/SvopexSMC.pine` (order blocky)
a `docs/BollingerBands.pine`.

## Struktura projektu

- `MQL5/Experts/TondaStrategy/TondaStrategy.mq5` – expert: vstupy, výstupy, velikost pozice.
- `MQL5/Experts/TondaStrategy/OrderBlocks.mqh` – detekce struktury a order blocků převzatá
  z indikátoru Svopex SMC.
- `MQL5/Experts/TondaStrategy/ChartDrawing.mqh` – kreslení grafu jako v TradingView.
- `MQL5/Experts/TondaStrategy/ZoneCanvas.mqh` – průhledná bitmapa pro order blocky a výplň BB.
- `MQL5/Experts/TondaStrategy/TradingHours.mqh` – obchodní doba (otevírání a zavírání obchodů).
- `scripts/install.ps1` – instalace a kompilace experta ve všech terminálech MT5.
- `docs/` – zadání strategie a zdrojové Pine skripty.

## Instalace a spuštění

1. Spusťte instalační skript:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install.ps1
   ```

   Skript najde všechny terminály MT5 (`%APPDATA%\MetaQuotes\Terminal`), v každém vytvoří
   odkaz (junction) `MQL5\Experts\TondaStrategy` na složku v repozitáři a expert zkompiluje.
   Změny v repozitáři se tak projeví ve všech terminálech; po úpravě kódu stačí skript
   spustit znovu (nebo zkompilovat v MetaEditoru klávesou F7).
2. V MT5 obnovte Navigátor (*Experti → pravé tlačítko → Obnovit*).
3. Přetáhněte experta na graf, nebo ho spusťte v testeru strategií. Strategie pracuje
   na časovém rámci grafu.

## Strategie

### Vstup do obchodu

Signál se vyhodnocuje průběžně na každém ticku:

- **Nákup** – cena (Bid) je v dolní polovině Bollinger Bands (mezi dolním zeleným
  a středním modrým pásmem) a zároveň:
  - na poslední uzavřené svíčce vznikl nový býčí order block a cena je v jeho
    blízkosti (tolerance = násobek ATR 14), nebo
  - tvořená svíčka se dotkla býčího order blocku shora, přičemž předchozí svíčka byla celá nad ním.
- **Prodej** – zrcadlově: cena je v horní polovině BB (mezi středním modrým a horním
  červeným pásmem) a vznikne nebo se zasáhne medvědí order block zdola.

Kontroluje se jen několik nejnovějších order blocků (`Počet kontrolovaných nejnovějších OB`).
Z každého order blocku vzejde nejvýš jeden signál. Současně je otevřená nejvýš jedna
pozice; dokud trvá, nové signály se ignorují.

### Výstup z obchodu

Nákup se zavře, jakmile Bid dosáhne horního (červeného) pásma, prodej po dosažení
dolního (zeleného) pásma. *Předčasný výstup* (násobek ATR 14, 0 = na pásmu) posune výstup
o tuto vzdálenost dřív; aktuální hodnota v bodech je vidět v textu vlevo nahoře.

### Obchodní doba

Časy jsou podle času serveru brokera (stejně jako svíčky v MT5). Volba *Zdroj obchodní doby*
určuje, odkud se berou:

- **Ručně** (výchozí):
  - nové obchody se otevírají jen od *Začátek obchodování* (výchozí 02:00) do *Konec otevírání
    obchodů* (výchozí 23:00),
  - v čase *Zavření otevřených obchodů* (výchozí 23:45) se případná otevřená pozice zavře;
    zavírací doba trvá až do začátku dalšího obchodování, takže se mezitím nic neotevře.
- **Podle obchodních seancí symbolu v MT5** (ze *Specifikace* symbolu, pro každý den v týdnu):
  - nové obchody se otevírají až 60 minut po začátku seance a přestanou 60 minut před jejím
    koncem (*Seance: otevírat až po* / *Seance: neotevírat*),
  - otevřená pozice se zavře 10 minut před koncem seance (*Seance: zavřít pozice*), tedy i před
    denní přestávkou,
  - navazující seance (i přes půlnoc) se berou jako jedna; symbol obchodovaný nepřetržitě
    se nezavírá,
  - svátky a zkrácené obchodování MT5 v seancích nemá, ty se nezohlední.

### Stop loss a velikost pozice

- SL je pod dolní hranou order blocku (nákup) nebo nad horní hranou (prodej)
  plus odstup. Ten je buď násobkem aktuálního spreadu v okamžiku vstupu (výchozí 1,25 ×,
  tedy spread zvětšený o 25 %), nebo pevným počtem bodů (výchozí 60) – podle volby
  *Odstup SL od order blocku*.
- Maximální skluz při otevření i zavření pozice je násobek ATR 14 (výchozí 0,15 ×, u XAUUSD M1
  zhruba 20 bodů), takže se přizpůsobuje volatilitě.
- Objem se počítá tak, aby ztráta při zásahu SL byla nastavené procento zůstatku účtu.
  Vyjde-li objem pod minimum symbolu, obchod se neotevře.

### Order blocky

Detekce odpovídá indikátoru Svopex SMC (LuxAlgo Smart Money Concepts): order block vzniká
při prolomení swingu close cenou (BOS/CHoCH) ze svíčky s extrémem mezi swingem a prolomením.
Velmi volatilní svíčky (rozpětí ≥ 2× ATR 200) se při výběru extrému potlačí. Order block
zaniká (mitigace), když cena projde za jeho protější hranu. Ve výchozím stavu se používají
internal order blocky (délka struktury 5), swing order blocky (délka 50) lze zapnout.
Order blocky se počítají z uzavřených svíček; při startu se zpracuje nastavený počet svíček historie.

## Nastavení

| Skupina | Parametr | Výchozí | Popis |
|---|---|---|---|
| Obchod | Riziko na obchod (% zůstatku) | 1.0 | Ztráta při zásahu SL v % zůstatku |
| Obchod | Odstup SL od order blocku | Násobek aktuálního spreadu | Způsob výpočtu vzdálenosti SL za hranou OB (násobek spreadu, nebo pevný počet bodů) |
| Obchod | Odstup SL – násobek spreadu | 1.25 | Odstup SL jako násobek spreadu při vstupu |
| Obchod | Odstup SL – pevně (body) | 60 | Odstup SL v bodech, je-li zvolen pevný počet bodů |
| Obchod | Magic number | 202610225598 | Identifikace pozic experta |
| Obchod | Maximální skluz (násobek ATR 14) | 0.15 | Povolená odchylka ceny při obchodu |
| Obchod | Tolerance nového OB (násobek ATR 14) | 0.5 | Blízkost ceny k nově vzniklému OB |
| Obchod | Předčasný výstup před pásmem BB (násobek ATR 14) | 0.5 | O kolik dřív se pozice zavře (0 = na pásmu) |
| Obchodní doba | Zdroj obchodní doby | Ručně | Ručně zadané časy, nebo obchodní seance symbolu v MT5 |
| Obchodní doba | Ručně: začátek obchodování | 02:00 | Od kdy se otevírají nové obchody (čas serveru, HH:MM) |
| Obchodní doba | Ručně: konec otevírání obchodů | 23:00 | Do kdy se otevírají nové obchody |
| Obchodní doba | Ručně: zavření otevřených obchodů | 23:45 | Kdy se otevřená pozice zavře |
| Obchodní doba | Seance: otevírat až po (min) | 60 | Odstup nových obchodů od začátku seance |
| Obchodní doba | Seance: neotevírat (min před koncem) | 60 | Kdy před koncem seance se přestanou otevírat obchody |
| Obchodní doba | Seance: zavřít pozice (min před koncem) | 10 | Kdy před koncem seance se otevřená pozice zavře |
| Bollinger Bands | Perioda / Směrodatná odchylka | 20 / 2.0 | Parametry BB (SMA z close) |
| Order blocky | Internal order blocky | ano | Používat internal OB |
| Order blocky | Swing order blocky | ne | Používat swing OB |
| Order blocky | Délka internal / swing struktury | 5 / 50 | Počet svíček pro potvrzení swingu |
| Order blocky | Mitigace order blocku | High/Low | Cena, která OB zneplatní (High/Low nebo Close) |
| Order blocky | Počet kontrolovaných nejnovějších OB | 5 | Kolik nejnovějších OB se kontroluje |
| Order blocky | Počet svíček historie pro rozběh | 2000 | Historie zpracovaná při startu |
| Zobrazení | Kreslit graf jako v TradingView | ano | Bollinger Bands a Svopex SMC kreslené expertem |
| Zobrazení | Mitigované order blocky | ano | Zneplatněné OB končící na svíčce mitigace |
| Zobrazení | Internal / swing struktura (BOS/CHoCH) | ano / ano | Čáry a popisky prolomení struktury |
| Zobrazení | Equal High/Low | ano | Čáry a popisky EQH/EQL |
| Zobrazení | Strong/Weak High/Low | ano | Poslední swing high a low s popiskem |
| Zobrazení | Počet svíček s Bollinger Bands | 500 | Kolik posledních svíček má nakreslené BB |
| Zobrazení | Text vlevo nahoře | ano | Stav obchodování a aktuální vzdálenosti strategie v bodech |

## Zobrazení v grafu

Expert sám kreslí graf tak, aby vypadal jako TradingView s indikátory `BollingerBands.pine`
a `SvopexSMC.pine` (v testeru jen ve vizuálním režimu, bez vizualizace se kvůli rychlosti nekreslí):

- tmavé pozadí `#0C0C0C`, zelené a červené svíčky bez mřížky (nastaví se vždy, při kreslení
  grafu; po odebrání experta se původní barvy vrátí),
- Bollinger Bands: modrý střed, červené horní a zelené dolní pásmo, výplň mezi pásmy,
- aktivní order blocky sahající doprava (počet podle *Počet kontrolovaných nejnovějších OB*);
  býčí (long) jsou zelené a medvědí (short) červené, o něco tmavší než svíčky (v Pine jsou long modré),
- 5 nejnovějších mitigovaných order blocků v šedé barvě pro oba směry (box končí na svíčce
  mitigace, tečkovaný okraj),
- internal BOS/CHoCH (čárkovaně) a swing BOS/CHoCH (plně) s popisky,
- EQH/EQL (tečkovaně) a Strong/Weak High a Low,
- text vlevo nahoře: zda expert může obchodovat (`ZAPNUTO`, nebo `VYPNUTO` s důvodem – např.
  vypnuté Algoritmické obchodování v terminálu nebo ve vlastnostech experta, chybějící připojení,
  zákaz obchodování na účtu či symbolu; mimo obchodní dobu `ZAPNUTO – mimo obchodní dobu`),
  obchodní doba (v režimu seancí aktuální seance a z ní odvozené časy otevírání a zavření)
  a aktuální hodnoty v bodech: tolerance nového OB, předčasný výstup,
  odstup SL a maximální skluz.

Vyplněné zóny (order blocky a výplň BB) se kreslí do jedné průhledné bitmapy za svíčkami,
kde se barvy skládají s průhledností z Pine stejně jako v TradingView – i tam, kde se boxy
překrývají. Vyplněné grafické objekty MT5 se při překryvu míchají přes XOR (průnik dvou
stejných boxů by zmizel), proto se pro zóny nepoužívají. Bitmapa se překresluje na nové
svíčce, při posunu, zoomu a změně cenového měřítka grafu. Čáry a popisky jsou grafické objekty.

Struktura se počítá z uzavřených svíček, takže BOS/CHoCH a nové OB se objeví až
po uzavření svíčky (TradingView je kreslí už během svíčky). Rozdíly mohou vzniknout
i z odlišných cenových dat brokera.
