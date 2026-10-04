# Power BI dashboard

File: `powerbi/nhs_rtt_dashboard.pbix` (one page, 1920 × 1080). Screenshot: `images/05_powerbi_dashboard.png`.
Theme: `powerbi/nhs_theme.json` (NHS colour palette, white cards on a light grey canvas).

## 1. Data model

| Table | Source | Notes |
|---|---|---|
| `Provider` | `exports/provider_month.csv` | Provider × month. Drives the KPIs, trends and league table. Names cleaned in Power Query; columns `Provider`, `ICB`, `Provider Type` |
| `Specialty` | `exports/specialty_month.csv` | Specialty × month (England level). Names shortened in Power Query |
| `Monthly` | `exports/monthly_england.csv` | England × month (reference) |
| `Dates` | DAX: `DISTINCT ( SELECTCOLUMNS ( Monthly, "Month", Monthly[month_start] ) )` | Disconnected table for the month slicer (format `mmmm yyyy`) |
| `KPI Measures` | DAX: `ROW ( "Placeholder", BLANK () )` | Holds the measures |

`Dates` is deliberately **not related** to the fact tables: the selected month is read
with `MAX ( Dates[Month] )` inside each KPI measure, so the trend charts keep showing all
12 months while the cards, specialty chart and league table follow the month slicer.
The ICB and Provider Type slicers filter the `Provider` table directly.

## 2. Measures

```DAX
-- Selected month
Waiting =
VAR m = MAX ( Dates[Month] )
RETURN CALCULATE ( SUM ( Provider[total_waiting] ), Provider[month_start] = m )

Pct 18w =
VAR m = MAX ( Dates[Month] )
RETURN DIVIDE (
    CALCULATE ( SUM ( Provider[within_18_wks] ), Provider[month_start] = m ),
    CALCULATE ( SUM ( Provider[known_start] ),   Provider[month_start] = m ) )

Over 52w =
VAR m = MAX ( Dates[Month] )
RETURN CALCULATE ( SUM ( Provider[over_52_wks] ), Provider[month_start] = m )

Gap to 92 =                                   -- patients short of the 92% standard
VAR m = MAX ( Dates[Month] )
RETURN CALCULATE ( 0.92 * SUM ( Provider[known_start] ) - SUM ( Provider[within_18_wks] ),
                   Provider[month_start] = m )

-- Baseline (April 2025): same logic with Provider[month_start] = DATE ( 2025, 4, 1 )
Waiting Apr25, Pct 18w Apr25, Over 52w Apr25, Gap to 92 Apr25

-- KPI card values (text, so the card shows full numbers)
Patients Waiting       = FORMAT ( [Waiting], "#,0" )
Waiting Under 18 Weeks = FORMAT ( [Pct 18w], "0.0%" )
Waiting Over 52 Weeks  = FORMAT ( [Over 52w], "#,0" )
Short of 92% Standard  = FORMAT ( [Gap to 92], "#,0" )

-- Trend labels under each KPI
Chg Waiting =
VAR d = DIVIDE ( [Waiting] - [Waiting Apr25], [Waiting Apr25] )
RETURN IF ( d <= 0, "▼ ", "▲ " ) & FORMAT ( ABS ( d ), "0.0%" ) & " vs Apr 2025"

Chg 18w =
VAR d = ( [Pct 18w] - [Pct 18w Apr25] ) * 100
RETURN IF ( d >= 0, "▲ ", "▼ " ) & FORMAT ( ABS ( d ), "0.0" ) & " pts vs Apr 2025"
-- Chg 52w, Chg Gap: same pattern as Chg Waiting

-- Colour of each trend label (conditional formatting > Field value)
Col Waiting = IF ( [Waiting] <= [Waiting Apr25], "#007F3B", "#DA291C" )
-- Col 18w (>=), Col 52w, Col Gap: same pattern

-- Trend charts (respond to ICB / provider type, all months)
Trend Waiting = SUM ( Provider[total_waiting] )
Trend Pct 18w = DIVIDE ( SUM ( Provider[within_18_wks] ), SUM ( Provider[known_start] ) )

-- League table and specialty chart
Total Waiting    = [Waiting]
% Under 18 Weeks = [Pct 18w]
52+ Week Waits   = [Over 52w]
Specialty 52+ Week Waits =
VAR m = MAX ( Dates[Month] )
RETURN CALCULATE ( SUM ( Specialty[over_52_wks] ), Specialty[month_start] = m )
```

## 3. Layout

| Area | Visual | Features |
|---|---|---|
| Header | Rectangle with title/subtitle | Month (single-select dropdown), ICB and Provider Type slicers |
| KPI row | Card (new), 4 values | Reference labels show change vs April 2025, green/red via `Col` measures |
| Trends | 2 line charts | `Provider[month_start]` axis; 65% interim ambition as a Y-axis constant line |
| Specialties | Clustered bar | Year-long waits, data labels |
| League table | Table | Filters: Provider Type = NHS trust, Total Waiting ≥ 20,000; data bars on % Under 18 Weeks; gradient on 52+ Week Waits |

## 4. Numbers to check against (March 2026, no ICB filter)

- Patients waiting: 7,045,510 (▼ 5.1% vs April 2025)
- Waiting under 18 weeks: 65.2% (▲ 5.5 pts)
- Waiting over 52 weeks: 95,824 (▼ 50.2%)
- Patients short of 92% standard: 1,885,247
- Top NHS trust (20,000+ waiting): Moorfields Eye Hospital, 85.8%
