//+------------------------------------------------------------------+
//| Orion_Industrial.mq5                                              |
//| Trend-following breakout, 1 posisi per simbol.                    |
//| TANPA martingale / grid / HFT / hedging averaging.                |
//| Pasang di chart simbol target (TF chart bebas, TF kerja = InpTF). |
//+------------------------------------------------------------------+
#property copyright "Orion Industrial"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Orion/OrionProfiles.mqh>
#include <Orion/OrionRisk.mqh>
#include <Orion/OrionSignal.mqh>

//--- Strategi
input group "=== Strategi ==="
input ENUM_TIMEFRAMES InpTF          = PERIOD_H4;   // TF entry
input ENUM_TIMEFRAMES InpTrendTF     = PERIOD_D1;   // TF filter tren
input int    InpEMAPeriod            = 50;          // EMA tren
input int    InpATRPeriod            = 14;
input int    InpADXPeriod            = 14;
input double InpATRMinRatio          = 0.8;         // ATR/ATRavg minimum
input double InpATRMaxRatio          = 2.5;         // ATR/ATRavg maksimum
// 0 = pakai profil kelas instrumen (OrionProfiles.mqh)
input int    InpDonchian             = 0;           // lookback breakout
input double InpSLATR                = 0.0;         // SL awal (x ATR)
input double InpTrailATR             = 0.0;         // trailing (x ATR)
input double InpADXMin               = 0.0;         // ADX minimum
input int    InpTrailLookback        = 22;          // lookback chandelier
input double InpBEATR                = 1.5;         // pindah SL ke BE setelah profit x ATR (0=off)
input double InpTPR                  = 0.0;         // TP dalam kelipatan R (0 = tanpa TP)
input int    InpMaxHoldBars          = 120;         // time stop (bar TF entry)
input int    InpFridayCloseHour      = 20;          // jam server tutup posisi Jumat

//--- Risk
input group "=== Risk ==="
input double InpRiskPct              = 1.0;         // risiko per trade (% equity)
input double InpMaxNotionalX         = 1.0;         // notional maks = equity x ini (1.0 = no leverage)
input double InpDailyLossPct         = 3.0;         // stop entry jika loss harian >= %
input double InpMonthlyLossPct       = 8.0;         // stop entry jika loss bulanan >= %
input double InpDDHaltPct            = 25.0;        // flat + halt sampai bulan depan jika DD >= %
input double InpMonthTargetStopPct   = 0.0;         // stop entry jika profit bulan ini >= % (0=off)
input int    InpMaxTradesPerDay      = 2;

//--- Eksekusi
input group "=== Eksekusi ==="
input long   InpMagic                = 26100701;
input int    InpDeviation            = 30;

//--- Optimasi
input group "=== Kriteria Optimasi ==="
input double InpTargetMaxDD          = 25.0;        // DD maks yang ditolerir skor
input int    InpMinTrades            = 60;          // trade minimum agar skor valid

CTrade        g_trade;
COrionRisk    g_risk;
COrionSignal  g_sig;
SOrionProfile g_prof;

int    g_donchian;
double g_slATR, g_trailATR, g_adxMin;
datetime g_lastBar = 0;
int    g_tradesToday = 0, g_tradeDayKey = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if(!SymbolSelect(_Symbol, true)) return INIT_FAILED;
   OrionLoadProfile(_Symbol, g_prof);

   g_donchian = (InpDonchian > 0)   ? InpDonchian : g_prof.donchian;
   g_slATR    = (InpSLATR > 0)      ? InpSLATR    : g_prof.slATR;
   g_trailATR = (InpTrailATR > 0)   ? InpTrailATR : g_prof.trailATR;
   g_adxMin   = (InpADXMin > 0)     ? InpADXMin   : g_prof.adxMin;

   if(!g_sig.Init(_Symbol, InpTF, InpTrendTF, InpEMAPeriod, InpATRPeriod, InpADXPeriod,
                  g_donchian, g_adxMin, InpATRMinRatio, InpATRMaxRatio))
   {
      Print("Orion: gagal membuat indikator");
      return INIT_FAILED;
   }
   g_risk.Init(_Symbol, InpRiskPct, InpMaxNotionalX, InpDailyLossPct,
               InpMonthlyLossPct, InpDDHaltPct, InpMonthTargetStopPct);

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { g_sig.Release(); }

//+------------------------------------------------------------------+
bool GetPosition(ulong &ticket, ENUM_POSITION_TYPE &ptype)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ticket = t;
      ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      return true;
   }
   return false;
}

