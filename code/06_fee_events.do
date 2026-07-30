version 18.0
* Purpose: D4 transportability - congestion-fee event studies with
*          GEOGRAPHIC treated zones (fee columns exist only post-treatment,
*          so zones are learned from post-period fee incidence and applied
*          to the pre-period). Locked per ANALYSIS_PLAN.md.
* Inputs:  data/cells/cells_zone.csv
* Outputs: ${DATA_INT}/es_fee*.dta, ${TABLES}/tab-fee.tex

import delimited "${PROJECT_ROOT}/data/cells/cells_zone.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen mo = real(substr(ym,6,2))
gen t = ym(y,mo)
format t %tm
gen mean_tip = sum_tip/n_card
gen mean_ptt = sum_ptt/n_card
drop if missing(mean_tip) | n_card < 25

*----------------------------------------------------------------------
* 1. Learn treated zone sets from post-period fee incidence
*----------------------------------------------------------------------
* CBD zone (2025 toll, south of 60th St): zones where the fee is charged
preserve
keep if t >= ym(2025,2)
collapse (mean) mean_cbd [aw=n_all], by(pu)
gen byte cbdzone = mean_cbd > 0.30
quietly count if cbdzone
di as result "CBD zones (2025 toll) identified: " r(N)
keep pu cbdzone
tempfile zcbd
save `zcbd'
restore
* 2019 surcharge zone (south of 96th St)
preserve
keep if inrange(t, ym(2019,3), ym(2019,12))
collapse (mean) mean_cs [aw=n_all], by(pu)
gen byte cszone = mean_cs > 0.30
quietly count if cszone
di as result "Congestion-surcharge zones (2019) identified: " r(N)
keep pu cszone
tempfile zcs
save `zcs'
restore
merge m:1 pu using `zcbd', keep(1 3) nogen
merge m:1 pu using `zcs', keep(1 3) nogen
replace cbdzone = 0 if missing(cbdzone)
replace cszone = 0 if missing(cszone)
egen zf = group(pu fbin)
save "${DATA_CLEAN}/zone_panel.dta", replace

*----------------------------------------------------------------------
* 2. 2025 CBD toll: DiD and event study
*    treated = CBD zones; control = non-CBD zones (incl. 60th-96th)
*----------------------------------------------------------------------
use "${DATA_CLEAN}/zone_panel.dta", clear
keep if inrange(t, ym(2024,1), ym(2025,6))
gen byte post = t >= ym(2025,1)
gen byte tp = cbdzone*post
di as result "=== D4a: 2025 CBD toll (fee = 0.75) ==="
reghdfe mean_tip tp [aw=n_card], absorb(zf t) vce(cluster pu)
di as result "   pooled DiD: b=" %7.4f _b[tp] " se=" %7.4f _se[tp] ///
    "  implied rho=" %6.3f _b[tp]/0.75 "  N=" e(N)
scalar b25 = _b[tp]
scalar se25 = _se[tp]
* first stage check: does the fee actually appear?
reghdfe mean_cbd tp [aw=n_card], absorb(zf t) vce(cluster pu)
di as result "   first stage (mean cbd fee): " %6.3f _b[tp] " (" %6.4f _se[tp] ")"
scalar fs25 = _b[tp]
di as result "   rho (fuzzy) = " %6.3f b25/fs25
* event study
use "${DATA_CLEAN}/zone_panel.dta", clear
keep if inrange(t, ym(2024,1), ym(2025,6))
gen evt = t - ym(2025,1)
forvalues k = 0/17 {
    local e = `k' - 12
    if `e' != -1 gen byte d`k' = cbdzone*(evt == `e')
}
reghdfe mean_tip d* [aw=n_card], absorb(zf t) vce(cluster pu)
preserve
clear
set obs 18
gen e = _n - 13
gen b = .
gen se = .
restore
tempname B SE
matrix `B' = J(18,1,.)
matrix `SE' = J(18,1,.)
forvalues k = 0/17 {
    local e = `k' - 12
    if `e' != -1 {
        matrix `B'[`k'+1,1] = _b[d`k']
        matrix `SE'[`k'+1,1] = _se[d`k']
    }
    else {
        matrix `B'[`k'+1,1] = 0
        matrix `SE'[`k'+1,1] = 0
    }
}
preserve
clear
svmat double `B', names(b)
svmat double `SE', names(se)
gen e = _n - 13
rename b1 b
rename se1 se
save "${DATA_INT}/es_fee25.dta", replace
di as result "   event study (rel. to Dec 2024):"
list e b se, noobs clean
restore

