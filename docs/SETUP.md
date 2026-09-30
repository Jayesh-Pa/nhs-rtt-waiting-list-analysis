# Setup: from download to loaded database

Estimated time: 45–60 minutes the first time.

## 1. Download the data (10 min)

1. Open the NHS England RTT page for 2025-26:
   <https://www.england.nhs.uk/statistics/statistical-work-areas/rtt-waiting-times/rtt-data-2025-26/>
2. For each month **April 2025 to March 2026**, download **"Full CSV data file"** (a ZIP).
3. Unzip each one into this project's `data/` folder.
4. Rename the CSVs to `rtt_Apr25.csv`, `rtt_May25.csv`, … `rtt_Mar26.csv`.

> `data/` is listed in `.gitignore`, so the raw files never get pushed to GitHub.
> The repo tells people where to get the data instead.

## 2. Check the file layout (2 min) — important

Open **one** CSV in a text editor (not Excel, it's large) and look at the first line.
The load script expects this column order:

```
Period, Provider Parent Org Code, Provider Parent Name, Provider Org Code, Provider Org Name,
Commissioner Parent Org Code, Commissioner Parent Name, Commissioner Org Code, Commissioner Org Name,
RTT Part Type, RTT Part Description, Treatment Function Code, Treatment Function Name,
Gt 00 To 01 Weeks SUM 1, ... , Gt 103 To 104 Weeks SUM 1, Gt 104 Weeks SUM 1,
Total, Patients with unknown clock start date, Total All
```

That is 13 descriptive columns, 105 weekly bands, then 3 totals (121 columns).
The 2025-26 files were checked and match this layout exactly. If NHS England changes
the layout in future years, adjust the column list in `sql/02_load_data.sql`.

## 3. Allow MySQL to load local files (5 min)

In MySQL Workbench:

1. Run: `SET GLOBAL local_infile = 1;`
2. Edit your connection → **Advanced** tab → in **Others** add: `OPT_LOCAL_INFILE=1`
3. Reconnect.

## 4. Run the SQL scripts in order (20–30 min)

| Script | What it does | What to check |
|---|---|---|
| `sql/01_create_schema.sql` | Creates the `nhs_rtt` database and staging table | Runs without errors |
| `sql/02_load_data.sql` | Loads the 12 CSVs | First replace `{DATA_DIR}` with your data folder path (use `/` not `\`). The last query should show 12 files |
| `sql/03_clean_transform.sql` | Profiles the data, builds the star schema | Step 1c and Step 4 should return 0 mismatches. Expect about 43,248 rows in `fact_waiting_list` |
| `sql/04_analysis.sql` | Creates the views and answers Q1–Q8 | Read every result and note what surprises you |

**Tip:** in `02_load_data.sql`, use Workbench's Find & Replace (Ctrl+H) to replace
`{DATA_DIR}` in one go.

## 5. Export the views for Excel and Power BI (5 min)

For each view, run `SELECT * FROM <view>;` in Workbench, then click
**Export recordset** (the icon above the results grid) → CSV → save into `exports/`:

- `vw_monthly_england` → `exports/monthly_england.csv`
- `vw_specialty_month` → `exports/specialty_month.csv`
- `vw_provider_month` → `exports/provider_month.csv`

These exports are already in the repo, so Excel and Power BI work without re-running
the SQL. Then follow `docs/POWERBI_GUIDE.md`.