bool SessionOK()
{
   MqlDateTime d; TimeToStruct(TimeCurrent(), d);
   if(g_prof.closeFriday && d.day_of_week == 5 && d.hour >= InpFridayCloseHour) return false;
   return (d.hour >= g_prof.hourFrom && d.hour < g_prof.hourTo);
}

//+------------------------------------------------------------------+
void ManagePosition(ulong ticket, ENUM_POSITION_TYPE ptype)
{
   if(!PositionSelectByTicket(ticket)) return;
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl   = PositionGetDouble(POSITION_SL);
   double tp   = PositionGetDouble(POSITION_TP);
   datetime ot = (datetime)PositionGetInteger(POSITION_TIME);
   bool isBuy  = (ptype == POSITION_TYPE_BUY);

   // time stop
   int held = (int)((TimeCurrent() - ot) / PeriodSeconds(InpTF));
   if(held >= InpMaxHoldBars) { g_trade.PositionClose(ticket); return; }

   // tutup Jumat malam
   MqlDateTime d; TimeToStruct(TimeCurrent(), d);
   if(g_prof.closeFriday && d.day_of_week == 5 && d.hour >= InpFridayCloseHour)
   { g_trade.PositionClose(ticket); return; }

   double atr;
   if(!g_sig.Atr(1, atr)) return;

   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = ask - bid;

   double newSL = sl;
   if(isBuy)
   {
      double hh = g_sig.HighestHigh(InpTrailLookback);
      if(hh <= 0) return;
      double cand = hh - g_trailATR * atr;
      if(InpBEATR > 0 && (bid - open) >= InpBEATR * atr) cand = MathMax(cand, open + spread);
      cand = NormalizeDouble(cand, digits);
      if(cand > sl + point && cand < bid - minDist) newSL = cand;
   }
   else
   {
      double ll = g_sig.LowestLow(InpTrailLookback);
      if(ll <= 0) return;
      double cand = ll + g_trailATR * atr;
      if(InpBEATR > 0 && (open - ask) >= InpBEATR * atr) cand = MathMin(cand, open - spread);
      cand = NormalizeDouble(cand, digits);
      if((sl <= 0 || cand < sl - point) && cand > ask + minDist) newSL = cand;
   }
   if(newSL != sl) g_trade.PositionModify(ticket, newSL, tp);
}

//+------------------------------------------------------------------+
void TryEntry()
{
   string why;
   if(!g_risk.EntryAllowed(why)) return;
   if(!SessionOK()) return;

   MqlDateTime d; TimeToStruct(TimeCurrent(), d);
   int dk = d.year * 10000 + d.mon * 100 + d.day;
   if(dk != g_tradeDayKey) { g_tradeDayKey = dk; g_tradesToday = 0; }
   if(g_tradesToday >= InpMaxTradesPerDay) return;

   int dir = g_sig.Direction();
   if(dir == 0) return;

   double atr;
   if(!g_sig.Atr(1, atr)) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if((ask - bid) > g_prof.maxSpreadATR * atr) return;   // spread kemahalan

   int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   double entry = (dir > 0) ? ask : bid;
   double slDist = g_slATR * atr;
   if(slDist < minDist) return;
   double sl = NormalizeDouble((dir > 0) ? entry - slDist : entry + slDist, digits);
   double tp = 0.0;
   if(InpTPR > 0) tp = NormalizeDouble((dir > 0) ? entry + InpTPR * slDist : entry - InpTPR * slDist, digits);

   double lots = g_risk.CalcLots(entry, sl);
   if(lots <= 0) return;

   // cek margin bebas
   double margin = 0;
   ENUM_ORDER_TYPE ot = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(ot, _Symbol, lots, entry, margin)) return;
   if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9) return;

   bool ok = (dir > 0) ? g_trade.Buy(lots, _Symbol, 0.0, sl, tp, "Orion")
                       : g_trade.Sell(lots, _Symbol, 0.0, sl, tp, "Orion");
   if(ok) g_tradesToday++;
}

//+------------------------------------------------------------------+
void OnTick()
{
   g_risk.Update();

   ulong ticket; ENUM_POSITION_TYPE ptype;
   bool has = GetPosition(ticket, ptype);

   if(has && g_risk.Halted())
   {
      g_trade.PositionClose(ticket);
      return;
   }

   datetime bar = iTime(_Symbol, InpTF, 0);
   if(bar == 0 || bar == g_lastBar) return;
   g_lastBar = bar;

   if(has)
   {
      ManagePosition(ticket, ptype);
      has = GetPosition(ticket, ptype);
   }
   if(has) return;
   TryEntry();
}

