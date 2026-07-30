version 18.0
* Purpose: D1 within-day discontinuities, D2 difference-in-discontinuities
*          across the Dec-2022 dose change, D3 offset decomposition.
*          Locked per ANALYSIS_PLAN.md.
use "${DATA_CLEAN}/minute_panel.dta", clear

capture program drop clockrd
program define clockrd, rclass
    args c w cond lab
    preserve
    quietly keep if `cond'
    quietly gen rv = mint - `c'
    quietly keep if abs(rv) <= `w'
    quietly gen byte post = rv >= 0
    quietly gen rvp = rv*post
    quietly reg mean_extra post rv rvp [aw=n_all], cluster(date)
    local fs = _b[post]
    local fs_se = _se[post]
    quietly reg mean_tip post rv rvp [aw=n_card], cluster(date)
    local rf = _b[post]
    local rf_se = _se[post]
    local rho = `rf'/`fs'
    di as result "`lab': FS=" %6.3f `fs' " (" %5.3f `fs_se' ")  RF=" ///
        %7.4f `rf' " (" %6.4f `rf_se' ")  rho=" %6.3f `rho' ///
        "  MDE_rf=" %6.4f 2.8*`rf_se' "  N=" _N
    return scalar fs = `fs'
    return scalar rf = `rf'
    return scalar rf_se = `rf_se'
    restore
end

* ---- D1/D2: 4pm by regime (dose test) ----
di as result "=== D1/D2: 4pm weekday, by surcharge regime ==="
foreach r in 1 25 {
    if `r' == 1  local rc "regime1"
    if `r' == 25 local rc "regime25"
    clockrd 960 60 "weekday & !holiday & `rc'" "4pm wd R`r' bw60"
    scalar rf_wd`r' = r(rf)
    scalar se_wd`r' = r(rf_se)
    scalar fs_wd`r' = r(fs)
    clockrd 960 60 "!weekday & `rc'" "4pm we R`r' (no surcharge)"
    scalar rf_we`r' = r(rf)
    scalar se_we`r' = r(rf_se)
}
* difference-in-discontinuities: weekday minus weekend, each regime
foreach r in 1 25 {
    scalar did`r' = rf_wd`r' - rf_we`r'
    scalar didse`r' = sqrt(se_wd`r'^2 + se_we`r'^2)
    scalar rhod`r' = did`r'/fs_wd`r'
    di as result "DiD 4pm R`r': RF_wd-RF_we=" %7.4f did`r' " (" %6.4f didse`r' ///
        ")  rho_netted=" %6.3f rhod`r'
}
* dose stability: is rho equal across the $1.00 and $2.50 regimes?
scalar drho = rhod25 - rhod1
di as result "DOSE TEST: rho(R25) - rho(R1) = " %6.3f drho

* ---- D1: other clocks, both regimes pooled where surcharge signs agree ----
di as result "=== D1: other clock cutoffs ==="
clockrd 1200 60 "weekday & !holiday & regime1"  "8pm wd R1 (net down)"
clockrd 1200 60 "weekday & !holiday & regime25" "8pm wd R25 (net down)"
clockrd 1200 60 "!weekday & regime1"  "8pm we R1 (up)"
clockrd 1200 60 "!weekday & regime25" "8pm we R25 (up)"
clockrd 360 55 "regime1"  "6am R1 (down)"
clockrd 360 55 "regime25" "6am R25 (down)"

* ---- placebos ----
di as result "=== placebos ==="
clockrd 900 25 "weekday & !holiday & regime1"  "3pm placebo R1"
clockrd 900 25 "weekday & !holiday & regime25" "3pm placebo R25"
clockrd 1020 25 "weekday & !holiday & regime25" "5pm placebo R25 (in-surcharge)"

* ---- bandwidth sensitivity on the headline ----
di as result "=== bandwidth sensitivity, 4pm weekday R25 ==="
foreach b in 20 30 45 60 90 {
    clockrd 960 `b' "weekday & !holiday & regime25" "4pm wd R25 bw`b'"
}

