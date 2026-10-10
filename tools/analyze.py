#!/usr/bin/env python3
"""Olah hasil backtest MT5 (CSV dari OnTester) jadi laporan Markdown + grafik.

  python analyze.py <folder_csv> [out_dir]

<folder_csv> = folder Common\\Files MT5 yang berisi Orion_deals_*.csv dan Orion_summary.csv
Semua angka laporan berasal dari data tester lo; script ini tidak membuat angka sendiri.
Catatan: DD di tabel utama = DD equity dari Strategy Tester (Orion_summary.csv).
DD dari kurva balance (closed trade) ditampilkan sebagai pembanding.
"""
import glob
import os
import sys
from datetime import datetime

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

GROUPS = {
    "EURUSD": "Forex", "USDJPY": "Forex", "XAUUSD": "Logam", "XAGUSD": "Logam",
    "JP225": "Index", "US30": "Index", "BTCUSD": "Crypto", "ETHUSD": "Crypto",
    "USOIL": "Energi", "UKOIL": "Energi",
}
INIT_DEFAULT = 10000.0


def load_deals(path):
    df = pd.read_csv(path, sep=";")
    df["time"] = pd.to_datetime(df["time"], format="%Y.%m.%d %H:%M:%S")
    df["pnl"] = df["pnl"].astype(float)
    return df.sort_values("time").reset_index(drop=True)


def monthly_returns(df, init):
    """Return bulanan = pnl bulan / balance awal bulan (compounding)."""
    df = df.copy()
    df["ym"] = df["time"].dt.to_period("M")
    pnl_m = df.groupby("ym")["pnl"].sum()
    idx = pd.period_range(pnl_m.index.min(), pnl_m.index.max(), freq="M")
    pnl_m = pnl_m.reindex(idx, fill_value=0.0)
    bal, rets = init, []
    for p in pnl_m:
        rets.append(p / bal if bal > 0 else 0.0)
        bal += p
    return pd.Series(rets, index=idx)


def balance_dd(df, init):
    bal = init + df["pnl"].cumsum()
    peak = bal.cummax().clip(lower=init)
    return float(((peak - bal) / peak).max() * 100.0)


def yearly_stats(mr):
    rows = []
    for y, s in mr.groupby(mr.index.year):
        rows.append({
            "Tahun": int(y),
            "Return (compound %)": ((1 + s).prod() - 1) * 100,
            "Bulan loss": int((s < 0).sum()),
            "Bulan >=3%": int((s >= 0.03).sum()),
            "Bulan 3-5%": int(((s >= 0.03) & (s <= 0.05)).sum()),
        })
    return pd.DataFrame(rows)


