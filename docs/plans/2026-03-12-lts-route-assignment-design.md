# Design: LTS Route Assignment Comparison

**Date:** 2026-03-12
**Script:** ExploreRoutes.R (append to existing)

## Goal

Identify street segments that are candidates for improved bicycle
infrastructure by comparing traffic assignment under two cost models:

1. **Unweighted**: cost = segment length only
2. **LTS-weighted**: cost = LTS × length (penalizes high-stress segments)

Segments with large decreases in flow under LTS-weighted routing are
desirable routes that cyclists avoid due to stress — prime candidates for
infrastructure investment.

## Inputs (already in scope in ExploreRoutes.R)

- `stress`: LTS street segments (sf LINESTRING, with `LTS` column)
- `hex_centers`: population-weighted hex centroids with `people_count`
- `public_schools`: 7 school locations (sf POINT)
- `school_districts`: school district boundaries with `Name` column

## Pipeline

### 1. Graph Preparation

Convert the LTS network to an undirected flownet graph:

```r
stress_graph <- linestrings_to_graph(stress, digits = NA,
                                     keep.cols = c('id', 'name', 'LTS'))
stress_graph <- create_undirected_graph(stress_graph)
# .length column is computed by default in linestrings_to_graph
```

### 2. Map Origins and Destinations to Nodes

```r
stress_nodes <- nodes_from_graph(stress_graph, sf = TRUE)
hex_node_ids    <- stress_nodes$node[st_nearest_feature(hex_centers, stress_nodes)]
school_node_ids <- stress_nodes$node[st_nearest_feature(public_schools, stress_nodes)]
```

### 3. Build OD Matrix

Two destination groups:

- **Secondary schools** (Northampton High School, Smith Vocational,
  JFK Middle School): all hex_centers are valid origins
- **Elementary schools** (Jackson Street, Ryan Road, Leeds, Bridge St):
  only hex_centers whose school district matches that school

District matching: spatial join `hex_centers` with `school_districts`,
then filter by `Name`. District names are not identical to school names
but the obvious mapping is correct (verify interactively if needed).

Flow weight = `people_count` at each hex centroid.

Result: a long data frame with columns `from` (hex node), `to` (school
node), `flow` (people_count).

### 4. Run Assignment — Unweighted (Phase 1)

```r
result_unweighted <- run_assignment(stress_graph, od_matrix,
                                    cost.column = ".length",
                                    method = "AoN")
```

### 5. Validate

Join `result_unweighted$final_flows` back to street segments and
visualize with mapview. Confirm flows concentrate on expected corridors
before proceeding.

### 6. LTS-Weighted Run + Comparison (Phase 2, later)

```r
stress_graph$lts_cost <- stress_graph$LTS * stress_graph$.length

result_lts <- run_assignment(stress_graph, od_matrix,
                             cost.column = "lts_cost",
                             method = "AoN")

flow_delta <- result_lts$final_flows - result_unweighted$final_flows
# Large negative values = infrastructure candidates
```

## OD Matrix Size

Northampton has ~300–600 populated hex cells. With 7 school
destinations the full OD matrix is ~2,000–4,000 pairs — well within
AoN capacity. No subsetting needed.

## Future Extensions

- Quarto document for shareable report
- PSL method for more realistic flow distribution
- Additional destinations (downtown, parks, transit stops)
- Refined LTS cost functions (e.g., LTS² × length)
- Subset to high-population hexes only if runtime becomes an issue
