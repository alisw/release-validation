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
        git clone "https://github.com/$ALIDIST_REPO" ${ALIDIST_BRANCH:+-b "$ALIDIST_BRANCH"} alidist/
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
          git clone --reference /build/mirror/$PKGLOW "$REPO" "$PKG/"
          pushd "$PKG/"
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

        # Actual build
        MAIN_PKG="${TAGS%%=*}"
        MAIN_VER=$(echo "$TAGS"|cut -d' ' -f1)
        MAIN_VER="${MAIN_VER#*=}"
        aliBuild --reference-sources /build/mirror                       \
                 --debug                                                 \
                 --work-dir "$WORKAREA/$WORKAREA_INDEX"                  \
                 --architecture "$BUILD_ARCH"                            \
                 --jobs 16                                               \
                 --remote-store "rsync://repo.marathon.mesos/store/::rw" \
                 ${DEFAULTS:+--defaults "$DEFAULTS"}                     \
                 build "$MAIN_PKG" || BUILDERR=$?
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
        /cvmfs/${CVMFS_NAMESPACE}.cern.ch/bin/alienv q | grep -E VO_ALICE@"$MAIN_PKG"::"$MAIN_VER"-'[0-9]' && { echo "Package published"; FOUND=1; break; }
        echo "Not found"
        for S in $CVMFS_SIGNAL; do
          [[ -e $S ]] && true || touch $S
        done
        sleep 1
        SW_COUNT=$((SW_COUNT+1))
      done
      [[ $FOUND ]] && true || { "Timeout waiting for publishing"; exit 1; }
    '''
  }

  stage "Validating"
  withEnv(["RELVAL_ALIPHYSICS_REF=$RELVAL_ALIPHYSICS_REF",
           "LIMIT_FILES=$LIMIT_FILES",
           "LIMIT_EVENTS=$LIMIT_EVENTS",
           "CVMFS_NAMESPACE=$CVMFS_NAMESPACE",
           "DATASET=$DATASET",
           "MONKEYPATCH_TARBALL_URL=$MONKEYPATCH_TARBALL_URL",
           "REQUIRED_SPACE_GB=$REQUIRED_SPACE_GB",
           "EXTRA_VARIABLES=$EXTRA_VARIABLES",
           "JIRA_ISSUE=$JIRA_ISSUE",
           "SUMMARIZE_ONLY=$SUMMARIZE_ONLY",
           "RELVAL_TIMESTAMP=$RELVAL_TIMESTAMP",
           "TAGS=$TAGS"]) {
    withCredentials([[$class: 'UsernamePasswordMultiBinding',
                      credentialsId: '369b09bf-5f5e-4b68-832a-2f30cad28755',
                      usernameVariable: 'JIRA_USER',
                      passwordVariable: 'JIRA_PASS']]) {
      sh '''
        set -e
        set -o pipefail

        MAIN_PKG="${TAGS%%=*}"
        [[ $MAIN_PKG == AliPhysics ]]
        MAIN_VER=$(echo "$TAGS"|cut -d' ' -f1)
        MAIN_VER="${MAIN_VER#*=}"
        ALIPHYSICS_VERSION=$(/cvmfs/${CVMFS_NAMESPACE}.cern.ch/bin/alienv q | grep -E VO_ALICE@"$MAIN_PKG"::"$MAIN_VER"-'[0-9]$' | sort -V | tail -n1)
        export ALIPHYSICS_VERSION="${ALIPHYSICS_VERSION##*:}"
        [[ $ALIPHYSICS_VERSION ]]

        RELVAL_BRANCH="${RELVAL##*:}"
        RELVAL_REPO="${RELVAL%:*}"
        [[ $RELVAL_BRANCH == $RELVAL ]] && RELVAL_BRANCH= || true
        git clone "https://github.com/$RELVAL_REPO" ${RELVAL_BRANCH:+-b "$RELVAL_BRANCH"} release-validation/

        echo "We will be using AliPhysics $ALIPHYSICS_VERSION with the following environment"
        env
        release-validation/relval-jenkins.sh
      '''
    }
  }
}
