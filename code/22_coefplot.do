version 18.0
* Purpose: the paper's headline exhibit -- ITT per STATUTORY surcharge dollar
*          at every locked change, on one axis: six primary clock changes, the
*          two 6am weekend changes, the two 6am weekday failures (grey), the
*          2025 CBD toll spatial estimate (no clock), and the 4pm weekend
*          placebos. Also logs: precision-weighted pooled mean of the six
*          primary changes, weekday-minus-weekend difference-in-
*          discontinuities (with and without the fare control), and MDEs
*          (2.8 x SE) for every row (ANALYSIS_PLAN.md inference block).
* Inputs:  data/cells/cells_minute_v3.csv, cells_minute_6am.csv,
*          cells_zone_v2.csv, cbd_zones.csv
* Outputs: ${FIGURES}/fig-coefplot.pdf

* ---------------- minute cells (clock designs) ----------------
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_v3.csv", clear varnames(1)
tempfile CLOCKS
save `CLOCKS'
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
gen mean_tip = s_tip/n_card
gen mean_ext = s_extra/n_card
gen nonsur   = (s_ptt - s_extra)/n_card
drop if missing(mean_tip)
tempfile MIN
save `MIN'

capture program drop cpq
program define cpq, rclass
    args c w cond dose
    preserve
    quietly keep if `cond'
    quietly gen rv = mint - `c'
    quietly keep if abs(rv) <= `w'
    quietly gen byte post = rv >= 0
    quietly gen rvp = rv*post
    quietly reg mean_tip post rv rvp nonsur [aw=n_card], cluster(date)
    return scalar itt = _b[post]/`dose'
    return scalar se  = abs(_se[post]/`dose')
    restore
end

tempfile PLOT
tempname H
postfile `H' ypos b se grp using `PLOT', replace

* row spec: ypos cutoff bw condition dose group(1=primary clock, 2=6am wd
* broken, 3=spatial, 4=placebo). 6am weekend rows are group 1 (in-family).
local sw = 0
local swb = 0
local i = 0
foreach s in ///
    `"1    960  60 "weekday & !holiday & regime25"  2.50 1"' ///
    `"2    960  60 "weekday & !holiday & regime1"   1.00 1"' ///
    `"3    1200 60 "!weekday & regime25"            1.00 1"' ///
    `"4    1200 60 "!weekday & regime1"             0.50 1"' ///
    `"5    1200 60 "weekday & !holiday & regime25" -1.50 1"' ///
    `"6    1200 60 "weekday & !holiday & regime1"  -0.50 1"' ///
    `"7    360  60 "!weekday & regime25"           -1.00 1"' ///
    `"8    360  60 "!weekday & regime1"            -0.50 1"' ///
    `"12.1 360  60 "weekday & !holiday & regime25" -1.00 2"' ///
    `"13.1 360  60 "weekday & !holiday & regime1"  -0.50 2"' ///
    `"16.5 960  60 "!weekday & regime25"            2.50 4"' ///
    `"17.5 960  60 "!weekday & regime1"             1.00 4"' {
    tokenize `"`s'"'
    local ++i
    cpq `2' `3' `"`4'"' `5'
    local b = r(itt)
    local se = r(se)
    post `H' (`1') (`b') (`se') (`6')
    di as result "COEFPLOT row ypos=`1' cond=`4' dose=`5': ITT=" %7.4f `b' ///
        " (SE " %6.4f `se' ")  MDE(2.8xSE)=" %6.4f (2.8*`se')
    * precision-weighted pooled mean over the six primary clock changes
    if `6' == 1 & `1' <= 6 {
        local sw  = `sw'  + 1/`se'^2
        local swb = `swb' + `b'/`se'^2
    }
}
local pool   = `swb'/`sw'
local poolse = sqrt(1/`sw')
di as result "COEFPLOT pooled precision-weighted mean, six primary changes: " ///
    %6.4f `pool' " (SE " %6.4f `poolse' ")"

* --------- difference-in-discontinuities, 4pm, both regimes ---------
* Weekday step minus weekend step at the same clock; holidays dropped from
* both groups (a holiday weekday carries no rush surcharge).
use `MIN', clear
drop if holiday
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp = rv*post
* The naive single difference, with and without the fare control -- the size
* of the omitted-fare bias the text quotes ("inflates the step by a third").
quietly reg mean_tip post rv rvp [aw=n_card] if regime25 & weekday, cluster(date)
di as result "NAIVE  wd R25, no fare control:  " %7.4f _b[post] " (" %6.4f _se[post] ")"
quietly reg mean_tip post rv rvp nonsur [aw=n_card] if regime25 & weekday, cluster(date)
di as result "SINGLE wd R25, fare-conditioned: " %7.4f _b[post] " (" %6.4f _se[post] ")"
quietly reg mean_tip post rv rvp [aw=n_card] if regime25 & !weekday, cluster(date)
di as result "NAIVE  we R25 placebo, no fare control:  " %7.4f _b[post] " (" %6.4f _se[post] ")"
quietly reg mean_tip post rv rvp nonsur [aw=n_card] if regime25 & !weekday, cluster(date)
di as result "SINGLE we R25 placebo, fare-conditioned: " %7.4f _b[post] " (" %6.4f _se[post] ")"
foreach r in 25 1 {
    local dose = cond(`r' == 25, 2.50, 1.00)
    quietly reg mean_tip c.post##i.weekday c.rv##i.weekday c.rvp##i.weekday ///
        nonsur [aw=n_card] if regime`r', cluster(date)
    di as result "DIDISC R`r' (wd-we, fare-conditioned): " ///
        %7.4f _b[1.weekday#c.post] " (" %6.4f _se[1.weekday#c.post] ///
        ")  per statutory USD = " %6.4f (_b[1.weekday#c.post]/`dose')
    quietly reg mean_tip c.post##i.weekday c.rv##i.weekday c.rvp##i.weekday ///
        [aw=n_card] if regime`r', cluster(date)
    di as result "DIDISC R`r' (wd-we, NO fare control):  " ///
        %7.4f _b[1.weekday#c.post] " (" %6.4f _se[1.weekday#c.post] ///
        ")  per statutory USD = " %6.4f (_b[1.weekday#c.post]/`dose')
}

* --------- JFK flat-fare rows (RatecodeID 2; see 25_jfk.do) ---------
* The JFK fare is flat, so the fare-jump confound is structurally absent;
* the same cpq program applies with the JFK statutory doses.
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
gen mean_tip = s_tip/n_card
gen mean_ext = s_extra/n_card
gen nonsur   = (s_ptt - s_extra)/n_card
drop if missing(mean_tip)
cpq 960 60 "weekday & !holiday & regime25" 5.00
post `H' (9.4) (`r(itt)') (`r(se)') (5)
di as result "COEFPLOT JFK R25 (+USD 5.00): ITT=" %7.4f r(itt) " (SE " %6.4f r(se) ")"
cpq 960 60 "weekday & !holiday & regime1" 4.50
post `H' (10.4) (`r(itt)') (`r(se)') (5)
di as result "COEFPLOT JFK R1  (+USD 4.50): ITT=" %7.4f r(itt) " (SE " %6.4f r(se) ")"

* --------- 2025 CBD toll, spatial pooled OD estimate ---------
* Spec identical to code/12_spatial_v2.do (2025 block): OD eligibility,
* window 2024m1-2025m6, unit = pu x doin x fbin FE, month FE, cluster pu.
* ITT per statutory dollar divides the tip DiD by the $0.75 statutory toll.
import delimited "${PROJECT_ROOT}/data/cells/cells_zone_v2.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen mo = real(substr(ym,6,2))
gen t = ym(y,mo)
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
keep if inrange(t, ym(2024,1), ym(2025,6))
gen byte post = t >= ym(2025,1)
gen byte tp = elig*post
reghdfe mean_tip tp [aw=n_card], absorb(unit t) vce(cluster puclu)
local sb = _b[tp]/0.75
local sse = _se[tp]/0.75
post `H' (14.8) (`sb') (`sse') (3)
di as result "COEFPLOT spatial 2025 OD: tip DiD=" %7.4f _b[tp] " (" ///
    %6.4f _se[tp] ")  ITT per statutory USD=" %6.4f `sb' " (SE " %6.4f `sse' ")"
postclose `H'

* ---------------- draw ----------------
use `PLOT', clear
gen lo = b - 1.96*se
gen hi = b + 1.96*se
* persist for restyled variants (poster) so they need not re-estimate
capture mkdir "${PROJECT_ROOT}/data/intermediate"
save "${PROJECT_ROOT}/data/intermediate/coefplot_data.dta", replace
set scheme s1mono
twoway ///
    (rcap lo hi ypos if grp==1, horizontal lcolor(navy) lwidth(medthin)) ///
    (scatter ypos b if grp==1, mcolor(navy) msymbol(O) msize(medium)) ///
    (rcap lo hi ypos if grp==2, horizontal lcolor(gs10) lwidth(medthin)) ///
    (scatter ypos b if grp==2, mcolor(gs10) msymbol(O) msize(medium)) ///
    (rcap lo hi ypos if grp==3, horizontal lcolor(teal) lwidth(medthin)) ///
    (scatter ypos b if grp==3, mcolor(teal) msymbol(D) msize(medium)) ///
    (rcap lo hi ypos if grp==4, horizontal lcolor(navy) lwidth(medthin)) ///
    (scatter ypos b if grp==4, mcolor(white) mlcolor(navy) msymbol(O) msize(medium)) ///
    (rcap lo hi ypos if grp==5, horizontal lcolor(navy) lwidth(medthin)) ///
    (scatter ypos b if grp==5, mcolor(navy) msymbol(S) msize(medium)) ///
    , xline(0, lcolor(gs8)) ///
    xline(`pool', lcolor(navy) lpattern(dash) lwidth(thin)) ///
    yline(8.9, lcolor(gs14)) yline(11.25, lcolor(gs14)) yline(13.95, lcolor(gs14)) yline(15.65, lcolor(gs14)) ///
    yscale(reverse range(0.4 18.1)) ///
    ylabel(1 "Rush begins, 4pm wd, +USD 2.50" ///
           2 "Rush begins, 4pm wd, +USD 1.00" ///
           3 "Overnight begins, 8pm we, +USD 1.00" ///
           4 "Overnight begins, 8pm we, +USD 0.50" ///
           5 "Rush ends, 8pm wd, net -USD 1.50" ///
           6 "Rush ends, 8pm wd, net -USD 0.50" ///
           7 "Overnight ends, 6am we, -USD 1.00" ///
           8 "Overnight ends, 6am we, -USD 0.50" ///
           9.4 "JFK flat fare, 4pm wd, +USD 5.00" ///
           10.4 "JFK flat fare, 4pm wd, +USD 4.50" ///
           12.1 "Overnight ends, 6am wd, -USD 1.00" ///
           13.1 "Overnight ends, 6am wd, -USD 0.50" ///
           14.8 "2025 CBD toll (spatial, no clock)" ///
           16.5 "4pm weekend placebo, USD 2.50 era" ///
           17.5 "4pm weekend placebo, USD 1.00 era" ///
           , angle(0) labsize(small) nogrid noticks) ///
    xlabel(-0.2(0.1)0.3, format(%3.1f)) ///
    xtitle("Tip response per statutory surcharge dollar", size(medsmall)) ///
    ytitle("") legend(off) ///
    text(17.9 `pool' "pooled clock mean", size(vsmall) color(navy) placement(e)) ///
    xsize(7.6) ysize(5.2)
graph export "${FIGURES}/fig-coefplot.pdf", as(pdf) replace
di as result "wrote fig-coefplot.pdf"

* --------- FUZZY difference-in-discontinuities (three-row presentation) ---
* First stage: weekday-weekend difference in the SURCHARGE discontinuity.
* Reduced form: same difference for tips (the sharp-DiDisc delta above).
* Fuzzy DiDisc = just-identified 2SLS with (post x weekday) as the excluded
* instrument; controls: post, weekday, running-variable terms by day type,
* and the non-surcharge base.
use `MIN', clear
drop if holiday
gen rv = mint - 960
keep if abs(rv) <= 60
gen byte post = rv >= 0
gen rvp  = rv*post
gen rvw  = rv*weekday
gen rvpw = rvp*weekday
gen pw   = post*weekday
foreach r in 25 1 {
    quietly reg mean_ext pw post weekday rv rvp rvw rvpw nonsur ///
        [aw=n_card] if regime`r', cluster(date)
    di as result "FDIDISC R`r' first stage (Delta RD_D): " %7.4f _b[pw] ///
        " (" %6.4f _se[pw] ")"
    quietly reg mean_tip pw post weekday rv rvp rvw rvpw nonsur ///
        [aw=n_card] if regime`r', cluster(date)
    di as result "FDIDISC R`r' reduced form (Delta RD_Y): " %7.4f _b[pw] ///
        " (" %6.4f _se[pw] ")"
    quietly ivregress 2sls mean_tip (mean_ext = pw) post weekday rv rvp ///
        rvw rvpw nonsur [aw=n_card] if regime`r', vce(cluster date)
    di as result "FDIDISC R`r' fuzzy 2SLS (tau): " %7.4f _b[mean_ext] ///
        " (" %6.4f _se[mean_ext] ")"
}
