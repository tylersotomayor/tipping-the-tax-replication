version 18.0
clear all
set more off
global PROJECT_ROOT "`c(pwd)'"
* Average rollout effect: stack the 2019 and 2025 fee adoptions, fuzzy
* per-dollar design (tip on observed fee, instrumented by elig x post),
* cohort-specific unit and time FE, cluster by pickup zone.
import delimited "${PROJECT_ROOT}/data/cells/cells_zone_v2.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen mo = real(substr(ym,6,2))
gen t = ym(y,mo)
gen mean_tip = s_tip/n_card
gen mean_fee19 = s_cs/n_card
gen mean_fee25 = s_cbd/n_card
drop if missing(mean_tip) | n_card < 25
preserve
import delimited "${PROJECT_ROOT}/data/cells/cbd_zones.csv", clear varnames(1)
gen byte puin = 1
tempfile Z
save `Z'
restore
merge m:1 pu using `Z', keep(1 3) nogen
replace puin = 0 if missing(puin)
* cohort 1: 2019 surcharge (dose 2.50, event 2019m2, elig = fee incidence zones)
preserve
keep if inrange(t, ym(2018,7), ym(2019,12))
gen byte coh = 1
gen fee = mean_fee19
* learn 2019 zones from post incidence at PU x doin grain
tempfile c1
save `c1'
keep if t >= ym(2019,3)
collapse (mean) m19 = mean_fee19 [aw=n_card], by(pu doin)
gen byte elig = m19 > 0.5
keep pu doin elig
merge 1:m pu doin using `c1', keep(3) nogen
gen byte post = t >= ym(2019,2)
tempfile C1
save `C1'
restore
* cohort 2: 2025 toll (dose 0.75, event 2025m1, elig = pu-in or do-in)
keep if inrange(t, ym(2024,1), ym(2025,6))
gen byte coh = 2
gen fee = mean_fee25
gen byte elig = puin | doin
gen byte post = t >= ym(2025,1)
append using `C1'
gen tp = elig*post
gen nonsur = (s_ptt - s_cs - s_cbd)/n_card
egen unit = group(coh pu doin fbin)
egen ct = group(coh t)
egen puclu = group(pu)
* pooled fuzzy per-dollar effect
quietly reghdfe mean_tip nonsur [aw=n_card], absorb(unit ct) resid(ry)
quietly reghdfe fee nonsur [aw=n_card], absorb(unit ct) resid(rx)
quietly reghdfe tp nonsur [aw=n_card], absorb(unit ct) resid(rz)
ivregress 2sls ry (rx = rz) [aw=n_card], vce(cluster puclu) noconstant
di as result "AVERAGE ROLLOUT EFFECT (pooled per-dollar, IV): rho = " ///
    %6.3f _b[rx] " (" %5.3f _se[rx] ")  N=" %9.0fc e(N)
* heterogeneity: allow cohort-specific effects and test equality
gen fee1 = fee*(coh==1)
gen fee2 = fee*(coh==2)
gen tp1 = tp*(coh==1)
gen tp2 = tp*(coh==2)
quietly reghdfe fee1 nonsur [aw=n_card], absorb(unit ct) resid(rx1)
quietly reghdfe fee2 nonsur [aw=n_card], absorb(unit ct) resid(rx2)
quietly reghdfe tp1 nonsur [aw=n_card], absorb(unit ct) resid(rz1)
quietly reghdfe tp2 nonsur [aw=n_card], absorb(unit ct) resid(rz2)
ivregress 2sls ry (rx1 rx2 = rz1 rz2) [aw=n_card], vce(cluster puclu) noconstant
di as result "  cohort 2019: " %6.3f _b[rx1] " (" %5.3f _se[rx1] ")"
di as result "  cohort 2025: " %6.3f _b[rx2] " (" %5.3f _se[rx2] ")"
test rx1 = rx2
di as result "  equality test p = " %6.4f r(p)
