# Vienna Bike-Share Availability

An automated workflow that collects live availability data of the Vienna bike-share system **WienMobil Rad** (operated by nextbike), checks every run whether the collection succeeded, and analyses where and when stations run out of bikes.

This is a student project for the course *Data Science and Machine learning* at the Vienna University of Economics and Business, part of the Master's in Economics (assignment: *Workflow Automation*). The full walk-through of the code is in [`assignment.qmd`](assignment.qmd).

## Idea

Bike-share users may arrive at a station only to find that no bikes are available. This project investigates which stations in Vienna are most frequently empty and at what times of day. Answering these questions requires collecting data at regular intervals over several days. Since bike availability changes continuously, manual data collection would be impractical. To address this, the project implements an automated workflow for data collection, validation, and storage.

```
nextbike API --> R script (update_data.R) --> checks --> data/snapshots.csv
                                                  \----> data/check_log.csv

GitHub Actions starts the script on a schedule and saves the new rows in this repository.
```

1. **Download.** The script reads the public GBFS feeds of the system `nextbike_wr` (station information and station status) and joins them into one table with one row per station.
2. **Check.** Five checks test whether the data looks right (see below).
3. **Save.** If all checks pass, the stations are appended to `data/snapshots.csv`. Every run, passed or failed, adds one row to `data/check_log.csv`.
4. **Schedule.** A GitHub Actions workflow runs the script every 15 minutes and commits the new rows back to the repository, so nobody's computer has to stay switched on.
5. **Analyse.** `visualisations.R` creates charts and a map from the collected data.

## Files

| File | Purpose |
|---|---|
| `update_data.R` | The script that is scheduled: download, check, save |
| `.github/workflows/collect.yml` | GitHub Actions workflow that runs the script on a schedule |
| `visualisations.R` | Charts and map from the collected data |
| `assignment.qmd` | Quarto report that explains the project and shows the results |
| `images/` | Screenshots of the data files used in the report |
| `data/snapshots.csv` | One row per station per run (only runs that passed all checks) |
| `data/check_log.csv` | One row per run: PASS or FAIL and why |

## Data

Data collection started on 24 October 2026 and ended on 29 October 2026.

**`data/snapshots.csv`**

| Column | Meaning |
|---|---|
| `collected_at_utc` | Time of the run (UTC) |
| `feed_last_updated_utc` | Time when nextbike last updated the feed (UTC) |
| `station_id`, `name`, `lat`, `lon` | Station identifier, name and position |
| `capacity` | Capacity of the station (as reported by the feed, not always reliable) |
| `bikes_available`, `docks_available` | Bikes that can be rented and free docks |
| `is_renting`, `is_returning` | Whether the station currently allows renting and returning |

**`data/check_log.csv`**

| Column | Meaning |
|---|---|
| `run_at_utc` | Time of the run (UTC) |
| `overall` | `PASS` or `FAIL` |
| `feed_url` | Feed address that was checked |
| `stations` | Number of stations in the run |
| `feed_age_s` | Age of the feed in seconds when the script ran |
| `failed_checks` | Names of the failed checks, separated by `;` |
| `details` | Result of every check |

All times are in UTC. The analysis converts them to Vienna time.

## The success checks

After each download the script tests the content of the data, not only whether the server answered:

| Check | Rule | Protects against |
|---|---|---|
| `station_count` | at least 100 stations (Vienna has around 240) | an empty or cut-off answer |
| `feed_fresh` | feed not older than 30 minutes | the server answering with old data |
| `bikes_valid` | no missing or negative bike counts | missing or impossible values |
| `no_duplicate_ids` | every station appears once | a broken join |
| `coords_in_vienna` | all stations inside a box around Vienna | wrong coordinates |

If a check fails, the data of that run is **not** saved, the failure is written to `check_log.csv`, and the script ends with exit code 1, so the run is shown with a red cross in the GitHub Actions tab.

## Running it yourself

You need R and the packages `tidyverse`, `jsonlite`, `rvest`, `leaflet` and `htmlwidgets`:

```r
install.packages(c("tidyverse", "jsonlite", "rvest", "leaflet", "htmlwidgets"))
```

From the project folder:

```
Rscript update_data.R    # one collection run: adds rows to data/
Rscript visualisations.R   # creates charts and the map in output/
```

The analysis writes `output/bike_availability_by_hour.png`, `output/weekday_weekend_availability.png` and `output/empty_stations_map.html`. Keep the folder `empty_stations_map_files` next to the HTML file. To render the report, use `quarto render assignment.qmd`.

Note: the scheduled workflow commits to the `data/` folder. If you run `update_data.R` on your own computer, do not push the changed data files, because they could conflict with the commits of the workflow.

## Limitations

- The data covers only a limited period, so patterns by hour are rough, and there is little weekend data.
- A station counts as *empty* only if it has exactly zero bikes at the moment of the snapshot. Shorter gaps between two snapshots are not seen.
- GitHub starts scheduled runs late and sometimes skips them. The workflow is set to run every 15 minutes, but in practice the runs came about every 40 minutes.
- Some runs failed when saving, because two commits were pushed at the same time and the CSV files could not be merged. The snapshot of such a run is lost, and such failures do not appear in `check_log.csv`. They are only visible as red runs in the GitHub Actions tab.
- The checks test whether the data is plausible, not whether it is exactly right.
- The `capacity` values of the feed are not reliable (many stations report more bikes than their capacity), so the analysis looks at empty stations only.

## Data sources and credits

- Station data: accessed through the public API (GBFS feed) of WienMobil Rad / nextbike (system `nextbike_wr`), which is listed in the [MobilityData catalogue of GBFS systems](https://github.com/MobilityData/gbfs/blob/master/systems.csv). The data is downloaded from R with `fromJSON()` (package `jsonlite`), and the API needs no key.
- Map background: Esri World Gray Canvas, shown through the R package `leaflet`.
- This project is not affiliated with Wiener Linien or nextbike. The data belongs to its publishers and is used here for a course assignment.

## Authors

Anita Mor, Paul Boissot and Peter Sparks
