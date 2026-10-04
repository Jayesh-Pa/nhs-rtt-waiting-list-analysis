# Power BI dashboard

File: `powerbi/nhs_rtt_dashboard.pbix` (one page). Screenshot: `images/05_powerbi_dashboard.png`.

## 1. Data

Three queries, each loaded from `exports/` with **Get Data → Blank query → Advanced Editor**:

| Query | Source | Cleaning in Power Query |
|---|---|---|
| `Monthly` | `monthly_england.csv` | Typed columns (locale en-GB) |
| `Specialty` | `specialty_month.csv` | Trailing " Service" removed; T&O and ENT renamed; column renamed `Specialty` |
| `Provider` | `provider_month.csv` | Names in proper case (NHS kept upper case); ICB names shortened; columns renamed `Provider`, `ICB`, `Provider Type` |

Simplified example (Provider, before the renaming and name-cleaning steps):

```m
let
    Source = Csv.Document(File.Contents("...\exports\provider_month.csv"), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed = Table.TransformColumnTypes(Promoted, {{"month_start", type date}, {"total_waiting", Int64.Type},
        {"known_start", Int64.Type}, {"within_18_wks", Int64.Type}, {"over_52_wks", Int64.Type}}, "en-GB")
in
    Typed
```

The three tables are not related. Each measure picks the latest month in its own table,
so the KPIs always show March 2026.

## 2. Measures (home table `Monthly`)

```DAX
Waiting List =
VAR m = MAX ( Monthly[month_start] )
RETURN CALCULATE ( SUM ( Monthly[total_waiting] ), Monthly[month_start] = m )

% Within 18 Weeks =
VAR m = MAX ( Monthly[month_start] )
RETURN DIVIDE (
    CALCULATE ( SUM ( Monthly[within_18_wks] ), Monthly[month_start] = m ),
    CALCULATE ( SUM ( Monthly[known_start] ),   Monthly[month_start] = m ) )

52+ Week Waiters =
VAR m = MAX ( Monthly[month_start] )
RETURN CALCULATE ( SUM ( Monthly[over_52_wks] ), Monthly[month_start] = m )

Specialty 52+ Week Waits =
VAR m = CALCULATE ( MAX ( Specialty[month_start] ), ALL ( Specialty ) )
RETURN CALCULATE ( SUM ( Specialty[over_52_wks] ), Specialty[month_start] = m )

Trust Waiting / Trust % Within 18 Weeks / Trust 52+ Week Waiters
    -- same latest-month pattern on the Provider table

Patients Waiting      = FORMAT ( [Waiting List], "#,0" )       -- card labels, full numbers
Waiting Over 52 Weeks = FORMAT ( [52+ Week Waiters], "#,0" )
```

Percentages are formatted `0.0%`. The file's format locale is English (United Kingdom).

## 3. Layout

| Visual | Fields | Notes |
|---|---|---|
| Card (3 values) | Patients Waiting, Waiting Over 52 Weeks, % Within 18 Weeks | Title = page title, subtitle = source |
| Line chart | `Monthly[month_start]` × Waiting List | Raw date, not the date hierarchy |
| Line chart | `Monthly[month_start]` × % Within 18 Weeks | Y-axis constant line at 65% ("Interim ambition 65%") |
| Clustered bar | `Specialty[Specialty]` × Specialty 52+ Week Waits | Sorted descending |
| Table | Provider, Trust Waiting, Trust % Within 18 Weeks, Trust 52+ Week Waiters | Filters: Provider Type = NHS trust, Trust Waiting ≥ 20,000; sorted by % descending |

## 4. Numbers to check against (March 2026)

- Patients waiting: 7,045,510
- % within 18 weeks: 65.2%
- 52+ week waiters: 95,824
- Top NHS trust (20,000+ waiting): Moorfields Eye Hospital, 85.8%
