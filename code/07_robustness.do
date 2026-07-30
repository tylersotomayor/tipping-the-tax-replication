version 18.0
* Purpose: locked robustness set - donut, wild cluster bootstrap, permutation
*          over placebo cutoffs, and the mechanical-vs-observed decomposition.
* Inputs:  ${DATA_CLEAN}/minute_panel.dta
* Outputs: ${TABLES}/tab-robust2.tex, ${DATA_INT}/perm.dta, log values

use "${DATA_CLEAN}/minute_panel.dta", clear

capture program drop rd2
program define rd2, rclass
    args c w cond donut
    preserve
    quietly keep if `cond'
    quietly gen rv = mint - `c'
    quietly keep if abs(rv) <= `w'
    if `donut' > 0 quietly drop if abs(rv) < `donut'
    quietly gen byte post = rv >= 0
    quietly gen rvp = rv*post
    quietly reg mean_extra post rv rvp [aw=n_all], cluster(date)
    return scalar fs = _b[post]
    quietly reg mean_tip post rv rvp [aw=n_card], cluster(date)
    return scalar rf = _b[post]
    return scalar se = _se[post]
    restore
end

di as result "=== R1: donut specifications, 4pm weekday, $2.50 regime ==="
foreach d in 0 3 5 10 {
    rd2 960 60 "weekday & !holiday & regime25" `d'
    local rho = r(rf)/r(fs)
    di as result "   donut +/-`d' min: FS=" %6.3f r(fs) " RF=" %6.4f r(rf) ///
        " (" %6.4f r(se) ")  rho=" %6.3f `rho'
    * weekend netting at same donut
    rd2 960 60 "!weekday & regime25" `d'
    di as result "      weekend RF=" %6.4f r(rf) " (" %6.4f r(se) ")"
}

di as result "=== R2: wild cluster bootstrap, headline reduced form ==="
preserve
keep if weekday & !holiday & regime25
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post
reg mean_tip post rv rvp [aw=n_card], cluster(date)
boottest post, reps(9999) weighttype(webb) seed(20260727) nograph
di as result "   WCB p = " %8.6f r(p) "   CI = " r(CIstr)
restore

di as result "=== R3: permutation over placebo cutoffs (weekday, R25) ==="
* every candidate cutoff in the 4pm window except the true one
preserve
keep if weekday & !holiday & regime25 & inrange(mint, 900, 1020)
tempname P
matrix `P' = J(41,2,.)
local i = 1
forvalues c = 930/970 {
    quietly {
        capture drop rv post rvp
        gen rv = mint - `c'
        gen byte post = rv >= 0
        gen rvp = rv*post
        reg mean_tip post rv rvp [aw=n_card], cluster(date)
        matrix `P'[`i',1] = `c'
        matrix `P'[`i',2] = _b[post]
    }
    local ++i
}
clear
svmat double `P', names(col)
rename c1 cutoff
rename c2 b
save "${DATA_INT}/perm.dta", replace
quietly sum b if cutoff == 960
local actual = r(mean)
quietly count if abs(b) >= abs(`actual') & cutoff != 960
local nge = r(N)
quietly count if cutoff != 960
di as result "   actual (960) = " %7.4f `actual' ///
    ";  placebo cutoffs with |b| >= actual: " `nge' " of " r(N) ///
    ";  p = " %5.3f `nge'/r(N)
restore

di as result "=== R4: mechanical vs observed decomposition, 4pm R25 ==="
preserve
keep if weekday & !holiday & regime25
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post
* observed tip step
quietly reg mean_tip post rv rvp [aw=n_card], cluster(date)
scalar obs = _b[post]
* first stage
quietly reg mean_extra post rv rvp [aw=n_all], cluster(date)
scalar fsx = _b[post]
* adherence just below the cutoff, and mean default rate implied by
* the tip-to-base ratio among exact-default payers
quietly sum sh_exact if !post [aw=n_card]
scalar adher = r(mean)
* mean pre-cutoff tip rate on the base
quietly sum mean_tip if !post [aw=n_card]
scalar tip0 = r(mean)
quietly sum mean_ptt_card if !post [aw=n_card]
scalar base0 = r(mean)
scalar tiprate = tip0/base0
scalar mech = fsx*tiprate
di as result "   first stage (surcharge step)      = " %6.3f fsx
di as result "   pre-cutoff mean tip rate on base  = " %6.4f tiprate
di as result "   mechanical prediction (FS x rate) = " %6.4f mech
di as result "   observed tip step                 = " %6.4f obs
di as result "   observed / mechanical             = " %6.3f obs/mech
di as result "   pre-cutoff exact-default adherence= " %6.3f adher
restore

di as result "=== R5: CONTAMINATION CHECK - does the metered fare also jump at 4pm? ==="
preserve
keep if weekday & !holiday & regime25
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post
gen nonsur = mean_ptt_card - mean_extra   // base excluding the surcharge
quietly reg mean_ptt_card post rv rvp [aw=n_card], cluster(date)
di as result "   total pre-tip base step   = " %6.3f _b[post] " (" %6.4f _se[post] ")"
quietly reg mean_extra post rv rvp [aw=n_all], cluster(date)
di as result "   of which surcharge        = " %6.3f _b[post] " (" %6.4f _se[post] ")"
quietly reg nonsur post rv rvp [aw=n_card], cluster(date)
di as result "   of which metered fare etc = " %6.3f _b[post] " (" %6.4f _se[post] ")"
di as result ""
di as result "   >>> CORRECTED SPEC: control for the non-surcharge base <<<"
quietly reg mean_tip post rv rvp nonsur [aw=n_card], cluster(date)
scalar rf_c = _b[post]
scalar se_c = _se[post]
quietly reg mean_extra post rv rvp nonsur [aw=n_all], cluster(date)
scalar fs_c = _b[post]
di as result "   controlled RF = " %6.4f rf_c " (" %6.4f se_c ")  FS = " %6.3f fs_c ///
    "  rho = " %6.3f rf_c/fs_c
* same for weekends (placebo: no surcharge, so controlled step should vanish)
restore
preserve
keep if !weekday & regime25
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post
gen nonsur = mean_ptt_card - mean_extra
quietly reg mean_tip post rv rvp nonsur [aw=n_card], cluster(date)
di as result "   weekend controlled RF = " %6.4f _b[post] " (" %6.4f _se[post] ")"
restore
* and for the $1.00 regime
preserve
keep if weekday & !holiday & regime1
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post
gen nonsur = mean_ptt_card - mean_extra
quietly reg mean_tip post rv rvp nonsur [aw=n_card], cluster(date)
scalar rf_c1 = _b[post]
scalar se_c1 = _se[post]
quietly reg mean_extra post rv rvp nonsur [aw=n_all], cluster(date)
di as result "   R1 controlled RF = " %6.4f rf_c1 " (" %6.4f se_c1 ")  rho = " ///
    %6.3f rf_c1/_b[post]
restore
