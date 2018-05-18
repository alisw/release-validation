#!/bin/bash -e

# This is the script running the AliDPG-based Release Validation on Jenkins.
# This script is meant to be sourced to provide the following functionalities:
#
# * Check EOS space and inodes before starting
# * Report on JIRA about the status of the release validation

# List of contact persons for components and detectors
DETECTORS=(
  "ACORDE:mrodrigu"
  "AD:mbroz"
  "EMCAL:gconesab"
  "FMD:cholm"
  "HLT:mkrzewic"
  "HMPID:gvolpe"
  "ITS:masera"
  "MUON:laphecet"
  "PMD:bnandi"
  "PHOS:kharlov"
  "TOF:fnoferin"
  "TPC:kschweda mivanov wiechula"
  "TRD:tdietel"
  "T0:alla"
  "V0:cvetan"
  "ZDC:coppedis"
  "Reconstruction:shahoian"
  "Calibration:zampolli"
  "DevOps:hristov dberzano eulisse"
  "DPG:fprino miweber cristea"
)
JIRA_WATCHERS=($(for D in "${DETECTORS[@]}"; do echo ${D##*:}; done | xargs -n1 echo | sort -u))

# Post a comment to a given ALICE JIRA ticket. Errors are non-fatal.
function jira_comment() {
  JIRA_ISSUE=$1
  shift
  [[ -z $JIRA_ISSUE ]] && return 0 || true
  echo "Posting comment to JIRA $JIRA_ISSUE"
  ERR=
  curl -k -D- -X POST                                                      \
       --connect-timeout 5                                                 \
       --max-time 10                                                       \
       --retry 5                                                           \
       --retry-delay 0                                                     \
       --retry-max-time 40                                                 \
       -u $JIRA_USER:$JIRA_PASS                                            \
       --data '{ "body": "'"$*"'" }'                                       \
       -H "Content-Type: application/json"                                 \
       https://alice.its.cern.ch/jira/rest/api/2/issue/$JIRA_ISSUE/comment &> jlog || ERR=1
  [[ $ERR ]] && cat jlog || true
  rm -f jlog
}

function jira_watchers() {
  JIRA_ISSUE=$1
  shift
  [[ -z $JIRA_ISSUE ]] && return 0 || true
  while [[ $# -gt 0 ]]; do
    # JIRA is stupid. We have to make an API call for each watcher.
    echo "Adding watcher $1 to JIRA $JIRA_ISSUE"
    ERR=
    curl -k -D- -X POST                                                       \
         --connect-timeout 5                                                  \
         --max-time 10                                                        \
         --retry 5                                                            \
         --retry-delay 0                                                      \
         --retry-max-time 40                                                  \
         -u $JIRA_USER:$JIRA_PASS                                             \
         --data '"'$1'"'                                                      \
         -H "Content-Type: application/json"                                  \
         https://alice.its.cern.ch/jira/rest/api/2/issue/$JIRA_ISSUE/watchers &> jlog || ERR=1
    [[ $ERR ]] && cat jlog || true
    rm -f jlog
    shift
  done
  return 0
}

function eos_check_quota() {
  # Check quota on EOS if appropriate.
  EOS_OUTPUT=$1
  EOS_REQ_GB=$2
  EOS_REQ_FILES=$3
  EOS_REQ_GB=${EOS_REQ_GB:=0}
  EOS_REQ_FILES=${EOS_REQ_FILES:=0}
  if [[ $EOS_OUTPUT == */eos/* ]]; then
    EOS_RE='\([a-z]\+://[^/]\+\)/\(.*$\)'
    EOS_HOST=$(echo "$EOS_OUTPUT" | sed -e 's!'"$EOS_RE"'!\1!')
    EOS_PATH=$(echo "$EOS_OUTPUT" | sed -e 's!'"$EOS_RE"'!\2!')
    EOS_QUOTA_RAW=$(eos $EOS_HOST quota $EOS_PATH -m)
    EOS_QUOTA=$(echo $EOS_QUOTA_RAW | grep maxfiles= || true)  # validate output
    if [[ $EOS_QUOTA ]]; then
    (
      eval $EOS_QUOTA
      EOS_FREE_GB=$(( ($maxbytes-$usedbytes)/1024/1024/1024 ))
      EOS_FREE_FILES=$(( $maxfiles-$usedfiles ))
      echo "EOS free quota: $EOS_FREE_GB GB, $EOS_FREE_FILES inodes"
      if [[ ($EOS_REQ_GB -gt 0 && $EOS_FREE_GB -lt $EOS_REQ_GB) ||
            ($EOS_REQ_FILES -gt 0 && $EOS_FREE_FILES -lt $EOS_REQ_FILES) ]]; then
        echo "FATAL: not enough EOS quota: requested $EOS_REQ_GB GB and $EOS_REQ_FILES inodes"
        exit 1
      fi
    )
    else
      echo "WARNING: cannot get quota for $EOS_PATH on $EOS_HOST"
    fi
  fi
}

# Call this function to post a JIRA comment when the release validation starts.
# Usage:
#   jira_relval_started $JIRA_ISSUE $DISPLAY_URL $VERSIONS_STR $DONTMENTION
function jira_relval_started() {
  local JIRA_ISSUE=$1
  local DISPLAY_URL=$2
  local VERSIONS_STR=$3
  local DONTMENTION=$4
  jira_comment "$JIRA_ISSUE" \
               "Release validation for *${VERSIONS_STR}* started.\n" \
               " * [Jenkins log|${BUILD_URL}/console]\n" \
               " * [Validation output|${DISPLAY_URL}] (it might be still empty)\n"
  [[ $DONTMENTION != true ]] && jira_watchers "$JIRA_ISSUE" "${JIRA_WATCHERS[@]}" || true
  return 0
}

# Call this function to post a JIRA comment when the release validation is done.
# Usage:
#   jira_relval_finished $JIRA_ISSUE $EXITCODE $DISPLAY_URL $VERSIONS_STR $DONTMENTION
function jira_relval_finished() {
  local JIRA_ISSUE=$1
  local EXITCODE=$2
  local DISPLAY_URL=$3
  local VERSIONS_STR=$4
  local DONTMENTION=$5
  [[ $EXITCODE == 0 ]] && JIRASTATUS="*{color:green}success{color}*" \
                       || JIRASTATUS="*{color:red}errors{color}*"
  TAGFMT='[~%s]'
  [[ $DONTMENTION == true ]] && TAGFMT='{{~%s}}'
  jira_comment "$JIRA_ISSUE"                                                                         \
    "Release validation for *${VERSIONS_STR}* finished with ${JIRASTATUS}.\n"           \
    " * [Jenkins log|$BUILD_URL/console]\n"                                                          \
    " * [Validation output|$DISPLAY_URL]\n"                                                          \
    " * Validation summary: [HTML|$DISPLAY_URL/summary.html], [text|$DISPLAY_URL/summary.log]\n"     \
    " * QA plots for [CPass1|$DISPLAY_URL/QAplots_CPass1] and [PPass|$DISPLAY_URL/QAplots_CPass2]\n" \
    "\n"                                                                                             \
    "Mentioning contact persons for detectors and components:\n"                                     \
    "$(for D in "${DETECTORS[@]}"; do
         printf " * ${D%%:*}:"; for R in ${D#*:}; do printf " $TAGFMT" "$R"; done; echo -n "\n"
       done)"
   return 0
}

# Function to preprocess the JDL
# Usage:
#   preprocess_jdl $JDL_IN $JDL_OUT
function preprocess_jdl() {
  local JDL_IN=$1
  local JDL_OUT=$2
  if grep -q 'aliroot_dpgsim.sh' "$JDL_IN"; then
    echo "Parsing JDL: ${JDL_IN}..."
    # JDL belongs to a Monte Carlo
    OUTPUT_URL="${OUTPUT_URL}/MC"
    [[ $LIMIT_FILES -ge 1 && $LIMIT_EVENTS -ge 1 ]] || { echo "LIMIT_FILES and LIMIT_EVENTS are wrongly set"; return 1; }
    cat <<EoF >> "$JDL_OUT"
NoLiveOutput = 1;
Split_override = "production:1-${LIMIT_FILES}";
SplitArguments_replace = { "--nevents\\s[0-9]+", "--nevents \${LIMIT_EVENTS}" };
OutputDir_override = "${OUTPUT_XRD}/${RELVAL_NAME}/MC/#alien_counter_04i#";
EnvironmentCommand = "export PACKAGES=\"$ALIENV_PKGS\"; export CVMFS_NAMESPACE=\"$CVMFS_NAMESPACE\"; source custom_environment.sh; type aliroot";
EoF
  elif grep -q '/aliroot_dpg' "$JDL_IN"; then
    # JDL belongs to a Reconstruction
    LHC_PERIOD=$(head -n1 input_files.txt | grep -oE '/LHC[0-9]{2}[^/]/')
    LHC_PERIOD=${LHC_PERIOD//\/}
    RUN_NUMBER=$(head -n1 input_files.txt | grep -oE '/[0-9]{9}/')
    RUN_NUMBER=$(( 10#${RUN_NUMBER//\/} ))
    cat <<EoF >> "$JDL_OUT"
X509_USER_PROXY = "\$PWD/eos-proxy";
OCDB_PATH = "/cvmfs/alice-ocdb.cern.ch";
EVENTS_PER_JOB = "$LIMIT_EVENTS";
ALIROOT_FORCE_COREDUMP = "1";
ExtraVariables = { "X509_USER_PROXY", "OCDB_PATH", "EVENTS_PER_JOB", "ALIROOT_FORCE_COREDUMP" };
InputFile_override = { "eos-proxy", "local_environment.sh" };
Output_append = { "core*", "validation_report.txt" };
OutputDir_override = "${OUTPUT_XRD}/${RELVAL_NAME}/reco/#alien_counter_04i#";
EnvironmentCommand = "source local_environment.sh";
InputDataCollection_override = "input_files.txt";
Packages = { $(for P in $ALIENV_PKGS; do echo \"$P\",; done)"" };
SplitArguments_override = "$(basename $(head -n1 input_files.txt))/#alienfilename# \$EVENTS_PER_JOB \$(( 10#\$(echo #alienfilename# | cut -b3-11) )) raw://";
NoLiveOutput = 0;
DontArchive = 1;
LPMRunNumber = "$RUN_NUMBER";
LPMAnchorRun = "$RUN_NUMBER";
LPMProductionTag = "$LHC_PERIOD";
LPMAnchorProduction = "$LHC_PERIOD";
LimitInputFiles = "$LIMIT_FILES";
EoF
  else
    # Other JDL: not supported at the moment
    echo "This JDL does not belong to a Monte Carlo. Not supported."
    return 1
  fi
  return 0
}
