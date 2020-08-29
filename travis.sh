#!/bin/bash

download_nightly() {
  if [[ "$TRAVIS_OS_NAME" == "linux" ]]
  then
    if [[ "$TRAVIS_CPU_ARCH" == "amd64" ]]
    then
      local SUFFIX="linux_x64\.tar\.xz"
    else
      local SUFFIX="linux_${TRAVIS_CPU_ARCH}\.tar\.xz"
    fi
  elif [[ "$TRAVIS_OS_NAME" == "osx" ]]
  then
    local SUFFIX="osx\.tar\.xz"
  elif [[ "$TRAVIS_OS_NAME" == "windows" ]]
  then
    local SUFFIX="windows_x64\.zip"
  fi

  if [[ ! -z "$SUFFIX" ]]
  then
    # Fetch nightly download url. This is subject to API rate limiting, so may fail
    # intermittently, in which case the script will fallback to building nim.
    local NIGHTLY_API_URL=https://api.github.com/repos/nim-lang/nightlies/releases

    local NIGHTLY_DOWNLOAD_URL=$(curl $NIGHTLY_API_URL -SsLf \
      | grep "\"browser_download_url\": \".*${SUFFIX}\"" \
      | head -n 1 \
      | sed -n 's/".*\(https:.*\)".*/\1/p')
  fi

  if [[ ! -z "$NIGHTLY_DOWNLOAD_URL" ]]
  then
    local NIGHTLY_ARCHIVE=$(basename $NIGHTLY_DOWNLOAD_URL)
    curl $NIGHTLY_DOWNLOAD_URL -SsLf > $NIGHTLY_ARCHIVE
  else
    echo "No nightly build available for $TRAVIS_OS_NAME $TRAVIS_CPU_ARCH"
  fi

  if [[ ! -z "$NIGHTLY_ARCHIVE" && -f "$NIGHTLY_ARCHIVE" ]]
  then
    rm -Rf $HOME/Nim-devel
    mkdir -p $HOME/Nim-devel
    tar -xf $NIGHTLY_ARCHIVE -C $HOME/Nim-devel --strip-components=1
    rm $NIGHTLY_ARCHIVE
    export PATH="$HOME/Nim-devel/bin:$PATH"
    echo "Installed nightly build $NIGHTLY_DOWNLOAD_URL"
    return 1
  fi

  return 0
}


build_nim () {
  if [[ "$BRANCH" == "devel" ]]
  then
    if [[ "$BUILD_NIM" != 1 ]]
    then
      # If not forcing build, download nightly build
      download_nightly
      local DOWNLOADED=$?
      if [[ "$DOWNLOADED" == "1" ]]
      then
        # Nightly build was downloaded
        return
      fi
    fi
    # Note: don't cache $HOME/Nim-devel in .travis.yml
    local NIMREPO=$HOME/Nim-devel
  else
    # Cache $HOME/.choosenim in .travis.yml to avoid rebuilding
    local NIMREPO=$HOME/.choosenim/toolchains/nim-$BRANCH-$TRAVIS_CPU_ARCH
  fi

  export PATH=$NIMREPO/bin:$PATH

  if [[ -f "$NIMREPO/bin/nim" ]]
  then
    echo "Using cached nim $NIMREPO"
  else
    echo "Building nim $BRANCH"
    if [[ "$BRANCH" =~ [0-9] ]]
    then
      local GITREF="v$BRANCH" # version tag
    else
      local GITREF=$BRANCH
    fi
    git clone -b $GITREF --single-branch https://github.com/nim-lang/Nim.git $NIMREPO
    cd $NIMREPO
    sh build_all.sh
    cd -
  fi
}


use_choosenim () {
  local GITBIN=$HOME/.choosenim/git/bin
  export CHOOSENIM_CHOOSE_VERSION="$BRANCH --latest"
  export CHOOSENIM_NO_ANALYTICS=1
  export PATH=$HOME/.nimble/bin:$GITBIN:$PATH
  if ! type -P choosenim &> /dev/null
  then
    echo "Installing choosenim"

    mkdir -p $GITBIN
    if [[ "$TRAVIS_OS_NAME" == "windows" ]]
    then
      export EXT=.exe
      # Setup git outside "Program Files", space breaks cmake sh.exe
      cd $GITBIN/..
      curl -L -s "https://github.com/git-for-windows/git/releases/download/v2.23.0.windows.1/PortableGit-2.23.0-64-bit.7z.exe" -o portablegit.exe
      7z x -y -bd portablegit.exe
      cd -
    fi

    curl https://nim-lang.org/choosenim/init.sh -sSf > init.sh
    sh init.sh -y
    cp $HOME/.nimble/bin/choosenim$EXT $GITBIN/.

    # Copy DLLs for choosenim
    if [[ "$TRAVIS_OS_NAME" == "windows" ]]
    then
      cp $HOME/.nimble/bin/*.dll $GITBIN/.
    fi
  else
    echo "choosenim already installed"
    rm -rf $HOME/.choosenim/current
    choosenim update $BRANCH --latest
    choosenim $BRANCH
  fi
}

if [[ "$TRAVIS_OS_NAME" == "osx" ]]
then
  # Work around https://github.com/nim-lang/Nim/issues/12337 fixed in 1.0+
  ulimit -n 8192
fi

# Autodetect whether to build nim or use choosenim, based on architecture.
# Force nim build with BUILD_NIM=1
# Force choosenim with USE_CHOOSENIM=1
if [[ ( "$TRAVIS_CPU_ARCH" != "amd64" || "$BUILD_NIM" == "1" ) && "$USE_CHOOSENIM" != "1" ]]
then
  build_nim
else
  use_choosenim
fi