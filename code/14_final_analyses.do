version 18.0
* (A) Vendor-split rho; (B) seasonal-FE event study + Wald; (C) OD dose-response.

*=================== (A) VENDOR-SPLIT RHO ===================
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_vendor.csv", clear varnames(1)
gen date = date(d, "YMD")
keep if inrange(date, mdy(9,1,2021), mdy(9,30,2024))
gen dow = dow(date)
gen byte weekday = inrange(dow,1,5)
gen byte regime25 = date >= mdy(12,19,2022)
keep if weekday
gen mean_tip = s_tip/n_card
gen mean_ext = s_extra/n_card
gen nonsur = (s_ptt - s_extra)/n_card
gen adher = n_exact/n_card
drop if missing(mean_tip) | n_card < 5
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post
di as result "===== (A) rho by vendor, 4pm weekday R25 ====="
foreach v in 1 2 6 7 {
    quietly count if vid == `v' & regime25
    if r(N) > 5000 {
        quietly sum adher if vid == `v' & regime25 & !post [aw=n_card]
        local ad = r(mean)
        quietly ivregress 2sls mean_tip (mean_ext = post) rv rvp nonsur ///
            [aw=n_card] if vid == `v' & regime25, vce(cluster d)
        di as result "  vendor `v': rho_IV=" %6.3f _b[mean_ext] " (" ///
            %5.3f _se[mean_ext] ")  exact-default adherence=" %5.3f `ad'
    }
}

*=================== (B) SEASONAL-FE EVENT STUDY ===================
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
* treated x calendar-month FE absorb CBD seasonality (2 pre-years identify it)
gen evt = t - ym(2025,1)
* pre-average normalization: dummies for all evt except full pre set; use
* deviation coding: include all post dummies + pre dummies, omit NONE, then
* recentre pre to mean zero via constraint-free approach: simplest robust =
* omit the average by including pre dummies and reporting them demeaned.
* Implementation: standard dummies omitting evt=-12..-1 jointly (they form
* the reference), i.e., include only post dummies + pre-trend test via
* separate regression with pre dummies vs 2023 baseline.
gen byte drop24 = inrange(evt,-12,-1)
* main: post bins vs ALL pre months, with elig x month-of-year FE
forvalues k = 0/5 {
    gen byte p`k' = elig*(evt == `k')
}
reghdfe mean_tip p0-p5 [aw=n_card], absorb(unit t elig#mo) vce(cluster puclu)
di as result "===== (B) 2025 ES with elig x calendar-month FE (ref: all pre months) ====="
forvalues k = 0/5 {
    di as result "  evt +`k': " %7.4f _b[p`k'] " (" %6.4f _se[p`k'] ")"
}
* pre-trend joint test: pre-year dummies (2024 months) vs 2023, seasonal FE in
drop p0-p5
forvalues k = 1/12 {
    gen byte q`k' = elig*(evt == `k'-13)
}
quietly reghdfe mean_tip q1-q12 p* [aw=n_card] if evt < 0, absorb(unit t elig#mo) vce(cluster puclu)
quietly reghdfe mean_tip q1-q12 [aw=n_card] if evt < 0, absorb(unit t elig#mo) vce(cluster puclu)
test q1 q2 q3 q4 q5 q6 q7 q8 q9 q10 q11 q12
di as result "  joint pre-trend Wald (2024 vs 2023, seasonal FE): p = " %6.4f r(p)

*=================== (C) OD DOSE-RESPONSE ===================
import delimited "${PROJECT_ROOT}/data/cells/cells_odpair.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen mo = real(substr(ym,6,2))
gen t = ym(y,mo)
gen mean_tip = s_tip/n_card
drop if missing(mean_tip) | n_card < 25
* dose = post-period charged share per OD pair
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
gen tdose = dose*post
gen mean_fare = s_fare/n_card
gen nonsur = (s_ptt - s_cbd - s_cs)/n_card
egen odp = group(pu dozone)
egen puclu = group(pu)
reghdfe mean_tip tdose nonsur [aw=n_card], absorb(odp t) vce(cluster puclu)
di as result "===== (C) OD continuous dose: tip per unit charging probability ====="
di as result "  b(dose x post) = " %7.4f _b[tdose] " (" %6.4f _se[tdose] ///
    ")  implied rho = " %6.3f _b[tdose]/0.75
* dose-bin gradient
gen db = 1 + (dose>0.1) + (dose>0.5) + (dose>0.9)
forvalues b = 2/4 {
    gen byte g`b' = (db==`b')*post
}
reghdfe mean_tip g2 g3 g4 nonsur [aw=n_card], absorb(odp t) vce(cluster puclu)
di as result "  gradient vs dose<=0.1: mid=" %6.4f _b[g2] " (" %5.4f _se[g2] ///
    ")  high=" %6.4f _b[g3] " (" %5.4f _se[g3] ")  full=" %6.4f _b[g4] " (" %5.4f _se[g4] ")"
