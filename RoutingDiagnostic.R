
# Diagnostic for error "20 OD-pairs have zero or non-finite flow values and will be skipped..."
library(igraph)

# Build the same igraph run_assignment uses internally
g <- graph_from_data_frame(stress_graph[, c("from", "to", "id")], directed = FALSE)
components <- components(g)

# Which od_matrix nodes are not in the giant component?
giant <- which(components$membership == which.max(components$csize))
problem_nodes <- od_matrix |> 
    filter(!from %in% giant | !to %in% giant) |>
    (\(x) unique(c(x$from, x$to)))()  

# Street segments connected to isolated nodes 
isolated_edges <- stress |>                               
  filter(id %in% (stress_graph |>
    filter(from %in% problem_nodes | to %in% problem_nodes) |>
    pull(id)))

# Affected origins and destinations
affected_hexes   <- hex_centers    |> filter(hex_node    %in% problem_nodes)
affected_schools <- public_schools |> filter(school_node %in% problem_nodes)

mapview(isolated_edges, color = "red", lwd = 3,  layer.name = "Isolated segments") +
mapview(affected_hexes, col.regions = "orange", layer.name = "Affected hex centroids") +
mapview(affected_schools, col.regions = "blue",  layer.name = "Affected schools")
sum(affected_hexes$people_count) #157
