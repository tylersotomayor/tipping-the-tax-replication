version 18.0
* Purpose: the base-rule menu -- what each component of the fare stack feeds
*          into tips, and what each possible base rule would return to riders.
*          Card-trip component totals for the 2025 fee environment (2025H1,
*          annualized x2), all rate codes pooled; induced tips at the two
*          scalings the paper reports (ITT per statutory dollar 0.108 and
*          rho^IV per recorded dollar 0.150 -- collections are recorded
*          dollars, so 0.150 is the aggregation rate and 0.108 conservative).
* Inputs:  data/cells/component_totals.csv (code/py/build_components.py)
* Outputs: ${TABLES}/tab-menu.tex

import delimited "${PROJECT_ROOT}/data/cells/component_totals.csv", clear varnames(1)
keep if substr(ym,1,4) == "2025"
collapse (sum) s_extra s_mta s_imp s_cs s_cbd s_air s_tolls n_card
foreach v of varlist s_* n_card {
    quietly replace `v' = 2*`v'      // 2025H1 -> annualized
}

local rlo = 0.108
local rhi = 0.150

tempname fh
file open `fh' using "${TABLES}/tab-menu.tex", write replace
file write `fh' "\emph{Components the driver keeps} & & & \\" _n
local b = s_extra[1]/1e6
file write `fh' "\quad Rush-hour and overnight surcharges & " %8.1fc (`b') ///
    " & " %6.1fc (`rlo'*`b') " & " %6.1fc (`rhi'*`b') " \\" _n
file write `fh' "\addlinespace" _n
file write `fh' "\emph{Components collected and remitted} & & & \\" _n
foreach spec in `""s_mta" "MTA State Surcharge (USD 0.50)""' ///
                `""s_imp" "Improvement surcharge (USD 1.00)""' ///
                `""s_cs"  "NYS congestion surcharge (USD 2.50)""' ///
                `""s_cbd" "MTA CBD toll (USD 0.75)""' ///
                `""s_air" "Airport access fee""' {
    tokenize `"`spec'"'
    local b = `1'[1]/1e6
    file write `fh' "\quad `2' & " %8.1fc (`b') " & " %6.1fc (`rlo'*`b') ///
        " & " %6.1fc (`rhi'*`b') " \\" _n
}
local b = s_tolls[1]/1e6
file write `fh' "\quad Bridge and tunnel tolls (third party) & " %8.1fc (`b') ///
    " & " %6.1fc (`rlo'*`b') " & " %6.1fc (`rhi'*`b') " \\" _n
file write `fh' "\addlinespace" _n
* totals: remitted-to-government, and all non-fare components
local gov = (s_mta[1]+s_imp[1]+s_cs[1]+s_cbd[1]+s_air[1])/1e6
local all = `gov' + (s_extra[1]+s_tolls[1])/1e6
file write `fh' "\emph{Base rules (tips returned to riders)} & & & \\" _n
file write `fh' "\quad Exclude the CBD toll only & " %8.1fc (s_cbd[1]/1e6) ///
    " & " %6.1fc (`rlo'*s_cbd[1]/1e6) " & " %6.1fc (`rhi'*s_cbd[1]/1e6) " \\" _n
file write `fh' "\quad Exclude all government fees & " %8.1fc (`gov') ///
    " & " %6.1fc (`rlo'*`gov') " & " %6.1fc (`rhi'*`gov') " \\" _n
file write `fh' "\quad Fare-only base (exclude everything) & " %8.1fc (`all') ///
    " & " %6.1fc (`rlo'*`all') " & " %6.1fc (`rhi'*`all') " \\" _n
file close `fh'

di as result "MENU annual card-trip base dollars (2025 env, USD m): " ///
    "extra=" %5.1f (s_extra[1]/1e6) " mta=" %5.1f (s_mta[1]/1e6) ///
    " imp=" %5.1f (s_imp[1]/1e6) " cs=" %5.1f (s_cs[1]/1e6) ///
    " cbd=" %5.1f (s_cbd[1]/1e6) " air=" %5.1f (s_air[1]/1e6) ///
    " tolls=" %5.1f (s_tolls[1]/1e6)
di as result "MENU gov-remitted total=" %6.1f `gov' ///
    "  all non-fare=" %6.1f `all' ///
    "  tips at [0.108,0.150]: gov [" %5.1f (`rlo'*`gov') ", " ///
    %5.1f (`rhi'*`gov') "]  all [" %5.1f (`rlo'*`all') ", " %5.1f (`rhi'*`all') "]"
