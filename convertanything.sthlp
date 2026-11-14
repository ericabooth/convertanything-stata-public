{smcl}
{* *! version 1.3.1  09nov2026  Author: Eric A. Booth}{...}
{vieweralsosee "[D] import delimited" "help import delimited"}{...}
{vieweralsosee "[D] import excel" "help import excel"}{...}
{vieweralsosee "[D] infile (free format)" "help infile1"}{...}
{vieweralsosee "[D] use" "help use"}{...}
{vieweralsosee "[U] Unicode" "help unicode"}{...}
{viewerjumpto "Syntax" "convertanything##syntax"}{...}
{viewerjumpto "Description" "convertanything##description"}{...}
{viewerjumpto "Options" "convertanything##options"}{...}
{viewerjumpto "Remarks: text files" "convertanything##text"}{...}
{viewerjumpto "Remarks: stray quotes" "convertanything##quotes"}{...}
{viewerjumpto "Remarks: other file types" "convertanything##types"}{...}
{viewerjumpto "Remarks: output names and replace" "convertanything##names"}{...}
{viewerjumpto "Remarks: what is skipped" "convertanything##skiprules"}{...}
{viewerjumpto "Messages and errors" "convertanything##messages"}{...}
{viewerjumpto "Examples" "convertanything##examples"}{...}
{viewerjumpto "Stored results" "convertanything##results"}{...}
{viewerjumpto "Changes from version 1.2" "convertanything##compat"}{...}
{viewerjumpto "Author" "convertanything##author"}{...}
{title:Title}

{phang}
{bf:convertanything} {hline 2} Convert a file, or every file in a folder tree, to Stata .dta datasets


{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmd:convertanything} {cmd:using} {it:path} [{cmd:,} {it:options}]

{p 8 17 2}
{cmd:convertanything} [{cmd:,} {opt recur:sive} {it:options}]

{pstd}
{it:path} is a file or a folder.  Put it in double quotes if it contains spaces.
{cmd:using} is required, except with {opt recursive}, where the default is the
current folder ({cmd:.}).

{synoptset 24 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Where}
{synopt:{opt sav:ing(folder)}}write the .dta files to {it:folder} (created, with any missing parent folders); default is next to each source file{p_end}
{synopt:{opt recur:sive}}also convert files in subfolders; with {opt saving()}, mirror the folder tree{p_end}
{synopt:{opt skip(names)}}subfolder names not to enter with {opt recursive}; default {cmd:_converted _archive}; {cmd:skip("")} enters every folder{p_end}
{synopt:{opt ex:tension(list)}}folder mode: convert only these types, for example {cmd:extension(csv xlsx)}{p_end}

