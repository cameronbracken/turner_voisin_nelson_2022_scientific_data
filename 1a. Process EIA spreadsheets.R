## 1. Process raw EIA spreadsheets EIA-923, EIA-906/920
## Author: Sean Turner sean.turner@pnnl.gov
## EIA downloaded from: https://www.eia.gov/electricity/data/eia923/ (2022-03-17)
## Hydrosource data downloaded from https://hydrosource.ornl.gov/dataset/EHA2021 (2022-03-17)

## 2023 1.2.1 Update - Cameron Bracken cameron.bracken@pnnl.gov
##   EIA downloaded from: https://www.eia.gov/electricity/data/eia923/ (2023-10-04)
##   Hydrosource data downloaded from https://hydrosource.ornl.gov/dataset/EHA2023 (2023-08-17)
## 2024 1.3.0 Update - Cameron Bracken cameron.bracken@pnnl.gov
##   As of May 2024, 2023 EIA data is not yet finalized and much is missing, so it cant be used


library(readxl) # read data from excel spreadsheets
library(tidyverse) # data wrangling
import::from(janitor, clean_names)

options(
  readr.show_progress = FALSE,
  readr.show_col_types = FALSE,
  pillar.width = 1e6
)

# Use HydroSource EHA (2021) to identify desired EIA_IDs
eha <- list(
  `2021` = "Data/ORNL_EHAHydro_Plant_FY2021/ORNL_EHAHydroPlant_FY2021_revised.xlsx",
  `2022` = "Data/ORNL_EHAHydro_Plant_FY2022/ORNL_EHAHydro_Plant_FY2022.xlsx",
  `2023` = "Data/ORNL_EHAHydro_Plant_FY2023_rev/ORNL_EHAHydroPlant_FY2023_rev.xlsx"
)
read_xlsx(eha[["2023"]], sheet = "Operational") %>%
  select(EHA_PtID, plant = PtName, eia_id = EIA_PtID, State, CH_MW) %>%
  mutate(eia_id = as.integer(eia_id)) %>%
  # filter for plants with known EIA ID
  filter(!is.na(eia_id)) %>%
  filter(!eia_id %in% (. |> filter(duplicated(eia_id)) |> pull(eia_id))) ->
hydrosource_EIA

EIA_IDs_desired <- hydrosource_EIA[["eia_id"]] %>% unique()

