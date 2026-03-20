library(flownet)
library(collapse)
library(sf)
africa_net <- fsubset(africa_network, !add, -add)
graph <- st_drop_geometry(africa_net)
nodes <- nodes_from_graph(graph, sf = TRUE)
nearest_nodes <- nodes$node[st_nearest_feature(africa_cities_ports, nodes)]
od_mat <- outer(africa_cities_ports$population, africa_cities_ports$population) / 1e12
dimnames(od_mat) <- list(nearest_nodes, nearest_nodes)
od_matrix_long <- melt_od_matrix(od_mat)

result <- run_assignment(graph, od_matrix_long, cost.column = "duration",
nthreads=4,
method = "PSL", return.extra = "all")

rlang::last_trace()
