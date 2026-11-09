# convertanything

**One Stata command to turn a folder of mixed-format files into `.dta` datasets.**

Version 1.3 (9 November 2026).

`convertanything` picks the right importer for each file (`import delimited`, `import excel`, `use`, `infile`) and saves the result as a `.dta`. Point it at a single file, a folder, or a whole nested tree.

```stata
convertanything using "raw", recursive saving("converted") ///
    allsheets cleannames destring compress clear replace
```

That line walks `raw/`, mirrors its folder tree into `converted/`, saves every Excel worksheet as its own `.dta`, makes every variable name lowercase and Stata-legal, converts numeric-looking text to numbers (keeping ID-like codes as text), and compresses the result.

---

## What it does

- **Reads seven types.** `.csv`, `.txt`, `.tab`, `.xls`, `.xlsx`, `.dta`, and `.raw` (a Stata dictionary file, or a rectangle of blank-separated values like `outfile` writes).
- **Mirrors the tree.** With `recursive` and `saving()`, `raw/2019/file.xls` becomes `converted/2019/file.dta`. The `saving()` folder is never walked into, even when it sits inside the source tree.
- **Reports every file.** Each file ends as saved, skipped or failed. Skips and failures always print with a reason, a summary line always prints, and the counts and file lists are returned in `r()`. One bad file never stops a folder run.
- **Keeps outputs distinct.** `survey.csv` and `survey.xlsx` in one folder become `survey_csv.dta` and `survey_xlsx.dta`. Worksheet names that clean to the same name get `_2`, `_3`. A `.dta` in the source folder that `convertanything` did not write is never overwritten, even with `replace`.
- **Reads text safely.** Before a `.csv`, `.txt` or `.tab` file is imported, it is scanned for three silent-loss problems, and each finding prints a note naming the file:
  - **Encoding.** Text is read as UTF-8 by default. A file that is not valid UTF-8 (latin1 or Windows text, where `Peñitas` would become `Peitas`) is read as `latin1` or `windows-1252` instead. A file that mixes encodings, or is read with `encoding(utf-8)` despite invalid bytes, gets a warning that those bytes are dropped. Any `encoding()` you give is used as given.
  - **Header row.** The first row is the header, even when every column is text. If every field of the first row is a number, the file is read as having no header (`v1`, `v2`, ...). Uncertain cases (some numbers and some text, empty or quoted fields, uneven rows) keep the first row as names and say so. `firstrow` forces a header (years as column names); `nofirstrow` forces none.
  - **Code columns.** Columns of zero-padded codes (`00501`, `001`, `01`) stay text instead of becoming 501, 1, 1, even without `destring`.

  Quoted fields may contain line breaks.
- **Handles awkward paths.** Spaces, `$`, and backquotes in file, folder, and sheet names are fine. On Windows, backslash paths work and `saving("C:\out\")` is safe. A leading `~` is expanded from your home folder.
- **Ignores clutter.** Extensions match without regard to case (`FILE.CSV`). macOS `._*` files and Excel lock files (`~$*.xls`, `~$*.xlsx`, `~$*.xlsm`) are ignored; other `~$` files, such as `~$notes.csv`, are converted. `_converted/` and `_archive/` are skipped by default in recursive mode.

---

## Install

```stata
net install convertanything, from("https://raw.githubusercontent.com/ericabooth/convertanything-stata-public/main/") replace force
discard
which convertanything
help convertanything
```

Requires Stata 16 or later.

---

## Quick examples

**Single file, fully cleaned:**

```stata
convertanything using "mydata.csv", replace clear cleannames destring compress
```

**One folder, CSV files only, flat output:**

```stata
convertanything using "C:/Data/Comptroller", extension(csv) ///
    saving("C:/Stata_Data") replace clear
```

**Recursive, with progress lines:**

```stata
convertanything using "Downloads/Raw_Data", recursive ///
    saving("Downloads/Stata_Data") verbose replace clear compress destring
```

**Rerun after new files arrive** (outputs that exist are skipped, so only new files are converted):

```stata
convertanything using "raw", recursive saving("converted") clear
display r(N_converted) " converted, " r(N_skipped) " skipped, " r(N_failed) " failed"
```

**A Windows-encoded CSV without a header row:**

```stata
convertanything using "old export.csv", encoding(windows-1252) nofirstrow replace clear
```

**A CSV whose column names are years** (otherwise a first row of numbers is read as data):

```stata
convertanything using "by_year.csv", firstrow replace clear
```

---

## Options

