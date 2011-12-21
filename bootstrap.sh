#!/bin/bash

# Typo3 Bootstrapper Script
# written by Oliver Salzburg
#
# Changelog:
# 1.0.0 - Initial release

set -o nounset
set -o errexit

SELF=`basename $0`

# Show the help for this script
showHelp() {
  cat << EOF
  Usage: $0 [OPTIONS]
  
  Core:
  --help      Display this help and exit.
  --base=PATH The name of the base path where Typo3 should be installed.
              If no base is supplied, "typo3" is used.
EOF
  exit 0
}

# Script Configuration start
# The base directory where Typo3 should be installed
BASE=typo3
# Script Configuration end

# The base location from where to retrieve new versions of this script
UPDATE_BASE=http://hartwig-at.de/fileadmin/t3scripts

# Self-update
runSelfUpdate() {
  echo "Performing self-update..."
  wget --quiet --output-document=$0.tmp $UPDATE_BASE/$SELF
  chmod u+x $0.tmp
  mv $0.tmp $0
  exit 0
}

# Read external configuration (overwrites default, hard-coded configuration)
CONFIG_FILENAME=${SELF:0:${#SELF}-3}.conf
if [ -e "$CONFIG_FILENAME" ]; then
  echo -n "Sourcing script configuration from $CONFIG_FILENAME..."
  source $CONFIG_FILENAME
  echo "Done."
fi

# Read command line arguments (overwrites config file)
for option in $*; do
  case "$option" in
    --help|-h)
      showHelp
      ;;
    --update)
      runSelfUpdate
      ;;
    --base|-b)
      BASE=`echo $option | cut -d'=' -f2`
      ;;
    *)
      echo "Unrecognized option \"$option\""
      exit 1
      ;;
  esac
done

# Update check
SUM_LATEST=$(curl $UPDATE_BASE/versions 2>&1 | grep $SELF | awk '{print $1}')
SUM_SELF=$(md5sum $0 | awk '{print $1}')
if [[ "$SUM_LATEST" != "$SUM_SELF" ]]; then
  echo "NOTE: New version available!"
fi

# Begin main operation

# Name command line arguments
VERSION=$1

# Check for existing installations
if [ -d "$BASE" ]; then
  echo "A directory named $BASE already exists. $SELF will not overwrite existing content."
  echo "Please remove the folder $BASE manually and run this script again."
  exit 1
fi

# The name of the package and the folder it will live in
VERSION_NAME=blankpackage-$VERSION
# The name of the file that contains the package
VERSION_FILENAME=$VERSION_NAME.tar.gz
# The location where the package can be downloaded
TYPO3_DOWNLOAD_URL=http://prdownloads.sourceforge.net/typo3/$VERSION_FILENAME

echo -n "Looking for Typo3 package at $VERSION_FILENAME..."
if [ ! -e "$VERSION_FILENAME" ]; then
  echo "NOT found!"
  echo -n "Downloading $TYPO3_DOWNLOAD_URL..."
  wget --quiet $TYPO3_DOWNLOAD_URL --output-document=$VERSION_FILENAME
else
  echo "Found!"
  echo -n "Trying to resume download from $TYPO3_DOWNLOAD_URL..."
  wget --quiet --continue $TYPO3_DOWNLOAD_URL --output-document=$VERSION_FILENAME
fi
echo "Done."

echo -n "Extracting Typo3 package $VERSION_FILENAME..."
tar --extract --gzip --file $VERSION_FILENAME
mv $VERSION_NAME $BASE
echo "Done."

# vim:ts=2:sw=2:expandtab: