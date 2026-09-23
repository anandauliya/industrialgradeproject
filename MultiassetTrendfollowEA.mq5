//+------------------------------------------------------------------+
//|  EA_MultiAsset_TrendFollow.mq5                                    |
//|  Industrial-grade swing/trend-following EA                        |
//|                                                                    |
//|  DESIGN CONSTRAINTS (per spec):                                   |
//|   - No martingale, no grid, no HFT (one signal check per new bar) |
//|   - No leverage-amplified sizing: lot size derived ONLY from      |
//|     %risk of equity vs. stop distance, never from margin/leverage |
//|   - One position per symbol at a time                             |
//|   - ATR-based SL/TP, optional trailing stop                       |
//|   - Built-in monthly drawdown guard (soft trading halt)           |
//|                                                                    |
//|  This EA is a STARTING FRAMEWORK. It must be optimized per        |
//|  instrument (EMA periods, ATR multiples) in MT5 Strategy Tester   |
//|  using Exness real-tick history before any conclusions are drawn. |
//+------------------------------------------------------------------+
#property copyright "Industrial EA Project"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//---------------- INPUTS ----------------
input group "=== Trend Filter ==="
input int    InpEmaFast        = 21;      // Fast EMA period
input int    InpEmaSlow        = 55;      // Slow EMA period
input int    InpEmaTrend       = 200;     // Higher trend-filter EMA period
input ENUM_TIMEFRAMES InpTF    = PERIOD_H4; // Working timeframe (swing, NOT HFT)

input group "=== Risk & Sizing (NO leverage amplification) ==="
input double InpRiskPercent    = 1.0;     // % of equity risked per trade
input double InpAtrSLMult      = 2.0;     // SL = ATR * this
input double InpAtrTPMult      = 3.5;     // TP = ATR * this (fixed RR, no grid/averaging)
input int    InpAtrPeriod      = 14;
input bool   InpUseTrailing    = true;
input double InpTrailAtrMult   = 1.5;     // trail distance = ATR * this

input group "=== Drawdown / Money Management Guard ==="
input double InpMonthlyDDHalt  = 8.0;     // if equity DD in current month exceeds this %, stop opening new trades until next month
input double InpMaxAccountDD   = 25.0;    // hard halt: close-only mode if account DD from equity high exceeds this %

input group "=== Misc ==="
input ulong  InpMagic          = 20260923;
input int    InpSlippagePoints = 30;

int hEmaFast, hEmaSlow, hEmaTrend, hAtr;
datetime lastBarTime = 0;
double   equityHighWaterMark = 0;
double   monthStartEquity    = 0;
int      currentMonth        = -1;
bool     tradingHaltedHardDD = false;

int OnInit()
  {
   hEmaFast  = iMA(_Symbol, InpTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow  = iMA(_Symbol, InpTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hEmaTrend = iMA(_Symbol, InpTF, InpEmaTrend, 0, MODE_EMA, PRICE_CLOSE);
   hAtr      = iATR(_Symbol, InpTF, InpAtrPeriod);

   if(hEmaFast==INVALID_HANDLE || hEmaSlow==INVALID_HANDLE ||
      hEmaTrend==INVALID_HANDLE || hAtr==INVALID_HANDLE)
     {
      Print("Failed to create indicator handles");
      return(INIT_FAILED);
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   equityHighWaterMark = AccountInfoDouble(ACCOUNT_EQUITY);
   monthStartEquity    = equityHighWaterMark;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   currentMonth = dt.mon;

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(hEmaFast);
   IndicatorRelease(hEmaSlow);
   IndicatorRelease(hEmaTrend);
   IndicatorRelease(hAtr);
  }

bool IsNewBar()
  {
   datetime t = iTime(_Symbol, InpTF, 0);
   if(t != lastBarTime)
     {
      lastBarTime = t;
      return true;
     }
   return false;
  }

void UpdateDrawdownGuards()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > equityHighWaterMark) equityHighWaterMark = equity;

   double accountDDpct = (equityHighWaterMark - equity) / equityHighWaterMark * 100.0;
   tradingHaltedHardDD = (accountDDpct >= InpMaxAccountDD);

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.mon != currentMonth)
     {
      currentMonth = dt.mon;
      monthStartEquity = equity;
     }
  }

