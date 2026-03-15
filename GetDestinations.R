# GetDestinations.R — Fetch civic POI and business district destinations from OSM
# Produces: data/destinations.gpkg (sf POINT, columns: name, type)

library(tidyverse)
library(osmdata)
library(sf)
library(mapview)
library(here)

noho_bb <- getbb("Northampton, Massachusetts")

# Fetch civic amenities: library, hospital, townhall
civic_raw <- opq(noho_bb) |>
  add_osm_feature(key = "amenity",
                  value = c("library", "hospital", "townhall")) |>
  osmdata_sf()

# Some features are nodes, others are polygons — combine both
civic_points <- list(
  civic_raw$osm_points   |> select(name, amenity),
  civic_raw$osm_polygons |> st_point_on_surface() |> select(name, amenity)
) |>
  discard(\(x) is.null(x) || nrow(x) == 0) |>
  bind_rows() |>
  filter(name %in% c(
    "Forbes Library",
    "Lilly Library",
    "Cooley Dickinson Hospital",
    "Northampton City Hall"
  )) |>
  transmute(name, type = "civic")

print(civic_points)
# Expected: 4 rows, columns: name, type, geometry
# All 4 named features should appear

mapview(civic_points, zcol = "name")
# Each point should be at a recognizable location in Northampton

# Representative intersections — verify visually and adjust if needed
business_districts <- tribble(
  ~name,              ~lon,       ~lat,
  "Main & King St",   -72.6327,   42.3240,   # Downtown north anchor
  "Main & Center St", -72.6325,   42.3194,   # Downtown mid
  "Main & State St",  -72.6346,   42.3197,   # Downtown south/west
  "Main & Maple St",  -72.6720,   42.3354,   # Florence center
  "Main & Chestnut St", -72.6674, 42.3358    # Florence east
) |>
  st_as_sf(coords = c("lon", "lat"), crs = 4326) |>
  mutate(type = "business_district")

# Combine and save
destinations <- bind_rows(civic_points, business_districts)

mapview(destinations, zcol = "type") +
  mapview(destinations, zcol = "name")
# Each point should fall at or very near its named intersection/location
# Adjust lon/lat values in the tribble if any are off

st_write(destinations, here("data/destinations.gpkg"), delete_dsn = TRUE)

# Note: this has been edited in QGIS.