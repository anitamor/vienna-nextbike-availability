# Vienna bike-share availability (WienMobil Rad / nextbike, GBFS)
#
# PART 1 (exploration) is the code of my teammate: it looks at the website and
# at the API, and builds the table bike_data.
# PART 2 (automation) checks the data and saves it. It runs every 15 minutes
# in GitHub Actions:  Rscript update_data.R

# ===========================================================================
# PART 1: exploration (teammate)
# ===========================================================================
# install.packages("jsonlite")   # installed by the GitHub workflow, not needed here
library(jsonlite)
api_url <- "https://gbfs.nextbike.net/maps/gbfs/v2/nextbike_wr/gbfs.json"

api_data <- jsonlite::fromJSON(api_url)

names(api_data$data$en)

api_data$data$en$feeds



# Get the current status of all bike stations
status_url <- "https://gbfs.nextbike.net/maps/gbfs/v2/nextbike_wr/en/station_status.json"

status_data <- jsonlite::fromJSON(status_url)

# See what information is available
names(status_data$data)

# Look at the first few stations
head(status_data$data$stations)

# Display only the most useful information
head(status_data$data$stations[
  , c("station_id",
      "num_bikes_available",
      "num_docks_available")
])


# Get information about all bike stations
info_url <- "https://gbfs.nextbike.net/maps/gbfs/v2/nextbike_wr/en/station_information.json"

info_data <- jsonlite::fromJSON(info_url)

# Check which columns are available
names(info_data$data$stations)

# Display the first six stations
head(info_data$data$stations)


# Give the two tables shorter names
bike_status <- status_data$data$stations
station_info <- info_data$data$stations

# Combine them using the shared station ID
bike_data <- merge(
  station_info,
  bike_status,
  by = "station_id"
)

# Display the result
head(bike_data[, c(
  "station_id",
  "name",
  "lat",
  "lon",
  "num_bikes_available",
  "num_docks_available"
)])


head(bike_data)


# ===========================================================================
# PART 2: automation (check, log, save)
# ===========================================================================

library(tidyverse)

snapshots_file <- "data/snapshots.csv"
log_file <- "data/check_log.csv"
dir.create("data", showWarnings = FALSE)

# Time of this run, written as text in UTC
run_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S+00:00", tz = "UTC")

# bike_data (from part 1) is the joined table of all stations. Add the two
# time columns and keep the columns that go into the dataset.
snapshot <- bike_data %>%
  mutate(
    collected_at_utc = run_at,
    feed_last_updated_utc = format(as_datetime(status_data$last_updated),
                                   "%Y-%m-%dT%H:%M:%S+00:00")
  ) %>%
  select(
    collected_at_utc, feed_last_updated_utc, station_id, name, lat, lon,
    capacity,
    bikes_available = num_bikes_available,
    docks_available = num_docks_available,
    is_renting, is_returning
  )

# Did it work? Each check is TRUE (passed) or FALSE (failed)
feed_age <- as.numeric(Sys.time()) - status_data$last_updated

checks <- c(
  station_count = nrow(snapshot) >= 100,
  feed_fresh = isTRUE(feed_age <= 30 * 60),
  bikes_valid = isTRUE(all(snapshot$bikes_available >= 0)),
  no_duplicate_ids = anyDuplicated(snapshot$station_id) == 0,
  coords_in_vienna = isTRUE(all(
    snapshot$lat >= 48.10 & snapshot$lat <= 48.35 &
      snapshot$lon >= 16.15 & snapshot$lon <= 16.65
  ))
)

failed_checks <- names(checks)[!checks]

check_log <- tibble(
  run_at_utc = run_at,
  overall = if_else(length(failed_checks) == 0, "PASS", "FAIL"),
  feed_url = status_url,
  stations = nrow(snapshot),
  feed_age_s = round(feed_age),
  failed_checks = paste(failed_checks, collapse = ";"),
  details = paste(names(checks), checks, sep = ": ", collapse = " | ")
)

# Save: only good data goes into the dataset, every run goes into the log
if (length(failed_checks) == 0) {
  write_csv(snapshot, snapshots_file, append = file.exists(snapshots_file))
}
write_csv(check_log, log_file, append = file.exists(log_file))

cat(check_log$overall, run_at, "stations:", check_log$stations, "\n")

# Exit code 1 lets the scheduler see that the run failed
if (length(failed_checks) > 0) quit(status = 1)
