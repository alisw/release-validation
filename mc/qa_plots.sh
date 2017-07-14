#!/bin/bash -e

DETECTORS_PATH="$ALICE_PHYSICS/PWGPP/QA/detectorQAscripts"
export ocdbStorage="raw://"
export runNumber=${ALIEN_JDL_LPMANCHORRUN:=$ALIEN_JDL_LPMRUNNUMBER}
DET_INCL=$ALIEN_JDL_QADETECTORINCLUDE
DET_EXCL=$ALIEN_JDL_QADETECTOREXCLUDE

while [[ $# -gt 0 ]]; do
  if [[ "$1" == *.zip ]]; then
    root -l -b <<EOF
TFile::Cp("$1", "$(basename "$1")");
EOF
    FILES=($(unzip -Z -1 $(basename "$1")|xargs -i echo "$PWD/$(basename "$1")#{}"))
  else
    FILES=$1
  fi
  for F in ${FILES[@]}; do
    case "$F" in
      *QAresults.root|*QAresults_merged.root|*QAresults_barrel.root) qaFile=$F             ;;
      *QAresults_outer.root)                                         qaFileOuter=$F        ;;
      *FilterEvents_Trees.root)                                      highPtTree=$F         ;;
      *event_stat.root|*event_stat_barrel.root)                      eventStatFile=$F      ;;
      *event_stat_outer.root)                                        eventStatFileOuter=$F ;;
    esac
  done
  shift
done

echo qaFile=$qaFile
echo qaFileOuter=$qaFileOuter
echo highPtTree=$highPtTree
echo eventStatFile=$eventStatFile
echo eventStatFileOuter=$eventStatFileOuter

FUNCS=( "runLevelQA:$qaFile"
        "runLevelQAouter:$qaFileOuter"
        "runLevelHighPtTreeQA:$highPtTree"
        "runLevelEventStatQA:$eventStatFile"
        "runLevelEventStatQAouter:$eventStatFileOuter" )

for FILE in "${DETECTORS_PATH}"/*; do
  [[ $FILE == *.sh ]] || continue
  DET=$(basename "${FILE%.sh}")
  if [[ ( ! $DET_INCL || " $DET_INCL " == *\ $DET\ * ) && ( ! $DET_EXCL || ! " $DET_EXCL " == *\ $DET\ * ) ]]; then
    for FUNC in "${FUNCS[@]}"; do unset -f ${FUNC%%:*}; done

    TMPQA=$PWD/qa_plots/$DET
    mkdir -p "$TMPQA"
    pushd "$TMPQA" &> /dev/null

      for FUNC in "${FUNCS[@]}"; do
        ARG=${FUNC#*:}
        FUNC=${FUNC%%:*}
        [[ $ARG ]] || continue
        source $FILE || true
        if declare -f $FUNC &> /dev/null; then
          echo "$DET/$FUNC: running..."
          RET=0
          ( $FUNC "$ARG" ) &> $FUNC.log || RET=$?
          echo "$DET/$FUNC: finished with exitcode $RET"
        fi
      done

      # Create default trending.root if missing
      if [[ ! -f trending.root && $qaFile ]]; then
        echo "$DET/simpleTrending: running..."
        detectorQAcontainerName=$DET
        RET=0
        root -b -q -l "$ALICE_PHYSICS/PWGPP/macros/simpleTrending.C(\"${qaFile}\",${runNumber},\"${detectorQAcontainerName}\",\"trending.root\",\"trending\",\"recreate\")" &> simpleTrending.log || RET=$?
        unset detectorQAcontainerName
        echo "$DET/simpleTrending: finished with exitcode $RET"
      fi

    popd &> /dev/null
    rmdir "$TMPQA" &> /dev/null || true
  fi
done
echo "Finished successfully"
