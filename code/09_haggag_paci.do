version 18.0
* Purpose: D6 scoped replication of Haggag & Paci (2014). Two payment vendors
*          displayed different default tip menus; the menus appear as spikes in
*          the tip-rate distribution, and mean tip rates differ accordingly.
* Inputs:  data/cells/hp_ratio.csv, data/cells/hp_means.csv
* Outputs: ${FIGURES}/fig-hp.pdf, ${TABLES}/tab-hp.tex

*----------------------------------------------------------------------
* 1. Recover each vendor's default menu from the tip-rate distribution
*----------------------------------------------------------------------
import delimited "${PROJECT_ROOT}/data/cells/hp_ratio.csv", clear varnames(1)
collapse (sum) n, by(v band rate_bin)
bysort v band: egen tot = total(n)
gen share = n/tot
di as result "=== D6: modal tip rates (high-fare band, fare >= \$15) ==="
foreach vv in 1 2 {
    preserve
    keep if v == `vv' & band == "hi"
    gsort -share
    di as result "   Vendor `vv' top spikes:"
    forvalues i = 1/4 {
        di as result "      " %5.1f rate_bin[`i'] "% of fare, share " %5.3f share[`i']
    }
    restore
}
save "${DATA_INT}/hp_ratio.dta", replace

*----------------------------------------------------------------------
* 2. Vendor difference in mean tip rate, conditional on fare
*----------------------------------------------------------------------
import delimited "${PROJECT_ROOT}/data/cells/hp_means.csv", clear varnames(1)
gen byte vts = v == 2
egen fb = group(fbin)
egen ymf = group(ym fbin)
di as result "=== D6: vendor gap in mean tip rate, conditional on fare bin ==="
reghdfe mean_rate vts [aw=n], absorb(ymf) vce(cluster fb)
scalar gap = _b[vts]
scalar gapse = _se[vts]
di as result "   VTS minus CMT mean tip rate: " %7.4f gap " (" %6.4f gapse ")"
di as result "   i.e. " %5.2f 100*gap " percentage points of fare"
quietly sum mean_rate [aw=n] if !vts
di as result "   CMT mean tip rate: " %6.4f r(mean)
quietly sum mean_rate [aw=n] if vts
di as result "   VTS mean tip rate: " %6.4f r(mean)
* zero-tip share
reghdfe zero_sh vts [aw=n], absorb(ymf) vce(cluster fb)
di as result "   VTS minus CMT zero-tip share: " %7.4f _b[vts] " (" %6.4f _se[vts] ")"

tempname fh
file open `fh' using "${TABLES}/tab-hp.tex", write replace
local t = abs(gap/gapse)
local s ""
if `t' > 1.645 local s "\sym{*}"
if `t' > 1.960 local s "\sym{**}"
if `t' > 2.576 local s "\sym{***}"
quietly sum mean_rate [aw=n] if !vts
file write `fh' "CMT mean tip rate & " %6.4f (r(mean)) " \\" _n
quietly sum mean_rate [aw=n] if vts
file write `fh' "VTS mean tip rate & " %6.4f (r(mean)) " \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "Difference (VTS $-$ CMT) & " %6.4f (gap) "`s' \\" _n
file write `fh' " & (" %6.4f (gapse) ") \\" _n
file close `fh'
