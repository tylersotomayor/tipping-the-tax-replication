version 18.0
* Amendment-3 spatial estimation: OD eligibility, standard-rate card sample,
* joint pre-trend Wald tests, old-vs-new design comparison.
import delimited "${PROJECT_ROOT}/data/cells/cells_zone_v2.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen mo = real(substr(ym,6,2))
gen t = ym(y,mo)
format t %tm
gen mean_tip = s_tip/n_card
gen mean_cbd = s_cbd/n_card
gen mean_cs  = s_cs/n_card
drop if missing(mean_tip) | n_card < 25
* CBD pickup-zone set (from committed list)
preserve
import delimited "${PROJECT_ROOT}/data/cells/cbd_zones.csv", clear varnames(1)
gen byte puin = 1
tempfile Z
save `Z'
restore
merge m:1 pu using `Z', keep(1 3) nogen
replace puin = 0 if missing(puin)
gen byte elig = puin | doin              // OD eligibility (statutory rule)
gen byte elig_puonly = puin              // old design, for comparison
egen unit = group(pu doin fbin)
egen puclu = group(pu)

capture program drop spat
program define spat
    args tvar evwin lo hi dose lab
    * pooled DiD + IV
    quietly gen byte post = t >= `evwin'
    quietly gen byte tp = `tvar'*post
    reghdfe mean_tip tp [aw=n_card], absorb(unit t) vce(cluster puclu)
    local b = _b[tp]
    local se = _se[tp]
    di as result "`lab': DiD b=" %7.4f `b' " (" %6.4f `se' ")"
    * event study + joint pre-trend Wald
    quietly gen evt = t - `evwin'
    local pre ""
    forvalues k = `lo'/`hi' {
        if `k' != -1 {
            local kk = `k' + 20
            quietly gen byte dd`kk' = `tvar'*(evt == `k')
            if `k' < -1 local pre "`pre' dd`kk'"
        }
    }
    quietly reghdfe mean_tip dd* [aw=n_card], absorb(unit t) vce(cluster puclu)
    test `pre'
    di as result "`lab': joint pre-trend Wald p = " %6.4f r(p)
    forvalues k = `lo'/`hi' {
        if `k' != -1 {
            local kk = `k' + 20
            di as result "   evt " %3.0f `k' ": " %7.4f _b[dd`kk'] " (" %6.4f _se[dd`kk'] ")"
        }
    }
    drop post tp evt dd*
end

* ---------- 2019 congestion surcharge (window complete) ----------
preserve
keep if inrange(t, ym(2018,7), ym(2019,12))
di as result "===== 2019 SURCHARGE, OD ELIGIBILITY ====="
spat elig "ym(2019,2)" -7 6 mean_cs "2019 OD"
* first stage & fuzzy rho
quietly gen byte post = t >= ym(2019,2)
quietly gen byte tp = elig*post
reghdfe mean_cs tp [aw=n_card], absorb(unit t) vce(cluster puclu)
di as result "2019 OD first stage (fee per card trip): " %6.3f _b[tp] " (" %6.4f _se[tp] ")"
local fs = _b[tp]
reghdfe mean_tip tp [aw=n_card], absorb(unit t) vce(cluster puclu)
di as result "2019 OD rho = " %6.3f _b[tp]/`fs' "  (delta-ish se " %6.3f _se[tp]/`fs' ")"
drop post tp
di as result "===== 2019 SURCHARGE, OLD PICKUP-ONLY (comparison) ====="
spat elig_puonly "ym(2019,2)" -7 6 mean_cs "2019 PU-only"
restore

* ---------- 2025 CBD toll (runs when window complete) ----------
quietly sum t
if r(max) >= ym(2025,6) {
    preserve
    keep if inrange(t, ym(2024,1), ym(2025,6))
    di as result "===== 2025 TOLL, OD ELIGIBILITY ====="
    spat elig "ym(2025,1)" -12 5 mean_cbd "2025 OD"
    quietly gen byte post = t >= ym(2025,1)
    quietly gen byte tp = elig*post
    reghdfe mean_cbd tp [aw=n_card], absorb(unit t) vce(cluster puclu)
    di as result "2025 OD first stage: " %6.3f _b[tp] " (" %6.4f _se[tp] ")"
    local fs = _b[tp]
    reghdfe mean_tip tp [aw=n_card], absorb(unit t) vce(cluster puclu)
    di as result "2025 OD rho = " %6.3f _b[tp]/`fs' "  (delta-ish se " %6.3f _se[tp]/`fs' ")"
    drop post tp
    di as result "===== 2025 TOLL, OLD PICKUP-ONLY (comparison) ====="
    spat elig_puonly "ym(2025,1)" -12 5 mean_cbd "2025 PU-only"
    restore
}
else di as result "2025 window incomplete; rerun when build lands"
