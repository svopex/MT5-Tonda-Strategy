//+------------------------------------------------------------------+
//|                                                  OrderBlocks.mqh |
//| Detekce struktury trhu a order blocků převzatá z indikátoru      |
//| Svopex SMC (LuxAlgo Smart Money Concepts, docs/SvopexSMC.pine).  |
//+------------------------------------------------------------------+

#define OB_BULLISH        1
#define OB_BEARISH       -1

#define LEG_BEARISH       0
#define LEG_BULLISH       1

// Maximální počet uchovávaných order blocků v jednom seznamu (stejně jako v Pine)
#define OB_MAX_STORED     100

// Maximální počet nevyzvednutých událostí struktury (víc se jich ani nekreslí)
#define EVENTS_MAX_STORED 500

// Délky ATR použité v indikátoru: 200 pro filtr volatilních svíček a EQH/EQL, 14 pro toleranci nového OB
#define ATR_FILTER_LENGTH     200
#define ATR_TOLERANCE_LENGTH  14

// Hodnota úrovně swingu, která ještě nebyla nalezena (ceny jsou vždy kladné)
const double NO_LEVEL = 0.0;

// Zdroj ceny pro mitigaci (zneplatnění) order blocku
enum ENUM_OB_MITIGATION
  {
   OB_MITIGATION_HIGHLOW, // High/Low
   OB_MITIGATION_CLOSE    // Close
  };

// Druh struktury: swing, internal, nebo krátká struktura pro rovná high/low
enum ENUM_STRUCTURE_KIND
  {
   STRUCTURE_SWING,
   STRUCTURE_INTERNAL,
   STRUCTURE_EQUAL
  };

//+------------------------------------------------------------------+
//| Wilderův klouzavý průměr (RMA) – stejný výpočet jako ta.rma      |
//| a ta.atr v Pine: první hodnota je SMA, dál rekurzivní vyhlazení. |
//+------------------------------------------------------------------+
class CRma
  {
private:
   int               m_length;
   int               m_count;
   double            m_sum;
   double            m_value;

public:
   // length – počet period průměru
   void              Init(const int length) { m_length = length; m_count = 0; m_sum = 0.0; m_value = 0.0; }

   // Přidá novou hodnotu a vrátí aktuální RMA (0, dokud není dost dat)
   double            Update(const double value)
     {
      // Rozběh: sčítáme hodnoty, dokud nemáme celou periodu pro první SMA
      if(m_count < m_length)
        {
         m_sum += value;
         if(++m_count == m_length)
            m_value = m_sum / m_length;
        }
      else
         m_value = (value + (m_length - 1) * m_value) / m_length;
      return m_value;
     }

   double            Value() const { return m_value; }
  };

//+------------------------------------------------------------------+
//| Zpracovaná svíčka v kruhovém bufferu detektoru                   |
//+------------------------------------------------------------------+
struct SBar
  {
   double            high;
   double            low;
   double            close;
   double            parsedHigh; // u volatilní svíčky prohozené s low (jako v Pine)
   double            parsedLow;
   datetime          time;
  };

//+------------------------------------------------------------------+
//| Swing bod (pivot) struktury trhu a kandidát na order block       |
//| (extrém parsed low/high od pivotu po předchozí svíčku)           |
//+------------------------------------------------------------------+
struct SPivot
  {
   double            level;      // aktuální úroveň swingu (NO_LEVEL = zatím neexistuje)
   double            prevLevel;  // úroveň platná na předchozí svíčce (pro detekci křížení)
   bool              crossed;    // úroveň už byla prolomena
   datetime          time;       // čas svíčky swingu
   double            blockHigh;  // parsed high svíčky kandidáta na OB
   double            blockLow;   // parsed low svíčky kandidáta na OB
   datetime          blockTime;  // čas svíčky kandidáta na OB
  };

//+------------------------------------------------------------------+
//| Order block                                                      |
//+------------------------------------------------------------------+
struct SOrderBlock
  {
   int               id;            // jednoznačný identifikátor OB
   double            high;          // horní hrana (u volatilní svíčky prohozená s low, jako v Pine)
   double            low;           // dolní hrana
   datetime          time;          // čas svíčky order blocku
   int               bias;          // OB_BULLISH (býčí, long) nebo OB_BEARISH (medvědí, short)
   int               createdBar;    // index svíčky, na které OB vznikl
   bool              used;          // z OB už vzešel signál
   datetime          mitigatedTime; // čas svíčky, která OB zneplatnila (0 = aktivní)

   // Geometrie zóny nezávisle na prohození hran u volatilní svíčky
   double            Top() const    { return MathMax(high, low); }
   double            Bottom() const { return MathMin(high, low); }
  };

//+------------------------------------------------------------------+
//| Událost struktury pro vykreslení: prolomení (BOS/CHoCH) swing    |
//| nebo internal struktury, případně rovná high/low (EQH/EQL).      |
//| Čára vede z bodu "from" do bodu "to", popisek patří doprostřed.  |
//+------------------------------------------------------------------+
struct SStructureEvent
  {
   ENUM_STRUCTURE_KIND kind;
   int               bias;       // prolomení: OB_BULLISH nahoru / OB_BEARISH dolů; EQL = OB_BULLISH, EQH = OB_BEARISH
   bool              choch;      // prolomení proti dosavadnímu trendu (CHoCH), jinak BOS
   datetime          fromTime;
   double            fromLevel;
   datetime          toTime;
   double            toLevel;
  };

//+------------------------------------------------------------------+
//| Poslední swing high/low upravované průběžnými extrémy ceny       |
//| (Strong/Weak High a Low v Pine)                                  |
//+------------------------------------------------------------------+
struct STrailingExtremes
  {
   double            top;
   datetime          topTime;
   double            bottom;
   datetime          bottomTime;
  };

//+------------------------------------------------------------------+
//| Stav jedné struktury trhu                                        |
//+------------------------------------------------------------------+
class CMarketStructure
  {
public:
   ENUM_STRUCTURE_KIND m_kind;
   int               m_length;      // počet svíček pro potvrzení swingu
   bool              m_storeBlocks; // ukládat order blocky této struktury
   int               m_leg;         // aktuální směr nohy (LEG_BULLISH / LEG_BEARISH)
   int               m_trend;       // směr posledního prolomení (OB_BULLISH / OB_BEARISH, 0 = žádné)
   SPivot            m_high;
   SPivot            m_low;
   SOrderBlock       m_blocks[];    // aktivní order blocky, nejnovější na indexu 0
   SOrderBlock       m_mitigated[]; // zneplatněné order blocky, nejnovější na indexu 0

   // kind – druh struktury, length – délka struktury, storeBlocks – zda z prolomení vytvářet OB
   void              Init(const ENUM_STRUCTURE_KIND kind, const int length, const bool storeBlocks)
     {
      m_kind        = kind;
      m_length      = length;
      m_storeBlocks = storeBlocks;
      m_leg         = LEG_BEARISH;
      m_trend       = 0;
      ZeroMemory(m_high);
      ZeroMemory(m_low);
      ArrayResize(m_blocks, 0);
      ArrayResize(m_mitigated, 0);
     }
  };

