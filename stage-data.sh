#!/bin/bash -e
RAWPATH=$1
NFILES=$2
( which alien_cp && which xrdcp ) &> /dev/null || {
  echo "Cannot find alien_cp/xrdcp."; exit 1; }
[[ ! -z $RAWPATH && ! -z $NFILES ]] || {
  echo "Usage: $0 <source_path> <n_files>  # where <source_path> is in the form /alice/data/2016/LHC16e/000252858/raw/"; exit 1; }

RANDOMIZE=1
TMPDATA=/tmp/relval_stage_$(echo $RAWPATH | sha1sum | cut -d' ' -f1)
RAWPATH=/$(echo $RAWPATH | sed -e 's!/+!/!g; s!/$!!; s!^/!!')
ALIEN_PREFIX=alien://$RAWPATH
[[ $RAWPATH =~ /([0-9]{4}/LHC[0-9]+[a-z]+/[0-9]{9})/ ]] || { echo "Invalid source path."; exit 1; }
EOS_PREFIX=root://eospublic.cern.ch//eos/opstest/pbuncic/reference/${BASH_REMATCH[1]}
BUF=/tmp/raw_temp_$$.root

function try_again() {
  local ERR R
  R=0
  while :; do
    "$@" || { R=$?; ERR=$((ERR+1)); }
    [[ $R == 0 || $ERR -gt 5 ]] && break
  done
  return $R
}

function print_list() {
  echo "==> List of files to copy: $TMPDATA"
  echo "==> List of files already copied: $TMPDATA.done"
}

[[ -s $TMPDATA ]] || { alien_ls $RAWPATH | sort ${RANDOMIZE:+-R} | head -$NFILES | xargs -L1 -I'{}' echo $ALIEN_PREFIX/'{}' $EOS_PREFIX/'{}' > $TMPDATA; }
[[ -s $TMPDATA ]]

print_list

while read FILE; do
  rm -f $BUF
  SRC=${FILE%% *}
  DEST=${FILE#* }
  grep -q $DEST $TMPDATA.done && continue || true
  echo "$SRC -> $DEST"
  echo "[AliEn->local] $SRC -> $BUF"
  try_again alien_cp $SRC $BUF
  echo "[local->EOS] $BUF -> $DEST"
  try_again env X509_USER_PROXY=$HOME/.globus/eos-proxy xrdcp -f $BUF $DEST || { rm -f $BUF; exit 1; }
  echo $DEST >> $TMPDATA.done
done < <(cat $TMPDATA|grep -v '^#')
rm -f $BUF

print_list
exit 0
