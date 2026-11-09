*! version 1.3.1  09nov2026
*! convertanything: convert a file, or a folder tree of csv/txt/tab/xls/xlsx/dta/raw
*! files, to Stata .dta datasets
*! Author: Eric A. Booth (eric.a.booth@gmail.com)
*!
*! v1.3.1 changes vs v1.3:
*!   - Text files follow a stray-quote rule (shared with combineall and
*!     cxchangelog).  Read with bindquote(strict); when a cell has a line
*!     break and a later line of that cell looks like a data row (at least
*!     k-1 delimiters for k columns; for k <= 2 also an id-like leading
*!     token), an unmatched quote such as an inch mark joined rows, so a
*!     WARNING note names the cell and the file is read with loose binding.
*!     Otherwise strict is kept silently (the v1.3 line-break note is gone).
*!     New option strictquotes keeps strict binding with no fallback.
*!
*! v1.3 changes vs v1.2:
*!   - Folders are detected with Mata direxists(), so folder and recursive mode
*!     work on Windows.  On Windows, backslashes in using and saving() become "/".
*!     A leading ~ is expanded from HOME (USERPROFILE on Windows).
*!   - Files are listed once per folder before anything is written; extensions
*!     match without regard to case; ._* (AppleDouble) files and Excel lock
*!     files (~$*.xls, ~$*.xlsx, ~$*.xlsm) are ignored; recursion never enters
*!     the saving() folder.
*!   - Every file gets a status (saved, skipped, failed) and a reason.  A summary
*!     always prints and is returned in r().  A batch never stops part way: a file
*!     whose output exists without replace is skipped, not an error.
*!   - Output names are unique within a run (survey.csv + survey.xlsx give
*!     survey_csv.dta + survey_xlsx.dta), and a .dta in the source folder that
*!     convertanything did not write from the same source (such as a v1.2
*!     output) is never overwritten; a note explains the new name.
*!   - Text files: UTF-8 by default (encoding()); a file that is not valid
*!     UTF-8 is read as latin1 or windows-1252 with a note, or warned about;
*!     the first row is checked: all numbers -> no header (firstrow forces
*!     one, nofirstrow forces none); columns of zero-padded codes (01, 00123)
*!     stay text; quoted line breaks kept (bindquote(strict), loose retry).
*!   - destring skips ID-like text and reports what it converted.
*!   - New options: encoding(), nofirstrow, firstrow; skip("") turns off the
*!     default list.
*!   - The v1.1 internal names ProcessFile and PostProcess are gone; they were
*!     never callable from outside this file.

program define convertanything, rclass
    version 16
    syntax [anything] [using/] [,                                          ///
        SAVing(string)     /// destination folder for .dta output
        RECURsive          /// recurse into subfolders (mirrors tree into saving())
        ALLsheets          /// import every worksheet of each Excel file
        REPLACE            /// overwrite .dta files this command wrote before
        CLEAR              /// allow replacing changed data in memory
        EXtension(string)  /// restrict folder mode to these extensions
        VERbose            /// per-file progress
        COMPress           /// compress every converted dataset
        CLEANnames         /// lowercase + Stata-legal variable names
        DESTRing           /// destring numeric-looking text (ID-like text kept)
        SKIP(string asis)  /// folder names to skip (default: _converted _archive)
        ENCoding(string)   /// encoding of text files (default utf-8, checked)
        NOFIRSTrow         /// first row is data, not variable names
        FIRSTrow           /// first row is variable names (no header detection)
        STRICTQuotes       /// text files: strict quote binding, no fallback
    ]
    * NOFIRSTrow must be declared before FIRSTrow: in the other order syntax
    * reads "nofirstrow" as "firstrow turned off" and both locals stay empty

    if `"`macval(anything)'"' != "" {
        di as error "convertanything: put {bf:using} before the path, for example"
        di as error `"    convertanything using "mydata.csv", replace clear"'
        exit 198
    }
    if `"`macval(using)'"' == "" & "`recursive'" == "" {
        di as error "convertanything: specify a file or folder with {bf:using}, for example"
        di as error `"    convertanything using "mydata.csv", replace clear"'
        exit 198
    }
    if "`firstrow'" != "" & "`nofirstrow'" != "" {
        di as error "convertanything: options firstrow and nofirstrow may not be combined"
        exit 198
    }
    if c(changed) & "`clear'" == "" {
        di as error "no; dataset in memory has changed since last saved"
        di as error "    convertanything replaces the data in memory; specify {bf:clear}"
        exit 4
    }

    local home : environment HOME
    if `"`macval(home)'"' == "" & c(os) == "Windows" {
        local home : environment USERPROFILE
    }
    local encgiven = `"`macval(encoding)'"' != ""
    if !`encgiven' local encoding "utf-8"
    local skipgiven = `"`macval(skip)'"' != ""

    local here `"`c(pwd)'"'
    mata: _ca_init()

    * skip(): a single quoted string is split into names (v1.2 behavior);
    * quote names that contain spaces: skip("my folder" _archive)
    if `skipgiven' {
        local s `"`macval(skip)'"'
        gettoken t r : s, qed(q)
        if `q' & `"`macval(r)'"' == "" local s `"`macval(t)'"'
        while `"`macval(s)'"' != "" {
            gettoken t s : s
            mata: _ca_addskip(st_local("t"))
        }
    }
    else {
        mata: _ca_addskip("_converted"); _ca_addskip("_archive")
    }

    capture noisily _ca_run
    local rc = _rc

    if `"`c(pwd)'"' != `"`macval(here)'"' {
        quietly cd `"`macval(here)'"'
    }
    mata: _ca_results()
    mata: _ca_cleanup()

    return scalar N_files     = `N_files'
    return scalar N_converted = `N_conv'
    return scalar N_saved     = `N_saved'
    return scalar N_skipped   = `N_skip'
    return scalar N_failed    = `N_fail'
    return scalar N_inplace   = `N_inpl'
    return local saved   `"`macval(saved)'"'
    return local skipped `"`macval(skipped)'"'
    return local failed  `"`macval(failed)'"'

    if `rc' exit `rc'
    * single-file mode: a file that was not converted is an error
    if "`mode'" == "file" & `N_conv' == 0 & `filerc' != 0 exit `filerc'
end


* ---------------------------------------------------------------------------
* _ca_run: resolve paths, list the files, plan output names, convert
* ---------------------------------------------------------------------------
program define _ca_run
    version 16
    mata: _ca_getopts()
    mata: _ca_paths()
    if !`isdir' & !`isfile' {
        di as error `"convertanything: path not found: `macval(input)'"'
        exit 601
    }
    mata: _ca_exts()
    if `"`badext'"' != "" {
        di as error `"convertanything: extension() has unsupported type(s): `badext'"'
        di as error "    supported: csv txt tab xls xlsx dta raw"
        exit 198
    }
    if `isfile' & `"`macval(extension)'"' != "" {
        di as text "note: extension() applies to folders and is ignored for a single file"
    }
    if `"`macval(saving)'"' != "" {
        mata: st_local("ok", strofreal(_ca_mkdirp(st_local("saving"))))
        if !`ok' {
            di as error `"convertanything: cannot create output folder `macval(saving)'"'
            exit 693
        }
    }
    mata: _ca_collect()
    mata: _ca_plan()

    forvalues i = 1/`nfiles' {
        capture noisily _ca_file `i'
        if _rc == 1 exit 1
        if _rc {
            local rc = _rc
            mata: _ca_note(`i', "failed", "unexpected error", `rc')
        }
    }
end


