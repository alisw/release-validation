#!groovy

if ("$SKIP_BUILD" == "true") {
  stage "Config credentials"
  println("Skipping as per user request")
  stage "Tagging"
  println("Skipping as per user request")
  stage "Building"
  println("Skipping as per user request")
}
else {
  node ("$BUILD_ARCH-$MESOS_QUEUE_SIZE") {

    stage "Config credentials"
    withCredentials([[$class: 'UsernamePasswordMultiBinding',
                      credentialsId: 'github_alibuild',
                      usernameVariable: 'GIT_BOT_USER',
                      passwordVariable: 'GIT_BOT_PASS']]) {
      sh '''
        set -e
        set -o pipefail
        printf "protocol=https\nhost=github.com\nusername=$GIT_BOT_USER\npassword=$GIT_BOT_PASS\n" | \
          git credential-store --file "$PWD/git-creds" store
      '''
    }
    withCredentials([[$class: 'UsernamePasswordMultiBinding',
                      credentialsId: 'gitlab_alibuild',
                      usernameVariable: 'GIT_BOT_USER',
                      passwordVariable: 'GIT_BOT_PASS']]) {
      sh '''
        set -e
        set -o pipefail
        printf "protocol=https\nhost=gitlab.cern.ch\nusername=$GIT_BOT_USER\npassword=$GIT_BOT_PASS\n" | \
          git credential-store --file "$PWD/git-creds" store
      '''
    }
    sh '''
      set -e
      set -o pipefail
      git config --global credential.helper "store --file $PWD/git-creds"
    '''

    stage "Tagging"
    withEnv(["TAGS=$TAGS",
             "ALIDIST=$ALIDIST",
             "DEFAULTS=$DEFAULTS"]) {

      sh '''
      set -e
      set -o pipefail
      cat > alidist-override-tags.py <<EOF
#!/usr/bin/env python
# Usage: alidist-override-tags.py alidist/defaults-blah.sh AliRoot=v123 AliPhysics=v456...
from __future__ import print_function
import yaml, sys
fn = sys.argv[1]  # path to the defaults file
with open(fn) as fp:
  defaults = yaml.safe_load(fp.read().split("---", 1)[0])
for t in sys.argv[2:]:
  pkg,tag = t.split("=", 1)
  if not "overrides" in defaults:
    defaults["overrides"] = {}
  if not pkg in defaults["overrides"]:
    defaults["overrides"][pkg] = {}
  defaults["overrides"][pkg]["tag"] = tag
with open(fn, "w") as fp:
  fp.write(yaml.dump(defaults, default_flow_style=False))
  fp.write(chr(10)+"---"+chr(10))
EOF
      chmod +x alidist-override-tags.py
      python -c 'import yaml' 2> /dev/null || pip install pyyaml
      '''

      sh '''
        set -e
        set -o pipefail
        ALIDIST_BRANCH="${ALIDIST##*:}"
        ALIDIST_REPO="${ALIDIST%:*}"
        [[ $ALIDIST_BRANCH == $ALIDIST ]] && ALIDIST_BRANCH= || true
        rm -rf alidist
        git clone ${ALIDIST_BRANCH:+-b "$ALIDIST_BRANCH"} "https://github.com/$ALIDIST_REPO" alidist/ || \
          { git clone "https://github.com/$ALIDIST_REPO" alidist/ && pushd alidist && git checkout "$ALIDIST_BRANCH" && popd; }
        for TAG in $TAGS; do
          VER="${TAG##*=}"
          PKG="${TAG%=*}"
          PKGLOW="$(echo "$PKG"|tr '[:upper:]' '[:lower:]')"
          REPO=$(cat alidist/"$PKGLOW".sh | grep '^source:' | head -n1)
          REPO=${REPO#*:}
          REPO=$(echo $REPO)

          # Use embedded Python script to override tags using aliBuild defaults
          ./alidist-override-tags.py alidist/defaults-${DEFAULTS:-release}.sh $TAGS
          ( cd alidist && git diff )

          git ls-remote --tags "$REPO" | grep "refs/tags/$VER\\$" && { echo "Tag $VER on $PKG exists - skipping"; continue; } || true
          rm -rf "$PKG/"
          git clone $([[ -d /build/mirror/$PKGLOW ]] && echo "--reference /build/mirror/$PKGLOW") "$REPO" "$PKG/"
          pushd "$PKG/"
            if [[ $PKG == AliDPG ]]; then
              DPGBRANCH="${VER%-XX-*}"
              [[ $DPGBRANCH == $VER || $DPGBRANCH == 'v9-99' ]] \
                && { echo "Cannot determine AliDPG branch to tag from $VER: assuming master"; DPGBRANCH=master; } \
                || DPGBRANCH="${DPGBRANCH}-XX"
              git checkout "$DPGBRANCH"
            fi
            git tag "$VER"
            git push origin "$VER"
          popd
          rm -rf "$PKG/"
        done
      '''
    }

    stage "Building"
    withEnv(["TAGS=$TAGS",
             "BUILD_ARCH=$BUILD_ARCH",
             "DEFAULTS=$DEFAULTS",
             "ALIBUILD=$ALIBUILD"]) {
      sh '''
        set -e
        set -o pipefail

        # aliBuild installation using pip
        ALIBUILD_BRANCH="${ALIBUILD##*:}"
        ALIBUILD_REPO="${ALIBUILD%:*}"
        [[ $ALIBUILD_BRANCH == $ALIBUILD ]] && ALIBUILD_BRANCH= || true
        export PYTHONUSERBASE="$PWD/local_python"
        export PATH="$PYTHONUSERBASE/bin:$PATH"
        rm -rf "$PYTHONUSERBASE"
        pip install --user "git+https://github.com/$ALIBUILD_REPO${ALIBUILD_BRANCH:+"@$ALIBUILD_BRANCH"}"
        which aliBuild

        # Prepare scratch directory
        BUILD_DATE=$(echo 2015$(echo "$(date -u +%s) / (86400 * 3)" | bc))
        WORKAREA=/build/workarea/sw/$BUILD_DATE
        WORKAREA_INDEX=0
        CURRENT_SLAVE=unknown
        while [[ "$CURRENT_SLAVE" != '' ]]; do
          WORKAREA_INDEX=$((WORKAREA_INDEX+1))
          CURRENT_SLAVE=$(cat $WORKAREA/$WORKAREA_INDEX/current_slave 2> /dev/null || true)
          [[ "$CURRENT_SLAVE" == "$NODE_NAME" ]] && CURRENT_SLAVE=
        done
        mkdir -p $WORKAREA/$WORKAREA_INDEX
        echo $NODE_NAME > $WORKAREA/$WORKAREA_INDEX/current_slave

        # Actual build of all packages from TAGS
        FETCH_REPOS="$(aliBuild build --help | grep fetch-repos || true)"
        for PKG in $TAGS; do
          BUILDERR=
          aliBuild --reference-sources /build/mirror                       \
                   --debug                                                 \
                   --work-dir "$WORKAREA/$WORKAREA_INDEX"                  \
                   --architecture "$BUILD_ARCH"                            \
                   ${FETCH_REPOS:+--fetch-repos}                           \
                   --jobs 16                                               \
                   --remote-store "rsync://repo.marathon.mesos/store/::rw" \
                   ${DEFAULTS:+--defaults "$DEFAULTS"}                     \
                   build "${PKG%%=*}" || BUILDERR=$?
          [[ $BUILDERR ]] && break || true
        done
        rm -f "$WORKAREA/$WORKAREA_INDEX/current_slave"
        [[ "$BUILDERR" ]] && exit $BUILDERR || true
      '''
    }

  }
}

