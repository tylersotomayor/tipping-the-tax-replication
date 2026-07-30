version 18.0
* Counterfactual and welfare-accounting table from committed cells.
* Rows are exact sums; rho values from headline estimates (documented).

import delimited "${PROJECT_ROOT}/data/cells/cells_zone_v2.csv", clear varnames(1)
gen y = real(substr(ym,1,4))
gen mo = real(substr(ym,6,2))
gen t = ym(y,mo)
* --- 2025 toll: eligible activity, 2025H1 annualized ---
preserve
import delimited "${PROJECT_ROOT}/data/cells/cbd_zones.csv", clear varnames(1)
gen byte puin = 1
tempfile Z
save `Z'
restore
merge m:1 pu using `Z', keep(1 3) nogen
replace puin = 0 if missing(puin)
gen byte elig = puin | doin
preserve
keep if elig & inrange(t, ym(2025,1), ym(2025,6))
collapse (sum) n_all n_card s_cbd
scalar fee25 = 2*s_cbd[1]
scalar q25all = 2*n_all[1]
scalar q25card = 2*n_card[1]
restore
* --- 2019 surcharge on card trips, calendar 2019 ---
preserve
keep if inrange(t, ym(2019,1), ym(2019,12))
collapse (sum) s_cs
scalar fee19 = s_cs[1]
restore

scalar rho25 = 0.133          // OD-eligibility DiD (SE 0.009)
scalar rho15 = 0.150          // clock headline (SE 0.002)
scalar tip25 = rho25*fee25
scalar tip19 = rho15*fee19
scalar tip25c = rho25*fee25*(2.50/0.75)   // counterfactual $2.50 toll
* DWL upper bound: 0.5 * fee * dQ, dQ at demand CI lower edge (2.9%)
scalar dwl = 0.5*0.75*0.029*q25all
* timing bound at 4pm: 1.3% of the 10-minute post mass reallocated x $2.50
* (share terms from the density test; expressed per year on rush weekday trips)

tempname fh
file open `fh' using "${TABLES}/tab-welfare.tex", write replace
file write `fh' "\emph{Annual transfers (measured)} & \\" _n
file write `fh' "\quad Riders $\rightarrow$ MTA, 2025 toll on card trips & " %12.1fc (fee25/1e6) " \\" _n
file write `fh' "\quad Riders $\rightarrow$ drivers via tips, 2025 toll ($\rho=0.133$) & " %12.1fc (tip25/1e6) " \\" _n
file write `fh' "\quad Riders $\rightarrow$ drivers via tips, 2019 surcharge ($\rho=0.150$) & " %12.1fc (tip19/1e6) " \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "\emph{Counterfactuals} & \\" _n
file write `fh' "\quad Fare-only tip base (both fees): induced tips & 0.0 \\" _n
file write `fh' "\quad Toll at USD 2.50 instead of USD 0.75: induced tips & " %12.1fc (tip25c/1e6) " \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "\emph{Scale gauges (not welfare bounds)} & \\" _n
file write `fh' "\quad Harberger triangle at demand-CI edge ($-2.9\%$; point est.\ $\approx 0$) & $\le$ " %5.2f (dwl/1e6) " \\" _n
file write `fh' "\quad Retiming, cash-switching, zero-tip margins & $\approx$ 0 \\" _n
file close `fh'
di as result "fee25=" fee25 " tip25=" tip25 " fee19=" fee19 " tip19=" tip19 ///
    " tip25c=" tip25c " dwl=" dwl " q25all=" q25all
