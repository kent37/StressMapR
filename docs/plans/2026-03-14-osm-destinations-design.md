# Design: OSM Destinations for Routing Analysis

**Date:** 2026-03-14
**Script:** GetDestinations.R (new file)

## Goal

Fetch non-school destinations for the bicycle routing analysis and integrate
them into the OD matrix in `ExploreRoutes.R`. Destinations cover two categories:
civic POIs (libraries, hospital, city hall) and business district representative
intersection points (downtown Northampton and Florence village center).

## Approach

Hybrid: OSM queries for named civic amenities + hardcoded coordinates for
business district intersections. Business district points require human judgment
about which intersections best represent each district — OSM commercial zone
polygons don't capture this well.

## Outputs

`data/destinations.gpkg` — sf POINT object with columns:
- `name`: human-readable label
- `type`: `"civic"` or `"business_district"`
- geometry (EPSG:4326)

## Data Sources

### Civic POIs — osmdata

Query `amenity` tags within the Northampton bounding box:

| Name | amenity tag |
|---|---|
| Forbes Library | library |
| Lilly Library | library |
| Cooley Dickinson Hospital | hospital |
| Northampton City Hall | townhall |

Filter by name to avoid picking up other libraries/hospitals in the bbox.

### Business District Points — hardcoded tribble

Representative intersections (coordinates to be looked up from OSM/Google):

| name | district |
|---|---|
| Main & King St | Downtown |
| Main & Center St | Downtown |
| Main & State St | Downtown |
| Main & Maple St | Florence |
| Main & Chestnut St | Florence |

## Integration in ExploreRoutes.R

1. Load `data/destinations.gpkg`
2. Add `dest_node` column via `st_nearest_feature` against `stress_nodes`
3. Build `od_destinations`: `cross_join` with `hex_centers` (all origins, no district filtering)
4. Bind into `od_matrix` alongside `od_secondary` and `od_elementary`

## Routing

All hex centroids are valid origins for all destinations (no geographic filtering).
Flow weight = `people_count` at each hex centroid, same as schools.
