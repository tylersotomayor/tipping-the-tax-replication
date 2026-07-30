version 18.0
* Figures for results A-C: vendor split, dose staircase, seasonal-FE ES.

*---- (A) vendor figure: rho and adherence side by side ----
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_vendor.csv", clear varnames(1)
gen date = date(d, "YMD")
keep if inrange(date, mdy(12,19,2022), mdy(9,30,2024))
gen dow = dow(date)
keep if inrange(dow,1,5)
gen mean_tip = s_tip/n_card
gen mean_ext = s_extra/n_card
gen nonsur = (s_ptt - s_extra)/n_card
gen adher = n_exact/n_card
drop if missing(mean_tip) | n_card < 5
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post
tempname R
matrix `R' = J(2,4,.)
local i = 1
foreach v in 1 2 {
    quietly sum adher if vid == `v' & !post [aw=n_card]
    matrix `R'[`i',3] = r(mean)
    quietly ivregress 2sls mean_tip (mean_ext = post) rv rvp nonsur ///
        [aw=n_card] if vid == `v', vce(cluster d)
    matrix `R'[`i',1] = _b[mean_ext]
    matrix `R'[`i',2] = _se[mean_ext]
    matrix `R'[`i',4] = `v'
    local ++i
}
clear
svmat double `R', names(col)
rename (c1 c2 c3 c4) (rho se adher vid)
gen lo = rho - 1.96*se
gen hi = rho + 1.96*se
gen x = _n
twoway (bar adher x, barwidth(0.35) color(teal%45) yaxis(2)) ///
    (rcap lo hi x, lcolor(navy) lwidth(medthick)) ///
    (scatter rho x, mcolor(navy) msymbol(O) msize(large)), ///
    xlabel(1 `""Vendor 1" "(19% press the button)""' 2 `""Vendor 2" "(65% press the button)""', labsize(small)) ///
    xscale(range(0.5 2.5)) ylabel(0(0.05)0.2) ylabel(0(0.2)0.8, axis(2)) ///
    xtitle("") ///
    ytitle("Pass-through {&rho}{superscript:IV}") ///
    ytitle("Exact-default adherence (bars)", axis(2)) ///
    legend(order(3 "Pass-through {&rho}{superscript:IV} (dots)" 1 "Exact-default adherence (bars)") pos(11) ring(0) cols(1) size(small))
graph export "${FIGURES}/fig-vendor.pdf", as(pdf) replace

*---- (C) dose staircase ----
import delimited "${PROJECT_ROOT}/data/cells/cells_odpair.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen mo = real(substr(ym,6,2))
gen t = ym(y,mo)
gen mean_tip = s_tip/n_card
drop if missing(mean_tip) | n_card < 25
preserve
keep if t >= ym(2025,2)
gen chsh = (s_cbd/0.75)/n_card
collapse (mean) dose = chsh [aw=n_card], by(pu dozone)
replace dose = 1 if dose > 1
tempfile D
save `D'
restore
merge m:1 pu dozone using `D', keep(3) nogen
gen byte post = t >= ym(2025,1)
gen nonsur = (s_ptt - s_cbd - s_cs)/n_card
egen odp = group(pu dozone)
egen puclu = group(pu)
gen db = 1 + (dose>0.1) + (dose>0.5) + (dose>0.9)
forvalues b = 2/4 {
    gen byte g`b' = (db==`b')*post
}
quietly reghdfe mean_tip g2 g3 g4 nonsur [aw=n_card], absorb(odp t) vce(cluster puclu)
clear
set obs 4
gen x = _n
gen b = 0 in 1
gen se = 0 in 1
replace b = _b[g2] in 2
replace se = _se[g2] in 2
replace b = _b[g3] in 3
replace se = _se[g3] in 3
replace b = _b[g4] in 4
replace se = _se[g4] in 4
gen lo = b - 1.96*se
gen hi = b + 1.96*se
twoway (bar b x, barwidth(0.55) color(navy%55) lcolor(navy)) ///
    (rcap lo hi x if x > 1, lcolor(gs5)), ///
    xlabel(1 `""0{&minus}10%" "(reference)""' 2 "10{&minus}50%" 3 "50{&minus}90%" 4 ">90%", labsize(small)) ///
    xtitle("Share of the OD pair's trips charged the 2025 toll") ///
    ytitle("Tip effect after Jan 2025 (USD)") ///
    yline(0, lcolor(gs8)) legend(off)
graph export "${FIGURES}/fig-dose.pdf", as(pdf) replace

*---- (B) seasonal-FE event study figure ----
import delimited "${PROJECT_ROOT}/data/cells/cells_zone_v2.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen mo = real(substr(ym,6,2))
gen t = ym(y,mo)
keep if t >= ym(2023,1)
gen mean_tip = s_tip/n_card
drop if missing(mean_tip) | n_card < 25
preserve
import delimited "${PROJECT_ROOT}/data/cells/cbd_zones.csv", clear varnames(1)
gen byte puin = 1
tempfile Z
save `Z'
restore
merge m:1 pu using `Z', keep(1 3) nogen
replace puin = 0 if missing(puin)
gen byte elig = puin | doin
egen unit = group(pu doin fbin)
egen puclu = group(pu)
gen evt = t - ym(2025,1)
forvalues k = 1/18 {
    local e = `k' - 13
    if `e' != -13 gen byte d`k' = elig*(evt == `e')
}
* reference: all of 2023 (evt < -12); 2024 pre months get their own dummies
quietly reghdfe mean_tip d* [aw=n_card], absorb(unit t elig#mo) vce(cluster puclu)
clear
set obs 18
gen e = _n - 13
gen b = .
gen se = .
forvalues k = 1/18 {
    local ee = `k' - 13
    if `ee' != -13 {
        replace b = _b[d`k'] if e == `ee'
        replace se = _se[d`k'] if e == `ee'
    }
}
drop if missing(b)
gen lo = b - 1.96*se
gen hi = b + 1.96*se
twoway (rcap lo hi e if e < 0, lcolor(gs9)) (scatter b e if e < 0, mcolor(gs7) msymbol(O)) ///
    (rcap lo hi e if e >= 0, lcolor(navy)) (scatter b e if e >= 0, mcolor(navy) msymbol(O)), ///
    yline(0, lcolor(gs10) lpattern(dash)) xline(-0.5, lcolor(maroon) lpattern(dash)) ///
    xlabel(-12(3)5) ///
    xtitle("Months relative to January 2025 (reference: calendar 2023)") ///
    ytitle("Tip difference, eligible vs never-eligible (USD)") ///
    legend(off)
graph export "${FIGURES}/fig-es-fee25.pdf", as(pdf) replace
