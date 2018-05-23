#!/bin/bash -e
ALIDPGSCRIPT="$(find "$ALIDPG_ROOT" -name "$1" -print -quit || true)"
[[ $ALIDPGSCRIPT ]] || { echo "Cannot find $1 in $ALIDPG_ROOT"; exit 1; }
[[ -x $ALIDPGSCRIPT ]] || ALIDPGSCRIPT="bash $ALIDPGSCRIPT"

# Execute actual cpass0SpCalib script first
shift
RV=0
$ALIDPGSCRIPT "$@" || RV=$?

# Check if we need to rerun it with an externally-supplied calibration
grep -qE '^E-ProcessOutput:' ocdb.log &> /dev/null \
  && echo "First run not OK for calibrating, we need to rerun" \
  || { echo "No problems found, exiting"; exit $RV; }

[[ $ALITPCDCALIBRES_LIST ]] || { echo "Cannot rerun as external list \$ALITPCDCALIBRES_LIST was not set"; exit 1; }

echo "Faking run by using external list $ALITPCDCALIBRES_LIST"
mv ocdb.log ocdb.log.old
rm -f alitpcdcalibres.txt
cat > copyHere.C <<EOF
void copyHere() {
  TFile::Cp("$ALITPCDCALIBRES_LIST", "alitpcdcalibres.txt");
}
EOF
root -l -b -q copyHere.C
rm -f copyHere.C

# Execute again, with updated stats
exec $ALIDPGSCRIPT "$@"
