# OSM Destinations Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fetch civic POI destinations from OSM and define business district representative points, save to `data/destinations.gpkg`, then integrate them into the routing OD matrix in `ExploreRoutes.R`.

**Architecture:** New script `GetDestinations.R` produces `data/destinations.gpkg` (sf POINT, columns: `name`, `type`). `ExploreRoutes.R` loads this file, snaps points to graph nodes, and adds them to `od_matrix` via `cross_join` with all hex centroids.

**Tech Stack:** osmdata, sf, tidyverse, mapview, here

---

### Task 1: Fetch civic POIs from OSM and save to gpkg

**Files:**
- Create: `GetDestinations.R`

**Context:**
The schools script (`ExploreRoutes.R`) uses `fromJSON` to load schools from a pre-fetched JSON. For destinations we query OSM directly via `osmdata`. Some amenities are stored as nodes (points), others as ways (polygons); we need to handle both by taking `st_centroid()` on polygons.

**Step 1: Create `GetDestinations.R` with civic POI query**

```r
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
civic_points <- bind_rows(
  civic_raw$osm_points   |> select(name, amenity),
  civic_raw$osm_polygons |> st_centroid() |> select(name, amenity)
) |>
  filter(name %in% c(
    "Forbes Library",
    "Lilly Library",
    "Cooley Dickinson Hospital",
    "Northampton City Hall"
  )) |>
  transmute(name, type = "civic")
```

**Step 2: Verify — print and map**

```r
print(civic_points)
# Expected: 4 rows, columns: name, type, geometry
# All 4 named features should appear

mapview(civic_points, zcol = "name")
# Each point should be at a recognizable location in Northampton
```

If any of the 4 features are missing, check `civic_raw$osm_points$name` and `civic_raw$osm_polygons$name` to see what names OSM uses, then adjust the `filter()`.

---

### Task 2: Define business district points and combine

**Files:**
- Modify: `GetDestinations.R` (append)

**Context:**
Business district representative points are hardcoded intersections — one per key intersection in downtown Northampton and Florence village. Coordinates below are approximate; verify with mapview and adjust if off by more than a block.

**Step 1: Add business district tribble and combine**

```r
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
```

**Step 2: Verify visually**

```r
mapview(destinations, zcol = "type") +
  mapview(destinations, zcol = "name")
# Each point should fall at or very near its named intersection/location
# Adjust lon/lat values in the tribble if any are off
```

**Step 3: Save to gpkg**

```r
st_write(destinations, here("data/destinations.gpkg"), delete_dsn = TRUE)
```

**Step 4: Verify the saved file**

```r
check <- st_read(here("data/destinations.gpkg"))
nrow(check)   # should be 9 (4 civic + 5 business district)
names(check)  # should include: name, type, geom
```

---

### Task 3: Integrate destinations into OD matrix in ExploreRoutes.R

**Files:**
- Modify: `ExploreRoutes.R` — insert after line 143 (after `public_schools` node mapping) and after line 194 (after `od_matrix` is built)

**Context:**
`stress_nodes` is already built at line 133. The pattern for snapping to nodes is: `stress_nodes$node[st_nearest_feature(points, stress_nodes)]`. All hex centroids are origins for all destinations (no district filtering).

**Step 1: Load destinations and snap to graph nodes**

Insert after the `public_schools` node-mapping block (after line 143):

```r
# Load non-school destinations and map to nearest graph nodes
destinations <- st_read(here::here("data/destinations.gpkg")) |>
  st_transform(st_crs(stress_nodes)) |>
  mutate(dest_node = stress_nodes$node[st_nearest_feature(destinations, stress_nodes)])
```

**Step 2: Build OD pairs for destinations**

Insert after `od_matrix` is built (after line 194, before the `run_assignment` call):

```r
# OD pairs: all hex centroids to all non-school destinations
od_destinations <- destinations |>
  st_drop_geometry() |>
  cross_join(hex_centers |>
               st_drop_geometry() |>
               select(hex_node, people_count)) |>
  transmute(from = hex_node, to = dest_node, flow = people_count)

# Add destinations to OD matrix
od_matrix <- bind_rows(od_matrix, od_destinations) |>
  filter(!is.na(from), !is.na(to), !is.na(flow), flow > 0, from != to)
```

**Step 3: Verify OD matrix growth**

```r
nrow(od_matrix)
# Should be larger than before (previous value + n_destinations * n_hex_centroids)

od_matrix |> count(to) |> arrange(desc(n))
# Should now show 16 distinct destination nodes (7 schools + 9 destinations)
# (or fewer if any destinations snap to the same node as a school)
```

**Step 4: Verify assignment still runs**

Re-run the `run_assignment` call for `result_unweighted` and confirm it completes without errors. Flow totals will be higher (more OD pairs), but the same segments should carry the most flow.

```r
result_unweighted <- run_assignment(
  stress_graph,
  od_matrix,
  cost.column = ".length",
  method = "PSL",
  verbose = TRUE
)
# Should complete; "OD-pairs skipped" warning may increase slightly
```