* ---------------------------------------------------------------------------
* _ca_file: convert source file number i
* ---------------------------------------------------------------------------
program define _ca_file
    version 16
    args i
    mata: _ca_getopts()
    mata: _ca_getfile(`i')
    mata: _ca_setsheet("", "")
    if "`verbose'" != "" {
        mata: _ca_say(`i')
    }
    if "`inplace'" == "1" {
        mata: _ca_note(`i', "skipped", "already a .dta in the output folder", 0)
        exit
    }
    if !inlist("`ext'", "csv", "txt", "tab", "xls", "xlsx", "dta", "raw") {
        mata: _ca_note(`i', "failed", "unsupported file type (supported: csv txt tab xls xlsx dta raw)", 198)
        exit
    }
    if inlist("`ext'", "xls", "xlsx") & "`allsheets'" != "" {
        _ca_sheets `i'
        exit
    }

    _ca_target `i'
    if "`act'" == "exists" {
        mata: _ca_note(`i', "skipped", "output exists; specify replace to overwrite", 602)
        exit
    }
    * import commands are ado-files that would expand a backquote or double
    * quote in the file name; read such files from a temporary copy
    local isrc `"`macval(src)'"'
    mata: st_local("risky", strofreal(strpos(st_local("src"), char(96)) > 0 | strpos(st_local("src"), char(34)) > 0))
    local tmpcopy 0
    if `risky' & "`ext'" != "dta" & "`ext'" != "raw" {
        tempfile tcopy
        local isrc "`tcopy'.`ext'"
        local tmpcopy 1
        capture copy `"`macval(src)'"' `"`isrc'"', replace
        if _rc {
            local rc = _rc
            mata: _ca_note(`i', "failed", "cannot make a temporary copy", `rc')
            exit
        }
    }

    local rc 0
    local why "import failed"
    if inlist("`ext'", "csv", "txt", "tab") {
        mata: _ca_set("isrc", st_local("isrc"))
        _ca_text `i'
    }
    else if inlist("`ext'", "xls", "xlsx") {
        local fr = cond("`nofirstrow'" != "", "", "firstrow")
        capture import excel using `"`macval(isrc)'"', `fr' clear
        local rc = _rc
    }
    else if "`ext'" == "dta" {
        capture use `"`macval(src)'"', clear
        local rc = _rc
        local why "cannot read .dta"
    }
    else if "`ext'" == "raw" {
        _ca_raw `i'
    }
    if `tmpcopy' {
        capture erase `"`isrc'"'
    }
    if `rc' {
        mata: _ca_note(`i', "failed", st_local("why"), `rc')
        exit
    }
    if c(k) == 0 {
        mata: _ca_note(`i', "failed", "no variables imported", 2000)
        exit
    }
    _ca_save `i'
end


* ---------------------------------------------------------------------------
* _ca_text: csv, txt and tab files.  Before importing, the file is scanned
* (Mata, _ca_textsniff) for three things:
*   - bytes that are not valid UTF-8 (encoding),
*   - whether the first row looks like data rather than variable names,
*   - fields that start with a zero followed by a digit (codes such as 01, 00123).
* Sets rc in the caller (_ca_file).
* ---------------------------------------------------------------------------
program define _ca_text
    version 16
    args i
    mata: _ca_getopts()
    mata: _ca_textsniff(`i')

    * --- encoding ----------------------------------------------------------
    local enc `"`macval(encoding)'"'
    if `ninvalid' {
        local isutf = inlist(lower(`"`macval(enc)'"'), "utf-8", "utf8")
        if !`encgiven' & !`hasmb' {
            local enc = cond(`hasc1', "windows-1252", "latin1")
            mata: _ca_say_note(`i', "the file is not valid UTF-8 (`ninvalid' invalid byte sequence(s)`scanpart') and has no UTF-8 accented characters, so it was read as encoding(`enc') to keep characters such as {c n~}; if the text looks wrong, rerun with the right encoding(), for example encoding(latin1) or encoding(windows-1252)")
        }
        else if `isutf' & !`encgiven' {
            mata: _ca_say_note(`i', "WARNING: the file mixes UTF-8 and other bytes (`ninvalid' invalid UTF-8 byte sequence(s)`scanpart'); it was read as UTF-8 and those bytes are DROPPED (Pe{c n~}itas becomes Peitas); if the file is latin1 or Windows text, rerun with encoding(latin1) or encoding(windows-1252)")
        }
        else if `isutf' {
            mata: _ca_say_note(`i', "WARNING: encoding(`enc') was given but the file has `ninvalid' invalid UTF-8 byte sequence(s)`scanpart'; those bytes are DROPPED; if the file is latin1 or Windows text, use encoding(latin1) or encoding(windows-1252)")
        }
    }
    mata: _ca_set("isenc", st_local("enc"))

    * --- header ------------------------------------------------------------
    if "`nofirstrow'" != "" local vn "varnames(nonames)"
    else if "`firstrow'" != "" local vn "varnames(1)"
    else if "`hdr'" == "data" {
        local vn "varnames(nonames)"
        mata: _ca_say_note(`i', "every field of the first row is a number (" + st_local("hdrshow") + "), so the file was read as having no header row: variables are v1, v2, ...; if the first row holds variable names, specify firstrow")
    }
    else if "`hdr'" == "unsure" | "`hdr'" == "mixed" {
        local vn "varnames(1)"
        mata: _ca_say_note(`i', "the first row was used as variable names, but " + st_local("hdrwhy") + " (" + st_local("hdrshow") + "); if the first row is data, specify nofirstrow (or firstrow to keep it as names and silence this note)")
    }
    else local vn "varnames(1)"

    * --- import, protecting zero-padded codes ---------------------------------
    if "`destring'" != "" {
        _ca_delim `i' "`vn'" "stringcols(_all)"
    }
    else if `codecand' {
        * read every column as text, find code columns, read again with
        * only those columns as text
        _ca_delim `i' "`vn'" "stringcols(_all)" quiet
        if `rc' {
            c_local rc `rc'
            exit
        }
        local idx
        local codes
        local k 0
        foreach v of varlist _all {
            local ++k
            capture confirm string variable `v'
            if _rc continue
            quietly count if ustrregexm(ustrtrim(`v'), "^0[0-9]")
            if !r(N) continue
            quietly count if !inlist(ustrtrim(`v'), "", ".") & missing(real(ustrtrim(`v')))
            if r(N) continue
            local idx `idx' `k'
            local codes `codes' `v'
        }
        if "`idx'" != "" {
            _ca_delim `i' "`vn'" "stringcols(`idx')"
            if !`rc' {
                mata: _ca_say_note(`i', "kept as text because values have leading zeros (codes such as 01 or 00123): `codes'")
            }
        }
        else {
            _ca_delim `i' "`vn'" ""
        }
    }
    else {
        _ca_delim `i' "`vn'" ""
    }
    c_local rc `rc'
    if `rc' exit
end


* ---------------------------------------------------------------------------
* _ca_delim: one import delimited of the current text file (path and encoding
* come from Mata) under the stray-quote rule of _cva_qguard: strict quoting,
* and loose quoting when a cell's later line looks like a data row (WARNING
* note unless quiet).  If the strict read fails outright, the file is read
* again with loose quoting and a note, unless strictquotes was given.
* Sets rc in the caller.
* ---------------------------------------------------------------------------
program define _ca_delim
    version 16
    args i vn sc quiet
    mata: st_local("isrc", _ca_get("isrc")); st_local("enc", _ca_get("isenc"))
    mata: st_local("strictquotes", _ca_get("strictquotes"))
    local qg_status
    capture _cva_qguard `"`macval(isrc)'"', `vn' `sc' ///
        encoding(`"`macval(enc)'"') nowarn `strictquotes'
    local rc = _rc
    if `rc' & "`strictquotes'" == "" {
        local rc1 = `rc'
        capture import delimited using `"`macval(isrc)'"', clear `vn' `sc' ///
            encoding(`"`macval(enc)'"')
        local rc = _rc
        if !`rc' & "`quiet'" == "" {
            mata: _ca_say_note(`i', "strict quote parsing failed (rc=`rc1'), read again with default (loose) quoting")
        }
    }
    else if !`rc' & "`qg_status'" == "stray" & "`quiet'" == "" {
        local km1 = `qg_k' - 1
        local qgmsg `"WARNING: stray-quote check: in the strict read, the quoted cell in row `qg_obs', column `qg_var' runs on into lines that look like data rows (each has at least `km1' delimiter(s)), so an unmatched quote, such as the inch mark in 5" screen, joined rows; strict quote binding read `qg_nstrict' row(s), loose binding read `qg_nloose' row(s); the loose result is used.  If those lines are text inside one quoted field, specify strictquotes"'
        mata: _ca_say_note(`i', st_local("qgmsg"))
    }
    c_local rc `rc'
end


* ---------------------------------------------------------------------------
* _ca_sheets: allsheets mode; one .dta per worksheet
* ---------------------------------------------------------------------------
program define _ca_sheets
    version 16
    args i
    mata: _ca_getopts()
    mata: _ca_getfile(`i')
    * import commands are ado-files that would expand a backquote or double
    * quote in the file name; read such files from a temporary copy
    local isrc `"`macval(src)'"'
    mata: st_local("risky", strofreal(strpos(st_local("src"), char(96)) > 0 | strpos(st_local("src"), char(34)) > 0))
    local tmpcopy 0
    if `risky' & "`ext'" != "dta" & "`ext'" != "raw" {
        tempfile tcopy
        local isrc "`tcopy'.`ext'"
        local tmpcopy 1
        capture copy `"`macval(src)'"' `"`isrc'"', replace
        if _rc {
            local rc = _rc
            mata: _ca_note(`i', "failed", "cannot make a temporary copy", `rc')
            exit
        }
    }
    capture import excel using `"`macval(isrc)'"', describe
    if _rc {
        local rc = _rc
        if `tmpcopy' {
            capture erase `"`isrc'"'
        }
        mata: _ca_note(`i', "failed", "cannot read workbook", `rc')
        exit
    }
    mata: _ca_sheetlist()
    if `ns' == 0 {
        if `tmpcopy' {
            capture erase `"`isrc'"'
        }
        mata: _ca_note(`i', "failed", "workbook has no worksheets", 2000)
        exit
    }
    local fr = cond("`nofirstrow'" != "", "", "firstrow")
    forvalues j = 1/`ns' {
        mata: _ca_picksheet(`j')
        if "`verbose'" != "" {
            mata: _ca_say_sheet()
        }
        _ca_target `i'
        if "`act'" == "exists" {
            mata: _ca_note(`i', "skipped", "output exists; specify replace to overwrite", 602)
            continue
        }
        capture import excel using `"`macval(isrc)'"', sheet(`"`macval(sname)'"') `fr' clear
        if _rc {
            local rc = _rc
            mata: _ca_note(`i', "failed", "cannot import worksheet", `rc')
            continue
        }
        if c(k) == 0 {
            mata: _ca_note(`i', "skipped", "worksheet is empty", 0)
            continue
        }
        _ca_save `i'
    }
    if `tmpcopy' {
        capture erase `"`isrc'"'
    }
end


* ---------------------------------------------------------------------------
* _ca_raw: .raw files.  A file that starts with "dictionary" (or "infile
* dictionary") is read with infile using; a rectangular whitespace-delimited
* file is read free-format with one variable per column.
* ---------------------------------------------------------------------------
program define _ca_raw
    version 16
    args i
    mata: _ca_getfile(`i')
    mata: _ca_rawsniff(`i')
    if "`rawmode'" == "dict" {
        capture infile using `"`macval(src)'"', clear
        c_local rc = _rc
        c_local why "infile with the file's dictionary failed"
    }
    else if "`rawmode'" == "free" {
        capture infile `rawvars' using `"`macval(src)'"', clear
        c_local rc = _rc
        c_local why "free-format infile failed"
    }
    else {
        c_local rc 610
        c_local why "`rawwhy'"
    }
end


* ---------------------------------------------------------------------------
* _ca_target: choose the output file for source i (and current sheet).
* Sets act = write | exists in the caller.
* A .dta in the source folder that convertanything did not write from this
* source is never overwritten; another name is used instead.
* ---------------------------------------------------------------------------
program define _ca_target
    version 16
    args i
    mata: _ca_getopts()
    mata: _ca_set("blocked", ""); _ca_set("blockwhy", "")
    local k 0
    while 1 {
        mata: _ca_candidate(`i', `k')
        if !`exists' {
            c_local act "write"
            mata: _ca_redirnote(`i', 1)
            exit
        }
        if `region' {
            capture use in 1 using `"`macval(tgt)'"', clear
            if _rc {
                capture use `"`macval(tgt)'"', clear
            }
            local own 0
            local readok = !_rc
            if `readok' {
                mata: st_local("own", strofreal(_ca_isown(`i')))
            }
            if !`own' {
                mata: _ca_block(`i', `readok')
                local ++k
                continue
            }
        }
        if "`replace'" != "" c_local act "write"
        else c_local act "exists"
        mata: _ca_redirnote(`i', "`replace'" != "")
        exit
    }
end


* ---------------------------------------------------------------------------
* _ca_save: post-process, tag, and save the data in memory for source i
* ---------------------------------------------------------------------------
program define _ca_save
    version 16
    args i
    capture noisily _ca_post `i'
    if _rc {
        local rc = _rc
        mata: _ca_note(`i', "failed", "post-processing failed", `rc')
        exit
    }
    mata: _ca_tag(`i')
    mata: st_local("tgt", _ca_curtgt())
    mata: st_local("ok", strofreal(_ca_mkdirp(_ca_outdir(`i'))))
    if !`ok' {
        mata: _ca_note(`i', "failed", "cannot create output folder", 693)
        exit
    }
    capture save `"`macval(tgt)'"', replace
    if _rc {
        local rc = _rc
        mata: _ca_note(`i', "failed", "save failed", `rc')
        exit
    }
    mata: _ca_note(`i', "saved", "", 0)
end


* ---------------------------------------------------------------------------
* _ca_post: cleannames / destring / compress
* ---------------------------------------------------------------------------
program define _ca_post
    version 16
    args i
    mata: _ca_getopts()
    if c(k) == 0 exit

    if "`cleannames'" != "" {
        foreach v of varlist _all {
            local nv = ustrtoname(ustrlower("`v'"))
            if "`nv'" == "`v'" continue
            capture confirm new variable `nv'
            if _rc {
                local base `nv'
                local k 2
                while 1 {
                    local nv = usubstr("`base'", 1, 32 - ustrlen("_`k'")) + "_`k'"
                    capture confirm new variable `nv'
                    if !_rc continue, break
                    local ++k
                }
                di as text "  note: cleannames: `v' -> `nv' (`base' is already taken)"
            }
            rename `v' `nv'
        }
    }

    if "`destring'" != "" {
        local d = char(36)
        local thou "^[-+]?[`d']?[-+]?[0-9]{1,3}(,[0-9]{3})+([.][0-9]*)?%?`d'"
        local pct "%`d'"
        local conv
        local idlike
        local mixed
        foreach v of varlist _all {
            capture confirm string variable `v'
            if _rc continue
            quietly count if ustrregexm(ustrtrim(`v'), "^0[0-9]")
            local isid = r(N) > 0
            if !`isid' {
                quietly count if ustrlen(ustrregexra(`v', "[^0-9]", "")) > 15
                local isid = r(N) > 0
            }
            if `isid' {
                local idlike `idlike' `v'
                continue
            }
            quietly count if strpos(`v', ",") & !ustrregexm(ustrtrim(`v'), "`thou'")
            if r(N) {
                local mixed `mixed' `v'
                continue
            }
            local popt
            quietly count if strpos(`v', "%")
            if r(N) {
                quietly count if ustrtrim(`v') != "" & !ustrregexm(ustrtrim(`v'), "`pct'")
                if r(N) {
                    local mixed `mixed' `v'
                    continue
                }
                local popt percent
            }
            capture quietly destring `v', replace ignore("`d',") `popt'
            capture confirm numeric variable `v'
            if !_rc local conv `conv' `v'
        }
        if "`conv'" != "" {
            di as text "  destring: converted `: word count `conv'' variable(s): `conv'"
        }
        if "`idlike'" != "" {
            di as text "  destring: kept as text (ID-like: leading zero or more than 15 digits): `idlike'"
        }
        if "`mixed'" != "" {
            di as text "  destring: kept as text (commas that are not thousands separators, or % on only some values): `mixed'"
        }
    }

    if "`compress'" != "" quietly compress
end


* ===========================================================================
* Mata: file lists, naming, status records.  All paths stay in Mata or reach
* Stata through st_local() and macval(), so $ and backquotes in file, folder
* and sheet names are never expanded.
* ===========================================================================
version 16
mata:
mata set matastrict on

// columns of __ca_S
// 1 src  2 name  3 base  4 ext  5 srcdir  6 rel  7 outdir  8 stem  9 inplace

void _ca_init()
{
    external transmorphic matrix __ca_opt, __ca_used, __ca_resv, __ca_srcset, __ca_stubs
    external string matrix __ca_S, __ca_res, __ca_skip, __ca_cur, __ca_sheets
    string rowvector keys
    real scalar k

    __ca_opt = asarray_create()
    keys = ("using", "saving", "home", "extension", "encoding", "recursive",
            "allsheets", "replace", "verbose", "compress", "cleannames",
            "destring", "nofirstrow", "firstrow", "skipgiven", "encgiven",
            "strictquotes")
    for (k = 1; k <= cols(keys); k++) asarray(__ca_opt, keys[k], st_local(keys[k]))
    asarray(__ca_opt, "input", "")
    asarray(__ca_opt, "savabs", "")
    asarray(__ca_opt, "exts", "")
    asarray(__ca_opt, "mode", "")
    asarray(__ca_opt, "listed", "")
    asarray(__ca_opt, "isrc", "")
    asarray(__ca_opt, "blocked", "")
    asarray(__ca_opt, "blockwhy", "")
    __ca_S      = J(0, 9, "")
    __ca_res    = J(0, 6, "")
    __ca_skip   = J(1, 0, "")
    __ca_cur    = ("", "", "")
    __ca_sheets = J(0, 1, "")
    __ca_used   = asarray_create()
    __ca_resv   = asarray_create()
    __ca_srcset = asarray_create()
    __ca_stubs  = asarray_create()
}

void _ca_cleanup()
{
    string rowvector nm
    real scalar k
    nm = ("__ca_opt", "__ca_used", "__ca_resv", "__ca_srcset", "__ca_stubs",
          "__ca_S", "__ca_res", "__ca_skip", "__ca_cur", "__ca_sheets")
    for (k = 1; k <= cols(nm); k++) rmexternal(nm[k])
}

string scalar _ca_get(string scalar key)
{
    external transmorphic matrix __ca_opt
    return(asarray(__ca_opt, key))
}

void _ca_set(string scalar key, string scalar val)
{
    external transmorphic matrix __ca_opt
    asarray(__ca_opt, key, val)
}

void _ca_getopts()
{
    external transmorphic matrix __ca_opt
    string colvector keys
    real scalar k
    keys = asarray_keys(__ca_opt)
    for (k = 1; k <= rows(keys); k++) st_local(keys[k], asarray(__ca_opt, keys[k]))
}

void _ca_addskip(string scalar s)
{
    external string matrix __ca_skip
    if (s != "") __ca_skip = (__ca_skip, ustrlower(s))
}

// strip trailing "/" but keep "/" and "X:/"
string scalar _ca_trim(string scalar p)
{
    while (strlen(p) > 1 & substr(p, -1, 1) == "/") {
        if (strlen(p) == 3 & substr(p, 2, 1) == ":") break
        p = substr(p, 1, strlen(p) - 1)
    }
    return(p)
}

string scalar _ca_norm(string scalar p, string scalar home, real scalar iswin)
{
    string scalar h
    if (p == "") return("")
    if (iswin) p = subinstr(p, char(92), "/")
    if ((p == "~" | substr(p, 1, 2) == "~/") & home != "") {
        h = home
        if (iswin) h = subinstr(h, char(92), "/")
        h = _ca_trim(h)
        p = h + substr(p, 2, .)
    }
    return(_ca_trim(p))
}

string scalar _ca_join(string scalar d, string scalar f)
{
    if (d == "") return(f)
    if (substr(d, -1, 1) == "/") return(d + f)
    return(d + "/" + f)
}

string scalar _ca_canondir(string scalar d)
{
    string scalar here, r
    here = pwd()
    if (_chdir(d)) return("")
    r = pwd()
    (void) _chdir(here)
    if (c("os") == "Windows") r = subinstr(r, char(92), "/")
    return(_ca_trim(r))
}

real scalar _ca_mkdirp(string scalar d)
{
    real scalar j
    string scalar cur
    if (d == "") return(0)
    if (direxists(d)) return(1)
    for (j = 2; j <= strlen(d); j++) {
        if (substr(d, j, 1) == "/") {
            cur = substr(d, 1, j - 1)
            if (cur != "" & !direxists(cur)) (void) _mkdir(cur)
        }
    }
    if (!direxists(d)) (void) _mkdir(d)
    return(direxists(d))
}

void _ca_paths()
{
    real scalar iswin
    string scalar home, inp, sav
    iswin = (c("os") == "Windows")
    home  = _ca_get("home")
    inp   = _ca_norm(_ca_get("using"), home, iswin)
    if (inp == "" & _ca_get("recursive") != "") inp = "."
    sav   = _ca_norm(_ca_get("saving"), home, iswin)
    _ca_set("input", inp)
    _ca_set("saving", sav)
    st_local("input", inp)
    st_local("saving", sav)
    st_local("isdir",  strofreal(inp != "" & direxists(inp)))
    st_local("isfile", strofreal(inp != "" & !direxists(inp) & fileexists(inp)))
    _ca_set("mode", (direxists(inp) ? "dir" : "file"))
}

void _ca_exts()
{
    string scalar s, t, ok, bad
    string rowvector tok, supp
    real scalar k
    supp = ("csv", "txt", "tab", "xls", "xlsx", "dta", "raw")
    s = _ca_get("extension")
    s = subinstr(s, char(34), " ")
    s = subinstr(s, char(96), " ")
    s = subinstr(s, char(39), " ")
    s = subinstr(s, ",", " ")
    tok = tokens(s)
    ok = ""
    bad = ""
    for (k = 1; k <= cols(tok); k++) {
        t = strlower(tok[k])
        while (substr(t, 1, 1) == ".") t = substr(t, 2, .)
        if (t == "") continue
        if (!anyof(supp, t)) bad = bad + " " + t
        else if (!anyof(tokens(ok), t)) ok = ok + " " + t
    }
    if (strtrim(ok) == "") ok = invtokens(supp)
    _ca_set("exts", strtrim(ok))
    st_local("exts", strtrim(ok))
    st_local("badext", strtrim(bad))
}

void _ca_addfile(string scalar dir, string scalar name, string scalar rel)
{
    external string matrix __ca_S
    real scalar dot
    string scalar base, ext
    dot = strrpos(name, ".")
    if (dot > 1) {
        base = substr(name, 1, dot - 1)
        ext  = strlower(substr(name, dot + 1, .))
    }
    else {
        base = name
        ext  = ""
    }
    __ca_S = __ca_S \ (_ca_join(dir, name), name, base, ext, dir, rel, "", "", "0")
}

void _ca_collect()
{
    external string matrix __ca_S, __ca_skip
    string scalar inp, root, par, name, d, rel, sub, sabs, savabs, why, ext
    string colvector files, subs
    string rowvector exts
    string matrix Q
    real scalar sl, j, depth, njunk, verbose, rec
    string scalar dol

    dol     = char(36)
    inp     = _ca_get("input")
    verbose = (_ca_get("verbose") != "")
    rec     = (_ca_get("recursive") != "")
    exts    = tokens(_ca_get("exts"))
    njunk   = 0

    savabs = ""
    if (_ca_get("saving") != "") savabs = _ca_canondir(_ca_get("saving"))
    if (savabs == "" & _ca_get("saving") != "") savabs = _ca_get("saving")
    _ca_set("savabs", savabs)

    if (!direxists(inp)) {
        // single file
        sl = strrpos(inp, "/")
        if (sl == 0)      par = "."
        else if (sl == 1) par = "/"
        else              par = substr(inp, 1, sl - 1)
        if (strlen(par) == 2 & substr(par, 2, 1) == ":") par = par + "/"
        name = substr(inp, sl + 1, .)
        d = _ca_canondir(par)
        if (d == "") d = par
        _ca_addfile(d, name, "")
        _ca_set("listed", "1")
        st_local("nfiles", strofreal(rows(__ca_S)))
        return
    }

    root = _ca_canondir(inp)
    if (root == "") root = inp
    Q = (root, "", "0")
    while (rows(Q) > 0) {
        d     = Q[1, 1]
        rel   = Q[1, 2]
        depth = strtoreal(Q[1, 3])
        Q = (rows(Q) > 1 ? Q[|2, 1 \ rows(Q), 3|] : J(0, 3, ""))

        files = dir(d, "files", "*")
        if (rows(files)) files = sort(files, 1)
        for (j = 1; j <= rows(files); j++) {
            name = files[j]
            if (strrpos(name, ".") < 2) continue
            ext = strlower(substr(name, strrpos(name, ".") + 1, .))
            // AppleDouble files, and Excel lock files (~$book.xlsx); other
            // names that start with ~$ are ordinary files
            if (substr(name, 1, 2) == "._" |
                (substr(name, 1, 2) == "~" + dol & anyof(("xls", "xlsx", "xlsm"), ext))) {
                njunk++
                continue
            }
            if (!anyof(exts, ext)) continue
            _ca_addfile(d, name, rel)
        }

        if (!rec) continue
        subs = dir(d, "dirs", "*")
        if (rows(subs)) subs = sort(subs, 1)
        for (j = 1; j <= rows(subs); j++) {
            sub = subs[j]
            if (sub == "." | sub == "..") continue
            why = ""
            sabs = _ca_canondir(_ca_join(d, sub))
            if (anyof(__ca_skip, ustrlower(sub))) why = "in skip()"
            else if (sabs == "") why = "cannot open folder"
            else if (savabs != "" &
                     strpos(ustrlower(sabs) + "/", ustrlower(savabs) + "/") == 1) why = "output folder"
            else if (depth >= 100) why = "more than 100 levels deep"
            if (why != "") {
                if (verbose | why == "more than 100 levels deep" | why == "cannot open folder") {
                    printf("{txt}  skipping folder %s (%s)\n", _ca_join(d, sub), why)
                }
                continue
            }
            Q = Q \ (sabs, (rel == "" ? sub : rel + "/" + sub), strofreal(depth + 1))
        }
    }
    _ca_set("listed", "1")
    if (verbose & njunk) printf("{txt}  ignored %g system file(s): ._* (AppleDouble) and ~%s*.xls/.xlsx/.xlsm (Excel lock files)\n", njunk, dol)
    st_local("nfiles", strofreal(rows(__ca_S)))
}

void _ca_plan()
{
    external string matrix __ca_S
    external transmorphic matrix __ca_resv, __ca_srcset
    transmorphic matrix cnt, dcnt
    real scalar i, n, w, allsh, k
    string scalar savabs, outdir, key, stem, full
    real colvector writer

    n      = rows(__ca_S)
    savabs = _ca_get("savabs")
    allsh  = (_ca_get("allsheets") != "")
    writer = J(n, 1, 0)
    cnt    = asarray_create()
    dcnt   = asarray_create()
    asarray_notfound(cnt, 0)
    asarray_notfound(dcnt, 0)

    for (i = 1; i <= n; i++) {
        if (savabs != "") outdir = (__ca_S[i, 6] == "" ? savabs : _ca_join(savabs, __ca_S[i, 6]))
        else              outdir = __ca_S[i, 5]
        __ca_S[i, 7] = outdir
        __ca_S[i, 9] = ((__ca_S[i, 4] == "dta" & ustrlower(outdir) == ustrlower(__ca_S[i, 5])) ? "1" : "0")
        asarray(__ca_srcset, ustrlower(_ca_join(__ca_S[i, 5], __ca_S[i, 2])), i)
        w = (__ca_S[i, 9] == "0")
        if (allsh & (__ca_S[i, 4] == "xls" | __ca_S[i, 4] == "xlsx")) w = 0
        writer[i] = w
        if (w) {
            key = ustrlower(_ca_join(outdir, __ca_S[i, 3]))
            asarray(cnt, key, asarray(cnt, key) + 1)
            if (__ca_S[i, 4] == "dta") asarray(dcnt, key, asarray(dcnt, key) + 1)
        }
    }
    for (i = 1; i <= n; i++) {
        if (!writer[i]) {
            __ca_S[i, 8] = __ca_S[i, 3]
            continue
        }
        key  = ustrlower(_ca_join(__ca_S[i, 7], __ca_S[i, 3]))
        stem = __ca_S[i, 3]
        if (asarray(cnt, key) > 1) {
            if (!(asarray(dcnt, key) == 1 & __ca_S[i, 4] == "dta")) stem = stem + "_" + __ca_S[i, 4]
        }
        full = stem
        k = 1
        while (asarray_contains(__ca_resv, ustrlower(_ca_join(__ca_S[i, 7], full + ".dta")))) {
            k++
            full = stem + "_" + strofreal(k)
        }
        __ca_S[i, 8] = full
        asarray(__ca_resv, ustrlower(_ca_join(__ca_S[i, 7], full + ".dta")), i)
    }
}

void _ca_getfile(real scalar i)
{
    external string matrix __ca_S
    st_local("src",     __ca_S[i, 1])
    st_local("name",    __ca_S[i, 2])
    st_local("base",    __ca_S[i, 3])
    st_local("ext",     __ca_S[i, 4])
    st_local("inplace", __ca_S[i, 9])
}

string scalar _ca_outdir(real scalar i)
{
    external string matrix __ca_S
    return(__ca_S[i, 7])
}

void _ca_setsheet(string scalar stub, string scalar sheet)
{
    external string matrix __ca_cur
    __ca_cur[2] = stub
    __ca_cur[3] = sheet
}

string scalar _ca_curtgt()
{
    external string matrix __ca_cur
    return(__ca_cur[1])
}

void _ca_sheetlist()
{
    external string matrix __ca_sheets
    external transmorphic matrix __ca_stubs
    real scalar ns, j
    ns = st_numscalar("r(N_worksheet)")
    if (ns == . | ns < 0) ns = 0
    __ca_sheets = J(ns, 1, "")
    for (j = 1; j <= ns; j++) __ca_sheets[j] = st_global("r(worksheet_" + strofreal(j) + ")")
    __ca_stubs = asarray_create()
    st_local("ns", strofreal(ns))
}

void _ca_picksheet(real scalar j)
{
    external string matrix __ca_sheets
    external transmorphic matrix __ca_stubs
    string scalar sheet, stub0, stub
    real scalar k
    sheet = __ca_sheets[j]
    stub0 = strtoname(sheet)
    if (stub0 == "") stub0 = "sheet" + strofreal(j)
    stub = stub0
    k = 1
    while (asarray_contains(__ca_stubs, ustrlower(stub))) {
        k++
        stub = stub0 + "_" + strofreal(k)
    }
    asarray(__ca_stubs, ustrlower(stub), 1)
    _ca_setsheet(stub, sheet)
    st_local("sname", sheet)
}

// candidate output file for source i; k = 0 is the planned name, k >= 1 an
// alternative used when the planned file is a .dta that convertanything did
// not write.  Sets locals tgt, exists, region.
void _ca_candidate(real scalar i, real scalar k)
{
    external string matrix __ca_S, __ca_cur
    external transmorphic matrix __ca_used, __ca_resv, __ca_srcset
    string scalar stub, stem, s, full, key, outdir
    real scalar j

    outdir = __ca_S[i, 7]
    stub   = __ca_cur[2]
    if (k == 0) stem = (stub == "" ? __ca_S[i, 8] : __ca_S[i, 3] + "_" + stub)
    else {
        stem = __ca_S[i, 3] + "_" + __ca_S[i, 4] + (stub == "" ? "" : "_" + stub)
        if (k > 1) stem = stem + "_" + strofreal(k)
    }
    j = 1
    while (1) {
        s    = (j == 1 ? stem : stem + "_" + strofreal(j))
        full = _ca_join(outdir, s + ".dta")
        key  = ustrlower(full)
        if (asarray_contains(__ca_used, key)) {
            j++
            continue
        }
        if (asarray_contains(__ca_resv, key)) {
            if (asarray(__ca_resv, key) != i) {
                j++
                continue
            }
        }
        break
    }
    asarray(__ca_used, key, i)
    __ca_cur[1] = full
    st_local("tgt", full)
    st_local("exists", strofreal(fileexists(full)))
    st_local("region", strofreal(ustrlower(outdir) == ustrlower(__ca_S[i, 5]) |
                                 asarray_contains(__ca_srcset, key)))
}

string scalar _ca_tagval(real scalar i)
{
    external string matrix __ca_S, __ca_cur
    return(__ca_S[i, 2] + (__ca_cur[3] == "" & __ca_cur[2] == "" ? "" : "|" + __ca_cur[3]))
}

real scalar _ca_isown(real scalar i)
{
    return(ustrlower(st_global("_dta[convertanything]")) == ustrlower(_ca_tagval(i)))
}

void _ca_tag(real scalar i)
{
    st_global("_dta[convertanything]", _ca_tagval(i))
}

string scalar _ca_label(real scalar i)
{
    external string matrix __ca_S, __ca_cur
    if (__ca_cur[2] == "") return(__ca_S[i, 1])
    return(__ca_S[i, 1] + " [sheet " + __ca_cur[3] + "]")
}

void _ca_say(real scalar i)
{
    external string matrix __ca_S
    printf("{txt}  -> %s\n", __ca_S[i, 1])
}

void _ca_say_sheet()
{
    external string matrix __ca_cur
    printf("{txt}     sheet: %s\n", __ca_cur[3])
}

void _ca_say_note(real scalar i, string scalar msg)
{
    printf("{txt}  note: %s: %s\n", _ca_label(i), msg)
}

// remember the first planned output that may not be overwritten, and why
void _ca_block(real scalar i, real scalar readok)
{
    external string matrix __ca_cur
    string scalar tag, why
    if (_ca_get("blocked") != "") return
    tag = (readok ? st_global("_dta[convertanything]") : "")
    if (!readok) why = "it is not a .dta file Stata can read"
    else if (tag == "") why = "it has no convertanything record, so it is your own file or an output of version 1.2 or earlier"
    else why = "it was written by convertanything from another source (" + tag + ")"
    _ca_set("blocked", __ca_cur[1])
    _ca_set("blockwhy", why)
}

// after the output name is final: explain a name that moved away from the
// planned one (willwrite = 1 when the new name is about to be written)
void _ca_redirnote(real scalar i, real scalar willwrite)
{
    external string matrix __ca_cur
    string scalar b
    b = _ca_get("blocked")
    if (b == "") return
    printf("{txt}  note: %s: %s already exists and %s.  convertanything never overwrites such a file in the source folder, even with replace, so the output %s %s instead.  To get the plain name, move or delete %s and rerun with replace, or use saving() to write to another folder.\n",
           _ca_label(i), b, _ca_get("blockwhy"),
           (willwrite ? "is saved as" : "name is"), __ca_cur[1], b)
    _ca_set("blocked", "")
}

// status record: i, kind, label, target, reason, rc
void _ca_note(real scalar i, string scalar kind, string scalar why, real scalar rc)
{
    external string matrix __ca_res, __ca_cur
    real scalar verbose
    verbose = (_ca_get("verbose") != "")
    __ca_res = __ca_res \ (strofreal(i), kind, _ca_label(i),
                           (kind == "saved" ? __ca_cur[1] : ""), why, strofreal(rc))
    if (kind == "saved") {
        if (verbose) printf("{txt}     saved %s\n", __ca_cur[1])
    }
    else if (kind == "failed") {
        printf("{err}  failed: %s: %s (rc=%g)\n", _ca_label(i), why, rc)
    }
    else if (verbose | why != "already a .dta in the output folder" | _ca_get("mode") == "file") {
        printf("{txt}  skipped: %s: %s\n", _ca_label(i), why)
    }
}

string scalar _ca_q(string scalar s)
{
    return(char(96) + char(34) + s + char(34) + char(39))
}

void _ca_results()
{
    external string matrix __ca_S, __ca_res
    real scalar n, i, r, nsv, nfl, nconv, nskip, nfail, nsaved, filerc, anyskip602, ninpl
    string scalar saved, skipped, failed, mode, dir
    real colvector id

    n = rows(__ca_S)
    id = (rows(__ca_res) ? strtoreal(__ca_res[., 1]) : J(0, 1, .))
    nconv = nskip = nfail = nsaved = 0
    filerc = 0
    anyskip602 = 0
    saved = skipped = failed = ""
    for (r = 1; r <= rows(__ca_res); r++) {
        if (__ca_res[r, 2] == "saved") {
            nsaved++
            saved = saved + " " + _ca_q(__ca_res[r, 4])
        }
    }
    mode = _ca_get("mode")
    ninpl = 0
    for (i = 1; i <= n; i++) {
        if (mode == "dir" & __ca_S[i, 9] == "1") {
            ninpl++
            continue
        }
        nsv = nfl = 0
        for (r = 1; r <= rows(__ca_res); r++) {
            if (id[r] != i) continue
            if (__ca_res[r, 2] == "saved")  nsv++
            if (__ca_res[r, 2] == "failed") {
                nfl++
                if (filerc == 0) filerc = strtoreal(__ca_res[r, 6])
            }
            if (__ca_res[r, 2] == "skipped" & __ca_res[r, 6] == "602") anyskip602 = 1
        }
        if (nsv)      nconv++
        else if (nfl) {
            nfail++
            failed = failed + " " + _ca_q(__ca_S[i, 1])
        }
        else {
            nskip++
            skipped = skipped + " " + _ca_q(__ca_S[i, 1])
        }
    }
    if (filerc == 0 & anyskip602) filerc = 602
    n = n - ninpl

    st_local("N_files", strofreal(n))
    st_local("N_conv",  strofreal(nconv))
    st_local("N_saved", strofreal(nsaved))
    st_local("N_skip",  strofreal(nskip))
    st_local("N_fail",  strofreal(nfail))
    st_local("saved",   strtrim(saved))
    st_local("skipped", strtrim(skipped))
    st_local("failed",  strtrim(failed))
    st_local("mode",    mode)
    st_local("filerc",  strofreal(filerc))
    st_local("N_inpl",  strofreal(ninpl))

    if (_ca_get("listed") != "1") return
    if (n == 0 & ninpl) {
        printf("{txt}convertanything: nothing to convert; %g .dta file%s already in the output folder\n", ninpl, (ninpl == 1 ? "" : "s"))
        return
    }
    if (mode == "dir" & n == 0) {
        dir = _ca_get("input")
        printf("{txt}convertanything: no files with extension(s) %s found in %s\n", _ca_get("exts"), dir)
        return
    }
    if (n == 0) return
    printf("{txt}convertanything: %g file%s: {res}%g{txt} converted (%g dataset%s saved), {res}%g{txt} skipped, %s%g{txt} failed\n",
           n, (n == 1 ? "" : "s"), nconv, nsaved, (nsaved == 1 ? "" : "s"), nskip,
           (nfail ? "{err}" : "{res}"), nfail)
    if (ninpl) printf("{txt}    (%g .dta file%s already in the output folder left as is)\n", ninpl, (ninpl == 1 ? "" : "s"))
}

// ---------------------------------------------------------------------------
// _ca_textsniff: scan a csv/txt/tab file before it is imported.
// Reads the file in 1 MB chunks (at most the first 64 MB) and sets locals
//   ninvalid  invalid UTF-8 byte sequences found
//   hasmb     1 if valid multibyte UTF-8 characters were found
//   hasc1     1 if bytes 0x80-0x9F occur where the text is not UTF-8
//             (printable in windows-1252, control codes in latin1)
//   scanpart  "" or " in the first 64 MB" when the file is larger
//   codecand  1 if some field starts with a zero followed by a digit
//   hdr       text | data | unsure | mixed | none   (first-row verdict)
//   hdrshow   the first few fields of the first row
//   hdrwhy    why the verdict is unsure or mixed
// ---------------------------------------------------------------------------
void _ca_textsniff(real scalar i)
{
    external string matrix __ca_S
    real scalar fh, nread, cap, ninv, hasmb, hasc1, codec, n, p, L, j, chunkno
    string scalar buf, chunk, carry, first, re, q, tab, tail
    real rowvector b

    fh = _fopen(__ca_S[i, 1], "r")
    st_local("ninvalid", "0")
    st_local("hasmb", "0")
    st_local("hasc1", "0")
    st_local("scanpart", "")
    st_local("codecand", "0")
    st_local("hdr", "text")
    st_local("hdrshow", "")
    st_local("hdrwhy", "")
    if (fh < 0) return

    q   = char(34)
    tab = char(9)
    re  = "[," + tab + char(10) + char(13) + ";" + q + "] *0[0-9]"
    cap = 64 * 1048576
    nread = ninv = hasmb = hasc1 = codec = 0
    carry = first = tail = ""
    chunkno = 0
    while (nread < cap) {
        buf = fread(fh, 1048576)
        if (buf == J(0, 0, "")) break
        chunkno++
        nread = nread + strlen(buf)
        chunk = carry + buf
        carry = ""
        // keep an incomplete multibyte sequence at the end for the next chunk
        n = strlen(chunk)
        for (p = n; p >= 1 & p >= n - 3; p--) {
            j = ascii(substr(chunk, p, 1))
            if (j < 128) break
            if (j >= 192) {
                L = (j >= 240 ? 4 : (j >= 224 ? 3 : 2))
                if (n - p + 1 < L) {
                    carry = substr(chunk, p, .)
                    chunk = substr(chunk, 1, p - 1)
                }
                break
            }
        }
        if (chunkno == 1) {
            first = chunk
            if (substr(chunk, 1, 3) == char(239) + char(187) + char(191)) first = substr(chunk, 4, .)
            if (substr(first, 1, 1) == "0" & regexm(substr(first, 1, 2), "^0[0-9]")) codec = 1
        }
        if (!codec) codec = regexm(tail + chunk, re)
        tail = substr(chunk, -3, 3)
        j = ustrinvalidcnt(chunk)
        if (j) {
            ninv = ninv + j
            b = ascii(chunk)
            if (ustrlen(chunk) - j - sum(b :< 128) > 0) hasmb = 1
            if (sum((b :>= 128) :& (b :< 160))) hasc1 = 1
        }
        else if (!hasmb) {
            if (strlen(chunk) != ustrlen(chunk)) hasmb = 1
        }
    }
    if (carry != "") ninv = ninv + ustrinvalidcnt(carry)
    if (nread >= cap & fread(fh, 1) != J(0, 0, "")) st_local("scanpart", " in the first 64 MB")
    fclose(fh)
    st_local("ninvalid", strofreal(ninv))
    st_local("hasmb", strofreal(hasmb))
    st_local("hasc1", strofreal(hasc1))
    st_local("codecand", strofreal(codec))
    _ca_hdrsniff(first, __ca_S[i, 4])
}

// split one line into fields; quotes group, "" inside quotes is a quote
string rowvector _ca_fields(string scalar line, string scalar d)
{
    string rowvector f
    string scalar cur, c, q
    real scalar k, inq, n
    q   = char(34)
    f   = J(1, 0, "")
    cur = ""
    inq = 0
    n   = strlen(line)
    for (k = 1; k <= n; k++) {
        c = substr(line, k, 1)
        if (inq) {
            if (c == q) {
                if (substr(line, k + 1, 1) == q) {
                    cur = cur + q
                    k++
                }
                else inq = 0
            }
            else cur = cur + c
        }
        else if (c == q) inq = 1
        else if (c == d) {
            f = (f, cur)
            cur = ""
        }
        else cur = cur + c
    }
    return((f, cur))
}

// first-row verdict from the first 21 non-empty lines of the file;
// txt is the start of the file (its first chunk, up to 1 MB)
void _ca_hdrsniff(string scalar txt, string scalar ext)
{
    string rowvector f
    string scalar d, line, show, t, tab, nlc
    real scalar k, j, nl, nnum, nemp, ntxt, kk, consistent, pos, e, quoted

    tab = char(9)
    nlc = char(10)
    txt = subinstr(txt, char(13) + nlc, nlc)
    txt = subinstr(txt, char(13), nlc)
    nl = 0
    f = J(1, 0, "")
    consistent = 1
    kk = 0
    quoted = 0
    d = ""
    pos = 1
    k = 0
    while (pos <= strlen(txt) & k < 1000) {
        k++
        e = strpos(substr(txt, pos, .), nlc)
        if (e == 0) {
            // no line end: the last line of the file, or a line cut off at
            // the end of the chunk (then it is not used)
            if (strlen(txt) >= 1048572) break
            line = substr(txt, pos, .)
            pos = strlen(txt) + 1
        }
        else {
            line = substr(txt, pos, e - 1)
            pos = pos + e
        }
        if (strtrim(line) == "") continue
        if (d == "") {
            if (ext == "tab") d = tab
            else if (strpos(line, tab) & !strpos(line, ",")) d = tab
            else if (strpos(line, ",")) d = ","
            else if (strpos(line, tab)) d = tab
            else d = ","
        }
        nl++
        if (nl == 1) {
            f = _ca_fields(line, d)
            kk = cols(f)
            quoted = (strpos(line, char(34)) > 0)
        }
        else if (cols(_ca_fields(line, d)) != kk) consistent = 0
        if (nl >= 21) break
    }
    if (nl == 0) {
        st_local("hdr", "none")
        return
    }
    nnum = nemp = ntxt = 0
    show = ""
    for (j = 1; j <= cols(f); j++) {
        t = strtrim(f[j])
        if (j <= 6) show = show + (j > 1 ? d : "") + t
        if (t == "") nemp++
        else if (strtoreal(t) < . ) nnum++
        else ntxt++
    }
    if (cols(f) > 6) show = show + (d == tab ? " ..." : ",...")
    show = subinstr(show, tab, " ")
    st_local("hdrshow", show)
    if (nnum == 0) {
        st_local("hdr", "text")
        return
    }
    if (ntxt == 0 & nemp == 0 & consistent & !quoted) {
        st_local("hdr", "data")
        return
    }
    if (ntxt == 0) {
        st_local("hdr", "unsure")
        if (nemp) st_local("hdrwhy", "its fields are all numbers or empty")
        else if (quoted) st_local("hdrwhy", "its fields are all numbers, written in quotes")
        else      st_local("hdrwhy", "its fields are all numbers and the rows below have a different number of fields")
        return
    }
    st_local("hdr", "mixed")
    st_local("hdrwhy", strofreal(nnum) + " of its " + strofreal(cols(f)) + " fields " + (nnum == 1 ? "is a number" : "are numbers"))
}

// .raw: dictionary file, or rectangular whitespace-delimited data
void _ca_rawsniff(real scalar i)
{
    external string matrix __ca_S
    real scalar fh, k, j, first, w
    string scalar line, tok, mode, why, vars
    string rowvector t
    real rowvector width, isnum

    fh = _fopen(__ca_S[i, 1], "r")
    if (fh < 0) {
        st_local("rawmode", "bad")
        st_local("rawwhy", "cannot open file")
        return
    }
    first = 1
    mode  = "free"
    why   = ""
    k     = 0
    width = J(1, 0, .)
    isnum = J(1, 0, .)
    while ((line = fget(fh)) != J(0, 0, "")) {
        line = subinstr(line, char(13), "")
        line = subinstr(line, char(9), " ")
        t = tokens(subinstr(line, ",", " "))
        if (cols(t) == 0) continue
        if (first) {
            if (t[1] == "dictionary" | (t[1] == "infile" & cols(t) > 1 & t[2] == "dictionary")) {
                mode = "dict"
                break
            }
            k = cols(t)
            width = J(1, k, 1)
            isnum = J(1, k, 1)
            first = 0
        }
        if (cols(t) != k) {
            mode = "bad"
            why  = "rows have different numbers of values; a .raw file needs a Stata dictionary or a rectangular layout"
            break
        }
        for (j = 1; j <= k; j++) {
            tok = t[j]
            w = strlen(tok)
            if (w > width[j]) width[j] = w
            if (isnum[j]) {
                if (strtoreal(tok) == . & !regexm(tok, "^[.][a-z]?$")) isnum[j] = 0
            }
        }
    }
    fclose(fh)
    if (mode == "free" & first) {
        mode = "bad"
        why  = "file is empty"
    }
    if (mode == "free") {
        vars = ""
        for (j = 1; j <= k; j++) {
            if (width[j] > 2045) {
                mode = "bad"
                why  = "a value is longer than 2045 characters"
                break
            }
            vars = vars + (isnum[j] ? " double" : " str" + strofreal(width[j])) + " v" + strofreal(j)
        }
    }
    st_local("rawmode", mode)
    st_local("rawwhy", why)
    st_local("rawvars", (mode == "free" ? strtrim(vars) : ""))
}

end


* ---------------------------------------------------------------------------
* _cva_qguard: import a delimited file under the stray-quote rule.  The same
* helper, with the same logic, ships in combineall, cxchangelog and
* convertanything (only the _cva_ name prefix differs).
*   1. Import once with bindquote(strict) maxquotedrows(unlimited), so a
*      quoted field that spans lines stays one cell.
*   2. strictquotes: keep the strict result; no check, no fallback.
*   3. Fast path: if no string cell contains a line break, keep the strict
*      result.  The file is read once and nothing is printed.
*   4. Otherwise split each cell that contains a line break at its line
*      breaks.  A line after the first looks like a data row of this file
*      when it holds at least k-1 delimiters (k = number of columns of the
*      strict import).  When k <= 2 that is too weak, so the line must also
*      start with an id-like token (digits, optionally after up to four
*      letters and a _ or -, such as 17, Q12, id_003 or 2024-001) and the
*      file's first column must hold such values.
*      - Some line looks like a data row: an unmatched quote (such as the
*        inch mark in 5" screen) joined rows.  Warn, naming the file, the
*        row and column where the joined cell starts, and the strict and
*        loose row counts, then import again with the default loose binding
*        and keep that result.  This also holds when the file has genuine
*        multi-line fields as well: the stray-quote reading wins.
*      - No line does: the breaks are genuine multi-line text.  Keep the
*        strict result and print nothing.
* Leaves in the caller: qg_status (clean, multiline, stray or forced),
* qg_nread (imports run, 1 or 2), qg_nstrict, qg_nloose, qg_k, qg_obs and
* qg_var.  nowarn suppresses the warning (the caller prints its own).
* ---------------------------------------------------------------------------
program define _cva_qguard
    version 16
    gettoken fname 0 : 0, parse(" ,")
    syntax , [STRICTQuotes NOWARN DELIMiters(string asis) *]
    local dl `delimiters'
    if `"`delimiters'"' != "" local options `"`options' delimiters(`delimiters')"'
    c_local qg_status ""
    c_local qg_nloose ""
    c_local qg_obs ""
    c_local qg_var ""
    quietly import delimited using `"`macval(fname)'"', `options' ///
        bindquote(strict) maxquotedrows(unlimited) clear
    local nstrict = _N
    local k = c(k)
    c_local qg_nread 1
    c_local qg_nstrict `nstrict'
    c_local qg_k `k'
    if "`strictquotes'" != "" {
        c_local qg_status forced
        exit
    }
    mata: _cva_qgscan(st_local("fname"), st_local("dl"))
    if "`qg_ml'" == "0" {
        c_local qg_status clean
        exit
    }
    if "`qg_hit'" == "0" {
        c_local qg_status multiline
        exit
    }
    quietly import delimited using `"`macval(fname)'"', `options' clear
    local nloose = _N
    c_local qg_status stray
    c_local qg_nread 2
    c_local qg_nloose `nloose'
    c_local qg_obs `qg_obs'
    c_local qg_var `qg_var'
    if "`nowarn'" == "" {
        di as err "warning:" as txt `" stray-quote check on file `fname'"'
        di as txt "  In the strict read, the quoted cell in row " as res `qg_obs' ///
            as txt ", column " as res "`qg_var'" as txt " runs on into lines"
        di as txt "  that look like data rows (each has at least " as res `k' - 1 ///
            as txt `" delimiter(s)): an unmatched quote, such as the inch mark in 5" screen, joined rows."'
        di as txt "  strict quote binding read " as res `nstrict' as txt ///
            " row(s); loose binding read " as res `nloose' as txt ///
            " row(s); using the loose result."
        di as txt "  If those lines are text inside one quoted field, " ///
            "specify {bf:strictquotes} to keep strict binding."
    }
end

mata:
// stray-quote rule (see _cva_qguard): sets locals qg_ml (some string cell
// has a line break), qg_hit (some later line looks like a data row), and
// qg_obs/qg_var (the first such cell: lowest row, then leftmost column)
void _cva_qgscan(string scalar fname, string scalar dl)
{
    real scalar k, j, i, r, anchor, bestr, bestj, found
    real vector ix
    string colvector s
    string scalar d

    st_local("qg_ml", "0")
    st_local("qg_hit", "0")
    k = st_nvar()
    bestr = bestj = .
    found = 0
    anchor = 1
    d = ","
    for (j = 1; j <= k; j++) {
        if (!st_isstrvar(j)) continue
        s = st_sdata(., j)
        ix = selectindex((strpos(s, char(10)) :+ strpos(s, char(13))) :> 0)
        if (length(ix) == 0) continue
        if (!found) {
            found = 1
            st_local("qg_ml", "1")
            d = _cva_qgdelim(fname, dl, k)
            if (k <= 2) anchor = _cva_qganchor()
        }
        if (!anchor) return
        for (i = 1; i <= length(ix); i++) {
            r = ix[i]
            if (r >= bestr) break
            if (_cva_qgrowline(s[r], d, k)) {
                bestr = r
                bestj = j
                break
            }
        }
    }
    if (bestr < .) {
        st_local("qg_hit", "1")
        st_local("qg_obs", strofreal(bestr))
        st_local("qg_var", st_varname(bestj))
    }
}

// 1 if a line after the first line of cell c looks like a data row
real scalar _cva_qgrowline(string scalar c, string scalar d, real scalar k)
{
    string scalar t, line
    real scalar p, first

    t = subinstr(c, char(13) + char(10), char(10))
    t = subinstr(t, char(13), char(10))
    first = 1
    while (1) {
        p = strpos(t, char(10))
        if (p) {
            line = substr(t, 1, p - 1)
            t = substr(t, p + 1, .)
        }
        else line = t
        if (!first) {
            if (_cva_qgcount(line, d) >= k - 1) {
                if (k > 2) return(1)
                if (_cva_qgidlike(_cva_qglead(line, d, k))) return(1)
            }
        }
        first = 0
        if (!p) return(0)
    }
    return(0)
}

// the delimiter: delimiters() when given, else the candidate (comma, tab,
// semicolon, pipe) that splits the first line of the file into k fields,
// else the most frequent candidate on that line, else comma
string scalar _cva_qgdelim(string scalar fname, string scalar dl, real scalar k)
{
    real scalar fh, j, n, best, bestn, p
    string scalar buf
    string rowvector cand

    if (dl == char(92) + "t") return(char(9))
    if (dl != "") return(dl)
    cand = (",", char(9), ";", "|")
    fh = _fopen(fname, "r")
    if (fh < 0) return(",")
    buf = fread(fh, 65536)
    fclose(fh)
    if (buf == J(0, 0, "")) return(",")
    if (substr(buf, 1, 3) == char(239) + char(187) + char(191)) buf = substr(buf, 4, .)
    p = strpos(buf, char(10))
    if (p) buf = substr(buf, 1, p - 1)
    p = strpos(buf, char(13))
    if (p) buf = substr(buf, 1, p - 1)
    best = 1
    bestn = 0
    for (j = 1; j <= cols(cand); j++) {
        n = _cva_qgcount(buf, cand[j])
        if (k > 1 & n == k - 1) return(cand[j])
        if (n > bestn) {
            best = j
            bestn = n
        }
    }
    return(cand[best])
}

// number of delimiter characters in s (each character of d counts)
real scalar _cva_qgcount(string scalar s, string scalar d)
{
    real scalar j, n
    n = 0
    for (j = 1; j <= strlen(d); j++) {
        n = n + strlen(s) - strlen(subinstr(s, substr(d, j, 1), ""))
    }
    return(n)
}

// the first field of a line (the whole line when k == 1)
string scalar _cva_qglead(string scalar line, string scalar d, real scalar k)
{
    real scalar j, p, q
    if (k == 1) return(line)
    p = strlen(line) + 1
    for (j = 1; j <= strlen(d); j++) {
        q = strpos(line, substr(d, j, 1))
        if (q & q < p) p = q
    }
    return(substr(line, 1, p - 1))
}

// 1 if s is an id-like token: 17, Q12, id_003, 2024-001 (quotes allowed)
real scalar _cva_qgidlike(string scalar s)
{
    string scalar t
    t = strtrim(s)
    if (strlen(t) >= 2 & substr(t, 1, 1) == char(34) & substr(t, -1, 1) == char(34)) {
        t = substr(t, 2, strlen(t) - 2)
    }
    return(ustrregexm(t, "^[A-Za-z]{0,4}[_-]?[0-9]+([._-][0-9]+)*$"))
}

// 1 if the first column holds id-like values (the file's row pattern,
// needed when k <= 2): any nonmissing number, or any string whose first
// line is id-like
real scalar _cva_qganchor()
{
    real scalar i, p
    string colvector s
    string scalar t
    if (!st_isstrvar(1)) return(missing(st_data(., 1)) < st_nobs())
    s = st_sdata(., 1)
    for (i = 1; i <= rows(s); i++) {
        t = subinstr(s[i], char(13), char(10))
        p = strpos(t, char(10))
        if (p) t = substr(t, 1, p - 1)
        if (_cva_qgidlike(t)) return(1)
    }
    return(0)
}
end
