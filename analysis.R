# Analysis of the collected bike-share data
# Output: a map of the stations that are most often empty, a chart by hour
#
# Run from the project folder:  Rscript analysis.R

library(tidyverse)
library(leaflet)
library(htmlwidgets)

dir.create("output", showWarnings = FALSE)

# 1. Read the data --------------------------------------------------------

snapshots <- read_csv("data/snapshots.csv", show_col_types = FALSE)

# The times are saved in UTC. For the hour of the day we want Vienna time.
snapshots <- snapshots %>%
  mutate(
    time = with_tz(collected_at_utc, "Europe/Vienna"),
    hour = hour(time),
    is_empty = bikes_available == 0
  )

# 2. Which stations are most often empty? ---------------------------------

# For each station: in what percent of the snapshots was it empty?
stations <- snapshots %>%
  group_by(station_id) %>%
  summarise(
    name = last(name),
    lat = last(lat),
    lon = last(lon),
    pct_empty = 100 * mean(is_empty)
  ) %>%
  arrange(desc(pct_empty))

print(head(stations, 10))

# 3. Map ------------------------------------------------------------------

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

# 4. Empty stations by hour of the day ------------------------------------

by_hour <- snapshots %>%
  group_by(hour) %>%
  summarise(pct_empty = 100 * mean(is_empty))

ggplot(by_hour, aes(x = hour, y = pct_empty)) +
  geom_line() +
  geom_point() +
  labs(title = "Share of stations with no bikes, by hour of the day",
       x = "Hour (Vienna time)", y = "% of stations empty")

ggsave("output/empty_by_hour.png", width = 8, height = 4.5)
