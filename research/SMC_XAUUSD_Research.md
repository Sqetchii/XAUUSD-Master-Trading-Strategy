# Research: Smart Money Concepts (SMC) für XAUUSD

Stand: September 2026. Dieses Dokument fasst zusammen, was bei der Recherche zu
"bewährten" SMC-Strategien für Gold (XAUUSD) tatsächlich an Evidenz existiert,
was reine Marketing-Behauptungen sind, und wie die daraus abgeleitete Strategie
in diesem Repo aufgebaut ist.

## 1. Ehrliches Fazit zuerst

**Es gibt keine seriöse, unabhängige akademische Bestätigung, dass "reine" SMC-
Konzepte (Order Blocks, Fair Value Gaps, Change of Character) für sich genommen
einen statistisch signifikanten Edge liefern.** Die gründlichste öffentlich
verfügbare Studie dazu (StatOasis, "I Backtested ICT / Smart Money Concepts —
What Survives") hat vier ICT-Kernkonzepte (Order Block, Fair Value Gap,
Liquidity Sweep, Optimal Trade Entry) mechanisch codiert und auf SPY/QQQ/DIA/IWM
(Tagesdaten, 1993–2026) getestet:

- Von 32 gemessenen t-Statistiken (Forward-Return-Edge über 5/10 Tage) hat
  **genau eine** die Signifikanzschwelle (t > 2) überschritten.
- Von 648 Backtests (7 Entry-Familien × Parametervarianten × 3 Exit-Horizonte ×
  4 Märkte) hat **null** Buy-and-Hold auf Netto-Gewinn geschlagen.
- Order Blocks waren innerhalb der SMC-Familie am konsistentesten (schlugen in
  55–82 % der Varianten eine zufällige Einstiegs-Baseline), aber kein Ansatz
  hielt seinen Rang über alle vier Märkte, und keiner erfüllte gleichzeitig
  "schlägt Buy&Hold" UND "schlägt Zufalls-Entry" auf allen vier Märkten.
- Fazit der Studie wörtlich: *"Mechanical ICT on daily bars is a middling entry
  system wearing an extraordinary story."*

Das heißt nicht, dass SMC nutzlos ist — es heißt, dass die dramatisierte
"Institutionen jagen gezielt deine Stop-Losses"-Erzählung nicht die Grundlage
für einen verifizierten Edge ist. Was tatsächlich real ist:

- **Stop-Order-Clustering an runden Zahlen und offensichtlichen Swing-Levels
  ist real** und Preis sweept diese Level nachweislich häufig.
- **Session-/Zeitfenster-Volatilitätsmuster ("Killzones") gehören zu den am
  meisten replizierten Befunden** in der Marktmikrostruktur-Literatur — London-
  Open und der London/NY-Overlap haben für Gold nachweislich überdurchschnittliche
  Range-Expansion.
- **Signed Order Imbalance bewegt Preise** — das ist die seriöse, akademisch
  anerkannte Version dessen, was FVGs informell beschreiben.
- Order Blocks funktionieren im Kern wie klassische Support/Resistance-Zonen,
  nicht wie ein eigenständiges neues Phänomen.

**"Kein Drawdown" ist bei keiner real handelbaren Strategie erreichbar.** Jede
Strategie mit positivem Erwartungswert hat Verlustserien; das Ziel ist, den
Drawdown durch striktes Risikomanagement zu **begrenzen**, nicht zu eliminieren.

## 2. Was reale, reproduzierbare XAUUSD-SMC-Systeme tatsächlich liefern

Zwei öffentlich dokumentierte, vollständig regelbasierte SMC-EAs für XAUUSD
liefern konkrete, nachvollziehbare Zahlen (aus Marketplace-/GitHub-Beschreibungen,
nicht unabhängig verifiziert — als Anhaltspunkt, nicht als Wahrheit zu behandeln):

| System | Zeitraum | Trades | Win-Rate | Profit Factor | Max DD | Sharpe |
|---|---|---|---|---|---|---|
| "SMC Gold: Liquidity Sweep + Order Block EA" (M15) | 2025 (Vollj.) | 175 | 36,6 % | 1,12 | 10,5 % | 1,90 |
| dasselbe System | Jan–Sep 2026 | 127 | 37,0 % | 1,10 | 10,6 % | 1,56 |
| "FvgGold-EA" (FVG + OB, quality-scored) | 6 Monate 2026 | 64 | 45,3 % | – | – | – |
| dasselbe System | 3 Monate 2026 | 35 | 40,0 % | – | – | – |

Wichtige Einordnung:

- Das erste System ist strukturell fast identisch mit dem, was hier
  implementiert wurde: Swing-Erkennung → Liquidity Sweep (Wick über Swing +
  ATR-Puffer, Close zurück innerhalb) → Order Block = Sweep-Kerzenkörper → H1-
  EMA-Trendfilter → Bestätigungs-Close innerhalb weniger Kerzen → Entry at
  Market, SL 0,1×ATR jenseits des Sweep-Wicks, TP bei 2:1. Die Kennzahlen
  (Sharpe ~1,6–1,9, PF ~1,1, DD ~10 %) sind **plausibel und realistisch** für
  ein mechanisches SMC-System mit sauberem Risikomanagement — aber der Edge ist
  klein: Bei ~1,9× Average-Win-zu-Average-Loss-Verhältnis reicht schon eine
  Win-Rate knapp über 34–35 %, damit die Strategie nicht verliert. Das ist eine
  dünne Marge, die durch Spread/Slippage/Requotes leicht aufgezehrt werden kann.
