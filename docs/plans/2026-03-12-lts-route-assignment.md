# LTS Route Assignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Assign population-weighted bicycle flows from hex centroids to schools through the LTS street network, first with unweighted cost (length only) to validate the pipeline.

**Architecture:** Append code to ExploreRoutes.R. Convert the existing directed stress graph to undirected, map origins/destinations to nearest nodes, build a school-district-aware OD matrix, run All-or-Nothing assignment, and visualize edge flows.

**Tech Stack:** flownet (linestrings_to_graph, create_undirected_graph, nodes_from_graph, run_assignment), sf (st_nearest_feature, st_join), tidyverse, mapview

---

### Task 1: Make the graph undirected and update stress_nodes

**Files:**
- Modify: `ExploreRoutes.R:129-130`

**Step 1: Replace the two graph lines**

The existing lines 129–130 create a directed graph and non-sf nodes.
Replace them with:

```r
# Make a street graph from the stress data (undirected)
stress_graph <- linestrings_to_graph(stress, digits = NA,
                                     keep.cols = c('id', 'name', 'LTS'))
stress_graph <- create_undirected_graph(stress_graph)
# .length column is computed by linestrings_to_graph by default
stress_nodes <- nodes_from_graph(stress_graph, sf = TRUE)
```

**Step 2: Verify**

Run these lines and check the output:

```r
nrow(stress_graph)      # should be roughly 2× the directed edge count
nrow(stress_nodes)      # unique nodes
st_crs(stress_nodes)    # should be EPSG:4326
head(stress_graph[, c("from", "to", "LTS", ".length")])  # confirm columns present
```

Expected: `LTS` values 1–4, `.length` in meters (hundreds to thousands).

---

### Task 2: Map hex_centers and public_schools to nearest graph nodes

**Files:**
- Modify: `ExploreRoutes.R` (append after Task 1)

**Step 1: Add node-mapping code**

```r
# Map origins and destinations to nearest graph nodes
hex_node_ids    <- stress_nodes$node[st_nearest_feature(hex_centers, stress_nodes)]
school_node_ids <- stress_nodes$node[st_nearest_feature(public_schools, stress_nodes)]
```

**Step 2: Verify**

```r
length(hex_node_ids)     # should equal nrow(hex_centers)
length(school_node_ids)  # should be 7

# Quick sanity check: do schools map to sensible locations?
stress_nodes |>
  filter(node %in% school_node_ids) |>
  mapview() +
  mapview(public_schools, col.regions = "red")
# School points and their nearest nodes should be very close together
```

---

### Task 3: Build the OD matrix

**Files:**
- Modify: `ExploreRoutes.R` (append after Task 2)

**Step 1: Check the district name values**

Run this before writing the mapping to confirm exact spelling:

```r
sort(school_districts$Name)
```

Note down the names that correspond to the 4 elementary schools.

**Step 2: Add district-aware OD matrix code**

```r
# Separate secondary from elementary schools
secondary_names <- c(
  "Northampton High School",
  "Smith Vocational and Agricultural High School",
  "John F. Kennedy Middle School"
)

# Assign each hex centroid to a school district
hex_districts <- hex_centers |>
  mutate(hex_node = hex_node_ids) |>
  st_join(school_districts) |>
  st_drop_geometry() |>
  select(hex_node, people_count, district_name = Name)

# OD pairs: secondary schools (all hexes as origins)
od_secondary <- public_schools |>
  filter(name %in% secondary_names) |>
  mutate(school_node = school_node_ids[name %in% secondary_names]) |>
  st_drop_geometry() |>
  cross_join(hex_centers |>
               mutate(hex_node = hex_node_ids) |>
               st_drop_geometry() |>
               select(hex_node, people_count)) |>
  transmute(from = hex_node, to = school_node, flow = people_count)

# OD pairs: elementary schools (only hexes in matching district)
# Verify this mapping against sort(school_districts$Name) output above
elementary_district_map <- tribble(
  ~school_name,                                        ~district_name,
  "Jackson Street School",                             "Jackson Street School",
  "Robert K. Finn Ryan Road Elementary School",        "Ryan Road School",
  "Leeds Elementary School",                           "Leeds Elementary School",
  "Bridge St School",                                  "Bridge Street School"
)
# NOTE: adjust district_name values to match actual school_districts$Name output

elementary_schools <- public_schools |>
  filter(!name %in% secondary_names) |>
  mutate(school_node = school_node_ids[!name %in% secondary_names]) |>
  st_drop_geometry() |>
  left_join(elementary_district_map, by = c("name" = "school_name"))

od_elementary <- elementary_schools |>
  left_join(hex_districts, by = "district_name", relationship = "many-to-many") |>
  transmute(from = hex_node, to = school_node, flow = people_count)

# Combine and remove self-loops (hex centroid snaps to same node as school)
od_matrix <- bind_rows(od_secondary, od_elementary) |>
  filter(!is.na(from), !is.na(to), !is.na(flow), flow > 0, from != to)
```

**Step 3: Verify**

```r
nrow(od_matrix)
# Expected: a few hundred to ~3000 rows

summary(od_matrix$flow)
# Should show positive values matching people_count scale

# Check each school appears as a destination
od_matrix |> count(to) |> arrange(desc(n))
# Should show 7 distinct destination nodes
```

---

### Task 4: Run unweighted traffic assignment

**Files:**
- Modify: `ExploreRoutes.R` (append after Task 3)

**Step 1: Add assignment code**

```r
result_unweighted <- run_assignment(
  stress_graph,
  od_matrix,
  cost.column = ".length",
  method = "AoN",
  verbose = TRUE
)
print(result_unweighted)
```

**Step 2: Verify**

```r
length(result_unweighted$final_flows)  # must equal nrow(stress_graph)
sum(result_unweighted$final_flows > 0) # edges with any flow — expect many hundreds
summary(result_unweighted$final_flows)
```

Expected: many edges have zero flow (not on any shortest path); a minority carry
substantial flow concentrated on main corridors.

---

### Task 5: Visualize flows

**Files:**
- Modify: `ExploreRoutes.R` (append after Task 4)

**Step 1: Join flows back to geometry and map**

```r
# Attach flows to original street geometry
stress_with_flows <- stress |>
  mutate(
    edge      = row_number(),
    flow_unweighted = result_unweighted$final_flows
  )

# Map — use log scale to handle skewed distribution
mapview(
  stress_with_flows |> filter(flow_unweighted > 0),
  zcol  = "flow_unweighted",
  lwd   = 3,
  layer.name = "Unweighted flow"
)
```

**Step 2: Sanity check**

High-flow segments should concentrate on major routes between residential
areas and school locations. Cross-reference with the earlier
`mapview(population, ...)` to confirm flows originate from populated hexes.

If flows look implausible (e.g., routing through clearly wrong areas),
revisit the `digits = NA` setting in `linestrings_to_graph` — it controls
node-matching precision and can affect graph connectivity.

---

## Next Steps (not in this plan)

After validating unweighted flows:

1. **LTS-weighted run**: add `lts_cost = LTS * .length` to `stress_graph`, re-run
2. **Comparison**: compute `flow_delta = lts_flows - unweighted_flows`, map segments
   with large negative delta
3. **Quarto document** for a shareable report
