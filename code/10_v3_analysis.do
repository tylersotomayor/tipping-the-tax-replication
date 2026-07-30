version 18.0
* Purpose: v3 estimation per Amendments 1-2. Standard-rate card trips only;
*          treatment = statutory dose (deterministic in pickup minute);
*          all moments card-consistent; IV for rho with joint inference;
*          balance table; ALL locked outcomes incl. 6am; placebos both sides.
* Inputs:  data/cells/cells_minute_v3.csv

* The 4pm/8pm windows and the 6am window are built separately (the v3 builder
* never collected 05:00-07:00; see code/py/build_cells_6am.py). Identical
* schema, so they append.
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_v3.csv", clear varnames(1)
tempfile CLOCKS
save `CLOCKS'
capture confirm file "${PROJECT_ROOT}/data/cells/cells_minute_6am.csv"
if _rc {
    di as error "MISSING: data/cells/cells_minute_6am.csv (run code/py/build_cells_6am.py)"
    exit 601
}
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_6am.csv", clear varnames(1)
append using `CLOCKS'
gen date = date(d, "YMD")
format date %td
keep if inrange(date, mdy(9,1,2021), mdy(9,30,2024))
gen dow = dow(date)
gen byte weekday = inrange(dow, 1, 5)
gen byte holiday = 0
foreach h in "25nov2021" "24dec2021" "31dec2021" "17jan2022" "21feb2022" ///
    "30may2022" "20jun2022" "4jul2022" "5sep2022" "24nov2022" "26dec2022" ///
    "2jan2023" "16jan2023" "20feb2023" "29may2023" "19jun2023" "4jul2023" ///
    "4sep2023" "23nov2023" "25dec2023" "1jan2024" "15jan2024" "19feb2024" ///
    "27may2024" "19jun2024" "4jul2024" "2sep2024" {
    quietly replace holiday = 1 if date == date("`h'", "DMY")
}
gen byte regime1  = date <  mdy(12,19,2022)
gen byte regime25 = date >= mdy(12,19,2022)
* card-consistent means (every numerator and denominator from card trips)
gen mean_tip   = s_tip/n_card
gen mean_ext   = s_extra/n_card
gen nonsur     = (s_ptt - s_extra)/n_card
gen mean_fare  = s_fare/n_card
gen mean_dist  = s_dist/n_card
gen mean_dur   = s_dur/n_card
gen sh_card    = n_card/n_all
gen sh_v2      = n_v2/n_card
gen sh_zero    = n_zero/n_card
gen sh_exact   = n_exact/n_card
gen sh_ex250   = n_ex250/n_card
gen sh_ex100   = n_ex100/n_card
gen sh_ex0     = n_ex0/n_card
drop if missing(mean_tip)

capture program drop v3rd
program define v3rd, rclass
    * cutoff window cond dose(statutory,0=skip) label
    args c w cond dose lab
    preserve
    quietly keep if `cond'
    quietly gen rv = mint - `c'
    quietly keep if abs(rv) <= `w'
    quietly gen byte post = rv >= 0
    quietly gen rvp = rv*post
    * ITT with fare-conditioning
    quietly reg mean_tip post rv rvp nonsur [aw=n_card], cluster(date)
    local rf = _b[post]
    local rfse = _se[post]
    * IV: measured card-sample surcharge instrumented by post (JOINT inference)
    quietly ivregress 2sls mean_tip (mean_ext = post) rv rvp nonsur ///
        [aw=n_card], vce(cluster date)
    local riv = _b[mean_ext]
    local rivse = _se[mean_ext]
    quietly reg mean_ext post rv rvp nonsur [aw=n_card], cluster(date)
    local fs = _b[post]
    if abs(`dose') > 0 {
        local itt = `rf'/`dose'
        local ittse = abs(`rfse'/`dose')
        di as result "`lab': RF=" %7.4f `rf' " (" %6.4f `rfse' ")  FS(extra)=" ///
            %6.3f `fs' "  ITT/dose=" %6.3f `itt' " (" %5.3f `ittse' ///
            ")  rho_IV=" %6.3f `riv' " (" %5.3f `rivse' ")"
    }
    else {
        di as result "`lab': RF=" %7.4f `rf' " (" %6.4f `rfse' ")  FS(extra)=" %6.3f `fs'
    }
    return scalar rf = `rf'
    return scalar rfse = `rfse'
    restore
end

