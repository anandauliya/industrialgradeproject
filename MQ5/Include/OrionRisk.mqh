//+------------------------------------------------------------------+
//| OrionRisk.mqh - position sizing & circuit breaker                 |
//| - Risk per trade fixed % equity (TIDAK naik setelah loss)         |
//| - Cap notional <= equity x MaxNotionalX  (X=1.0 -> tanpa leverage)|
//| - Limit loss harian, bulanan, dan halt saat DD dari peak          |
//+------------------------------------------------------------------+
#ifndef ORION_RISK_MQH
#define ORION_RISK_MQH

class COrionRisk
{
private:
   string m_sym;
   double m_riskPct, m_maxNotionalX, m_dailyLossPct, m_monthlyLossPct, m_ddHaltPct, m_monthTargetStop;
   double m_peak, m_dayStartEq, m_monthStartEq;
   int    m_dayKey, m_monthKey, m_haltMonthKey;
   bool   m_armed;

   int KeyDay(datetime t)   { MqlDateTime d; TimeToStruct(t, d); return d.year * 10000 + d.mon * 100 + d.day; }
   int KeyMonth(datetime t) { MqlDateTime d; TimeToStruct(t, d); return d.year * 100 + d.mon; }

public:
   void Init(const string sym, double riskPct, double maxNotionalX, double dailyLossPct,
             double monthlyLossPct, double ddHaltPct, double monthTargetStop)
   {
      m_sym = sym; m_riskPct = riskPct; m_maxNotionalX = maxNotionalX;
      m_dailyLossPct = dailyLossPct; m_monthlyLossPct = monthlyLossPct;
      m_ddHaltPct = ddHaltPct; m_monthTargetStop = monthTargetStop;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      m_peak = eq; m_dayStartEq = eq; m_monthStartEq = eq;
      m_dayKey = 0; m_monthKey = 0; m_haltMonthKey = 0; m_armed = true;
   }

   double DrawdownPct() const
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peak <= 0) return 0;
      return MathMax(0.0, (m_peak - eq) / m_peak * 100.0);
   }

   // dipanggil tiap tick (ringan)
   void Update()
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      datetime t = TimeCurrent();
      int dk = KeyDay(t), mk = KeyMonth(t);
      if(dk != m_dayKey)   { m_dayKey = dk;   m_dayStartEq = eq; }
      if(mk != m_monthKey) { m_monthKey = mk; m_monthStartEq = eq; }

      if(eq >= m_peak) { m_peak = eq; m_armed = true; }
      double dd = DrawdownPct();
      if(!m_armed && dd < m_ddHaltPct * 0.5) m_armed = true;

      // circuit breaker: sekali per episode DD, halt sampai awal bulan depan
      if(m_armed && dd >= m_ddHaltPct)
      {
         m_haltMonthKey = m_monthKey;
         m_armed = false;
      }
   }

   // true = harus flat & stop entry (halt aktif bulan ini)
   bool Halted() const { return (m_haltMonthKey != 0 && m_haltMonthKey == m_monthKey); }

   bool EntryAllowed(string &why)
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(Halted()) { why = "DD halt"; return false; }
      if(m_dayStartEq > 0 && (m_dayStartEq - eq) / m_dayStartEq * 100.0 >= m_dailyLossPct)
      { why = "daily loss limit"; return false; }
      if(m_monthStartEq > 0 && (m_monthStartEq - eq) / m_monthStartEq * 100.0 >= m_monthlyLossPct)
      { why = "monthly loss limit"; return false; }
      if(m_monthTargetStop > 0 && m_monthStartEq > 0 &&
         (eq - m_monthStartEq) / m_monthStartEq * 100.0 >= m_monthTargetStop)
      { why = "monthly target reached"; return false; }
      return true;
   }

   // Lot berdasarkan risiko, dibatasi notional. Return 0 jika tidak layak.
   double CalcLots(double entry, double sl)
   {
      double eq    = AccountInfoDouble(ACCOUNT_EQUITY);
      double tickV = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickV <= 0) tickV = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_VALUE);
      double tickS = SymbolInfoDouble(m_sym, SYMBOL_TRADE_TICK_SIZE);
      double slDist = MathAbs(entry - sl);
      if(tickV <= 0 || tickS <= 0 || slDist <= 0 || eq <= 0) return 0.0;

      // risk scaling turun linear saat DD naik (anti-martingale), min 25%
      double mult = MathMax(0.25, 1.0 - DrawdownPct() / m_ddHaltPct);

      double lossPerLot     = slDist / tickS * tickV;
      double lotsByRisk     = eq * (m_riskPct / 100.0) * mult / lossPerLot;
      double notionalPerLot = entry / tickS * tickV;
      double lotsByNotional = eq * m_maxNotionalX / notionalPerLot;
      double lots = MathMin(lotsByRisk, lotsByNotional);

      double step = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_STEP);
      double vmin = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MIN);
      double vmax = SymbolInfoDouble(m_sym, SYMBOL_VOLUME_MAX);
      if(step <= 0) step = 0.01;
      lots = MathFloor(lots / step + 1e-9) * step;
      if(lots < vmin) return 0.0;     // tidak dipaksa ke lot minimum (jaga no-leverage)
      lots = MathMin(lots, vmax);
      return NormalizeDouble(lots, 8);
   }
};

#endif
