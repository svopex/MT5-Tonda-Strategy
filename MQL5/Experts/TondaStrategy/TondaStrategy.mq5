//+------------------------------------------------------------------+
//|                                                TondaStrategy.mq5 |
//| Tondova strategie: vstup při vzniku nebo doteku order blocku     |
//| (Svopex SMC) v příslušné polovině Bollinger Bands, výstup        |
//| na protějším pásmu, stop loss za order blockem.                  |
//+------------------------------------------------------------------+
#property copyright "Petr Svoboda"
#property link      "https://github.com/svopex/MT5-Tonda-Strategy"
// Verze experta: vlastnosti experta v MT5 i text vlevo nahoře
#define EA_VERSION "1.11"
#property version   EA_VERSION
#property description "Order blocky (Svopex SMC) + Bollinger Bands"

#include <Trade/Trade.mqh>
#include "OrderBlocks.mqh"
#include "ChartDrawing.mqh"
#include "TradingHours.mqh"

// Způsob výpočtu odstupu SL za order blockem (komentáře hodnot se zobrazí v nastavení)
enum ENUM_SL_OFFSET_MODE
  {
   SL_OFFSET_SPREAD, // Násobek aktuálního spreadu
   SL_OFFSET_POINTS  // Pevný počet bodů
  };

input group "Obchod"
input double             InpRiskPercent          = 1.0;           // Riziko na obchod (% zůstatku)
input ENUM_SL_OFFSET_MODE InpStopLossOffsetMode  = SL_OFFSET_SPREAD; // Odstup SL od order blocku
input double             InpStopLossSpreadMultiple = 1.25;        // Odstup SL – násobek spreadu
input int                InpStopLossOffsetPoints = 60;            // Odstup SL – pevně (body)
input ulong              InpMagic                = 202610225598;  // Magic number
input double             InpSlippageAtr          = 0.15;          // Maximální skluz (násobek ATR 14)
input double             InpNewBlockTolerance    = 0.5;           // Tolerance nového OB (násobek ATR 14)
input double             InpEarlyExitAtr         = 0.5;           // Předčasný výstup před pásmem BB (násobek ATR 14, 0 = na pásmu)

input group "Obchodní doba (čas serveru)"
input ENUM_HOURS_SOURCE  InpHoursSource          = HOURS_SESSIONS; // Zdroj obchodní doby
input string             InpTradeStart           = "02:00";       // Ručně: začátek obchodování (HH:MM)
input string             InpTradeEnd             = "23:00";       // Ručně: konec otevírání obchodů (HH:MM)
input string             InpCloseTime            = "23:45";       // Ručně: zavření otevřených obchodů (HH:MM)
input int                InpSessionOpenDelay     = 60;            // Seance: otevírat až po (min od začátku seance)
input int                InpSessionEntryStop     = 60;            // Seance: neotevírat (min před koncem seance)
input int                InpSessionCloseBefore   = 10;            // Seance: zavřít pozice (min před koncem seance)

input group "Bollinger Bands"
input int                InpBandsPeriod          = 20;            // Perioda
input double             InpBandsDeviation       = 2.0;           // Směrodatná odchylka

input group "Order blocky"
input bool               InpUseInternalBlocks    = true;          // Internal order blocky
input bool               InpUseSwingBlocks       = false;         // Swing order blocky
input int                InpInternalLength       = 5;             // Délka internal struktury
input int                InpSwingLength          = 50;            // Délka swing struktury
input ENUM_OB_MITIGATION InpMitigation           = OB_MITIGATION_HIGHLOW; // Mitigace order blocku
input int                InpMaxBlocks            = 5;             // Počet kontrolovaných nejnovějších OB
input int                InpHistoryBars          = 2000;          // Počet svíček historie pro rozběh

input group "Zobrazení"
input bool               InpShowChart            = true;          // Kreslit graf jako v TradingView
input bool               InpShowMitigatedBlocks  = true;          // Mitigované order blocky
input bool               InpShowInternalStructure = true;         // Internal struktura (BOS/CHoCH)
input bool               InpShowSwingStructure   = true;          // Swing struktura (BOS/CHoCH)
input bool               InpShowEqualHighsLows   = true;          // Equal High/Low
input bool               InpShowStrongWeak       = true;          // Strong/Weak High/Low
input int                InpBandsBars            = 500;           // Počet svíček s Bollinger Bands
input bool               InpShowInfo             = true;          // Text vlevo nahoře (stav obchodování, tolerance OB)

