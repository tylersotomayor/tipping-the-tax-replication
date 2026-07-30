version 18.0
* Purpose: headline figures.
* Fig 1: minute means around 4pm, by regime (dose visible)
use "${DATA_INT}/fig4pm.dta", clear
gen rv = mint - 960
twoway (scatter mean_tip rv if regime25==0, mcolor(navy) msymbol(O) msize(small)) ///
    (scatter mean_tip rv if regime25==1, mcolor(dkorange) msymbol(T) msize(small)), ///
    xline(0, lcolor(gs6) lpattern(dash)) ///
    xtitle("Minutes relative to 4:00pm (weekdays)") ///
    ytitle("Mean credit-card tip (USD)") ///
    legend(order(1 "$1.00 surcharge (2021{&minus}22)" 2 "$2.50 surcharge (2023{&minus}24)") ///
        pos(5) ring(0) cols(1) size(small))
graph export "${FIGURES}/fig-4pm.pdf", as(pdf) replace

* Fig 2: weekday vs weekend at 4pm, $2.50 regime (the netting)
use "${DATA_INT}/fig4pm_wewd.dta", clear
gen rv = mint - 960
twoway (scatter mean_tip rv if weekday==1, mcolor(navy) msymbol(O) msize(small)) ///
    (scatter mean_tip rv if weekday==0, mcolor(teal) msymbol(S) msize(small)), ///
    xline(0, lcolor(gs6) lpattern(dash)) ///
    xtitle("Minutes relative to 4:00pm ($2.50 surcharge regime)") ///
    ytitle("Mean credit-card tip (USD)") ///
    legend(order(1 "Weekdays (surcharge applies)" 2 "Weekends (no surcharge)") ///
        pos(5) ring(0) cols(1) size(small))
graph export "${FIGURES}/fig-wewd.pdf", as(pdf) replace

* Fig 3: first stage (the surcharge step itself)
use "${DATA_INT}/fig4pm.dta", clear
gen rv = mint - 960
twoway (scatter mean_extra rv if regime25==0, mcolor(navy) msymbol(O) msize(small)) ///
    (scatter mean_extra rv if regime25==1, mcolor(dkorange) msymbol(T) msize(small)), ///
    xline(0, lcolor(gs6) lpattern(dash)) ///
    xtitle("Minutes relative to 4:00pm (weekdays)") ///
    ytitle("Mean metered surcharge (USD)") ///
    legend(order(1 "$1.00 regime" 2 "$2.50 regime") pos(11) ring(0) cols(1) size(small))
graph export "${FIGURES}/fig-firststage.pdf", as(pdf) replace

* Fig 4: 2025 CBD toll event study
capture confirm file "${DATA_INT}/es_fee25.dta"
if !_rc {
    use "${DATA_INT}/es_fee25.dta", clear
    drop if missing(b)
    gen lo = b - 1.96*se
    gen hi = b + 1.96*se
    twoway (rcap lo hi e, lcolor(navy)) (scatter b e, mcolor(navy) msymbol(O)), ///
        yline(0, lcolor(gs8) lpattern(dash)) xline(-0.5, lcolor(maroon)) ///
        xlabel(-12(3)5) ///
        xtitle("Months relative to January 2025 CBD toll") ///
        ytitle("Tip difference, CBD vs non-CBD zones (USD)") ///
        legend(off)
    graph export "${FIGURES}/fig-es-fee25.pdf", as(pdf) replace
}

* Fig 5: Haggag-Paci replication - vendor default menus as tip-rate spikes
capture confirm file "${DATA_INT}/hp_ratio.dta"
if !_rc {
    use "${DATA_INT}/hp_ratio.dta", clear
    keep if band == "hi" & inrange(rate_bin, 5, 40)
    twoway (line share rate_bin if v == 1, lcolor(navy) lwidth(medthick)) ///
        (line share rate_bin if v == 2, lcolor(dkorange) lwidth(medthick)), ///
        xlabel(5(5)40) ///
        xtitle("Tip as percent of metered fare") ///
        ytitle("Share of credit-card tips") ///
        legend(order(1 "Vendor 1 (CMT)" 2 "Vendor 2 (VTS)") pos(1) ring(0) cols(1) size(small)) ///
        note("Spikes mark each vendor's on-screen default buttons, 2012{&minus}2013.", size(vsmall))
    graph export "${FIGURES}/fig-hp.pdf", as(pdf) replace
}
