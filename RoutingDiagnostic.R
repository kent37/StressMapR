
# Diagnostic for error "xx OD-pairs have zero or non-finite flow values and will be skipped..."
library(igraph)

# Build the same igraph run_assignment uses internally
g <- graph_from_data_frame(stress_graph[, c("from", "to", "id")], directed = FALSE)
components <- components(g)

# Which od_matrix nodes are not in the giant component?
giant <- which(components$membership == which.max(components$csize))
giant_nodes <- as.integer(names(giant))
problem_nodes <- od_matrix |>
    filter(!from %in% giant_nodes | !to %in% giant_nodes) |>
    (\(x) unique(c(x$from, x$to)))() |>
    (\(x) x[!x %in% giant_nodes])()  

# Street segments connected to isolated nodes 
isolated_edges <- stress |>                               
  filter(id %in% (stress_graph |>
    filter(from %in% problem_nodes | to %in% problem_nodes) |>
    pull(id)))

# Affected origins and destinations
affected_hexes   <- hex_centers    |> filter(hex_node    %in% problem_nodes)
affected_schools <- public_schools |> filter(school_node %in% problem_nodes)

mapview(isolated_edges, color = "red", lwd = 3,  layer.name = "Isolated segments") +
mapview(affected_hexes, col.regions = "orange", layer.name = "Affected hex centroids")
sum(affected_hexes$people_count) #7

# Map all street segments colored by connected component
giant_comp <- which.max(components$csize)

stress_components <- stress_graph |>
  mutate(comp = components$membership[match(from, as.integer(V(g)$name))],
         comp_label = if_else(comp == giant_comp, "Giant", paste0("C", comp))) |>
  left_join(stress |> select(id, geom), by = "id") |>
  st_as_sf()

small_labels <- sort(unique(stress_components$comp_label[stress_components$comp_label != "Giant"]))
n_small      <- length(small_labels)
small_colors <- RColorBrewer::brewer.pal(max(3, min(n_small, 12)), "Set3") |>
  rep_len(n_small)
comp_colors  <- c(small_colors, "#aaaaaa") |>
  setNames(c(small_labels, "Giant"))

mapview(stress_components |> filter(comp_label == "Giant"),
        color = "#aaaaaa", lwd = 2, layer.name = "Giant component") +
mapview(stress_components |> filter(comp_label != "Giant"),
        zcol = "comp_label", color = small_colors,
        lwd = 2, layer.name = "Small components")

# Verify that path_costs equals sum of .length for each path's segments.
# paths[[i]] contains row indices into stress_graph; path_costs[i] is the
# total cost (sum of .length) that run_assignment computed for that path.
seg_lengths <- as.numeric(stress_graph$.length)

path_length_sums <- 
  map_dbl(result_unweighted$paths, \(segs) sum(seg_lengths[segs]))

diff <- path_length_sums - result_unweighted$path_costs
cat("Paths checked:         ", length(diff), "\n")
cat("Max absolute diff (m): ", max(abs(diff)), "\n")
cat("All match (tol 1e-6):  ", all(abs(diff) < 1e-6), "\n")