CTrade              g_trade;
COrderBlockDetector g_detector;
CChartDrawing       g_chart;
CTradingHours       g_hours;
int                 g_bandsHandle  = INVALID_HANDLE;
datetime            g_lastBarTime  = 0;   // čas poslední zpracované uzavřené svíčky
bool                g_infoEnabled  = false; // vypisovat text vlevo nahoře
string              g_infoText     = "";  // naposledy vypsaný text vlevo nahoře

//+------------------------------------------------------------------+
//| Inicializace experta                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Kontrola nastavení, se kterým strategie nedává smysl
   if(InpRiskPercent <= 0.0 || InpStopLossOffsetPoints < 0 || InpStopLossSpreadMultiple < 0.0 ||
      InpSlippageAtr < 0.0 || InpMaxBlocks < 1 || InpEarlyExitAtr < 0.0 ||
      InpInternalLength < 1 || InpSwingLength < 1 || (!InpUseInternalBlocks && !InpUseSwingBlocks) ||
      !InitTradingHours())
     {
      Print("Neplatné nastavení vstupních parametrů.");
      return INIT_PARAMETERS_INCORRECT;
     }

   // BB stejně jako v Pine: SMA z close, populační směrodatná odchylka
   g_bandsHandle = iBands(_Symbol, _Period, InpBandsPeriod, 0, InpBandsDeviation, PRICE_CLOSE);
   if(g_bandsHandle == INVALID_HANDLE)
     {
      Print("Nepodařilo se vytvořit indikátor Bollinger Bands, chyba ", GetLastError());
      return INIT_FAILED;
     }

   // Kreslení grafu; zda se v testeru opravdu kreslí, rozhodne CChartDrawing sám
   SChartDrawingSettings settings;
   settings.enabled               = InpShowChart;
   settings.blocksCount           = InpMaxBlocks;
   settings.showMitigatedBlocks   = InpShowMitigatedBlocks;
   settings.showInternalStructure = InpShowInternalStructure;
   settings.showSwingStructure    = InpShowSwingStructure;
   settings.showEqualHighsLows    = InpShowEqualHighsLows;
   settings.showStrongWeak        = InpShowStrongWeak;
   settings.bandsBars             = MathMax(InpBandsBars, 1);
   g_chart.Init(settings, g_bandsHandle, g_detector);

   g_detector.Init(InpSwingLength, InpInternalLength, InpUseSwingBlocks, InpUseInternalBlocks, InpMitigation);
   g_lastBarTime = 0;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   // Text vlevo nahoře jen tam, kde je graf vidět; časovač hlídá pohled grafu i stav obchodování
   g_infoEnabled = InpShowInfo && IsChartVisible();
   if(g_infoEnabled || (InpShowChart && IsChartVisible()))
      EventSetMillisecondTimer(CANVAS_CHECK_INTERVAL_MS);
   g_infoText = "";
   UpdateInfo();
   return INIT_SUCCEEDED;
  }

// Nastaví obchodní dobu podle zvoleného zdroje; false při neplatných časech nebo odstupech
bool InitTradingHours()
  {
   if(InpHoursSource == HOURS_SESSIONS)
      return g_hours.InitSessions(_Symbol, InpSessionOpenDelay, InpSessionEntryStop, InpSessionCloseBefore);
   return g_hours.InitManual(InpTradeStart, InpTradeEnd, InpCloseTime);
  }

//+------------------------------------------------------------------+
//| Ukončení experta                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_bandsHandle != INVALID_HANDLE)
      IndicatorRelease(g_bandsHandle);

   EventKillTimer();
   g_chart.Deinit();
   if(g_infoEnabled)
      Comment("");
  }

