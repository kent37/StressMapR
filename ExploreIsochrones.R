# Maps of isochrones
library(tidyverse)
library(sf)
library(leaflet)
library(here)

# Schools and school districts

school_iso       <- st_read(here("isochrones.gpkg"), layer = "schools_12", quiet = TRUE)
school_districts <- read_sf(here("data/School_Districts_2015/School_Districts_2015.shp")) |>
  st_transform(4326)
schools          <- st_read(here("data/schools.gpkg"), quiet = TRUE) |>
  filter(is_public)

# Only elementary schools have dedicated attendance districts
district_for_school <- c(
  "Bridge St School"                           = "Bridge St",
  "Jackson Street School"                      = "Jackson St",
  "Leeds Elementary School"                    = "Leeds",
  "Robert K. Finn Ryan Road Elementary School" = "Ryan Rd"
)

school_names <- sort(unique(school_iso$center))
colors <- setNames(
  RColorBrewer::brewer.pal(length(school_names), "Set2"),
  school_names
)

m <- leaflet() |>
  addProviderTiles("CartoDB.Positron")

for (school in school_names) {
  color        <- colors[[school]]
  iso          <- school_iso |> filter(center == school)
  district_name <- district_for_school[school]

  if (!is.na(district_name)) {
    dist <- school_districts |> filter(Name == district_name)
    m <- m |>
      addPolygons(
        data = dist, group = school,
        fillColor = color, fillOpacity = 0.3,
        color = color, weight = 2,
        label = ~paste(Name, "District")
      )
  }

  m <- m |>
    addPolygons(
      data = iso, group = school,
      fillColor = color, fillOpacity = 0.15,
      color = color, weight = 2, dashArray = "6,4",
      label = paste(school, "12-minutes")
    )
}

legend_html <- htmltools::HTML("
  <div style='background:white; padding:8px 10px; border-radius:4px;
              border:1px solid #ccc; font-size:13px; line-height:1.6'>
    <b>Attendance district</b> — solid outline<br>
    <b>12-minute isochrone</b> — dashed outline
  </div>
")

m |>
  addLayersControl(
    overlayGroups = school_names,
    options = layersControlOptions(collapsed = FALSE)
  ) |>
  hideGroup(setdiff(school_names, "Northampton High School")) |>
  addControl(legend_html, position = "bottomleft")

# ── Destinations map ──────────────────────────────────────────────────────────
dest_iso    <- st_read(here("isochrones.gpkg"), layer = "destinations_12", quiet = TRUE)
dest_pts    <- st_read(here("data/destinations.gpkg"), quiet = TRUE)
hex_centers <- st_read(here("data/stress_flows.gpkg"), layer = "hex_centers", quiet = TRUE) |>
  st_transform(st_crs(dest_iso))

# Population reachable within each 12-minute isochrone
dest_pop <- st_join(hex_centers, dest_iso, join = st_within) |>
  st_drop_geometry() |>
  filter(!is.na(center)) |>
  summarise(population = sum(people_count), .by = center) |>
  arrange(desc(population)) |>
  mutate(group = paste0(center, " (", format(population, big.mark = ","), ")"))

pop_pal <- colorNumeric("YlOrRd", domain = dest_pop$population)

m2 <- leaflet() |>
  addProviderTiles("CartoDB.Positron")

for (i in seq_len(nrow(dest_pop))) {
  row   <- dest_pop[i, ]
  color <- pop_pal(row$population)
  iso   <- dest_iso |> filter(center == row$center)
  pt    <- dest_pts  |> filter(name  == row$center)

  m2 <- m2 |>
    addPolygons(
      data = iso, group = row$group,
      fillColor = color, fillOpacity = 0.15,
      color = color, weight = 2, dashArray = "6,4",
      label = paste(row$center, "12-minutes")
    ) |>
    addCircleMarkers(
      data = pt, group = row$group,
      color = color, fillColor = color, fillOpacity = 0.9,
      radius = 6, weight = 2,
      label = row$group
    )
}

m2 |>
  addLayersControl(
    overlayGroups = dest_pop$group,
    options = layersControlOptions(collapsed = FALSE)
  ) |>
  hideGroup(dest_pop$group)
