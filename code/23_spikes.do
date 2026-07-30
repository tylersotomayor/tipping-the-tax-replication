version 18.0
* Purpose: the base, drawn rather than argued. Distribution of credit-card
*          tips as a percentage of (A) the all-in pre-tip total -- the base
*          the buttons multiply -- and (B) the metered fare alone, June 2025.
*          Same tips, same axes: knife-edge spikes at exactly 20/25/30 against
*          the all-in total; against the fare the spikes vanish.
* Inputs:  data/cells/spikes.csv (code/py/build_spikes.py)
* Outputs: ${FIGURES}/fig-spikes.pdf

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
di as result "SPIKES: allin 20/25/30 bins = `s20' / `s25' / `s30' pct; fare max bin = `fmax' pct"

set scheme s1mono
twoway (bar share bin if base == "allin", color(navy) barwidth(0.45)), ///
    ylabel(0(10)60, angle(0)) xlabel(5(5)40) ///
    xtitle("") ytitle("Percent of tips") ///
    text(60 20 "`s20'%", size(small) color(navy)) ///
    text(11.5 25 "`s25'%", size(small) color(navy)) ///
    text(6.2 30 "`s30'%", size(small) color(navy)) ///
    title("A. As a percentage of the all-in total (the buttons' base)", ///
        size(medsmall) color(black) position(11)) ///
    name(gA, replace) nodraw
twoway (bar share bin if base == "fare", color(dkorange) barwidth(0.45)), ///
    ylabel(0(10)60, angle(0)) xlabel(5(5)40) ///
    xtitle("Tip as a percentage of the candidate base") ///
    ytitle("Percent of tips") ///
    text(9 32.5 "largest bin: `fmax' percent", size(small) color(dkorange)) ///
    title("B. The same tips as a percentage of the metered fare alone", ///
        size(medsmall) color(black) position(11)) ///
    name(gB, replace) nodraw
graph combine gA gB, col(1) imargin(2 2 1 1) xsize(6.4) ysize(6.0)
graph export "${FIGURES}/fig-spikes.pdf", as(pdf) replace
di as result "wrote fig-spikes.pdf"