//+------------------------------------------------------------------+
//| Detektor struktury a order blocků zpracovávající uzavřené svíčky |
//| postupně od nejstarší. Logika odpovídá funkcím Pine              |
//| getCurrentStructure, displayStructure, storeOrdeBlock,           |
//| deleteOrderBlocks a updateTrailingExtremes.                      |
//+------------------------------------------------------------------+
class COrderBlockDetector
  {
private:
   CMarketStructure  m_swing;
   CMarketStructure  m_internal;
   CMarketStructure  m_equal;
   CRma              m_atrFilter;
   CRma              m_atrTolerance;
   ENUM_OB_MITIGATION m_mitigation;
   double            m_equalThreshold; // citlivost EQH/EQL v násobcích ATR(200)
   int               m_barIndex;       // index poslední zpracované svíčky (-1 = žádná)
   int               m_nextBlockId;
   STrailingExtremes m_trailing;
   SStructureEvent   m_events[];       // události struktury čekající na vyzvednutí (TakeEvents)

   // Kruhový buffer posledních svíček; stačí délka nejdelší struktury + 1
   SBar              m_bars[];
   int               m_ringSize;

public:
   // swingLength/internalLength – délky struktur (>= 1), useSwing/useInternal – které OB ukládat,
   // mitigation – zdroj ceny pro zneplatnění OB, equalLength/equalThreshold – detekce EQH/EQL
   void              Init(const int swingLength, const int internalLength,
                          const bool useSwing, const bool useInternal,
                          const ENUM_OB_MITIGATION mitigation,
                          const int equalLength = 3, const double equalThreshold = 0.1)
     {
      m_swing.Init(STRUCTURE_SWING, swingLength, useSwing);
      m_internal.Init(STRUCTURE_INTERNAL, internalLength, useInternal);
      m_equal.Init(STRUCTURE_EQUAL, equalLength, false);
      m_atrFilter.Init(ATR_FILTER_LENGTH);
      m_atrTolerance.Init(ATR_TOLERANCE_LENGTH);
      m_mitigation     = mitigation;
      m_equalThreshold = equalThreshold;
      m_barIndex       = -1;
      m_nextBlockId    = 0;
      ZeroMemory(m_trailing);
      ArrayResize(m_events, 0);
      m_ringSize = MathMax(MathMax(swingLength, internalLength), equalLength) + 1;
      ArrayResize(m_bars, m_ringSize);
     }

   //+---------------------------------------------------------------+
   //| Zpracuje jednu uzavřenou svíčku (volat chronologicky)         |
   //+---------------------------------------------------------------+
   void              ProcessBar(const MqlRates &bar)
     {
      m_barIndex++;
      StoreBar(bar);

      // Pořadí kroků odpovídá Pine: trailing extrémy, swingy, prolomení internal, prolomení swing, mitigace
      UpdateTrailing();
      UpdatePivots(m_swing);
      UpdatePivots(m_internal);
      UpdatePivots(m_equal);

      // Internal swing splývající se swing strukturou se neprolamuje (extraCondition v Pine)
      bool internalHighAllowed = m_internal.m_high.level != m_swing.m_high.level;
      bool internalLowAllowed  = m_internal.m_low.level != m_swing.m_low.level;
      DetectBreaks(m_internal, internalHighAllowed, internalLowAllowed);
      DetectBreaks(m_swing, true, true);
      MitigateBlocks(m_internal);
      MitigateBlocks(m_swing);
     }

   //+---------------------------------------------------------------+
   //| Hledá vstupní signál na aktuálním ticku: nový OB poblíž ceny  |
   //| nebo dotek OB zvenku v právě tvořené svíčce.                  |
   //| bias – hledaný směr, maxBlocks – kolik nejnovějších OB        |
   //| kontrolovat, toleranceAtr – tolerance nového OB v násobcích   |
   //| ATR(14), price – aktuální cena, currentLow/currentHigh –      |
   //| extrémy tvořené svíčky, signal – nalezený OB                  |
   //+---------------------------------------------------------------+
   bool              FindSignal(const int bias, const int maxBlocks, const double toleranceAtr,
                                const double price, const double currentLow, const double currentHigh,
                                SOrderBlock &signal)
     {
      double tolerance = toleranceAtr * m_atrTolerance.Value();
      if(FindSignalIn(m_internal, bias, maxBlocks, tolerance, price, currentLow, currentHigh, signal))
         return true;
      return FindSignalIn(m_swing, bias, maxBlocks, tolerance, price, currentLow, currentHigh, signal);
     }

   //+---------------------------------------------------------------+
   //| Označí OB jako použitý, aby z něj nevzešel další signál       |
   //+---------------------------------------------------------------+
   void              MarkUsed(const int blockId)
     {
      MarkUsedIn(m_internal, blockId);
      MarkUsedIn(m_swing, blockId);
     }

   // Struktura s aktivními a zneplatněnými OB pro vykreslení (internal nebo swing)
   CMarketStructure *Structure(const bool internal) { return internal ? GetPointer(m_internal) : GetPointer(m_swing); }

   //+---------------------------------------------------------------+
   //| Předá dosud nevyzvednuté události struktury (od nejstarší)    |
   //| a vyprázdní frontu. Vrací počet událostí v out.               |
   //+---------------------------------------------------------------+
   int               TakeEvents(SStructureEvent &out[])
     {
      ArrayFree(out);
      ArraySwap(m_events, out);
      return ArraySize(out);
     }

   // Strong/Weak High a Low: trailing extrémy a trend swing struktury
   STrailingExtremes Trailing() const { return m_trailing; }
   int               SwingTrend() const { return m_swing.m_trend; }

private:
   // Svíčka podle absolutního indexu (musí být v rozsahu kruhového bufferu)
   SBar              Bar(const int index) const { return m_bars[index % m_ringSize]; }

   //+---------------------------------------------------------------+
   //| Uloží svíčku do bufferu a spočítá "parsed" high/low:          |
   //| u velmi volatilní svíčky (rozpětí >= 2× ATR(200)) se high     |
   //| a low prohodí, aby nebyla vybrána jako extrém order blocku.   |
   //+---------------------------------------------------------------+
   void              StoreBar(const MqlRates &bar)
     {
      const int k = m_barIndex;

      // True range; první svíčka nemá předchozí close, bere se jen rozpětí
      double range     = bar.high - bar.low;
      double trueRange = range;
      if(k > 0)
        {
         double prevClose = Bar(k - 1).close;
         trueRange = MathMax(range, MathMax(MathAbs(bar.high - prevClose), MathAbs(bar.low - prevClose)));
        }
      double atr = m_atrFilter.Update(trueRange);
      m_atrTolerance.Update(trueRange);

      bool highVolatilityBar = atr > 0.0 && range >= 2.0 * atr;
      SBar stored;
      stored.high       = bar.high;
      stored.low        = bar.low;
      stored.close      = bar.close;
      stored.time       = bar.time;
      stored.parsedHigh = highVolatilityBar ? bar.low : bar.high;
      stored.parsedLow  = highVolatilityBar ? bar.high : bar.low;
      m_bars[k % m_ringSize] = stored;
     }

   //+---------------------------------------------------------------+
   //| Posune trailing extrémy na nové maximum/minimum ceny          |
   //| (updateTrailingExtremes v Pine; před prvním swingem neplatí)  |
   //+---------------------------------------------------------------+
   void              UpdateTrailing()
     {
      SBar current = Bar(m_barIndex);
      if(m_trailing.top != NO_LEVEL && current.high >= m_trailing.top)
        {
         m_trailing.top     = current.high;
         m_trailing.topTime = current.time;
        }
      if(m_trailing.bottom != NO_LEVEL && current.low <= m_trailing.bottom)
        {
         m_trailing.bottom     = current.low;
         m_trailing.bottomTime = current.time;
        }
     }

   //+---------------------------------------------------------------+
   //| Hledá nové swingy (funkce leg/getCurrentStructure v Pine).    |
   //| Svíčka před m_length svíčkami je swing high, pokud je její    |
   //| high vyšší než všechna následující high (a obdobně low).      |
   //+---------------------------------------------------------------+
   void              UpdatePivots(CMarketStructure &structure)
     {
      const int length = structure.m_length;
      const int k      = m_barIndex;
      if(k < length)
         return;

      int    pivotBar = k - length;
      double maxHigh  = -DBL_MAX;
      double minLow   = DBL_MAX;
      for(int i = pivotBar + 1; i <= k; i++)
        {
         maxHigh = MathMax(maxHigh, Bar(i).high);
         minLow  = MathMin(minLow, Bar(i).low);
        }

      // Nový swing high zahajuje medvědí nohu, nový swing low býčí nohu
      SBar pivotCandle = Bar(pivotBar);
      int  leg         = structure.m_leg;
      if(pivotCandle.high > maxHigh)
         leg = LEG_BEARISH;
      else if(pivotCandle.low < minLow)
         leg = LEG_BULLISH;

      if(leg == structure.m_leg)
         return;
      structure.m_leg = leg;

      // Začátek býčí nohy potvrzuje swing low, začátek medvědí nohy swing high
      if(leg == LEG_BEARISH)
         SetPivot(structure, structure.m_high, pivotBar, true);
      else
         SetPivot(structure, structure.m_low, pivotBar, false);
     }

   //+---------------------------------------------------------------+
   //| Nastaví nový pivot. U EQ struktury nejdřív porovná s předchozí|
   //| úrovní (EQH/EQL), u swing struktury posune trailing extrémy   |
   //| a u struktur s OB připraví kandidáta ze svíček od pivotu.     |
   //| isHigh – swing high (kandidát na býčí OB = nejnižší parsed    |
   //| low), jinak swing low (medvědí OB = nejvyšší parsed high).    |
   //+---------------------------------------------------------------+
   void              SetPivot(CMarketStructure &structure, SPivot &pivot, const int pivotBar, const bool isHigh)
     {
      SBar   pivotCandle = Bar(pivotBar);
      double level       = isHigh ? pivotCandle.high : pivotCandle.low;

      // Rovná high/low: nový swing je od předchozího blíž než práh × ATR(200)
      if(structure.m_kind == STRUCTURE_EQUAL && pivot.level != NO_LEVEL &&
         MathAbs(pivot.level - level) < m_equalThreshold * m_atrFilter.Value())
         AddEvent(STRUCTURE_EQUAL, isHigh ? OB_BEARISH : OB_BULLISH, false,
                  pivot.time, pivot.level, pivotCandle.time, level);

      pivot.level    = level;
      pivot.crossed  = false;
      pivot.time     = pivotCandle.time;

      // Swing struktura určuje výchozí bod trailing extrémů
      if(structure.m_kind == STRUCTURE_SWING)
        {
         if(isHigh)
           {
            m_trailing.top     = level;
            m_trailing.topTime = pivotCandle.time;
           }
         else
           {
            m_trailing.bottom     = level;
            m_trailing.bottomTime = pivotCandle.time;
           }
        }

      if(!structure.m_storeBlocks)
         return;
      SetCandidate(pivot, pivotCandle);
      for(int i = pivotBar + 1; i < m_barIndex; i++)
         UpdateCandidate(pivot, Bar(i), isHigh);
     }

   void              SetCandidate(SPivot &pivot, const SBar &bar)
     {
      pivot.blockHigh = bar.parsedHigh;
      pivot.blockLow  = bar.parsedLow;
      pivot.blockTime = bar.time;
     }

   // Přísné porovnání zachová nejstarší svíčku při shodě (jako indexof v Pine)
   void              UpdateCandidate(SPivot &pivot, const SBar &bar, const bool isHigh)
     {
      if(isHigh ? bar.parsedLow < pivot.blockLow : bar.parsedHigh > pivot.blockHigh)
         SetCandidate(pivot, bar);
     }

   //+---------------------------------------------------------------+
   //| Detekuje prolomení swingu close cenou (BOS/CHoCH) a vytvoří   |
   //| order block (funkce displayStructure v Pine).                 |
   //| highAllowed/lowAllowed – zda lze prolomit swing high/low      |
   //+---------------------------------------------------------------+
   void              DetectBreaks(CMarketStructure &structure, const bool highAllowed, const bool lowAllowed)
     {
      // Prolomení swing high nahoru vytváří býčí OB, prolomení swing low dolů medvědí OB
      HandleBreak(structure, structure.m_high, true, highAllowed);
      HandleBreak(structure, structure.m_low, false, lowAllowed);

      // Kandidáti na OB zahrnou i aktuální svíčku pro další prolomení
      if(!structure.m_storeBlocks)
         return;
      SBar current = Bar(m_barIndex);
      UpdateCandidate(structure.m_high, current, true);
      UpdateCandidate(structure.m_low, current, false);
     }

   //+---------------------------------------------------------------+
   //| Zpracuje prolomení jednoho pivotu. isHigh – swing high        |
   //| (křížení nahoru, býčí OB), jinak swing low (dolů, medvědí OB) |
   //+---------------------------------------------------------------+
   void              HandleBreak(CMarketStructure &structure, SPivot &pivot, const bool isHigh, const bool allowed)
     {
      bool crossed = Crossed(pivot, isHigh);

      // Zapamatujeme úroveň pro detekci křížení na další svíčce
      pivot.prevLevel = pivot.level;
      if(!crossed || pivot.crossed || !allowed)
         return;

      // Prolomení proti dosavadnímu trendu je CHoCH, ve směru trendu BOS
      int  bias  = isHigh ? OB_BULLISH : OB_BEARISH;
      bool choch = structure.m_trend == -bias;
      structure.m_trend = bias;
      pivot.crossed     = true;

      SBar current = Bar(m_barIndex);
      AddEvent(structure.m_kind, bias, choch, pivot.time, pivot.level, current.time, pivot.level);
      if(!structure.m_storeBlocks)
         return;

      SOrderBlock block;
      ZeroMemory(block);
      block.id         = m_nextBlockId++;
      block.high       = pivot.blockHigh;
      block.low        = pivot.blockLow;
      block.time       = pivot.blockTime;
      block.bias       = bias;
      block.createdBar = m_barIndex;
      PushFront(structure.m_blocks, block);
     }

   //+---------------------------------------------------------------+
   //| ta.crossover / ta.crossunder close ceny přes úroveň pivotu    |
   //| upward – true pro křížení nahoru, false pro křížení dolů      |
   //+---------------------------------------------------------------+
   bool              Crossed(const SPivot &pivot, const bool upward)
     {
      const int k = m_barIndex;
      // Úroveň se nikdy nevrací na NO_LEVEL, platná předchozí úroveň znamená i platnou aktuální
      if(k < 1 || pivot.prevLevel == NO_LEVEL)
         return false;
      double close     = Bar(k).close;
      double prevClose = Bar(k - 1).close;
      if(upward)
         return close > pivot.level && prevClose <= pivot.prevLevel;
      return close < pivot.level && prevClose >= pivot.prevLevel;
     }

   //+---------------------------------------------------------------+
   //| Přesune OB, přes které cena prošla, mezi zneplatněné          |
   //| (deleteOrderBlocks v Pine)                                    |
   //+---------------------------------------------------------------+
   void              MitigateBlocks(CMarketStructure &structure)
     {
      SBar   current       = Bar(m_barIndex);
      bool   useClose      = m_mitigation == OB_MITIGATION_CLOSE;
      double bearishSource = useClose ? current.close : current.high;
      double bullishSource = useClose ? current.close : current.low;

      for(int i = ArraySize(structure.m_blocks) - 1; i >= 0; i--)
        {
         SOrderBlock block = structure.m_blocks[i];
         bool mitigated = (block.bias == OB_BEARISH && bearishSource > block.high) ||
                          (block.bias == OB_BULLISH && bullishSource < block.low);
         if(!mitigated)
            continue;
         block.mitigatedTime = current.time;
         PushFront(structure.m_mitigated, block);
         ArrayRemove(structure.m_blocks, i, 1);
        }
     }

   // Vloží OB na začátek seznamu; nejstarší OB nad limit se zahodí
   void              PushFront(SOrderBlock &blocks[], const SOrderBlock &block)
     {
      int size = MathMin(ArraySize(blocks) + 1, OB_MAX_STORED);
      ArrayResize(blocks, size);
      for(int i = size - 1; i > 0; i--)
         blocks[i] = blocks[i - 1];
      blocks[0] = block;
     }

   void              AddEvent(const ENUM_STRUCTURE_KIND kind, const int bias, const bool choch,
                              const datetime fromTime, const double fromLevel,
                              const datetime toTime, const double toLevel)
     {
      SStructureEvent event;
      event.kind      = kind;
      event.bias      = bias;
      event.choch     = choch;
      event.fromTime  = fromTime;
      event.fromLevel = fromLevel;
      event.toTime    = toTime;
      event.toLevel   = toLevel;
      // Nejstarší nevyzvednutá událost nad limit se zahodí
      if(ArraySize(m_events) >= EVENTS_MAX_STORED)
         ArrayRemove(m_events, 0, 1);
      int size = ArraySize(m_events);
      ArrayResize(m_events, size + 1);
      m_events[size] = event;
     }

   //+---------------------------------------------------------------+
   //| Hledá signál v jedné struktuře (parametry viz FindSignal)     |
   //+---------------------------------------------------------------+
   bool              FindSignalIn(CMarketStructure &structure, const int bias, const int maxBlocks,
                                  const double tolerance, const double price,
                                  const double currentLow, const double currentHigh, SOrderBlock &signal)
     {
      int  count      = MathMin(maxBlocks, ArraySize(structure.m_blocks));
      SBar lastClosed = Bar(m_barIndex);
      for(int i = 0; i < count; i++)
        {
         SOrderBlock block = structure.m_blocks[i];
         if(block.bias != bias || block.used)
            continue;
         double top    = block.Top();
         double bottom = block.Bottom();

         // Cena už je za OB (na opačné straně, než má obchod začít) – OB je prolomený
         if((bias == OB_BULLISH && price < bottom) || (bias == OB_BEARISH && price > top))
            continue;

         // Nový OB vzniklý na poslední uzavřené svíčce, cena je v jeho blízkosti
         bool isNewAtPrice = block.createdBar == m_barIndex &&
                             price >= bottom - tolerance && price <= top + tolerance;

         // Dotek zvenku: předchozí svíčka byla celá mimo OB, tvořená svíčka do něj zasáhla
         bool touched = (bias == OB_BULLISH) ? (currentLow <= top && lastClosed.low > top)
                                             : (currentHigh >= bottom && lastClosed.high < bottom);

         if(isNewAtPrice || touched)
           {
            signal = block;
            return true;
           }
        }
      return false;
     }

   void              MarkUsedIn(CMarketStructure &structure, const int blockId)
     {
      for(int i = 0; i < ArraySize(structure.m_blocks); i++)
         if(structure.m_blocks[i].id == blockId)
            structure.m_blocks[i].used = true;
     }
  };
//+------------------------------------------------------------------+
