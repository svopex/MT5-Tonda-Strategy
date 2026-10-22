# Tondova obchodni strategie

Strategie vychazi z `SvopexSMC.pine` a `BollingerBands.pine`.
To jsou strategie pro pinescript, pro tradingview.

## Vstup do obchodu

Pri vytvoreni nebo dotknuti se order blocku.
Zaroven musim byt dolni nebo horni polovine bollinger bands pasu (mezi cervenou a modrou nebo zelenou a modrou, vzdy na opacne nez kam nakupujeme).

## Vystup z obchodu

Po dosazeni protejsiho bollinger bands pasu.

## StopLoss

Pod urovni order blocku +60 bodu (nastavitelne v konfiguraci).

## Technologie

Automaticka strategie expert pro MT5.
