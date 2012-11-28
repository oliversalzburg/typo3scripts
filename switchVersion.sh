#!/bin/bash

# TYPO3 Version Switching Script
# written by Oliver Salzburg

set -o nounset
set -o errexit

SELF=$(basename "$0")

# Show the help for this script
function showHelp() {
  cat << EOF
  Usage: $0 [OPTIONS]
  
  Core:
  --help              Display this help and exit.
  --verbose           Display more detailed messages.
  --quiet             Do not display anything.
  --force             Perform actions that would otherwise abort the script.
  --update            Tries to update the script to the latest version.
  --update-check      Checks if a newer version of the script is available.
  --export-config     Prints the default configuration of this script.
  --extract-config    Extracts configuration parameters from TYPO3.
  --base=PATH         The name of the base path where TYPO3 is 
                      installed. If no base is supplied, "typo3" is used.
  
  Options:
  --version=VERSION   The version to switch to.
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
REQUIRED_ARGUMENT_COUNT=0
if [[ $# -lt $REQUIRED_ARGUMENT_COUNT ]]; then
  echo "Insufficient command line arguments!" >&2
  echo "Use $0 --help to get additional information." >&2
  exit 1
fi

# Script Configuration start
# Should the script give more detailed feedback?
VERBOSE=false
# Should the script surpress all feedback?
QUIET=false
# Should the script ignore reasons that would otherwise cause it to abort?
FORCE=false
# The base directory where TYPO3 is installed
BASE=typo3
# The version to switch to
VERSION=6.0.0
# Script Configuration end

function consoleWrite() {
  [ "false" == "$QUIET" ] && echo -n $* >&2
  return 0
}
function consoleWriteLine() {
  [ "false" == "$QUIET" ] && echo $* >&2
  return 0
}
function consoleWriteVerbose() {
  $VERBOSE && consoleWrite $*
  return 0
}
function consoleWriteLineVerbose() {
  $VERBOSE && consoleWriteLine $*
  return 0
}

# The base location from where to retrieve new versions of this script
UPDATE_BASE=http://typo3scripts.googlecode.com/svn/trunk

# Update check
function updateCheck() {
  if ! hash curl 2>&-; then
    consoleWriteLine "Update checking requires curl. Check skipped."
    return 2
  fi
  
  SUM_LATEST=$(curl $UPDATE_BASE/versions 2>&1 | grep $SELF | awk '{print $2}')
  SUM_SELF=$(tail --lines=+2 "$0" | md5sum | awk '{print $1}')
  
  consoleWriteLineVerbose "Remote hash source: '$UPDATE_BASE/versions'"
  consoleWriteLineVerbose "Own hash: '$SUM_SELF' Remote hash: '$SUM_LATEST'"
  
  if [[ "" == $SUM_LATEST ]]; then
    consoleWriteLine "No update information is available for '$SELF'"
    consoleWriteLine "Please check the project home page 'http://code.google.com/p/typo3scripts/'."
    return 2
    
  elif [[ "$SUM_LATEST" != "$SUM_SELF" ]]; then
    consoleWriteLine "NOTE: New version available!"
    return 1
  fi
  
  return 0
}

# Self-update
function runSelfUpdate() {
  echo "Performing self-update..."
  
  _tempFileName="$0.tmp"
  _payloadName="$0.payload"
  
  # Download new version
  echo -n "Downloading latest version..."
  if ! wget --quiet --output-document="$_payloadName" $UPDATE_BASE/$SELF ; then
    echo "Failed: Error while trying to wget new version!"
    echo "File requested: $UPDATE_BASE/$SELF"
    exit 1
  fi
  echo "Done."
  
  # Restore shebang
  _interpreter=$(head --lines=1 "$0")
  echo $_interpreter > "$_tempFileName"
  tail --lines=+2 "$_payloadName" >> "$_tempFileName"
  rm "$_payloadName"
  
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
  echo "Done."
  echo "Update complete."
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
  consoleWriteVerbose "Sourcing script configuration from $BASE_CONFIG_FILENAME..."
  source $BASE_CONFIG_FILENAME
  consoleWriteLineVerbose "Done."
fi

# Read external configuration - Stage 2 - script-specific (overwrites default, hard-coded configuration)
CONFIG_FILENAME=${SELF:0:${#SELF}-3}.conf
if [[ -e "$CONFIG_FILENAME" ]]; then
  consoleWriteVerbose "Sourcing script configuration from $CONFIG_FILENAME..."
  source $CONFIG_FILENAME
  consoleWriteLineVerbose "Done."
fi

# Read command line arguments (overwrites config file)
for option in $*; do
  case "$option" in
    --verbose)
      VERBOSE=true
      ;;
    --quiet)
      QUIET=true
      ;;
    --force)
      FORCE=true
      ;;
    --update)
      runSelfUpdate
      ;;
    --update-check)
      updateCheck
      exit $?
      ;;
    --export-config)
      exportConfig
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
  consoleWriteVerbose "Checking dependency '$1' => "
  if ! hash $1 2>&-; then
    consoleWriteLine "Failed!"
    consoleWriteLine "This script requires '$1' but it can not be found. Aborting."
    exit 1
  fi
  consoleWriteLineVerbose $(which $1)
  return 0
}
consoleWrite "Checking dependencies..."
consoleWriteLineVerbose
checkDependency wget
checkDependency curl
checkDependency md5sum
checkDependency grep
checkDependency awk
checkDependency tar
consoleWriteLine "Succeeded."

