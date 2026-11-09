*==============================================================================*
* test_convertanything.do -- test battery for convertanything 1.3.1
*
* Run:  stata-mp -b do test_convertanything.do ["/path/to/pkg" ["/work/dir"]]
*   arg 1: folder holding convertanything.ado (default: found on the adopath)
*   arg 2: folder for the fixtures (default: c(tmpdir)); a subfolder
*          ca_test_battery is created there and removed at the end
* log close resets r(), so results are kept in locals before a named log closes
* Judge the run by the log: it ends with "ALL TESTS PASSED" and has no
* "assertion is false" or r(NNN) error.  Only Stata commands and Mata are used
* for file work (no shell), so the battery runs on Windows, macOS and Linux.
*==============================================================================*
clear all
set more off
version 16

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

local work `"`2'"'
if `"`work'"' == "" local work `"`c(tmpdir)'"'
mata: st_local("work", subinstr(st_local("work"), char(92), "/"))
if substr(`"`work'"', -1, 1) == "/" local work = substr(`"`work'"', 1, strlen(`"`work'"') - 1)

* --- Mata helpers: recursive delete, file/folder tests -----------------------
capture mata: mata drop cat_rmtree()
capture mata: mata drop cat_fe()
capture mata: mata drop cat_de()
capture mata: mata drop cat_inlog()
mata:
void cat_rmtree(string scalar d)
{
    string colvector f
    real scalar j
    if (!direxists(d)) return
    f = dir(d, "files", "*")
    for (j = 1; j <= rows(f); j++) (void) _unlink(d + "/" + f[j])
    f = dir(d, "dirs", "*")
    for (j = 1; j <= rows(f); j++) {
        if (f[j] != "." & f[j] != "..") cat_rmtree(d + "/" + f[j])
    }
    (void) _rmdir(d)
}
// file exists, path taken from a local (no macro expansion of $ or `)
real scalar cat_fe(string scalar lname) return(fileexists(st_local(lname)))
real scalar cat_de(string scalar lname) return(direxists(st_local(lname)))
// 1 if text (local tname) occurs in the text log (local lname); wrapped
// lines ("> " continuations) are joined first
real scalar cat_inlog(string scalar lname, string scalar tname)
{
    real scalar fh
    string scalar s, t
    fh = fopen(st_local(lname), "r")
    s = fread(fh, 50000000)
    fclose(fh)
    if (s == J(0, 0, "")) s = ""
    s = subinstr(s, char(13), "")
    s = subinstr(s, char(10) + "> ", "")
    s = subinstr(s, char(10), " ")
    t = st_local(tname)
    return(strpos(s, t) > 0)
}
end

local root "`work'/ca_test_battery"
mata: cat_rmtree(st_local("root"))
mata: st_local("gone", strofreal(!direxists(st_local("root"))))
assert `gone'
mkdir "`root'"
local d = char(36)
local bq = char(96)

* ----- base tree used by TESTS 1-6 --------------------------------------------
local src "`root'/src"
local out "`root'/out"
mkdir "`src'"
mkdir "`src'/sub"
file open h using "`src'/a.csv", write replace
file write h "My Var,Other Col" _n "1,x" _n "2,y" _n "3,z" _n
file close h
file open h using "`src'/sub/b.csv", write replace
file write h "v1,v2" _n "10,20" _n "30,40" _n
file close h
sysuse auto, clear
save "`src'/c.dta", replace

*--- (1) recursive convert mirrors the tree ----------------------------------*
convertanything using "`src'", recursive saving("`out'") replace clear ///
    cleannames compress
confirm file "`out'/a.dta"
confirm file "`out'/sub/b.dta"
confirm file "`out'/c.dta"
di as res "TEST 1 OK: recursive convert mirrors the source tree"

*--- (2) r() results -----------------------------------------------------------*
assert r(N_files) == 3
assert r(N_converted) == 3
assert r(N_saved) == 3
assert r(N_skipped) == 0
assert r(N_failed) == 0
assert `: word count `r(saved)'' == 3
di as res "TEST 2 OK: r() counts (3 files, 3 saved)"

*--- (3) row counts, cleannames, numbers ---------------------------------------*
use "`out'/a.dta", clear
assert _N == 3
confirm variable myvar othercol
use "`out'/sub/b.dta", clear
assert _N == 2
confirm numeric variable v1 v2
quietly summarize v1
assert r(mean) == 20
use "`out'/c.dta", clear
assert _N == 74
di as res "TEST 3 OK: rows, cleaned names and numeric values preserved"

*--- (4) missing source fails loudly; using is required ------------------------*
capture noisily convertanything using "`root'/does_not_exist", ///
    recursive saving("`root'/out2") replace clear
