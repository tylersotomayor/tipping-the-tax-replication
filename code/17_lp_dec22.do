version 18.0
clear all
set more off
set scheme s1mono
global PROJECT_ROOT "`c(pwd)'"
global FIGURES "${PROJECT_ROOT}/output/figures"
* LP-style adaptation path: weekly horizon effects of the Dec-19-2022
* surcharge repricing on the rush-window tip rate, netted against the
* surcharge-free pre-rush window (diff-in-disc at each horizon h).
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_v3.csv", clear varnames(1)
gen date = date(d, "YMD")
keep if inrange(date, mdy(6,20,2022), mdy(6,19,2023))
gen dow = dow(date)
keep if inrange(dow,1,5)
gen byte rush = inrange(mint, 960, 1050)
keep if rush | inrange(mint, 870, 955)
collapse (sum) s_tip s_ptt n_card, by(date rush)
gen rate = s_tip/s_ptt
reshape wide rate s_tip s_ptt n_card, i(date) j(rush)
gen drate = rate1 - rate0
gen wk = floor((date - mdy(12,19,2022))/7)
* LP: for each horizon h (weeks 0..25), effect vs pre mean (wk in -26..-1)
quietly sum drate if inrange(wk,-26,-1) [aw=n_card1]
scalar pre    = r(mean)
scalar pre_sd = r(sd)
scalar pre_n  = r(N)
tempname L
matrix `L' = J(26,3,.)
forvalues h = 0/25 {
    * Capture BOTH moments from the same summarize before any other r-class
    * command runs -- -count- clears r(sd) and overwrites r(N).
    quietly sum drate if wk == `h' [aw=n_card1]
    local mh  = r(mean)
    local sdh = r(sd)
    local nh  = r(N)
    matrix `L'[`h'+1,1] = `h'
    matrix `L'[`h'+1,2] = `mh' - pre
    * SE of the contrast: horizon-h daily variation PLUS the sampling error in
    * the shared pre-period mean the contrast is measured against.
    matrix `L'[`h'+1,3] = sqrt(`sdh'^2/`nh' + pre_sd^2/pre_n)
}
clear
svmat double `L', names(col)
rename (c1 c2 c3) (h b se)
gen lo = b - 1.96*se
gen hi = b + 1.96*se
* mechanical full-pass-through benchmark: rate unchanged => 0
* full-attention benchmark: rate falls to keep tip dollars fixed
twoway (rarea lo hi h, color(navy%20) lwidth(none)) (line b h, lcolor(navy) lwidth(medthick)), ///
    yscale(range(-0.0125 0.0015)) ylabel(-0.012(0.003)0) ///
    yline(0, lcolor(gs6)) yline(-0.011, lcolor(maroon) lpattern(dash)) ///
    xtitle("Weeks since the December 19, 2022 surcharge increase") ///
    ytitle("Tip-rate response (rush {&minus} pre-rush, vs pre-period)") ///
    text(-0.0102 13 "full attention: riders keep tip dollars fixed ({&minus}1.1pp)", size(vsmall) color(maroon)) ///
    text(0.0009 13 "full pass-through: tip rate unchanged (0)", size(vsmall) color(gs6)) ///
    legend(off)
graph export "${FIGURES}/fig-lp-dec22.pdf", as(pdf) replace
quietly sum b if inrange(h,0,3)
di as result "LP mean h0-3: " %7.4f r(mean)
quietly sum b if inrange(h,22,25)
di as result "LP mean h22-25: " %7.4f r(mean)
