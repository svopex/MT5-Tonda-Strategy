# Instrukce pro tento projekt

## Dokumentace

- `README.md` průběžně aktualizuj: při každé změně, která mění chování aplikace, ovládání,
  zobrazení v grafu, nastavení, strategii, export, spuštění nebo strukturu
  projektu, uprav odpovídající část `README.md` ve stejném commitu.
- Před commitem zkontroluj, zda `README.md` odpovídá změnám v commitu; pokud úprava není
  potřeba (refaktoring, testy, kosmetika), README neměň.

## Instalace do MetaTrader 5

- Před každou instalací nové verze experta spusť `/simplify` a zapracuj jeho nálezy;
  do té doby kompiluj jen kopii v pracovní složce (scratchpad), ne v repozitáři.
- Po každé změně kódu v `MQL5/` spusť instalaci a kompilaci experta:
  `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install.ps1`
- Skript vytvoří ve všech nalezených terminálech MT5 junction `MQL5\Experts\TondaStrategy`
  na složku v repozitáři (pokud chybí) a expert zkompiluje.
- Nepoužívej vlastní indikátory; vše, co se má zobrazit v grafu, kreslí expert sám.
- Úkol je hotový, až když skript skončí s `Result: 0 errors`; chyby kompilace oprav.
- Před každým nasazením nové verze zvyš `EA_VERSION` (`#property version`) v `TondaStrategy.mq5` podle
  sekce *Verzování* v `README.md` (oprava +0.01, nová funkce +0.10, zásadní změna +1.00)
  a aktualizuj tam „Aktuální verze“. Commit s novou verzí označ tagem `vX.YY` a tag pushni
  spolu s commitem.
- Zdrojové soubory MQL5 a `.ps1` ukládej v UTF-8 s BOM (MetaEditor i PowerShell 5.1
  jinak špatně načtou češtinu).