assert _rc == 601
capture noisily convertanything "`src'", replace clear
assert _rc == 198
capture noisily convertanything, replace clear
assert _rc == 198
di as res "TEST 4 OK: missing path r(601); omitted using r(198)"

*--- (5) a rerun without replace skips, never aborts ---------------------------*
clear
convertanything using "`src'", recursive saving("`out'") clear
assert r(N_files) == 3 & r(N_skipped) == 3 & r(N_saved) == 0 & r(N_failed) == 0
capture noisily convertanything using "`src'/a.csv", saving("`out'") clear
assert _rc == 602
di as res "TEST 5 OK: existing outputs are skipped without replace (file mode r(602))"

*--- (6) clear: changed data protected, unchanged data never blocks a batch ----*
sysuse auto, clear
replace price = price + 1 in 1
capture noisily convertanything using "`src'", recursive saving("`root'/o6") replace
assert _rc == 4
mata: st_local("p", st_local("root") + "/o6/a.dta")
mata: assert(!cat_fe("p"))
sysuse auto, clear
convertanything using "`src'", recursive saving("`root'/o6") replace
assert r(N_saved) == 3
di as res "TEST 6 OK: no clear -> r(4) on changed data; whole batch runs otherwise"

*--- (7) folders with spaces, trailing separators, nested saving() -------------*
local s7 "`root'/sp dir"
mkdir "`s7'"
file open h using "`s7'/x.csv", write replace
file write h "a,b" _n "1,2" _n
file close h
convertanything using "`s7'/", saving("`root'/o7/a/b c/d/") replace clear
confirm file "`root'/o7/a/b c/d/x.dta"
convertanything using "`s7'//", saving("`root'/o7/e//") replace clear
confirm file "`root'/o7/e/x.dta"
if c(os) == "Windows" {
    local s7w : subinstr local s7 "/" "\", all
    local o7w : subinstr local root "/" "\", all
    convertanything using "`s7w'", saving("`o7w'\o7w\") replace clear
    confirm file "`root'/o7w/x.dta"
    convertanything using "`s7w'\x.csv", saving("`o7w'\o7w2\") replace clear
    confirm file "`root'/o7w2/x.dta"
    di as res "TEST 7w OK: backslash paths and trailing backslash in saving()"
}
di as res "TEST 7 OK: spaces, trailing slashes, nested saving() created"

*--- (8) extension case, extension() forms, Windows 8.3 double match ----------*
local s8 "`root'/case"
mkdir "`s8'"
mkdir "`s8'/_archive"
foreach f in lower.csv UPPER.CSV Mixed.Csv _archive/arch.csv {
    file open h using "`s8'/`f'", write replace
    file write h "a,b" _n "1,2" _n
    file close h
}
sysuse auto, clear
keep in 1/5
export excel using "`s8'/BOOK.XLSX", firstrow(variables) replace
export excel using "`s8'/old.xls", firstrow(variables) replace
convertanything using "`s8'", recursive saving("`root'/o8") replace clear
assert r(N_files) == 5 & r(N_saved) == 5
foreach f in lower UPPER Mixed BOOK old {
    confirm file "`root'/o8/`f'.dta"
}
mata: st_local("p", st_local("root") + "/o8/_archive")
mata: assert(!cat_de("p"))
convertanything using "`s8'", saving("`root'/o8b") extension(CSV) replace clear
assert r(N_files) == 3
convertanything using "`s8'", saving("`root'/o8c") extension(.xlsx) replace clear
assert r(N_files) == 1
* quotes inside extension() do not shift other options (skip default kept)
convertanything using "`s8'", recursive saving("`root'/o8d") ///
    extension(`""csv" "xlsx""') replace clear
assert r(N_files) == 4
mata: st_local("p", st_local("root") + "/o8d/_archive")
mata: assert(!cat_de("p"))
capture noisily convertanything using "`s8'", extension(pdf) clear
assert _rc == 198
di as res "TEST 8 OK: FILE.CSV/.Csv/.XLSX found; extension() forms; xls != xlsx"

*--- (9) same basename: unique outputs; source .dta never overwritten ----------*
local s9 "`root'/same"
mkdir "`s9'"
file open h using "`s9'/survey.csv", write replace
file write h "id,v" _n "1,10" _n "2,20" _n
file close h
sysuse auto, clear
keep in 1/4
export excel using "`s9'/survey.xlsx", firstrow(variables) replace
sysuse auto, clear
keep in 1/7
save "`s9'/survey.dta", replace
datasignature
local sig `"`r(datasignature)'"'
convertanything using "`s9'", replace clear
confirm file "`s9'/survey_csv.dta"
confirm file "`s9'/survey_xlsx.dta"
convertanything using "`s9'", replace clear
convertanything using "`s9'/survey.csv", replace clear
local f : dir "`s9'" files "*.dta"
assert `: word count `f'' == 3
use "`s9'/survey.dta", clear
datasignature
assert `"`r(datasignature)'"' == `"`sig'"'
assert `"`: char _dta[convertanything]'"' == ""
use "`s9'/survey_csv.dta", clear
assert _N == 2
* with saving(): the .dta copy keeps its name, the others get a suffix
convertanything using "`s9'", saving("`root'/o9") replace clear
confirm file "`root'/o9/survey.dta"
confirm file "`root'/o9/survey_csv.dta"
confirm file "`root'/o9/survey_xlsx.dta"
di as res "TEST 9 OK: survey.csv/.xlsx/.dta -> distinct outputs; source .dta untouched"

*--- (10) saving() naming the source folder another way ------------------------*
local s10 "`root'/self"
mkdir "`s10'"
sysuse auto, clear
save "`s10'/keep.dta", replace
datasignature
local sig `"`r(datasignature)'"'
convertanything using "`s10'/", saving("`s10'/./") replace clear cleannames destring
assert r(N_saved) == 0
use "`s10'/keep.dta", clear
datasignature
assert `"`r(datasignature)'"' == `"`sig'"'
di as res "TEST 10 OK: src/ vs src/./ recognized as the same folder"

*--- (11) recursive never enters its own saving() folder -----------------------*
local s11 "`root'/nest"
mkdir "`s11'"
file open h using "`s11'/n.csv", write replace
file write h "a" _n "1" _n
file close h
local here `"`c(pwd)'"'
quietly cd "`s11'"
convertanything, recursive saving("conv") replace clear
convertanything, recursive saving("conv") replace clear
quietly cd `"`here'"'
confirm file "`s11'/conv/n.dta"
mata: st_local("p", st_local("s11") + "/conv/conv")
mata: assert(!cat_de("p"))
di as res "TEST 11 OK: saving() inside the source tree is not re-entered"

*--- (12) text files: multi-line quotes, UTF-8, encoding(), headers -----------*
local s12 "`root'/text"
mkdir "`s12'"
file open h using "`s12'/ml.csv", write replace
file write h "id,comment" _n `"1,"line one"' _n `"line two""' _n `"2,"ok""' _n
file close h
convertanything using "`s12'/ml.csv", replace clear
use "`s12'/ml.dta", clear
assert _N == 2
assert id[2] == 2
file open h using "`s12'/u8.csv", write replace
file write h "name,city" _n "Peña,San Antonio" _n "José,Río Grande" _n
file close h
convertanything using "`s12'/u8.csv", replace clear
use "`s12'/u8.dta", clear
assert name[1] == "Peña" & city[2] == "Río Grande"
file open h using "`s12'/l1.csv", write replace
file write h "name" _n "Pe" _char(241) "a" _n
file close h
convertanything using "`s12'/l1.csv", replace clear encoding("latin1")
use "`s12'/l1.dta", clear
assert name[1] == "Peña"
* all-text header kept by default; nofirstrow reads it as data
use "`s12'/u8.dta", clear
assert _N == 2
confirm variable name city
convertanything using "`s12'/u8.csv", saving("`s12'/nf") replace clear nofirstrow
use "`s12'/nf/u8.dta", clear
assert _N == 3 & v1[1] == "name"
di as res "TEST 12 OK: quoted line breaks, UTF-8 default, encoding(), header rules"

*--- (13) Excel: allsheets collisions, quote in sheet name, nofirstrow ---------*
local s13 "`root'/xl"
mkdir "`s13'"
clear
set obs 3
gen x = _n
gen y = "a" + string(_n)
export excel using "`s13'/wb.xlsx", sheet("Sheet 1") firstrow(variables) replace
export excel using "`s13'/wb.xlsx", sheet("Sheet_1") firstrow(variables) sheetreplace
export excel using "`s13'/wb.xlsx", sheet(`"say "hi""') firstrow(variables) sheetreplace
export excel using "`s13'/wb.xlsx", sheet("x") firstrow(variables) sheetreplace
export excel using "`s13'/nohead.xlsx", replace
file open h using "`s13'/wb_x.csv", write replace
file write h "q" _n "9" _n
file close h
convertanything using "`s13'", allsheets saving("`root'/o13") replace clear
assert r(N_failed) == 0 & r(N_files) == 3
* 4 sheets + nohead (1 sheet) + wb_x.csv
assert r(N_saved) == 6
local f : dir "`root'/o13" files "wb_*.dta"
assert `: word count `f'' == 5
use "`root'/o13/wb_x.dta", clear
confirm variable q
convertanything using "`s13'/nohead.xlsx", saving("`root'/o13b") replace clear nofirstrow
use "`root'/o13b/nohead.dta", clear
assert _N == 3
convertanything using "`s13'/nohead.xlsx", saving("`root'/o13c") replace clear
use "`root'/o13c/nohead.dta", clear
assert _N == 2
di as res "TEST 13 OK: sheet-name collisions, quoted sheet, nofirstrow"

*--- (14) destring: IDs kept, reports, comma and percent rules ----------------*
local s14 "`root'/ds"
mkdir "`s14'"
file open h using "`s14'/d.csv", write replace
file write h "zip,big,amt,pct,mix,codes,n" _n
file write h `"00123,12345678901234567,"`d'1,200",45%,5%,"1,5",7"' _n
file write h `"78701,22345678901234567,"`d'3",50%,6,"2,3",8"' _n
file close h
convertanything using "`s14'/d.csv", replace clear destring
use "`s14'/d.dta", clear
confirm string variable zip big mix codes
confirm numeric variable amt pct n
assert zip[1] == "00123"
assert amt[1] == 1200 & abs(pct[1] - .45) < 1e-6 & n[2] == 8
di as res "TEST 14 OK: destring keeps ID-like text, converts money/percent"

*--- (15) $ and backquotes in file names --------------------------------------*
local s15 "`root'/macro"
mkdir "`s15'"
local n1 = "Plan " + char(36) + "FY25.csv"
local n2 = "Costs_" + char(36) + "USD.csv"
local n3 = "Costs_.csv"
local n4 = "a" + char(96) + "b.csv"
local k 0
foreach nm in n1 n2 n3 n4 {
    local ++k
    mata: st_local("p", st_local("s15") + "/" + st_local(st_local("nm")))
    file open h using `"`macval(p)'"', write replace
    file write h "v" _n "`k'" _n
    file close h
}
clear
set obs 1
generate v = 5
mata: st_local("p", st_local("s15") + "/d" + char(96) + "t.dta")
save `"`macval(p)'"', replace
convertanything using "`s15'", saving("`root'/o15") replace clear
assert r(N_files) == 5 & r(N_saved) == 5 & r(N_failed) == 0
* every source is still there (temporary copies are removed, sources never)
foreach nm in n1 n2 n3 n4 {
    mata: st_local("p", st_local("s15") + "/" + st_local(st_local("nm")))
    mata: assert(cat_fe("p"))
}
mata: st_local("p", st_local("s15") + "/d" + char(96) + "t.dta")
mata: assert(cat_fe("p"))
mata: st_local("p", st_local("root") + "/o15/d" + char(96) + "t.dta")
mata: assert(cat_fe("p"))
local e1 = "Plan " + char(36) + "FY25"
local e2 = "Costs_" + char(36) + "USD"
local e3 = "Costs_"
local e4 = "a" + char(96) + "b"
local k 0
foreach nm in e1 e2 e3 e4 {
    local ++k
    mata: st_local("p", st_local("root") + "/o15/" + st_local(st_local("nm")) + ".dta")
    mata: assert(cat_fe("p"))
    use `"`macval(p)'"', clear
    assert v[1] == `k'
}
di as res "TEST 15 OK: names with $ and a backquote are never expanded"

*--- (16) AppleDouble and Excel lock files are ignored (see also TEST 26) -----*
local s16 "`root'/junk"
mkdir "`s16'"
file open h using "`s16'/._a.csv", write replace
file write h "junk" _n "1" _n
file close h
mata: st_local("p", st_local("s16") + "/~" + char(36) + "book.xlsx")
file open h using `"`macval(p)'"', write replace
file write h "lock" _n
file close h
file open h using "`s16'/a.csv", write replace
file write h "v" _n "1" _n
file close h
convertanything using "`s16'", replace clear
assert r(N_files) == 1 & r(N_failed) == 0
mata: st_local("p", st_local("s16") + "/._a.dta")
mata: assert(!cat_fe("p"))
di as res "TEST 16 OK: ._* and ~$* files ignored"

*--- (17) skip(): "" turns default off; case-insensitive; names with spaces ----*
local s17 "`root'/skip"
mkdir "`s17'"
foreach sd in _archive Archive2 "my folder" other {
    mkdir "`s17'/`sd'"
    file open h using "`s17'/`sd'/f.csv", write replace
    file write h "v" _n "1" _n
    file close h
}
convertanything using "`s17'", recursive saving("`root'/o17a") replace clear
assert r(N_files) == 3
convertanything using "`s17'", recursive saving("`root'/o17b") replace clear skip("")
assert r(N_files) == 4
convertanything using "`s17'", recursive saving("`root'/o17c") replace clear ///
    skip(ARCHIVE2 _ARCHIVE)
assert r(N_files) == 2
convertanything using "`s17'", recursive saving("`root'/o17d") replace clear ///
    skip("my folder" other)
assert r(N_files) == 2
convertanything using "`s17'", recursive saving("`root'/o17e") replace clear ///
    skip("_converted _archive")
assert r(N_files) == 3
di as res "TEST 17 OK: skip() forms"

*--- (18) cleannames collisions -----------------------------------------------*
local s18 "`root'/names"
mkdir "`s18'"
* a .dta source keeps the case of its names (import delimited lowercases)
clear
set obs 2
foreach v in ID id id_2 Name name {
    generate `v' = _n
}
save "`s18'/n.dta", replace
convertanything using "`s18'/n.dta", saving("`root'/o18") replace clear cleannames
use "`root'/o18/n.dta", clear
foreach v of varlist _all {
    assert "`v'" == lower("`v'")
}
assert c(k) == 5
confirm variable id id_2 id_3 name name_2
di as res "TEST 18 OK: cleannames collisions get unique lowercase names"

*--- (19) .raw: dictionary, free format, unsupported layout --------------------*
local s19 "`root'/raw"
mkdir "`s19'"
clear
input double x str5 s
1 "ab"
2 "cd"
3 "e f"
end
outfile using "`s19'/free.raw", replace
file open h using "`s19'/dict.raw", write replace
file write h "dictionary {" _n "  float a" _n "  float b" _n "}" _n "1 2" _n "3 4" _n
file close h
file open h using "`s19'/ragged.raw", write replace
file write h "1 2 3" _n "4 5" _n
file close h
convertanything using "`s19'", replace clear
assert r(N_files) == 3 & r(N_converted) == 2 & r(N_failed) == 1
use "`s19'/free.dta", clear
assert _N == 3 & c(k) == 2 & v1[3] == 3 & v2[3] == "e f"
use "`s19'/dict.dta", clear
assert _N == 2 & b[2] == 4
capture noisily convertanything using "`s19'/ragged.raw", replace clear
assert _rc == 610
di as res "TEST 19 OK: .raw dictionary and free format; ragged reported"

*--- (20) single file: unsupported type, extension() note ---------------------*
file open h using "`root'/notes.pdf", write replace
file write h "x" _n
file close h
capture noisily convertanything using "`root'/notes.pdf", replace clear
assert _rc == 198
convertanything using "`src'/a.csv", saving("`root'/o20") extension(xlsx) replace clear
confirm file "`root'/o20/a.dta"
di as res "TEST 20 OK: unsupported single file r(198)"

*--- (21) v1.2 call syntax still works ---------------------------------------*
convertanything using "`src'", recursive saving("`root'/o21") ///
    skip("_converted _archive") allsheets cleannames destring compress clear replace
assert r(N_saved) == 3
di as res "TEST 21 OK: v1.2 syntax"

*--- (22) header detection for text files: firstrow / nofirstrow ---------------*
local s22 "`root'/hdr"
mkdir "`s22'"
file open h using "`s22'/nh.csv", write replace
file write h "1,2,3" _n "4,5,6" _n
file close h
file open h using "`s22'/yr.csv", write replace
file write h "2019,2020" _n "5,6" _n "7,8" _n
file close h
file open h using "`s22'/mixed.csv", write replace
file write h "1,Smith,45" _n "2,Jones,50" _n
file close h
file open h using "`s22'/unsure.csv", write replace
file write h "1,,3" _n "4,5,6" _n
file close h
file open h using "`s22'/onecol.txt", write replace
file write h "5" _n "6" _n "7" _n
file close h
file open h using "`s22'/tabbed.tab", write replace
file write h "1" _tab "2" _n "3" _tab "4" _n
file close h
file open h using "`s22'/named.csv", write replace
file write h "a,b" _n "1,2" _n
file close h
file open h using "`s22'/quoted.csv", write replace
file write h `""2019","2020""' _n "1,2" _n
file close h
local lg "`root'/l22.log"
log using "`lg'", text replace name(t22)
convertanything using "`s22'", replace clear
local ok = r(N_saved) == 8 & r(N_failed) == 0
log close t22
assert `ok'
local t "every field of the first row is a number (1,2,3)"
mata: assert(cat_inlog("lg", "t"))
local t "specify nofirstrow"
mata: assert(cat_inlog("lg", "t"))
use "`s22'/nh.dta", clear
assert _N == 2 & c(k) == 3 & v1[1] == 1 & v3[2] == 6
use "`s22'/yr.dta", clear
assert _N == 3 & v1[1] == 2019
use "`s22'/mixed.dta", clear
assert _N == 1
use "`s22'/unsure.dta", clear
assert _N == 1
use "`s22'/onecol.dta", clear
assert _N == 3 & v1[3] == 7
use "`s22'/tabbed.dta", clear
assert _N == 2 & v2[2] == 4
use "`s22'/named.dta", clear
assert _N == 1
confirm variable a b
* numbers in quotes are not taken as data: header kept, with a note
use "`s22'/quoted.dta", clear
assert _N == 1
local t "written in quotes"
mata: assert(cat_inlog("lg", "t"))
* firstrow forces a numeric header: years as column names
convertanything using "`s22'/yr.csv", saving("`root'/o22") firstrow replace clear
use "`root'/o22/yr.dta", clear
assert _N == 2
assert `"`: variable label v1'"' == "2019"
* nofirstrow forces data for the mixed first row
convertanything using "`s22'/mixed.csv", saving("`root'/o22") nofirstrow replace clear
use "`root'/o22/mixed.dta", clear
assert _N == 2 & v2[1] == "Smith"
* header-less with destring
convertanything using "`s22'/nh.csv", saving("`root'/o22d") destring replace clear
use "`root'/o22d/nh.dta", clear
assert _N == 2
confirm numeric variable v1 v2 v3
capture noisily convertanything using "`s22'/nh.csv", firstrow nofirstrow replace clear
assert _rc == 198
di as res "TEST 22 OK: all-number first row read as data; firstrow/nofirstrow override"

*--- (23) encoding: invalid UTF-8 detected; latin1 / windows-1252 read --------*
local s23 "`root'/enc"
mkdir "`s23'"
file open h using "`s23'/lat.csv", write replace
file write h "city,n" _n "Pe" _char(241) "itas,1" _n "Ca" _char(241) "on City,2" _n
file close h
file open h using "`s23'/win.csv", write replace
file write h "note" _n "A" _char(150) "B Pe" _char(241) "a" _n
file close h
file open h using "`s23'/mix.csv", write replace
file write h "name" _n "Jos" _char(195) _char(169) _n "Pe" _char(241) "a" _n
file close h
local lg "`root'/l23.log"
log using "`lg'", text replace name(t23)
convertanything using "`s23'", replace clear
local ok = r(N_saved) == 3
log close t23
assert `ok'
local t "read as encoding(latin1)"
mata: assert(cat_inlog("lg", "t"))
local t "read as encoding(windows-1252)"
mata: assert(cat_inlog("lg", "t"))
local t "those bytes are DROPPED"
mata: assert(cat_inlog("lg", "t"))
use "`s23'/lat.dta", clear
assert city[1] == "Pe" + uchar(241) + "itas" & n[2] == 2
use "`s23'/win.dta", clear
assert note[1] == "A" + uchar(8211) + "B Pe" + uchar(241) + "a"
use "`s23'/mix.dta", clear
assert name[1] == "Jos" + uchar(233)
* an explicit encoding() is used as given: utf-8 warns and drops the byte
local lg "`root'/l23b.log"
log using "`lg'", text replace name(t23b)
convertanything using "`s23'/lat.csv", saving("`root'/o23") encoding(utf-8) replace clear
log close t23b
local t "encoding(utf-8) was given"
mata: assert(cat_inlog("lg", "t"))
use "`root'/o23/lat.dta", clear
assert city[1] != "Pe" + uchar(241) + "itas"
convertanything using "`s23'/lat.csv", saving("`root'/o23b") encoding(latin1) replace clear
use "`root'/o23b/lat.dta", clear
assert city[1] == "Pe" + uchar(241) + "itas"
di as res "TEST 23 OK: latin1/windows-1252 detected and read; explicit encoding() obeyed"

*--- (24) rerun over v1.2 outputs: untagged name.dta is never overwritten ------*
local s24 "`root'/v12"
mkdir "`s24'"
file open h using "`s24'/p.csv", write replace
file write h "x" _n "1" _n "2" _n
file close h
* a v1.2-style output: same data, no _dta[convertanything] record
import delimited using "`s24'/p.csv", clear
save "`s24'/p.dta", replace
datasignature
local sig `"`r(datasignature)'"'
local lg "`root'/l24.log"
log using "`lg'", text replace name(t24)
convertanything using "`s24'", replace clear
local ok = r(N_saved) == 1 & r(N_inplace) == 1
log close t24
assert `ok'
confirm file "`s24'/p_csv.dta"
local t "has no convertanything record"
mata: assert(cat_inlog("lg", "t"))
local t "move or delete"
mata: assert(cat_inlog("lg", "t"))
use "`s24'/p.dta", clear
datasignature
assert `"`r(datasignature)'"' == `"`sig'"'
* rerun: the suffixed output is ours, so replace overwrites it
convertanything using "`s24'", replace clear
assert r(N_saved) == 1
local f : dir "`s24'" files "*.dta"
assert `: word count `f'' == 2
* opt in to the plain name: delete the old output, rerun with replace
erase "`s24'/p.dta"
convertanything using "`s24'/p.csv", replace clear
use "`s24'/p.dta", clear
assert `"`: char _dta[convertanything]'"' == "p.csv"
convertanything using "`s24'/p.csv", replace clear
assert r(N_saved) == 1
confirm file "`s24'/p.dta"
di as res "TEST 24 OK: v1.2 output kept, new name explained; delete + replace restores plain name"

*--- (25) zero-padded codes stay text without destring ------------------------*
local s25 "`root'/codes"
mkdir "`s25'"
file open h using "`s25'/c.csv", write replace
file write h "zip,fips,amt,month,frac,lab" _n
file write h "78701,453,5,10,0.5,NA" _n
file write h "00501,001,6,01,1.5,01" _n
file write h "73301,113,7,12,2.5,x" _n
file close h
file open h using "`s25'/nh.tab", write replace
file write h "01" _tab "5" _n "02" _tab "6" _n
file close h
file open h using "`s25'/plain.csv", write replace
file write h "a,b" _n "10,0.25" _n "20,1.75" _n
file close h
convertanything using "`s25'", replace clear
assert r(N_saved) == 3
use "`s25'/c.dta", clear
confirm string variable zip fips month lab
confirm numeric variable amt frac
assert zip[2] == "00501" & fips[2] == "001" & month[2] == "01" & lab[2] == "01"
assert abs(frac[1] - .5) < 1e-6
use "`s25'/nh.dta", clear
confirm string variable v1
confirm numeric variable v2
assert v1[1] == "01" & _N == 2
use "`s25'/plain.dta", clear
confirm numeric variable a b
* destring keeps its own ID protection
convertanything using "`s25'/c.csv", saving("`root'/o25") destring replace clear
use "`root'/o25/c.dta", clear
confirm string variable zip fips month
confirm numeric variable amt frac
di as res "TEST 25 OK: zero-padded code columns kept as text; other columns numeric"

*--- (26) only Excel lock files are skipped among ~$ names --------------------*
local s26 "`root'/lock"
mkdir "`s26'"
foreach nm in notes.csv book.xlsx old.xls {
    mata: st_local("p", st_local("s26") + "/~" + char(36) + st_local("nm"))
    file open h using `"`macval(p)'"', write replace
    file write h "v" _n "1" _n
    file close h
}
convertanything using "`s26'", replace clear
assert r(N_files) == 1 & r(N_saved) == 1 & r(N_failed) == 0
mata: st_local("p", st_local("s26") + "/~" + char(36) + "notes.dta")
mata: assert(cat_fe("p"))
di as res "TEST 26 OK: a ~$-prefixed csv is converted; Excel lock files ignored"

*--- (27) cleannames: the variable that must be renamed gets the suffix -------*
local s27 "`root'/order"
mkdir "`s27'"
clear
set obs 1
generate id = 1
generate ID = 2
save "`s27'/a.dta", replace
clear
set obs 1
generate ID = 1
generate id = 2
save "`s27'/b.dta", replace
convertanything using "`s27'", saving("`root'/o27") cleannames replace clear
use "`root'/o27/a.dta", clear
assert id == 1 & id_2 == 2
use "`root'/o27/b.dta", clear
assert id_2 == 1 & id == 2
di as res "TEST 27 OK: cleannames suffix goes to the renamed variable (id then ID -> id, id_2)"

*--- (28) the stray-quote rule for text files (1.3.1) ------------------------*
* Text files are read with bindquote(strict).  When a cell has a line break
* and a later line of that cell looks like a data row (at least k-1
* delimiters; for k <= 2 also an id-like leading token), a stray quote joined
* rows: a WARNING note names the cell and the loose result is kept.
* Otherwise strict is kept silently.  strictquotes forces strict binding.
local s28 "`root'/quotes"
mkdir "`s28'"
local q = char(34)
* (a) a legitimate multi-line survey answer: one row, no note, one import
file open h using "`s28'/ml.csv", write replace
file write h "id,answer,score" _n `"1,"I liked it."' _n `"Then, less so.",10"' _n "2,ok,20" _n
file close h
local lg "`root'/l28a.log"
log using "`lg'", text replace name(t28a)
convertanything using "`s28'/ml.csv", replace clear
log close t28a
use "`s28'/ml.dta", clear
assert _N == 2 & score[2] == 20
assert answer[1] == "I liked it." + char(10) + "Then, less so."
local t "WARNING"
mata: assert(!cat_inlog("lg", "t"))
local t "line breaks"
mata: assert(!cat_inlog("lg", "t"))
* (b) a stray inch mark: WARNING note naming the cell and both row counts,
*     loose rows kept
file open h using "`s28'/inch.csv", write replace
file write h "id,desc,n" _n "1,5" `"""' " screen,10" _n "2,ok,20" _n "3,fine,30" _n
file close h
quietly import delimited using "`s28'/inch.csv", bindquote(strict) maxquotedrows(unlimited) clear
assert _N == 1
local lg "`root'/l28b.log"
log using "`lg'", text replace name(t28b)
convertanything using "`s28'/inch.csv", replace clear
log close t28b
use "`s28'/inch.dta", clear
assert _N == 3 & n[3] == 30 & desc[2] == "ok"
local t "WARNING: stray-quote check: in the strict read, the quoted cell in row 1, column desc"
mata: assert(cat_inlog("lg", "t"))
local t "strict quote binding read 1 row(s), loose binding read 3 row(s); the loose result is used"
mata: assert(cat_inlog("lg", "t"))
* strictquotes: strict binding, no fallback, no note
local lg "`root'/l28c.log"
log using "`lg'", text replace name(t28c)
convertanything using "`s28'/inch.csv", replace clear strictquotes
log close t28c
use "`s28'/inch.dta", clear
assert _N == 1
local t "WARNING"
mata: assert(!cat_inlog("lg", "t"))
* (c) both in one file: the stray-quote warning wins (documented); the loose
*     result is kept, so the multi-line answer splits too
file open h using "`s28'/both.csv", write replace
file write h "id,answer,score" _n `"1,"line one"' _n `"line two",10"' _n
file write h "2,5" `"""' " screen,20" _n "3,fine,30" _n "4,ok,40" _n
file close h
quietly import delimited using "`s28'/both.csv", clear
local nloose = _N
local lg "`root'/l28d.log"
log using "`lg'", text replace name(t28d)
convertanything using "`s28'/both.csv", replace clear
log close t28d
use "`s28'/both.dta", clear
assert _N == `nloose'
local t "in the strict read, the quoted cell in row 2, column answer"
mata: assert(cat_inlog("lg", "t"))
* (d) a clean file: no note, and the fast path imports it once
file open h using "`s28'/clean.csv", write replace
file write h "id,answer" _n "1,plain" _n "2,also plain" _n
file close h
local lg "`root'/l28e.log"
log using "`lg'", text replace name(t28e)
convertanything using "`s28'/clean.csv", replace clear
log close t28e
local t "WARNING"
mata: assert(!cat_inlog("lg", "t"))
* (e) tab-delimited variants: a second line with two commas is text in a tab
*     file (k = 3, but its delimiter is the tab); a stray inch mark warns
file open h using "`s28'/mltab.tab", write replace
file write h "id" _tab "answer" _tab "score" _n "1" _tab `""one, two, three"' _n
file write h `"four, five, six""' _tab "10" _n "2" _tab "ok" _tab "20" _n
file close h
local lg "`root'/l28f.log"
log using "`lg'", text replace name(t28f)
convertanything using "`s28'/mltab.tab", replace clear
log close t28f
use "`s28'/mltab.dta", clear
assert _N == 2 & answer[1] == "one, two, three" + char(10) + "four, five, six"
local t "WARNING"
mata: assert(!cat_inlog("lg", "t"))
file open h using "`s28'/inchtab.txt", write replace
file write h "id" _tab "desc" _tab "n" _n "1" _tab "5" `"""' " screen" _tab "10" _n
file write h "2" _tab "ok" _tab "20" _n "3" _tab "fine" _tab "30" _n
file close h
local lg "`root'/l28g.log"
log using "`lg'", text replace name(t28g)
convertanything using "`s28'/inchtab.txt", replace clear
log close t28g
use "`s28'/inchtab.dta", clear
assert _N == 3 & n[3] == 30
local t "strict quote binding read 1 row(s), loose binding read 3 row(s)"
mata: assert(cat_inlog("lg", "t"))
* (f) the private helper itself: status and number of imports.  Running the
*     ado-file defines it for this do-file (discard first).
discard
quietly run "$pkgroot/convertanything.ado"
_cva_qguard "`s28'/clean.csv", varnames(1)
assert "`qg_status'" == "clean" & `qg_nread' == 1 & _N == 2
_cva_qguard "`s28'/ml.csv", varnames(1)
assert "`qg_status'" == "multiline" & `qg_nread' == 1 & _N == 2
quietly _cva_qguard "`s28'/inch.csv", varnames(1)
assert "`qg_status'" == "stray" & `qg_nread' == 2 & _N == 3
assert `qg_nstrict' == 1 & `qg_nloose' == 3 & "`qg_obs'" == "1" & "`qg_var'" == "desc"
_cva_qguard "`s28'/inch.csv", varnames(1) strictquotes
assert "`qg_status'" == "forced" & `qg_nread' == 1 & _N == 1
_cva_qguard "`s28'/mltab.tab", varnames(1)
assert "`qg_status'" == "multiline" & _N == 2
di as res "TEST 28 OK: stray-quote rule (multi-line kept, stray quote warned, both, clean, tab)"

* ----- cleanup (Stata/Mata only) ----------------------------------------------
clear
mata: cat_rmtree(st_local("root"))
mata: st_local("gone", strofreal(!direxists(st_local("root"))))
assert `gone'
di as res _n "ALL TESTS PASSED: convertanything battery complete"
