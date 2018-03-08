ALIBUILD_PREFIX=/home/dberzano/alisw/alibuild
export ALIBUILD_WORK_DIR=/home/dberzano/alice-ng/sw
eval $($ALIBUILD_PREFIX/alienv printenv -q AliPhysics/latest-prod-user,AliDPG/latest-prod-user)
type aliroot &> /dev/null
[[ $ALIDPG_ROOT ]] || exit 1