def md_table(df, floatfmt="{:.2f}"):
    cols = list(df.columns)
    out = ["| " + " | ".join(str(c) for c in cols) + " |",
           "|" + "|".join(["---"] * len(cols)) + "|"]
    for _, r in df.iterrows():
        cells = []
        for c in cols:
            v = r[c]
            cells.append(floatfmt.format(v) if isinstance(v, float) else str(v))
        out.append("| " + " | ".join(cells) + " |")
    return "\n".join(out)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else "report_out"
    os.makedirs(out, exist_ok=True)

    summ = None
    sp = os.path.join(src, "Orion_summary.csv")
    if os.path.exists(sp):
        summ = pd.read_csv(sp, sep=";").drop_duplicates("symbol", keep="last").set_index("symbol")

    data, mrets, rows = {}, {}, []
    for path in sorted(glob.glob(os.path.join(src, "Orion_deals_*.csv"))):
        sym = os.path.basename(path)[len("Orion_deals_"):-4]
        df = load_deals(path)
        if df.empty:
            continue
        init = float(summ.loc[sym, "initial"]) if summ is not None and sym in summ.index else INIT_DEFAULT
        data[sym] = (df, init)
        mr = monthly_returns(df, init)
        mrets[sym] = mr
        yrs = max(1.0, (df["time"].iloc[-1] - df["time"].iloc[0]).days / 365.25)
        total = df["pnl"].sum() / init * 100
        ys = yearly_stats(mr)
        ddt = float(summ.loc[sym, "eq_dd_pct"]) if summ is not None and sym in summ.index else float("nan")
        trades = int(summ.loc[sym, "trades"]) if summ is not None and sym in summ.index else len(df) // 2
        pf = float(summ.loc[sym, "pf"]) if summ is not None and sym in summ.index else float("nan")
        rows.append({
            "Instrumen": sym, "Kelas": GROUPS.get(sym, "-"),
            "Net %": total, "CAGR %": ((1 + total / 100) ** (1 / yrs) - 1) * 100,
            "Rata2 bln %": mr.mean() * 100, "DD equity % (tester)": ddt,
            "DD balance %": balance_dd(df, init), "Trades": trades, "PF": pf,
            "Bln loss maks/thn": int(ys["Bulan loss"].max()),
            "Bln 3-5%": int(ys["Bulan 3-5%"].sum()),
        })
    if not rows:
        print("Tidak ada file Orion_deals_*.csv di", src)
        sys.exit(1)

    res = pd.DataFrame(rows)

    # portfolio = alokasi sama rata, tiap instrumen akun sendiri, rebalance bulanan
    allm = pd.concat(mrets, axis=1).fillna(0.0)
    port = allm.mean(axis=1)
    pe = (1 + port).cumprod()
    port_dd = float(((pe.cummax() - pe) / pe.cummax()).max() * 100)
    port_total = (pe.iloc[-1] - 1) * 100
    port_years = len(port) / 12.0
    port_cagr = (pe.iloc[-1] ** (1 / port_years) - 1) * 100
    port_ys = yearly_stats(port)

    # grafik
    fig, ax = plt.subplots(figsize=(10, 5))
    for sym, (df, init) in data.items():
        ax.plot(df["time"], init + df["pnl"].cumsum(), label=sym, linewidth=1)
    ax.set_title("Kurva balance per instrumen (closed trade)")
    ax.legend(ncol=5, fontsize=7)
    ax.grid(alpha=.3)
    fig.tight_layout(); fig.savefig(os.path.join(out, "equity_per_instrument.png"), dpi=130); plt.close(fig)

    fig, ax = plt.subplots(figsize=(10, 4))
    ax.plot(pe.index.to_timestamp(), pe.values, color="navy")
    ax.set_title("Kurva equity portfolio (equal weight, 10 instrumen)")
    ax.grid(alpha=.3)
    fig.tight_layout(); fig.savefig(os.path.join(out, "equity_portfolio.png"), dpi=130); plt.close(fig)

    fig, ax = plt.subplots(figsize=(11, 4 + 0.3 * len(allm.columns)))
    hm = (allm.T * 100)
    im = ax.imshow(hm.values, aspect="auto", cmap="RdYlGn", vmin=-8, vmax=8)
    ax.set_yticks(range(len(hm.index))); ax.set_yticklabels(hm.index, fontsize=7)
    step = max(1, len(hm.columns) // 14)
    ax.set_xticks(range(0, len(hm.columns), step))
    ax.set_xticklabels([str(c) for c in hm.columns[::step]], rotation=45, fontsize=7)
    ax.set_title("Return bulanan (%)")
    fig.colorbar(im); fig.tight_layout()
    fig.savefig(os.path.join(out, "monthly_heatmap.png"), dpi=130); plt.close(fig)

    allm.mul(100).round(2).to_csv(os.path.join(out, "monthly_returns.csv"))

    # cek aturan tugas
    def chk(ok):
        return "LULUS" if ok else "TIDAK LULUS"
    avg_m = port.mean() * 100
    checks = [
        ("Target bulanan 3-5% (rata2 portfolio)", f"{avg_m:.2f}%", chk(3 <= avg_m <= 5)),
        ("Target tahunan 50-70% (CAGR portfolio)", f"{port_cagr:.1f}%", chk(50 <= port_cagr <= 70)),
        ("Max DD portfolio <= 30%", f"{port_dd:.1f}%", chk(port_dd <= 30)),
        ("Bulan loss <= 6 per tahun (portfolio)", f"maks {int(port_ys['Bulan loss'].max())}",
         chk(port_ys["Bulan loss"].max() <= 6)),
    ]
    chk_df = pd.DataFrame(checks, columns=["Aturan", "Hasil", "Status"])

    now = datetime.now().strftime("%d %B %Y")
    first = min(d["time"].iloc[0] for d, _ in data.values()).strftime("%Y-%m-%d")
    last = max(d["time"].iloc[-1] for d, _ in data.values()).strftime("%Y-%m-%d")

    rep = f"""# Laporan Backtest & Optimasi — Orion Industrial EA

Dibuat: {now} | Periode data: {first} s/d {last}

## 1. Ringkasan proyek
Orion Industrial adalah EA trend-following berbasis breakout Donchian pada TF H4 dengan filter tren
EMA D1, ADX, dan rasio volatilitas ATR. Satu posisi per simbol, stop-loss wajib, trailing chandelier,
time stop, dan penutupan Jumat. Tidak memakai martingale, grid, maupun HFT.

## 2. Pengaturan pengujian
- Broker/akun: Exness (akun real, hanya untuk backtest)
- Model: Every tick based on real ticks
- Periode: 7 tahun terakhir
- Instrumen (10): {", ".join(res["Instrumen"])}
- Deposit awal per instrumen: ${INIT_DEFAULT:,.0f} (akun terpisah per instrumen)
- Tanpa leverage: notional posisi dibatasi <= 1x equity (`InpMaxNotionalX = 1.0`)
- Risiko per trade 1% equity, turun otomatis saat drawdown (bukan naik: anti-martingale)

## 3. Manajemen risiko (kode)
- Limit loss harian 3% dan bulanan 8% (stop entry)
- Circuit breaker: flat dan halt sampai awal bulan berikutnya bila DD dari peak >= 25%
- Maks 2 trade per hari, time stop 120 bar H4, filter spread terhadap ATR

## 4. Metodologi optimasi
- Parameter: lookback Donchian, SL (xATR), trailing (xATR), ADX minimum
- Algoritma genetik; kriteria: Custom max (`OnTester`) = return tahunan / DD,
  penalti DD di atas batas dan penalti tahun dengan lebih dari 6 bulan loss
- Validasi akhir pada seluruh 7 tahun dengan every tick based on real ticks
- Risiko overfitting: parameter dipilih dari area stabil (plateau), bukan satu puncak

## 5. Hasil per instrumen
{md_table(res)}

DD equity (tester) adalah angka resmi; DD balance dihitung dari kurva closed trade sebagai pembanding.

![Equity per instrumen](equity_per_instrument.png)

## 6. Hasil portfolio (alokasi sama rata)
- Net kumulatif: {port_total:.1f}%
- CAGR: {port_cagr:.1f}%
- Rata-rata return bulanan: {avg_m:.2f}%
- Max DD portfolio (kurva bulanan): {port_dd:.1f}%

Catatan: portfolio dihitung dari return bulanan tiap instrumen (akun terpisah), jadi DD intrabulan
antar-instrumen tidak sepenuhnya tertangkap.

![Equity portfolio](equity_portfolio.png)

### Statistik tahunan portfolio
{md_table(port_ys)}

![Heatmap bulanan](monthly_heatmap.png)

## 7. Pemeriksaan terhadap ketentuan
{md_table(chk_df)}

## 8. Analisis dan keterbatasan
(Isi dengan analisis sendiri: instrumen terbaik/terburuk, periode sulit, penjelasan bulan loss,
dampak spread/komisi, dan alasan bila ada target yang tidak tercapai.)

Poin yang perlu dibahas jujur:
- Tanpa leverage, instrumen volatilitas rendah (terutama Forex) sulit mencapai 3-5% per bulan.
- Hasil backtest tidak menjamin hasil live (slippage, perubahan spread, rezim pasar).
- Parameter hasil optimasi punya risiko overfitting; periksa stabilitas di sekitar nilai terpilih.
"""
    with open(os.path.join(out, "Laporan_Backtest_Orion.md"), "w", encoding="utf-8") as f:
        f.write(rep)
    print("Selesai ->", out)


if __name__ == "__main__":
    main()
