# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

StressMapR is an R-based project for visualizing bicycle Level of Traffic Stress (LTS) data in Northampton, MA. It creates interactive maps showing:
- Level of Traffic Stress (LTS) ratings (1-4, from low to high stress)
- Potential for Everyday Biking data from MassGIS
- Actual bike routes from Ride with GPS (transparent GeoTIFF overlay)
- Isochrones (5, 12, 20-minute biking distances) from downtown Northampton and Florence

The project uses Leaflet for interactive web maps and can render to standalone HTML files via Quarto.

## Key Dependencies

- **tidyverse**: Data manipulation
- **sf**: Spatial data handling
- **leaflet**: Interactive mapping
- **leafem**: Advanced Leaflet features (especially `addGeotiff()` for raster overlays)
- **terra**: Raster data handling
- **openrouteservice**: Isochrone generation (rate-limited: 20/min, 500/day)
- **mapview**: Quick spatial data viewing

## Data Sources

The project depends on external data files:
- `../StressMap/plots/Northampton_LTS.gpkg`: Contains two layers
  - "Northampton": LTS ratings for street segments
  - "Potential for everyday biking": Potential ratings (High/Medium/Low)
- `isochrones.gpkg`: Pre-computed isochrones (layer: 'isochrones')
- `../Noho/Biking potential/Biking potential transparent geo.tif`: Actual bike routes raster

## Core Scripts

- **ExploreStress.R**: Main visualization script that creates the Leaflet map with all layers
  - Defines color schemes for LTS (blue to red), Potential (green/yellow/red), and isochrones
  - Includes custom `pixelValueFunction` for proper GeoTIFF alpha channel rendering
  - Sets up layer controls with initial visibility settings
- **Make_isochrones.R**: Generates isochrones using OpenRouteService API
  - Processes access points one at a time due to API rate limits
  - Creates 5, 12, and 20-minute biking time isochrones
  - Saves results to `isochrones.gpkg`
- **BikeStressMap.qmd**: Quarto document that sources ExploreStress.R and renders to HTML
  - Produces standalone HTML with embedded resources
  - Adds fullscreen control to the map
- **ExploreMapdeck.R**: Experimental mapdeck visualization (lacks layer toggle functionality)

## Rendering the Map

To render the standalone HTML map:
```r
quarto::quarto_render("BikeStressMap.qmd")
```

Or from the command line:
```bash
quarto render BikeStressMap.qmd
```

Output: `BikeStressMap.html`

## Interactive Development

To work interactively with the map:
```r
source("ExploreStress.R")
map  # View the map in RStudio Viewer or browser
```

## Important Implementation Details

### GeoTIFF Alpha Channel Rendering
The raster overlay requires a custom `pixelValueFunction` (JavaScript) to properly render RGBA values from the 4-band GeoTIFF. This is defined in ExploreStress.R:67-144 and is necessary due to georaster-layer-for-leaflet limitations.

### Color Schemes
All color schemes are defined as named lists at the top of ExploreStress.R:
- `lts_colors`: Blue (#0076be) for LTS 1 to red (#c50605) for LTS 4
- `potential_colors`: Green (#1a9641) = High, Yellow (#f0de11) = Medium, Red (#f0111f) = Low
- `iso_colors` and `iso_dashes`: Purple (#7B68EE) with dashed lines for isochrones

### Layer Management
Initial visibility is controlled via `hideGroup()` in ExploreStress.R:163-166. By default, these layers are hidden:
- Potential: Medium, Low
- Actual routes
- Florence isochrones
- LTS: Low Stress, Moderate Stress

## Regenerating Isochrones

If you need to regenerate isochrones (e.g., for new locations):
```r
source("Make_isochrones.R")
```

Note: This is slow due to OpenRouteService rate limits (20 requests/min).

## Project Structure

This is an RStudio project (.Rproj) configured with:
- 2 spaces for tabs
- UTF-8 encoding
- knitr for R Markdown
