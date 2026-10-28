##load packages
library(tidyverse)
library(lubridate)

##read data
bike_data <- read_csv("vienna-nextbike-availability/data/snapshots.csv")
head(bike_data)
names(bike_data)
nrow(bike_data)
n_distinct(bike_data$station_id)

##prepare data for visualisation
bike_data <- bike_data %>%
  mutate(
    time = ymd_hms(collected_at_utc, tz = "UTC"), ##convert timestamps so R can understand
    vienna_time = with_tz(time, "Europe/Vienna"), ##conver to vienna time
    hour = hour(vienna_time), ##extract hour
    empty = bikes_available == 0 ##identify empty statiosn
  )

head(bike_data %>%
  select(vienna_time, hour, bikes_available, empty))

##calculate prcentage of empty stations by hour
hourly_data <- bike_data %>%
  filter(!is.na(empty)) %>% ##remove missing observations
  group_by(hour) %>% 
  summarise(
    pct_empty = mean(empty) * 100, ##calculate percentage of empty stations
    n_observations = n(),
    .groups = "drop"
  )

print(hourly_data)
print(hourly_data, n = 24)

##visualise the percentage of empty stations by hour

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

ggsave(
  "bike_availability_by_hour.png",
  width = 10,
  height = 6,
  dpi = 300
)
##create weekday and weekend variable
bike_data <- bike_data %>%
  mutate(
    day_type = if_else(
      wday(vienna_time, week_start = 1) >= 6,
      "Weekend",
      "Weekday"
    )
  )
##calculate percentage of empty stations by hour and day type
weekday_weekend_data <- bike_data %>%
  filter(!is.na(empty), !is.na(day_type)) %>%
  group_by(day_type, hour) %>%
  summarise(
    pct_empty = mean(empty) * 100,
    n_observations = n(),
    .groups = "drop"
  )
print(weekday_weekend_data, n = 48)

ggplot(
  weekday_weekend_data,
  aes(x = hour, y = pct_empty, colour = day_type)
) +
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

ggsave(
  "weekday_weekend_availability.png",
  width = 10,
  height = 6,
  dpi = 300
)