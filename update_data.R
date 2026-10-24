# Vienna bike-share availability (WienMobil Rad / nextbike, GBFS)
#
# Each run:
#   1. GET the station information and station status feeds
#   2. Check if the data looks right
#   3. Append one row per station to data/snapshots.csv (only if all checks pass) # nolint
#   4. Append one row per run to data/check_log.csv (PASS or FAIL)
#
# Run from the project folder:  Rscript update_data.R

library(tidyverse)
library(httr)
library(glue)
q
# Settings ----------------------------------------------------------------

# The first URL that works is used. Find the current address of the system
# "nextbike_wr" in https://github.com/MobilityData/gbfs/blob/master/systems.csv
gbfs_urls <- c(
  "https://api.nextbike.net/maps/gbfs/v1/nextbike_wr/gbfs.json",
  "https://gbfs.nextbike.net/maps/gbfs/v2/nextbike_wr/gbfs.json"
)

data_dir <- "data"
min_stations <- 100        # Vienna has around 240 stations
max_age_seconds <- 30 * 60 # feed should not be older than 30 minutes
lat_range <- c(48.10, 48.35)
lon_range <- c(16.15, 16.65)

dir.create(data_dir, showWarnings = FALSE)

# Helper functions --------------------------------------------------------

iso_utc <- function(x) {
  format(as.POSIXct(x, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%S+00:00")
}

value_or_na <- function(x) {
  if (is.null(x)) NA else x
}

get_json <- function(url) {
  response <- GET(url, user_agent("uni-data-science-project"), timeout(20))
  if (status_code(response) != 200) {
    stop(glue("HTTP status {status_code(response)} for {url}"))
  }
  content(response, as = "parsed", type = "application/json")
}

# GBFS: v1/v2 list the feeds under data$<language>$feeds, v3 under data$feeds
get_feed_urls <- function(gbfs) {
  feeds <- gbfs$data$feeds
  if (is.null(feeds)) {
    language <- if ("en" %in% names(gbfs$data)) "en" else names(gbfs$data)[1]
    feeds <- gbfs$data[[language]]$feeds
  }
  setNames(map_chr(feeds, "url"), map_chr(feeds, "name"))
}

append_csv <- function(data, path) {
  write_csv(data, path, append = file.exists(path))
}

# 1. Get the data ---------------------------------------------------------

run_at <- iso_utc(Sys.time())
fetched <- NULL
errors <- character()

for (url in gbfs_urls) {
  fetched <- tryCatch({
    feed_urls <- get_feed_urls(get_json(url))
    list(
      url = url,
      info = get_json(feed_urls[["station_information"]]),
      status = get_json(feed_urls[["station_status"]])
    )
  }, error = function(e) {
    errors <<- c(errors, paste0(url, ": ", conditionMessage(e)))
    NULL
  })
  if (!is.null(fetched)) break
}

# If nothing could be downloaded, log the failure and stop
if (is.null(fetched)) {
  check_log <- tibble(
    run_at_utc = run_at,
    overall = "FAIL",
    feed_url = "",
    stations = 0,
    feed_age_s = NA_real_,
    failed_checks = "fetch_or_parse",
    details = paste(errors, collapse = " | ")
  )
  append_csv(check_log, file.path(data_dir, "check_log.csv"))
  cat(glue("[FAIL] {run_at} could not download the feed\n"))
  quit(status = 1)
}

# 2. Put it in a data frame -----------------------------------------------

station_info <- map_dfr(fetched$info$data$stations, function(s) {
  tibble(
    station_id = as.character(s$station_id),
    name = as.character(value_or_na(s$name)),
    lat = as.numeric(value_or_na(s$lat)),
    lon = as.numeric(value_or_na(s$lon)),
    capacity = as.numeric(value_or_na(s$capacity))
  )
})

station_status <- map_dfr(fetched$status$data$stations, function(s) {
  tibble(
    station_id = as.character(s$station_id),
    bikes_available = as.numeric(value_or_na(s$num_bikes_available)),
    docks_available = as.numeric(value_or_na(s$num_docks_available)),
    is_renting = as.logical(value_or_na(s$is_renting)),
    is_returning = as.logical(value_or_na(s$is_returning))
  )
})

feed_last_updated <- as.numeric(value_or_na(fetched$status$last_updated))

snapshot <- station_status %>%
  inner_join(station_info, by = "station_id") %>%
  mutate(
    collected_at_utc = run_at,
    feed_last_updated_utc = iso_utc(feed_last_updated)
  ) %>%
  select(
    collected_at_utc, feed_last_updated_utc, station_id, name, lat, lon,
    capacity, bikes_available, docks_available, is_renting, is_returning
  )

# 3. Did it work? ---------------------------------------------------------

n_stations <- nrow(snapshot)
join_share <- n_stations / nrow(station_status)
feed_age <- as.numeric(Sys.time()) - feed_last_updated

n_negative <- sum(is.na(snapshot$bikes_available) | snapshot$bikes_available < 0)
n_over_capacity <- sum(
  !is.na(snapshot$capacity) & snapshot$capacity > 0 &
    snapshot$bikes_available > snapshot$capacity,
  na.rm = TRUE
)

n_extreme <- sum(
  !is.na(snapshot$capacity) & snapshot$capacity > 0 &
    snapshot$bikes_available > 2 * snapshot$capacity,
  na.rm = TRUE
)

n_outside <- sum(
  is.na(snapshot$lat) | is.na(snapshot$lon) |
    snapshot$lat < lat_range[1] | snapshot$lat > lat_range[2] |
    snapshot$lon < lon_range[1] | snapshot$lon > lon_range[2]
)
total_bikes <- sum(snapshot$bikes_available, na.rm = TRUE)

checks <- tribble(
  ~check, ~passed, ~detail,
  "station_count", n_stations >= min_stations,
    glue("{n_stations} stations (min {min_stations})"),
  "info_status_join", join_share >= 0.95,
    glue("{round(join_share * 100, 1)}% of status rows matched station info"),
  "feed_fresh", isTRUE(feed_age <= max_age_seconds),
    glue("feed age {round(feed_age)}s (max {max_age_seconds}s)"),
  "bikes_non_negative", n_negative == 0,
    glue("{n_negative} invalid bike counts"),
 "bikes_plausible", n_extreme <= 0.05 * max(n_stations, 1),
    glue("{n_extreme} stations with more than 2x their capacity ",
         "({n_over_capacity} above capacity, tolerated)"),
  "coords_in_vienna", n_outside <= 0.02 * max(n_stations, 1),
    glue("{n_outside} stations outside Vienna"),
  "not_all_zero", total_bikes > 0,
    glue("{total_bikes} bikes available in total")
) %>%
  mutate(detail = as.character(detail))

failed_checks <- checks %>%
  filter(!passed) %>%
  pull(check)

check_log <- tibble(
  run_at_utc = run_at,
  overall = if_else(length(failed_checks) == 0, "PASS", "FAIL"),
  feed_url = fetched$url,
  stations = n_stations,
  feed_age_s = round(feed_age),
  failed_checks = paste(failed_checks, collapse = ";"),
  details = paste(checks$check, checks$detail, sep = ": ", collapse = " | ")
)

# 4. Save -----------------------------------------------------------------

# Only good data goes into the dataset, every run goes into the log
if (length(failed_checks) == 0) {
  append_csv(snapshot, file.path(data_dir, "snapshots.csv"))
}
append_csv(check_log, file.path(data_dir, "check_log.csv"))

cat(glue("[{check_log$overall}] {run_at} stations={n_stations} ",
         "failed={if (length(failed_checks) == 0) '-' else check_log$failed_checks}\n"))

# Exit code 1 lets a scheduler see that the run failed
if (length(failed_checks) > 0) quit(status = 1)
