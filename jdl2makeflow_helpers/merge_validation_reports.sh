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
rm -rf temp.txt copyHere.C
