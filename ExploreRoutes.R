# Duplicate parts of STN potential for biking data
library(tidyverse)
library(classInt)
library(flownet)
library(hexify)
library(jsonlite)
library(mapview)
library(sf)

# Load the StressMap and Potential for everyday biking data
stress <- read_sf("../StressMap/plots/Northampton_LTS.gpkg", 
                  layer="Northampton")

potential <- read_sf("../StressMap/plots/Northampton_LTS.gpkg", 
                  layer="Potential for everyday biking") |> 
  st_zm() |> # Drop M dimension
  st_transform(st_crs(stress))

# Get population data
lines <- readLines(here::here("data/northampton_addresses.json"))                              
population = lines |>     
    str_replace_all("=>", ":") |>  
    str_replace_all("nil", "null") |>
    paste(collapse = ",\n") |>           
    (\(x) paste0("[", x, "]"))() |>      
    jsonlite::fromJSON() |>
    mutate(longitude = as.numeric(longitude), latitude = as.numeric(latitude)) |>
    st_as_sf(coords = c("longitude", "latitude"), crs = 4326)
#mapview(population, zcol='people_count')

# There are a bunch of locations that are not in Northampton...
noho = read_sf("../Noho/Shapefiles/Noho_outline/Noho_outline.gpkg") |> 
  st_transform(4326)

# Bin population in a hex grid 500 ft on a side (as with PEB)
grid <- hex_grid(area_km2 = 60342.2945/10^6)
pop_hexes = hexify(population, grid)
population$cell_id = pop_hexes@cell_id
noho_hexes = grid_clip(noho, grid)

# Aggregate population per hex
pop_per_hex = population |> 
  st_drop_geometry() |> 
  summarise(people_count = sum(people_count), .by=cell_id)

# Spatial data (hexes) with population
pop_by_hex = noho_hexes |> 
  inner_join(pop_per_hex)

hex_breaks <- classIntervals(pop_by_hex$people_count, n = 10, style = "jenks")$brks
pop_breaks = classIntervals(population$people_count, n = 10, style = "jenks")$brks
mapview(pop_by_hex, zcol='people_count', at = hex_breaks) + 
  mapview(population, zcol='people_count', at=pop_breaks,
          col.regions = colorRampPalette(RColorBrewer::brewer.pal(9, "YlOrRd")),
          lwd=0)

top_hexes = pop_by_hex |> slice_max(people_count, prop=0.1)
top_hex_breaks <- classIntervals(top_hexes$people_count, n = 10, style = "jenks")$brks
mapview(top_hexes, zcol='people_count', at = top_hex_breaks) + 
  mapview(population, zcol='people_count', at=pop_breaks,
          col.regions = colorRampPalette(RColorBrewer::brewer.pal(9, "YlOrRd")),
          lwd=0)

# Get a single point to represent each hex - a weighted average of the
# address points
hex_centers = population |>             
    mutate(                        
      x = st_coordinates(geometry)[, 1],  
      y = st_coordinates(geometry)[, 2]
    ) |>                               
    st_drop_geometry() |>
    group_by(cell_id) |>
    summarise(
      x = weighted.mean(x, people_count, na.rm = TRUE),
      y = weighted.mean(y, people_count, na.rm = TRUE),
      people_count = sum(people_count)
    ) |>
    st_as_sf(coords = c("x", "y"), crs = 4326)
mapview(pop_by_hex, zcol='people_count', at = hex_breaks) + 
  mapview(hex_centers, zcol='people_count', at=hex_breaks,
          col.regions = colorRampPalette(RColorBrewer::brewer.pal(9, "YlOrRd")),
          lwd=0)

# What is the population density of each hex?
km2_per_mi2 = 2.59
pop_by_hex$density = pop_by_hex$people_count / grid@area_km2 * km2_per_mi2 
# 4,000 / sq mile is a bare minimum for a walkable city
mapview(pop_by_hex |> filter(density >= 4000), zcol='density') + 
  mapview(population, zcol='people_count', at=pop_breaks,
          col.regions = colorRampPalette(RColorBrewer::brewer.pal(9, "YlOrRd")),
          lwd=0)