//+------------------------------------------------------------------+
//| Časovač: překreslí zóny po posunu, zoomu nebo změně měřítka      |
//| grafu a obnoví text vlevo nahoře                                 |
//+------------------------------------------------------------------+
void OnTimer()
  {
   g_chart.OnTimer();

   // Stav obchodování se může změnit i bez ticku (tlačítko Algoritmické obchodování)
   UpdateInfo();
  }

//+------------------------------------------------------------------+
//| Zpracování ticku                                                 |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Zavírací doba závisí jen na čase: pozice se zavře, i když chybí data svíček nebo BB
   ulong ticket = FindOpenPosition();
   if(ticket != 0 && g_hours.IsClosingTime())
     {
      ClosePosition(ticket);
      return;
     }

   // Order blocky se počítají z uzavřených svíček; nové svíčky zpracujeme hned na prvním ticku
   bool newBar = false;
   if(!ProcessClosedBars(newBar))
      return;
   UpdateInfo();

   // Hodnoty BB tvořené svíčky se načtou jednou a použijí je kreslení i strategie
   SBandValues bands;
   if(!ReadBands(bands))
      return;
   g_chart.Refresh(newBar, bands);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Otevřená pozice: výstup po dosažení protějšího pásma, nové vstupy se neotevírají
   if(ticket != 0)
     {
      ManagePosition(ticket, bid, bands);
      return;
     }

   if(g_hours.IsEntryTime())
      CheckEntry(bid, bands);
  }

//+------------------------------------------------------------------+
//| Vypíše vlevo nahoře, zda expert může obchodovat, a aktuální      |
//| vzdálenosti strategie v bodech. Comment se volá jen při změně.   |
//+------------------------------------------------------------------+
void UpdateInfo()
  {
   if(!g_infoEnabled)
      return;

   // Mimo obchodní dobu je expert zapnutý, ale nové obchody neotevírá
   string reason = TradingBlockReason();
   string status = "ZAPNUTO – může obchodovat";
   if(reason != "")
      status = "VYPNUTO – " + reason;
   else if(!g_hours.IsEntryTime())
      status = "ZAPNUTO – mimo obchodní dobu, nové obchody neotevírá";

   // Vzdálenosti stejné jako ve strategii, převedené na body symbolu
   string earlyExit = InpEarlyExitAtr > 0.0 ? AtrPointsText(InpEarlyExitAtr) + " před pásmem" : "vypnutý (výstup na pásmu)";
   string text = "TondaStrategy " + EA_VERSION + ": " + status +
                 "\nObchodní doba: " + g_hours.Description() +
                 "\nTolerance nového OB: " + AtrPointsText(InpNewBlockTolerance) +
                 "\nPředčasný výstup: " + earlyExit +
                 "\nOdstup SL: " + StopLossOffsetText() +
                 "\nMaximální skluz: " + AtrPointsText(InpSlippageAtr);
   if(text == g_infoText)
      return;
   g_infoText = text;
   Comment(text);
  }

// Cenová vzdálenost převedená na celé body symbolu
int ToPoints(const double distance)
  {
   return (int)MathRound(distance / _Point);
  }

// Násobek ATR(14) jako text v bodech symbolu, např. "87 bodů (0.50 × ATR 14)"
string AtrPointsText(const double multiple)
  {
   double distance = g_detector.AtrDistance(multiple);
   if(distance <= 0.0)
      return "čeká na data";
   return IntegerToString(ToPoints(distance)) + " bodů (" + DoubleToString(multiple, 2) + " × ATR " + IntegerToString(ATR_DISTANCE_LENGTH) + ")";
  }

// Aktuální spread v ceně (Ask − Bid)
double CurrentSpread()
  {
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
  }

// Odstup SL za order blockem v ceně: pevný počet bodů, nebo násobek aktuálního spreadu
double StopLossOffset()
  {
   if(InpStopLossOffsetMode == SL_OFFSET_POINTS)
      return InpStopLossOffsetPoints * _Point;
   return InpStopLossSpreadMultiple * CurrentSpread();
  }

// Odstup SL jako text v bodech symbolu, např. "9 bodů (1.25 × spread 7 bodů)"
string StopLossOffsetText()
  {
   if(InpStopLossOffsetMode == SL_OFFSET_POINTS)
      return IntegerToString(InpStopLossOffsetPoints) + " bodů (pevně)";
   double spread = CurrentSpread();
   return IntegerToString(ToPoints(InpStopLossSpreadMultiple * spread)) + " bodů (" +
          DoubleToString(InpStopLossSpreadMultiple, 2) + " × spread " + IntegerToString(ToPoints(spread)) + " bodů)";
  }

// Nastaví maximální skluz obchodních operací na násobek ATR 14; volá se po každé změně ATR
void UpdateDeviation()
  {
   g_trade.SetDeviationInPoints((ulong)ToPoints(g_detector.AtrDistance(InpSlippageAtr)));
  }

//+------------------------------------------------------------------+
//| Důvod, proč expert nemůže obchodovat (prázdný = může)            |
//+------------------------------------------------------------------+
string TradingBlockReason()
  {
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      return "terminál není připojen k serveru";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return "v terminálu je vypnuté Algoritmické obchodování";
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return "ve vlastnostech experta není povolené algoritmické obchodování";
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return "obchodování na účtu není povolené";
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return "účet nepovoluje obchodování expertů";
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return "obchodování symbolu " + _Symbol + " je zakázané";
   return "";
  }

//+------------------------------------------------------------------+
//| Předá detektoru všechny nově uzavřené svíčky. Při prvním volání  |
//| zpracuje historii pro rozběh. Vrací false, pokud data chybí.     |
//| newBar – nastaví se na true, pokud přibyla uzavřená svíčka       |
//+------------------------------------------------------------------+
bool ProcessClosedBars(bool &newBar)
  {
   datetime closedBarTime = iTime(_Symbol, _Period, 1);
   if(closedBarTime == 0)
      return false;
   if(closedBarTime == g_lastBarTime)
      return true;

   // Při rozběhu vezmeme pevný počet svíček, jinak svíčky od poslední zpracované
   // (ta je v rozsahu znovu a přeskočí ji filtr času níže)
   MqlRates rates[];
   int copied = (g_lastBarTime == 0)
                ? CopyRates(_Symbol, _Period, 1, InpHistoryBars, rates)
                : CopyRates(_Symbol, _Period, g_lastBarTime, closedBarTime, rates);
   if(copied <= 0)
      return false;

   for(int i = 0; i < copied; i++)
      if(rates[i].time > g_lastBarTime)
         g_detector.ProcessBar(rates[i]);
   g_lastBarTime = rates[copied - 1].time;
   newBar = true;
   UpdateDeviation();
   return true;
  }

//+------------------------------------------------------------------+
//| Načte aktuální hodnoty Bollinger Bands (tvořená svíčka)          |
//+------------------------------------------------------------------+
bool ReadBands(SBandValues &bands)
  {
   double basis[1], upper[1], lower[1];
   if(CopyBuffer(g_bandsHandle, BASE_LINE, 0, 1, basis) != 1 ||
      CopyBuffer(g_bandsHandle, UPPER_BAND, 0, 1, upper) != 1 ||
      CopyBuffer(g_bandsHandle, LOWER_BAND, 0, 1, lower) != 1)
      return false;
   bands.basis = basis[0];
   bands.upper = upper[0];
   bands.lower = lower[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Vrátí ticket otevřené pozice tohoto experta na symbolu (0 = není)|
//+------------------------------------------------------------------+
ulong FindOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return ticket;
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| Zavře pozici po dosažení protějšího pásma BB (nákup na horním    |
//| červeném, prodej na dolním zeleném), případně o předčasný výstup |
//| (násobek ATR 14) dříve                                           |
//+------------------------------------------------------------------+
void ManagePosition(const ulong ticket, const double bid, const SBandValues &bands)
  {
   if(!PositionSelectByTicket(ticket))
      return;

   bool   isBuy         = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
   double earlyExit     = g_detector.AtrDistance(InpEarlyExitAtr);
   bool   reachedTarget = isBuy ? bid >= bands.upper - earlyExit : bid <= bands.lower + earlyExit;
   if(reachedTarget)
      ClosePosition(ticket);
  }

// Zavře pozici tržním příkazem; neúspěch zapíše do logu
void ClosePosition(const ulong ticket)
  {
   if(!g_trade.PositionClose(ticket))
      Print("Pozici ", ticket, " se nepodařilo zavřít: ", g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Vyhodnotí vstup: nákup u býčího OB v dolní polovině BB           |
//| (mezi dolním a středním pásmem), prodej u medvědího OB v horní   |
//| polovině BB (mezi středním a horním pásmem).                     |
//+------------------------------------------------------------------+
void CheckEntry(const double bid, const SBandValues &bands)
  {
   // Mimo pásmo se neobchoduje; polovina pásma určuje směr obchodu
   if(bid < bands.lower || bid > bands.upper)
      return;
   int bias = (bid <= bands.basis) ? OB_BULLISH : OB_BEARISH;

   SOrderBlock block;
   if(!g_detector.FindSignal(bias, InpMaxBlocks, InpNewBlockTolerance, bid,
                             iLow(_Symbol, _Period, 0), iHigh(_Symbol, _Period, 0), block))
      return;

   // Každý OB dá nejvýš jeden signál, i když se obchod nepodaří otevřít
   // (jinak by se neúspěšný pokus opakoval na každém ticku)
   g_detector.MarkUsed(block.id);
   OpenPosition(bias == OB_BULLISH ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, block);
  }

//+------------------------------------------------------------------+
//| Otevře pozici se SL za order blockem a objemem podle rizika      |
//| type – ORDER_TYPE_BUY / ORDER_TYPE_SELL, block – signální OB     |
//+------------------------------------------------------------------+
void OpenPosition(const ENUM_ORDER_TYPE type, const SOrderBlock &block)
  {
   bool   isBuy  = type == ORDER_TYPE_BUY;
   double price  = SymbolInfoDouble(_Symbol, isBuy ? SYMBOL_ASK : SYMBOL_BID);
   double offset = StopLossOffset();

   // SL pod dolní hranou OB (nákup) nebo nad horní hranou OB (prodej)
   double stopLoss = NormalizeDouble(isBuy ? block.Bottom() - offset : block.Top() + offset, _Digits);

   // SL musí být na správné straně ceny a dál než minimální vzdálenost brokera
   double minDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if((isBuy && stopLoss >= price - minDistance) || (!isBuy && stopLoss <= price + minDistance))
     {
      Print("Signál přeskočen: SL ", stopLoss, " je příliš blízko ceny ", price);
      return;
     }

   double volume = CalculateVolume(type, price, stopLoss);
   if(volume <= 0.0)
      return;

   string comment = "Tonda " + (isBuy ? "BUY" : "SELL") + " OB";
   if(!g_trade.PositionOpen(_Symbol, type, volume, price, stopLoss, 0.0, comment) ||
      g_trade.ResultRetcode() != TRADE_RETCODE_DONE)
      Print("Obchod se nepodařilo otevřít: ", g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Spočítá objem tak, aby ztráta na SL byla InpRiskPercent zůstatku |
//| Vrací 0, pokud vychází pod minimální objem symbolu.              |
//+------------------------------------------------------------------+
double CalculateVolume(const ENUM_ORDER_TYPE type, const double price, const double stopLoss)
  {
   // Ztráta jednoho lotu při zásahu SL včetně přepočtu měny symbolu na měnu účtu
   double lossPerLot = 0.0;
   if(!OrderCalcProfit(type, _Symbol, 1.0, price, stopLoss, lossPerLot) || lossPerLot >= 0.0)
     {
      Print("Nelze spočítat ztrátu na SL, chyba ", GetLastError());
      return 0.0;
     }

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   // Zaokrouhlení dolů na krok objemu, aby riziko nepřekročilo nastavené procento
   double volume = MathFloor(riskMoney / -lossPerLot / step) * step;
   if(volume < minVolume)
     {
      Print("Signál přeskočen: objem pro riziko ", InpRiskPercent, " % je pod minimem ", minVolume);
      return 0.0;
     }
   return NormalizeDouble(MathMin(volume, maxVolume), 8);
  }

//+------------------------------------------------------------------+
