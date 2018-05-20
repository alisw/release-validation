#!/bin/bash -e
cat > copyHere.C <<EOF
void copyHere() {
  Int_t count = 0;
  TString cmd;
$(cat "$1" | xargs -n1 -IXXX echo -e "\n  gSystem->Unlink(\"temp.txt\");\n  cmd.Form(\"cat temp.txt | xargs -n1 -I{} echo '%s/{}' >> validation_report_full.txt\", gSystem->DirName(\"XXX\"));\n  TFile::Cp(\"XXX\", \"temp.txt\");\n  gSystem->Exec(cmd.Data());")
}
EOF
root -l -b -q copyHere.C
cat validation_report_full.txt | sed -e '/^$/d' | sort > validation_report_full.txt.0
mv validation_report_full.txt.0 validation_report_full.txt
cat > validation_report_full.html <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Release validation summary</title>
<style>
/* Body font */
body { font: 14px sans-serif; }

/* Links */
a { text-decoration: none;
    color: #CC444B; }

/* All tables */
table.report td { border-right: 2px solid #AAA; }
table.report tr > td:last-of-type { border-right: 0; }
table.report th { color: white; }
table.report th,
table.report td { padding: 7px 10px 7px 10px; }
table.report { border-collapse: collapse; }

/* All tables: alternate row colors */
table.report tr:nth-of-type(odd) { background-color: white; }
table.report tr:nth-of-type(even) { background-color: #F0F2EF; }

/* Summary tables: align numbers */
table.summary td:nth-of-type(2) { text-align: right; }
table.fullsummary td:nth-of-type(2) { text-align: right; }

/* File in full summary */
tr.emph td { font-weight: bold;
             text-align: left !important; }

/* Table 1 */
div.group:nth-of-type(1) h2,
div.group:nth-of-type(1) h3 { color: #F63E02; }
div.group:nth-of-type(1) table.report th { background: #F63E02; }
div.group:nth-of-type(1) table.report td { border-right-color: #F63E02; }
div.group:nth-of-type(1) table.report tr.emph { color: #F63E02; }

/* Table 2 */
div.group:nth-of-type(2) h2,
div.group:nth-of-type(2) h3 { color: #FF6201; }
div.group:nth-of-type(2) table.report th { background: #FF6201; }
div.group:nth-of-type(2) table.report td { border-right-color: #FF6201; }
div.group:nth-of-type(2) table.report tr.emph { color: #FF6201; }

/* Table 3 */
div.group:nth-of-type(3) h2,
div.group:nth-of-type(3) h3 { color: #FAA300; }
div.group:nth-of-type(3) table.report th { background: #FAA300; }
div.group:nth-of-type(3) table.report td { border-right-color: #FAA300; }
div.group:nth-of-type(1) table.report tr.emph { color: #FAA300; }

/* Table 4 */
div.group:nth-of-type(4) h2,
div.group:nth-of-type(4) h3 { color: #F7B538; }
div.group:nth-of-type(4) table.report th { background: #F7B538; }
div.group:nth-of-type(4) table.report td { border-right-color: #F7B538; }
div.group:nth-of-type(1) table.report tr.emph { color: #F7B538; }
</style>
</head>
<body>

<div class="group">
<h2>Error summary</h2>
<table class="report fullsummary">
<tr><th>File</th><th>Line</th><th>Message</th></tr>
$(while read LINE; do
  ALIEN_JDL_OUTPUTDIR=$(dirname $ALIEN_JDL_OUTPUTDIR)/$(basename $ALIEN_JDL_OUTPUTDIR)
  RE='^([a-z0-9_]+://)(.*)$'
  if [[ $LINE =~ $RE ]]; then
    FILE=${BASH_REMATCH[1]}${BASH_REMATCH[2]%%:*}
    LINE=${BASH_REMATCH[2]}
  else
    FILE=${LINE%%:*}
  fi
  # If RELVAL_DISPLAY_URL is defined, link is modified to point to the right prefix
  [[ $RELVAL_DISPLAY_URL ]] && URL=${RELVAL_DISPLAY_URL}/${FILE//"$ALIEN_JDL_OUTPUTDIR/"} || URL="$FILE"
  FILE="<a href=\"$URL\">${FILE//"$ALIEN_JDL_OUTPUTDIR/"}</a>"
  NUM=$(echo "$LINE" | cut -d: -f2)
  ERROR=$(echo "$LINE" | cut -d: -f3-)
  echo "<tr><td>$FILE</td><td>$NUM</td><td>$ERROR</td></tr>"
done < <(cat validation_report_full.txt))
</table>
</div>

</body>
</html>
EOF

rm -rf temp.txt copyHere.C