*----------------------------------------------------------------------
* 3. 2019 congestion surcharge: DiD
*----------------------------------------------------------------------
use "${DATA_CLEAN}/zone_panel.dta", clear
keep if inrange(t, ym(2018,7), ym(2019,12))
gen byte post = t >= ym(2019,2)
gen byte tp = cszone*post
di as result "=== D4b: 2019 congestion surcharge (fee = 2.50) ==="
reghdfe mean_tip tp [aw=n_card], absorb(zf t) vce(cluster pu)
di as result "   pooled DiD: b=" %7.4f _b[tp] " se=" %7.4f _se[tp] "  N=" e(N)
scalar b19 = _b[tp]
scalar se19 = _se[tp]
reghdfe mean_cs tp [aw=n_card], absorb(zf t) vce(cluster pu)
di as result "   first stage (mean surcharge): " %6.3f _b[tp] " (" %6.4f _se[tp] ")"
scalar fs19 = _b[tp]
di as result "   rho (fuzzy) = " %6.3f b19/fs19

* table
tempname fh
file open `fh' using "${TABLES}/tab-fee.tex", write replace
file write `fh' "2019 congestion surcharge & " %6.3f (fs19) " & " %6.3f (b19) ///
    " & (" %5.3f (se19) ") & " %6.3f (b19/fs19) " \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "2025 {CBD} congestion toll & " %6.3f (fs25) " & " %6.3f (b25) ///
    " & (" %5.3f (se25) ") & " %6.3f (b25/fs25) " \\" _n
file close `fh'

*----------------------------------------------------------------------
* 4. Aggregate transfer (assumption-free arithmetic on observed money)
*----------------------------------------------------------------------
use "${DATA_CLEAN}/zone_panel.dta", clear
* 2025 CBD toll: card trips actually paying the fee, most recent 6 months
preserve
keep if inrange(t, ym(2025,1), ym(2025,6))
gen double paid = n_card*mean_cbd            // dollars of CBD fee on card trips
gen double tipx = n_card*mean_cbd*0.146      // rho from D4a
collapse (sum) n_card paid tipx
gen double annual_fee = paid*2
gen double annual_tip = tipx*2
di as result "=== TRANSFER: 2025 CBD toll ==="
di as result "   card trips (6 mo): " %12.0fc n_card
di as result "   fee paid on card trips, annualized: $" %12.0fc annual_fee
di as result "   extra tips induced, annualized:     $" %12.0fc annual_tip
restore
* 2019 congestion surcharge, most recent 12 months of that window
preserve
keep if inrange(t, ym(2019,1), ym(2019,12))
gen double paid = n_card*mean_cs
gen double tipx = n_card*mean_cs*0.254
collapse (sum) n_card paid tipx
di as result "=== TRANSFER: 2019 congestion surcharge (2019 full year) ==="
di as result "   card trips: " %12.0fc n_card
di as result "   surcharge paid on card trips: $" %12.0fc paid
di as result "   extra tips induced:           $" %12.0fc tipx
restore
* rush surcharge, from the clock design: 2024 card trips in 4-8pm weekday window
preserve
keep if inrange(t, ym(2024,1), ym(2024,12))
collapse (sum) n_card
di as result "=== SCALE: 2024 card trips (all hours, all zones): " %12.0fc n_card
restore
