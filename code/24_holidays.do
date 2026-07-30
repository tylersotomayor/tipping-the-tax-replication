version 18.0
* Purpose: holidays as a SECOND control series for the 4pm design. Legal
*          holidays are calendar weekdays on which the rush surcharge does not
*          apply, so they supply a working-day counterfactual that weekends
*          cannot: same commuting calendar, no treatment. Three deliverables:
*          (1) verify the holiday first stage is ~0 (meters program the
*              exemption); (2) the holiday placebo tip step, fare-conditioned;
*          (3) weekday-minus-holiday difference-in-discontinuities per
*              statutory dollar, wild-bootstrapped (few holiday clusters).
*          Bonus: the 8pm overnight-begins step ON holidays (overnight applies
*          every day), one more dose replication on weekday-calendar dates.
* Inputs:  data/cells/cells_minute_v3.csv
* Outputs: log values (tagged HOLIDAY) used in Sections 4-5.

import delimited "${PROJECT_ROOT}/data/cells/cells_minute_v3.csv", clear varnames(1)
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
gen mean_tip = s_tip/n_card
gen mean_ext = s_extra/n_card
gen nonsur   = (s_ptt - s_extra)/n_card
drop if missing(mean_tip)

* ---- classify each holiday by its OWN 4pm first stage ----
* The federal list is not the TLC list: Juneteenth is fully charged in all
* three years (first stages 0.90, 2.29, 2.28 against statutory doses of
* 1.00, 2.50, 2.50), the traditional holidays are cleanly exempt, and one
* observed date (Dec 26, 2022) is partially charged. Rule: exempt if the
* holiday's own first stage is below $0.50; charged if above 80 percent of
* the statutory dose; ambiguous dates are dropped from both groups.
preserve
keep if holiday & abs(mint - 960) <= 60
gen byte post = mint >= 960
collapse (mean) mean_ext [aw=n_card], by(date post)
reshape wide mean_ext, i(date) j(post)
gen fs = mean_ext1 - mean_ext0
gen dose = cond(date >= mdy(12,19,2022), 2.50, 1.00)
gen byte hexempt = fs < 0.50
gen byte hcharged = fs > 0.80*dose
di as result "HOLIDAY classification: exempt/charged/ambiguous:"
count if hexempt
local ne = r(N)
count if hcharged
local nc = r(N)
count if !hexempt & !hcharged
di as result "   `ne' exempt, `nc' charged (Juneteenth), " r(N) " ambiguous (dropped)"
keep date hexempt hcharged
tempfile HCLASS
save `HCLASS'
restore
merge m:1 date using `HCLASS', keep(1 3) nogen
replace hexempt = 0 if missing(hexempt)
replace hcharged = 0 if missing(hcharged)

* ---------------- 4pm window ----------------
preserve
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post

foreach r in 25 1 {
    local dose = cond(`r' == 25, 2.50, 1.00)

    * (1)+(2) EXEMPT holidays only: first stage and fare-conditioned tip step
    quietly tab date if regime`r' & weekday & hexempt
    local nh = r(r)
    quietly reg mean_ext post rv rvp [aw=n_card] ///
        if regime`r' & weekday & hexempt, cluster(date)
    di as result "HOLIDAY R`r' EXEMPT first stage (`nh' holidays): " ///
        %7.4f _b[post] " (" %6.4f _se[post] ")"
    quietly reg mean_tip post rv rvp nonsur [aw=n_card] ///
        if regime`r' & weekday & hexempt, cluster(date)
    di as result "HOLIDAY R`r' EXEMPT placebo tip step (fare-cond): " ///
        %7.4f _b[post] " (" %6.4f _se[post] ")"

    * (3) weekday-minus-exempt-holiday DiDisc, weekday-calendar dates only;
    *     charged and ambiguous holidays excluded from both groups
    quietly gen byte treat = !holiday if weekday & (!holiday | hexempt)
    quietly reg mean_tip c.post##i.treat c.rv##i.treat c.rvp##i.treat nonsur ///
        [aw=n_card] if regime`r' & weekday & (!holiday | hexempt), cluster(date)
    local b  = _b[1.treat#c.post]
    local se = _se[1.treat#c.post]
    di as result "HOLIDAY R`r' DiDisc (wd - exempt holiday):   " ///
        %7.4f `b' " (" %6.4f `se' ")  per statutory USD = " %6.4f (`b'/`dose')
    * wild cluster bootstrap: holiday clusters are few, analytic SEs suspect
    boottest 1.treat#c.post, reps(9999) weighttype(webb) seed(20260728) nograph
    di as result "HOLIDAY R`r' DiDisc WCB p = " %8.5f r(p)
    quietly drop treat
}

* Juneteenth: a charged weekday-calendar holiday -- holiday composition WITH
* the full dose. Thin (2-3 dates) but logged: its tip step should look like
* a treated weekday, not like the exempt holidays.
quietly reg mean_tip post rv rvp nonsur [aw=n_card] ///
    if hcharged & regime25, cluster(date)
di as result "HOLIDAY Juneteenth (charged) tip step, R25: " ///
    %7.4f _b[post] " (" %6.4f _se[post] ")  ITT/USD " %6.4f (_b[post]/2.50)
restore

* ---------------- bonus: 8pm overnight-begins ON holidays ----------------
preserve
gen rv = mint - 1200
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post
foreach r in 25 1 {
    local dose = cond(`r' == 25, 1.00, 0.50)
    quietly reg mean_ext post rv rvp [aw=n_card] ///
        if regime`r' & weekday & holiday, cluster(date)
    local fs = _b[post]
    quietly reg mean_tip post rv rvp nonsur [aw=n_card] ///
        if regime`r' & weekday & holiday, cluster(date)
    di as result "HOLIDAY R`r' 8pm overnight-begins on holidays: tip " ///
        %7.4f _b[post] " (" %6.4f _se[post] ")  FS " %6.3f `fs' ///
        "  ITT/USD " %6.4f (_b[post]/`dose')
}
restore
