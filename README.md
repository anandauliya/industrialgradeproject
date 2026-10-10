# industrialgradeproject

Laporan dapat dilihat pada [IndustrialGradeProject](https://docs.google.com/document/d/1WFXfDfPj3XkI6MSGKgfysT3M_PNgGwm1NDjhqrkDru8/edit?usp=sharing)

# Orion Industrial EA

Expert Advisor (EA) trend-following breakout multi-aset untuk MetaTrader 5.
Proyek ini dikerjakan oleh Ananda Auliya Rahma (24/533691/PA/22608), Departemen Ilmu Komputer dan Elektronika, FMIPA, Universitas Gadjah Mada, 2026.

---

## Ringkasan

Orion Industrial masuk searah tren besar ketika harga H4 menembus kisaran tertinggi atau terendah N bar (Donchian), lalu keluar lewat trailing stop berbasis ATR. Strategi disaring oleh tren EMA D1, kekuatan tren ADX, dan rasio volatilitas ATR. EA memegang satu posisi per simbol, merisikokan 1% equity per trade, dan membatasi notional posisi maksimal 1x equity. EA tidak memakai martingale, grid, maupun HFT.

**Hasil sejauh ini**

| Pengujian | Hasil utama |
|---|---|
| Optimasi JP225 (164 pass) | Profit tertinggi hanya 1.048,61 USD dari deposit 10.000 USD, DD equity 2,75–10,36%. 75% pass positif di forward, 98% positif di back, tetapi korelasi forward-back hanya 0,14 (Spearman). |
| Backtest XAUUSD H4, 1 Sep 2024 – 1 Sep 2026, 100% real ticks | Net 1.355,46 USD (13,55%), CAGR sekitar 6,56%, DD equity 7,04%, profit factor 1,79, 71 trade, win rate 45,07%, maksimal 4 bulan loss per tahun. |
| Backtest 7 instrumen (EURUSD, USDJPY, XAUUSD, XAGUSD, JP225, BTCUSD, ETHUSD) | Semua positif: net 0,44–17,22%, DD equity 1,51–7,04%, profit factor 1,05–1,93. Terbaik BTCUSD (+17,22%), terlemah USDJPY (+0,44%). ETHUSD hanya 9 bulan. |

**Kesimpulan sementara**

- EA aman dari sisi drawdown (jauh di bawah batas 25–30%) tetapi return jauh di bawah target 50–70% per tahun dan 3–5% per bulan.
- Satu pass "terbaik" belum bisa dipercaya karena hasil forward dan back hampir tidak berkorelasi dan tiap pass hanya memuat 32–80 trade.
- Trailing stop 3,0–3,5 ATR adalah temuan paling stabil di JP225 (58 dari 60 pass positif di forward, dibanding 3 dari 23 pada 2,5 ATR).
- Hasil XAUUSD kemungkinan dipengaruhi tren naik emas (±2.500 ke di atas 5.000) dan 56 dari 71 trade adalah long.
- Net EURUSD, USDJPY, dan ETHUSD bergantung pada satu trade terbesar: tanpa trade itu hasilnya negatif (−65,86; −81,72; −218,08 USD). Pada BTCUSD dan XAGUSD satu trade terbesar menyumbang sekitar 51% net.

---

## Target dan ketentuan

| Kriteria | Target |
|---|---|
| Return bulanan | 3% – 5% |
| Return tahunan | 50% – 70% |
| Maximum drawdown | 25% – 30% |
| Bulan loss | Maksimal 6 per tahun |
| Dilarang | Martingale, grid, HFT |
| Leverage dalam sizing | Tidak digunakan (didefinisikan sebagai notional maksimal 1x equity) |

Definisi "tanpa leverage" sebagai notional maksimal 1x equity masih perlu dikonfirmasi ke dosen.

---

## Instrumen

| Kelas | Instrumen | Status |
|---|---|---|
| Forex | EURUSD, USDJPY | Backtest 2 tahun |
| Logam | XAUUSD, XAGUSD | Backtest 2 tahun |
| Index | JP225, US30 | JP225: dioptimasi dan backtest 2 tahun. US30: belum diuji |
| Crypto | BTCUSD, ETHUSD | BTCUSD: backtest 2 tahun. ETHUSD: backtest 9 bulan |
| Energi | USOIL, UKOIL | Belum diuji |

Nama simbol mengikuti Market Watch Exness (contoh yang dipakai pada tes: `XAUUSDm`).

---

## Logika strategi

Semua sinyal dievaluasi pada bar yang sudah tutup (shift 1), sehingga tidak ada look-ahead.

**Syarat entry long** (short kebalikannya):

1. Close H4 terakhir menembus high tertinggi N bar sebelumnya (Donchian).
2. Close D1 berada di atas EMA 50 D1 dan EMA itu sedang naik.
3. ADX H4 minimal sama dengan ambang `InpADXMin`.
4. ATR sekarang berada antara 0,8x dan 2,5x rata-rata ATR 50 bar.
5. Jam server di dalam sesi, spread tidak melebihi batas fraksi ATR, dan belum ada posisi di simbol itu.

**Cara keluar**

- Stop loss awal sejauh `InpSLATR` x ATR dari harga entry.
- Trailing chandelier: high tertinggi 22 bar dikurangi `InpTrailATR` x ATR, hanya bergerak searah profit.
- Setelah profit mencapai 1,5 ATR, SL dipindah ke break-even ditambah spread.
- Time stop pada 120 bar H4 dan penutupan posisi Jumat malam (kecuali crypto).

**Parameter awal per kelas instrumen** (titik awal optimasi, bukan hasil akhir)

| Kelas | Donchian | SL (xATR) | Trailing (xATR) | ADX min | Jam entry server | Tutup Jumat |
|---|---|---|---|---|---|---|
| Forex | 40 | 2,0 | 3,0 | 20 | 04–20 | Ya |
| Logam | 36 | 2,2 | 3,2 | 20 | 04–20 | Ya |
| Index | 30 | 2,0 | 3,0 | 18 | 00–20 | Ya |
| Crypto | 48 | 2,5 | 3,5 | 22 | 00–24 | Tidak |
| Energi | 36 | 2,2 | 3,2 | 20 | 04–20 | Ya |

---

## Manajemen risiko

Ukuran lot ditentukan oleh risiko per trade, lalu dipotong oleh batas notional:

```
Lot = min( E * r * m / L ,  E * X / N )
m   = max( 0.25 , 1 - DD / DD_halt )
```

E = equity, r = risiko per trade (1%), L = kerugian per lot bila SL kena, X = batas notional (1,0), N = notional per lot. Bila hasilnya di bawah lot minimum broker, EA tidak membuka posisi. Lot tidak pernah dinaikkan setelah loss.

| Pengaman | Nilai bawaan | Perilaku |
|---|---|---|
| Risiko per trade | 1% equity | Dikali m, turun hingga 25% saat DD naik |
| Batas notional | 1x equity | Syarat tanpa leverage |
| Loss harian | 3% | Stop entry sampai hari berikutnya |
| Loss bulanan | 8% | Stop entry sampai bulan berikutnya |
| Circuit breaker DD | 25% dari puncak equity | Tutup posisi, halt sampai awal bulan berikutnya |
| Trade per hari | Maksimal 2 | Mencegah perilaku frekuensi tinggi |
| Margin | Maksimal 90% margin bebas | Entry dibatalkan bila melebihi |

Setelah halt, EA aktif lagi bulan berikutnya dengan risiko minimum 25%. Halt baru hanya bisa terjadi lagi setelah equity pulih ke setengah ambang DD atau membuat puncak baru.

---

## Arsitektur dan struktur proyek

EA utama hanya mengorkestrasi tiga modul. Modul sinyal tidak mengenal uang dan modul risiko tidak mengenal indikator, sehingga keduanya dapat diuji dan diubah terpisah.

```
[ISI: sesuaikan dengan struktur folder sebenarnya]
MQL5/
  Experts/Orion_Industrial.mq5     # EA utama (orkestrasi)
  Include/[ISI: modul sinyal].mqh
  Include/[ISI: modul risiko].mqh
  Include/[ISI: file keempat].mqh
tools/
  analyze.py                       # analisis hasil, grafik, heatmap
  [ISI: skrip Python kedua]
bt_*.ini                           # konfigurasi backtest Strategy Tester
Orion_summary.csv                  # ringkasan hasil per instrumen
```

---

## Parameter input

| Kelompok | Input | Nilai pada tes XAUUSD | Keterangan |
|---|---|---|---|
| Strategi | `InpTF` | 16388 (H4) | Time frame entry |
| | `InpTrendTF` | 16408 (D1) | Time frame filter tren |
| | `InpEMAPeriod` | 50 | Periode EMA filter D1 |
| | `InpATRPeriod` | 14 | Periode ATR |
| | `InpADXPeriod` | 14 | Periode ADX |
| | `InpATRMinRatio` / `InpATRMaxRatio` | 0,8 / 2,5 | Rentang rasio volatilitas |
| | `InpDonchian` | 20 | Jumlah bar channel breakout |
| | `InpSLATR` | 1,5 | Pengali ATR untuk SL awal |
| | `InpTrailATR` | 4,5 | Pengali ATR untuk trailing |
| | `InpADXMin` | 15 | Ambang minimum ADX |
| | `InpTrailLookback` | 22 | Lookback high tertinggi untuk trailing |
| | `InpBEATR` | 1,5 | Profit (xATR) untuk pindah ke break-even |
| | `InpTPR` | 0,0 | Take profit berbasis R (0 = nonaktif, diasumsikan) |
| | `InpMaxHoldBars` | 120 | Time stop (bar H4) |
| | `InpFridayCloseHour` | 20 | Jam tutup posisi Jumat |
| Risiko | `InpRiskPct` | 1,0 | Risiko per trade (% equity) |
| | `InpMaxNotionalX` | 1,0 | Notional maksimal (x equity) |
| | `InpDailyLossPct` | 3,0 | Batas loss harian (%) |
| | `InpMonthlyLossPct` | 8,0 | Batas loss bulanan (%) |
| | `InpDDHaltPct` | 25,0 | Circuit breaker DD (%) |
| | `InpMonthTargetStopPct` | 0,0 | Stop saat target bulanan tercapai (0 = nonaktif, diasumsikan) |
| | `InpMaxTradesPerDay` | 2 | Maksimal trade per hari |
| Eksekusi | `InpMagic` | 26100701 | Magic number |
| | `InpDeviation` | 30 | Deviasi harga (poin) |
| Optimasi | `InpTargetMaxDD` | 25,0 | DD target untuk skor custom |
| | `InpMinTrades` | 60 | Trade minimum agar skor tidak nol |

---

## Cara menjalankan backtest

1. Salin file MQL5 ke folder data MetaTrader 5 (`File > Open Data Folder`), lalu kompilasi `Orion_Industrial.mq5` di MetaEditor.
2. Pastikan histori tick penuh sudah terunduh untuk simbol dan periode yang diuji (buka chart, scroll ke kiri, cek tab Journal).
3. Di Strategy Tester pilih:
   - Expert: `Orion_Industrial`
   - Model: **Every tick based on real ticks**
   - Time frame: H4
   - Deposit: 10.000 USD, leverage 1:1
   - Periode target: 1 Oktober 2019 – 30 September 2026 (atau gunakan file `bt_*.ini`)
4. Untuk optimasi, pilih algoritma genetik dan kriteria **Custom max** (skor dari `OnTester`).
5. Jalankan `python tools/analyze.py` untuk menghasilkan tabel rekap, kurva balance per instrumen, kurva equity portofolio, dan heatmap return bulanan.

---

## Optimasi

Optimasi dijalankan per instrumen dengan algoritma genetik pada 1.050 kombinasi:

| Parameter | Rentang | Step |
|---|---|---|
| `InpDonchian` | 20–80 | 10 |
| `InpSLATR` | 1,5–3,5 | 0,5 |
| `InpTrailATR` | 2,0–4,5 | 0,5 |
| `InpADXMin` | 15–27 | 3 |

Skor custom di `OnTester` memakai return tahunan linear (A), DD equity relatif dalam persen (D), jumlah trade (T), dan jumlah tahun dengan lebih dari enam bulan loss (V):

```
Skor = A / max(D, 5) * (25 / D)^(3 * [D > 25]) * 1 / (1 + V) * min(1, sqrt(T / 120))
```

Skor ini condong ke pass dengan DD rendah dan trade sedikit, jadi parameter dipilih dari area yang stabil, bukan dari satu puncak, lalu diuji ulang dengan real ticks.

---

## Hasil

### Optimasi JP225

| Pass | Donchian | SL | Trailing | ADX | Forward | Back | Profit (USD) | DD (%) | Trade |
|---|---|---|---|---|---|---|---|---|---|
| Forward terbaik | 20 | 2,5 | 3,5 | 27 | 1,05 | 0,20 | 1.048,61 | 4,89 | 42 |
| Kandidat A | 40 | 2,5 | 3,5 | 27 | 0,87 | 0,33 | 926,25 | 4,47 | 36 |
| Kandidat B | 50 | 2,5 | 3,0 | 27 | 0,81 | 0,28 | 854,29 | 3,93 | 36 |
| Kandidat C | 30 | 3,0 | 3,5 | 21 | 0,91 | 0,20 | 877,33 | 4,33 | 47 |
| Back terbaik | 80 | 3,5 | 3,5 | 27 | 0,32 | 0,51 | 359,19 | 2,75 | 32 |

Catatan: ADX 27 adalah tepi atas rentang, sehingga rentang ADX perlu dilebarkan. Pass dengan 32–59 trade masih bersekor positif padahal `InpMinTrades` bawaan 60 seharusnya membuatnya nol; nilai input dan periode kolom Trades perlu dicek.

### Backtest XAUUSD (H4, 1 Sep 2024 – 1 Sep 2026)

Server Exness-MT5Real6 (Build 6238), 100% real ticks (159.793.465 tick, 3.192 bar), deposit 10.000 USD, leverage 1:1, parameter `InpDonchian` 20 / `InpSLATR` 1,5 / `InpTrailATR` 4,5 / `InpADXMin` 15.

| Metrik | Nilai |
|---|---|
| Total net profit | 1.355,46 USD (13,55%) |
| Profit factor | 1,79 |
| Expected payoff | 19,09 USD |
| Recovery factor | 1,59 |
| Sharpe ratio | 2,23 |
| Max DD equity / balance | 851,95 USD (7,04%) / 514,77 USD (4,36%) |
| Total trade | 71 (56 long, 15 short) |
| Win rate | 45,07% |
| Rata-rata profit / loss | 95,87 USD / −43,91 USD |
| Loss beruntun terpanjang | 6 trade (−140,69 USD) |
| Skor OnTester | 0,751 |

Bulan loss dihitung dari saldo balance akhir bulan: 1 bulan pada 2024, 2 pada 2025, dan 4 pada 2026, dengan rangkaian terpanjang 2 bulan beruntun. CAGR dan rata-rata bulanan dihitung dari net 13,55% selama 2 tahun dan perlu dicocokkan dengan `analyze.py`.

### Backtest enam instrumen lain

Server Exness-MT5Real6 (Build 6238), deposit 10.000 USD, leverage 1:1, H4. Periode 1 Sep 2024 – 1 Sep 2026, kecuali ETHUSD (1 Jan – 1 Okt 2026).

| Instrumen | Kualitas data | Donchian / SL / Trailing / ADX | Win rate | Rata-rata profit / loss (USD) | Loss beruntun terpanjang |
|---|---|---|---|---|---|
| EURUSD | 100% real ticks | 60 / 3,5 / 2,0 / 15 | 47,62% | 42,03 / −25,41 | 3 trade (−82,51 USD) |
| USDJPY | 33% real ticks | 50 / 3,5 / 4,0 / 18 | 52,50% | 40,35 / −42,28 | 3 trade (−181,77 USD) |
| XAGUSD | 33% real ticks | 20 / 2,0 / 3,5 / 21 | 53,06% | 82,19 / −58,70 | 4 trade (−275,48 USD) |
| JP225 | 33% real ticks | 40 / 2,5 / 3,5 / 27 | 62,50% | 78,02 / −67,43 | 3 trade (−212,40 USD) |
| BTCUSD | 100% (4,2 juta tick) | 20 / 2,5 / 4,0 / 21 | 44,93% | 118,95 / −51,72 | 6 trade (−285,32 USD) |
| ETHUSD | 100% real ticks | 80 / 1,5 / 3,5 / 27 | 28,57% | 286,01 / −81,72 | 4 trade (−314,98 USD) |

Catatan:

- Parameter JP225 sama dengan Kandidat A di tabel optimasi; profit 939,13 USD pada backtest ini dibanding 926,25 USD pada optimasi.
- Laporan JP225, XAGUSD, BTCUSD, dan ETHUSD memakai `InpMinTrades` 30 (EURUSD, USDJPY, XAUUSD memakai 60). Ini menjelaskan pass JP225 dengan 32–59 trade yang tetap bersekor positif.
- USDJPY mencapai 6 bulan loss pada 2025 (lima bulan beruntun April–Agustus), tepat di batas 6.
- BTCUSD berkualitas "100%" tanpa label real ticks dan hanya 4,2 juta tick (XAUUSD: 159,8 juta), jadi mode pengujiannya perlu dicek.

### Rekapitulasi 10 instrumen

| Instrumen | Net (%) | CAGR (%) | Rata-rata bulanan (%) | DD equity (%) | Profit factor | Trade | Bulan loss maks per tahun |
|---|---|---|---|---|---|---|---|
| EURUSD | 1,41 | 0,70 | 0,06 | 1,51 | 1,50 | 21 | 4 |
| USDJPY | 0,44 | 0,22 | 0,02 | 3,32 | 1,05 | 40 | 6 |
| XAUUSD | 13,55 | 6,56 | 0,53 | 7,04 | 1,79 | 71 | 4 |
| XAGUSD | 7,87 | 3,86 | 0,32 | 5,52 | 1,58 | 49 | 4 |
| JP225 | 9,39 | 4,59 | 0,37 | 4,48 | 1,93 | 40 | 4 |
| US30 | | | | | | | |
| BTCUSD | 17,22 | 8,27 | 0,66 | 5,88 | 1,88 | 69 | 5 |
| ETHUSD (9 bulan) | 3,27 | 4,38 | 0,36 | 5,82 | 1,40 | 14 | 5 |
| USOIL | | | | | | | |
| UKOIL | | | | | | | |
| Portofolio (bobot sama) | | | | | | | |

Net, DD equity, profit factor, dan jumlah trade diambil dari laporan Strategy Tester. CAGR dan rata-rata bulanan (geometrik) dihitung dari net selama periode uji (ETHUSD hanya 9 bulan, jadi CAGR-nya ekstrapolasi), dan bulan loss dihitung dari saldo balance akhir bulan; ketiganya perlu dicocokkan dengan `analyze.py`. Sel kosong akan diisi dari `Orion_summary.csv` dan keluaran `tools/analyze.py`, tidak diperkirakan.

---

## Kepatuhan terhadap ketentuan tugas

| No. | Ketentuan | Status |
| 1 | 10 instrumen dari lima kelas | Terkonfigurasi; 7 dari 10 sudah dibacktest, US30, USOIL, UKOIL belum |
| 2 | Tanpa martingale, grid, HFT | Terpenuhi (desain) |
| 3 | Tanpa leverage, DD maks 25–30%, bulanan 3–5% | DD (maks 7,04%) dan notional terpenuhi; return bulanan 0,02–0,66% belum tercapai |
| 4 | Target tahunan 50–70% | Belum tercapai (CAGR 0,22–8,27% pada 7 instrumen) |
| 5 | Bulan loss maksimal enam per tahun | Terpenuhi pada 7 instrumen (maks 6 pada USDJPY, tepat di batas); menunggu backtest penuh |
| 6 | Backtest 7 tahun, every tick based on real ticks | Belum dijalankan (baru 2 tahun; sebagian bukan 100% real ticks) |
| 7 | Broker Exness, akun real hanya untuk backtest | Menunggu backtest penuh |
| 8 | Time frame bebas | Terpenuhi (entry H4, filter D1) |
| 9 | Lampirkan kode proyek | Terpenuhi (4 file MQL5, 2 skrip Python) |
| 10 | Laporan backtest dan optimasi | Terpenuhi |

---

## Keterbatasan

- Return jauh di bawah target; perlu dibahas dengan dosen apakah "tanpa leverage" berarti notional maksimal 1x equity atau cukup risiko per trade yang kecil.
- Risiko overfitting: korelasi forward-back 0,14, jumlah trade per pass sedikit, dan parameter XAUUSD berada di tepi rentang optimasi tanpa validasi forward.
- Hasil XAUUSD berasal dari satu rezim tren naik selama 2 tahun.
- Net EURUSD, USDJPY, dan ETHUSD bergantung pada satu trade terbesar; tanpa trade itu hasilnya negatif.
- Jumlah trade per instrumen kecil (14–71), sehingga belum cukup untuk menyimpulkan edge yang stabil.
- Kualitas data tidak seragam: USDJPY, XAGUSD, JP225 hanya 33% real ticks, dan mode BTCUSD perlu dicek. Kualitas real ticks Exness untuk 7 tahun harus diperiksa per simbol.
- Hasil backtest tidak menjamin hasil live karena slippage, spread, dan rezim pasar dapat berbeda.

## Langkah lanjutan

1. Ulang optimasi JP225 dengan ADX sampai 33 dan Donchian mulai 10.
2. Uji kandidat A, B, dan C dengan every tick based on real ticks selama 7 tahun.
3. Optimasi sembilan instrumen lainnya dengan pola yang sama dan validasi forward, lalu backtest 7 tahun dengan 100% real ticks. Uji US30, USOIL, dan UKOIL yang belum ada hasilnya.
4. Jalankan `tools/analyze.py`, cocokkan angka hitungan manual, dan isi baris portofolio serta grafik.
5. Cocokkan laporan dengan spesifikasi file tugas dan lengkapi butir administratif.
6. Lakukan forward-test di akun demo sebelum penggunaan live.

---

## Referensi utama

- Wilder, J. W. (1978). *New Concepts in Technical Trading Systems* (ATR, ADX).
- Covel, M. W. (2007). *The Complete TurtleTrader*; Faith, C. M. (2007). *Way of the Turtle* (breakout).
- Pardo, R. (2008). *The Evaluation and Optimization of Trading Strategies* (walk-forward).
- Vince, R. (1992). *The Mathematics of Money Management* (fixed-fractional).
- Chan, E. (2009, 2013); Kaufman, P. J. (2013); Murphy, J. J. (1999); Tomasini & Jaekle (2009); Pruitt & Hill (2012).
- MQL5 Reference dan Strategy Tester Documentation (MetaQuotes); Exness trading conditions.

Daftar lengkap ada di laporan proyek.

## Disclaimer

Proyek ini untuk keperluan akademik. Hasil backtest historis bersifat indikatif dan tidak menjamin kinerja di masa depan. Trading derivatif berisiko tinggi; jangan dipakai di akun live tanpa forward-test dan pemahaman penuh atas risikonya.
