# Try mapdeck
# No way to turn layers on and off...

library(mapdeck)

mapdeck() |> 
  add_path(potential |>
             mutate(color = str_to_upper(paste0(unlist(potential_colors[Potential]), 'ff'))),
           stroke_colour='color',
           stroke_width=30,
           layer_id='potential',
           legend = mapdeck_legend(legend_element(
              variables = names(potential_colors),
              colours = unlist(potential_colors),
              colour_type = "fill",
              variable_type = "category",
              title='Potential'
            ))) |>
  add_path(st_cast(isochrones, 'MULTILINESTRING')  |> 
             mutate(color = str_to_upper(paste0(unlist(iso_colors[center]), 'ff'))),
           stroke_colour='color',
           layer_id='iso',
           legend = mapdeck_legend(legend_element(
              variables = names(iso_colors),
              colours = unlist(iso_colors),
              colour_type = "fill",
              variable_type = "category",
              title='Isochrones'
            ))) |>
  add_path(stress |> 
             mutate(LTS=as.character(LTS),
                    color = str_to_upper(paste0(unlist(lts_colors[LTS]), 'ff'))), 
           stroke_width=40, stroke_colour='color', 
           layer_id='stress',
           legend = mapdeck_legend(legend_element(
              variables = paste('LTS:', names(lts_colors)),
              colours = unlist(lts_colors),
              colour_type = "fill",
              variable_type = "category",
              title='Stress'
            ))
  )