bool MonthlyHaltActive()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double monthDDpct = (monthStartEquity - equity) / monthStartEquity * 100.0;
   return (monthDDpct >= InpMonthlyDDHalt);
  }

double CalcLotSize(double slDistancePoints)
  {
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney  = equity * (InpRiskPercent / 100.0);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickValue<=0 || tickSize<=0 || point<=0) return 0.0;

   double valuePerPoint = tickValue * (point / tickSize);
   double slValue        = slDistancePoints * valuePerPoint;
   if(slValue<=0) return 0.0;

   double lots = riskMoney / slValue;

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots/lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
  }

bool HasOpenPosition()
  {
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            PositionGetInteger(POSITION_MAGIC)==(long)InpMagic)
            return true;
        }
     }
   return false;
  }

void ManageTrailingStop()
  {
   if(!InpUseTrailing) return;
   double atr[]; ArraySetAsSeries(atr,true);
   if(CopyBuffer(hAtr,0,0,1,atr)<=0) return;
   double trailDist = atr[0]*InpTrailAtrMult;

   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic) continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double sl   = PositionGetDouble(POSITION_SL);
      double price= (type==POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                                                : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double newSL;
      if(type==POSITION_TYPE_BUY)
        {
         newSL = price - trailDist;
         if(newSL > sl + SymbolInfoDouble(_Symbol,SYMBOL_POINT) && newSL < price)
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
        }
      else
        {
         newSL = price + trailDist;
         if((sl==0 || newSL < sl - SymbolInfoDouble(_Symbol,SYMBOL_POINT)) && newSL > price)
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
        }
     }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateDrawdownGuards();
   ManageTrailingStop();

   if(!IsNewBar()) return;           // <-- hard guarantee: never HFT
   if(tradingHaltedHardDD) return;   // hard account DD breached -> close-only, no new entries
   if(MonthlyHaltActive()) return;   // soft monthly DD guard
   if(HasOpenPosition()) return;     // one position per symbol, no grid/averaging

   double emaFast[], emaSlow[], emaTrend[], atr[];
   ArraySetAsSeries(emaFast,true); ArraySetAsSeries(emaSlow,true);
   ArraySetAsSeries(emaTrend,true); ArraySetAsSeries(atr,true);

   if(CopyBuffer(hEmaFast,0,0,3,emaFast)<=0)  return;
   if(CopyBuffer(hEmaSlow,0,0,3,emaSlow)<=0)  return;
   if(CopyBuffer(hEmaTrend,0,0,3,emaTrend)<=0)return;
   if(CopyBuffer(hAtr,0,0,2,atr)<=0)          return;

   bool crossUp   = (emaFast[2] <= emaSlow[2]) && (emaFast[1] > emaSlow[1]);
   bool crossDown = (emaFast[2] >= emaSlow[2]) && (emaFast[1] < emaSlow[1]);
   bool uptrend   = emaFast[1] > emaTrend[1];
   bool downtrend = emaFast[1] < emaTrend[1];

   double atrVal = atr[1];
   if(atrVal<=0) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slDistPrice  = atrVal * InpAtrSLMult;
   double tpDistPrice  = atrVal * InpAtrTPMult;
   double slDistPoints = slDistPrice / point;

   double lots = CalcLotSize(slDistPoints);
   if(lots<=0) return;

   if(crossUp && uptrend)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = ask - slDistPrice;
      double tp  = ask + tpDistPrice;
      trade.Buy(lots, _Symbol, ask, sl, tp, "TrendFollow-Buy");
     }
   else if(crossDown && downtrend)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = bid + slDistPrice;
      double tp  = bid - tpDistPrice;
      trade.Sell(lots, _Symbol, bid, sl, tp, "TrendFollow-Sell");
     }
  }
