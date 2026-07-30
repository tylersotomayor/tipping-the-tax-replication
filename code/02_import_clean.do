version 18.0
* Purpose: import committed minute cells; construct design variables.
* Inputs:  data/cells/cells_minute.csv   Outputs: ${DATA_CLEAN}/minute_panel.dta
import delimited "${PROJECT_ROOT}/data/cells/cells_minute.csv", clear varnames(1)
gen date = date(d, "YMD")
format date %td
* keep true sample dates only (files contain stray misdated rows)
keep if inrange(date, mdy(10,1,2021), mdy(6,30,2026))
gen dow = dow(date)
gen byte weekday = inrange(dow, 1, 5)
* federal + NYC holidays (surcharge-exempt): drop from both groups
gen byte holiday = inlist(mdy(month(date), day(date), year(date)), ///
    mdy(11,25,2021), mdy(12,24,2021), mdy(12,31,2021), mdy(1,17,2022), ///
    mdy(2,21,2022), mdy(5,30,2022), mdy(6,20,2022), mdy(7,4,2022), ///
    mdy(9,5,2022), mdy(11,24,2022), mdy(12,26,2022))
replace holiday = 1 if inlist(mdy(month(date), day(date), year(date)), ///
    mdy(1,2,2023), mdy(1,16,2023), mdy(2,20,2023), mdy(5,29,2023), ///
    mdy(6,19,2023), mdy(7,4,2023), mdy(9,4,2023), mdy(11,23,2023), ///
    mdy(12,25,2023), mdy(1,1,2024), mdy(1,15,2024), mdy(2,19,2024))
gen byte regime1 = date <  mdy(12,19,2022)   // $1.00 rush surcharge
gen byte regime25 = date >= mdy(12,19,2022)  // $2.50 from 2022-12-19
gen mean_tip = sum_tip_card/n_card
gen sh_exact = n_exact/n_card
gen sh_zero  = n_zero/n_card
gen sh_card  = n_card/n_all
save "${DATA_CLEAN}/minute_panel.dta", replace
count
tab regime1
