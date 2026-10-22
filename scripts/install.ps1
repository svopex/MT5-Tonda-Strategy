# Instalace experta TondaStrategy do všech nainstalovaných terminálů MetaTrader 5.
# Do datové složky každého terminálu vytvoří junction MQL5\Experts\TondaStrategy
# ukazující do repozitáře a expert zkompiluje MetaEditorem.
# Spuštění: powershell -ExecutionPolicy Bypass -File scripts\install.ps1

$ErrorActionPreference = 'Stop'

$repoMql5 = Join-Path $PSScriptRoot '..\MQL5' | Resolve-Path
$linkedFolder = 'Experts\TondaStrategy'
$terminalsRoot = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
$installed = @()

# Datové složky terminálů poznáme podle souboru origin.txt s cestou k instalaci terminálu
foreach ($dataDir in Get-ChildItem $terminalsRoot -Directory) {
    $originFile = Join-Path $dataDir.FullName 'origin.txt'
    $terminalMql5 = Join-Path $dataDir.FullName 'MQL5'
    if (-not (Test-Path $originFile) -or -not (Test-Path $terminalMql5)) { continue }

    $target = Join-Path $terminalMql5 $linkedFolder
    $source = Join-Path $repoMql5 $linkedFolder

    # Junction nevyžaduje práva administrátora; existující složku jiného původu nepřepisujeme
    if (-not (Test-Path $target)) {
        New-Item -ItemType Junction -Path $target -Target $source | Out-Null
        Write-Host "Vytvořen odkaz: $target"
    }
    elseif ((Get-Item $target).LinkType -ne 'Junction') {
        Write-Warning "Přeskočeno, $target existuje a není to odkaz na repozitář."
    }

    $installed += [pscustomobject]@{ TerminalDir = (Get-Content $originFile -Raw).Trim(); Mql5Dir = $terminalMql5 }
}

if ($installed.Count -eq 0) { throw 'Nenalezen žádný terminál MetaTrader 5.' }

# Kompilace stačí jednou: .ex5 vznikne ve složce repozitáře, kterou sdílejí všechny junctiony
$compiler = $installed | Where-Object { Test-Path (Join-Path $_.TerminalDir 'MetaEditor64.exe') } | Select-Object -First 1
if (-not $compiler) { throw 'Nenalezen MetaEditor64.exe.' }
$metaEditor = Join-Path $compiler.TerminalDir 'MetaEditor64.exe'
$logFile = Join-Path $env:TEMP 'TondaStrategy-compile.log'

# Kompilujeme přes cestu v terminálu, include <Trade/Trade.mqh> se hledá v jeho MQL5\Include
$sourceFile = Join-Path $compiler.Mql5Dir "$linkedFolder\TondaStrategy.mq5"
Start-Process -FilePath $metaEditor -ArgumentList "/compile:`"$sourceFile`"", "/inc:`"$($compiler.Mql5Dir)`"", "/log:`"$logFile`"" -Wait

# MetaEditor vrací nespolehlivý návratový kód, výsledek proto čteme z logu (UTF-16)
$result = Get-Content $logFile -Encoding Unicode | Where-Object { $_ -match 'error|warning|Result:' }
$result | ForEach-Object { Write-Host $_ }
if (-not ($result -match 'Result: 0 errors')) { throw 'Kompilace selhala.' }

Write-Host "Nainstalováno do $($installed.Count) terminálů. V MT5 obnovte Navigátor (pravé tlačítko -> Obnovit)."