2001:2022 %>%
  map_dfr(function(yr) {
    message(yr)

    if (yr %in% 2001:2002) {
      file_name <- paste0("Data/EIA-923/f906920_", yr, "/f906920_", yr, ".xls")

      # read EIA file
      read_xls(file_name, skip = 7) %>%
        rename(eia_id = `Plant ID`) %>%
        mutate(eia_id = as.integer(eia_id)) -> EIA_data

      # filter EIA file for hydro
      EIA_data %>%
        filter(
          eia_id %in% EIA_IDs_desired,
          `AER Fuel Type Code` == "HYC"
        ) %>%
        select(
          eia_id, contains("Netgen"),
          `NET GENERATION (megawatthours)`
        ) %>%
        clean_names() -> EIA_hydro

      # fix col names
      names(EIA_hydro) <- names(EIA_hydro) %>% substr(1, 10)

      # make netgen numeric and add frequency of reporting "true_monthly?"
      return(
        tibble(eia_id = EIA_IDs_desired) %>%
          left_join(EIA_hydro, by = "eia_id") %>%
          mutate_if(is.character, as.numeric) %>%
          mutate(
            freq = NA_character_,
            year = !!yr
          )
      )
    }


    if (yr %in% 2003:2007) {
      file_name <- paste0("Data/EIA-923/f906920_", yr, "/f906920_", yr, ".xls")

      # read EIA file
      read_xls(file_name, skip = 7) %>%
        rename(eia_id = `Plant ID`) ->
      EIA_data

      # filter EIA file for hydro
      EIA_data %>%
        select(eia_id, contains("Netgen"),
          type = contains("mover"),
          `NET GENERATION (megawatthours)`
        ) %>%
        filter(eia_id %in% EIA_IDs_desired, type == "HY") %>%
        select(-type) %>%
        clean_names() -> EIA_hydro

      # fix col names
      names(EIA_hydro) <- names(EIA_hydro) %>% substr(1, 10)

      # make netgen numeric and add frequency of reporting "true_monthly?"
      return(
        tibble(eia_id = EIA_IDs_desired) %>%
          left_join(EIA_hydro, by = "eia_id") %>%
          mutate_if(is.character, as.numeric) %>%
          mutate(
            freq = NA_character_,
            year = !!yr
          )
      )
    }

    if (yr %in% 2008:2023) {
      if (yr %in% 2008:2010) {
        file_name <- paste0("Data/EIA-923/f923_", yr, "/EIA923 SCHEDULES ", yr, ".xls")
        read_xls(file_name, skip = 7) %>%
          rename(eia_id = `Plant ID`) ->
        EIA_data

        EIA_rep_freq <- tibble(eia_id = EIA_IDs_desired, freq = NA_character_)
      }

      if (yr %in% 2011:2020) {
        file_name <- paste0("Data/EIA-923/f923_", yr, "/EIA923 SCHEDULES ", yr, ".xlsx")
        read_xlsx(file_name, skip = 5, guess_max = 10e5) %>%
          rename(eia_id = `Plant Id`) ->
        EIA_data

        if (yr %in% c(2011, 2013)) {
          id_col_name <- "EIA Plant Id"
          rf_name <- "Reporting Frequency (Annual Or Monthly)"
        }
        if (yr %in% c(2012, 2014:2019)) {
          id_col_name <- "Plant Id"
          rf_name <- "Reporting\r\nFrequency"
        }
        if (yr == 2020) {
          id_col_name <- "Plant Id"
          rf_name <- "Respondent\r\nFrequency"
        }

        read_xlsx(file_name, skip = 4, sheet = "Page 6 Plant Frame") %>%
          select(
            eia_id = one_of(id_col_name),
            freq = one_of(rf_name)
          ) ->
        EIA_rep_freq
      }


      if (yr %in% 2021:2022) {
        file_name <- switch(as.character(yr),
          `2021` = paste0("Data/EIA-923/f923_", yr, "/EIA923_Schedules_2_3_4_5_M_12_2021_Final_Revision.xlsx"),
          `2022` = paste0("Data/EIA-923/f923_", yr, "/EIA923_Schedules_2_3_4_5_M_12_2022_Final.xlsx")
        )
        read_xlsx(file_name, skip = 5, guess_max = 10e5) %>%
          rename(eia_id = `Plant Id`) ->
        EIA_data

        id_col_name <- "Plant Id"
        rf_name <- "Respondent\r\nFrequency"

        read_xlsx(file_name, skip = 4, sheet = "Page 6 Plant Frame") %>%
          select(
            eia_id = one_of(id_col_name),
            freq = one_of(rf_name)
          ) ->
        EIA_rep_freq
      }

      if (yr %in% 2023) {
        file_name <- "Data/EIA-923/EIA923_Schedules_2_3_4_5_M_12_2023_22FEB2024.xlsx"
        read_xlsx(file_name, skip = 5, guess_max = 10e5) %>%
          rename(eia_id = `Plant Id`) ->
        EIA_data

        id_col_name <- "Plant Id"
        rf_name <- "Reporting\r\nFrequency"

        read_xlsx(file_name, skip = 3, sheet = "Page 6 Plant Frame") %>%
          select(
            # month = MONTH,
            eia_id = one_of(id_col_name),
            freq = one_of(rf_name)
          ) %>%
          # 2023 has monthly values
          distinct(eia_id, .keep_all = T) ->
        EIA_rep_freq

        # check if all monthly reporting frequencies are the same, they are in 2023
        # EIA_rep_freq |>
        #   group_by(eia_id) |>
        #   summarise(all_same = (length(unique(freq)) == 1)) |>
        #   filter(!all_same)
      }

      # filter EIA file for hydro
      EIA_data %>%
        clean_names() %>%
        select(eia_id, contains("netgen"),
          type = contains("mover"),
          net_generation_megawatthours
        ) %>%
        filter(eia_id %in% EIA_IDs_desired, type == "HY") %>%
        select(-type) -> EIA_hydro

      # fix col names
      names(EIA_hydro) <- names(EIA_hydro) %>% substr(1, 10)

      if (yr %in% 2022:2023) {
        EIA_hydro %>%
          mutate_if(is.character, function(x) as.numeric(gsub("^\\.", "", x))) %>%
          group_by(eia_id) %>%
          summarise(across(starts_with("net"), function(x) sum(x, na.rm = T))) ->
        EIA_hydro
      }
      # make netgen numeric and add frequency of reporting "true_monthly?"
      return(
        tibble(eia_id = EIA_IDs_desired) %>%
          left_join(EIA_hydro, by = "eia_id") %>%
          # some years put a period in cells where there is no data, so replace it
          # before converting to numeric to avoid warnings
          mutate_if(is.character, function(x) as.numeric(gsub("^\\.", "", x))) %>%
          left_join(EIA_rep_freq, by = "eia_id") %>%
          mutate(year = !!yr)
      )
    }
  }) -> EIA_hydro_netgen_and_freq