# Begin main operation

# Check default argument validity
if [[ $VERSION == --* ]]; then
  consoleWriteLine "The given TYPO3 version '$VERSION' looks like a command line parameter."
  consoleWriteLine "Please use --help to see a list of available command line parameters."
  exit 1
fi

# The name of the package
VERSION_NAME=typo3_src-$VERSION
# The name of the file that contains the package
VERSION_FILENAME=$VERSION_NAME.tar.gz
# The location where the package can be downloaded
TYPO3_DOWNLOAD_URL=http://prdownloads.sourceforge.net/typo3/$VERSION_FILENAME
VERSION_FILE=$BASE/$VERSION_FILENAME
VERSION_DIRNAME=typo3_src-$VERSION
VERSION_DIR=$BASE/$VERSION_DIRNAME/
SYMLINK=$BASE/typo3_src

consoleWriteVerbose "Looking for TYPO3 source package at '$VERSION_DIR'..."
if [[ -d "$VERSION_DIR" ]]; then
  consoleWriteLineVerbose "Found!"
else
  # Retrieve TYPO3 source package
  if [[ -e "$VERSION_FILE" ]]; then
    consoleWriteLineVerbose "NOT found!"
    consoleWriteLine "Archive already exists. Trying to resume download."
    consoleWrite "Downloading $TYPO3_DOWNLOAD_URL..."
    if ! wget --quiet --continue $TYPO3_DOWNLOAD_URL --output-document=$VERSION_FILE; then
      consoleWriteLine "Failed!"
      exit 1
    fi
  else
    consoleWriteLineVerbose "NOT found! Downloading."
    consoleWrite "Downloading $TYPO3_DOWNLOAD_URL..."
    if ! wget --quiet $TYPO3_DOWNLOAD_URL --output-document=$VERSION_FILE; then
      consoleWriteLine "Failed!"
      exit 1
    fi
  fi
  consoleWriteLine "Done."

  consoleWrite "Extracting source package $VERSION_FILE..."
  if ! tar --extract --gzip --directory $BASE --file $VERSION_FILE; then
    consoleWriteLine "Failed!"
    exit 1
  fi
  consoleWriteLine "Done."
fi

# Switch symlink
consoleWrite "Switching TYPO3 source symlink to $VERSION_DIR..."
if ! rm --force -- $SYMLINK; then
  consoleWriteLine "Failed! Unable to remove old symlink '$SYMLINK'"
  exit 1
fi
if ! ln --symbolic $VERSION_DIRNAME $SYMLINK; then
  consoleWriteLine "Failed! Unable to create new symlink '$SYMLINK'"
  exit 1
fi
consoleWriteLine "Done."

# Check if index.php is a file or a symlink
# If it is a file, it is an indication of a bootstrap.sh installation using
# the --fix-indexphp parameter.
INDEX_PHP=$BASE/index.php
INDEX_TARGET=$SYMLINK/index.php
consoleWriteVerbose "Checking if index.php needs to be updated..."
if [[ -h "$INDEX_PHP" ]]; then
  rm -f "$INDEX_PHP"
  cp "$INDEX_TARGET" "$INDEX_PHP"
  consoleWriteLineVerbose "Done."
else
  consoleWriteLineVerbose "Skipped."
fi

# Delete old, cached files
consoleWriteVerbose "Deleting temp_CACHED_* files from typo3conf..."
if ! rm --force -- $BASE/typo3conf/temp_CACHED_*; then
  consoleWriteLineVerbose "Failed!"
  # No need to exit. Failing to delete cache files is not critical to operation
fi

consoleWriteLine "Done!"
consoleWriteLine "Version switched to $VERSION."

# vim:ts=2:sw=2:expandtab: