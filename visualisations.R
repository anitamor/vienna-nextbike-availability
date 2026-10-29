# Analysis of the collected bike-share data
# Output (folder output/): a map of the stations that are most often empty,
# and two charts of empty stations by hour of the day
# (the two charts are the visualisation code of my teammate)
#
# Run from the project folder:  Rscript analysis.R

library(tidyverse)
library(lubridate)
library(leaflet)
library(htmlwidgets)

dir.create("output", showWarnings = FALSE)

# 1. Read and prepare the data --------------------------------------------

bike_data <- read_csv("data/snapshots.csv", show_col_types = FALSE)

bike_data <- bike_data %>%
  mutate(
    vienna_time = with_tz(collected_at_utc, "Europe/Vienna"),  # UTC to Vienna time
    hour = hour(vienna_time),                                  # hour of the day
    empty = bikes_available == 0,                              # empty station?
    day_type = if_else(
      wday(vienna_time, week_start = 1) >= 6,
      "Weekend",
      "Weekday"
    )
  )

# 2. Chart: empty stations by hour ----------------------------------------

hourly_data <- bike_data %>%
  filter(!is.na(empty)) %>%
  group_by(hour) %>%
  summarise(
    pct_empty = mean(empty) * 100,
    n_observations = n(),
    .groups = "drop"
  )

ggplot(hourly_data, aes(x = hour, y = pct_empty)) +
  geom_line(colour = "steelblue", linewidth = 1) +
  geom_point(colour = "steelblue", size = 2) +
  scale_x_continuous(breaks = 0:23) +
  labs(
    title = "Empty Bike Stations in Vienna by Hour",
    subtitle = "Percentage of station observations with zero bikes",
    x = "Hour of Day (Vienna Time)",
    y = "Empty Station Observations (%)"
  ) +
  theme_minimal()

ggsave("output/bike_availability_by_hour.png", width = 10, height = 6, dpi = 300)

# 3. Chart: weekdays and weekends -----------------------------------------

weekday_weekend_data <- bike_data %>%
  filter(!is.na(empty), !is.na(day_type)) %>%
  group_by(day_type, hour) %>%
  summarise(
    pct_empty = mean(empty) * 100,
    n_observations = n(),
    .groups = "drop"
  )

ggplot(weekday_weekend_data,
       aes(x = hour, y = pct_empty, colour = day_type)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_x_continuous(breaks = 0:23) +
  labs(
    title = "Bike Station Availability: Weekdays vs Weekends",
    subtitle = "Percentage of station observations with zero available bikes",
    x = "Hour of Day (Vienna Time)",
    y = "Empty Station Observations (%)",
    colour = "Day Type"
  ) +
  theme_minimal()

ggsave("output/weekday_weekend_availability.png", width = 10, height = 6, dpi = 300)

# 4. Which stations are most often empty? ---------------------------------

# For each station: in what percent of the snapshots was it empty?
stations <- bike_data %>%
  group_by(station_id) %>%
  summarise(
    name = last(name),
    lat = last(lat),
    lon = last(lon),
    pct_empty = 100 * mean(empty)
  ) %>%
  arrange(desc(pct_empty))

print(head(stations, 10))

# 5. Map ------------------------------------------------------------------

# Colour classes: most stations are rarely empty, so the classes are small
# at the bottom
pal <- colorBin("YlOrRd", domain = stations$pct_empty,
                bins = c(0, 2, 5, 10, 20, 100))

bike_map <- leaflet(stations) %>%
  addProviderTiles(providers$Esri.WorldGrayCanvas) %>%
  addCircleMarkers(
    lng = ~lon, lat = ~lat, radius = ~4 + pct_empty / 5,
    stroke = TRUE, color = "grey30", weight = 0.7, fillOpacity = 0.9,
    fillColor = ~pal(pct_empty),
    popup = ~paste0("<b>", name, "</b><br>Empty ", round(pct_empty, 1),
                    "% of the time")
  ) %>%
  addLegend("bottomright", pal = pal, values = ~pct_empty,
            title = "% of time empty")

saveWidget(bike_map, "output/empty_stations_map.html", selfcontained = FALSE)
