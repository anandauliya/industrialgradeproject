//+------------------------------------------------------------------+
//| OrionSignal.mqh - Donchian breakout + filter tren & volatilitas   |
//| Semua evaluasi pakai bar yang sudah close (shift >= 1).           |
//+------------------------------------------------------------------+
#ifndef ORION_SIGNAL_MQH
#define ORION_SIGNAL_MQH

class COrionSignal
{
private:
   string          m_sym;
   ENUM_TIMEFRAMES m_tf, m_tfTrend;
   int             m_hAtr, m_hAdx, m_hEma, m_donchian;
   double          m_adxMin, m_atrMinR, m_atrMaxR;

public:
   COrionSignal() : m_hAtr(INVALID_HANDLE), m_hAdx(INVALID_HANDLE), m_hEma(INVALID_HANDLE) {}
   ~COrionSignal() { Release(); }

   bool Init(const string sym, ENUM_TIMEFRAMES tf, ENUM_TIMEFRAMES tfTrend, int emaPeriod,
             int atrPeriod, int adxPeriod, int donchian, double adxMin,
             double atrMinRatio, double atrMaxRatio)
   {
      Release();
      m_sym = sym; m_tf = tf; m_tfTrend = tfTrend;
      m_donchian = donchian; m_adxMin = adxMin;
      m_atrMinR = atrMinRatio; m_atrMaxR = atrMaxRatio;
      m_hAtr = iATR(sym, tf, atrPeriod);
      m_hAdx = iADX(sym, tf, adxPeriod);
      m_hEma = iMA(sym, tfTrend, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      return (m_hAtr != INVALID_HANDLE && m_hAdx != INVALID_HANDLE && m_hEma != INVALID_HANDLE);
   }

   void Release()
   {
      if(m_hAtr != INVALID_HANDLE) { IndicatorRelease(m_hAtr); m_hAtr = INVALID_HANDLE; }
      if(m_hAdx != INVALID_HANDLE) { IndicatorRelease(m_hAdx); m_hAdx = INVALID_HANDLE; }
      if(m_hEma != INVALID_HANDLE) { IndicatorRelease(m_hEma); m_hEma = INVALID_HANDLE; }
   }

   bool Atr(int shift, double &v)
   {
      double b[1];
      if(CopyBuffer(m_hAtr, 0, shift, 1, b) != 1) return false;
      v = b[0];
      return (v > 0);
   }

   double HighestHigh(int n)
   {
      double h[];
      if(CopyHigh(m_sym, m_tf, 1, n, h) != n) return 0.0;
      return h[ArrayMaximum(h)];
   }

   double LowestLow(int n)
   {
      double l[];
      if(CopyLow(m_sym, m_tf, 1, n, l) != n) return 0.0;
      return l[ArrayMinimum(l)];
   }

   // +1 long, -1 short, 0 tidak ada sinyal
   int Direction()
   {
      double hi[], lo[];
      if(CopyHigh(m_sym, m_tf, 2, m_donchian, hi) != m_donchian) return 0;
      if(CopyLow (m_sym, m_tf, 2, m_donchian, lo) != m_donchian) return 0;
      double hh = hi[ArrayMaximum(hi)];
      double ll = lo[ArrayMinimum(lo)];

      double c[1];
      if(CopyClose(m_sym, m_tf, 1, 1, c) != 1) return 0;

      // filter kekuatan tren
      double adx[1];
      if(CopyBuffer(m_hAdx, 0, 1, 1, adx) != 1) return 0;
      if(adx[0] < m_adxMin) return 0;

      // filter volatilitas: ATR sekarang vs rata-rata 50 bar
      double a[];
      if(CopyBuffer(m_hAtr, 0, 1, 50, a) != 50) return 0;
      double sum = 0;
      for(int i = 0; i < 50; i++) sum += a[i];
      double avg = sum / 50.0;
      if(avg <= 0) return 0;
      double ratio = a[49] / avg;
      if(ratio < m_atrMinR || ratio > m_atrMaxR) return 0;

      // filter tren TF besar: close > EMA dan EMA menanjak (atau sebaliknya)
      double e[2], c2[1];
      if(CopyBuffer(m_hEma, 0, 1, 2, e) != 2) return 0;
      if(CopyClose(m_sym, m_tfTrend, 1, 1, c2) != 1) return 0;
      bool up = (c2[0] > e[1] && e[1] > e[0]);
      bool dn = (c2[0] < e[1] && e[1] < e[0]);

      if(c[0] > hh && up) return 1;
      if(c[0] < ll && dn) return -1;
      return 0;
   }
};

#endif
