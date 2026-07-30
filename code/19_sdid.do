version 18.0
clear all
set more off
set scheme s1mono
global PROJECT_ROOT "`c(pwd)'"
global FIGURES "${PROJECT_ROOT}/output/figures"
* Synthetic DiD for the 2025 toll: zone-level balanced monthly panel,
* fare-conditioned tips, treated = OD-eligible zones.
import delimited "${PROJECT_ROOT}/data/cells/cells_zone_v2.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen mo = real(substr(ym,6,2))
gen t = ym(y,mo)
keep if inrange(t, ym(2023,1), ym(2025,6))
gen mean_tip = s_tip/n_card
drop if missing(mean_tip) | n_card < 10
* fare-conditioning first, then aggregate to zone-month
quietly reghdfe mean_tip [aw=n_card], absorb(fbin#doin) resid
predict double rtip, resid
preserve
import delimited "${PROJECT_ROOT}/data/cells/cbd_zones.csv", clear varnames(1)
gen byte puin = 1
tempfile Z
save `Z'
restore
merge m:1 pu using `Z', keep(1 3) nogen
replace puin = 0 if missing(puin)
gen byte elig = puin | doin
* unit = pickup zone: treated = CBD-pickup zones (all their trips pay);
* controls = non-CBD pickup zones' never-eligible pool (doin==0 only),
* dropping their eligible dropoff pool so controls are untreated.
keep if puin | (doin == 0)
collapse (mean) rtip (sum) n_card, by(pu puin t)
gen elig = puin
egen unit = group(pu)
bysort unit: gen T = _N
quietly sum T
keep if T == r(max)
gen byte treat = elig & t >= ym(2025,1)
sdid rtip unit t treat, vce(bootstrap) reps(200) seed(20260727) ///
    graph g1on g2_opt(ylabel(, labsize(small)))
di as result "SDID ATT = " %7.4f e(ATT) " (" %6.4f e(se) ")"
di as result "  implied rho (fee/card trip = 0.602): " %6.3f e(ATT)/0.602
graph export "${FIGURES}/fig-sdid.pdf", as(pdf) replace
* in-time placebo: pretend adoption 2024m7, using only pre-2025 data
preserve
keep if t < ym(2025,1)
gen byte treatp = elig & t >= ym(2024,7)
sdid rtip unit t treatp, vce(bootstrap) reps(200) seed(20260727)
di as result "SDID PLACEBO (fake 2024m7) ATT = " %7.4f e(ATT) " (" %6.4f e(se) ")"
restore
