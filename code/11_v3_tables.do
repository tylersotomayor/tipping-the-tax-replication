version 18.0
* Purpose: v3 tables (balance, main, robustness) + v3 figure data.
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
gen mean_tip  = s_tip/n_card
gen mean_ext  = s_extra/n_card
gen nonsur    = (s_ptt - s_extra)/n_card
gen mean_fare = s_fare/n_card
gen mean_dist = s_dist/n_card
gen mean_dur  = s_dur/n_card
gen sh_card   = n_card/n_all
gen sh_v2     = n_v2/n_card
drop if missing(mean_tip)
tempfile V3
save `V3'

capture program drop starof
program define starof
    args b se
    local t = abs(`b'/`se')
    global STAR ""
    if `t' > 1.645 global STAR "\sym{*}"
    if `t' > 1.960 global STAR "\sym{**}"
    if `t' > 2.576 global STAR "\sym{***}"
end

*---- balance table ----
tempname fh
file open `fh' using "${TABLES}/tab-balance.tex", write replace
preserve
quietly keep if weekday & !holiday & regime25 & inrange(mint, 900, 1020)
quietly gen rv = mint - 960
quietly gen byte post = rv >= 0
quietly gen rvp = rv*post
foreach y in mean_fare mean_dist mean_dur sh_card sh_v2 {
    if "`y'" == "mean_fare" local lbl "Metered fare (USD)"
    if "`y'" == "mean_dist" local lbl "Trip distance (miles)"
    if "`y'" == "mean_dur"  local lbl "Trip duration (minutes)"
    if "`y'" == "sh_card"   local lbl "Card share of trips"
    if "`y'" == "sh_v2"     local lbl "Vendor 2 share of card trips"
    quietly sum `y' [aw=n_card] if !post
    local m0 = r(mean)
    quietly reg `y' post rv rvp [aw=n_card], cluster(date)
    starof _b[post] _se[post]
    file write `fh' "`lbl' & " %8.3f (`m0') " & " %8.4f (_b[post]) "${STAR} & (" ///
        %6.4f (_se[post]) ") \\" _n
}
restore
file close `fh'

*---- main table: six clocks, RF / ITT / rho_IV ----
capture program drop v3row
program define v3row, rclass
    args c w cond dose
    preserve
    quietly keep if `cond'
    quietly gen rv = mint - `c'
    quietly keep if abs(rv) <= `w'
    quietly gen byte post = rv >= 0
    quietly gen rvp = rv*post
    quietly reg mean_tip post rv rvp nonsur [aw=n_card], cluster(date)
    return scalar rf = _b[post]
    return scalar rfse = _se[post]
    quietly ivregress 2sls mean_tip (mean_ext = post) rv rvp nonsur ///
        [aw=n_card], vce(cluster date)
    return scalar riv = _b[mean_ext]
    return scalar rivse = _se[mean_ext]
    restore
end
file open `fh' using "${TABLES}/tab-main3.tex", write replace
foreach spec in "960 weekday&!holiday&regime25 2.50 Rush_begins_4pm,_wk,_USD_2.50" ///
                "960 weekday&!holiday&regime1 1.00 Rush_begins_4pm,_wk,_USD_1.00" ///
                "1200 !weekday&regime25 1.00 Overnight_begins_8pm,_wke,_USD_1.00" ///
                "1200 !weekday&regime1 0.50 Overnight_begins_8pm,_wke,_USD_0.50" ///
                "1200 weekday&!holiday&regime25 -1.50 Rush_ends_8pm,_wk,_net_minus_USD_1.50" ///
                "1200 weekday&!holiday&regime1 -0.50 Rush_ends_8pm,_wk,_net_minus_USD_0.50" {
    local c  : word 1 of `spec'
    local cd : word 2 of `spec'
    local dz : word 3 of `spec'
    local nm : word 4 of `spec'
    v3row `c' 60 "`cd'" `dz'
    local rf = r(rf)
    local rfse = r(rfse)
    local riv = r(riv)
    local rivse = r(rivse)
    local itt = `rf'/`dz'
    local ittse = `rfse'/abs(`dz')
    starof `rf' `rfse'
    local lbl = subinstr("`nm'", "_", " ", .)
    file write `fh' "`lbl' & " %6.3f (`rf') "${STAR} & (" %5.3f (`rfse') ") & " ///
        %6.3f (`itt') " & " %6.3f (`riv') " & (" %5.3f (`rivse') ") \\" _n
}
* weekend 4pm placebos as final rows
foreach spec in "regime25 4pm,_weekend_placebo,_USD_2.50_era" "regime1 4pm,_weekend_placebo,_USD_1.00_era" {
    local cd : word 1 of `spec'
    local nm : word 2 of `spec'
    v3row 960 60 "!weekday & `cd'" 1
    local rf = r(rf)
    local rfse = r(rfse)
    starof `rf' `rfse'
    local lbl = subinstr("`nm'", "_", " ", .)
    file write `fh' "`lbl' & " %6.3f (`rf') "${STAR} & (" %5.3f (`rfse') ") & --- & --- & \\" _n
}
file close `fh'

*---- robustness: bandwidth + donut on v3 ----
capture program drop v3don
program define v3don, rclass
    args c w cond donut
    preserve
    quietly keep if `cond'
    quietly gen rv = mint - `c'
    quietly keep if abs(rv) <= `w'
    if `donut' > 0 quietly drop if abs(rv) < `donut'
    quietly gen byte post = rv >= 0
    quietly gen rvp = rv*post
    quietly ivregress 2sls mean_tip (mean_ext = post) rv rvp nonsur ///
        [aw=n_card], vce(cluster date)
    return scalar riv = _b[mean_ext]
    return scalar rivse = _se[mean_ext]
    restore
end
file open `fh' using "${TABLES}/tab-bw3.tex", write replace
foreach b in 30 45 60 90 {
    v3don 960 `b' "weekday & !holiday & regime25" 0
    starof r(riv) r(rivse)
    file write `fh' "Bandwidth \$\pm\$`b' min & " %6.3f (r(riv)) "${STAR} & (" ///
        %5.3f (r(rivse)) ") \\" _n
}
file write `fh' "\addlinespace" _n
foreach dnt in 3 5 10 {
    v3don 960 60 "weekday & !holiday & regime25" `dnt'
    starof r(riv) r(rivse)
    file write `fh' "Donut \$\pm\$`dnt' min & " %6.3f (r(riv)) "${STAR} & (" ///
        %5.3f (r(rivse)) ") \\" _n
}
file close `fh'

*---- v3 figure data ----
use `V3', clear
preserve
keep if weekday & !holiday & inrange(mint, 900, 1020)
collapse (mean) mean_tip [aw=n_card], by(mint regime25)
save "${DATA_INT}/fig4pm.dta", replace
restore
preserve
keep if inrange(mint, 900, 1020) & regime25
collapse (mean) mean_tip [aw=n_card], by(mint weekday)
save "${DATA_INT}/fig4pm_wewd.dta", replace
restore
preserve
keep if weekday & !holiday & inrange(mint, 900, 1020)
gen mean_extra_card = mean_ext
collapse (mean) mean_extra [aw=n_card], by(mint regime25)
rename mean_extra mean_extra_card2
save "${DATA_INT}/figfs.dta", replace
restore
