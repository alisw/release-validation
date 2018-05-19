#!/bin/bash -e
mkdir mergelogs
cat > copyHere.C <<EOF
void copyHere() {
  Int_t count = 0;
  TString dest;
$(cat "$1" | xargs -n1 -IXXX echo -e "  dest = \"mergelogs/log\"; dest += count++;\n  TFile::Cp(\"XXX\", dest.Data());")
}
EOF
root -l -b -q copyHere.C
cat mergelogs/* | sed -e '/^$/d' > validation_report_full.txt
rm -rf mergelogs copyHere.C
