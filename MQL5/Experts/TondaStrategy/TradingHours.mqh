//+------------------------------------------------------------------+
//|                                                 TradingHours.mqh |
//| Obchodní doba experta podle času serveru: okno pro otevírání     |
//| nových obchodů a čas zavření otevřených obchodů. Časy se zadají  |
//| ručně, nebo se odvodí z obchodních seancí symbolu v MT5.         |
//+------------------------------------------------------------------+

#define SECONDS_PER_DAY   86400
#define SESSION_SCAN_DAYS 7     // kolik dní před a po dnešku se prochází při hledání seance
#define SESSION_JOIN_GAP  60    // mezera (s), do které se navazující seance spojí (např. 23:59 → 00:00)

// Zdroj obchodní doby (komentáře hodnot se zobrazí v nastavení)
enum ENUM_HOURS_SOURCE
  {
   HOURS_MANUAL,   // Ručně (časy od–do a zavření)
   HOURS_SESSIONS  // Podle obchodních seancí symbolu v MT5
  };

// Souvislá obchodní seance v čase serveru
struct STradeSession
  {
   datetime          start;
   datetime          end;
  };

//+------------------------------------------------------------------+
//| Obchodní doba: ruční časy v minutách od půlnoci, nebo seance     |
//| symbolu s odstupy od začátku a konce seance                      |
//+------------------------------------------------------------------+
class CTradingHours
  {
private:
   ENUM_HOURS_SOURCE m_source;
   // Ruční režim (minuty od půlnoci)
   int               m_start;        // začátek obchodování
   int               m_end;          // konec otevírání nových obchodů
   int               m_close;        // zavření otevřených obchodů
   string            m_description;  // text pro výpis vlevo nahoře
   // Režim seancí (odstupy v sekundách)
   string            m_symbol;
   int               m_openDelay;    // otevírat až po této době od začátku seance
   int               m_entryStop;    // neotevírat tuto dobu před koncem seance
   int               m_closeBefore;  // zavřít pozice tuto dobu před koncem seance
   // Aktuální úsek [m_from, m_to): seance, nebo mezera mezi seancemi (trh zavřený).
   // Hranice za prohledanými dny se ořízne na okraj (je pak nejméně 6 dní daleko
   // a odstupy neovlivní); příznaky Known říkají, zda je hranice skutečná.
   bool              m_inSession;
   datetime          m_from;
   datetime          m_to;
   bool              m_fromKnown;
   bool              m_toKnown;
   datetime          m_validTo;      // do kdy úsek platí bez nového hledání (nejpozději do půlnoci)

public:
   //+---------------------------------------------------------------+
   //| Ruční obchodní doba z časů "HH:MM"; false při chybném formátu |
   //| nebo hodnotě. start – začátek obchodování, end – konec        |
   //| otevírání obchodů, close – zavření otevřených obchodů         |
   //+---------------------------------------------------------------+
   bool              InitManual(const string start, const string end, const string close)
     {
      m_source = HOURS_MANUAL;
      if(!Parse(start, m_start) || !Parse(end, m_end) || !Parse(close, m_close))
         return false;
      m_description = start + "–" + end + ", zavření " + close + " (čas serveru)";
      return true;
     }

   //+---------------------------------------------------------------+
   //| Obchodní doba podle seancí symbolu v MT5; false při záporném  |
   //| odstupu. openDelay – minuty od začátku seance, entryStop –    |
   //| minuty před koncem seance bez nových obchodů, closeBefore –   |
   //| minuty před koncem seance pro zavření pozic                   |
   //+---------------------------------------------------------------+
   bool              InitSessions(const string symbol, const int openDelay, const int entryStop, const int closeBefore)
     {
      m_source = HOURS_SESSIONS;
      if(openDelay < 0 || entryStop < 0 || closeBefore < 0)
         return false;
      m_symbol      = symbol;
      m_openDelay   = openDelay * 60;
      m_entryStop   = entryStop * 60;
      m_closeBefore = closeBefore * 60;
      m_from        = 0;
      m_validTo     = 0;
      return true;
     }

   // Je čas zavřít otevřené pozice?
   bool              IsClosingTime()
     {
      // Ručně: zavírací doba trvá od času zavření do začátku dalšího obchodování
      if(m_source == HOURS_MANUAL)
         return InRange(MinuteOfDay(), m_close, m_start);

      // Seance: zavírá se ke konci seance, mimo seanci se obchodovat nedá
      datetime now = Refresh();
      return m_inSession && now >= m_to - m_closeBefore;
     }

   // Nové obchody jen v obchodním okně a nikdy během zavírací doby
   bool              IsEntryTime()
     {
      return InEntryWindow() && !IsClosingTime();
     }

   // Text pro výpis vlevo nahoře; v režimu seancí s aktuální seancí a z ní odvozenými časy
   string            Description()
     {
      if(m_source == HOURS_MANUAL)
         return m_description;

      datetime now = Refresh();
      if(!m_inSession)
         return "podle seancí symbolu – trh zavřený" + (m_toKnown ? ", další seance " + TimeText(m_to, now) : "");

      // Neznámé hranice: seance začala dřív nebo trvá déle, než kolik dní se prochází
      string text = "seance " + (m_fromKnown ? TimeText(m_from, now) : "dříve") + "–" +
                    (m_toKnown ? TimeText(m_to, now) : "bez konce");
      string entryFrom = m_fromKnown ? TimeText(m_from + m_openDelay, now) : "ihned";
      if(m_toKnown)
         text += ", otevírání " + entryFrom + "–" + TimeText(m_to - MathMax(m_entryStop, m_closeBefore), now) +
                 ", zavření " + TimeText(m_to - m_closeBefore, now);
      else
         text += ", otevírání od " + entryFrom;
      return text + " (čas serveru)";
     }

private:
   // Leží aktuální čas v okně pro otevírání obchodů (bez ohledu na zavírací dobu)?
   bool              InEntryWindow()
     {
      if(m_source == HOURS_MANUAL)
         return InRange(MinuteOfDay(), m_start, m_end);

      datetime now = Refresh();
      return m_inSession && now >= m_from + m_openDelay && now < m_to - m_entryStop;
     }

   //+---------------------------------------------------------------+
   //| Najde úsek (seanci nebo mezeru mezi seancemi) obsahující      |
   //| aktuální čas a vrátí ho. Seance se procházejí jen po opuštění |
   //| platného úseku, nejméně jednou denně (posune se tím okno      |
   //| prohledaných dní).                                            |
   //+---------------------------------------------------------------+
   datetime          Refresh()
     {
      datetime now = TimeCurrent();
      if(now >= m_from && now < m_validTo)
         return now;

      datetime today       = (datetime)((long)now / SECONDS_PER_DAY * SECONDS_PER_DAY);
      datetime windowStart = today - SESSION_SCAN_DAYS * SECONDS_PER_DAY;
      datetime windowEnd   = today + (SESSION_SCAN_DAYS + 1) * SECONDS_PER_DAY;
      STradeSession sessions[];
      LoadSessions(windowStart, windowEnd, sessions);

      // Bez nalezené seance je celé okno mezerou (trh zavřený)
      m_inSession = false;
      m_from      = windowStart;
      m_to        = windowEnd;
      for(int i = 0; i < ArraySize(sessions); i++)
        {
         // Mezera do začátku této seance
         if(now < sessions[i].start)
           {
            m_to = sessions[i].start;
            break;
           }
         // Uvnitř seance
         if(now < sessions[i].end)
           {
            m_inSession = true;
            m_from      = sessions[i].start;
            m_to        = sessions[i].end;
            break;
           }
         m_from = sessions[i].end;
        }

      m_fromKnown = m_from > windowStart;
      m_toKnown   = m_to < windowEnd;
      m_validTo   = MathMin(m_to, today + SECONDS_PER_DAY);
      return now;
     }

   //+---------------------------------------------------------------+
   //| Načte obchodní seance symbolu ve dnech [from, to) seřazené    |
   //| podle času; navazující seance (i přes půlnoc) spojí do jedné  |
   //+---------------------------------------------------------------+
   void              LoadSessions(const datetime from, const datetime to, STradeSession &sessions[])
     {
      ArrayResize(sessions, 0);
      for(datetime dayStart = from; dayStart < to; dayStart += SECONDS_PER_DAY)
        {
         MqlDateTime day;
         TimeToStruct(dayStart, day);
         datetime sessionFrom, sessionTo;
         for(uint index = 0; SymbolInfoSessionTrade(m_symbol, (ENUM_DAY_OF_WEEK)day.day_of_week, index, sessionFrom, sessionTo); index++)
           {
            datetime start = dayStart + sessionFrom;
            datetime end   = dayStart + sessionTo;
            // Konec před začátkem znamená seanci přes půlnoc (např. 01:00–00:00)
            if(end <= start)
               end += SECONDS_PER_DAY;

            int count = ArraySize(sessions);
            if(count > 0 && start <= sessions[count - 1].end + SESSION_JOIN_GAP)
              {
               if(end > sessions[count - 1].end)
                  sessions[count - 1].end = end;
               continue;
              }
            ArrayResize(sessions, count + 1);
            sessions[count].start = start;
            sessions[count].end   = end;
           }
        }
     }

   // Čas jako "HH:MM", v jiný den než now se zkratkou dne, např. "Po 01:00"
   static string     TimeText(const datetime time, const datetime now)
     {
      static const string dayNames[] = {"Ne", "Po", "Út", "St", "Čt", "Pá", "So"};
      string text = TimeToString(time, TIME_MINUTES);
      if((long)time / SECONDS_PER_DAY == (long)now / SECONDS_PER_DAY)
         return text;
      MqlDateTime day;
      TimeToStruct(time, day);
      return dayNames[day.day_of_week] + " " + text;
     }

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