//+------------------------------------------------------------------+
//| Custom criterion optimasi + export CSV untuk laporan              |
//+------------------------------------------------------------------+
double OnTester()
{
   if(!HistorySelect(0, TimeCurrent())) return 0.0;

   bool   doExport = !MQLInfoInteger(MQL_OPTIMIZATION);
   double init     = TesterStatistics(STAT_INITIAL_DEPOSIT);
   int    trades   = (int)TesterStatistics(STAT_TRADES);
   double ddRel    = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double net      = TesterStatistics(STAT_PROFIT);
   double pf       = TesterStatistics(STAT_PROFIT_FACTOR);

   int hCsv = INVALID_HANDLE;
   if(doExport)
   {
      hCsv = FileOpen("Orion_deals_" + _Symbol + ".csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
      if(hCsv != INVALID_HANDLE) FileWrite(hCsv, "time", "symbol", "pnl");
   }

   int lossCnt[101];
   ArrayInitialize(lossCnt, 0);
   int curKey = 0, curYear = 0;
   double bal = init, monthStartBal = init, monthPnl = 0.0;
   datetime firstT = 0, lastT = 0;

   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong dt = HistoryDealGetTicket(i);
      if(dt == 0) continue;
      long type = HistoryDealGetInteger(dt, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;

      double pnl = HistoryDealGetDouble(dt, DEAL_PROFIT) + HistoryDealGetDouble(dt, DEAL_SWAP) +
                   HistoryDealGetDouble(dt, DEAL_COMMISSION) + HistoryDealGetDouble(dt, DEAL_FEE);
      datetime t = (datetime)HistoryDealGetInteger(dt, DEAL_TIME);
      if(firstT == 0) firstT = t;
      lastT = t;

      MqlDateTime md; TimeToStruct(t, md);
      int key = md.year * 100 + md.mon;
      if(curKey != 0 && key != curKey)
      {
         double r = (monthStartBal > 0) ? monthPnl / monthStartBal : 0.0;
         if(r < 0 && curYear >= 2000 && curYear <= 2100) lossCnt[curYear - 2000]++;
         bal += monthPnl; monthStartBal = bal; monthPnl = 0.0;
      }
      curKey = key; curYear = md.year;
      monthPnl += pnl;

      if(hCsv != INVALID_HANDLE)
         FileWrite(hCsv, TimeToString(t, TIME_DATE | TIME_MINUTES | TIME_SECONDS), _Symbol, DoubleToString(pnl, 2));
   }
   if(curKey != 0)
   {
      double r = (monthStartBal > 0) ? monthPnl / monthStartBal : 0.0;
      if(r < 0 && curYear >= 2000 && curYear <= 2100) lossCnt[curYear - 2000]++;
   }
   if(hCsv != INVALID_HANDLE) FileClose(hCsv);

   int violYears = 0;
   for(int y = 0; y <= 100; y++) if(lossCnt[y] > 6) violYears++;

   if(doExport)
   {
      int hs = FileOpen("Orion_summary.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
      if(hs != INVALID_HANDLE)
      {
         if(FileSize(hs) == 0) FileWrite(hs, "symbol", "from", "to", "initial", "net", "trades", "pf", "eq_dd_pct", "viol_years");
         FileSeek(hs, 0, SEEK_END);
         FileWrite(hs, _Symbol, TimeToString(firstT, TIME_DATE), TimeToString(lastT, TIME_DATE),
                   DoubleToString(init, 2), DoubleToString(net, 2), IntegerToString(trades),
                   DoubleToString(pf, 3), DoubleToString(ddRel, 2), IntegerToString(violYears));
         FileClose(hs);
      }
   }

   if(trades < InpMinTrades || init <= 0 || lastT <= firstT) return 0.0;

   double years  = MathMax(1.0, (double)(lastT - firstT) / (365.25 * 86400.0));
   double annual = net / init * 100.0 / years;          // % per tahun (linear)
   double score  = annual / MathMax(ddRel, 5.0);        // return per unit DD
   if(ddRel > InpTargetMaxDD) score *= MathPow(InpTargetMaxDD / ddRel, 3.0);
   score /= (1.0 + violYears);                          // penalti tahun dgn >6 bulan loss
   score *= MathMin(1.0, MathSqrt((double)trades / (2.0 * InpMinTrades)));
   return score;
}
