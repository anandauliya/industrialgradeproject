//+------------------------------------------------------------------+
//| OrionProfiles.mqh - default parameter per kelas instrumen         |
//| Nilai ini cuma titik awal; nilai final dicari lewat optimasi.     |
//+------------------------------------------------------------------+
#ifndef ORION_PROFILES_MQH
#define ORION_PROFILES_MQH

enum ENUM_ORION_CLASS
{
   ORION_FX = 0,
   ORION_METAL,
   ORION_INDEX,
   ORION_CRYPTO,
   ORION_ENERGY
};

struct SOrionProfile
{
   ENUM_ORION_CLASS cls;
   int    donchian;      // lookback breakout (bar TF entry)
   double slATR;         // jarak SL awal (x ATR)
   double trailATR;      // jarak chandelier trailing (x ATR)
   double adxMin;        // ADX minimum
   int    hourFrom;      // jam server mulai boleh entry (inklusif)
   int    hourTo;        // jam server batas entry (eksklusif)
   bool   closeFriday;   // tutup posisi jumat malam
   double maxSpreadATR;  // spread maks sbg fraksi ATR
};

ENUM_ORION_CLASS OrionDetectClass(const string sym)
{
   string s = sym;
   StringToUpper(s);
   if(StringFind(s, "XAU") >= 0 || StringFind(s, "XAG") >= 0) return ORION_METAL;
   if(StringFind(s, "BTC") >= 0 || StringFind(s, "ETH") >= 0) return ORION_CRYPTO;
   if(StringFind(s, "OIL") >= 0 || StringFind(s, "BRENT") >= 0 || StringFind(s, "WTI") >= 0) return ORION_ENERGY;
   if(StringFind(s, "JP225") >= 0 || StringFind(s, "US30") >= 0 || StringFind(s, "USTEC") >= 0 ||
      StringFind(s, "US500") >= 0 || StringFind(s, "DE30") >= 0 || StringFind(s, "UK100") >= 0) return ORION_INDEX;
   return ORION_FX;
}

void OrionLoadProfile(const string sym, SOrionProfile &p)
{
   p.cls = OrionDetectClass(sym);
   switch(p.cls)
   {
      case ORION_METAL:
         p.donchian = 36; p.slATR = 2.2; p.trailATR = 3.2; p.adxMin = 20.0;
         p.hourFrom = 4; p.hourTo = 20; p.closeFriday = true; p.maxSpreadATR = 0.15; break;
      case ORION_INDEX:
         p.donchian = 30; p.slATR = 2.0; p.trailATR = 3.0; p.adxMin = 18.0;
         p.hourFrom = 0; p.hourTo = 20; p.closeFriday = true; p.maxSpreadATR = 0.15; break;
      case ORION_CRYPTO:
         p.donchian = 48; p.slATR = 2.5; p.trailATR = 3.5; p.adxMin = 22.0;
         p.hourFrom = 0; p.hourTo = 24; p.closeFriday = false; p.maxSpreadATR = 0.20; break;
      case ORION_ENERGY:
         p.donchian = 36; p.slATR = 2.2; p.trailATR = 3.2; p.adxMin = 20.0;
         p.hourFrom = 4; p.hourTo = 20; p.closeFriday = true; p.maxSpreadATR = 0.15; break;
      default: // FX
         p.donchian = 40; p.slATR = 2.0; p.trailATR = 3.0; p.adxMin = 20.0;
         p.hourFrom = 4; p.hourTo = 20; p.closeFriday = true; p.maxSpreadATR = 0.12; break;
   }
}

#endif