# CB added this to prevent a many-to-many join, hydrosource has some plants with the same eia_id,
# they are mostly small plants outside of the WECC, so we'll remove them. There is probably
# a better way to handle this. will this cause issues elsewhere?
eha_exclude <- hydrosource_EIA |>
  count(eia_id) |>
  filter(n > 1) |>
  pull(eia_id)
# hydrosource_EIA |> filter(eia_id %in% eha_exclude) |> print(n=100)

# check that annual totals correspond to reported annual
EIA_hydro_netgen_and_freq %>%
  mutate(
    netgen_total = netgen_jan + netgen_feb +
      netgen_mar + netgen_apr + netgen_may +
      netgen_jun + netgen_jul + netgen_aug +
      netgen_sep + netgen_oct + netgen_nov + netgen_dec
  ) %>%
  ggplot(aes(net_genera, netgen_total)) +
  geom_point() +
  facet_wrap(~year) +
  scale_x_continuous(trans = "log10") +
  scale_y_continuous(trans = "log10") +
  geom_abline(slope = 1)

month_num <- 1:12 |> `names<-`(tolower(month.abb))

eia_long <- EIA_hydro_netgen_and_freq |>
  select(eia_id, year, starts_with("netgen"), -net_genera) |>
  pivot_longer(-c(eia_id, year), names_to = c("blah", "month"), names_sep = "_") |>
  select(-blah) |>
  mutate(month = month_num[month]) |>
  mutate(value = ifelse(value < 0, NA, value)) |>
  left_join(hydrosource_EIA, by = join_by(eia_id)) |>
  mutate(hours_per_month = 24 * days_in_month(fast_strptime(paste0(year, "-", month, "-", 1), "%Y-%m-%d"))) |>
  mutate(EIA_MW = value / hours_per_month) |>
  # any month with average gen exceeding the nameplate
  # by more than 5%, set those months to NA, its around 1% of points
  mutate(value = ifelse(EIA_MW > 1.05 * CH_MW, NA, value)) |>
  # ensure no duplicates
  distinct(eia_id, year, month, .keep_all = T)


# find eia plants with less than 12 months of data, exclude those
eia_exclude1 <- eia_long |>
  na.omit() |>
  group_by(eia_id) |>
  count() |>
  filter(n < 12) |>
  pull(eia_id)
# find eia plants with no data, exclude those too
eia_exclude2 <- eia_long |>
  group_by(eia_id) |>
  summarise(all_na = all(is.na(value))) |>
  filter(all_na) |>
  pull(eia_id) |>
  unique()

