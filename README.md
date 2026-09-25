# XAUUSD Master Trading Strategy — SMC Expert Advisor für MetaTrader 5

Regelbasierte Smart-Money-Concepts-Strategie für Gold (XAUUSD) samt
vollständig backtestbarer MQL5-Implementierung für MetaTrader 5.

## Wichtig: Bevor du irgendetwas testest

Lies zuerst **[`research/SMC_XAUUSD_Research.md`](research/SMC_XAUUSD_Research.md)**.
Kurzfassung: Es gibt keine seriöse akademische Bestätigung, dass "reines" SMC
(Order Blocks/FVGs) für sich genommen einen verifizierten Edge hat — die
gründlichste öffentlich verfügbare Studie fand praktisch keine statistisch
signifikante Kante bei mechanisch codierten ICT-Konzepten. Was real belegt ist:
Stop-Order-Clustering an Swing-Levels und Session-/Killzone-Volatilitätsmuster.
Genau darauf ist diese Strategie aufgebaut — nicht auf der unbelegten
"Institutionen jagen gezielt deine Stops"-Erzählung. **Und: "kein Drawdown"
gibt es bei keiner real handelbaren Strategie.** Ziel hier ist ein
kontrollierter, durch striktes Risikomanagement begrenzter Drawdown — nicht
null.

## Was hier drin ist

```
MQL5/
  Experts/SMC_XAUUSD_EA.mq5       Die Expert-Advisor-Strategie (Strategy-Tester-fähig)
  Indicators/SMC_Visualizer.mq5   Zeichnet dieselben Signale zur visuellen Kontrolle
  Include/SMC/SMCCore.mqh         Geteilte SMC-Erkennungslogik (Swings, Sweeps, OBs, FVGs)
research/SMC_XAUUSD_Research.md   Recherche, Quellen, ehrliche Einordnung
docs/Backtesting_Guide.md         Schritt-für-Schritt: Installation, Tick-Daten, Walk-Forward
```

## Strategie in Kürze

1. **HTF-Trendfilter** (H1-EMA50): nur Long über, nur Short unter der EMA.
2. **Liquidity Sweep**: Kerze durchbricht einen bestätigten Swing High/Low um
   mindestens `X × ATR` und schließt wieder zurück — der klassische Stop-Hunt.
3. **Order Block**: Kerzenkörper der Sweep-Kerze.
4. **Bestätigung**: Innerhalb weniger Kerzen muss ein Schlusskurs mit
   ausreichend Momentum (Mindest-Range in ATR) durch den Order Block zurück
   schließen.
5. **Optionale Filter**: Fair-Value-Gap-Konfluenz (standardmäßig aus),
   Premium/Discount-Zone der aktiven Swing-Range (standardmäßig an).
6. **Session-Filter**: Nur London-Open und London/NY-Overlap (konfigurierbar) —
   der am besten belegte Baustein der ganzen Strategie.
7. **Ausführung**: Markt-Entry, SL knapp jenseits des Sweep-Wicks (ATR-Puffer),
   TP als festes R:R-Vielfaches, optionales Breakeven-Management.
8. **Risikomanagement**: % Risiko pro Trade, Tagesverlustlimit, Cooldown nach
   Verlustserie, max. Trades/Tag, Spread-Filter, nur eine Position gleichzeitig,
   kein Martingale/Grid.

Jeder dieser Punkte ist über Inputs konfigurierbar/deaktivierbar, damit du im
Strategy-Tester-Optimizer selbst prüfen kannst, welcher Baustein tatsächlich
zur risikoadjustierten Performance beiträgt, statt das blind zu glauben.

## Los geht's

Siehe **[`docs/Backtesting_Guide.md`](docs/Backtesting_Guide.md)** für:
Installation in MT5, korrekte Tick-Daten-/Spread-Einstellungen, wie du die
Signale visuell verifizierst, und wie du Walk-Forward-/Out-of-Sample-/
Monte-Carlo-Tests durchführst, um Overfitting zu erkennen, bevor du irgendeiner
Zahl aus einem einzelnen Backtest-Lauf traust.

## Realistische Zielgrößen für deine eigenen Backtests

Profit Factor > 1,2 · Sharpe Ratio > 1,0 (annualisiert) · Max Drawdown < 15–20 % ·
mindestens 100+ Trades über 2–3+ Jahre Daten. Reale, öffentlich dokumentierte
SMC-Systeme mit ähnlicher Logik liegen bei Sharpe ~1,5–1,9, Profit Factor
~1,1–1,12, Max DD ~10 % — plausible Referenzwerte, keine Garantie (Details und
Quellen im Research-Dokument).

## Haftungsausschluss

Dies ist ein Forschungs- und Backtesting-Werkzeug, keine Anlageberatung. Vor
jedem Live-Einsatz: Demo-Forward-Test über mehrere Wochen, kleine
Positionsgrößen, eigenverantwortliche Prüfung.
