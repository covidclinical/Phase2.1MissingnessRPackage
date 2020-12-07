
#' Runs the analytic workflow for the Missingness project
#'
#' @keywords 4CE
#' @export

runAnalysis <- function() {

    ## make sure this instance has the latest version of the quality control and data wrangling code available
    devtools::install_github("https://github.com/covidclinical/Phase2.1DataRPackage", subdir="FourCePhase2.1Data", upgrade=FALSE)

    ## get the site identifier assocaited with the files stored in the /4ceData/Input directory that
    ## is mounted to the container
    currSiteId = FourCePhase2.1Data::getSiteId()

    ## run the quality control
    FourCePhase2.1Data::runQC(currSiteId)

    ## DO NOT CHANGE ANYTHING ABOVE THIS LINE

    ## To Do: implement analytic workflow, saving results to a site-specific
    ## file to be sent to the coordinating site later via submitAnalysis()

    #SET UP
    library(ggplot2)
    library(readr)
    library(dplyr)
    library(tidyr)
    library(forcats)
    library(DT)
    library(tibble)
    library(cowplot)
    library(ggridges)
    theme_set(theme_bw() +
                  theme(legend.title = element_blank(),
                        panel.grid.minor = element_blank()))

    ## Read in files
    #and convert to wide format
    #4CE long format Labs Data
    patient_obs <- read_csv('penn-data/labs_long_thrombo_v2.csv') %>%
        mutate(severity = (severe_ind == 1) %>%
                   as_factor() %>%
                   fct_recode('nonsevere' = 'FALSE', 'severe' = 'TRUE'))
    #Code, Descriptions and Ranges
    lab_mapping <- read_csv('public-data/loinc-map.csv')
    lab_bounds <- read_csv('public-data/lab_bounds.csv')
    # load('public-data/code.dict.rda')

    patient_obs_wide <- patient_obs %>%
        left_join(lab_bounds, by = c('concept_code' = 'LOINC')) %>%
        select(- concept_code) %>%
        pivot_wider(id_cols = c(patient_num, days_since_admission, severity),
                    names_from = short_name,
                    values_from = value,
                    values_fn = mean)
    patient_obs_long <- patient_obs_wide %>%
        pivot_longer(-c(patient_num, days_since_admission, severity),
                     names_to = 'lab', values_to = 'value',
                     values_drop_na = TRUE)
    #check NAs in the Wide format
    na_stats <- patient_obs_wide %>%
        select(- c(patient_num, days_since_admission, severity)) %>%
        is.na() %>%
        `!`
    na_df <- data.frame(value_existed = colSums(na_stats),
                        prop_existed = colMeans(na_stats)) %>%
        rownames_to_column('lab') %>%
        mutate(prop_na = 1 - prop_existed,
               lab = fct_reorder(lab, value_existed))
    n_values <- na_df %>%
        ggplot(aes(x = value_existed, y = lab)) +
        geom_col() +
        labs(x = 'Number of values', y = NULL)
    na_prob <- na_df %>%
        rename('Valid value' = prop_existed, 'NA' = prop_na) %>%
        pivot_longer(c(`Valid value`, `NA`)) %>%
        ggplot(aes(x = value, y = lab, fill = name)) +
        geom_col() +
        scale_fill_discrete(guide = guide_legend(reverse = TRUE)) +
        labs(x = 'Proportion', y = NULL) +
        # guides(fill = guide_legend(reverse = TRUE))
        theme(
            axis.text.y = element_blank(),
            legend.key.width = unit(6, 'mm'),
            legend.key.height = unit(4, 'mm'),
            legend.position = 'bottom')
    plot_grid(n_values, na_prob, nrow = 1, axis = 'b', align = 'h')
    penn_na_df <- na_df

    # number of patients per lab value
    get_pat_labs <- function(labi){
        patients_labs <- patient_obs_long %>%
            filter(lab == labi) %>%
            count(patient_num) %>%
            pull(n) %>%
            hist(., breaks = seq(0, max(.), 1))
        patients_labs[[1]] <- patients_labs[[1]][-1]
        data.frame(
            do.call(cbind.data.frame, patients_labs[1:3]),
            lab = labi)
    }
    patient_lab <- lapply(unique(patient_obs_long$lab), get_pat_labs) %>%
        bind_rows()
    penn_patient_lab <- patient_lab
    melt_patient_lab <- patient_lab[rep(1:nrow(patient_lab), patient_lab$counts), ]

    melt_patient_lab %>%
        filter(breaks < 30) %>%
        mutate(lab = fct_infreq(lab)) %>%
        ggplot(aes(x = breaks, y = lab, fill = lab, height = ..count..)) +
        # geom_density_ridges(stat = "identity", scale = 2) +
        geom_ridgeline(stat="binline", binwidth=1, scale = 0.001) +
        # scale_color_viridis_d(option = 'C') +
        scale_fill_viridis_d(option = 'C', guide = FALSE) +
        labs(y = NULL) +
        # coord_flip() +
        # facet_wrap(~ lab, scales = 'free') +
        NULL

    # patient_lab %>%
    #   filter(breaks < 30) %>%
    #   mutate(lab = fct_infreq(lab)) %>%
    #   ggplot(aes(x = breaks, y = lab, fill = lab, height = sqrt(counts))) +
    #   geom_density_ridges(stat = "identity", scale = 1.5) +
    #   scale_fill_viridis_d(option = 'C', guide = FALSE) +
    #   labs(y = NULL) +
    #   scale_x_continuous(expand = expansion(0, 0)) +
    #   # coord_cartesian(xlim = c(1, NA)) +
    #   NULL


    ## Number of observation (days) per patient
    days_count_min_max <- patient_obs_wide %>%
        group_by(patient_num, severity) %>%
        summarise(
            n_values = n_distinct(days_since_admission),
            min_day = min(days_since_admission),
            max_day = max(days_since_admission),
            .groups = 'drop'
        ) %>%
        mutate(time_obs = max_day - min_day) %>%
        select(-patient_num) %>%
        add_count(severity, name = 'n_severity')
    penn_agg_n_values <- days_count_min_max %>%
        count(severity, n_severity, n_values,
              name = 'n_nvals')
    penn_agg_max_day <- days_count_min_max %>%
        count(severity, n_severity, max_day,
              name = 'n_maxday')
    (n_severe <- sum(days_count_min_max$severity == 'severe'))
    (n_nonsevere <- sum(days_count_min_max$severity == 'nonsevere'))
    save(penn_na_df, penn_agg_n_values, penn_agg_max_day, penn_patient_lab,
         file = 'results/penn-results.Rdata')


    ## Histogram of the number of days with at least one observation
    penn_agg_n_values %>%
        ggplot(aes(x = n_values, y = n_nvals, fill = severity)) +
        geom_col(alpha = 0.5) +
        scale_fill_brewer(palette = 'Dark2', direction = -1) +
        labs(fill = 'Severe?',
             x = "Number of days with data",
             y = "Count")

    ## Histogram of length of stay
    ##i.e. last day with observation-first day with observation
    ##We need to check for readmission here.
    penn_agg_max_day %>%
        ggplot(aes(x = max_day, y = n_maxday, fill = severity)) +
        geom_col(alpha = 0.5) +
        scale_fill_brewer(palette = 'Dark2', direction = -1) +
        labs(fill = 'Severe?',
             x = "Number of days with data",
             y = "Count")

    ## Analyze missingness and frequency of measures for each lab
    per_lab <- patient_obs_long %>%
        group_by(lab, patient_num, severity) %>%
        count(name = 'n_obs') %>%
        ungroup() %>%
        group_by(lab, severity) %>%
        count(n_obs) %>%
        ungroup() %>%
        pivot_wider(names_from = severity, values_from = n, values_fill = 0) %>%
        mutate(both_severities = nonsevere + severe) %>%
        mutate(prop_nonsevere = nonsevere/n_nonsevere,
               prop_severe = severe/n_severe,
               prop_both = both_severities/nrow(days_count_min_max))
    lab_medians <-
        patient_obs_long %>%
        add_count(lab, name = 'total_obs') %>%
        group_by(lab) %>%
        mutate(total_patients = length(unique(patient_num))) %>%
        add_count(patient_num, name = 'n_obs_patients') %>%
        mutate(median_obs_per_patient = median(n_obs_patients),
               n_greater0 = n_obs_patients > median_obs_per_patient,
               n_greater1 = n_obs_patients > median_obs_per_patient + 1,
               n_greater2 = n_obs_patients > median_obs_per_patient + 2) %>%
        group_by(severity) %>%
        mutate(each_med_obs_per_patient = median(n_obs_patients)) %>%
        ungroup(severity) %>%
        select(- c(days_since_admission, value)) %>%
        distinct() %>%
        group_by(lab) %>%
        mutate(across(contains('n_greater'), sum)) %>%
        select(- c(n_obs_patients, patient_num)) %>%
        distinct() %>%
        pivot_wider(names_from = severity, values_from = each_med_obs_per_patient) %>%
        rename('median_obs_per_severe_patient' = severe,
               'median_obs_per_non_severe_patient' = nonsevere) %>%
        select(lab, total_obs, total_patients, starts_with('med'), starts_with('n_'))
    lab_medians %>%
        datatable(rownames = FALSE)

    lab_medians %>%
        select(lab, total_obs, total_patients) %>%
        pivot_longer(- lab) %>%
        ggplot(aes(x = value, y = fct_reorder(lab, value))) +
        geom_col() +
        facet_grid(cols = vars(name), scales = 'free_x', space = 'free') +
        labs(y = NULL)

    # In the figure below:
    #
    # - Grey dash line: `Reference Low`
    # - Grey solid line: `Reference High`
    # - Black dash line: `lower bound outlier` (QC)
    # - Black solid line: `upper bound outlier` (QC)

    patient_obs_long %>%
        left_join(lab_bounds, by = c('lab' = 'short_name')) %>%
        ggplot(aes(y = severity, x = value, fill = severity)) +
        geom_violin() +
        scale_fill_brewer(palette = 'Dark2', guide = guide_legend(reverse = TRUE)) +
        labs(y = NULL, x = NULL) +
        geom_vline(aes(xintercept = `Reference Low`), linetype = 'dashed', color = 'grey') +
        geom_vline(aes(xintercept = `Reference High`), color = 'grey') +
        geom_vline(aes(xintercept = LB), linetype = 'dashed') +
        geom_vline(aes(xintercept = UB)) +
        facet_wrap(~ lab, scales = 'free', ncol = 2, strip.position = 'left') +
        theme(axis.text.y = element_blank())

    ## Missing data heatmap
    ##"Binned" heatmap

    per_lab %>%
        mutate(obs_bin = cut(
            n_obs,
            breaks = c(0:15, 20, 30, max(n_obs)))) %>%
        group_by(lab, obs_bin) %>%
        summarise(both_severities = sum(both_severities),
                  severe = sum(severe),
                  nonsevere = sum(nonsevere),
                  .groups = 'drop') %>%
        select(lab, obs_bin, both_severities, severe, nonsevere) %>%
        pivot_longer(c(both_severities, severe, nonsevere)) %>%
        mutate(name = name %>% fct_recode(
            'All patients' = 'both_severities',
            'Severe patients' = 'severe',
            'Non-severe patients' = 'nonsevere'
        )) %>%
        ggplot(aes(x = obs_bin, fill = value, y = fct_reorder(lab, value))) +
        geom_tile(colour = "white", size = 0.2) +
        geom_text(aes(label = value), colour = "white", size = 2) +
        scale_y_discrete(expand = c(0, 0))+
        scale_fill_gradient(low = "lightgrey", high = "darkblue") +
        facet_wrap(~ name, nrow = 1) +
        labs(x = 'Binned number of values a patient has for each lab',
             y = NULL, fill = '# patients') +
        theme(panel.grid.major = element_blank(),
              legend.position = c(0.93, 0.2),
              axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5),
              axis.ticks.y = element_blank()
        )

    per_lab %>%
        mutate(obs_bin = cut(n_obs, breaks = c(0:15, 20, 30, max(n_obs)))) %>%
        group_by(lab, obs_bin) %>%
        summarise(prop_both = sum(prop_both),
                  prop_severe = sum(prop_severe),
                  prop_nonsevere = sum(prop_nonsevere),
                  .groups = 'drop') %>%
        select(lab, obs_bin, prop_both, prop_severe, prop_nonsevere) %>%
        pivot_longer(c(prop_both, prop_severe, prop_nonsevere)) %>%
        mutate(name = name %>% fct_recode(
            'Compared to all patients' = 'prop_both',
            'Compared to all severe patients' = 'prop_severe',
            'Compared to all non-severe patients' = 'prop_nonsevere'
        )) %>%
        ggplot(aes(x = obs_bin, fill = value, y = fct_reorder(lab, value))) +
        geom_tile(colour = "white", size = 0.2) +
        geom_text(aes(label = round(value, 2)), colour = "white", size = 2) +
        scale_y_discrete(expand = c(0, 0)) +
        scale_fill_gradient(low = "lightgrey", high = "darkblue",
                            labels = scales::percent_format(accuracy = 1L)) +
        facet_wrap(~ name, nrow = 1) +
        labs(x = 'Binned number of values a patient has for each lab',
             y = NULL, fill = '% patients') +
        theme(panel.grid.major = element_blank(),
              legend.position = c(0.93, 0.2),
              axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5),
              axis.ticks.y = element_blank()
        )

    ### Denominator: total number of patients, total number of non-severe patients,
    and total number of severe patients, respectively.

    per_lab %>%
        select(lab, n_obs, severe, nonsevere) %>%
        filter(n_obs <= 90) %>%
        pivot_longer(c(severe, nonsevere)) %>%
        mutate(lab = fct_reorder(lab, n_obs),
               name = name %>% fct_recode(
                   'Severe patients' = 'severe',
                   'Non-severe patients' = 'nonsevere'
               )) %>%
        ggplot(aes(x = n_obs, fill = name, y = value)) +
        geom_col() +
        scale_fill_brewer(palette = 'Dark2', direction = -1) +
        facet_wrap(~ lab, scales = 'free') +
        labs(x = 'Number of values a patient has for each lab',
             y = NULL, fill = '# patients') +
        theme(panel.grid.major = element_blank(),
              legend.position = c(0.9, 0.2),
              axis.ticks.y = element_blank()
        )

    ## Save results to appropriately named files for submitAnalysis(), e.g.:
    #write.csv(
    #    matrix(rnorm(100), ncol=5),
    #    file=file.path(getProjectOutputDirectory(), paste0(currSiteId, "_ResultTable.csv"))
    #)

    #write.table(
    #    matrix(rnorm(12), ncol=3),
    #    file=file.path(getProjectOutputDirectory(), paste0(currSiteId, "_ModelParameters.txt"))
    #)

}