# schools_raw <- fromJSON(here::here("data/schools.json"))$elements |>
#   as_tibble()

# schools = schools_raw |>
#   mutate(
#     lat = coalesce(lat, center$lat),
#     lon = coalesce(lon, center$lon),
#     name = tags$name
#   ) |>
#   select(type, id, lat, lon, name) |> 
#   st_as_sf(coords=c('lon', 'lat'), crs=4326)
# Allow editing of the schools to put the location near the entrances
#st_write(schools, here::here('data/schools.gpkg'))
schools = st_read(here::here('data/schools.gpkg'))

mapview(schools, zcol='name')

public_schools = schools |> 
  filter(name %in% c("Jackson Street School", 
                     "Robert K. Finn Ryan Road Elementary School",
                     "John F. Kennedy Middle School", 
                     "Leeds Elementary School", 
                     "Bridge St School", 
                     "Smith Vocational and Agricultural High School", 
                     "Northampton High School"
))

school_districts = 
  read_sf(here::here('data/School_Districts_2015/School_Districts_2015.shp')) |> 
  st_transform(4326)
mapview(public_schools, zcol='name') + mapview(school_districts, zcol='Name', alpha.regions=0.2)

# What is the population in each school district?
population |> 
  st_join(school_districts) |> 
  st_drop_geometry() |> 
  summarize(people_count=sum(people_count), .by=Name)

# Make a street graph from the stress data (undirected)
stress_graph <- linestrings_to_graph(stress, digits = 4,
                                     keep.cols = c('id', 'name', 'LTS'))
stress_graph <- create_undirected_graph(stress_graph, by='LTS')
# .length column is computed by linestrings_to_graph by default
stress_nodes <- nodes_from_graph(stress_graph, sf = TRUE)

# Map origins and destinations to nearest graph nodes
hex_centers <- hex_centers  |> 
  mutate(hex_node = stress_nodes$node[st_nearest_feature(hex_centers, stress_nodes)])
public_schools <- public_schools |>
  mutate(school_node = stress_nodes$node[st_nearest_feature(public_schools, stress_nodes)])

# Load non-school destinations and map to nearest graph nodes
destinations <- st_read(here::here("data/destinations.gpkg"))
destinations = destinations |>
  st_transform(st_crs(stress_nodes)) |>
  mutate(dest_node = stress_nodes$node[st_nearest_feature(destinations, stress_nodes)])

# Visualize the mapping from hex_centers, public_schools, and destinations to their nearest stress_nodes
hex_mapped_nodes   <- stress_nodes |> filter(node %in% hex_centers$hex_node)
school_mapped_nodes <- stress_nodes |> filter(node %in% public_schools$school_node)
dest_mapped_nodes  <- stress_nodes |> filter(node %in% destinations$dest_node)

mapview(hex_mapped_nodes,   col.regions = "steelblue", layer.name = "Hex center nodes") +
mapview(school_mapped_nodes, col.regions = "firebrick", layer.name = "School nodes") +
mapview(dest_mapped_nodes,  col.regions = "darkgreen", layer.name = "Destination nodes") +
mapview(hex_centers,        col.regions = "lightblue", cex = 4, layer.name = "Hex centers") +
mapview(public_schools,     col.regions = "red",       cex = 6, layer.name = "Schools") +
mapview(destinations,       col.regions = "green",     cex = 6, layer.name = "Destinations")

# Build OD matrix: hex centroids to schools, weighted by population
secondary_names <- c(
  "Northampton High School",
  "Smith Vocational and Agricultural High School",
  "John F. Kennedy Middle School"
)

# Assign each hex centroid to a school district
hex_districts <- hex_centers |>
  st_join(school_districts) |>
  st_drop_geometry() |>
  select(hex_node, people_count, district_name = Name)

# OD pairs: secondary schools (all hexes as origins)
od_secondary <- public_schools |>
  filter(name %in% secondary_names) |>
  st_drop_geometry() |>
  cross_join(hex_centers |>
               st_drop_geometry() |>
               select(hex_node, people_count)) |>
  transmute(from = hex_node, to = school_node, flow = people_count)