- Das zweite System zeigt deutlich höhere kurzfristige Renditen, aber auf Basis
  von nur 35–64 Trades über wenige Monate — statistisch nicht aussagekräftig
  genug, um daraus einen "bewährten" Edge abzuleiten (Overfitting-Risiko hoch).
- Keine der beiden Quellen ist eine unabhängig geprüfte, aus echten Tick-Daten
  mit realistischem Spread/Slippage erzeugte Zahl. Sie sind Ausgangspunkt, kein
  Beweis.

## 3. Warum diese Bausteine für die hier gebaute Strategie gewählt wurden

Die implementierte Strategie (`MQL5/Experts/SMC_XAUUSD_EA.mq5`) kombiniert die
Elemente mit der besten verfügbaren Evidenz, statt naiv "reines SMC" 1:1
umzusetzen:

1. **Liquidity Sweep als Trigger** (real: Stop-Clustering existiert) statt
   bloßes "Order Block antesten" ohne Sweep-Bestätigung.
2. **Momentum-Bestätigung nach dem Sweep** (Mindest-Range in ATR), um reine
   Lärm-Wicks ohne Displacement herauszufiltern — genau der Punkt, an dem die
   StatOasis-Studie zeigt, dass naive OB-Reentries kaum Edge haben.
3. **HTF-Trendfilter (H1-EMA50)**, weil gegen-den-Trend-Reversal-Trades in
   praktisch jeder Backtest-Literatur eine schlechtere Trefferquote haben als
   Trend-Continuation-Setups.
4. **Session-/Killzone-Filter (London-Open, London/NY-Overlap)**, weil dies der
   am besten belegte Baustein überhaupt ist — außerhalb dieser Fenster ist
   XAUUSD-Volatilität strukturell geringer und Spreads relativ höher.
5. **Premium/Discount-Filter (Equilibrium der aktiven Swing-Range)** als
   zusätzlicher, optionaler Konfluenzfaktor — schwächer belegt, deshalb
   standardmäßig aktiv, aber leicht per Input abschaltbar, damit du seinen
   eigenständigen Beitrag im Optimizer separat testen kannst.
6. **FVG als optionale, nicht verpflichtende Konfluenz** — die Studienlage für
   FVGs allein ist am schwächsten (t-Stat nahe 0 in der SPY-Untersuchung),
   daher standardmäßig deaktiviert (`InpRequireFVG = false`), aber im Code
   vorhanden, damit du selbst testen kannst, ob sie in deinem Datensatz filtert
   oder nur Trades kostet.
7. **Festes R:R (Default 2:1) statt diskretionärer Zielsetzung**, damit die
   Strategie im Strategy Tester überhaupt objektiv reproduzierbar ist —
   diskretionäre SMC-Trades lassen sich per Definition nicht fair backtesten.
8. **Striktes Risikomanagement** (1 % Risiko/Trade, Tagesverlustlimit,
   Cooldown nach Verlustserie, max. Trades/Tag, kein Martingale/Grid) als
   Hauptinstrument gegen übermäßigen Drawdown — nicht die Signal-Logik selbst.

## 4. Realistische Erwartungshaltung

- Erwarte **keinen** garantierten Edge. Die Aufgabe dieses Repos ist, dir ein
  sauberes, reproduzierbares Werkzeug zu geben, um die Strategie **selbst** mit
  echten Tick-Daten zu verifizieren — nicht, dir eine fertig bewiesene
  Gewinnstrategie zu liefern, die es laut Studienlage in dieser Form nicht gibt.
- Realistische Zielgrößen, an denen du deine eigenen Backtest-Resultate messen
  solltest: Profit Factor > 1,2, Sharpe Ratio > 1,0 (annualisiert, aus dem MT5-
  Report), Max Drawdown < 15–20 %, mindestens 100+ Trades über mindestens 2–3
  Jahre Daten, damit die Statistik überhaupt aussagekräftig ist.
- Siehe `docs/Backtesting_Guide.md` für Walk-Forward-, Out-of-Sample- und
  Monte-Carlo-Validierung, damit du nicht auf ein überoptimiertes
  Parameter-Set hereinfällst.

## 5. Quellen (Auswahl, abgerufen September 2026)

- StatOasis: [I Backtested ICT / Smart Money Concepts — What Survives](https://statoasis.com/overfit/research/ict-backtest-what-survives)
- GitHub: [foeed/FvgGold-EA](https://github.com/foeed/FvgGold-EA)
- MQL5 Code Base: ["SMC Gold: Liquidity Sweep and Order Block EA for XAUUSD M15"](https://www.mql5.com/en/code/77639)
- FXNX: [Master XAUUSD Liquidity Sweep Strategies](https://fxnx.com/en/blog/master-xauusd-liquidity-sweep-strategies-stop-being-fuel)
- FXNX: [ICT Killzones: Master XAUUSD Timing](https://fxnx.com/en/blog/ict-killzones-master-xauusd-timing-maximum-profit)
- Medium/FXM Brand: [The Ultimate Step-by-Step Guide to Day Trading Gold with SMC](https://medium.com/forex-champs/the-ultimate-step-by-step-guide-to-day-trading-gold-xau-usd-with-smart-money-concepts-smc-1dcc69fce514)
- AlgoStorm: [ICT & SMC Truth: Evidence-Based Trading Review](https://algostorm.com/ict-smc-realistic-overview/)
