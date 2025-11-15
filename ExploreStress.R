# Load required libraries
library(tidyverse)
library(leaflet)
library(sf)

# Load the StressMap and Potential for everyday biking data
stress <- read_sf("../StressMap/plots/Northampton_LTS.gpkg", 
                  layer="Northampton")

potential <- read_sf("../StressMap/plots/Northampton_LTS.gpkg", 
                  layer="Potential for everyday biking") |> 
  st_zm() |> # Drop M dimension
  st_transform(st_crs(stress))

# Define color mapping for Potential values
potential_colors <- list(
  "High" = "#1a9641",
  "Medium" = "#f0de11",
  "Low" = "#f0111f"
)

# Define color mapping for LTS values
lts_colors <- list(
  "1" = "#0076be",
  "2" = "#a4fc3c",
  "3" = "#fb7e21",
  "4" = "#c50605"
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

# Create leaflet map
map <- leaflet(width='796px', height='700px') %>%
  addTiles()

# Add each Potential value as a separate layer
for (potential_value in c("High", "Medium", "Low")) {
  potential_data <- potential %>% filter(Potential == potential_value)

  if (nrow(potential_data) > 0) {
    map <- map %>%
      addPolylines(
        data = potential_data,
        color = potential_colors[[potential_value]],
        weight = 6,
        opacity = 0.8,
        group = paste("Potential:", potential_value)
      )
  }
}

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
        group = paste("LTS", lts_value),
        label = lapply(list(label_html), htmltools::HTML)
      )
  }
}

# Add layer control and set initial visibility
map <- map %>%
  addLayersControl(
    overlayGroups = c("Potential: High", "Potential: Medium", "Potential: Low",
                      "LTS 1", "LTS 2", "LTS 3", "LTS 4"),
    options = layersControlOptions(collapsed = FALSE)
  ) %>%
  hideGroup(c("Potential: Medium", "Potential: Low", "LTS 1", "LTS 2"))

# Display the map

#map
