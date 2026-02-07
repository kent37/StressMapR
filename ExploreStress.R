# Load required libraries
library(tidyverse)
library(leaflet)
library(leafem)
library(sf)

# Load the StressMap and Potential for everyday biking data
stress <- read_sf("../StressMap/plots/Northampton_LTS.gpkg", 
                  layer="Northampton")

potential <- read_sf("../StressMap/plots/Northampton_LTS.gpkg", 
                  layer="Potential for everyday biking") |> 
  st_zm() |> # Drop M dimension
  st_transform(st_crs(stress))

isochrones <- read_sf(here::here('isochrones.gpkg'), 
         layer='isochrones')

# Define color mapping for Potential values (continuous viridis palette)
# Use quantile-based coloring to handle skewed distribution
potential_pal <- colorQuantile(
  palette = "viridis",
  domain = potential$biking_pot,
  n = 10  # Divide into 10 quantile bins
)

# Define color mapping for LTS values
lts_colors <- list(
  "1" = "#0076be",
  "2" = "#a4fc3c",
  "3" = "#fb7e21",
  "4" = "#c50605"
)

iso_colors <- list(
#  "Northampton" = '#483D8B',
  "Northampton" = '#7B68EE',
  "Florence" = '#7B68EE'
)

iso_dashes <- list(
#  "Northampton" = "5 4 1 4 ",
  "Northampton" = "4 4 ",
  "Florence" = "4 4"
)

# Define emoji mapping for LTS values
stress_faces <- list(
  "1" = "😊",
  "2" = "🙂",
  "3" = "😟",
  "4" = "😠"
)

# Define label text for LTS values
stress_labels <- list(
  "1" = "Low Stress",
  "2" = "Moderate Stress",
  "3" = "High Stress",
  "4" = "Very High Stress"
)

# Actual routes
biking_actual_path = here::here("../Noho/Biking potential/Biking potential transparent geo.tif")
biking_actual = terra::rast(biking_actual_path)

# Create leaflet map
map <- leaflet(width='796px', height='700px') %>%
    addProviderTiles('CartoDB.Positron', group='Street')

# Add Potential layer with continuous viridis coloring
map <- map %>%
  addPolylines(
    data = potential,
    color = ~potential_pal(biking_pot),
    weight = 6,
    opacity = 0.8,
    group = "Potential for Everyday Biking",
    label = ~paste0("Biking Potential: ", round(biking_pot, 3))
  )

# Add each LTS value as a separate layer
for (lts_value in 1:4) {
  lts_data <- stress %>% filter(LTS == lts_value)

  if (nrow(lts_data) > 0) {
    # Create HTML label with emoji and text
    label_html <- sprintf(
      '<div style="text-align: center; font-family: Arial, sans-serif;">
        <span style="font-size: 18px; margin-bottom: 4px;">%s</span>
        <span style="margin-left: 10px; font-size: 14px; font-weight: bold;">%s</span>
      </div>',
      stress_faces[[as.character(lts_value)]],
      stress_labels[[as.character(lts_value)]]
    )

    map <- map %>%
      addPolylines(
        data = lts_data,
        color = unname(lts_colors[[as.character(lts_value)]]),
        weight = 3,
        opacity = 0.8,
        group = unname(stress_labels[[as.character(lts_value)]]),
        label = lapply(list(label_html), htmltools::HTML)
      )
  }
}

# Add isochrones
for (center_value in c("Northampton", "Florence")) {
  iso_data <- isochrones %>% filter(center == center_value)

  map <- map %>%
    addPolygons(
      data = iso_data,
      color = iso_colors[[center_value]],
      dashArray = iso_dashes[[center_value]],
      weight = 1,
      opacity = 0.8,
      fillOpacity = 0.08,
      fill = TRUE,
      group = paste("Iso:", center_value)
    )
}

# Custom pixel value function needed to get the alpha and color to 
# render properly. See
# https://github.com/GeoTIFF/georaster-layer-for-leaflet/issues/36
# https://github.com/r-spatial/leafem/issues/25
pixelValueFunction = htmlwidgets::JS(
  "
    pixelValuesToColorFn = (values) => {
      //if (values[0]>0)
        //debugger;
      return `rgba(${values[0]}, ${values[1]}, ${values[2]}, ${(values[3]/255).toFixed(2)})`;
    };
  "
)

map = map |> 
  #addMapPane('above', zIndex=450) |> 
  addGeotiff(biking_actual_path, bands=1:4, opacity=1,
             group='Actual',
             resolution=256, imagequery=FALSE,
             #options=tileOptions(pane='above'),
             pixelValuesToColorFn=pixelValueFunction)

# Add layer control and set initial visibility
map <- map %>%
  addLayersControl(
    overlayGroups = c("Potential for Everyday Biking",
                      "Actual",
                      "Iso: Northampton", "Iso: Florence",
                      unname(unlist(stress_labels))),
    options = layersControlOptions(collapsed = FALSE)
  ) %>%
  hideGroup(c("Actual",
              "Iso: Florence",
              "Low Stress", "Moderate Stress"))

# Legend
map = map |>
  addLegend(
    position = "bottomright",
    pal = potential_pal,
    values = potential$biking_pot,
    title = "Biking Potential",
    opacity = 1
  ) |>
  addLegend(
    position = "bottomright",
    opacity = 1,
    colors = c(iso_colors, '', lts_colors),
    labels = c(paste('Iso:', names(iso_colors)), '',
               unname(unlist(stress_labels)))
  )
# Display the map

#map
