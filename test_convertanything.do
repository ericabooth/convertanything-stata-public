*==============================================================================*
* test_convertanything.do -- battery for convertanything v1.2
* Run:  stata-mp -b do test_convertanything.do ["/path/to/pkg"]
* Judge the run by the log: no r(NNN) errors, no "assertion is false".
*==============================================================================*
clear all
set more off

if `"`1'"' != "" global pkgroot `"`1'"'
if `"$pkgroot"' == "" {
    capture findfile convertanything.ado
    if !_rc {
        local fp `"`r(fn)'"'
        local s = max(strrpos(`"`fp'"', "/"), strrpos(`"`fp'"', "\"))
        if `s' > 1 global pkgroot = substr(`"`fp'"', 1, `s' - 1)
    }
}
if `"$pkgroot"' == "" {
    di as err "test_convertanything: cannot locate convertanything.ado."
    exit 601
}
confirm file "$pkgroot/convertanything.ado"
adopath ++ "$pkgroot"
discard

* ----- build a small mixed-format source tree ---------------------------------
local root "`c(tmpdir)'/ca_test_src"
local out  "`c(tmpdir)'/ca_test_out"
capture shell rm -rf "`root'" "`out'"
mkdir "`root'"
mkdir "`root'/sub"

* a.csv: 3 data rows, a header that needs cleaning
file open h using "`root'/a.csv", write replace
file write h "My Var,Other Col" _n "1,x" _n "2,y" _n "3,z" _n
file close h
* sub/b.csv: 2 data rows
file open h using "`root'/sub/b.csv", write replace
file write h "v1,v2" _n "10,20" _n "30,40" _n
file close h
* c.dta: 74-row auto
sysuse auto, clear
save "`root'/c.dta", replace

*--- (1) recursive convert mirrors the tree -----------------------------------*
convertanything using "`root'", recursive saving("`out'") replace clear ///
    cleannames compress
confirm file "`out'/a.dta"
confirm file "`out'/sub/b.dta"
confirm file "`out'/c.dta"
di as res "TEST 1 OK: recursive convert mirrors the source tree"

*--- (2) row counts survive ---------------------------------------------------*
use "`out'/a.dta", clear
assert _N == 3
use "`out'/sub/b.dta", clear
assert _N == 2
use "`out'/c.dta", clear
assert _N == 74
di as res "TEST 2 OK: row counts preserved (3 / 2 / 74)"

*--- (3) cleannames makes headers Stata-legal lowercase -----------------------*
use "`out'/a.dta", clear
capture confirm variable myvar
if _rc {
    * accept the underscore variant some versions produce
    confirm variable my_var
}
di as res "TEST 3 OK: header cleaned to a legal lowercase name"

*--- (4) values arrive as numbers, not strings --------------------------------*
use "`out'/sub/b.dta", clear
confirm numeric variable v1 v2
quietly summarize v1
assert r(mean) == 20
di as res "TEST 4 OK: delimited values import as numbers"

*--- (5) missing source directory fails loudly --------------------------------*
capture noisily convertanything using "`c(tmpdir)'/ca_does_not_exist", ///
    recursive saving("`out'2") replace clear
assert _rc != 0
di as res "TEST 5 OK: missing source errors (rc " _rc ")"

capture shell rm -rf "`root'" "`out'" "`out'2"
di as res _n "ALL TESTS PASSED: convertanything battery complete"
