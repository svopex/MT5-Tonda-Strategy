//+------------------------------------------------------------------+
//|                                                 TradingHours.mqh |
//| Obchodní doba experta podle času serveru: okno pro otevírání     |
//| nových obchodů a čas zavření otevřených obchodů.                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Obchodní doba v minutách od půlnoci (čas serveru)                |
//+------------------------------------------------------------------+
class CTradingHours
  {
private:
   int               m_start;        // začátek obchodování
   int               m_end;          // konec otevírání nových obchodů
   int               m_close;        // zavření otevřených obchodů
   string            m_description;  // text pro výpis vlevo nahoře

public:
   //+---------------------------------------------------------------+
   //| Nastaví obchodní dobu z časů "HH:MM"; false při chybném       |
   //| formátu nebo hodnotě. start – začátek obchodování, end –      |
   //| konec otevírání obchodů, close – zavření otevřených obchodů   |
   //+---------------------------------------------------------------+
   bool              Init(const string start, const string end, const string close)
     {
      if(!Parse(start, m_start) || !Parse(end, m_end) || !Parse(close, m_close))
         return false;
      m_description = start + "–" + end + ", zavření " + close + " (čas serveru)";
      return true;
     }

   // Zavírací doba trvá od času zavření do začátku dalšího obchodování
   bool              IsClosingTime() const
     {
      return InRange(MinuteOfDay(), m_close, m_start);
     }

   // Nové obchody jen v obchodním okně a mimo zavírací dobu
   bool              IsEntryTime() const
     {
      int minute = MinuteOfDay();
      return InRange(minute, m_start, m_end) && !InRange(minute, m_close, m_start);
     }

   string            Description() const { return m_description; }

private:
   // Převede čas "HH:MM" na minuty od půlnoci
   static bool       Parse(const string text, int &minutes)
     {
      string parts[];
      if(StringSplit(text, ':', parts) != 2)
         return false;
      int hours = (int)StringToInteger(parts[0]);
      int mins  = (int)StringToInteger(parts[1]);
      if(hours < 0 || hours > 23 || mins < 0 || mins > 59)
         return false;
      minutes = hours * 60 + mins;
      return true;
     }

   // Aktuální čas serveru v minutách od půlnoci
   static int        MinuteOfDay()
     {
      MqlDateTime now;
      TimeToStruct(TimeCurrent(), now);
      return now.hour * 60 + now.min;
     }

   // Leží minuta v intervalu [from, to)? Interval může přecházet přes půlnoc
   static bool       InRange(const int minute, const int from, const int to)
     {
      if(from <= to)
         return minute >= from && minute < to;
      return minute >= from || minute < to;
     }
  };
//+------------------------------------------------------------------+