* ---- D3: offset decomposition at 4pm, both regimes ----
di as result "=== D3: offsets at 4pm ==="
capture program drop offsets
program define offsets
    args c w cond lab
    preserve
    quietly keep if `cond'
    quietly gen rv = mint - `c'
    quietly keep if abs(rv) <= `w'
    quietly gen byte post = rv >= 0
    quietly gen rvp = rv*post
    foreach y in sh_exact sh_zero sh_card mean_ptt_card {
        quietly reg `y' post rv rvp [aw=n_card], cluster(date)
        di as result "   `lab' `y': " %8.5f _b[post] " (" %8.5f _se[post] ")"
    }
    restore
end
offsets 960 60 "weekday & !holiday & regime1"  "R1"
offsets 960 60 "weekday & !holiday & regime25" "R25"

* ---- figure data: minute means by regime ----
preserve
keep if weekday & !holiday & inrange(mint, 900, 1020)
collapse (mean) mean_extra mean_tip [aw=n_card], by(mint regime25)
save "${DATA_INT}/fig4pm.dta", replace
restore
preserve
keep if inrange(mint, 900, 1020) & regime25
collapse (mean) mean_tip [aw=n_card], by(mint weekday)
save "${DATA_INT}/fig4pm_wewd.dta", replace
restore

*----------------------------------------------------------------------
* D0: vendor-level validation of the tip base
*----------------------------------------------------------------------
preserve
import delimited "${PROJECT_ROOT}/data/cells/cells_vendor.csv", clear varnames(1)
collapse (mean) m_allin m_nocbd m_fare [aw=n_cardtip], by(vid)
di as result "=== D0: share of tips matching 20/25/30% of each base, by vendor ==="
list, noobs clean
restore

*----------------------------------------------------------------------
* D4: congestion-fee event studies (2019 surcharge, 2025 CBD toll)
*----------------------------------------------------------------------
preserve
import delimited "${PROJECT_ROOT}/data/cells/cells_did.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen m = real(substr(ym,6,2))
gen t = ym(y,m)
format t %tm
gen mean_tip = sum_tip_card/n_card
gen sh_zero = n_zero/n_card
drop if missing(mean_tip)
tempfile didall
save `didall'
* 2025 CBD toll: treated = zone (cbd fee > 0), event 2025m1
keep if t >= ym(2024,1)
gen byte post = t >= ym(2025,1)
gen byte tp = zone*post
reghdfe mean_tip tp [aw=n_card], absorb(i.zone#i.fbin i.t) vce(cluster fbin)
di as result "=== D4a: 2025 CBD toll DiD, tip | fare bin ==="
di as result "   b=" %7.4f _b[tp] " se=" %7.4f _se[tp] " N=" e(N)
* event study by month
gen evt = t - ym(2025,1)
quietly levelsof evt if inrange(evt,-12,5), local(es)
di as result "   event study (zone x month, rel to 2024m12):"
foreach e of local es {
    if `e' != -1 {
        quietly gen byte z`=`e'+13' = zone*(evt==`e')
    }
}
reghdfe mean_tip z* [aw=n_card] if inrange(evt,-12,5), absorb(i.zone#i.fbin i.t) vce(cluster fbin)
foreach e of local es {
    if `e' != -1 {
        local v = `e'+13
        di as result "      evt=" %3.0f `e' ": " %7.4f _b[z`v'] " (" %6.4f _se[z`v'] ")"
    }
}
use `didall', clear
* 2019 congestion surcharge: treated = zone (cs > 0), event 2019m2
keep if t <= ym(2019,12)
gen byte post19 = t >= ym(2019,2)
gen byte tp19 = zone*post19
reghdfe mean_tip tp19 [aw=n_card], absorb(i.zone#i.fbin i.t) vce(cluster fbin)
di as result "=== D4b: 2019 congestion surcharge DiD, tip | fare bin ==="
di as result "   b=" %7.4f _b[tp19] " se=" %7.4f _se[tp19] " N=" e(N)
restore
