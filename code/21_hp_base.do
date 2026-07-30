version 18.0
* Purpose: 2012-13 vendor tip-base table. Replaces the hand-coded table that
*          previously sat inside sections/appendix_replication.tex (house rule:
*          never hand-edit generated fragments) and corrects its base ladder.
* Inputs:  data/cells/hp_base.csv  (code/py/build_hp_base.py)
* Outputs: ${TABLES}/tab-hp-base.tex, plus the reconciliation scalars in the log

import delimited "${PROJECT_ROOT}/data/cells/hp_base.csv", clear varnames(1)

gen str3 vend = cond(v == 1, "CMT", "VTS")
* Raw trip counts must be summed WITHOUT weights -- -collapse (sum)- with
* aweights rescales the total.
preserve
collapse (sum) ntot = n, by(vend)
tempfile TOT
save `TOT'
restore
collapse (mean) b1 b2 b3 b4 mean_rate gapshare mean_fare ///
         mean_extra mean_taxtoll [aw=n], by(vend)
merge 1:1 vend using `TOT', nogenerate
rename ntot n

tempname fh
file open `fh' using "${TABLES}/tab-hp-base.tex", write replace
foreach vv in "CMT" "VTS" {
    quietly sum n if vend == "`vv'"
    local nn = r(mean)
    foreach k in 1 2 3 4 {
        quietly sum b`k' if vend == "`vv'"
        local x`k' = r(mean)
    }
    local lbl = cond("`vv'"=="CMT", "Vendor 1 (CMT)", "Vendor 2 (VTS)")
    file write `fh' "`lbl' & " %12.0fc (`nn') " & " %5.3f (`x1') " & " ///
        %5.3f (`x2') " & " %5.3f (`x3') " & " %5.3f (`x4') " \\" _n
}
file close `fh'

* ---- reconciliation arithmetic, reported in the log ----
quietly sum mean_rate if vend == "CMT"
local rc = r(mean)
quietly sum mean_rate if vend == "VTS"
local rv = r(mean)
quietly sum gapshare if vend == "CMT"
local gs = r(mean)
quietly sum b4 if vend == "CMT"
local adh = r(mean)
local pred = 0.20*`gs'*`adh'
di as result "HP-BASE: CMT tip/fare = " %6.4f `rc' "  VTS = " %6.4f `rv' ///
    "  observed gap = " %6.4f (`rc'-`rv')
di as result "HP-BASE: E[(tax+tolls)/fare] = " %6.4f `gs' ///
    "  CMT adherence = " %5.3f `adh'
di as result "HP-BASE: predicted gap = " %6.4f `pred' ///
    "  = " %4.0f (100*`pred'/(`rc'-`rv')) " percent of observed"
