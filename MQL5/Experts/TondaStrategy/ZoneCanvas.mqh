//+------------------------------------------------------------------+
//|                                                   ZoneCanvas.mqh |
//| Průhledná bitmapa přes celý graf pro vyplněné zóny (order blocky |
//| a výplň Bollinger Bands). MT5 vyplněné objekty při překryvu      |
//| míchá přes XOR, bitmapa skládá barvy s průhledností jako         |
//| TradingView.                                                     |
//+------------------------------------------------------------------+
#include <Canvas/Canvas.mqh>

//+------------------------------------------------------------------+
//| Pohled na graf; při jeho změně (posun, zoom, velikost, měřítko   |
//| ceny) se musí bitmapa překreslit                                 |
//+------------------------------------------------------------------+
struct SChartView
  {
   long              firstBar;
   long              widthInBars;
   long              widthInPixels;
   long              heightInPixels;
   double            priceMax;
   double            priceMin;
  };

//+------------------------------------------------------------------+
//| Zdrojová barva připravená pro skládání (jednou na obdélník)      |
//+------------------------------------------------------------------+
struct SBlendSource
  {
   double            red;
   double            green;
   double            blue;
   double            alpha;
   uint              packed;   // hotový pixel ARGB pro zápis do prázdného místa
  };

//+------------------------------------------------------------------+
//| Bitmapa v souřadnicích grafu s alfa skládáním (source-over)      |
//+------------------------------------------------------------------+
class CZoneCanvas : public CCanvas
  {
private:
   SChartView        m_view;   // pohled, pro který je bitmapa nakreslená

public:
   // Vytvoří bitmapu velikosti grafu za svíčkami; name – název objektu
   bool              Open(const string name)
     {
      ZeroMemory(m_view);
      SChartView view = CurrentView();
      if(!CreateBitmapLabel(0, 0, name, 0, 0, (int)view.widthInPixels, (int)view.heightInPixels, COLOR_FORMAT_ARGB_NORMALIZE))
         return false;
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      return true;
     }

   // Pohled grafu se od posledního kreslení změnil
   bool              ViewChanged()
     {
      SChartView view = CurrentView();
      return view.firstBar != m_view.firstBar || view.widthInBars != m_view.widthInBars ||
             view.widthInPixels != m_view.widthInPixels || view.heightInPixels != m_view.heightInPixels ||
             view.priceMax != m_view.priceMax || view.priceMin != m_view.priceMin;
     }

   // Začne nové kreslení: uloží pohled, přizpůsobí velikost bitmapy grafu a smaže obsah
   void              Begin()
     {
      m_view = CurrentView();
      if(m_width != m_view.widthInPixels || m_height != m_view.heightInPixels)
         Resize((int)m_view.widthInPixels, (int)m_view.heightInPixels);
      Erase(0);
     }

   // Převod času a ceny na pixely; false pro čas mimo historii grafu
   bool              ToXY(const datetime time, const double price, int &x, int &y)
     {
      return ChartTimePriceToXY(0, 0, time, price, x, y);
     }

   //+---------------------------------------------------------------+
   //| Vyplní obdélník mezi body (x1,y1) a (x2,y2) barvou            |
   //| s průhledností 0–100 jako v Pine                              |
   //+---------------------------------------------------------------+
   void              FillRect(int x1, int y1, int x2, int y2, const color fill, const int transparency)
     {
      Normalize(x1, y1, x2, y2);
      x1 = MathMax(x1, 0);
      x2 = MathMin(x2, m_width - 1);
      y1 = MathMax(y1, 0);
      y2 = MathMin(y2, m_height - 1);
      if(x1 > x2 || y1 > y2)
         return;

      SBlendSource source = PrepareSource(fill, transparency);
      for(int y = y1; y <= y2; y++)
         for(int x = x1; x <= x2; x++)
            BlendPixel(y * m_width + x, source);
     }

   //+---------------------------------------------------------------+
   //| Okraj obdélníku přerušovanou čarou: dash pixelů čára, gap     |
   //| pixelů mezera (gap = 0 plná čára)                             |
   //+---------------------------------------------------------------+
   void              BorderRect(int x1, int y1, int x2, int y2, const color line,
                                const int transparency, const int dash, const int gap)
     {
      Normalize(x1, y1, x2, y2);
      SBlendSource source = PrepareSource(line, transparency);
      int period = dash + gap;
      for(int x = x1; x <= x2; x++)
         if((x - x1) % period < dash)
           {
            BlendClipped(x, y1, source);
            BlendClipped(x, y2, source);
           }
      for(int y = y1 + 1; y < y2; y++)
         if((y - y1) % period < dash)
           {
            BlendClipped(x1, y, source);
            BlendClipped(x2, y, source);
           }
     }

private:
   SChartView        CurrentView()
     {
      SChartView view;
      view.firstBar       = ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
      view.widthInBars    = ChartGetInteger(0, CHART_WIDTH_IN_BARS);
      view.widthInPixels  = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      view.heightInPixels = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
      view.priceMax       = ChartGetDouble(0, CHART_PRICE_MAX);
      view.priceMin       = ChartGetDouble(0, CHART_PRICE_MIN);
      return view;
     }

   // Seřadí rohy tak, aby (x1,y1) byl levý horní a (x2,y2) pravý dolní
   void              Normalize(int &x1, int &y1, int &x2, int &y2)
     {
      if(x1 > x2)
        {
         int swap = x1;
         x1 = x2;
         x2 = swap;
        }
      if(y1 > y2)
        {
         int swap = y1;
         y1 = y2;
         y2 = swap;
        }
     }

   // value – barva MQL (0x00BBGGRR), transparency – 0–100
   SBlendSource      PrepareSource(const color value, const int transparency)
     {
      SBlendSource source;
      source.red    = value & 0xFF;
      source.green  = (value >> 8) & 0xFF;
      source.blue   = (value >> 16) & 0xFF;
      source.alpha  = (100 - transparency) / 100.0;
      source.packed = ((uint)MathRound(source.alpha * 255.0) << 24) | ((uint)source.red << 16) |
                      ((uint)source.green << 8) | (uint)source.blue;
      return source;
     }

   void              BlendClipped(const int x, const int y, const SBlendSource &source)
     {
      if(x >= 0 && x < m_width && y >= 0 && y < m_height)
         BlendPixel(y * m_width + x, source);
     }

   //+---------------------------------------------------------------+
   //| Složí barvu přes pixel (source-over, nepředvynásobené ARGB);  |
   //| prázdný pixel se rovnou přepíše hotovou hodnotou              |
   //+---------------------------------------------------------------+
   void              BlendPixel(const int index, const SBlendSource &source)
     {
      uint target = m_pixels[index];
      if(target == 0)
        {
         m_pixels[index] = source.packed;
         return;
        }

      // Výsledná alfa a podíl původního pixelu
      double targetAlpha = (target >> 24) / 255.0;
      double weight      = targetAlpha * (1.0 - source.alpha);
      double alpha       = source.alpha + weight;

      uint red   = (uint)MathRound((source.red * source.alpha + ((target >> 16) & 0xFF) * weight) / alpha);
      uint green = (uint)MathRound((source.green * source.alpha + ((target >> 8) & 0xFF) * weight) / alpha);
      uint blue  = (uint)MathRound((source.blue * source.alpha + (target & 0xFF) * weight) / alpha);
      m_pixels[index] = ((uint)MathRound(alpha * 255.0) << 24) | (red << 16) | (green << 8) | blue;
     }
  };
//+------------------------------------------------------------------+
