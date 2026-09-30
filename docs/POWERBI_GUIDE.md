# Power BI: 3-page dashboard

Save as `powerbi/nhs_rtt_dashboard.pbix`. Estimated time: 2–3 hours.

The data is already prepared: the three CSVs in `exports/` come from the SQL views.
`provider_month.csv` also has a `provider_type` column (NHS trust vs independent sector).

## 1. Load the data

**Get Data → Text/CSV** and load the three files from `exports/`:
`monthly_england.csv`, `specialty_month.csv`, `provider_month.csv`.

In Power Query, check that `month_start` is type **Date** and all counts are
**Whole Number**. Rename the queries to `Monthly`, `Specialty`, `Provider`.

Create a date table (**Modeling → New table**):

```DAX
Calendar =
ADDCOLUMNS (
    CALENDAR ( DATE ( 2025, 4, 1 ), DATE ( 2026, 3, 31 ) ),
    "Month", FORMAT ( [Date], "mmm yyyy" ),
    "MonthSort", YEAR ( [Date] ) * 100 + MONTH ( [Date] )
)
```

Sort `Month` by `MonthSort`. Relate `Calendar[Date]` to `month_start` in all three tables.

## 2. Measures (create a blank table called `_Measures` to hold them)

```DAX
Total Waiting = SUM ( Provider[total_waiting] )

Within 18 Weeks = SUM ( Provider[within_18_wks] )

Known Start = SUM ( Provider[known_start] )

% Within 18 Weeks = DIVIDE ( [Within 18 Weeks], [Known Start] )

Gap to 92% = 0.92 - [% Within 18 Weeks]

52+ Week Waiters = SUM ( Provider[over_52_wks] )

Waiting Prev Month =
CALCULATE ( [Total Waiting], DATEADD ( Calendar[Date], -1, MONTH ) )

MoM Change = [Total Waiting] - [Waiting Prev Month]

Latest Month Waiting =
VAR LastDate = MAX ( Provider[month_start] )
RETURN CALCULATE ( [Total Waiting], Provider[month_start] = LastDate )
```

Format `% Within 18 Weeks` and `Gap to 92%` as percentages with 1 decimal place.

## 3. Page 1 — Overview

- Four **cards**: Total Waiting, % Within 18 Weeks, 52+ Week Waiters, MoM Change
- **Line chart**: Total Waiting by Calendar[Month]
- **Line chart**: % Within 18 Weeks by month, with a **constant line at 92%**
  (Analytics pane → Constant line) labelled "Constitutional standard"
- **Slicer**: Month

## 4. Page 2 — Specialties

- **Bar chart**: total waiting by `treatment_function_name` (latest month, sorted)
- **Bar chart**: 52+ week waiters by specialty
- **Matrix**: specialty × month, values = % within 18 weeks, with conditional
  formatting (background colour scale, red under 92%)

## 5. Page 3 — Hospital trusts

- **Table**: provider_name, provider_parent_name, Total Waiting, % Within 18 Weeks,
  52+ Week Waiters. Add a visual-level filter: Total Waiting ≥ 1,000.
  Conditional formatting (icons or data bars) on % Within 18 Weeks.
- **Bar chart**: % Within 18 Weeks by provider_parent_name
- **Slicer**: provider_parent_name (ICB)
- **Slicer**: provider_type, so viewers can compare NHS trusts only

## 6. Polish

- One colour theme (View → Themes), one accent colour for "bad vs target"
- Title on every page and a short subtitle saying what the page answers
- Text box footer: "Source: NHS England RTT Waiting Times, Apr 2025 – Mar 2026"

## Numbers to sanity-check your dashboard against (March 2026)

- Total waiting: 7,045,510
- % within 18 weeks: 65.2%
- 52+ week waiters: 95,824
- Trauma & Orthopaedics waiting: 826,172

If your cards show different numbers, check the relationships and the month filter.

## 7. Screenshots for GitHub and LinkedIn

Export each page (**File → Export → Export to PDF**, or Windows **Snipping Tool**)
and save as `images/dashboard_overview.png`, `images/dashboard_specialties.png`,
`images/dashboard_trusts.png`.