# put back into monthly columns, add metadata
eia_wide <- eia_long |>
  mutate(month = month.abb[month]) |>
  pivot_wider(id_cols = c(eia_id, year), names_from = month, values_from = value) |>
  filter(!(eia_id %in% c(eha_exclude, eia_exclude1, eia_exclude2))) |>
  group_by(eia_id, year) |>
  arrange(eia_id, year) |>
  # add back in the frequency
  left_join(
    EIA_hydro_netgen_and_freq |>
      select(eia_id, year, freq, net_genera),
    by = join_by(eia_id, year)
  ) |>
  mutate(net_genera = ifelse(net_genera < 0, NA, net_genera)) |>
  # fill in missing annual values with the sum of monthly
  mutate(netgen_annual = ifelse(is.na(net_genera),
    Jan + Feb + Mar + Apr + May + Jun + Jul + Aug + Sep + Oct + Nov + Dec,
    net_genera
  )) |>
  select(-net_genera) |>
  left_join(hydrosource_EIA, by = "eia_id") |>
  rename(
    state = State, nameplate_MW = CH_MW
  ) |>
  # ensure no duplicates
  distinct(eia_id, year, .keep_all = T) |>
  relocate(eia_id, EHA_PtID, year, plant, state, nameplate_MW, freq, netgen_annual)

eia_wide |>
  readr::write_csv("Output_1_EIA_MWh.csv")

###############################
# diagnostics, uncomment to use
###############################

# EIA_hydro_netgen_and_freq %>%
#   filter(!(eia_id == 3437 & netgen_jan == 0)) %>%
#   count(year, freq) %>%
#   bind_rows(tibble(
#     year = rep(2001:2011, each = 2),
#     freq = rep(c("A", "M"), 11),
#     n = 0
#   ))
# #
# hydrosource_EIA %>%
#   count(State) %>%
#   arrange(-n) %>%
#   .[["State"]] %>%
#   .[1:20] -> states_with_most_plants
#
# hydrosource_EIA %>%
#   group_by(State) %>%
#   summarise(x = sum(CH_MW, na.rm = T)) %>%
#   arrange(-x) %>%
#   .[["State"]] %>%
#   .[1:50] -> states_with_most_cap
# #
# #
# EIA_hydro_netgen_and_freq %>%
#   filter(year > 2013) %>%
#   mutate(freq = if_else(freq == "AM" | freq == "AM/A", "A", freq)) %>%
#   left_join(hydrosource_EIA, by = "eia_id", relationship = "many-to-many") %>%
#   count(year, State, freq) %>%
#   filter(State %in% states_with_most_cap) %>%
#   ggplot(aes(year, n, fill = freq)) +
#   geom_bar(stat = "identity") +
#   facet_wrap(~State, scales = "free_y")
#
# # check reporting frequency
# EIA_hydro_netgen_and_freq %>%
#   filter(year > 2013) %>%
#   mutate(freq = if_else(freq == "AM" | freq == "AM/A", "A", freq)) %>%
#   left_join(hydrosource_EIA, by = "eia_id", relationship = "many-to-many") %>%
#   group_by(State, year, freq) %>%
#   summarise(cap = sum(CH_MW), .groups = "drop") %>%
#   filter(State %in% states_with_most_cap) %>%
#   ggplot(aes(year, cap, fill = freq)) +
#   geom_bar(stat = "identity") +
#   facet_wrap(~State, scales = "free_y")
# #
# # check for annual capacity
# EIA_hydro_netgen_and_freq %>%
#   filter(year > 2013) %>%
#   mutate(
#     netgen_total = netgen_jan + netgen_feb +
#       netgen_mar + netgen_apr + netgen_may +
#       netgen_jun + netgen_jul + netgen_aug +
#       netgen_sep + netgen_oct + netgen_nov + netgen_dec
#   ) %>%
#   select(netgen_total, eia_id, freq, year) %>%
#   left_join(hydrosource_EIA, by = join_by(eia_id), relationship = "many-to-many") %>%
#   # count(year, freq) %>%
#   group_by(year, freq) %>%
#   summarise(x = sum(CH_MW, na.rm = T), .groups = "drop") %>%
#   mutate(xx = x / sum(x)) %>%
#   filter(freq == "M")
# #
# # Check for complete years
# EIA_hydro_netgen_and_freq %>%
#   filter(year > 2013) %>%
#   mutate(
#     netgen_total = netgen_jan + netgen_feb +
#       netgen_mar + netgen_apr + netgen_may +
#       netgen_jun + netgen_jul + netgen_aug +
#       netgen_sep + netgen_oct + netgen_nov + netgen_dec
#   ) %>%
#   select(netgen_total, eia_id, freq, year) %>%
#   filter(!is.na(netgen_total)) %>%
#   count(eia_id)
