ALIBUILD_PREFIX=/home/dberzano/alisw/alibuild
export ALIBUILD_WORK_DIR=/home/dberzano/alice-ng/sw
eval $($ALIBUILD_PREFIX/alienv printenv -q AliPhysics/latest-aliroot5-user,AliDPG/latest)
type aliroot &> /dev/null
[[ $ALIDPG_ROOT ]] || exit 1
