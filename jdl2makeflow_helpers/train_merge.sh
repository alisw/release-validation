#!/bin/bash

export LD_LIBRARY_PATH=.:$LD_LIBRARY_PATH

echo "========================================="
echo "############## PATH : ##############"
echo $PATH
echo "############## LD_LIBRARY_PATH : ##############"
echo $LD_LIBRARY_PATH
echo "############## ROOTSYS : ##############"
echo $ROOTSYS
echo "############## which root : ##############"
which root
echo "############## ALICE_ROOT : ##############"
echo $ALICE_ROOT
echo "############## which aliroot : ##############"
which aliroot
echo "############## system limits : ##############"
ulimit -a
echo "############## memory : ##############"
free -m
echo "========================================="

runNum=${ALIEN_JDL_LPMRUNNUMBER}
echo " * Run number is $runNum * "
echo "Printing all environment variables"
printenv

export CONFIG_OCDB=${CONFIG_OCDB:-alien}
export CONFIG_RUN=$runNum

if [ -f "train_merge.C" ]; then
  export ARG="train_merge.C(\"$1\",$2)"
elif [ -f "QAtrainsim.C" ]; then
  #export ARG="QAtrainsim.C(0,\"$1\",$2)"
  export ARG="QAtrainsim.C($runNum,\"$1\",$2)" # new, catalin - ZDC QA needs the run number
elif [ -f "$ALIDPG_ROOT/QA/QAtrainsim.C" ]; then
  export ARG="$ALIDPG_ROOT/QA/QAtrainsim.C(0,\"$1\",$2)"
fi

time aliroot -b -q -x $ARG

exitcode=$?

echo "======== $ARG finished with exit code: $exitcode ========"

echo "############## memory after: ##############"
free -m

if [ $exitcode -ne 0 ]; then
    echo "$ARG exited with code $exitcode" > validation_error.message
fi

exit $exitcode