di as result "===== V3: BALANCE AT THE 4PM CUTOFF (weekday, R25) ====="
preserve
quietly keep if weekday & !holiday & regime25 & inrange(mint, 900, 1020)
quietly gen rv = mint - 960
quietly gen byte post = rv >= 0
quietly gen rvp = rv*post
foreach y in mean_fare mean_dist mean_dur sh_card sh_v2 nonsur {
    quietly sum `y' [aw=n_card] if !post
    local m0 = r(mean)
    quietly reg `y' post rv rvp [aw=n_card], cluster(date)
    di as result "   `y': jump = " %8.4f _b[post] " (" %7.4f _se[post] ///
        ")   pre-mean = " %8.3f `m0'
}
restore

di as result "===== V3: MAIN ESTIMATES (statutory dose; IV joint inference) ====="
v3rd 960 60 "weekday & !holiday & regime25" 2.50 "4pm wd R25"
v3rd 960 60 "weekday & !holiday & regime1"  1.00 "4pm wd R1 "
v3rd 960 60 "!weekday & regime25" 0 "4pm we R25 (placebo)"
v3rd 960 60 "!weekday & regime1"  0 "4pm we R1  (placebo)"

di as result "===== V3: ALL LOCKED CLOCKS (incl. 6am) ====="
v3rd 1200 60 "weekday & !holiday & regime25" -1.50 "8pm wd R25 (down)"
v3rd 1200 60 "weekday & !holiday & regime1"  -0.50 "8pm wd R1  (down)"
v3rd 1200 60 "!weekday & regime25" 1.00 "8pm we R25 (up)"
v3rd 1200 60 "!weekday & regime1"  0.50 "8pm we R1  (up)"
* 6:00am: the overnight surcharge ENDS, so the step is downward. It applies on
* every day of the week, so weekdays and weekends are both treated (there is
* no weekend placebo at this clock -- that asymmetry is reported, not hidden).
v3rd 360 60 "weekday & !holiday & regime25" -1.00 "6am wd R25 (down)"
v3rd 360 60 "weekday & !holiday & regime1"  -0.50 "6am wd R1  (down)"
v3rd 360 60 "!weekday & regime25"           -1.00 "6am we R25 (down)"
v3rd 360 60 "!weekday & regime1"            -0.50 "6am we R1  (down)"
* Composition of the surcharge field at each cutoff (Amendment 2, item 4):
* what the `extra` discontinuity is actually made of.
di as result "===== V3: SURCHARGE-FIELD COMPOSITION AT EACH CUTOFF ====="
foreach spec in "960 25 4pm" "1200 25 8pm" "360 25 6am" {
    tokenize "`spec'"
    preserve
    quietly keep if weekday & !holiday & regime`2' & abs(mint - `1') <= 60
    quietly gen byte post = (mint - `1') >= 0
    foreach c in ex0 ex100 ex250 {
        quietly sum sh_`c' [aw=n_card] if !post
        local a = r(mean)
        quietly sum sh_`c' [aw=n_card] if post
        di as result "   `3' share extra==`c': pre=" %5.3f `a' "  post=" %5.3f r(mean)
    }
    restore
}

di as result "===== V3: PLACEBO CUTOFFS - BOTH SIDES REPORTED ====="
v3rd 915 20 "weekday & !holiday & regime25" 0 "3:15pm placebo"
v3rd 1020 20 "weekday & !holiday & regime25" 0 "5:00pm placebo"

di as result "===== V3: PERMUTATION, uncontaminated cutoffs (bandwidth-matched) ====="
* Every candidate cutoff -- true and placebo alike -- is estimated with the
* SAME specification and the SAME bandwidth (+/-30), so the placebo
* distribution is comparable to the actual statistic. Candidates are drawn
* from minutes whose +/-30 window never crosses 4:00pm, i.e. entirely before
* the surcharge switches on or entirely after it is already in force.
preserve
quietly keep if weekday & !holiday & regime25
* --- actual statistic at the true cutoff, bandwidth 30 ---
quietly {
    gen rv = mint - 960
    gen byte post = rv >= 0
    gen rvp = rv*post
    reg mean_tip post rv rvp nonsur [aw=n_card] if abs(rv) <= 30, cluster(date)
}
local actual = abs(_b[post])
di as result "   actual |RF| at 4:00pm (bw 30) = " %7.4f `actual'
local nbig = 0
local nn = 0
quietly {
    foreach c of numlist 900/929 991/1020 {
        capture drop rv post rvp
        gen rv = mint - `c'
        gen byte post = rv >= 0
        gen rvp = rv*post
        capture reg mean_tip post rv rvp nonsur [aw=n_card] ///
            if abs(rv) <= 30, cluster(date)
        if _rc == 0 {
            local ++nn
            if abs(_b[post]) >= `actual' local ++nbig
        }
    }
}
di as result "   placebo cutoffs with |RF| >= actual: " `nbig' " of " `nn'
restore

di as result "===== V3: WILD CLUSTER BOOTSTRAP on corrected RF ====="
preserve
quietly keep if weekday & !holiday & regime25
quietly gen rv = mint - 960
quietly keep if abs(rv) <= 60
quietly gen byte post = rv >= 0
quietly gen rvp = rv*post
quietly reg mean_tip post rv rvp nonsur [aw=n_card], cluster(date)
boottest post, reps(9999) weighttype(webb) seed(20260727) nograph
di as result "   WCB p = " %10.2e r(p)
restore
