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
             "ALIDIST=$ALIDIST"]) {
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
          sed -e "s/tag:.*/tag: $VER/" "alidist/$PKGLOW.sh" > "alidist/$PKGLOW.sh.0"
          mv "alidist/$PKGLOW.sh.0" "alidist/$PKGLOW.sh"
          git ls-remote --tags "$REPO" | grep "refs/tags/$VER\\$" && { echo "Tag $VER on $PKG exists - skipping"; continue; } || true
          rm -rf "$PKG/"
          git clone $([[ -d /build/mirror/$PKGLOW ]] && echo "--reference /build/mirror/$PKGLOW") "$REPO" "$PKG/"
          pushd "$PKG/"
            if [[ $PKG == AliDPG ]]; then
              DPGBRANCH="${VER%-XX-*}"
              [[ $DPGBRANCH != $VER ]] || { echo "Cannot determine AliDPG branch to tag from $VER - aborting"; exit 1; }
              DPGBRANCH="${DPGBRANCH}-XX"
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
        export PYTHONUSERBASE="$PWD/python"
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

  stage "Checking framework"
  if ("$SKIP_CHECK_FRAMEWORK" == "true") {
    println("Skipping as per user request")
  }
  else {
    sh '''
      set -e
      set -o pipefail
      curl -X DELETE -H "Content-type: application/json" "http://leader.mesos:8080/v2/apps/wqmesos/tasks?scale=true"
      curl -X DELETE -H "Content-type: application/json" "http://leader.mesos:8080/v2/apps/wqcatalog/tasks?scale=true"
      curl -X PUT -H "Content-type: application/json" --data '{ "instances": 1 }' "http://leader.mesos:8080/v2/apps/wqcatalog?force=true"
      sleep 90
      curl -X PUT -H "Content-type: application/json" --data '{ "instances": 1 }' "http://leader.mesos:8080/v2/apps/wqmesos?force=true"
    '''
  }

  stage "Validating"
  withEnv(["LIMIT_FILES=$LIMIT_FILES",
           "LIMIT_EVENTS=$LIMIT_EVENTS",
           "CVMFS_NAMESPACE=$CVMFS_NAMESPACE",
           "DATASET=$DATASET",
           "MONKEYPATCH_TARBALL_URL=$MONKEYPATCH_TARBALL_URL",
           "REQUIRED_SPACE_GB=$REQUIRED_SPACE_GB",
           "REQUIRED_FILES=$REQUIRED_FILES",
           "JIRA_ISSUE=$JIRA_ISSUE",
           "JDL_TO_RUN=$JDL_TO_RUN",
           "RELVAL_TIMESTAMP=$RELVAL_TIMESTAMP",
           "TAGS=$TAGS"]) {
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
        OUTPUT_URL="https://ali-ci.cern.ch/release-validation/$RELVAL_NAME"
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
        git clone "https://github.com/$RELVAL_REPO" ${RELVAL_BRANCH:+-b "$RELVAL_BRANCH"} release-validation/
        export PYTHONUSERBASE=$PWD/python
        export PATH=$PYTHONUSERBASE/bin:$PATH
        rm -rf python && mkdir python
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

        # Determine the JDL to use
        cd release-validation/examples/$JDL_TO_RUN
        JDL=$(echo *.jdl)
        [[ -e $JDL ]] || { echo "Cannot find a JDL"; exit 1; }
        cp -v /secrets/eos-proxy .  # fetch EOS proxy in workdir

        if grep -q 'aliroot_dpgsim.sh' "$JDL"; then
          # JDL belongs to a Monte Carlo
          OUTPUT_URL="${OUTPUT_URL}/MC"
          [[ $LIMIT_FILES -ge 1 && $LIMIT_EVENTS -ge 1 ]] || { echo "LIMIT_FILES and LIMIT_EVENTS are wrongly set"; exit 1; }
          echo "Split_override = \\"production:1-${LIMIT_FILES}\\";" >> $JDL
          echo "SplitArguments_replace = { \\"--nevents\\\\\\s[0-9]+\\", \\"--nevents ${LIMIT_EVENTS}\\" };" >> $JDL
          echo "OutputDir_override = \\"${OUTPUT_XRD}/${RELVAL_NAME}/MC/#alien_counter_04i#\\";" >> $JDL
          echo "EnvironmentCommand = \\"export PACKAGES=\\\\\\"$ALIENV_PKGS\\\\\\"; export CVMFS_NAMESPACE=alice-nightlies; source custom_environment.sh; type aliroot\\";"
        else
          # Other JDL: not supported at the moment
          echo "This JDL does not belong to a Monte Carlo. Not supported."
          exit 1
        fi

        # Start the Release Validation (notify on JIRA before and after)
        jira_relval_started  "$JIRA_ISSUE" "$OUTPUT_URL" "${TAGS// /, }" false || true
        jdl2makeflow --force --run $JDL -T wq -N alirelval_${RELVAL_NAME} -r 3 -C wqcatalog.marathon.mesos:9097 || RV=$?
        jira_relval_finished "$JIRA_ISSUE" $RV "$OUTPUT_URL" "${TAGS// /, }" false || true
        exit $RV
      '''
    }
  }
}