node("$RUN_ARCH-relval") {

  stage "Waiting for deployment"
  withEnv(["TAGS=$TAGS",
           "CVMFS_NAMESPACE=$CVMFS_NAMESPACE"]) {
    sh '''
      set -e
      set -o pipefail

      MAIN_PKG="${TAGS%%=*}"
      MAIN_VER=$(echo "$TAGS"|cut -d' ' -f1)
      MAIN_VER="${MAIN_VER#*=}"

      SW_COUNT=0
      SW_MAXCOUNT=1200
      CVMFS_SIGNAL="/tmp/${CVMFS_NAMESPACE}.cern.ch.cvmfs_reload /build/workarea/wq/${CVMFS_NAMESPACE}.cern.ch.cvmfs_reload"
      mkdir -p /build/workarea/wq || true
      while [[ $SW_COUNT -lt $SW_MAXCOUNT ]]; do
        ALL_FOUND=1
        for PKG in $TAGS; do
          /cvmfs/${CVMFS_NAMESPACE}.cern.ch/bin/alienv q | \
            grep -E VO_ALICE@"${PKG%%=*}"::"${PKG#*=}" || { ALL_FOUND= ; break; }
        done
        [[ $ALL_FOUND ]] && { echo "All packages ($TAGS) published"; break; } || true
        for S in $CVMFS_SIGNAL; do
          [[ -e $S ]] && true || touch $S
        done
        sleep 1
        SW_COUNT=$((SW_COUNT+1))
      done
      [[ $ALL_FOUND ]] && true || { "Timeout while waiting for packages to be published"; exit 1; }
    '''
  }

  stage "Validating"
  withEnv(["REC_LIMIT_FILES=$REC_LIMIT_FILES",
           "REC_LIMIT_EVENTS=$REC_LIMIT_EVENTS",
           "SIM_NUM_JOBS=$SIM_NUM_JOBS",
           "SIM_EVENTS_PER_JOB=$SIM_EVENTS_PER_JOB",
           "CVMFS_NAMESPACE=$CVMFS_NAMESPACE",
           "DATASET=$DATASET",
           "DRY_RUN=$DRY_RUN",
           "PARSE_ONLY=$PARSE_ONLY",
           "DONT_MENTION=$DONT_MENTION",
           "REQUIRED_SPACE_GB=$REQUIRED_SPACE_GB",
           "REQUIRED_FILES=$REQUIRED_FILES",
           "JIRA_ISSUE=$JIRA_ISSUE",
           "SIM_START_AT=$SIM_START_AT",
           "REC_START_AT=$REC_START_AT",
           "SIM_STOP_AT=$SIM_STOP_AT",
           "REC_STOP_AT=$REC_STOP_AT",
           "JDL_TO_RUN=$JDL_TO_RUN",
           "RELVAL_TIMESTAMP=$RELVAL_TIMESTAMP",
           "RELVAL=$RELVAL",
           "WQ_CATALOG=$WQ_CATALOG",
           "TAGS=$TAGS",
           "SKIP_CHECK_FRAMEWORK=$SKIP_CHECK_FRAMEWORK"]) {
    withCredentials([[$class: 'UsernamePasswordMultiBinding',
                      credentialsId: '369b09bf-5f5e-4b68-832a-2f30cad28755',
                      usernameVariable: 'JIRA_USER',
                      passwordVariable: 'JIRA_PASS']]) {
      sh '''
        set -e
        set +x
        set -o pipefail
        hostname -f

        # Reset locale
        for V in LANG LANGUAGE LC_ALL LC_COLLATE LC_CTYPE LC_MESSAGES LC_MONETARY \
                 LC_NUMERIC LC_TIME LC_ALL; do
          export $V=C
        done

        # Define a unique name for the Release Validation
        RELVAL_NAME="${TAGS//=/-}-${RELVAL_TIMESTAMP}"
        RELVAL_NAME="${RELVAL_NAME// /_}"
        OUTPUT_URL="https://ali-ci.cern.ch/release-validation"
        OUTPUT_XRD="root://eospublic.cern.ch//eos/experiment/alice/release-validation/output"
        echo "Release Validation output on $OUTPUT_URL -- on XRootD: $OUTPUT_XRD"

        # Select the appropriate versions of software to load from CVMFS. We have some workaround
        # to prevent loading AliRoot if AliPhysics is there
        ALIENV_PKGS=
        HAS_ALIPHYSICS=$(echo $TAGS | grep AliPhysics || true)
        for PKG in $TAGS; do
          [[ $HAS_ALIPHYSICS && ${PKG%%=*} == AliRoot ]] && continue || true
          ALIENV_PKGS="${ALIENV_PKGS} $(/cvmfs/${CVMFS_NAMESPACE}.cern.ch/bin/alienv q | \
            grep -E VO_ALICE@"${PKG%%=*}"::"${PKG#*=}" | sort -V | tail -n1)"
        done
        ALIENV_PKGS=$(echo $ALIENV_PKGS)
        echo "We will be loading from /cvmfs/${CVMFS_NAMESPACE}.cern.ch the following packages: ${ALIENV_PKGS}"

        # Install the release-validation package
        RELVAL_BRANCH="${RELVAL##*:}"
        RELVAL_REPO="${RELVAL%:*}"
        [[ $RELVAL_BRANCH == $RELVAL ]] && RELVAL_BRANCH= || true
        rm -rf release-validation/
        git clone --depth 1 "https://github.com/$RELVAL_REPO" ${RELVAL_BRANCH:+-b "$RELVAL_BRANCH"} release-validation/
        export PYTHONUSERBASE=$PWD/local_python
        export PATH=$PYTHONUSERBASE/bin:$PATH
        rm -rf "$PYTHONUSERBASE" && mkdir "$PYTHONUSERBASE"
        pip install --user release-validation/

        # Copy credentials and check validity (assume they are under /secrets). Credentials should
        # be valid for 7 more days from now (we don't want them to expire while we are validating)
        openssl x509 -in /secrets/eos-proxy -noout -subject -enddate -checkend $((86400*7)) || \
          { echo "EOS credentials are no longer valid."; exit 1; }

        # Source utilities file
        source release-validation/relval-jenkins.sh

        # Check EOS quota
        export X509_CERT_DIR="/cvmfs/grid.cern.ch/etc/grid-security/certificates"
        export X509_USER_PROXY=$PWD/eos-proxy
        eos_check_quota "$OUTPUT_XRD" "$REQUIRED_SPACE_GB" "$REQUIRED_FILES"

        # Global exit code
        EXITCODE=0

        # Add overrides to the JDL
        for THIS_JDL in $(echo "${JDL_TO_RUN//,/ }"); do

          if [[ $DRY_RUN == true ]]; then
            DRY_RUN_SWITCH="--dryrun"
            DONT_MENTION=true
          fi
          if [[ $PARSE_ONLY == true ]]; then
            PARSE_ONLY_SWITCH="--parse-only"
            JIRA_ISSUE=
            SKIP_CHECK_FRAMEWORK="true"
          fi

          pushd release-validation/examples/$THIS_JDL &> /dev/null
            echo ""
            echo "=== Starting release validation for $THIS_JDL ==="
            [[ -e "${THIS_JDL}.jdl" ]] || { echo "Cannot find ${THIS_JDL}.jdl"; exit 1; }

            cp -v /secrets/eos-proxy .  # fetch EOS proxy in workdir
            preprocess_jdl "${THIS_JDL}.jdl" "${THIS_JDL}_override.jdl"
            echo "Job type was determined to be: ${JOB_TYPE}"
            echo "=== Environment ==="
            env
            echo "=== Override JDL ==="
            cat "${THIS_JDL}_override.jdl"
            echo "=== Original JDL ==="
            cat "${THIS_JDL}.jdl"
            START_AT=
            [[ $JOB_TYPE == rec ]] && START_AT=$REC_START_AT
            [[ $JOB_TYPE == sim ]] && START_AT=$SIM_START_AT
            STOP_AT=
            [[ $JOB_TYPE == rec ]] && STOP_AT=$REC_STOP_AT
            [[ $JOB_TYPE == sim ]] && STOP_AT=$SIM_STOP_AT

            # Start the Release Validation (notify on JIRA before and after)
            jira_relval_started  "$JIRA_ISSUE" "${TAGS// /, }" "$DONT_MENTION" || true
            THIS_EXITCODE=0
            set -x
            ls -la ~/.globus
            screen -L -d -m /cvmfs/alice.cern.ch/bin/alienv setenv AliEn-ROOT-Legacy/0.0.7-10 -c 'XrdSecDEBUG=1 alien-token-init alienci'
            sleep 5
            cat screenlog.0
            jdl2makeflow ${PARSE_ONLY_SWITCH} ${DRY_RUN_SWITCH} ${START_AT:+--start-at $START_AT} ${STOP_AT:+--stop-at $STOP_AT} --parse --work-dir work --remove --run "${THIS_JDL}.jdl" -T wq -N alirelval_${RELVAL_NAME} -r 3 -C ${WQ_CATALOG} || THIS_EXITCODE=$?
            set +x
            jira_relval_finished "$JIRA_ISSUE" $THIS_EXITCODE "${TAGS// /, }" "$DONT_MENTION" || true
            [[ $THIS_EXITCODE == 0 ]] || EXITCODE=$THIS_EXITCODE  # propagate globally (will cause visible Jenkins error), but continue
          popd &> /dev/null

        done
        exit $EXITCODE
      '''
    }
  }
}