{syntab:Reading}
{synopt:{opt all:sheets}}save every Excel worksheet as its own .dta{p_end}
{synopt:{opt nofirst:row}}the first row is data, not variable names (text and Excel files){p_end}
{synopt:{opt first:row}}text files: the first row is variable names, even if it holds only numbers{p_end}
{synopt:{opt enc:oding(name)}}encoding of csv, txt and tab files; default {cmd:utf-8}, with a check (see {help convertanything##encoding:Encoding}){p_end}
{synopt:{opt strictq:uotes}}text files: skip the stray-quote rule; keep strict quote binding, no fallback (see {help convertanything##quotes:Stray quotes}){p_end}

{syntab:Cleaning}
{synopt:{opt clean:names}}lowercase, Stata-legal, unique variable names{p_end}
{synopt:{opt destr:ing}}convert numeric-looking text to numbers; ID-like text is kept as text{p_end}
{synopt:{opt comp:ress}}compress every dataset before saving{p_end}

{syntab:Control}
{synopt:{opt replace}}overwrite outputs that already exist (never a .dta that {cmd:convertanything} did not write; see {help convertanything##names:Output names}){p_end}
{synopt:{opt clear}}allow the command to replace changed data in memory{p_end}
{synopt:{opt ver:bose}}one line per file and per saved dataset{p_end}
{synoptline}


{marker description}{...}
{title:Description}

{pstd}
{cmd:convertanything} reads each file with the importer that fits its extension
({cmd:import delimited}, {cmd:import excel}, {cmd:use} or {cmd:infile}) and saves
the result as a .dta file.  Given a folder, it converts every supported file in
it, and with {opt recursive} every supported file below it.  The supported
extensions are .csv, .txt, .tab, .xls, .xlsx, .dta and .raw.

{pstd}
The command lists all the files first and then converts them, so the .dta files
it writes are never read back as input in the same run.  Every file ends as
{it:saved}, {it:skipped} or {it:failed}.  Failures and skips are always printed
with a reason, a one-line summary always prints, and the counts and file lists
are stored in {cmd:r()}.  A folder run never stops part way because one file has
a problem.

{pstd}
Before a text file (.csv, .txt, .tab) is imported, the command scans it for three
problems that {cmd:import delimited} would otherwise cause without a word: text
that is not UTF-8, a first row that is data rather than variable names, and
columns of zero-padded codes such as {cmd:01} or {cmd:00123}.  Each finding is
handled as described in {help convertanything##text:Remarks: text files} and is
reported with a note that names the file and says how to override it.

{pstd}
Paths may contain spaces, {cmd:$} and backquotes.  On Windows, backslashes in
{it:path} and {opt saving()} are turned into forward slashes, which Stata accepts
everywhere, including UNC paths ({cmd://server/share}).  A leading {cmd:~} is
replaced by the HOME folder (USERPROFILE on Windows when HOME is not set).

{pstd}
The data in memory are replaced: after the run, memory holds the last dataset
read.  Like {cmd:use}, the command refuses with r(4) when the data in memory
have changed since they were last saved, unless you specify {opt clear}.


{marker options}{...}
{title:Options}

{dlgtab:Where}

{phang}
{opt saving(folder)} writes the .dta files to {it:folder}.  Missing folders are
created level by level.  Without {opt saving()}, each .dta is written next to its
source file.  With {opt recursive}, the source tree is mirrored:
{cmd:src/2019/file.xls} becomes {it:folder}{cmd:/2019/file.dta}.  Without
{opt recursive}, all output goes directly into {it:folder}.  If {it:folder} lies
inside the source tree, {opt recursive} never enters it, whatever its name.

{phang}
{opt recursive} also converts the files in every subfolder, except folders named
in {opt skip()}, the {opt saving()} folder and anything below it, and folders more
than 100 levels deep.  See {help convertanything##skiprules:Remarks: what is skipped}.

{phang}
{opt skip(names)} lists subfolder names that {opt recursive} does not enter.
The default is {cmd:_converted _archive}.  Names match without regard to case,
so {cmd:skip(archive)} also skips {cmd:Archive}.  Any {opt skip()} replaces the
default list rather than adding to it, and {cmd:skip("")} turns skipping off.
For compatibility with version 1.2, a single quoted string is split at spaces:
{cmd:skip("_converted _archive")} names two folders.  To name a folder that
contains a space, quote it among other names, {cmd:skip("my folder" _archive)},
or use compound quotes, {cmd:skip(`""my folder""')}.

{phang}
{opt extension(list)} restricts folder mode to the listed types, for example
{cmd:extension(csv xlsx)}.  Case, a leading dot and quotes do not matter, so
{cmd:extension(.CSV)} and {cmd:extension("csv" "xlsx")} work.  {cmd:xls} and
{cmd:xlsx} are separate types.  An unsupported type is an error (r(198)).  For a
single file, {opt extension()} is ignored with a note.

{dlgtab:Reading}

{phang}
{opt allsheets} saves every worksheet of each .xls and .xlsx file as
{it:file}{cmd:_}{it:sheet}{cmd:.dta}; see {help convertanything##names:Output names}.
Without {opt allsheets}, only the first worksheet is read and saved as
{it:file}{cmd:.dta}.  Empty worksheets are skipped with a message.

{phang}
{opt nofirstrow} says that the first row is data.  Text files are then read with
{cmd:varnames(nonames)} and their variables are named v1, v2, v3, ...; Excel files
are read without {cmd:firstrow} and their variables are named A, B, C, ....
{opt nofirstrow} turns off the header check described under
{help convertanything##header:First row}.

{phang}
{opt firstrow} says that the first row of a text file holds the variable names,
even when every field in it is a number.  Use it for a file whose column names
are years or other numbers ({cmd:2019,2020,2021}); without it such a row is read
as data.  The file is read with {cmd:varnames(1)}; a name that is not a legal
Stata name, such as {cmd:2019}, becomes v1, v2, ... with the original name as
the variable label, as {cmd:import delimited} does.  {opt firstrow} turns off
the header check and its notes.  Excel files are always read with
{cmd:firstrow} unless you give {opt nofirstrow}, so for them this option changes
nothing.  {opt firstrow} and {opt nofirstrow} may not be combined (r(198)).

{phang}
{marker encoding}{...}
{opt encoding(name)} names the encoding of csv, txt and tab files, for example
{cmd:encoding(latin1)} or {cmd:encoding(windows-1252)}.  The default is
{cmd:utf-8} on every Stata version, so the result does not depend on the
version that runs the command.  When you do not give {opt encoding()}, a file
that is not valid UTF-8 is detected and read as latin1 or windows-1252 instead,
with a note; see {help convertanything##encoding2:Encoding}.  When you do give
{opt encoding()}, it is always used as given; if you name {cmd:utf-8} and the
file is not valid UTF-8, a warning says that the invalid bytes are dropped.  See
{help import delimited} for the encoding names Stata accepts.

{dlgtab:Cleaning}

{phang}
{opt cleannames} lowercases every variable name and makes it a legal Stata name
with {help ustrtoname()}.  A variable whose name is already lowercase and legal
keeps it.  When the cleaned name of a variable is already taken, by an earlier or
a later variable, the variable being renamed gets the next free suffix
({cmd:_2}, {cmd:_3}, ...) and a note is printed.  So with variables {cmd:id} then
{cmd:ID}, the later one becomes {cmd:id_2}; with {cmd:ID} then {cmd:id}, the
earlier one becomes {cmd:id_2}, because {cmd:id} already has the clean name and
keeps it.  With {cmd:Name} then {cmd:NAME}, {cmd:Name} becomes {cmd:name} and
{cmd:NAME} becomes {cmd:name_2}.  Note that {cmd:import delimited} already
lowercases the names it reads, so collisions mostly arise in Excel and .dta
sources.

{phang}
{opt destring} converts text variables that hold numbers to numeric, removing
{cmd:$} signs and thousands commas.  To protect codes and identifiers, a text
variable is kept as text if any value starts with a zero followed by a digit
({cmd:00123}) or has more than 15 digits.  A variable is also kept as text if it
has commas that are not thousands separators ({cmd:1,5}), or if only some of its
values end in {cmd:%}.  If every value ends in {cmd:%}, the values are divided by
100 ({cmd:45%} becomes 0.45).  For each file the command lists the variables it
converted and the ones it kept as text.  With {opt destring}, csv, txt and tab
files are read with every column as text first, so that leading zeros survive
until these rules are applied.  Without {opt destring}, zero-padded code columns
of text files are still kept as text; see
{help convertanything##codes:Code columns}.

{phang}
{opt compress} runs {help compress} on every dataset before it is saved.

{dlgtab:Control}

{phang}
{opt replace} lets the command overwrite an output file that already exists.
Without {opt replace}, a file whose output already exists is skipped with the
message "output exists; specify replace to overwrite", and the run goes on, so a
rerun converts only new files.  In a separate {opt saving()} folder,
{opt replace} overwrites existing outputs.  In the source folder, {opt replace}
overwrites only a .dta that {cmd:convertanything} itself wrote from the same
source; any other .dta there, including outputs of version 1.2, is never
overwritten.  See {help convertanything##names:Output names and replace}.

{phang}
{opt clear} allows the command to replace data in memory that have changed since
they were last saved.

{phang}
{opt verbose} prints each source file, each worksheet, each saved .dta, the
skipped folders and the number of ignored system files.  The notes about
encoding, the first row, code columns and output names print with or without
{opt verbose}.


{marker text}{...}
{title:Remarks: text files (.csv, .txt, .tab)}

{pstd}
Text files are read with {cmd:import delimited} using {cmd:bindquote(strict)}
and {cmd:maxquotedrows(unlimited)}, so a quoted field may contain line breaks.
A stray unmatched quote is caught by the rule in
{help convertanything##quotes:Stray quotes}.  If the strict read fails, the file
is read again with the default (loose) quoting and a note names the file
(unless {opt strictquotes} is given, in which case the file fails).  The
delimiter is detected by {cmd:import delimited} as usual (comma or tab).

{pstd}
Before the import, the file is scanned in Mata, without changing it.  The scan
reads the whole file, or its first 64 MB when it is larger, and looks for the
three problems below.  In a larger file, invalid UTF-8 bytes or zero-padded
codes that first occur after 64 MB are not seen; the encoding note then says
"in the first 64 MB", and you can give {opt encoding()} or {opt destring} to be
safe.

{marker encoding2}{...}
{pstd}
{ul:Encoding.}  Stata stores text as UTF-8.  When a file saved in latin1 or
Windows-1252 (common for older exports and for files saved from Excel on
Windows) is read as UTF-8, every accented character is silently dropped:
{cmd:Pe}{c n~}{cmd:itas} becomes {cmd:Peitas}.  The scan counts the byte
sequences that are not valid UTF-8 and checks whether the file also holds valid
UTF-8 accented characters.  Then:

{phang2}
o  The file is valid UTF-8: it is read as UTF-8, with no note.{p_end}

{phang2}
o  {opt encoding()} was not given, the file has invalid bytes and no valid UTF-8
accented characters: it is a single-byte file, and it is read as
{cmd:windows-1252} if it has bytes 0x80 to 0x9F (curly quotes, dashes and the
euro sign in Windows text, unused control codes in latin1) and as {cmd:latin1}
otherwise.  A note names the file, the number of invalid sequences and the
encoding used.  This retry is automatic because reading such a file as UTF-8
loses the characters for good, while reading it as latin1 or windows-1252 keeps
every byte as a character; for the characters 0xA0 to 0xFF the two encodings
agree, and they cover the Western European letters.  If the text still looks
wrong (the file is, say, Cyrillic or Mac Roman), rerun with the right
{opt encoding()}.{p_end}

{phang2}
o  {opt encoding()} was not given and the file mixes valid UTF-8 accented
characters with invalid bytes: it is read as UTF-8, because guessing a
single-byte encoding would garble the valid characters, and a warning says that
the invalid bytes are dropped.{p_end}

{phang2}
o  {opt encoding(utf-8)} was given and the file has invalid bytes: it is read as
UTF-8, as asked, with the same warning.  Any other {opt encoding()} is used as
given without a check.{p_end}

{marker header}{...}
{pstd}
{ul:First row.}  By default the first row of a text file holds the variable names
({cmd:varnames(1)}).  A file without a header row would then lose its first data
row, silently.  So, unless {opt firstrow} or {opt nofirstrow} is given, the scan
splits the first non-empty row into fields (honoring double quotes) and also
reads up to 20 more rows to compare the number of fields:

{phang2}
o  Every field of the first row is a number, no field is in quotes, and the
following rows have the same number of fields: the file has no header.  It is
read with {cmd:varnames(nonames)} (variables v1, v2, ...) and a note shows the
first fields and says to specify {opt firstrow} if they are names.{p_end}

{phang2}
o  The first row is all numbers, but some fields are empty, or are in quotes, or
the rows below have a different number of fields; or the first row mixes numbers
and text ({cmd:1,Smith,45}): the case is uncertain.  The first row is used as
variable names, as before, and a note says why the case is uncertain and to
specify {opt nofirstrow} if the row is data (or {opt firstrow} to silence the
note).{p_end}

{phang2}
o  No field of the first row is a number: the row is a header and is read as
one, with no note.  This includes a header whose columns are all text.{p_end}

{pstd}
A number here is anything Stata reads as a number: {cmd:12}, {cmd:-3.5},
{cmd:1e5}, {cmd:.5}.  Fields such as {cmd:pop2019}, {cmd:$5} or {cmd:1,200} are
text.  A UTF-8 byte order mark at the start of the file is ignored.  The check
applies only to text files; Excel files are read with {cmd:firstrow} unless you
give {opt nofirstrow}.

{marker codes}{...}
{pstd}
{ul:Code columns.}  {cmd:import delimited} reads a column of numbers as numeric,
which turns ZIP codes, FIPS codes and zero-padded months ({cmd:00501},
{cmd:001}, {cmd:01}) into 501, 1 and 1.  Without {opt destring}, the scan looks
for any field that starts with a zero followed by a digit.  If there is one, the
file is first read with every column as text, and each column in which some
value starts with a zero followed by a digit, and every value is a number or
empty, is a code column.  The file is then read again with only the code columns
as text ({cmd:stringcols()}), so all other columns get their usual numeric
types, and a note lists the code columns.  Values such as {cmd:0.5} do not count
as zero-padded.  A column that also holds text ({cmd:NA}, {cmd:x}) is read as
text by {cmd:import delimited} anyway, so its zeros are kept without being
listed.  Files with no zero-padded field are read once, as before.  With
{opt destring}, every column is read as text and the ID rules of {opt destring}
apply instead.


{marker quotes}{...}
{title:Remarks: stray quotes}

{pstd}
{opt strictquotes} skips the rule below: every text file is read with
{cmd:bindquote(strict)}, with no check and no fallback to loose binding (a
file that strict binding cannot read fails).

{pstd}
Strict binding keeps a quoted field that contains the delimiter or a line
break in one cell, but it also treats one unmatched double quote, such as the
inch mark in {cmd:1,5" screen,10}, as the start of a quoted field, so the rows
after it can fold into a single cell with no error.  Unless
{opt strictquotes} is given, {cmd:convertanything} checks the strict result:

{p 8 10 2}
o  If no string cell contains a line break, the strict result is kept.  The
file is read once and nothing is printed.{p_end}
{p 8 10 2}
o  Otherwise each cell that contains a line break is split at its line
breaks.  A line after the first {it:looks like a data row} when it holds at
least {it:k}-1 delimiters, where {it:k} is the number of columns of the strict
read and the delimiter is the one of comma, tab, semicolon, or pipe that
splits the file's first line into {it:k} fields.  When {it:k} <= 2 that test is
too weak, so the line must also start with an id-like token (digits,
optionally after up to four letters and a {cmd:_} or {cmd:-}, such as
{cmd:17}, {cmd:Q12}, {cmd:id_003}, or {cmd:2024-001}), and the first column of
the file must hold such values.{p_end}
{p 8 10 2}
o  If any line looks like a data row, a stray quote joined rows.  A
{cmd:WARNING} note names the file, the row and column of the strict read
where the joined cell starts, and the strict and loose row counts, and the
file is read again with the default loose binding; that result is saved.
Every row survives, but the cell that holds the stray quote runs to the end of
its line, so repair that line upstream.{p_end}
{p 8 10 2}
o  If no line looks like a data row, the line breaks are genuine multi-line
text, such as a free-text survey answer: the strict result is kept and nothing
is printed.{p_end}

{pstd}
A file with both a genuine multi-line field and a stray quote gets the
warning and the loose result: the stray-quote reading wins, so the multi-line
field splits too.  Repair the stray quote upstream.  A genuine multi-line field
whose later line happens to hold {it:k}-1 delimiters (for example, a second line
with two commas in a three-column file) is also read as a stray quote; specify
{opt strictquotes} for such a file.  The same rule, with the same logic, is used
by {cmd:combineall} and {cmd:cxchangelog}.


{marker types}{...}
{title:Remarks: other file types}

{p2colset 8 20 22 2}{...}
{p2col:Extension}How it is read{p_end}
{p2line}
{p2col:.csv .txt .tab}{cmd:import delimited}; see {help convertanything##text:Remarks: text files}.{p_end}
{p2col:.xls .xlsx}{cmd:import excel} with {cmd:firstrow} (without it under
{opt nofirstrow}); the first worksheet, or each worksheet with
{opt allsheets}.  A worksheet with no data is skipped.{p_end}
{p2col:.dta}{cmd:use}; copied to {opt saving()} with any cleaning options
applied.  A .dta whose output folder is its own folder is left as is and
counted in {cmd:r(N_inplace)}, not in {cmd:r(N_files)}.{p_end}
{p2col:.raw}See below.{p_end}
{p2line}

{pstd}
{ul:.raw files.}  A .raw file is read in one of two ways, chosen from its
content:

{phang2}
o  If the first word of the file is {cmd:dictionary} (or the file starts with
{cmd:infile dictionary}), it is a Stata dictionary followed by the data, and it
is read with {cmd:infile using}.{p_end}

{phang2}
o  Otherwise the file must be a rectangle of values separated by blanks, tabs or
commas, the layout {cmd:outfile} writes, with the same number of values on
every non-empty line.  It is read free-format with {cmd:infile}, one variable
per column, named v1, v2, ....  A column in which every value is a number (or a
missing value such as {cmd:.} or {cmd:.a}) is read as double; any other column
is read as a string as wide as its longest value.  Values in double quotes may
contain blanks ({cmd:"e f"}).{p_end}

{pstd}
Other .raw files fail with r(610) and a reason: rows with different numbers of
values (for example fixed-column data without a dictionary; write a dictionary
for those), an empty file, or a value longer than 2,045 characters.  .raw files
are not checked for encoding, header or code columns.


{marker names}{...}
{title:Remarks: output names and replace}

{pstd}
Each source {it:name.ext} becomes {it:name}{cmd:.dta} in the output folder, with
these exceptions, which keep every output of one run distinct and protect
existing data:

{phang2}
1.  If several sources in one output folder share a name ({cmd:survey.csv},
{cmd:survey.xlsx}), each gets its type as a suffix: {cmd:survey_csv.dta},
{cmd:survey_xlsx.dta}.  A .dta among them that is copied to {opt saving()} keeps
its name.{p_end}

{phang2}
2.  With {opt allsheets}, the worksheet name is passed through {help strtoname()}:
sheet {cmd:Sheet 1} of {cmd:book.xlsx} becomes {cmd:book_Sheet_1.dta}.  Sheets
that map to the same name get {cmd:_2}, {cmd:_3}, ...: {cmd:Sheet_1} becomes
{cmd:book_Sheet_1_2.dta}.{p_end}

{phang2}
3.  A name already used in this run, or taken by another source's output, gets
{cmd:_2}, {cmd:_3}, ....  Names are compared without regard to case.{p_end}

{phang2}
4.  {ul:Tags.}  Every saved dataset records its source in the characteristic
{cmd:_dta[convertanything]}: the source file name ({cmd:survey.csv}), followed
by {cmd:|}{it:sheet} for a worksheet saved with {opt allsheets}.  You can see it
with {cmd:char list _dta[convertanything]}.{p_end}

{phang2}
5.  {ul:Protection in the source folder.}  When the output goes into the source
folder (no {opt saving()}), an existing .dta of the planned name is overwritten
(with {opt replace}) only if its tag shows that {cmd:convertanything} wrote it
from the same source.  Any other .dta is left alone: your own {cmd:survey.dta},
a .dta written from another source, a file Stata cannot read, or an output of
version 1.2 or earlier, which had no tag.  The new output is then saved as
{it:name}{cmd:_}{it:ext}{cmd:.dta} (then {cmd:_2}, {cmd:_3}, ... if that is taken
too), and a note names the existing file, says why it was not overwritten, and
names the file written instead.{p_end}

{pstd}
{ul:Rerunning over version 1.2 outputs.}  Outputs written by version 1.2 have no
tag, so a rerun in place keeps them and writes {it:name}{cmd:_}{it:ext}{cmd:.dta}
beside them.  This is deliberate: an untagged {it:name}{cmd:.dta} could just as
well be your own dataset, and the command cannot tell the two apart.  Later
reruns find their own tagged {it:name}{cmd:_}{it:ext}{cmd:.dta} and update it
with {opt replace}.  To go back to the plain names, move or delete the old
{it:name}{cmd:.dta} files and rerun with {opt replace}; the new outputs are then
written as {it:name}{cmd:.dta} with a tag, and later reruns with {opt replace}
overwrite them.  Or write to a separate folder with {opt saving()}, where
{opt replace} overwrites existing outputs whatever their tag.  There is no
option to overwrite untagged files in the source folder.

{pstd}
{ul:replace in short.}  Without {opt replace}, an existing output is never
touched and its source is counted as skipped.  With {opt replace}, an existing
output is overwritten in a {opt saving()} folder, and in the source folder only
if its tag matches the source.


{marker skiprules}{...}
{title:Remarks: what is skipped}

{pstd}
{ul:Folders.}  With {opt recursive}, these subfolders are not entered: folders
named in {opt skip()} (default {cmd:_converted} and {cmd:_archive}, matched
without regard to case), the {opt saving()} folder and everything below it, and
folders more than 100 levels deep.  Folders that cannot be opened, or that are
too deep, are reported; the others are reported with {opt verbose}.

{pstd}
{ul:Files.}  In folder mode, extensions match without regard to case
({cmd:FILE.CSV}, {cmd:Data.Xlsx}), and only the supported extensions (or those
in {opt extension()}) are read.  Two kinds of system files are ignored, and
counted with {opt verbose}:

{phang2}
o  names that start with {cmd:._}: macOS AppleDouble files on shared or USB
drives;{p_end}

{phang2}
o  Excel lock files: names that start with {cmd:~$} and end in {cmd:.xls},
{cmd:.xlsx} or {cmd:.xlsm}, such as {cmd:~$budget.xlsx}, which Excel creates
while a workbook is open.  Other files whose names start with {cmd:~$}, such as
{cmd:~$notes.csv}, are ordinary files and are converted.{p_end}

{pstd}
{ul:Outputs.}  A source whose output exists is skipped without {opt replace}.  A
.dta whose output folder is its own folder is left in place.  An empty worksheet
is skipped.


{marker messages}{...}
{title:Messages and errors}

{pstd}
Every file gets one status line when it is skipped or fails, and notes when the
command changed how it read the file (encoding, first row, code columns, loose
quoting after a strict read failed or a stray quote was found) or chose another
output name.  Each note starts
with the source path.  At the end, a summary line reports the number of files,
how many were converted, the number of datasets saved, and how many were skipped
and failed; the same counts are in {cmd:r()}.

{pstd}
In folder mode, the command returns 0 when it has finished, even if some files
failed; check {cmd:r(N_failed)} and {cmd:r(failed)}.  For a single file, a file
that is not converted is an error: the return code of the failure (r(198) for an
unsupported type, r(610) for an unreadable .raw), or r(602) when the output
exists and {opt replace} was not given.  Other errors: r(198) when {cmd:using} is
missing, {opt extension()} names an unsupported type, or {opt firstrow} and
{opt nofirstrow} are combined; r(601) when the path does not exist; r(693) when
the {opt saving()} folder cannot be created; and r(4) when changed data are in
memory and {opt clear} was not given.


{marker examples}{...}
{title:Examples}

{pstd}Convert one file and clean it{p_end}
{phang2}{cmd:. convertanything using "mydata.csv", replace clear cleannames destring compress}{p_end}

{pstd}Convert a whole tree into a separate folder, every worksheet, fully cleaned{p_end}
{phang2}{cmd:. convertanything using "raw", recursive saving("converted") ///}{p_end}
{phang2}{cmd:      allsheets cleannames destring compress clear replace}{p_end}

{pstd}Only the CSV files of one folder, flat output{p_end}
{phang2}{cmd:. convertanything using "downloads", extension(csv) saving("stata_data") replace clear}{p_end}

{pstd}Rerun after new files arrive: existing outputs are skipped{p_end}
{phang2}{cmd:. convertanything using "raw", recursive saving("converted") clear}{p_end}
{phang2}{cmd:. display r(N_converted) " new, " r(N_skipped) " already converted"}{p_end}

{pstd}A Windows-encoded CSV without a header row{p_end}
{phang2}{cmd:. convertanything using "old export.csv", encoding(windows-1252) nofirstrow replace clear}{p_end}

{pstd}A CSV whose column names are years{p_end}
{phang2}{cmd:. convertanything using "by_year.csv", firstrow replace clear}{p_end}

{pstd}Enter every subfolder, including {cmd:_archive}{p_end}
{phang2}{cmd:. convertanything using "raw", recursive saving("converted") skip("") replace clear}{p_end}

{pstd}List what failed in a folder run{p_end}
{phang2}{cmd:. convertanything using "raw", recursive saving("converted") replace clear}{p_end}
{phang2}{cmd:. foreach f in `r(failed)' {c -(}}{p_end}
{phang2}{cmd:.     display `"`f'"'}{p_end}
{phang2}{cmd:. {c )-}}{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:convertanything} stores the following in {cmd:r()}, also when some files
failed:

{synoptset 18 tabbed}{...}
{p2col 5 18 22 2: Scalars}{p_end}
{synopt:{cmd:r(N_files)}}source files considered (not counting .dta files left in place){p_end}
{synopt:{cmd:r(N_converted)}}source files with at least one dataset saved{p_end}
{synopt:{cmd:r(N_saved)}}.dta files written (worksheets count separately){p_end}
{synopt:{cmd:r(N_skipped)}}source files skipped (output exists, empty worksheet, ...){p_end}
{synopt:{cmd:r(N_failed)}}source files that could not be converted{p_end}
{synopt:{cmd:r(N_inplace)}}folder mode: .dta files already in their output folder, left as is{p_end}

{p2col 5 18 22 2: Macros}{p_end}
{synopt:{cmd:r(saved)}}the .dta files written, each in compound quotes{p_end}
{synopt:{cmd:r(skipped)}}the skipped source files, each in compound quotes{p_end}
{synopt:{cmd:r(failed)}}the failed source files, each in compound quotes{p_end}
{p2colreset}{...}

{pstd}
{cmd:r(N_files)} = {cmd:r(N_converted)} + {cmd:r(N_skipped)} + {cmd:r(N_failed)}.
A workbook with {opt allsheets} counts as converted if at least one worksheet was
saved.  Version 1.2 stored nothing in {cmd:r()}.


{marker compat}{...}
{title:Changes from version 1.2}

{pstd}
Calls written for version 1.2 run unchanged; no option was removed or renamed.
The results can differ, and this section lists every difference.

{pstd}
{ul:Reading text files}

{phang2}
o  {ul:Encoding.}  Version 1.2 read text files with the encoding that
{cmd:version 16} implies, latin1, so UTF-8 files lost their accented characters
on every Stata version ({cmd:Pe}{c n~}{cmd:itas} became {cmd:Pe}{c A~}{c 177}{cmd:itas}).
Version 1.3 reads UTF-8 by default, adds {opt encoding()}, and checks each file:
a file that is not valid UTF-8 is read as latin1 or windows-1252 with a note,
and a file that mixes encodings, or is read as UTF-8 by request despite invalid
bytes, gets a warning.  See {help convertanything##encoding2:Encoding}.{p_end}

{phang2}
o  {ul:Header row.}  Version 1.2 let {cmd:import delimited} guess whether the
first row was a header, and that guess can take the header for data when every
column is text, so the header became the first observation.  Version 1.3 uses
the first row as variable names by default, reads a first row of numbers only
as data with a note, notes uncertain cases, and adds {opt firstrow} and
{opt nofirstrow} (version 1.2 had neither, for any file type).  See {help convertanything##header:First row}.{p_end}

{phang2}
o  {ul:Code columns.}  Version 1.2 turned zero-padded codes into numbers
({cmd:00501} became 501).  Version 1.3 keeps such columns as text, with a note,
even without {opt destring}.  See {help convertanything##codes:Code columns}.{p_end}

{phang2}
o  {ul:Quoted line breaks.}  Text files are read with {cmd:bindquote(strict)}, so
a quoted field may contain line breaks; a file that strict quoting cannot read
is read again with loose quoting and a note.  Version 1.3.1 adds the
stray-quote rule and {opt strictquotes} (see {help convertanything##quotes:Stray quotes});
in 1.3, a stray quote silently merged rows and only a note about line breaks
was printed.{p_end}

{pstd}
{ul:Output names, tags and replace}

{phang2}
o  Version 1.2 saved every source as {it:name}{cmd:.dta}, so {cmd:survey.csv},
{cmd:survey.xlsx} and {cmd:survey.dta} overwrote one another, and without
{opt saving()} a conversion could overwrite your own {cmd:survey.dta}.  Version
1.3 gives same-named sources a type suffix ({cmd:survey_csv.dta}) and makes
every name unique within a run.{p_end}

{phang2}
o  Every output now carries the tag {cmd:_dta[convertanything]}.  In the source
folder, only a tagged output from the same source is overwritten.  So a rerun
in place over version 1.2 outputs writes {it:name}{cmd:_}{it:ext}{cmd:.dta}
beside them, with a note; see
{help convertanything##names:Rerunning over version 1.2 outputs} for how to go
back to the plain names.{p_end}

{phang2}
o  Without {opt replace}, an existing output is skipped and the run goes on.
Version 1.2 stopped the whole batch with r(602) at the first existing
output.{p_end}

{phang2}
o  With {opt allsheets}, worksheet names that map to the same name under
{help strtoname()} get {cmd:_2}, {cmd:_3}, ...; version 1.2 wrote them to one
file.  Sheet names with quotes are read correctly.{p_end}

{phang2}
o  {opt saving()} folders are created with any missing parent folders; version
1.2 created only the last level.{p_end}

{pstd}
{ul:Which files are read}

{phang2}
o  Folders are detected with Mata {cmd:direxists()}, so folder and recursive
mode work on Windows; backslashes in paths become forward slashes; a leading
{cmd:~} is expanded.{p_end}

{phang2}
o  Files are listed once, before anything is written, so outputs are never read
back as input in the same run.  Version 1.2 could pick up the .dta files it had
just written.{p_end}

{phang2}
o  Extensions match without regard to case; version 1.2 could miss
{cmd:FILE.CSV} on a case-sensitive file system.
{opt extension()} accepts a leading dot and quotes, and rejects unsupported
types with r(198).{p_end}

{phang2}
o  AppleDouble files ({cmd:._*}) and Excel lock files ({cmd:~$*.xls},
{cmd:~$*.xlsx}, {cmd:~$*.xlsm}) are ignored; other {cmd:~$} files are
converted.{p_end}

{phang2}
o  {opt recursive} never enters the {opt saving()} folder, matches {opt skip()}
names without regard to case, and accepts {cmd:skip("")} to enter every folder
and quoted names with spaces.{p_end}

{phang2}
o  .raw files without a dictionary are read free-format when they are
rectangular, and fail with a reason otherwise; version 1.2 failed on them
silently.{p_end}

{pstd}
{ul:Reporting and errors}

{phang2}
o  Every file is reported as saved, skipped or failed with a reason; a summary
line always prints; counts and lists are stored in {cmd:r()}.  Version 1.2
printed failures only with {opt verbose}, without a reason, and stored
nothing.{p_end}

{phang2}
o  Without {opt clear}, changed data in memory stop the command with r(4) before
anything is written.  Version 1.2 then converted only the first file, or none,
without a message.{p_end}

{phang2}
o  A single file that is not converted is an error (r(198), r(602), r(610), ...);
a folder run returns 0 when it finishes.  Version 1.2 returned 0 in both
cases.{p_end}

{pstd}
{ul:Cleaning}

{phang2}
o  {opt destring} keeps ID-like text (leading zero, more than 15 digits), odd
commas and partial percent signs as text, and reports what it converted and
kept.  Version 1.2 ran {cmd:destring _all} with {cmd:ignore("$,%") percent},
which turned {cmd:00123} into 123 and {cmd:1,5} into 15.{p_end}

{phang2}
o  {opt cleannames} makes colliding names unique with a suffix and a note, and
uses {help ustrtoname()} so non-ASCII names are handled.  Version 1.2 left a
variable whose clean name was taken under its old name, without a message.{p_end}

{pstd}
{ul:Internals}

{phang2}
o  The internal programs {cmd:ProcessFile} and {cmd:PostProcess} of version 1.1
are gone; they were never callable from outside the ado-file.{p_end}


{marker author}{...}
{title:Author}

{pstd}
Eric A. Booth{break}
Texas 2036{break}
Email: {browse "mailto:eric.a.booth@gmail.com":eric.a.booth@gmail.com}{break}
GitHub: {browse "https://www.github.com/ericabooth":www.github.com/ericabooth}
{p_end}
