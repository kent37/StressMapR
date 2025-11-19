# Find biking distance from Northampton and Florence center
library(tidyverse)
library(sf)
library(openrouteservice)

# Access points to open space, created by hand in QGIS (Open space isochrones.qgz)
access_pts = tribble(
  ~lon, ~lat,
  -72.63151212936923, 42.31801314253943, # Northampton
  -72.67200875862284, 42.33524575815275  # Florence
)


# We can only process five points at at time...
# Might as well just do one at a time
# This is slow, we are rate-limited to 20/min (and 500/day) at OpenRouteService
isochrones = pmap(access_pts,
                 function(lon, lat) {
                   ors_isochrones(c(lon, lat), 
                         range=c(5, 12, 20)*60, 
                         range_type='time',
                         profile=ors_profile('bike'), 
                         output='sf')
                   })


buffer = do.call(c, map(isochrones, st_geometry)) |> 
  st_make_valid() |> 
  st_as_sf(crs=4326) |> 
  mutate(time=rep(c(5, 12, 20), 2), center=rep(c('Northampton', 'Florence'), each=3))

library(mapview)
mapview(buffer, zcol=c('center'), burst=TRUE, alpha.regions=0)

st_write(buffer, here::here('isochrones.gpkg'), 
         layer='isochrones', delete_layer=TRUE)

buffer = st_read(here::here('isochrones.gpkg'), 
         layer='isochrones')
