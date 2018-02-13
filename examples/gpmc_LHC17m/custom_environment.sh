#!/bin/bash -e

# Use this script with jdl2makeflow by adding the following line to your JDL:
# EnvironmentCommand = "export PACKAGES=\"<package1> <package2>\"; export CVMFS_NAMESPACE=alice-nightlies; source custom_environment.sh";

SW_COUNT=0
SW_MAXCOUNT=200
mkdir -p /build/workarea/wq || true
CVMFS_SIGNAL="/tmp/${CVMFS_NAMESPACE}.cern.ch.cvmfs_reload /build/workarea/wq/${CVMFS_NAMESPACE}.cern.ch.cvmfs_reload"
while [[ $SW_COUNT -lt $SW_MAXCOUNT ]]; do
  FOUND=1
  for P in $PACKAGES; do
    /cvmfs/${CVMFS_NAMESPACE}.cern.ch/bin/alienv q | grep -qE "^$P$" || { FOUND=; break; }
  done
  [[ $FOUND ]] && break || true
  [[ ! -z "$CVMFS_SIGNAL" ]] && { touch $CVMFS_SIGNAL; unset CVMFS_SIGNAL; }
  sleep 1
  SW_COUNT=$((SW_COUNT+1))
done

eval $(/cvmfs/${CVMFS_NAMESPACE}.cern.ch/bin/alienv printenv ${PACKAGES// /,})
