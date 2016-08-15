#!/bin/bash -e

for V in LANG LANGUAGE LC_ALL LC_COLLATE LC_CTYPE LC_MESSAGES LC_MONETARY \
         LC_NUMERIC LC_TIME LC_ALL; do
  export $V=C
done

set -o pipefail
hostname -f

set -x
cd $(mktemp -d /mnt/mesos/sandbox/relval-XXXXX)

# Fetch required scripts from the configurable upstream version of AliPhysics.
for FILE in PWGPP/benchmark/benchmark.sh \
            PWGPP/scripts/utilities.sh   \
            PWGPP/scripts/alilog4bash.sh ; do
  curl http://git.cern.ch/pubweb/AliPhysics.git/blob_plain/$RELVAL_ALIPHYSICS_REF:/$FILE -O
done
set +x

# Define tag name.
RELVAL_SHORT_NAME=AliPhysics-${ALIPHYSICS_VERSION}
RELVAL_NAME=${RELVAL_SHORT_NAME}-${RELVAL_TIMESTAMP}
echo "Release validation name: $RELVAL_NAME"

# Configuration file for the Release Validation.
cat > benchmark.config <<EOF
# Note: do not be confused by "2010". It will be substituted with the actual year at runtime.
defaultOCDB="local:///cvmfs/alice-ocdb.cern.ch/calibration/data/2010/OCDB/"
batchFlags=""
reconstructInTemporaryDir=0
recoTriggerOptions="\"\""
export additionalRecOptions="TPC:useRAWorHLT;"
export ALIEN_JDL_TARGETSTORAGERESIDUAL=local://./resOCDB
percentProcessedFilesToContinue=100
maxSecondsToWait=$(( 3600*24 ))
nMaxChunks=0
postSetUpActionCPass0=""
postSetUpActionCPass1=""
runCPass0reco=1
runCPass0MergeMakeOCDB=1
runCPass1reco=1
runCPass1MergeMakeOCDB=1
runESDfiltering=1
filteringFactorHighPt=1e2
filteringFactorV0s=1e1
MAILTO=""
logToFinalDestination=1
ALIROOT_FORCE_COREDUMP=1
# Note: -r 3 ==> retry up to 3 times
makeflowOptions="-T wq -N alirelval_${RELVAL_NAME} -r 3 -C wqcatalog.marathon.mesos:9097"
baseOutputDirectory="root://eospublic.cern.ch//eos/experiment/alice/release-validation/output"
alirootEnv=
reconstructInTemporaryDir=2
dontRedirectStdOutToLog=
logToFinalDestination=
copyInputData=1
nEvents=$LIMIT_EVENTS

# Check if the chosen AliPhysics version is available.
# If not, try to signal a CVMFS refresh. Patiently wait for up to 200 s.
SW_COUNT=0
SW_MAXCOUNT=200
mkdir -p /build/workarea/wq || true
CVMFS_SIGNAL="/tmp/${CVMFS_NAMESPACE}.cern.ch.cvmfs_reload /build/workarea/wq/${CVMFS_NAMESPACE}.cern.ch.cvmfs_reload"
echo "Waiting for AliPhysics $ALIPHYSICS_VERSION to be available (max \${SW_MAXCOUNT}s)"
while [[ \$SW_COUNT -lt \$SW_MAXCOUNT ]]; do
  eval \$(/cvmfs/$CVMFS_NAMESPACE.cern.ch/bin/alienv printenv AliPhysics/$ALIPHYSICS_VERSION 2> /dev/null) > /dev/null 2>&1
  which aliroot > /dev/null 2>&1 && break || true
  [[ ! -z "\$CVMFS_SIGNAL" ]] && { touch \$CVMFS_SIGNAL; unset CVMFS_SIGNAL; }
  sleep 1
  SW_COUNT=\$((SW_COUNT+1))
done
which aliroot || exit 40

export X509_CERT_DIR="/cvmfs/grid.cern.ch/etc/grid-security/certificates"
export X509_USER_PROXY="/secrets/eos-proxy"
[[ -f "\$X509_USER_PROXY" ]] || exit 41
EOF

# Run functions in the Release Validation's environment.
function relvalenv() {(
  source utilities.sh     &> /dev/null
  source benchmark.config &> /dev/null
  "$@"
)}

# Print variable value in the Release Validation's environment.
function relvalvar() {(
  source utilities.sh     &> /dev/null
  source benchmark.config &> /dev/null
  eval 'echo $'$1
)}

