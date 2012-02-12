#!/bin/bash

# TYPO3 Version Switching Script
# written by Oliver Salzburg

set -o nounset
set -o errexit

SELF=$(basename "$0")

# Show the help for this script
function showHelp() {
  cat << EOF
  Usage: $0 [OPTIONS --version=<VERSION>]|<VERSION>
  
  Core:
  --help            Display this help and exit.
  --update          Tries to update the script to the latest version.
  --base=PATH       The name of the base path where TYPO3 is installed.
                    If no base is supplied, "typo3" is used.
  --export-config   Prints the default configuration of this script.
  --extract-config  Extracts configuration parameters from TYPO3.
  
  Options:
  --version=VERSION The version to switch to.
  
  Note: When using an external configuration file, it is sufficient to supply
        just the target version as a parameter.
        When supplying any other command line argument, supply the target
        version through the --version command line parameter.
EOF
}

# Print the default configuration to ease creation of a config file.
function exportConfig() {
  # Spaces are escaped here to avoid sed matching this line when exporting the
  # configuration
  sed -n "/#\ Script\ Configuration\ start/,/# Script Configuration end/p" "$0"
}

# Extract all known (database related) parameters from the TYPO3 configuration.
function extractConfig() {
  LOCALCONF="$BASE/typo3conf/localconf.php"
  
  echo HOST=$(tac $LOCALCONF | grep --perl-regexp --only-matching "(?<=typo_db_host = ')[^']*(?=';)")
  echo USER=$(tac $LOCALCONF | grep --perl-regexp --only-matching "(?<=typo_db_username = ')[^']*(?=';)")
  echo PASS=$(tac $LOCALCONF | grep --perl-regexp --only-matching "(?<=typo_db_password = ')[^']*(?=';)")
  echo DB=$(tac $LOCALCONF | grep --perl-regexp --only-matching "(?<=typo_db = ')[^']*(?=';)")
}

# Check on minimal command line argument count
REQUIRED_ARGUMENT_COUNT=1
if [[ $# -lt $REQUIRED_ARGUMENT_COUNT ]]; then
  echo "Insufficient command line arguments!"
  echo "Use $0 --help to get additional information."
  exit 1
fi

# Script Configuration start
# The base directory where TYPO3 is installed
BASE=typo3
# The version to switch to
VERSION=$1
# Script Configuration end

# The base location from where to retrieve new versions of this script
UPDATE_BASE=http://typo3scripts.googlecode.com/svn/trunk

# Self-update
function runSelfUpdate() {
  echo "Performing self-update..."
  
  _tempFileName="$0.tmp"
  
  # Download new version
  echo -n "Downloading latest version..."
  if ! wget --quiet --output-document="$_tempFileName" $UPDATE_BASE/$SELF ; then
    echo "Failed: Error while trying to wget new version!"
    echo "File requested: $UPDATE_BASE/$SELF"
    exit 1
  fi
  echo "Done."
  
  # Copy over modes from old version
  OCTAL_MODE=$(stat -c '%a' $SELF)
  if ! chmod $OCTAL_MODE "$_tempFileName" ; then
    echo "Failed: Error while trying to set mode on $_tempFileName."
    exit 1
  fi
  
  # Spawn update script
  cat > updateScript.sh << EOF
#!/bin/bash
# Overwrite old file with new
if mv "$_tempFileName" "$0"; then
  echo "Done. Update complete."
  rm -- \$0
else
  echo "Failed!"
fi
EOF
  
  echo -n "Inserting update process..."
  exec /bin/bash updateScript.sh
}

# Make a quick run through the command line arguments to see if the user wants
# to print the help. This saves us a lot of headache with respecting the order
# in which configuration parameters have to be overwritten.
for option in $*; do
  case "$option" in
    --help|-h)
      showHelp
      exit 0
      ;;
  esac
done

# Read external configuration - Stage 1 - typo3scripts.conf (overwrites default, hard-coded configuration)
BASE_CONFIG_FILENAME="typo3scripts.conf"
if [[ -e "$BASE_CONFIG_FILENAME" ]]; then
  echo -n "Sourcing script configuration from $BASE_CONFIG_FILENAME..."
  source $BASE_CONFIG_FILENAME
  echo "Done."
fi

# Read external configuration - Stage 2 - script-specific (overwrites default, hard-coded configuration)
CONFIG_FILENAME=${SELF:0:${#SELF}-3}.conf
if [[ -e "$CONFIG_FILENAME" ]]; then
  echo -n "Sourcing script configuration from $CONFIG_FILENAME..."
  source $CONFIG_FILENAME
  echo "Done."
fi

# Read command line arguments (overwrites config file)
for option in $*; do
  case "$option" in
    --update)
      runSelfUpdate
      ;;
    --base=*)
      BASE=$(echo $option | cut -d'=' -f2)
      ;;
    --export-config)
      exportConfig
      exit 0
      ;;
    --extract-config)
      extractConfig
      exit 0
      ;;
    --version=*)
      VERSION=$(echo $option | cut -d'=' -f2)
      ;;
    *)
      VERSION=$option
      ;;
  esac