| Option | What it does |
| --- | --- |
| `saving(folder)` | Destination folder, created with any missing parents. Omit it to save next to each source file. |
| `recursive` | Also convert subfolders; with `saving()`, mirror the tree. Without `using`, starts in the current folder. |
| `skip(names)` | Subfolder names not to enter. Default `_converted _archive`. Matching ignores case. Any `skip()` replaces the default; `skip("")` enters every folder. Quote a name with spaces among others: `skip("my folder" _archive)`. |
| `extension(list)` | Folder mode only: convert only these types, e.g. `extension(csv xlsx)`. `xls` and `xlsx` are separate types. |
| `allsheets` | Every Excel worksheet becomes its own `.dta`, named `file_sheet.dta` (sheet name passed through `strtoname()`). |
| `nofirstrow` | The first row is data, not variable names (Excel and text files). Turns off the header check. |
| `firstrow` | Text files: the first row is variable names even if every field is a number. Turns off the header check. Cannot be combined with `nofirstrow`. |
| `encoding(name)` | Encoding of csv/txt/tab files. Default `utf-8`; without `encoding()`, a file that is not valid UTF-8 is read as `latin1` or `windows-1252` with a note. A given `encoding()` is always used. |
| `cleannames` | Lowercase, Stata-legal, unique variable names. A name that is already clean is kept; the variable that must be renamed gets the suffix. With `id` then `ID`, the later `ID` becomes `id_2`; with `ID` then `id`, the earlier `ID` becomes `id_2`. |
| `destring` | Convert numeric-looking text to numbers, removing `$` and thousands commas. Text with a leading zero (`00123`) or more than 15 digits is kept as text, and so is text with odd commas (`1,5`) or `%` on only some values. Columns where every value ends in `%` are divided by 100. Prints what it converted and what it kept. (Zero-padded code columns of text files stay text even without `destring`.) |
| `compress` | `compress` before saving. |
| `replace` | Overwrite existing outputs. Without it, files whose output exists are skipped. In the source folder, only a `.dta` that `convertanything` wrote from the same source is overwritten. |
| `clear` | Allow replacing changed data in memory (otherwise r(4), as with `use`). |
| `verbose` | One line per file, worksheet, and saved `.dta`. |

## Stored results

| Result | Meaning |
| --- | --- |
| `r(N_files)` | Source files considered (not counting `.dta` files left in place) |
| `r(N_converted)` | Source files with at least one dataset saved |
| `r(N_saved)` | `.dta` files written (worksheets count separately) |
| `r(N_skipped)` | Source files skipped |
| `r(N_failed)` | Source files that could not be converted |
| `r(N_inplace)` | Folder mode: `.dta` files already in their output folder |
| `r(saved)`, `r(skipped)`, `r(failed)` | The files, each in compound quotes |

`r(N_files)` = `r(N_converted)` + `r(N_skipped)` + `r(N_failed)`. A summary line with the same counts always prints.

See `help convertanything` for the full reference, including the naming rules, the text-file checks, the skip rules and return codes.

---

## Behavior notes

- **Without `saving()`**, outputs land next to their sources. With `recursive` this fills the raw tree with `.dta` files, so use `saving()` for anything serious.
- **A `.dta` source without `saving()`** is left as is.
- **Tags and reruns over version 1.2 outputs.** Every output records its source in the characteristic `_dta[convertanything]` (for example `survey.csv`, or `book.xlsx|Sheet 1` with `allsheets`). In the source folder, an existing `.dta` is replaced only if its tag shows it was written from the same source. Outputs written by version 1.2 have no tag and cannot be told apart from your own datasets, so a rerun in place keeps them and saves the new output as `name_ext.dta` beside them, with a note that says why. Later reruns update `name_ext.dta`. To go back to plain names, move or delete the old `name.dta` files and rerun with `replace`, or write to a separate folder with `saving()`, where `replace` overwrites whatever is there. There is no option to overwrite untagged files in the source folder.
- **Folder mode returns 0** when it has finished, even if some files failed; check `r(N_failed)`. For a single file, a file that is not converted is an error.
- **Memory** holds the last dataset read when the command ends.
- **`.raw` files** must start with a Stata dictionary (read with `infile using`) or be a rectangle of values separated by blanks, tabs or commas (read free-format as `v1`, `v2`, ..., numeric where every value is a number). Fixed-column data without a dictionary, ragged rows and empty files are reported as failed (r(610)) with a reason.
- **Large text files** are scanned for encoding and code columns in their first 64 MB; give `encoding()` or `destring` to be safe with bigger files.

---

## Changes from version 1.2

Calls written for 1.2 run unchanged, but results can differ. In short (the help file lists every change):

- Text files are read as UTF-8 (1.2 used latin1 under `version 16`, so UTF-8 accents became mojibake); invalid UTF-8 is detected and read as latin1/windows-1252 or warned about.
- The first row is the header by default; an all-number first row is read as data with a note; `firstrow` and `nofirstrow` are new.
- Zero-padded code columns stay text.
- Same-named sources get suffixed outputs; outputs are tagged; untagged `.dta` files in the source folder (including 1.2 outputs) are never overwritten.
- Existing outputs are skipped without `replace` instead of stopping the batch; every file is reported; counts go to `r()`.
- Changed data in memory without `clear` stop the run with r(4) before anything is written (1.2 silently converted only the first file, or none).
- Only Excel lock files and AppleDouble files are ignored; extensions match regardless of case; `recursive` never enters `saving()`.
- `destring` keeps ID-like text; `cleannames` resolves collisions with suffixes.

---

## Testing

`test_convertanything.do` builds its fixtures in a scratch folder, runs 27 tests, and removes the folder again, using only Stata and Mata (no shell commands). Tests 22 to 27 cover the header check, encoding detection, reruns over 1.2 outputs, code columns, lock files and `cleannames` order. It passes on Stata 16.1 and StataNow 19.5:

```stata
do test_convertanything.do "/path/to/package" "/path/to/scratch"
```

The run passes when the log ends with `ALL TESTS PASSED`.

---

## Author

Eric A. Booth, Sr Researcher, Texas 2036 (eric.a.booth@gmail.com).

Issues and PRs welcome.