# Check whether proxy certificate exists and it will still valid be for the next week.
set -x
  ( source benchmark.config )
  echo "Checking certificate validity"
  openssl x509 -in "$(relvalvar X509_USER_PROXY)" -noout -subject -enddate -checkend $((86400*7))
set +x

# Check quota on EOS if appropriate.
EOS_REQ_GB=${REQUIRED_SPACE_GB:=-1}
if [[ $EOS_REQ_GB -ge 0 && "$(relvalvar baseOutputDirectory)" == */eos/* ]]; then
  EOS_RE='\([a-z]\+://[^/]\+\)/\(.*$\)'
  EOS_HOST=$(relvalvar baseOutputDirectory | sed -e 's!'"$EOS_RE"'!\1!')
  EOS_PATH=$(relvalvar baseOutputDirectory | sed -e 's!'"$EOS_RE"'!\2!')
  EOS_QUOTA_RAW=$(relvalenv eos $EOS_HOST quota $EOS_PATH -m)
  EOS_QUOTA=$(echo $EOS_QUOTA_RAW | grep uid= || true)
  [[ -z "$EOS_QUOTA" ]] \
    && EOS_FREE_GB=infinite \
    || EOS_FREE_GB=$(eval $EOS_QUOTA; echo $(( ($maxbytes-$usedbytes)/1024/1024/1024 )) )
    [[ -z "$EOS_QUOTA" || "$EOS_FREE_GB" -ge $EOS_REQ_GB ]] \
      && echo "Free space on EOS: $EOS_FREE_GB GB (above $EOS_REQ_GB GB)." \
      || { echo "Only $EOS_FREE_GB GB on EOS, but $EOS_REQ_GB GB required. Aborting."; exit 1; }
  else
    echo ""
fi

# Prepare dataset
DATASET_FILE="$WORKSPACE/release-validation/datasets/${DATASET}.txt"
cp "$DATASET_FILE" files.list
if [[ "$LIMIT_FILES" -gt 0 ]]; then
  echo "Limiting validation to $LIMIT_FILES file(s)."
  head -n$LIMIT_FILES "$DATASET_FILE" > files.list
fi

# Pure (i.e. non-filtered) raws need this parameter
if ! grep -q filtered files.list; then
  echo "Adding trigger option for non-filtered raws."
  cat >> benchmark.config <<EOF
recoTriggerOptions="?Trigger=kCalibBarrel"
EOF
fi

echo "Using dataset $DATASET, list of files follows."
cat files.list

# Allow for monkey-patching the current validation. It takes a tarball from the given URL and
# unpacks it in the current directory.
if [[ ! -z "$MONKEYPATCH_TARBALL_URL" ]]; then
  echo "Getting and applying monkey-patch tarball from $MONKEYPATCH_TARBALL_URL..."
  relvalenv copyFileFromRemote "$MONKEYPATCH_TARBALL_URL" "$PWD"
  TAR=`basename "$MONKEYPATCH_TARBALL_URL"`
  tar xzvvf "$TAR"
  rm -f "$TAR"
fi

chmod +x benchmark.sh
[[ "$DRY_RUN" == true ]] && { echo "Dry run: not running the release validation.";
                              DRY_RUN_PREFIX="echo Would have run: "; }

if [[ $SUMMARIZE_ONLY == true ]]; then
  echo "Starting the Release Validation summary only."
  OUTPUT=$(relvalvar baseOutputDirectory)/$RELVAL_NAME
  set +e
    relvalenv xCopy -f -d $PWD $OUTPUT/benchmark.makeflow $OUTPUT/benchmark.config
  set -e
  [[ -e benchmark.makeflow ]]
  REQUIRED=$(grep ^summary.log: benchmark.makeflow | cut -d: -f2)
  REQUIRED=$(for FILE in $REQUIRED; do [[ $FILE == *.done ]] && echo $OUTPUT/$FILE || true; done)
  set +e
    relvalenv xCopy -f -d $PWD $REQUIRED
  set -e
  for FILE in $REQUIRED; do
    [[ -e $(basename $FILE) ]] || { echo "Some files were not copied."; exit 1; }
  done
  CMD=$(grep -A1 ^summary.log: benchmark.makeflow | tail -n1 | xargs echo)
  $DRY_RUN_PREFIX $CMD simplifiedSummary=1
  RV=$?
else
  echo "Starting the Release Validation."
  set +e
  $DRY_RUN_PREFIX ./benchmark.sh run "$RELVAL_NAME" files.list benchmark.config $EXTRA_VARIABLES
  RV=$?
fi

echo "Release Validation finished with exitcode $RV."
echo "Current directory (contents follow): $PWD"
find . -ls

exit $RV
