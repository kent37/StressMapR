# Explore access to food stores
library(tidyverse)
library(sf)
library(leaflet)

food_stores <- read_sf(here::here('data/food_stores.gpkg'))
food_iso    <- read_sf(here::here('isochrones.gpkg'), layer = 'food_stores_12') |>
  mutate(type = food_stores$type)
hex_centers <- read_sf(here::here("data/stress_flows.gpkg"), layer = "hex_centers") |>
  mutate(food_count = lengths(st_within(geom, food_iso)))

ggplot(hex_centers, aes(y=food_count, weight=people_count)) + 
  geom_histogram(binwidth=1) +
  scale_y_continuous(breaks=0:14, transform='reverse') +
  labs(y='Number of stores', x='Population') +
  theme_minimal(base_size=14) +
  theme(panel.grid.major.y=element_blank(),
        panel.grid.minor.y=element_blank())

# --- Colors ---
type_colors <- c(
  supermarket = "#1a7f5a",
  convenience = "#c47d0e"
)

iso_colors   <- unname(type_colors[food_iso$type])
store_colors <- unname(type_colors[food_stores$type])

pop_pal <- colorNumeric(
  palette = c("#fee5d9", "#fc4e2a", "#800026"),
  domain  = c(0, max(hex_centers$people_count))
)
pop_radius <- pmin(4 + hex_centers$people_count / 100, 8)

# --- Leaflet map ---
leaflet() |>
  addProviderTiles(providers$CartoDB.Positron) |>
  addPolygons(
    data        = food_iso,
    group       = "Isochrones",
    fillColor   = iso_colors,
    fillOpacity = 0.15,
    color       = iso_colors,
    weight      = 1.5,
    opacity     = 0.7,
    popup       = paste0("<strong>", food_iso$center, "</strong><br>12-min bike ride")
  ) |>
  addCircleMarkers(
    data        = food_stores,
    group       = "Stores",
    radius      = 6,
    color       = "#ffffff",
    weight      = 2,
    fillColor   = store_colors,
    fillOpacity = 1,
    popup       = paste0("<strong>", food_stores$name, "</strong><br>", food_stores$type)
  ) |>
  addCircleMarkers(
    data        = hex_centers,
    group       = "Population",
    radius      = pop_radius,
    stroke      = FALSE,
    fillColor   = pop_pal(hex_centers$people_count),
    fillOpacity = 0.7,
    label       = ~as.character(people_count)
  ) |>
  addLayersControl(
    overlayGroups = c("Isochrones", "Stores", "Population"),
    options       = layersControlOptions(collapsed = FALSE)
  ) |>
  addLegend(
    position = "bottomright",
    colors   = unname(type_colors),
    labels   = names(type_colors),
    title    = "Store type"
  )
