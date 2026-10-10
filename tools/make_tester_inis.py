#!/usr/bin/env python3
"""Bikin file .ini Strategy Tester MT5 untuk 10 instrumen Exness.

  python make_tester_inis.py                 -> opt_<SYM>.ini + bt_<SYM>.ini (param default)
  python make_tester_inis.py best.json       -> bt_<SYM>.ini pakai parameter hasil optimasi

best.json contoh:
  {"XAUUSD": {"InpDonchian": 40, "InpSLATR": 2.0, "InpTrailATR": 3.0, "InpADXMin": 20}}

Jalankan di MT5:  terminal64.exe /config:bt_XAUUSD.ini
"""
import json
import os
import sys

# Sesuaikan nama simbol dengan Market Watch akun real Exness lo (suffix m/c/z dll).
SYMBOLS = {
    "EURUSDm": "Forex", "USDJPYm": "Forex",
    "XAUUSDm": "Logam", "XAGUSDm": "Logam",
    "JP225m": "Index", "US30m": "Index",
    "BTCUSDm": "Crypto", "ETHUSDm": "Crypto",
    "USOILm": "Energi", "UKOILm": "Energi",
}

EXPERT = r"Orion\Orion_Industrial"
FROM_DATE, TO_DATE = "2019.09.01", "2026.09.01"   # 7 tahun terakhir
DEPOSIT, CURRENCY = 10000, "USD"
LEVERAGE = 1  # no leverage; kalau tester menolak, pakai 100 (EA tetap cap notional <= equity)

# range optimasi: nilai||start||step||stop||Y
SWEEP = {
    "InpDonchian": (40, 20, 10, 80),
    "InpSLATR": (2.0, 1.5, 0.5, 3.5),
    "InpTrailATR": (3.0, 2.0, 0.5, 4.5),
    "InpADXMin": (20, 15, 3, 27),
}


def header(sym, model, optimization, criterion):
    return [
        "[Tester]",
        f"Expert={EXPERT}",
        f"Symbol={sym}",
        "Period=H4",
        f"Optimization={optimization}",     # 0 off, 2 genetic
        f"Model={model}",                   # 1 = 1 minute OHLC, 4 = every tick based on real ticks
        f"FromDate={FROM_DATE}",
        f"ToDate={TO_DATE}",
        "ForwardMode=0",
        f"Deposit={DEPOSIT}",
        f"Currency={CURRENCY}",
        f"Leverage={LEVERAGE}",
        "ExecutionMode=0",
        f"OptimizationCriterion={criterion}",  # 6 = custom max (OnTester)
        "Visual=0",
        "ShutdownTerminal=1",
        "ReplaceReport=1",
    ]


def main():
    best = {}
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8") as f:
            best = json.load(f)

    os.makedirs("ini", exist_ok=True)
    for sym in SYMBOLS:
        # Optimasi (in-sample, model OHLC 1 menit biar cepat)
        lines = header(sym, model=1, optimization=2, criterion=6)
        lines += [f"Report=Orion_opt_{sym}", "[TesterInputs]"]
        for k, (v, a, s, b) in SWEEP.items():
            lines.append(f"{k}={v}||{a}||{s}||{b}||Y")
        with open(f"ini/opt_{sym}.ini", "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

        # Backtest final (every tick based on real ticks, 7 tahun penuh)
        lines = header(sym, model=4, optimization=0, criterion=6)
        lines += [f"Report=Orion_bt_{sym}", "[TesterInputs]"]
        for k, val in best.get(sym, {}).items():
            lines.append(f"{k}={val}")
        with open(f"ini/bt_{sym}.ini", "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    print("OK -> folder ini/ (opt_*.ini dan bt_*.ini)")


if __name__ == "__main__":
    main()
