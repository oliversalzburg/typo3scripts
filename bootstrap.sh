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
  --help              Display this help and exit.
  --update            Tries to update the script to the latest version.
  --base=PATH         The name of the base path where Typo3 should be
                      installed. If no base is supplied, "typo3" is used.
              
  Options:
  --version=VERSION   The version to install.
  
  Database:
  --hostname=HOST     The name of the host where the Typo3 database is running.
  --username=USER     The username to use when connecting to the Typo3
                      database.
  --password=PASSWORD The password to use when connecting to the Typo3
                      database.
  --database=DB       The name of the database in which Typo3 is stored.
              
  Note: When using an external configuration file, it is sufficient to supply
        just the target version as a parameter.
        When supplying any command line argument, supply the target version
        through the --version command line parameter.
EOF
  exit 0
}

# Check on minimal command line argument count
REQUIRED_ARGUMENT_COUNT=1
if [ $# -lt $REQUIRED_ARGUMENT_COUNT ]; then
  echo "Insufficient command line arguments!"
  echo "Use $0 --help to get additional information."
  exit -1
fi

# Script Configuration start
# The base directory where Typo3 should be installed
BASE=typo3
# The version to install
VERSION=$1
# The hostname of the MySQL server that Typo3 uses
HOST=localhost
# The username used to connect to that MySQL server
USER=*username*
# The password for that user
PASS=*password*
# The name of the database in which Typo3 is stored
DB=typo3
# Script Configuration end

# The base location from where to retrieve new versions of this script
UPDATE_BASE=http://typo3scripts.googlecode.com/svn/trunk

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
    --base=*)
      BASE=`echo $option | cut -d'=' -f2`
      ;;
    --version=*)
      VERSION=`echo $option | cut -d'=' -f2`
      ;;
    --hostname=*)
      HOST=`echo $option | cut -d'=' -f2`
      ;;
    --username=*)
      USER=`echo $option | cut -d'=' -f2`
      ;;
    --password=*)
      PASS=`echo $option | cut -d'=' -f2`
      ;;
    --database=*)
      DB=`echo $option | cut -d'=' -f2`
      ;;
    *)
      VERSION=$option
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

# Generate configuration
echo -n "Generating localconf.php..."
TYPO3_CONFIG=
TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db_username = '$USER';\n"
TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db_password = '$PASS';\n"
TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db_host     = '$HOST';\n"
TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db          = '$DB';\n"
# Write configuration
cp $BASE/typo3conf/localconf.php $BASE/typo3conf/localconf.php.orig
sed "/^## INSTALL SCRIPT EDIT POINT TOKEN/a $TYPO3_CONFIG" $BASE/typo3conf/localconf.php.orig > $BASE/typo3conf/localconf.php
echo "Done."

# vim:ts=2:sw=2:expandtab: