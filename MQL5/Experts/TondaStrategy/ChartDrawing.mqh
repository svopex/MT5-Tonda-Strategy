//+------------------------------------------------------------------+
//|                                                 ChartDrawing.mqh |
//| Kreslení grafu jako v TradingView přímo z experta: Bollinger     |
//| Bands (docs/BollingerBands.pine) a Svopex SMC                    |
//| (docs/SvopexSMC.pine) – order blocky, BOS/CHoCH, EQH/EQL         |
//| a Strong/Weak High/Low. Vyplněné zóny jsou v průhledné bitmapě,  |
//| čáry a popisky jsou grafické objekty.                            |
//+------------------------------------------------------------------+
#include "OrderBlocks.mqh"
#include "ZoneCanvas.mqh"

// Prefixy objektů: trvalé události struktury, čáry Strong/Weak a úseky Bollinger Bands
#define EVENT_PREFIX     "TondaE_"
#define TRAILING_PREFIX  "TondaT_"
#define BANDS_PREFIX     "TondaB_"

// Bitmapa s vyplněnými zónami a interval časovače experta, který hlídá změnu pohledu grafu
// (nejvýš 5 překreslení za sekundu)
#define CANVAS_NAME                "TondaCanvas"
#define CANVAS_CHECK_INTERVAL_MS   200

// Limit trvalých čar struktury (v Pine max_lines_count = 500) a počet mitigovaných OB
#define MAX_EVENT_OBJECTS   500
#define MITIGATED_COUNT     5

// Jak daleko doprava sahají čáry Strong/Weak (20 svíček v Pine); aktivní OB sahají k pravému okraji grafu
#define TRAILING_EXTEND_BARS  20

// Tečkovaný okraj mitigovaného OB: délka čárky a mezery v pixelech
#define DOT_LENGTH  2
#define DOT_GAP     2

// Barvy tmavého motivu TradingView a indikátorů z Pine
#define COLOR_BACKGROUND        C'12,12,12'
#define COLOR_FOREGROUND        C'178,181,190'
#define COLOR_BULLISH           C'8,153,129'
#define COLOR_BEARISH           C'242,54,69'
#define COLOR_BANDS_BASIS       C'41,98,255'
#define COLOR_BANDS_FILL        C'33,150,243'
#define COLOR_INTERNAL_BULLISH  C'49,121,245'
#define COLOR_SWING_BULLISH     C'24,72,204'
// Medvědí (short) OB, internal i swing, jsou na přání zelené místo červených z Pine
#define COLOR_BLOCK_BEARISH     COLOR_BULLISH
// Mitigované OB mají jednu šedou pro oba směry
#define COLOR_MITIGATED         C'120,123,134'

// Průhlednosti barev z Pine (0 = neprůhledná, 100 = neviditelná)
#define BANDS_FILL_TRANSPARENCY       95
#define BLOCK_TRANSPARENCY            80
#define MITIGATED_TRANSPARENCY        85
#define MITIGATED_BORDER_TRANSPARENCY 50

// Velikosti písma odpovídající size.tiny a size.small v TradingView
#define FONT_TINY   6
#define FONT_SMALL  7
#define LABEL_FONT  "Arial"

// Vlastnosti grafu měněné motivem a jejich hodnoty (stejné pořadí); původní hodnoty se po odebrání experta vrátí
const ENUM_CHART_PROPERTY_INTEGER THEME_PROPERTIES[] = {CHART_MODE, CHART_SHOW_GRID, CHART_COLOR_BACKGROUND,
                                                       CHART_COLOR_FOREGROUND, CHART_COLOR_CHART_UP,
                                                       CHART_COLOR_CANDLE_BULL, CHART_COLOR_CHART_DOWN,
                                                       CHART_COLOR_CANDLE_BEAR, CHART_COLOR_CHART_LINE};
const long THEME_VALUES[] = {CHART_CANDLES, false, COLOR_BACKGROUND, COLOR_FOREGROUND, COLOR_BULLISH,
                             COLOR_BULLISH, COLOR_BEARISH, COLOR_BEARISH, COLOR_BULLISH};

//+------------------------------------------------------------------+
//| Je výstup do grafu vidět? V testeru bez vizualizace ne, kreslit  |
//| a vypisovat by jen zpomalovalo                                   |
//+------------------------------------------------------------------+
bool IsChartVisible()
  {
   return !MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE);
  }

//+------------------------------------------------------------------+
//| Hodnoty Bollinger Bands jedné svíčky                             |
//+------------------------------------------------------------------+
struct SBandValues
  {
   double            basis;
   double            upper;
   double            lower;
  };

//+------------------------------------------------------------------+
//| Nastavení, co se má kreslit                                      |
//+------------------------------------------------------------------+
struct SChartDrawingSettings
  {
   bool              enabled;
   int               blocksCount;
   bool              showMitigatedBlocks;
   bool              showInternalStructure;
   bool              showSwingStructure;
   bool              showEqualHighsLows;
   bool              showStrongWeak;
   int               bandsBars;          // počet svíček, pro které se kreslí Bollinger Bands
  };

//+------------------------------------------------------------------+
//| Kreslení vizuálu TradingView. Při vypnutém kreslení (nebo        |
//| v testeru bez vizualizace) nedělá nic.                           |
//+------------------------------------------------------------------+
class CChartDrawing
  {
private:
   SChartDrawingSettings m_settings;
   bool              m_enabled;
   int               m_bandsHandle;
   COrderBlockDetector *m_detector;
   CZoneCanvas       m_canvas;          // výplň BB a order blocky s průhledností
   int               m_eventCount;      // počet vykreslených událostí struktury
   long              m_savedColors[];   // původní hodnoty THEME_PROPERTIES
   datetime          m_currentSegment;  // začátek úseku BB končícího na tvořené svíčce (0 = BB ještě nejsou)
   datetime          m_oldestSegment;   // začátek nejstaršího nakresleného úseku BB

public:
   // settings – co kreslit, bandsHandle – handle iBands experta, detector – zdroj struktury a OB
   void              Init(const SChartDrawingSettings &settings, const int bandsHandle, COrderBlockDetector &detector)
     {
      m_enabled = settings.enabled && IsChartVisible();
      if(!m_enabled)
         return;

      m_settings       = settings;
      m_bandsHandle    = bandsHandle;
      m_detector       = GetPointer(detector);
      m_eventCount     = 0;
      m_currentSegment = 0;
      m_oldestSegment  = 0;
      Clear();
      ApplyChartColors();

      // Bitmapa vzniká před čarami BB, aby ležela pod nimi
      m_canvas.Open(CANVAS_NAME);
     }

   // Smaže všechny objekty a vrátí původní barvy grafu
   void              Deinit()
     {
      if(!m_enabled)
         return;
      Clear();
      m_canvas.Destroy();
      RestoreChartColors();
     }

   //+---------------------------------------------------------------+
   //| Obnoví graf na ticku. Na nové svíčce dokreslí BB, nové        |
   //| události struktury a překreslí zóny; jinak jen posune úsek BB |
   //| tvořené svíčky. newBar – přibyla uzavřená svíčka,             |
   //| current – hodnoty BB tvořené svíčky                           |
   //+---------------------------------------------------------------+
   void              Refresh(const bool newBar, const SBandValues &current)
     {
      if(!m_enabled)
         return;

      if(!newBar && m_currentSegment != 0)
        {
         MoveCurrentSegment(current);
         return;
        }

      // Dokud nejsou data BB, zkouší se to znovu na dalším ticku
      if(!SyncBands())
         return;
      DrawEvents();
      DrawTrailing();
      DrawCanvas();
     }

   //+---------------------------------------------------------------+
   //| Časovač: posun, zoom, změna velikosti grafu i automatického   |
   //| měřítka ceny posunou zóny v pixelech, bitmapa se překreslí.   |
   //| Funguje i bez ticků a v testeru, kde nechodí události grafu.  |
   //+---------------------------------------------------------------+
   void              OnTimer()
     {
      if(m_enabled && m_currentSegment != 0 && m_canvas.ViewChanged())
         DrawCanvas();
     }

private:
   void              Clear()
     {
      ObjectsDeleteAll(0, EVENT_PREFIX);
      ObjectsDeleteAll(0, TRAILING_PREFIX);
      ObjectsDeleteAll(0, BANDS_PREFIX);
     }

   // Barvy grafu podle tmavého motivu TradingView; původní hodnoty se uloží
   void              ApplyChartColors()
     {
      int count = ArraySize(THEME_PROPERTIES);
      ArrayResize(m_savedColors, count);
      for(int i = 0; i < count; i++)
        {
         m_savedColors[i] = ChartGetInteger(0, THEME_PROPERTIES[i]);
         ChartSetInteger(0, THEME_PROPERTIES[i], THEME_VALUES[i]);
        }
     }

   void              RestoreChartColors()
     {
      for(int i = 0; i < ArraySize(m_savedColors); i++)
         ChartSetInteger(0, THEME_PROPERTIES[i], m_savedColors[i]);
      ArrayFree(m_savedColors);
     }

   //+---------------------------------------------------------------+
   //| Vykreslí nové události struktury z detektoru: čáru BOS/CHoCH  |
   //| nebo EQH/EQL a popisek uprostřed                              |
   //+---------------------------------------------------------------+
   void              DrawEvents()
     {
      SStructureEvent events[];
      int count = m_detector.TakeEvents(events);
      for(int i = 0; i < count; i++)
        {
         SStructureEvent event = events[i];
         bool visible = (event.kind == STRUCTURE_INTERNAL && m_settings.showInternalStructure) ||
                        (event.kind == STRUCTURE_SWING && m_settings.showSwingStructure) ||
                        (event.kind == STRUCTURE_EQUAL && m_settings.showEqualHighsLows);
         if(!visible)
            continue;

         // Styl podle Pine: internal čárkovaně, swing plně, EQH/EQL tečkovaně
         ENUM_LINE_STYLE style = STYLE_SOLID;
         if(event.kind == STRUCTURE_INTERNAL)
            style = STYLE_DASH;
         else if(event.kind == STRUCTURE_EQUAL)
            style = STYLE_DOT;
         color  eventColor = event.bias == OB_BULLISH ? COLOR_BULLISH : COLOR_BEARISH;
         string text       = event.kind == STRUCTURE_EQUAL ? (event.bias == OB_BEARISH ? "EQH" : "EQL")
                                                           : (event.choch ? "CHoCH" : "BOS");

         // Popisek nad čarou u prolomení nahoru a u EQH, jinak pod čarou
         bool above = event.kind == STRUCTURE_EQUAL ? event.bias == OB_BEARISH : event.bias == OB_BULLISH;
         int  font  = event.kind == STRUCTURE_SWING ? FONT_SMALL : FONT_TINY;

         // Uvolnění nejstarší události nad limit (jako max_lines_count v Pine)
         if(m_eventCount >= MAX_EVENT_OBJECTS)
           {
            string oldest = EVENT_PREFIX + IntegerToString(m_eventCount - MAX_EVENT_OBJECTS) + "_";
            ObjectDelete(0, oldest + "L");
            ObjectDelete(0, oldest + "T");
           }

         string name = EVENT_PREFIX + IntegerToString(m_eventCount++) + "_";
         CreateLine(name + "L", event.fromTime, event.fromLevel, event.toTime, event.toLevel, eventColor, style, false);

         // Popisek na svíčce uprostřed čáry (při lichém počtu svíček ta novější, jako round v Pine)
         int middleShift = (iBarShift(_Symbol, _Period, event.fromTime) + iBarShift(_Symbol, _Period, event.toTime)) / 2;
         CreateText(name + "T", iTime(_Symbol, _Period, middleShift), event.toLevel, text, eventColor, font,
                    above ? ANCHOR_LOWER : ANCHOR_UPPER);
        }
     }

   //+---------------------------------------------------------------+
   //| Doplní úseky BB od posledního nakresleného po tvořenou svíčku |
   //| a smaže úseky mimo kreslený rozsah. Úsek začíná na svíčce     |
   //| shift a končí na svíčce shift-1. Vrací false, chybí-li data.  |
   //+---------------------------------------------------------------+
   bool              SyncBands()
     {
      // Při startu celý rozsah, jinak od dosavadního úseku tvořené svíčky (dostane konečné hodnoty)
      int firstShift = m_settings.bandsBars;
      if(m_currentSegment != 0)
         firstShift = MathMin(iBarShift(_Symbol, _Period, m_currentSegment), m_settings.bandsBars);

      int bars = firstShift + 1;
      double basis[], upper[], lower[];
      datetime times[];
      ArraySetAsSeries(basis, true);
      ArraySetAsSeries(upper, true);
      ArraySetAsSeries(lower, true);
      ArraySetAsSeries(times, true);
      if(CopyBuffer(m_bandsHandle, BASE_LINE, 0, bars, basis) != bars ||
         CopyBuffer(m_bandsHandle, UPPER_BAND, 0, bars, upper) != bars ||
         CopyBuffer(m_bandsHandle, LOWER_BAND, 0, bars, lower) != bars ||
         CopyTime(_Symbol, _Period, 0, bars, times) != bars)
         return false;

      if(m_currentSegment != 0)
         DeleteSegment(m_currentSegment);
      for(int shift = firstShift; shift >= 1; shift--)
         CreateSegment(times[shift], basis[shift], upper[shift], lower[shift],
                       times[shift - 1], basis[shift - 1], upper[shift - 1], lower[shift - 1]);
      m_currentSegment = times[1];
      if(m_oldestSegment == 0)
         m_oldestSegment = times[firstShift];

      // Úseky, které vypadly z kresleného rozsahu, se mažou od nejstaršího
      int oldestShift = iBarShift(_Symbol, _Period, m_oldestSegment);
      while(oldestShift > m_settings.bandsBars)
        {
         DeleteSegment(m_oldestSegment);
         oldestShift--;
         m_oldestSegment = iTime(_Symbol, _Period, oldestShift);
        }
      return true;
     }

   //+---------------------------------------------------------------+
   //| Nakreslí jeden úsek linií BB (výplň je v bitmapě). Úseky bez  |
   //| hodnoty (před první periodou) se vynechají.                   |
   //+---------------------------------------------------------------+
   void              CreateSegment(const datetime t1, const double basis1, const double upper1, const double lower1,
                                   const datetime t2, const double basis2, const double upper2, const double lower2)
     {
      if(basis1 == EMPTY_VALUE || basis1 == 0.0)
         return;
      string name = BANDS_PREFIX + IntegerToString((long)t1);
      CreateLine(name + "B", t1, basis1, t2, basis2, COLOR_BANDS_BASIS, STYLE_SOLID, true);
      CreateLine(name + "U", t1, upper1, t2, upper2, COLOR_BEARISH, STYLE_SOLID, true);
      CreateLine(name + "L", t1, lower1, t2, lower2, COLOR_BULLISH, STYLE_SOLID, true);
     }

   //+---------------------------------------------------------------+
   //| Posune pravý konec úseku BB tvořené svíčky na aktuální hodnoty|
   //| (levý konec leží na uzavřené svíčce a nemění se)              |
   //+---------------------------------------------------------------+
   void              MoveCurrentSegment(const SBandValues &current)
     {
      string name = BANDS_PREFIX + IntegerToString((long)m_currentSegment);
      ObjectSetDouble(0, name + "B", OBJPROP_PRICE, 1, current.basis);
      ObjectSetDouble(0, name + "U", OBJPROP_PRICE, 1, current.upper);
      ObjectSetDouble(0, name + "L", OBJPROP_PRICE, 1, current.lower);
     }

   void              DeleteSegment(const datetime startTime)
     {
      string name = BANDS_PREFIX + IntegerToString((long)startTime);
      string parts[] = {"B", "U", "L"};
      for(int i = 0; i < ArraySize(parts); i++)
         ObjectDelete(0, name + parts[i]);
     }

   //+---------------------------------------------------------------+
   //| Překreslí bitmapu: výplň BB a order blocky. Vypnutá struktura |
   //| nemá žádné OB, takže se pro ni nic nenakreslí.                |
   //+---------------------------------------------------------------+
   void              DrawCanvas()
     {
      m_canvas.Begin();
      DrawBandsFill();
      for(int kind = 0; kind < 2; kind++)
        {
         bool internal = kind == 0;
         CMarketStructure *structure = m_detector.Structure(internal);
         if(m_settings.showMitigatedBlocks)
            DrawBlocks(structure.m_mitigated, MITIGATED_COUNT, internal, true);
         DrawBlocks(structure.m_blocks, m_settings.blocksCount, internal, false);
        }
      m_canvas.Update(true);
     }

   //+---------------------------------------------------------------+
   //| Výplň mezi horním a dolním pásmem BB pro viditelné svíčky     |
   //| (nejvýše v rozsahu kreslených linií BB)                       |
   //+---------------------------------------------------------------+
   void              DrawBandsFill()
     {
      int bars = (int)MathMin(ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR), m_settings.bandsBars) + 1;
      if(bars < 2)
         return;

      double upper[], lower[];
      datetime times[];
      ArraySetAsSeries(upper, true);
      ArraySetAsSeries(lower, true);
      ArraySetAsSeries(times, true);
      if(CopyBuffer(m_bandsHandle, UPPER_BAND, 0, bars, upper) != bars ||
         CopyBuffer(m_bandsHandle, LOWER_BAND, 0, bars, lower) != bars ||
         CopyTime(_Symbol, _Period, 0, bars, times) != bars)
         return;

      // Mezi středy sousedních svíček se hranice pásma lineárně prokládají po sloupcích pixelů;
      // body předchozí svíčky se použijí znovu
      int  previousX = 0, previousUpper = 0, previousLower = 0;
      bool hasPrevious = false;
      for(int shift = bars - 1; shift >= 0; shift--)
        {
         int x, yUpper, yLower;
         if(upper[shift] == EMPTY_VALUE || upper[shift] == 0.0 ||
            !m_canvas.ToXY(times[shift], upper[shift], x, yUpper) ||
            !m_canvas.ToXY(times[shift], lower[shift], x, yLower))
           {
            hasPrevious = false;
            continue;
           }

         for(int column = previousX; hasPrevious && column < x; column++)
           {
            double ratio = (double)(column - previousX) / (x - previousX);
            m_canvas.FillRect(column, (int)MathRound(previousUpper + (yUpper - previousUpper) * ratio),
                              column, (int)MathRound(previousLower + (yLower - previousLower) * ratio),
                              COLOR_BANDS_FILL, BANDS_FILL_TRANSPARENCY);
           }
         previousX     = x;
         previousUpper = yUpper;
         previousLower = yLower;
         hasPrevious   = true;
        }
     }

   //+---------------------------------------------------------------+
   //| Vykreslí nejvýše count nejnovějších OB ze seznamu do bitmapy. |
   //| internal – barva internal/swing OB, mitigated – zneplatněné   |
   //| OB (box končí na svíčce mitigace, tečkovaný okraj); aktivní   |
   //| OB sahají k pravému okraji grafu (extend.right v Pine)        |
   //+---------------------------------------------------------------+
   void              DrawBlocks(const SOrderBlock &blocks[], const int count, const bool internal, const bool mitigated)
     {
      int total = MathMin(count, ArraySize(blocks));
      for(int i = 0; i < total; i++)
        {
         // Internal a swing se barvou liší jen u býčích OB
         color base = mitigated                      ? COLOR_MITIGATED
                      : blocks[i].bias != OB_BULLISH ? COLOR_BLOCK_BEARISH
                      : internal                     ? COLOR_INTERNAL_BULLISH
                                                     : COLOR_SWING_BULLISH;

         // OB starší než historie grafu se nekreslí; mitigovaný končí na svíčce mitigace
         int left, top, bottom, right = m_canvas.Width(), unused;
         if(!m_canvas.ToXY(blocks[i].time, blocks[i].high, left, top) ||
            !m_canvas.ToXY(blocks[i].time, blocks[i].low, left, bottom) ||
            (mitigated && !m_canvas.ToXY(blocks[i].mitigatedTime, blocks[i].low, right, unused)))
            continue;
         m_canvas.FillRect(left, top, right, bottom, base, mitigated ? MITIGATED_TRANSPARENCY : BLOCK_TRANSPARENCY);

         // Mitigovaný OB má tečkovaný okraj se sytější barvou, swing OB plný okraj (jako v Pine)
         if(mitigated)
            m_canvas.BorderRect(left, top, right, bottom, base, MITIGATED_BORDER_TRANSPARENCY, DOT_LENGTH, DOT_GAP);
         else if(!internal)
            m_canvas.BorderRect(left, top, right, bottom, base, BLOCK_TRANSPARENCY, 1, 0);
        }
     }

   //+---------------------------------------------------------------+
   //| Strong/Weak High a Low: čára od posledního extrému doprava    |
   //| a popisek podle trendu swing struktury (grafické objekty)     |
   //+---------------------------------------------------------------+
   void              DrawTrailing()
     {
      ObjectsDeleteAll(0, TRAILING_PREFIX);
      if(!m_settings.showStrongWeak)
         return;

      datetime          rightTime = iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period) * TRAILING_EXTEND_BARS;
      STrailingExtremes trailing  = m_detector.Trailing();
      int               trend     = m_detector.SwingTrend();

      if(trailing.top != NO_LEVEL)
        {
         CreateLine(TRAILING_PREFIX + "TopL", trailing.topTime, trailing.top, rightTime, trailing.top, COLOR_BEARISH, STYLE_SOLID, false);
         CreateText(TRAILING_PREFIX + "TopT", rightTime, trailing.top, trend == OB_BEARISH ? "Strong High" : "Weak High",
                    COLOR_BEARISH, FONT_TINY, ANCHOR_LOWER);
        }
      if(trailing.bottom != NO_LEVEL)
        {
         CreateLine(TRAILING_PREFIX + "BottomL", trailing.bottomTime, trailing.bottom, rightTime, trailing.bottom, COLOR_BULLISH, STYLE_SOLID, false);
         CreateText(TRAILING_PREFIX + "BottomT", rightTime, trailing.bottom, trend == OB_BULLISH ? "Strong Low" : "Weak Low",
                    COLOR_BULLISH, FONT_TINY, ANCHOR_UPPER);
        }
     }

   //+---------------------------------------------------------------+
   //| Pomocné funkce pro vytvoření grafických objektů               |
   //+---------------------------------------------------------------+
   // Společné vlastnosti: barva, kreslení za svíčkami (back), nevybíratelné a skryté v seznamu objektů
   void              SetCommon(const string name, const color objectColor, const bool back)
     {
      ObjectSetInteger(0, name, OBJPROP_COLOR, objectColor);
      ObjectSetInteger(0, name, OBJPROP_BACK, back);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }

   // back – kreslit za svíčkami (pásma BB), jinak nad nimi (struktura)
   void              CreateLine(const string name, const datetime time1, const double price1,
                                const datetime time2, const double price2, const color lineColor,
                                const ENUM_LINE_STYLE style, const bool back)
     {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2))
         return;
      SetCommon(name, lineColor, back);
      ObjectSetInteger(0, name, OBJPROP_STYLE, style);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
     }

   // anchor – ANCHOR_LOWER = text nad bodem, ANCHOR_UPPER = text pod bodem
   void              CreateText(const string name, const datetime time1, const double price1, const string text,
                                const color textColor, const int fontSize, const ENUM_ANCHOR_POINT anchor)
     {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, time1, price1))
         return;
      SetCommon(name, textColor, false);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, LABEL_FONT);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
     }

  };
//+------------------------------------------------------------------+
