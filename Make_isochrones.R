# Find biking distance from various destinations
library(tidyverse)
library(sf)
library(openrouteservice)

# Access points to open space, created by hand in QGIS (Open space isochrones.qgz)
access_pts = tribble(
  ~lon, ~lat,
  -72.63151212936923, 42.31801314253943, # Northampton
  -72.67200875862284, 42.33524575815275  # Florence
)


# Rate limit: 20 calls/min, 500 calls/day at OpenRouteService.
fetch_iso <- function(lon, lat, range_min) {
  ors_isochrones(c(lon, lat),
                 range = range_min * 60,
                 range_type = 'time',
                 profile = ors_profile('bike'),
                 output = 'sf')
}

# We can only process five points at at time...
# Might as well just do one at a time
isochrones = pmap(access_pts,
                 function(lon, lat) fetch_iso(lon, lat, c(5, 12, 20)))


buffer = do.call(c, map(isochrones, st_geometry)) |> 
  st_make_valid() |> 
  st_as_sf(crs=4326) |> 
  mutate(time=rep(c(5, 12, 20), 2), center=rep(c('Northampton', 'Florence'), each=3))

library(mapview)
mapview(buffer, zcol=c('center'), burst=TRUE, alpha.regions=0)

st_write(buffer, here::here('isochrones.gpkg'),
         layer='city_centers_5_12_20', delete_layer=TRUE)

buffer = st_read(here::here('isochrones.gpkg'),
         layer='city_centers_5_12_20')

# Build isochrones for each feature in an sf object.
# Returns an sf with time and center (= name) columns.
iso_from_sf <- function(sf_data, range_min) {
  coords <- st_coordinates(st_transform(sf_data, 4326))
  map2(coords[, 1], coords[, 2],
       \(lon, lat) fetch_iso(lon, lat, range_min) |> st_geometry()) |>
    do.call(c, args = _) |>
    st_make_valid() |>
    st_as_sf(crs = 4326) |>
    mutate(time = range_min, center = sf_data$name)
}

# ── Schools: 12-minute isochrones ─────────────────────────────────────────────
schools <- st_read(here::here('data/schools.gpkg'), quiet = TRUE)

school_iso <- iso_from_sf(public_schools, 12)
mapview(school_iso, zcol='center')
st_write(school_iso, here::here('isochrones.gpkg'),
         layer = 'schools_12', delete_layer = TRUE)

# ── Destinations: 12-minute isochrones ────────────────────────────────────────
destinations <- st_read(here::here('data/destinations.gpkg'), quiet = TRUE)

dest_iso <- iso_from_sf(destinations, 12)
mapview(dest_iso, zcol='center')
st_write(dest_iso, here::here('isochrones.gpkg'),
         layer = 'destinations_12', delete_layer = TRUE)

# ── Food stores: 12-minute isochrones ────────────────────────────────────────
food_stores <- st_read(here::here('data/food_stores.gpkg'), quiet = TRUE)

food_stores_iso <- iso_from_sf(food_stores, 12)
mapview(food_stores_iso, zcol='center')
st_write(food_stores_iso, here::here('isochrones.gpkg'),
         layer = 'food_stores_12', delete_layer = TRUE)

