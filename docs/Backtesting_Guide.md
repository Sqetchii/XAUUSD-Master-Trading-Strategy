# Backtesting-Guide: SMC_XAUUSD_EA in MetaTrader 5

## 1. Installation

1. MetaTrader 5 öffnen → `Datei` → `Speicherort für Daten öffnen` (öffnet den
   MT5-Datenordner im Explorer/Finder).
2. Dateien aus diesem Repo in den passenden Unterordner von `MQL5/` kopieren:
   - `MQL5/Experts/SMC_XAUUSD_EA.mq5` → `<Datenordner>/MQL5/Experts/`
   - `MQL5/Indicators/SMC_Visualizer.mq5` → `<Datenordner>/MQL5/Indicators/`
   - `MQL5/Include/SMC/SMCCore.mqh` → `<Datenordner>/MQL5/Include/SMC/`
     (den Unterordner `SMC` neu anlegen, falls nicht vorhanden)
3. Im MetaEditor (F4 aus MT5) beide `.mq5`-Dateien öffnen und mit F7
   kompilieren. Es dürfen keine Fehler auftreten (Warnungen sind unkritisch).
4. Zurück in MT5: Navigator (Strg+N) → Rechtsklick auf `Experts`/`Indicators`
   → `Aktualisieren`, falls die Dateien nicht sofort erscheinen.

## 2. Tick-Daten-Qualität sicherstellen

Das MT5-Ergebnis (inkl. Sharpe Ratio) ist nur so gut wie die zugrunde liegenden
Kursdaten. Vor jedem ernsthaften Test:

1. `Strategy Tester` (Strg+R) → Reiter `Einstellungen` → Symbol `XAUUSD`
   wählen.
2. `Modell`: **"Jeder Tick basierend auf echten Kursen"** verwenden, nicht
   "OHLC" oder "Eröffnungskurse" — sonst werden Sweeps/Wicks innerhalb einer
   Kerze nicht korrekt simuliert.
3. Vor dem ersten Lauf im Tester-Reiter auf `Historien-Center` bzw. im
   Reiter „Einstellungen" auf die Lupe/„Modellierungsqualität prüfen" klicken.
   Ziel: möglichst nah an 99 % Modellierungsqualität. Falls dein Broker wenig
   Tickhistorie liefert, zusätzliche Tickdaten importieren (z. B. über einen
   Tick-Data-Suite-Import oder den Broker mit langer History wählen) — sonst
   sind frühere Jahre nur aus M1-OHLC interpoliert und die Ergebnisse unsicher.
4. **Spread realistisch setzen**: XAUUSD hat je nach Broker/Sitzung stark
   schwankende Spreads (grob 15–25 Punkte normal, bis 60+ um News/Rollover).
   Im Tester unter „Einstellungen" → „Spread" entweder „Aktuell" oder einen
   festen, konservativen Wert (z. B. 25–35 Punkte) einstellen — nicht 0.
5. Kommission/Swap im Konto-Profil des Testers hinterlegen, falls dein echter
   Broker welche berechnet — sonst wird die Performance systematisch zu gut.

## 3. Ersten Lauf durchführen

1. `Experten Advisor`: `SMC_XAUUSD_EA` wählen.
2. `Zeitraum`: mindestens 2–3 Jahre (mehr ist besser, siehe Abschnitt 5).
3. Chart-Timeframe im Tester auf `InpTimeframe` (Default M15) einstellen —
   das ist nur die Anzeige, der EA lädt sich seine Daten selbst per
   `CopyRates`, aber ein passender Chart-TF erleichtert die visuelle Kontrolle.
