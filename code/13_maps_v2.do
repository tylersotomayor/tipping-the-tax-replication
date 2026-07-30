version 18.0
* Causal twin choropleths: per-zone fare-conditioned tip jump at a placebo
* date (2024-07-01) and at the real toll (2025-01-05). Muted when |t|<1.96.
import delimited "${PROJECT_ROOT}/data/cells/cells_zone_v2.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen mo = real(substr(ym,6,2))
gen t = ym(y,mo)
keep if t >= ym(2024,1)
gen mean_tip = s_tip/n_card
drop if missing(mean_tip) | n_card < 25
* fare-conditioning: residualize on fare-bin x dropoff-flag cells
quietly reghdfe mean_tip [aw=n_card], absorb(fbin#doin) resid
predict double rtip, resid
* subtract CONTROL-zone period means (never-eligible: pickup outside CBD list
* and dropoff outside), so jumps are relative to untreated NYC, not to a
* city average dominated by the treated CBD itself
preserve
import delimited "${PROJECT_ROOT}/data/cells/cbd_zones.csv", clear varnames(1)
gen byte cbdpu = 1
tempfile CC
save `CC'
restore
merge m:1 pu using `CC', keep(1 3) nogen
replace cbdpu = 0 if missing(cbdpu)
preserve
keep if !cbdpu & doin == 0
collapse (mean) ctrlm = rtip [aw=n_card], by(t)
tempfile CM
save `CM'
restore
merge m:1 t using `CM', keep(1 3) nogen
replace rtip = rtip - ctrlm
* per-zone jumps
capture postclose Z
postfile Z int(pu) byte(real) double(b se) using "${DATA_INT}/zonejumps.dta", replace
quietly levelsof pu, local(zs)
foreach z of local zs {
    * placebo: within 2024, Jul-Dec vs Jan-Jun
    quietly count if pu == `z' & t < ym(2024,7)
    local n1 = r(N)
    quietly count if pu == `z' & inrange(t, ym(2024,7), ym(2024,12))
    if `n1' >= 4 & r(N) >= 4 {
        capture drop post
        quietly gen byte post = inrange(t, ym(2024,7), ym(2024,12))
        quietly reg rtip post [aw=n_card] if pu == `z' & t < ym(2025,1), robust
        post Z (`z') (0) (_b[post]) (_se[post])
        drop post
    }
    * real: 2025H1 vs 2024 full year
    quietly count if pu == `z' & t >= ym(2025,1)
    if r(N) >= 4 {
        capture drop post
        quietly gen byte post = t >= ym(2025,1)
        quietly reg rtip post [aw=n_card] if pu == `z', robust
        post Z (`z') (1) (_b[post]) (_se[post])
        drop post
    }
}
postclose Z

* draw the two maps
import delimited "${PROJECT_ROOT}/data/cells/zone_geometry.csv", clear varnames(1)
gen long vid = _n
tempfile G
save `G'
foreach r in 0 1 {
    use "${DATA_INT}/zonejumps.dta", clear
    keep if real == `r'
    gen t_ = abs(b/se)
    merge 1:m pu using `G', keep(2 3) nogen
    sort vid
    gen grp = 0
    replace grp = 1 if !missing(t_) & t_ >= 1.96 & b > 0 & b <= 0.05
    replace grp = 2 if !missing(t_) & t_ >= 1.96 & b > 0.05 & b <= 0.10
    replace grp = 3 if !missing(t_) & t_ >= 1.96 & b > 0.10
    replace grp = 4 if !missing(t_) & t_ >= 1.96 & b < 0
    local cmd ""
    quietly levelsof pu, local(zs)
    foreach z of local zs {
        quietly sum grp if pu == `z'
        local g = r(mean)
        if `g' == 0 local c "235 235 235"
        if `g' == 1 local c "170 180 220"
        if `g' == 2 local c "90 105 190"
        if `g' == 3 local c "20 30 120"
        if `g' == 4 local c "230 150 90"
        local cmd `"`cmd' (area lat lon if pu == `z', cmissing(n) nodropbase fcolor("`c'") lcolor(white) lwidth(vvthin))"'
    }
    if `r' == 0 local ti "Placebo: July 2024"
    if `r' == 1 local ti "Real: January 2025 toll"
    twoway `cmd', aspectratio(1.3) legend(off) title("`ti'", size(medium)) ///
        xtitle("") ytitle("") xlabel(none) ylabel(none) ///
        graphregion(color(white)) plotregion(lcolor(none)) ///
        name(map`r', replace) nodraw
}
graph combine map0 map1, cols(2) imargin(1 1 1 1) graphregion(color(white)) ///
    note("Per-zone fare-conditioned change in mean credit-card tip at each date." ///
         "Blues: significant increase (darker = larger). Orange: significant decrease. Grey: no significant change.", size(vsmall))
graph export "${FIGURES}/fig-map-causal.pdf", as(pdf) replace
* summary counts for the text
use "${DATA_INT}/zonejumps.dta", clear
gen sig = abs(b/se) >= 1.96
preserve
import delimited "${PROJECT_ROOT}/data/cells/cbd_zones.csv", clear varnames(1)
gen byte cbd = 1
tempfile C
save `C'
restore
merge m:1 pu using `C', keep(1 3) nogen
replace cbd = 0 if missing(cbd)
di as result "=== zone-jump summary ==="
table real cbd, statistic(mean sig) statistic(mean b) nototals
