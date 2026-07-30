version 18.0
* Purpose: "Who passes it through" -- the mechanism decomposition at full
*          sample and locked spec. For each tipping category (button /
*          whole-dollar / other custom / zero), estimate the weekday-weekend
*          difference-in-discontinuities at 4pm in each regime: the category's
*          mean tip (among its own trips) and its share of trips. Prediction
*          from the base-arithmetic mechanism: button and custom-percentage
*          tips carry the pass-through; whole-dollar tips are inert; shares
*          do not move at the cutoff.
* Inputs:  data/cells/cells_minute_decomp.csv (build_cells_decomp.py)
* Outputs: log values (tagged DECOMP) + ${TABLES}/tab-decomp.tex

import delimited "${PROJECT_ROOT}/data/cells/cells_minute_decomp.csv", clear varnames(1)
* a few trips are dated outside their file's month, producing duplicate
* (d,mint) keys across adjacent monthly files -- sum them
collapse (sum) n_card s_allin n_btn s_btn n_whole s_whole n_other s_other n_zero, by(d mint)
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
drop if holiday & weekday          // holiday weekdays: neither treated nor control here
gen byte regime1  = date <  mdy(12,19,2022)
gen byte regime25 = date >= mdy(12,19,2022)
* Non-surcharge base control (eq. didisc's B) from the v3 cells: the decomp
* builder's s_allin INCLUDES the surcharge, so conditioning on it would
* absorb the treatment. Merge the card-consistent moments instead.
preserve
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_v3.csv", clear varnames(1)
keep d mint s_ptt s_extra n_card
collapse (sum) s_ptt s_extra n_card, by(d mint)   // same straggler dedupe
gen nonsur = (s_ptt - s_extra)/n_card
keep d mint nonsur
tempfile NS
save `NS'
restore
merge 1:1 d mint using `NS', keep(3) nogen
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post

tempname fh
file open `fh' using "${TABLES}/tab-decomp.tex", write replace

foreach r in 25 1 {
    local dose = cond(`r' == 25, 2.50, 1.00)
    di as result "===== DECOMP regime `r' (dose `dose') ====="
    foreach c in btn whole other {
        * category mean tip among the category's own trips
        capture drop mt w
        quietly gen mt = s_`c'/n_`c'
        quietly gen w = n_`c'
        quietly reg mt c.post##i.weekday c.rv##i.weekday c.rvp##i.weekday ///
            nonsur [aw=w] if regime`r' & !missing(mt), cluster(date)
        local b  = _b[1.weekday#c.post]
        local se = _se[1.weekday#c.post]
        di as result "DECOMP R`r' `c' TIP DiDisc: " %7.4f `b' " (" %6.4f `se' ///
            ")  per statutory USD = " %6.4f (`b'/`dose')
        if `r' == 25 {
            local lab = cond("`c'"=="btn","Exact-button tips", ///
                        cond("`c'"=="whole","Whole-dollar tips","Custom (non-round) tips"))
            file write `fh' "`lab' & " %7.3f (`b') " & (" %6.3f (`se') ///
                ") & " %6.3f (`b'/`dose') " \\" _n
        }
    }
    * category SHARES: composition response at the cutoff
    foreach c in btn whole other zero {
        capture drop sh
        quietly gen sh = n_`c'/n_card
        quietly reg sh c.post##i.weekday c.rv##i.weekday c.rvp##i.weekday ///
            [aw=n_card] if regime`r', cluster(date)
        di as result "DECOMP R`r' `c' SHARE DiDisc: " %8.5f _b[1.weekday#c.post] ///
            " (" %7.5f _se[1.weekday#c.post] ")"
        if `r' == 25 & "`c'" != "zero" {
            local lab2 = cond("`c'"=="btn","\quad share of trips", "\quad share of trips")
        }
    }
}
* share rows for the table (regime 25)
foreach c in btn whole other zero {
    capture drop sh
    quietly gen sh = n_`c'/n_card
    quietly reg sh c.post##i.weekday c.rv##i.weekday c.rvp##i.weekday ///
        [aw=n_card] if regime25, cluster(date)
    local lab = cond("`c'"=="btn","Share: button", ///
                cond("`c'"=="whole","Share: whole-dollar", ///
                cond("`c'"=="other","Share: custom","Share: zero tip")))
    file write `fh' "`lab' & " %8.4f (_b[1.weekday#c.post]) " & (" ///
        %7.4f (_se[1.weekday#c.post]) ") & --- \\" _n
}
file close `fh'
di as result "wrote tab-decomp.tex"
