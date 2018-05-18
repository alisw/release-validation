#!/bin/bash -e
ALIBUILD_PREFIX=/home/dberzano/alisw/alibuild
export ALIBUILD_WORK_DIR=/home/dberzano/alice-ng/sw
eval $($ALIBUILD_PREFIX/alienv --no-refresh printenv -q AliPhysics/latest-aliroot5-user,AliDPG/latest)
# Work around some system library problems with ROOT
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib/x86_64-linux-gnu"
type aliroot &> /dev/null
[[ $ALIDPG_ROOT ]] || exit 1
