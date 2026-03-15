# LTS Route Assignment — Progress Summary

**Date:** 2026-03-12

## Goal

Identify street segments that are candidates for improved bicycle
infrastructure by comparing traffic assignment under two cost models:

1. **Unweighted** — cost = segment length only (where do people *want* to go?)
2. **LTS-weighted** — cost penalizes high-stress segments (where do they go when stress matters?)

Segments with large decreases in flow under LTS-weighted routing are
desirable routes that cyclists avoid due to stress.

## What Has Been Built

The pipeline is implemented in `ExploreRoutes.R` (lines 128–208),
appended after the existing population/school/district data preparation.

### Graph (lines 128–133)

The LTS street network is converted to an **undirected** flownet graph:

```r
stress_graph <- linestrings_to_graph(stress, digits = NA,
                                     keep.cols = c('id', 'name', 'LTS'))
stress_graph <- create_undirected_graph(stress_graph)
stress_nodes <- nodes_from_graph(stress_graph, sf = TRUE)
```

`linestrings_to_graph` computes a `.length` column (meters) by default.
`create_undirected_graph` collapses bidirectional duplicates, averaging
numeric attributes (including LTS) across merged edges.

### Node mapping (lines 135–139)

Nearest graph nodes are added directly to the origin/destination objects:

```r
hex_centers    <- hex_centers    |> mutate(hex_node    = ...)
public_schools <- public_schools |> mutate(school_node = ...)
```

### OD matrix (lines 141–181)

Origins: `hex_centers` (population-weighted hex centroids, `people_count` as flow weight)
Destinations: `public_schools` (7 schools)

Two destination groups:
- **Secondary schools** (Northampton High, Smith Vocational, JFK Middle):
  all hex centroids as origins — `cross_join`
- **Elementary schools** (Jackson St, Ryan Rd, Leeds, Bridge St):
  only hex centroids in the matching school district — `left_join` via
  `elementary_district_map`

District name mapping (from `school_districts$Name`):

| School | District |
|---|---|
| Jackson Street School | Jackson St |
| Robert K. Finn Ryan Road Elementary School | Ryan Rd |
| Leeds Elementary School | Leeds |
| Bridge St School | Bridge St |

Self-loops and NA rows are filtered from `od_matrix`.

### Assignment (lines 183–208)

Unweighted run (PSL, cost = `.length`) is implemented and validated.
Results visualized via `mapview` filtered to edges with positive flow,
joined back to `stress` geometry via the `edge` identifier key.

```r
result_unweighted <- run_assignment(stress_graph, od_matrix,
                                    cost.column = ".length",
                                    method = "PSL")
```

The flow-to-geometry join uses `stress_graph$edge` (which references
original `stress` row indices) rather than positional alignment, to
guard against row-count differences introduced by `create_undirected_graph`.

## Key Design Decisions

- **PSL over AoN**: Path-Sized Logit distributes flow across multiple
  plausible routes, penalizing overlapping alternatives. Produces smoother,
  more realistic flows than All-or-Nothing. AoN was validated first;
  method switched to PSL after confirming plausible results.
- **Undirected graph**: bike streets are bidirectional.
- **Flow weight = `people_count`**: routes represent actual population,
  not equal-weighted zones.
- **Elementary schools district-filtered**: only residents within a
  school's catchment area are routed to that school.

## Next Steps

### 1. LTS-weighted run

Add a cost column to `stress_graph` and re-run assignment. Proposed
cost function (step function, most faithful to LTS categorical meaning):

```r
stress_graph <- stress_graph |>
  mutate(lts_cost = case_when(
    LTS <= 2 ~ .length,
    LTS == 3 ~ 5 * .length,
    LTS == 4 ~ 10 * .length
  ))

result_lts <- run_assignment(stress_graph, od_matrix,
                             cost.column = "lts_cost",
                             method = "PSL")
```

Alternative cost functions considered:
- Linear: `LTS * .length` (LTS 4 = 4× penalty)
- Quadratic: `LTS^2 * .length` (LTS 4 = 16× penalty)
- Step function (recommended): treats LTS 1–2 as acceptable, 3–4 as avoided

### 2. Flow comparison

```r
flow_delta <- result_lts$final_flows - result_unweighted$final_flows
# Large negative values = infrastructure candidates
```

Join `flow_delta` to street geometry (via `edge` key) and map.

### 3. Future extensions

- Additional destinations (downtown, parks, transit stops)
- Quarto document for shareable report
- Tune step-function multipliers based on results
