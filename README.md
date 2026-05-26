# convertanything

**One Stata command to ingest a folder of mixed-format files into clean `.dta`s.**

`convertanything` detects each file's type and calls the right importer for you — no more juggling `import excel`, `import delimited`, `use`, and `infile` by hand. Point it at a single file, a folder, or a whole nested tree, and it returns Stata datasets you can actually work with.

```stata
convertanything using "raw/", recursive saving("converted/") ///
    allsheets cleannames destring compress clear replace
```

That one line walks `raw/`, mirrors the folder tree into `converted/`, exports every Excel worksheet as its own `.dta`, lowercases and Stata-legalizes every variable name, destrings money/percent/comma-formatted columns, and compresses the result.

---

## Why you'd reach for this

- **Stops the format-juggling.** `.xls`, `.xlsx`, `.csv`, `.txt`, `.tab`, `.dta`, `.raw` — all one command.
- **Recursive with tree-mirroring.** `raw/2019/file.xls` → `converted/2019/file.dta`. No flat-dump filename collisions across years/regions/cohorts.
- **Multi-sheet Excel workbooks become one `.dta` per sheet** with `allsheets`. Each saved as `filename_sheetname.dta`.
- **Bulletproof with messy paths.** Spaces in "My Drive", "Shared drives/Data and Research Team", "Program Files (x86)" — all handled via compound-quoting throughout. No silent failures.
- **Skips re-processing.** `_converted/` and `_archive/` are skipped by default in recursive mode (configurable via `skip()`) so the destination won't be re-ingested into itself.
- **Cleaning built in.** `cleannames`, `destring` (with `$,%` and percent handling), and `compress` are toggles, not separate post-passes.

---

## Install

```stata
net install convertanything, from("https://raw.githubusercontent.com/ericabooth/convertanything-stata-public/main/")
```

Or drop `convertanything.ado` and `convertanything.sthlp` anywhere on your Stata `adopath`.

Requires Stata 16+.

---

## Quick examples

**Single file, fully cleaned:**

```stata
convertanything using "mydata.csv", replace clear cleannames destring compress
```

**Whole folder, flat output, CSVs only:**

```stata
convertanything using "C:/Data/Comptroller/", extension(csv) ///
    saving("C:/Stata_Data/") replace clear
```

**Recursive tree-mirroring with verbose progress:**

```stata
convertanything using "Downloads/Raw_Data/", recursive ///
    saving("Downloads/Stata_Data/") ///
    verbose replace clear compress destring
```

**Pass-0 bulk-convert in a data pipeline** (wipe the converted cache, then rebuild it from raw):

```stata
dswipe "${converted}"
convertanything using "${raw}", recursive saving("${converted}") ///
    skip("_converted _archive") allsheets cleannames destring compress clear replace
```

---

## Options at a glance

| Option | What it does |
| --- | --- |
| `saving(dir)` | Destination folder. Omit to save next to each source file. |
| `recursive` | Walk subdirectories; mirror the tree into `saving()`. |
| `skip(namelist)` | Subdir names to skip when recursive. Default: `_converted _archive`. |
| `extension(list)` | Restrict to these extensions, e.g. `extension("csv xlsx")`. |
| `allsheets` | Every Excel worksheet becomes its own `.dta` (`filename_sheetname.dta`). |
| `cleannames` | Lowercase + `strtoname()` every variable. |
| `destring` | `destring _all, replace ignore("$,%") percent`. |
| `compress` | `compress` before saving. |
| `clear` / `replace` | Pass-through to `import` / `save`. |
| `verbose` | Per-file progress lines. |

See `help convertanything` after install for the full reference.

---

## Behavior notes

- **Single-format restriction** with `extension("csv")` is great for partial pipelines (e.g., convert the CSVs today, do the spreadsheets tomorrow).
- **No `saving()`** means converted files land next to their source. Combined with `recursive`, this can pollute your raw tree — use `saving()` for anything serious.
- **`allsheets` on a non-Excel file** is harmless (ignored). Safe to leave on as a default in pipelines that mix formats.
- **The default `skip("_converted _archive")`** assumes a convention where machine-converted output lives under `_converted/` and old vintages under `_archive/`. Override with `skip("")` if you want to traverse everything.

---

## Author

Eric A. Booth · Texas 2036 · [eric.a.booth@gmail.com](mailto:eric.a.booth@gmail.com) · [@ericabooth](https://github.com/ericabooth)

Issues and PRs welcome.