done

# Check for dependencies
function checkDependency() {
  if ! hash $1 2>&-; then
    echo "Failed!"
    echo "This script requires '$1' but it can not be found. Aborting." >&2
    exit 1
  fi
}
echo -n "Checking dependencies..."
checkDependency wget
checkDependency curl
checkDependency md5sum
checkDependency grep
checkDependency awk
checkDependency tar
echo "Succeeded."

# Update check
SUM_LATEST=$(curl $UPDATE_BASE/versions 2>&1 | grep $SELF | awk '{print $1}')
SUM_SELF=$(md5sum "$0" | awk '{print $1}')
if [[ "" == $SUM_LATEST ]]; then
  echo "No update information is available for '$SELF'" >&2
  echo "Please check the project home page http://code.google.com/p/typo3scripts/." >&2
  
elif [[ "$SUM_LATEST" != "$SUM_SELF" ]]; then
  echo "NOTE: New version available!" >&2
fi

# Begin main operation

# Check argument validity
if [[ $VERSION == --* ]]; then
  echo "The given TYPO3 version '$VERSION' looks like a command line parameter."
  echo "Please use the --version parameter when giving multiple arguments."
  exit 1
fi

VERSION_FILENAME=typo3_src-$VERSION.tar.gz
TYPO3_DOWNLOAD_URL=http://prdownloads.sourceforge.net/typo3/$VERSION_FILENAME
VERSION_FILE=$BASE/$VERSION_FILENAME
VERSION_DIRNAME=typo3_src-$VERSION
VERSION_DIR=$BASE/$VERSION_DIRNAME/
SYMLINK=$BASE/typo3_src

echo -n "Looking for TYPO3 source package at $VERSION_DIR..."
if [[ -d "$VERSION_DIR" ]]; then
  echo "Found!"
else
  # Retrieve TYPO3 source package
  if [[ -e "$VERSION_FILE" ]]; then
    echo "NOT found!"
    echo "Archive already exists. Trying to resume download."
    echo -n "Downloading $TYPO3_DOWNLOAD_URL..."
    if ! wget --quiet --continue $TYPO3_DOWNLOAD_URL --output-document=$VERSION_FILE; then
      echo "Failed!"
      exit 1
    fi
  else
    echo "NOT found! Downloading."
    echo -n "Downloading $TYPO3_DOWNLOAD_URL..."
    if ! wget --quiet $TYPO3_DOWNLOAD_URL --output-document=$VERSION_FILE; then
      echo "Failed!"
      exit 1
    fi
  fi
  echo "Done."

  echo -n "Extracting source package $VERSION_FILE..."
  if ! tar --extract --gzip --directory $BASE --file $VERSION_FILE; then
    echo "Failed!"
    exit 1
  fi
  echo "Done."
fi

# Switch symlink
echo -n "Switching TYPO3 source symlink to $VERSION_DIR..."
if ! rm --force -- $SYMLINK; then
  echo "Failed! Unable to remove old symlink '$SYMLINK'"
  exit 1
fi
if ! ln --symbolic $VERSION_DIRNAME $SYMLINK; then
  echo "Failed! Unable to create new symlink '$SYMLINK'"
  exit 1
fi
echo "Done."

# Check if index.php is a file or a symlink
# If it is a file, it is an indication of a bootstrap.sh installation using
# the --fix-indexphp parameter.
INDEX_PHP=$BASE/index.php
INDEX_TARGET=$SYMLINK/index.php
echo -n "Checking if index.php needs to be updated..."
if [[ -h "$INDEX_PHP" ]]; then
  rm -f "$INDEX_PHP"
  cp "$INDEX_TARGET" "$INDEX_PHP"
  echo "Done."
else
  echo "Skipped."
fi


# Delete old, cached files
echo -n "Deleting temp_CACHED_* files from typo3conf..."
if ! rm --force -- $BASE/typo3conf/temp_CACHED_*; then
  echo "Failed!"
  # No need to exit. Failing to delete cache files is not critical to operation
fi

echo "Done!"
echo "Version switched to $VERSION."

# vim:ts=2:sw=2:expandtab: