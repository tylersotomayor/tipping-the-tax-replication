version 18.0
* Purpose: Amendment 2, item 4 -- the composition of the TLC `extra` field on
*          each side of every clock cutoff. This is the diagnostic that shows
*          the measured "first stage" is not a clean statutory dose, and it is
*          why the paper reports an ITT per statutory dollar alongside rho^IV.
* Inputs:  data/cells/cells_minute_v3.csv, data/cells/cells_minute_6am.csv
* Outputs: ${TABLES}/tab-composition.tex

import delimited "${PROJECT_ROOT}/data/cells/cells_minute_v3.csv", clear varnames(1)
tempfile CLOCKS
save `CLOCKS'
import delimited "${PROJECT_ROOT}/data/cells/cells_minute_6am.csv", clear varnames(1)
append using `CLOCKS'

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
keep if date >= mdy(12,19,2022)          // $2.50 regime only
gen sh_ex0   = n_ex0/n_card
gen sh_ex100 = n_ex100/n_card
gen sh_ex250 = n_ex250/n_card
gen sh_oth   = 1 - sh_ex0 - sh_ex100 - sh_ex250
gen mean_ext = s_extra/n_card
drop if missing(mean_ext)

tempname fh
file open `fh' using "${TABLES}/tab-composition.tex", write replace

foreach spec in "960 4:00pm" "1200 8:00pm" "360 6:00am" {
    tokenize "`spec'"
    local c "`1'"
    local lab "`2'"
    forvalues p = 0/1 {
        preserve
        quietly keep if weekday & !holiday & abs(mint - `c') <= 60
        quietly gen byte post = (mint - `c') >= 0
        quietly keep if post == `p'
        local side = cond(`p'==0, "before", "after")
        quietly sum sh_ex0 [aw=n_card]
        local a = r(mean)
        quietly sum sh_ex100 [aw=n_card]
        local b = r(mean)
        quietly sum sh_ex250 [aw=n_card]
        local cc = r(mean)
        quietly sum sh_oth [aw=n_card]
        local dd = r(mean)
        quietly sum mean_ext [aw=n_card]
        local mm = r(mean)
        file write `fh' "`lab', `side' & " %5.3f (`a') " & " %5.3f (`b') ///
            " & " %5.3f (`cc') " & " %5.3f (`dd') " & " %5.2f (`mm') " \\" _n
        restore
    }
    if "`c'" != "360" file write `fh' "\addlinespace" _n
}
file close `fh'
di as result "wrote tab-composition.tex"
