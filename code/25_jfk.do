version 18.0
* Purpose: the JFK flat-fare design (RatecodeID 2, analysed separately per
*          Amendment 2). The JFK fare is FLAT, so the metered fare cannot jump
*          at 4:00pm by construction -- the fare-jump confound of the main
*          design is structurally absent -- and the statutory rush dose is
*          $5.00 (post-2022), twice the largest dose in the main design. This
*          is the out-of-sample test of dose linearity, on the population the
*          main sample excludes.
* Inputs:  data/cells/cells_minute_jfk.csv
* Outputs: log values (tagged JFK) used in Sections 4-5.

import delimited "${PROJECT_ROOT}/data/cells/cells_minute_jfk.csv", clear varnames(1)
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
gen mean_tip  = s_tip/n_card
gen mean_ext  = s_extra/n_card
gen nonsur    = (s_ptt - s_extra)/n_card
gen mean_fare = s_fare/n_card
gen mean_dur  = s_dur/n_card
gen sh_card   = n_card/n_all
gen sh_zero   = n_zero/n_card
gen sh_exact  = n_exact/n_card
drop if missing(mean_tip)

* ---------------- descriptives ----------------
quietly sum mean_fare [aw=n_card] if regime25 & weekday & !holiday
di as result "JFK mean flat fare, R25 weekdays: " %6.2f r(mean)
quietly sum mean_tip [aw=n_card] if regime25 & weekday & !holiday
di as result "JFK mean card tip,  R25 weekdays: " %6.2f r(mean)
quietly sum sh_exact [aw=n_card] if regime25 & weekday & !holiday
di as result "JFK exact-default share, R25:     " %6.3f r(mean)

* ---------------- 4pm design ----------------
preserve
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post

* balance: the flat fare CANNOT jump; verify, along with duration/card/zero
di as result "JFK BALANCE at 4pm (weekday, R25):"
foreach y in mean_fare mean_dur sh_card nonsur {
    quietly sum `y' [aw=n_card] if regime25 & weekday & !holiday & !post
    local m0 = r(mean)
    quietly reg `y' post rv rvp [aw=n_card] ///
        if regime25 & weekday & !holiday, cluster(date)
    di as result "   `y': jump = " %8.4f _b[post] " (" %7.4f _se[post] ///
        ")  pre-mean = " %8.3f `m0'
}

foreach r in 25 1 {
    * statutory JFK rush dose: $5.00 post-Dec-2022; pre-period dose taken
    * from the measured composition (logged by the builder: the pre-2022
    * regime shows the dose the meters actually carried).
    local dose = cond(`r' == 25, 5.00, 4.50)
    quietly reg mean_ext post rv rvp [aw=n_card] ///
        if regime`r' & weekday & !holiday, cluster(date)
    local fs = _b[post]
    di as result "JFK R`r' first stage: " %6.3f `fs' " (" %6.4f _se[post] ")"
    quietly reg mean_tip post rv rvp nonsur [aw=n_card] ///
        if regime`r' & weekday & !holiday, cluster(date)
    di as result "JFK R`r' tip step (fare-cond): " %7.4f _b[post] " (" ///
        %6.4f _se[post] ")  ITT per statutory USD (dose `dose') = " ///
        %6.4f (_b[post]/`dose')
    di as result "JFK R`r' per RECORDED dollar (tip step / first stage): " ///
        %6.4f (_b[post]/`fs')
    quietly reg mean_tip post rv rvp [aw=n_card] ///
        if regime`r' & weekday & !holiday, cluster(date)
    di as result "JFK R`r' tip step (NO controls): " %7.4f _b[post] " (" ///
        %6.4f _se[post] ")  ITT/USD = " %6.4f (_b[post]/`dose')
    * behavioral margins at the cutoff
    foreach y in sh_exact sh_zero sh_card {
        quietly reg `y' post rv rvp [aw=n_card] ///
            if regime`r' & weekday & !holiday, cluster(date)
        di as result "JFK R`r' `y' step: " %8.5f _b[post] " (" %7.5f _se[post] ")"
    }
    * weekend placebo: no JFK rush surcharge on weekends
    quietly reg mean_ext post rv rvp [aw=n_card] if regime`r' & !weekday, cluster(date)
    local pfs = _b[post]
    quietly reg mean_tip post rv rvp nonsur [aw=n_card] ///
        if regime`r' & !weekday, cluster(date)
    di as result "JFK R`r' WEEKEND placebo: tip " %7.4f _b[post] " (" ///
        %6.4f _se[post] ")  FS " %6.3f `pfs'
}

* JFK mechanical benchmark: pre-cutoff tip rate x statutory dose
quietly sum mean_tip [aw=n_card] if regime25 & weekday & !holiday & !post
local t0 = r(mean)
quietly sum s_ptt [aw=n_card] if regime25 & weekday & !holiday & !post
quietly gen tiprate = s_tip/s_ptt
quietly sum tiprate [aw=n_card] if regime25 & weekday & !holiday & !post
local rate = r(mean)
di as result "JFK pre-4pm tip rate R25: " %6.4f `rate' ///
    "  mechanical benchmark (rate x 5.00): " %6.3f (`rate'*5.00)
restore
