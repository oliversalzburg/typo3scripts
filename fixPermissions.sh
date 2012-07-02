#!/bin/bash

# TYPO3 Permission Fix Script
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
  --owner=OWNER       The name of the user that owns the installation.
  --httpd-group=GROUP The user group the local HTTP daemon is running as.
  --fix-indexphp      Replaces the index.php symlink with the actual file.
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
# The base directory where TYPO3 should be installed
BASE=typo3
# The owner of the TYPO3 installation
OWNER=$(id --user --name)
# The group the local http daemon is running as (usually www-data or apache)
HTTPD_GROUP=www-data
# Should the index.php symlink be replaced by the actual file?
FIX_INDEXPHP=false
# Script Configuration end

# Pre-initialize the owner to the user that called sudo (if applicable)
if [[ "$(id -u)" == "0" ]]; then
  OWNER=$SUDO_USER
fi

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
    consoleWriteLine "Update checking requires curl. Check skipped." >&2
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
    --owner=*)
      OWNER=$(echo $option | cut -d'=' -f2)
      ;;
    --httpd-group=*)
      HTTPD_GROUP=$(echo $option | cut -d'=' -f2)
      ;;
    --fix-indexphp)
      FIX_INDEXPHP=true
      ;;
    *)
      VERSION=$option
      ;;
  esac
done

# Check for dependencies
function checkDependency() {
  $VERBOSE && echo -n "Checking dependency '$1' => " >&2
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
checkDependency chown
checkDependency chgrp
checkDependency chmod
consoleWriteLine "Succeeded."

# Begin main operation
consoleWrite "Changing ownership of '$BASE' to '$OWNER'..."
sudo chown --recursive $OWNER $BASE
consoleWriteLine "Done"

consoleWrite "Changing owning group of essential TYPO3 folders to '$HTTPD_GROUP'..."
sudo chgrp --recursive $HTTPD_GROUP $BASE $BASE/fileadmin $BASE/typo3temp $BASE/typo3conf $BASE/uploads
consoleWriteLine "Done"

consoleWrite "Changing access permissions for essential TYPO3 folders..."
sudo chmod --recursive g+rwX,o-w $BASE/fileadmin $BASE/typo3temp $BASE/typo3conf $BASE/uploads
consoleWriteLine "Done"

consoleWrite "Fixing access to common files..."
sudo chgrp $HTTPD_GROUP $BASE/.htaccess $BASE/.htpasswd $BASE/favicon.ico
sudo chmod g+r $BASE/.htaccess $BASE/.htpasswd $BASE/favicon.ico
consoleWriteLine "Done"

consoleWrite "Fixing access to TYPO3 source packages..."
sudo chgrp --recursive $HTTPD_GROUP $BASE/typo3_src*
sudo chmod g+rX $BASE/typo3_src*
consoleWriteLine "Done"