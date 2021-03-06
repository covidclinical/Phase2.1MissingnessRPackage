
#' Runs the analytic workflow for the Missingness project
#'
#' @keywords 4CE
#' @export

runAnalysis <- function( dir.output ) {

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
    ggplot2::theme_set(ggplot2::theme_bw() +
                  ggplot2::theme(legend.title = ggplot2::element_blank(),
                        panel.grid.minor = ggplot2::element_blank()))

    ## Read in files
    #and convert to wide format
    #4CE long format Labs Data
    dir.input=FourCePhase2.1Data::getInputDataDirectoryName()

    patient_obs <- readr::read_csv( paste0( dir.input, '/LocalPatientObservations.csv'))
    patient_obs <- patient_obs[ patient_obs$concept_type == "LAB-LOINC" &
                                    patient_obs$days_since_admission >= 0,]

    severity <- readr::read_csv( paste0( dir.input, '/LocalPatientClinicalCourse.csv'))
    severity <- severity[ , c("patient_num", "days_since_admission", "severe")]
    colnames( severity ) <- c("patient_num", "days_since_admission", "severity")
    patient_obs <- dplyr::full_join( patient_obs, severity)

    patient_obs$severity <- as.factor( ifelse( patient_obs$severity == 1, "severe", "nonsevere") )


    #Code, Descriptions and Ranges
    #lab_mapping <- read_csv('public-data/loinc-map.csv')
    lab_mapping <- readr::read_csv( system.file("extdata",
                "loinc-map.csv",
                package="FourCePhase2.1Missingness"))
    #lab_bounds <- read_csv('public-data/lab_bounds.csv')
    # load('public-data/code.dict.rda')
    lab_bounds <- readr::read_csv( system.file("extdata",
                                         "lab_bounds.csv",
                                         package="FourCePhase2.1Missingness"))


    patient_obs_wide <- patient_obs %>%
        dplyr::left_join(lab_bounds, by = c('concept_code' = 'LOINC')) %>%
        dplyr::select(- concept_code) %>%
        tidyr::pivot_wider(id_cols = c(patient_num, days_since_admission, severity),
                    names_from = short_name,
                    values_from = value,
                    values_fn = mean)
    patient_obs_long <- patient_obs_wide %>%
        tidyr::pivot_longer(-c(patient_num, days_since_admission, severity),
                     names_to = 'lab', values_to = 'value',
                     values_drop_na = TRUE)
    #check NAs in the Wide format
    na_stats <- patient_obs_wide %>%
        dplyr::select(- c(patient_num, days_since_admission, severity)) %>%
        is.na() %>%
        `!`
    na_df <- data.frame(value_existed = colSums(na_stats),
                        prop_existed = colMeans(na_stats)) %>%
        tibble::rownames_to_column('lab') %>%
        mutate(prop_na = 1 - prop_existed,
               lab = forcats::fct_reorder(lab, value_existed))
    n_values <- na_df %>%
        ggplot2::ggplot(ggplot2::aes(x = value_existed, y = lab)) +
        ggplot2::geom_col() +
        ggplot2::labs(x = 'Number of values', y = NULL)
    na_prob <- na_df %>%
        rename('Valid value' = prop_existed, 'NA' = prop_na) %>%
        tidyr::pivot_longer(c(`Valid value`, `NA`)) %>%
        ggplot2::ggplot(ggplot2::aes(x = value, y = lab, fill = name)) +
        ggplot2::geom_col() +
        ggplot2::scale_fill_discrete(guide = guide_legend(reverse = TRUE)) +
        ggplot2::labs(x = 'Proportion', y = NULL) +
        # guides(fill = guide_legend(reverse = TRUE))
        ggplot2::theme(
            axis.text.y = element_blank(),
            legend.key.width = unit(6, 'mm'),
            legend.key.height = unit(4, 'mm'),
            legend.position = 'bottom')

    cowplot::plot_grid(n_values, na_prob, nrow = 1, axis = 'b', align = 'h')
    site_na_df <- na_df

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
    site_patient_lab <- patient_lab
    melt_patient_lab <- patient_lab[rep(1:nrow(patient_lab), patient_lab$counts), ]

    melt_patient_lab %>%
        filter(breaks < 30) %>%
        mutate(lab = forcats::fct_infreq(lab)) %>%
        ggplot2::ggplot(ggplot2::aes(x = breaks, y = lab, fill = lab, height = ..count..)) +
        # geom_density_ridges(stat = "identity", scale = 2) +
        ggridges::geom_ridgeline(stat="binline", binwidth=1, scale = 0.001) +
        # scale_color_viridis_d(option = 'C') +
        ggplot2::scale_fill_viridis_d(option = 'C', guide = FALSE) +
        ggplot2::labs(y = NULL) +
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
        dplyr::select(-patient_num) %>%
        add_count(severity, name = 'n_severity')
    site_agg_n_values <- days_count_min_max %>%
        count(severity, n_severity, n_values,
              name = 'n_nvals')
    site_agg_max_day <- days_count_min_max %>%
        count(severity, n_severity, max_day,
              name = 'n_maxday')
    (n_severe <- sum(days_count_min_max$severity == 'severe', na.rm = TRUE))
    (n_nonsevere <- sum(days_count_min_max$severity == 'nonsevere', na.rm = TRUE))
    save(site_na_df, site_agg_n_values, site_agg_max_day, site_patient_lab,
         file = paste0( dir.output,'/',currSiteId,'-results.Rdata'))


    ## Histogram of the number of days with at least one observation
    site_agg_n_values %>%
        ggplot2::ggplot(ggplot2::aes(x = n_values, y = n_nvals, fill = severity)) +
        ggplot2::geom_col(alpha = 0.5) +
        ggplot2::scale_fill_brewer(palette = 'Dark2', direction = -1) +
        ggplot2::labs(fill = 'Severe?',
             x = "Number of days with data",
             y = "Count")

    ## Histogram of length of stay
    ##i.e. last day with observation-first day with observation
    ##We need to check for readmission here.
    site_agg_max_day %>%
        ggplot2::ggplot(ggplot2::aes(x = max_day, y = n_maxday, fill = severity)) +
        ggplot2::geom_col(alpha = 0.5) +
        ggplot2::scale_fill_brewer(palette = 'Dark2', direction = -1) +
        ggplot2::labs(fill = 'Severe?',
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
        tidyr::pivot_wider(names_from = severity, values_from = n, values_fill = 0) %>%
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
        dplyr::select(- c(days_since_admission, value)) %>%
        distinct() %>%
        group_by(lab) %>%
        mutate(across(contains('n_greater'), sum)) %>%
        dplyr::select(- c(n_obs_patients, patient_num)) %>%
        distinct() %>%
        tidyr::pivot_wider(names_from = severity, values_from = each_med_obs_per_patient) %>%
        rename('median_obs_per_severe_patient' = severe,
               'median_obs_per_non_severe_patient' = nonsevere) %>%
        dplyr::select(lab, total_obs, total_patients, starts_with('med'), starts_with('n_'))
    lab_medians %>%
        DT::datatable(rownames = FALSE)

    lab_medians %>%
        dplyr::select(lab, total_obs, total_patients) %>%
        tidyr::pivot_longer(- lab) %>%
        ggplot2::ggplot(ggplot2::aes(x = value, y = forcats::fct_reorder(lab, value))) +
        ggplot2::geom_col() +
        ggplot2::facet_grid(cols = vars(name), scales = 'free_x', space = 'free') +
        ggplot2::labs(y = NULL)

    # In the figure below:
    #
    # - Grey dash line: `Reference Low`
    # - Grey solid line: `Reference High`
    # - Black dash line: `lower bound outlier` (QC)
    # - Black solid line: `upper bound outlier` (QC)

    patient_obs_long %>%
        dplyr::left_join(lab_bounds, by = c('lab' = 'short_name')) %>%
        ggplot2::ggplot(ggplot2::aes(y = severity, x = value, fill = severity)) +
        ggplot2::geom_violin() +
        ggplot2::scale_fill_brewer(palette = 'Dark2', guide = guide_legend(reverse = TRUE)) +
        ggplot2::labs(y = NULL, x = NULL) +
        ggplot2::geom_vline(ggplot2::aes(xintercept = `Reference Low`), linetype = 'dashed', color = 'grey') +
        ggplot2::geom_vline(ggplot2::aes(xintercept = `Reference High`), color = 'grey') +
        ggplot2::geom_vline(ggplot2::aes(xintercept = LB), linetype = 'dashed') +
        ggplot2::geom_vline(ggplot2::aes(xintercept = UB)) +
        ggplot2::facet_wrap(~ lab, scales = 'free', ncol = 2, strip.position = 'left') +
        ggplot2::theme(axis.text.y = element_blank())

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
        dplyr::select(lab, obs_bin, both_severities, severe, nonsevere) %>%
        tidyr::pivot_longer(c(both_severities, severe, nonsevere)) %>%
        mutate(name = name %>% forcats::fct_recode(
            'All patients' = 'both_severities',
            'Severe patients' = 'severe',
            'Non-severe patients' = 'nonsevere'
        )) %>%
        ggplot2::ggplot(ggplot2::aes(x = obs_bin, fill = value, y = forcats::fct_reorder(lab, value))) +
        ggplot2::geom_tile(colour = "white", size = 0.2) +
        ggplot2::geom_text(ggplot2::aes(label = value), colour = "white", size = 2) +
        ggplot2::scale_y_discrete(expand = c(0, 0))+
        ggplot2::scale_fill_gradient(low = "lightgrey", high = "darkblue") +
        ggplot2::facet_wrap(~ name, nrow = 1) +
        ggplot2::labs(x = 'Binned number of values a patient has for each lab',
             y = NULL, fill = '# patients') +
        ggplot2::theme(panel.grid.major = element_blank(),
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
        dplyr::select(lab, obs_bin, prop_both, prop_severe, prop_nonsevere) %>%
        tidyr::pivot_longer(c(prop_both, prop_severe, prop_nonsevere)) %>%
        mutate(name = name %>% forcats::fct_recode(
            'Compared to all patients' = 'prop_both',
            'Compared to all severe patients' = 'prop_severe',
            'Compared to all non-severe patients' = 'prop_nonsevere'
        )) %>%
        ggplot2::ggplot(ggplot2::aes(x = obs_bin, fill = value, y = forcats::fct_reorder(lab, value))) +
        ggplot2::geom_tile(colour = "white", size = 0.2) +
        ggplot2::geom_text(ggplot2::aes(label = round(value, 2)), colour = "white", size = 2) +
        ggplot2::scale_y_discrete(expand = c(0, 0)) +
        ggplot2::scale_fill_gradient(low = "lightgrey", high = "darkblue",
                            labels = scales::percent_format(accuracy = 1L)) +
        ggplot2::facet_wrap(~ name, nrow = 1) +
        ggplot2::labs(x = 'Binned number of values a patient has for each lab',
             y = NULL, fill = '% patients') +
        ggplot2::theme(panel.grid.major = element_blank(),
              legend.position = c(0.93, 0.2),
              axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5),
              axis.ticks.y = element_blank()
        )

    ### Denominator: total number of patients, total number of non-severe patients,
    ### and total number of severe patients, respectively.

    per_lab %>%
        dplyr::select(lab, n_obs, severe, nonsevere) %>%
        filter(n_obs <= 90) %>%
        tidyr::pivot_longer(c(severe, nonsevere)) %>%
        mutate(lab = forcats::fct_reorder(lab, n_obs),
               name = name %>% forcats::fct_recode(
                   'Severe patients' = 'severe',
                   'Non-severe patients' = 'nonsevere'
               )) %>%
        ggplot2::ggplot(ggplot2::aes(x = n_obs, fill = name, y = value)) +
        ggplot2::geom_col() +
        ggplot2::scale_fill_brewer(palette = 'Dark2', direction = -1) +
        ggplot2::facet_wrap(~ lab, scales = 'free') +
        ggplot2::labs(x = 'Number of values a patient has for each lab',
             y = NULL, fill = '# patients') +
        ggplot2::theme(panel.grid.major = element_blank(),
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