# OD pairs: elementary schools (only hexes in matching district)
elementary_district_map <- tribble(
  ~school_name,                                        ~district_name,
  "Jackson Street School",                             "Jackson St",
  "Robert K. Finn Ryan Road Elementary School",        "Ryan Rd",
  "Leeds Elementary School",                           "Leeds",
  "Bridge St School",                                  "Bridge St"
)

od_elementary <- public_schools |>
  filter(!name %in% secondary_names) |>
  st_drop_geometry() |>
  left_join(elementary_district_map, by = c("name" = "school_name")) |>
  left_join(hex_districts, by = "district_name", relationship = "many-to-many") |>
  transmute(from = hex_node, to = school_node, flow = people_count)

# OD pairs: all hex centroids to all non-school destinations
od_destinations <- destinations |>
  st_drop_geometry() |>
  cross_join(hex_centers |>
               st_drop_geometry() |>
               select(hex_node, people_count)) |>
  transmute(from = hex_node, to = dest_node, flow = people_count)

# Combine all OD pairs and remove self-loops and invalid rows
od_matrix <- bind_rows(od_secondary, od_elementary, od_destinations) |>
  filter(!is.na(from), !is.na(to), !is.na(flow), flow > 0, from != to)

# Run unweighted traffic assignment (cost = segment length)
result_unweighted <- run_assignment(
  stress_graph,
  od_matrix,
  cost.column = ".length",
  method = "AoN",
  nthreads=6, # Broken in R 4.5.3 vs 4.5.0 for PSL
  return.extra='all',
  verbose = TRUE
)

# Attach flows to street geometry and visualize
stress_with_flows <- stress |>
  left_join(
    stress_graph |>
      mutate(flow_unweighted = result_unweighted$final_flows) |>
      select(id, flow_unweighted),
    by = "id"
  )

mapview(
  stress_with_flows |> filter(flow_unweighted > 0),
  zcol       = "flow_unweighted",
  lwd        = 3,
  layer.name = "Unweighted flow"
)

# LTS-weighted traffic assignment
# Step function: LTS 1-2 = no penalty, LTS 3 = 5x, LTS 4 = 10x
stress_graph <- stress_graph |>
  mutate(lts_cost = case_when(
    LTS <= 2 ~ .length,
    LTS == 3 ~ 5 * .length,
    LTS == 4 ~ 10 * .length
  ))

result_lts <- run_assignment(
  stress_graph,
  od_matrix,
  cost.column = "lts_cost",
  method = "AoN",
  nthreads=6,
  return.extra='all',
  verbose = TRUE
)

# Compare flows: segments avoided due to stress are infrastructure candidates
stress_with_flows <- stress_with_flows |>
  left_join(
    stress_graph |>
      mutate(flow_lts = result_lts$final_flows) |>
      select(id, flow_lts),
    by = "id"
  ) |>
  mutate(flow_delta = flow_lts - flow_unweighted)

# Routes chosen while avoiding high-stress
mapview(
  stress_with_flows |> filter(flow_lts > 0),
  zcol       = "flow_lts",
  lwd        = 3,
  layer.name = "Weighted flow"
)

# How much flow is sill on high stress streets, even with high avoidance?
high_stress_flows = stress_with_flows |> filter(flow_lts > 1600, LTS >=3)
mapview(
  high_stress_flows,
  zcol       = "flow_lts",
  lwd        = 3,
  at = classIntervals(high_stress_flows$flow_lts, n = 8, style = "quantile")$brks,

  layer.name = "Unavoidable stress"
)

# Segments with large negative delta = desirable but avoided due to stress
# Segments with a large positive delta are the alternatives
delta_data <- stress_with_flows |>
  filter(!is.na(flow_delta), abs(flow_delta) >= 50)