4. `Start` klicken. Nach Abschluss: Reiter `Ergebnisse` für die Trade-Liste,
   Reiter `Grafik` für die Equity-Kurve, Reiter `Bericht` (Rechtsklick →
   „Bericht speichern") für die vollständigen Statistiken inkl. **Sharpe
   Ratio**, **Profit Factor**, **Max Drawdown (absolut/relativ)**, **Recovery
   Factor**, **Expected Payoff**.

## 4. Signale visuell verifizieren

Bevor du den Zahlen traust: `SMC_Visualizer` auf denselben Chart/Zeitraum
laden (gleiche Inputs wie im EA verwenden). Er zeichnet mit derselben
Kern-Logik (`SMCCore.mqh`) Swing-Punkte, Order Blocks, FVGs und
Bestätigungssignale ein — so siehst du exakt, welche Setups der EA nehmen
würde, statt der Statistik blind zu vertrauen. Stichproben an 10–15 zufälligen
Signalen manuell prüfen: Ergibt der Sweep visuell Sinn, ist die Order-Block-
Zone plausibel, wäre der Trade so wirklich ausführbar gewesen?

## 5. Robustheit statt Overfitting: Walk-Forward & Out-of-Sample

Ein einzelner optimierter Backtest-Lauf ist fast immer überoptimiert. Vorgehen:

1. **Datensatz dreiteilen**: z. B. 2018–2022 = In-Sample (Optimierung),
   2023–2024 = Out-of-Sample (Validierung, keine weitere Anpassung), 2025–heute
   = finaler Walk-Forward-Check.
2. **Optimierung nur auf In-Sample**: Tester-Reiter `Einstellungen` →
   `Optimierung` aktivieren, Parameter wie `InpSweepATR_Mult`,
   `InpConfirmATR_Mult`, `InpRR`, `InpSwingLookback` in sinnvollen Bereichen
   variieren. Als Optimierungskriterium **nicht** nur „Gewinn maximieren"
   nehmen, sondern in MT5 „Complex Criterion max" bzw. manuell nach
   Sharpe Ratio / (Sharpe Ratio bei möglichst niedrigem Max Drawdown) sortieren.
3. **Out-of-Sample-Test mit den gewählten Parametern, ohne weitere Anpassung.**
   Wenn die Performance dort massiv einbricht (z. B. Sharpe fällt von 1,8 auf
   0,3, PF von 1,3 auf <1,0), war die In-Sample-Optimierung überangepasst —
   Parameter-Ranges verbreitern oder Setup-Filter (Session, Trendfilter)
   strenger statt lockerer wählen.
4. **MT5-eigener Walk-Forward** (ab MT5-Build mit Walk-Forward-Unterstützung
   im Tester) oder manuell in rollierenden Fenstern (z. B. 12 Monate
   optimieren → nächste 3 Monate testen → Fenster verschieben) wiederholen.
5. **Monte-Carlo-Drawdown-Simulation**: Trade-Liste aus dem Bericht exportieren
   und die Reihenfolge der Trade-Ergebnisse zufällig neu mischen (z. B. per
   Skript/Excel), um zu sehen, wie stark der Max Drawdown streut, wenn dieselben
   Trades in anderer Reihenfolge aufgetreten wären. Ein System, dessen
   Drawdown-Verteilung sehr breit streut, ist fragiler als der einzelne
   beobachtete Lauf suggeriert.
6. **Parameter-Sensitivität prüfen**: Für die wichtigsten Parameter (v. a.
   `InpSweepATR_Mult`, `InpConfirmATR_Mult`, `InpRR`) die 3D-Optimierungs-
   Oberfläche im Tester ansehen. Ein robuster Bereich zeigt ein „Plateau"
   ähnlich guter Ergebnisse; ein einzelner scharfer Peak ist ein
   Overfitting-Warnsignal — dann lieber einen Wert aus der Mitte des Plateaus
   wählen statt das absolute Maximum.

## 6. Vor dem Live-/Demo-Einsatz

1. Mindestens 4–8 Wochen **Demo-Forward-Test** parallel zum fortlaufenden
   Marktgeschehen — das ist der einzige Test, der garantiert nicht
   in-die-Vergangenheit-optimiert sein kann.
2. Reale Ausführung mit dem Backtest vergleichen (Slippage, Requotes,
   tatsächliche Fill-Preise vs. simulierte).
3. Kapitaleinsatz klein starten, `InpRiskPercent` konservativ (≤1 %) lassen,
   `InpDailyLossLimitPercent` als harte Notbremse aktiv lassen.
4. Diese Strategie ist ein Forschungs-/Backtesting-Werkzeug, kein
   Finanzberatungsprodukt — die Verantwortung für jede Live-Entscheidung liegt
   bei dir.

## 7. Wichtige Inputs im Überblick

| Input | Zweck |
|---|---|
| `InpTimeframe` | Signal-Zeitrahmen (Default M15) |
| `InpSwingLookback` | Bars je Seite zur Swing-Bestätigung |
| `InpUseHTFTrendFilter`, `InpHTF`, `InpHTF_EMA_Period` | Higher-Timeframe-Trendfilter |
| `InpSweepATR_Mult` | Mindest-Wick-Durchbruch über Swing, in ATR |
| `InpConfirmBars`, `InpConfirmATR_Mult` | Bestätigungsfenster & Mindest-Momentum |
| `InpRequireFVG` | Optionale FVG-Konfluenz (Default aus) |
| `InpUsePremiumDiscount` | Nur Käufe im Discount / Verkäufe im Premium der Swing-Range |
| `InpSL_ATR_Buffer`, `InpMinSL_ATR`, `InpRR` | Stop/Ziel-Berechnung |
| `InpUseBreakeven`, `InpBreakevenAtR` | Breakeven-Management |
| `InpUseSessionFilter`, `InpSession1..3*` | Killzone-Fenster (Broker-/Serverzeit!) |
| `InpRiskPercent`, `InpDailyLossLimitPercent`, `InpMaxTradesPerDay`, `InpMaxConsecLosses`, `InpCooldownBars` | Risikomanagement |
| `InpMaxSpreadPoints` | Spread-Filter |

**Wichtig zu Sessions**: Die Stunden sind Broker-/Serverzeit, nicht GMT — dein
Broker-Server läuft meist auf GMT+2/GMT+3 (mit DST-Wechsel). Prüfe die aktuelle
Serverzeit (`TimeCurrent()` bzw. Uhrzeit unten rechts im MT5-Terminal) und
passe `InpSession1StartHour` etc. entsprechend an, damit die Fenster wirklich
London-Open (ca. 08:00–11:00 Uhr GMT) und den London/NY-Overlap (ca.
13:00–16:00 Uhr GMT) treffen.
