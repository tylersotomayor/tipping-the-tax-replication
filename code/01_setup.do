version 18.0
* Purpose: settings and dependency checks.
set more off
set scheme s1mono
set seed 20260727
foreach dir in "${DATA_INT}" "${DATA_CLEAN}" "${FIGURES}" "${TABLES}" "${LOGS}" {
    capture mkdir "`dir'"
}
foreach cmd in reghdfe esttab boottest {
    capture which `cmd'
    if _rc {
        di as error "missing `cmd'"
        exit 111
    }
}
