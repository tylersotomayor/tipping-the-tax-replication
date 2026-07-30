version 18.0
* Purpose: Columbia-palette re-renders of the four poster chart panels.
*          Writes to poster/figures/ ONLY -- the paper's figures in
*          output/figures/ keep the house style. Palette: Columbia navy
*          (24 72 144), Columbia blue (108 172 228), light blue fill
*          (185 217 235), grey, carnelian accent (179 27 27).
* Inputs:  data/cells/spikes.csv, cells_minute_v3.csv,
*          data/intermediate/coefplot_data.dta (saved by 22_coefplot.do)
* Outputs: poster/figures/fig-spikes.pdf, fig-4pm.pdf, fig-coefplot.pdf,
*          fig-dec22.pdf

set scheme s1mono
* match the poster type system: sans-serif inside every figure
graph set window fontface "Helvetica Neue"
global PFIG "${PROJECT_ROOT}/poster/figures"

* ---------------- A. spikes ----------------
import delimited "${PROJECT_ROOT}/data/cells/spikes.csv", clear varnames(1)
bysort base: egen tot = total(n)
gen share = 100*n/tot
quietly sum share if base == "allin" & abs(bin-20) < 0.01
local s20 : display %4.1f r(mean)
quietly sum share if base == "allin" & abs(bin-25) < 0.01
local s25 : display %3.1f r(mean)
quietly sum share if base == "allin" & abs(bin-30) < 0.01
local s30 : display %3.1f r(mean)
quietly sum share if base == "fare"
local fmax : display %3.1f r(max)
twoway (bar share bin if base == "allin", color("24 72 144") barwidth(0.45)), ///
    ylabel(0(10)60, angle(0)) xlabel(5(5)40) xtitle("") ///
    ytitle("Percent of tips") ///
    text(60 20 "`s20'%", size(small) color("24 72 144")) ///
    text(11.5 25 "`s25'%", size(small) color("24 72 144")) ///
    text(6.2 30 "`s30'%", size(small) color("24 72 144")) ///
    title("A. As a percentage of the fee-inclusive total (the buttons' base)", ///
        size(medsmall) color(black) position(11)) ///
    name(gA, replace) nodraw
twoway (bar share bin if base == "fare", color("108 172 228") barwidth(0.45)), ///
    ylabel(0(10)60, angle(0)) xlabel(5(5)40) ///
    xtitle("Tip as a percentage of the candidate base") ///
    ytitle("Percent of tips") ///
    text(9 32.5 "largest bin: `fmax' percent", size(small) color("108 172 228")) ///
    title("B. The same tips as a percentage of the metered fare alone", ///
        size(medsmall) color(black) position(11)) ///
    name(gB, replace) nodraw
graph combine gA gB, col(1) imargin(2 2 1 1) xsize(6.4) ysize(6.0)
graph export "${PFIG}/fig-spikes.pdf", as(pdf) replace

* ---------------- B. 4pm minute plot ----------------
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_v3.csv", clear varnames(1)
gen date = date(d, "YMD")
keep if inrange(date, mdy(9,1,2021), mdy(9,30,2024))
gen dow = dow(date)
keep if inrange(dow, 1, 5)
gen byte holiday = 0
foreach h in "25nov2021" "24dec2021" "31dec2021" "17jan2022" "21feb2022" ///
    "30may2022" "20jun2022" "4jul2022" "5sep2022" "24nov2022" "26dec2022" ///
    "2jan2023" "16jan2023" "20feb2023" "29may2023" "19jun2023" "4jul2023" ///
    "4sep2023" "23nov2023" "25dec2023" "1jan2024" "15jan2024" "19feb2024" ///
    "27may2024" "19jun2024" "4jul2024" "2sep2024" {
    quietly replace holiday = 1 if date == date("`h'", "DMY")
}
drop if holiday
gen byte regime25 = date >= mdy(12,19,2022)
gen rv = mint - 960
keep if abs(rv) <= 60
collapse (sum) s_tip n_card, by(rv regime25)
gen mtip = s_tip/n_card
twoway (scatter mtip rv if !regime25, mcolor("108 172 228") msize(small)) ///
       (scatter mtip rv if regime25,  mcolor("24 72 144")  msize(small)), ///
    xline(0, lcolor(gs6) lpattern(dash)) ///
    xtitle("Minutes relative to 4:00pm (weekdays)") ///
    ytitle("Mean credit-card tip (USD)") ///
    legend(order(2 "USD 2.50 surcharge (2023-24)" 1 "USD 1.00 surcharge (2021-22)") ///
        ring(0) position(4) cols(1) region(lstyle(none))) ///
    xsize(6.4) ysize(4.4)
graph export "${PFIG}/fig-4pm.pdf", as(pdf) replace

* ---------------- C. coefplot ----------------
use "${PROJECT_ROOT}/data/intermediate/coefplot_data.dta", clear
quietly sum b [aw=1/se^2] if grp == 1 & ypos <= 6
local pool = r(mean)
twoway ///
    (rcap lo hi ypos if grp==1, horizontal lcolor("24 72 144") lwidth(medthin)) ///
    (scatter ypos b if grp==1, mcolor("24 72 144") msymbol(O) msize(medium)) ///
    (rcap lo hi ypos if grp==2, horizontal lcolor(gs10) lwidth(medthin)) ///
    (scatter ypos b if grp==2, mcolor(gs10) msymbol(O) msize(medium)) ///
    (rcap lo hi ypos if grp==3, horizontal lcolor("179 27 27") lwidth(medthin)) ///
    (scatter ypos b if grp==3, mcolor("179 27 27") msymbol(D) msize(medium)) ///
    (rcap lo hi ypos if grp==4, horizontal lcolor("24 72 144") lwidth(medthin)) ///
    (scatter ypos b if grp==4, mcolor(white) mlcolor("24 72 144") msymbol(O) msize(medium)) ///
    (rcap lo hi ypos if grp==5, horizontal lcolor("108 172 228") lwidth(medthin)) ///
    (scatter ypos b if grp==5, mcolor("108 172 228") msymbol(S) msize(medium)) ///
    , xline(0, lcolor(gs8)) ///
    xline(`pool', lcolor("24 72 144") lpattern(dash) lwidth(thin)) ///
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
    text(17.9 `pool' "pooled clock mean", size(vsmall) color("24 72 144") placement(e)) ///
    xsize(7.6) ysize(5.2)
graph export "${PFIG}/fig-coefplot.pdf", as(pdf) replace

* ---------------- D. Dec-2022 repricing ----------------
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_v3.csv", clear varnames(1)
gen date = date(d, "YMD")
keep if inrange(date, mdy(6,20,2022), mdy(6,19,2023))
gen dow = dow(date)
keep if inrange(dow, 1, 5)
gen byte rush = inrange(mint, 960, 1050)
keep if rush | inrange(mint, 870, 955)
collapse (sum) s_tip s_ptt, by(date rush)
gen rate = 100*s_tip/s_ptt
gen wk = floor((date - mdy(12,19,2022))/7)
collapse (mean) rate, by(wk rush)
keep if inrange(wk, -15, 12)
reshape wide rate, i(wk) j(rush)
gen gap = rate1 - rate0
quietly sum gap if wk < 0
local g0 = r(mean)
gen gapc = gap - `g0'
twoway (connected gapc wk, mcolor("24 72 144") lcolor("24 72 144") msize(medsmall)), ///
    xline(0, lcolor(gs6) lpattern(dash)) ///
    yline(0, lcolor(gs10) lpattern(dash)) ///
    yline(-1.1, lcolor("179 27 27") lpattern(dash)) ///
    yscale(range(-1.3 0.42)) ylabel(-1.2(0.4)0.4, labsize(medium) format(%3.1f)) ///
    xlabel(-15(5)10, labsize(medium)) ///
    xtitle("Weeks relative to December 19, 2022 repricing", size(medium)) ///
    ytitle("Change in the rush{&minus}pre-rush gap (pp)", size(medium)) ///
    text(0.13 6 "pre-period average", size(medsmall) color(gs8) placement(e)) ///
    text(-0.99 -15 "full pushback: tips defended in dollars ({&minus}1.1 pts)", ///
        size(medsmall) color("179 27 27") placement(e)) ///
    text(-0.46 4 "observed: {&minus}0.22 pts", size(medsmall) color("24 72 144") placement(e)) ///
    legend(off) xsize(6.4) ysize(3.8)
graph export "${PFIG}/fig-dec22.pdf", as(pdf) replace
di as result "poster figures re-rendered in Columbia palette"

* ================= POSTER-EDITION VARIANTS (editorial pass) =================
* Single-frame spikes: navy bars = vs all-in base; light outline = the same
* tips vs the fare alone. One frame, one contrast.
import delimited "${PROJECT_ROOT}/data/cells/spikes.csv", clear varnames(1)
bysort base: egen tot = total(n)
gen share = 100*n/tot
quietly sum share if base == "allin" & abs(bin-20) < 0.01
local s20 : display %4.1f r(mean)
quietly sum share if base == "fare"
local fmax : display %3.1f r(max)
twoway (bar share bin if base == "allin", color("24 72 144") barwidth(0.45)) ///
       (bar share bin if base == "fare", color(none) lcolor("108 172 228") ///
            lwidth(medthick) barwidth(0.45)), ///
    ylabel(0(20)60, angle(0) labsize(medsmall)) xlabel(5(5)40, labsize(medsmall)) ///
    xtitle("Tip as a percentage of the base", size(medsmall)) ///
    ytitle("Percent of tips", size(medsmall)) ///
    plotregion(style(none)) legend(off) xsize(6.4) ysize(3.6)
graph export "${PFIG}/fig-spikes-poster.pdf", as(pdf) replace

* Pruned 9-row coefplot, poster type sizes
use "${PROJECT_ROOT}/data/intermediate/coefplot_data.dta", clear
quietly sum b [aw=1/se^2] if grp == 1 & ypos <= 6
local pool = r(mean)
* keep: 4pm x2, 8pm we +1.00, 8pm wd -1.50, JFK x2, one 6am-wd failure,
* spatial, one placebo
gen keep = inlist(ypos,1,2,3,5) | inrange(ypos,9.3,10.5) | ///
    inrange(ypos,14.7,14.9) | inrange(ypos,16.4,16.6)
keep if keep
gen row = .
replace row = 1 if ypos==1
replace row = 2 if ypos==2
replace row = 3 if ypos==3
replace row = 4 if ypos==5
replace row = 5 if inrange(ypos,9.3,9.5)
replace row = 6 if inrange(ypos,10.3,10.5)
replace row = 7.8 if inrange(ypos,14.7,14.9)
replace row = 9.4 if inrange(ypos,16.4,16.6)
gen se_pd = (hi - lo)/3.92
gen str24 anno = string(b,"%6.3f") + " (" + string(se_pd,"%5.3f") + ")"
replace anno = anno + "***" if !inlist(grp,2,4)
gen xanno = 0.185
twoway ///
    (rcap lo hi row if grp==1, horizontal lcolor("24 72 144") lwidth(medium)) ///
    (scatter row b if grp==1, mcolor("24 72 144") msymbol(O) msize(large)) ///
    (rcap lo hi row if grp==5, horizontal lcolor("108 172 228") lwidth(medium)) ///
    (scatter row b if grp==5, mcolor("108 172 228") msymbol(S) msize(large)) ///
    (rcap lo hi row if grp==3, horizontal lcolor("179 27 27") lwidth(medium)) ///
    (scatter row b if grp==3, mcolor("179 27 27") msymbol(D) msize(large)) ///
    (rcap lo hi row if grp==4, horizontal lcolor("24 72 144") lwidth(medium)) ///
    (scatter row b if grp==4, mcolor(white) mlcolor("24 72 144") msymbol(O) msize(large)) ///
    (scatter row xanno if !inlist(grp,2,4), msymbol(i) mlabel(anno) mlabpos(3) mlabsize(medsmall) mlabcolor(gs4)) ///
    (scatter row xanno if inlist(grp,2,4), msymbol(i) mlabel(anno) mlabpos(3) mlabsize(medsmall) mlabcolor(gs10)) ///
    , xline(0, lcolor(gs8)) ///
    xline(`pool', lcolor("24 72 144") lpattern(dash) lwidth(thin)) ///
    yline(7, lcolor(gs14)) yline(8.6, lcolor(gs14)) ///
    yscale(reverse range(0.5 9.9)) ///
    ylabel(1 "Rush begins 4 PM, +$2.50 (2023-24)" ///
           2 "Rush begins 4 PM, +$1.00 (2021-22)" ///
           3 "Overnight begins 8 PM, +$1.00 (2023-24)" ///
           4 "Rush ends 8 PM, {&minus}$1.50 net (2023-24)" ///
           5 "JFK flat fare, +$5.00 (2023-24)" ///
           6 "JFK flat fare, +$4.50 (2021-22)" ///
           7.8 "2025 CBD toll (spatial)" ///
           9.4 "Weekend placebo" ///
           , angle(0) labsize(medsmall) nogrid noticks) ///
    xscale(range(-0.19 0.34)) ///
    xlabel(-0.15(0.05)0.15, format(%4.2f) labsize(medsmall)) ///
    xtitle("Tip response per statutory surcharge dollar", size(medsmall)) ///
    ytitle("") legend(off) ///
    text(9.85 `pool' "pooled 0.108 (0.001)***", size(small) color("24 72 144") placement(e)) ///
    xsize(7.0) ysize(4.0)
graph export "${PFIG}/fig-coefplot-poster.pdf", as(pdf) replace

* Declutter 4pm: no legend box, direct series labels, tighter window
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_v3.csv", clear varnames(1)
gen date = date(d, "YMD")
keep if inrange(date, mdy(9,1,2021), mdy(9,30,2024))
gen dow = dow(date)
keep if inrange(dow, 1, 5)
gen byte holiday = 0
foreach h in "25nov2021" "24dec2021" "31dec2021" "17jan2022" "21feb2022" ///
    "30may2022" "20jun2022" "4jul2022" "5sep2022" "24nov2022" "26dec2022" ///
    "2jan2023" "16jan2023" "20feb2023" "29may2023" "19jun2023" "4jul2023" ///
    "4sep2023" "23nov2023" "25dec2023" "1jan2024" "15jan2024" "19feb2024" ///
    "27may2024" "19jun2024" "4jul2024" "2sep2024" {
    quietly replace holiday = 1 if date == date("`h'", "DMY")
}
drop if holiday
gen byte regime25 = date >= mdy(12,19,2022)
gen rv = mint - 960
keep if abs(rv) <= 45
collapse (sum) s_tip n_card, by(rv regime25)
gen mtip = s_tip/n_card
twoway (scatter mtip rv if !regime25, mcolor("108 172 228") msize(medsmall)) ///
       (scatter mtip rv if regime25,  mcolor("24 72 144")  msize(medsmall)) ///
       (lfit mtip rv if regime25 & rv<0,  lcolor("24 72 144") lwidth(medthick)) ///
       (lfit mtip rv if regime25 & rv>=0, lcolor("24 72 144") lwidth(medthick)) ///
       (lfit mtip rv if !regime25 & rv<0,  lcolor("108 172 228") lwidth(medthick)) ///
       (lfit mtip rv if !regime25 & rv>=0, lcolor("108 172 228") lwidth(medthick)), ///
    xline(0, lcolor(gs6) lpattern(dash)) ///
    xtitle("Minutes relative to 4:00 PM (weekdays)", size(medsmall)) ///
    ytitle("Mean credit-card tip (USD)", size(medsmall)) ///
    ylabel(, labsize(medsmall)) xlabel(-45(15)45, labsize(medsmall)) ///
    text(4.42 -43 "USD 2.50 regime (2023-24)", size(medsmall) color("24 72 144") placement(e)) ///
    text(3.30 -43 "USD 1.00 regime (2021-22)", size(medsmall) color("108 172 228") placement(e)) ///
    legend(off) xsize(6.4) ysize(4.0)
graph export "${PFIG}/fig-4pm-poster.pdf", as(pdf) replace
di as result "poster-edition variants done"

* Columbia-palette choropleth twin (reuses zonejumps.dta from 13_maps_v2.do)
import delimited "${PROJECT_ROOT}/data/cells/zone_geometry.csv", clear varnames(1)
gen long vid = _n
tempfile G
save `G'
foreach r in 0 1 {
    use "${PROJECT_ROOT}/data/intermediate/zonejumps.dta", clear
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
        if `g' == 0 local c "234 238 243"
        if `g' == 1 local c "185 217 235"
        if `g' == 2 local c "108 172 228"
        if `g' == 3 local c "24 72 144"
        if `g' == 4 local c "201 148 141"
        local cmd `"`cmd' (area lat lon if pu == `z', cmissing(n) nodropbase fcolor("`c'") lcolor(white) lwidth(vvthin))"'
    }
    if `r' == 0 local ti "Placebo split: July 2024"
    if `r' == 1 local ti "Real: January 2025 toll"
    twoway `cmd', aspectratio(1.3) legend(off) ///
        title("`ti'", size(medlarge) color("28 32 36")) ///
        xtitle("") ytitle("") xlabel(none) ylabel(none) ///
        graphregion(color(white)) plotregion(lcolor(none)) ///
        name(pmap`r', replace) nodraw
}
graph combine pmap0 pmap1, cols(2) imargin(1 1 1 1) graphregion(color(white))
graph export "${PFIG}/fig-map-poster.pdf", as(pdf) replace
di as result "poster map done"
