version 18.0
clear all
set more off

* Complete reproducible entry point. Run from the project root with:
*   ./run_stata.sh

global PROJECT_ROOT "`c(pwd)'"
global CODE         "${PROJECT_ROOT}/code"
global DATA_RAW     "${PROJECT_ROOT}/data/raw"
global DATA_INT     "${PROJECT_ROOT}/data/intermediate"
global DATA_CLEAN   "${PROJECT_ROOT}/data/processed"
global FIGURES      "${PROJECT_ROOT}/output/figures"
global TABLES       "${PROJECT_ROOT}/output/tables"
global LOGS         "${PROJECT_ROOT}/logs"

capture log close _all
log using "${LOGS}/stata-master.log", text replace name(master)

* ---- Guard: the minute cells are NOT versioned (see README.md). Fail loudly
*      rather than silently estimating on a stale or missing build.
foreach f in "cells_minute_v3.csv" "cells_odpair.csv" "cells_zone_v2.csv" ///
             "cells_minute_vendor.csv" "cells_minute_6am.csv" ///
             "cells_minute_jfk.csv" "cells_minute_decomp.csv" {
    capture confirm file "${PROJECT_ROOT}/data/cells/`f'"
    if _rc {
        di as error "MISSING CELL FILE: data/cells/`f'"
        di as error "Rebuild with code/py/build_cells_v3.py, build_odpair.py,"
        di as error "build_zone_v2.py, build_cells_vendor.py before running."
        exit 601
    }
}

* ---- Legacy v1/v2 pipeline (superseded specs; retained for provenance) ----
do "${CODE}/01_setup.do"
do "${CODE}/02_import_clean.do"
do "${CODE}/03_analysis.do"
do "${CODE}/04_figures.do"
do "${CODE}/05_tables.do"
do "${CODE}/06_fee_events.do"
do "${CODE}/07_robustness.do"
do "${CODE}/09_haggag_paci.do"
do "${CODE}/08_map.do"

* ---- Preferred (Amendment 1-2) pipeline: everything the paper displays ----
do "${CODE}/10_v3_analysis.do"
do "${CODE}/11_v3_tables.do"
do "${CODE}/12_spatial_v2.do"
do "${CODE}/13_maps_v2.do"
do "${CODE}/14_final_analyses.do"
do "${CODE}/15_new_figures.do"
do "${CODE}/16_welfare.do"
do "${CODE}/17_lp_dec22.do"
do "${CODE}/18_pooled_rollout.do"
do "${CODE}/19_sdid.do"
do "${CODE}/20_composition.do"
do "${CODE}/21_hp_base.do"
do "${CODE}/22_coefplot.do"
do "${CODE}/23_spikes.do"
do "${CODE}/24_holidays.do"
do "${CODE}/25_jfk.do"
do "${CODE}/26_transfer_menu.do"
do "${CODE}/27_poster_figs.do"
do "${CODE}/28_decomp.do"

log close master