delta_breaks <- pretty(delta_data$flow_delta, n=10)
if (!0 %in% delta_breaks) delta_breaks <- sort(c(delta_breaks, 0))
n_neg <- sum(delta_breaks < 0)
n_pos <- sum(delta_breaks > 0)
delta_colors <- c(
  colorRampPalette(c("#d73027", "#ffffbf"))(n_neg),
  colorRampPalette(c("#ffffbf", "#4575b4"))(n_pos)
)
mapview(
  delta_data,
  zcol       = "flow_delta",
  at         = delta_breaks,
  color      = delta_colors,
  lwd        = 3,
  layer.name = "Flow change with stress-avoidance"
)

# High avoidance: segments avoided due to stress (negative delta only)
neg_data   <- stress_with_flows |> filter(!is.na(flow_delta), flow_delta < 0)
neg_breaks <- pretty(neg_data$flow_delta, n = 8)
neg_colors <- colorRampPalette(c("#d73027", "#ffffbf"))(length(neg_breaks))
mapview(
  neg_data,
  zcol       = "flow_delta",
  at         = neg_breaks,
  color      = neg_colors,
  lwd        = 3,
  layer.name = "High avoidance"
)

# Segments that are either highly avoided or unavoidable
candidates = stress_with_flows |> 
  filter(flow_delta < 0 | (flow_lts > 0 & LTS >=3)) |> 
  mutate(score = pmax(-flow_delta, flow_lts))
mapview(candidates |> filter(score>15000), zcol='score',
        layer.name='Avoided or unavoidable') +
mapview(public_schools,     col.regions = "red",       cex = 6, layer.name = "Schools") +
mapview(destinations,       col.regions = "green",     cex = 6, layer.name = "Destinations")
ggplot(candidates) +
  geom_histogram(aes(score))


# Compare path lengths 
unweighted_lengths <- result_unweighted$path_costs

seg_lengths <- as.numeric(stress_graph$.length)

lts_lengths <- map_dbl(result_lts$paths, \(segs) sum(seg_lengths[segs]))

detour_lengths <- lts_lengths - unweighted_lengths

tibble(
  unweighted = unweighted_lengths,
  lts        = lts_lengths,
  diff       = detour_lengths) |>
  ggplot() +
  geom_histogram(aes(diff))

# Segment-level detour burden: for each segment avoided by the LTS router,
# sum the detour distance across all OD pairs that avoided it.
# - setdiff(unw, lts) finds segments in the unweighted path that were dropped
#   by the LTS router (i.e., avoided due to stress)
# - Each avoided segment gets the full detour length for that OD pair added
#   to its burden — so detour_burden answers "how much total extra distance
#   do people ride because of this segment?"
# - Only OD pairs with a positive detour contribute
# The segments with the highest detour_burden are the best infrastructure
# candidates — improving them would eliminate the most collective detour.
avoided_df <- pmap(
  list(result_unweighted$paths, result_lts$paths, detour_lengths),
  \(unw, lts, detour) {
    avoided_segs <- setdiff(unw, lts)
    if (length(avoided_segs) == 0 || detour <= 0) return(NULL)
    tibble(seg_row = avoided_segs, detour = detour)
  }
) |>
  list_rbind()

seg_detour_burden <- avoided_df |>
  summarise(detour_burden = sum(detour), .by = seg_row)

stress_detour <- stress_graph |>
  mutate(seg_row = row_number()) |>
  inner_join(seg_detour_burden, by = "seg_row") |>
  left_join(stress |> select(id, geom), by = "id") |>
  st_as_sf()

mapview(stress_detour |> filter(detour_burden>=1000000), zcol = "detour_burden", lwd = 3, layer.name = "Detour burden")

# Add detour_burden to stress_with_flows and save for scrollytelling map
stress_with_flows <- stress_with_flows |>
  left_join(
    stress_detour |> st_drop_geometry() |> select(id, detour_burden),
    by = "id"
  )

stress_with_flows |>
  filter(
    flow_unweighted > 0 | flow_lts > 0 | !is.na(detour_burden)
  ) |>
  select(LTS, flow_unweighted, flow_lts, flow_delta, detour_burden) |>
  st_write(here::here("data/stress_flows.gpkg"), delete_dsn = TRUE)

hex_centers |>
  select(people_count) |>
  st_write(here::here("data/stress_flows.gpkg"), layer = "hex_centers", append = TRUE)
