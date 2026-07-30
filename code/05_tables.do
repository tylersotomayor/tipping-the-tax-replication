version 18.0
* Purpose: all estimation-table fragments, with significance stars.
* Inputs:  ${DATA_CLEAN}/minute_panel.dta, cells
* Outputs: ${TABLES}/tab-*.tex

* star string from a t-ratio, computed inline (no r() clobbering)
capture program drop starof
program define starof
    args b se
    local t = abs(`b'/`se')
    global STAR ""
    if `t' > 1.645 global STAR "\sym{*}"
    if `t' > 1.960 global STAR "\sym{**}"
    if `t' > 2.576 global STAR "\sym{***}"
end

*----------------------------------------------------------------------
* Table 1: descriptive statistics
*----------------------------------------------------------------------
use "${DATA_CLEAN}/minute_panel.dta", clear
tempname fh
file open `fh' using "${TABLES}/tab-descriptive.tex", write replace
foreach grp in "regime1 Lower-dose regime (Sep 2021--Dec 2022)" ///
               "regime25 Higher-dose regime (Dec 2022--Sep 2024)" {
    local v : word 1 of `grp'
    local lbl = subinstr("`grp'", "`v' ", "", 1)
    quietly {
        count if `v'
        local ncell = string(r(N), "%12.0fc")
        sum n_all if `v'
        local ntrip = string(r(sum)/1e6, "%6.1f")
        sum n_card if `v'
        local ncard = string(r(sum)/1e6, "%6.1f")
        local cardsh = string(100*r(sum), "%12.0f")
        sum mean_tip if `v' [aw=n_card]
        local mtip = string(r(mean), "%5.2f")
        local sdtip = string(r(sd), "%5.2f")
        sum mean_ptt_card if `v' [aw=n_card]
        local mbase = string(r(mean), "%6.2f")
        sum sh_exact if `v' [aw=n_card]
        local mex = string(100*r(mean), "%5.1f")
        sum sh_zero if `v' [aw=n_card]
        local mz = string(100*r(mean), "%5.1f")
        sum sh_card if `v' [aw=n_all]
        local mc = string(100*r(mean), "%5.1f")
        sum mean_extra if `v' [aw=n_all]
        local mex2 = string(r(mean), "%5.2f")
    }
    file write `fh' "\emph{`lbl'} & \\" _n
    file write `fh' "\quad Date-by-minute cells & `ncell' \\" _n
    file write `fh' "\quad Trips (millions) & `ntrip' \\" _n
    file write `fh' "\quad Card trips (millions) & `ncard' \\" _n
    file write `fh' "\quad Card share of trips (\%) & `mc' \\" _n
    file write `fh' "\quad Mean credit-card tip (USD) & `mtip' \\" _n
    file write `fh' "\quad Mean pre-tip total (USD) & `mbase' \\" _n
    file write `fh' "\quad Mean metered surcharge (USD) & `mex2' \\" _n
    file write `fh' "\quad Tips exactly at a default button (\%) & `mex' \\" _n
    file write `fh' "\quad Zero tips (\%) & `mz' \\" _n
    file write `fh' "\addlinespace" _n
}
file close `fh'

*----------------------------------------------------------------------
* Table 2: headline pass-through, corrected specification
*----------------------------------------------------------------------
capture program drop rdc
program define rdc, rclass
    * cutoff window cond control(0/1)
    args c w cond ctrl
    preserve
    quietly keep if `cond'
    quietly gen rv = mint - `c'
    quietly keep if abs(rv) <= `w'
    quietly gen byte post = rv >= 0
    quietly gen rvp = rv*post
    quietly gen nonsur = mean_ptt_card - mean_extra
    if `ctrl' == 1 {
        quietly reg mean_tip post rv rvp nonsur [aw=n_card], cluster(date)
    }
    else {
        quietly reg mean_tip post rv rvp [aw=n_card], cluster(date)
    }
    return scalar rf = _b[post]
    return scalar se = _se[post]
    if `ctrl' == 1 {
        quietly reg mean_extra post rv rvp nonsur [aw=n_all], cluster(date)
    }
    else {
        quietly reg mean_extra post rv rvp [aw=n_all], cluster(date)
    }
    return scalar fs = _b[post]
    return scalar fsse = _se[post]
    return scalar n = e(N)
    restore
end

file open `fh' using "${TABLES}/tab-main.tex", write replace
foreach r in 1 25 {
    if `r' == 1  local rc "regime1"
    if `r' == 1  local dose "Lower dose (1.00)"
    if `r' == 25 local rc "regime25"
    if `r' == 25 local dose "Higher dose (2.50)"
    * (1) uncontrolled weekday
    rdc 960 60 "weekday & !holiday & `rc'" 0
    local u_rf = r(rf)
    local u_se = r(se)
    local u_fs = r(fs)
    starof `u_rf' `u_se'
    local u_s "${STAR}"
    * (2) weekend
    rdc 960 60 "!weekday & `rc'" 0
    local w_rf = r(rf)
    local w_se = r(se)
    starof `w_rf' `w_se'
    local w_s "${STAR}"
    * (3) corrected weekday
    rdc 960 60 "weekday & !holiday & `rc'" 1
    local c_rf = r(rf)
    local c_se = r(se)
    local c_fs = r(fs)
    local c_n = r(n)
    starof `c_rf' `c_se'
    local c_s "${STAR}"
    * (4) corrected weekend placebo
    rdc 960 60 "!weekday & `rc'" 1
    local cw_rf = r(rf)
    local cw_se = r(se)
    starof `cw_rf' `cw_se'
    local cw_s "${STAR}"
    local rho = `c_rf'/`c_fs'
    local rhose = `c_se'/`c_fs'
    file write `fh' "`dose' & " %5.3f (`u_rf') "`u_s' & " %5.3f (`w_rf') "`w_s' & " ///
        %5.3f (`c_rf') "`c_s' & " %5.3f (`cw_rf') "`cw_s' & " %5.3f (`rho') " \\" _n
    file write `fh' " & (" %5.3f (`u_se') ") & (" %5.3f (`w_se') ") & (" ///
        %5.3f (`c_se') ") & (" %5.3f (`cw_se') ") & (" %5.3f (`rhose') ") \\" _n
    if `r' == 1 file write `fh' "\addlinespace" _n
}
file close `fh'

*----------------------------------------------------------------------
* Table 3: asymmetry (corrected spec)
*----------------------------------------------------------------------
file open `fh' using "${TABLES}/tab-asym.tex", write replace
foreach spec in "960 weekday&!holiday&regime1 Rush_begins_4pm_(1.00) Up" ///
                "960 weekday&!holiday&regime25 Rush_begins_4pm_(2.50) Up" ///
                "1200 !weekday&regime1 Overnight_begins_8pm_(0.50) Up" ///
                "1200 !weekday&regime25 Overnight_begins_8pm_(1.00) Up" ///
                "1200 weekday&!holiday&regime1 Rush_ends_8pm_(net_1.50_less) Down" ///
                "1200 weekday&!holiday&regime25 Rush_ends_8pm_(net_1.50_less) Down" {
    local c  : word 1 of `spec'
    local cd : word 2 of `spec'
    local nm : word 3 of `spec'
    local dir : word 4 of `spec'
    rdc `c' 60 "`cd'" 1
    local afs = r(fs)
    local arf = r(rf)
    local ase = r(se)
    local rho = `arf'/`afs'
    starof `arf' `ase'
    local s "${STAR}"
    local lbl = subinstr("`nm'", "_", " ", .)
    file write `fh' "`lbl' & `dir' & " %6.3f (`afs') " & " %6.3f (`arf') "`s' & (" ///
        %5.3f (`ase') ") & " %5.3f (`rho') " \\" _n
}
file close `fh'

*----------------------------------------------------------------------
* Table 4: robustness (donut, bandwidth) - corrected spec
*----------------------------------------------------------------------
capture program drop rddon
program define rddon, rclass
    args c w cond donut
    preserve
    quietly keep if `cond'
    quietly gen rv = mint - `c'
    quietly keep if abs(rv) <= `w'
    if `donut' > 0 quietly drop if abs(rv) < `donut'
    quietly gen byte post = rv >= 0
    quietly gen rvp = rv*post
    quietly gen nonsur = mean_ptt_card - mean_extra
    quietly reg mean_tip post rv rvp nonsur [aw=n_card], cluster(date)
    return scalar rf = _b[post]
    return scalar se = _se[post]
    quietly reg mean_extra post rv rvp nonsur [aw=n_all], cluster(date)
    return scalar fs = _b[post]
    restore
end
file open `fh' using "${TABLES}/tab-robust2.tex", write replace
foreach b in 30 45 60 90 {
    rddon 960 `b' "weekday & !holiday & regime25" 0
    local afs = r(fs)
    local arf = r(rf)
    local ase = r(se)
    starof `arf' `ase'
    file write `fh' "Bandwidth \$\pm\$`b' min & " %6.3f (`afs') " & " %6.3f (`arf') ///
        "${STAR} & (" %5.3f (`ase') ") & " %5.3f (`arf'/`afs') " \\" _n
}
file write `fh' "\addlinespace" _n
foreach d in 3 5 10 {
    rddon 960 60 "weekday & !holiday & regime25" `d'
    local afs = r(fs)
    local arf = r(rf)
    local ase = r(se)
    starof `arf' `ase'
    file write `fh' "Donut \$\pm\$`d' min & " %6.3f (`afs') " & " %6.3f (`arf') ///
        "${STAR} & (" %5.3f (`ase') ") & " %5.3f (`arf'/`afs') " \\" _n
}
file close `fh'

*----------------------------------------------------------------------
* Table 5: vendor base validation
*----------------------------------------------------------------------
preserve
import delimited "${PROJECT_ROOT}/data/cells/cells_vendor.csv", clear varnames(1)
keep if inlist(ym, "2024-07", "2025-06")
sort ym vid
file open `fh' using "${TABLES}/tab-vendor.tex", write replace
local prev ""
forvalues i = 1/`=_N' {
    local y = ym[`i']
    local v = vid[`i']
    if "`y'" != "`prev'" & "`prev'" != "" file write `fh' "\addlinespace" _n
    file write `fh' "Vendor `v', `y' & " %8.0fc (n_cardtip[`i']) " & " ///
        %5.3f (m_allin[`i']) " & " %5.3f (m_nocbd[`i']) " & " %5.3f (m_fare[`i']) " \\" _n
    local prev "`y'"
}
file close `fh'
restore
