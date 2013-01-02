#!/bin/bash

# TYPO3 Bootstrapper Script
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
  --version=VERSION   The version to install.
  --skip-config       Skips writing any configuration data/file.
  --skip-db-config    Skips writing the database configuration to localconf.php
  --skip-gm-detect    Skips the detection of GraphicsMagick.
  --skip-unzip-detect Skips the detection of the unzip utility.
  --skip-rights       Skip trying to fix access rights.
  --owner=OWNER       The name of the user that owns the installation.
  --httpd-group=GROUP The user group the local HTTP daemon is running as.
  --fix-indexphp      Replaces the index.php symlink with the actual file.

  Database:
  --hostname=HOST     The name of the host where the TYPO3 database is running.
  --username=USER     The username to use when connecting to the TYPO3
                      database.
  --password=PASSWORD The password to use when connecting to the TYPO3
                      database.
  --database=DB       The name of the database in which TYPO3 is stored.
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
# The version to install
VERSION=4.7.7
# The hostname of the MySQL server that TYPO3 uses
HOST=localhost
# The username used to connect to that MySQL server
USER=*username*
# The password for that user
PASS=*password*
# The name of the database in which TYPO3 is stored
DB=typo3
# Should writing the configuration be skipped?
SKIP_CONFIG=false
# Should the database configuration be written to the TYPO3 configuration?
SKIP_DB_CONFIG=false
# Should the detection of GraphicsMagick be skipped?
SKIP_GM_DETECT=true
# Should the detection of the unzip utility be skipped?
SKIP_UNZIP_DETECT=false
# Should we try to fix access permissions for files of the new
# installation?
SKIP_RIGHTS=false
# The owner of the TYPO3 installation
OWNER=$(id --user --name)
# The group the local http daemon is running as (usually www-data or apache)
HTTPD_GROUP=www-data
# Should the index.php symlink be replaced by the actual file?
FIX_INDEXPHP=false
# Script Configuration end

# Pre-initialize password to random 16-character string if possible
if [[ -r /dev/urandom ]]; then
  # Generate a password for the database user
  PASS=$(head --bytes=100 /dev/urandom | sha1sum | head --bytes=16)
  # Generate another password for the TYPO3 install tool
  INSTALL_TOOL_PASSWORD=$(head --bytes=100 /dev/urandom | sha1sum | head --bytes=16)
fi

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
    --skip-config)
      SKIP_CONFIG=true
      ;;
    --skip-db-config)
      SKIP_DB_CONFIG=true
      ;;
    --skip-gm-detect)
      SKIP_GM_DETECT=true
      ;;
    --skip-unzip-detect)
      SKIP_UNZIP_DETECT=true
      ;;
    --skip-rights)
      SKIP_RIGHTS=true
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
    --hostname=*)
      HOST=$(echo $option | cut -d'=' -f2)
      ;;
    --username=*)
      USER=$(echo $option | cut -d'=' -f2)
      ;;
    --password=*)
      PASS=$(echo $option | cut -d'=' -f2)
      ;;
    --database=*)
      DB=$(echo $option | cut -d'=' -f2)
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
checkDependency sha1sum
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

# Check for existing installations
if [[ -d "$BASE" && "false" == $FORCE ]]; then
  consoleWriteLine "A directory named $BASE already exists. $SELF will not overwrite existing content."
  consoleWriteLine "Please remove the folder $BASE manually and run this script again."
  exit 1
fi

# Are we running as root?
if [[ "$(id -u)" != "0" ]]; then
  if ! $SKIP_RIGHTS; then
    SKIP_RIGHTS=true
    consoleWriteLine "Adjusting access rights for the target installation will be skipped because this script is not running with root privileges!"
  fi
fi

# Is the user requesting a TYPO3 6.x branch?
if [[ $VERSION == 6.* ]]; then
  consoleWriteLine "The TYPO3 6.0 configuration file format is not supported by $SELF. Database configuration will be skipped."
  SKIP_DB_CONFIG=true
  SKIP_GM_DETECT=true
  SKIP_UNZIP_DETECT=true
  SKIP_CONFIG=true
fi

# The name of the package
VERSION_NAME=blankpackage-$VERSION
# The name of the file that contains the package
VERSION_FILENAME=$VERSION_NAME.tar.gz
# The location where the package can be downloaded
TYPO3_DOWNLOAD_URL=http://prdownloads.sourceforge.net/typo3/$VERSION_FILENAME

consoleWriteVerbose "Looking for TYPO3 package at '$VERSION_FILENAME'..."
if [[ ! -e "$VERSION_FILENAME" || "true" == $FORCE ]]; then
  if [[ ! "true" == $FORCE ]]; then
    consoleWriteLineVerbose "NOT found!"
  else
    consoleWriteLineVerbose "ignored!"
  fi
  consoleWrite "Downloading $TYPO3_DOWNLOAD_URL..."
  wget --quiet $TYPO3_DOWNLOAD_URL --output-document=$VERSION_FILENAME
else
  consoleWriteLineVerbose "Found!"
  consoleWrite "Trying to resume download from '$TYPO3_DOWNLOAD_URL'..."
  if ! wget --quiet --continue $TYPO3_DOWNLOAD_URL --output-document=$VERSION_FILENAME; then
    consoleWriteLine "Failed!"
    consoleWriteLine "Possibly, the download could not be resumed. Either call $SELF with --force or delete the partially downloaded '$VERSION_FILENAME' manually."
    exit 1
  fi
fi
consoleWriteLine "Done."

consoleWrite "Extracting TYPO3 package '$VERSION_FILENAME'..."
if ! tar --extract --gzip --file $VERSION_FILENAME; then
  consoleWriteLine "Failed!"
  exit 1
fi
consoleWriteLine "Done."

consoleWrite "Moving TYPO3 package to '$BASE'..."
if ! mv $VERSION_NAME $BASE; then
  consoleWriteLine "Failed!"
  exit 1
fi
consoleWriteLine "Done."

# Generate configuration

# Print a single newline, but only the first time it is called
_NEWLINE_PRINTED=false
function newLineOnce() {
  if $_NEWLINE_PRINTED; then
    return
  fi
  consoleWriteLine
  _NEWLINE_PRINTED=true
}

consoleWrite "Generating localconf.php..."
TYPO3_CONFIG=

# Add database configuration
if [[ ! $SKIP_DB_CONFIG || "true" == $SKIP_CONFIG ]]; then
  TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db_username = '$USER';\n"
  TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db_password = '$PASS';\n"
  TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db_host     = '$HOST';\n"
  # Writing the database name is currently disabled. There doesn't seem to be
  # any advantage to it and it conflicts with the TYPO3 installer.
  #TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db          = '$DB';\n"
fi

# Write TYPO3 install tool password
if [[ "true" != $SKIP_CONFIG ]]; then
  INSTALL_TOOL_PASSWORD_HASH=$(echo -n $INSTALL_TOOL_PASSWORD | md5sum | awk '{print $1}')
  TYPO3_CONFIG=$TYPO3_CONFIG"\$TYPO3_CONF_VARS['BE']['installToolPassword'] = '$INSTALL_TOOL_PASSWORD_HASH';\n"
fi

# Add GraphicsMagick (if available)
# TODO: Setting [GFX][im_no_effects] = 1 should be preferred over using GM due to GM's problems when converting .pdf and .psd documents
if [[ ! $SKIP_GM_DETECT || "true" == $SKIP_CONFIG ]]; then
  if ! hash gm 2>&-; then
    newLineOnce
    consoleWriteLine "  Could not find GraphicsMagick binary. im_version_5 will not be set."
  else
    LOCATION_GM=$(which gm)
    TYPO3_CONFIG=$TYPO3_CONFIG"\$TYPO3_CONF_VARS['GFX']['im_version_5'] = '$LOCATION_GM';\n"
  fi
fi

# Add unzip utility
if [[ ! $SKIP_UNZIP_DETECT || "true" == $SKIP_CONFIG ]]; then
  if ! hash unzip 2>&-; then
    newLineOnce
    consoleWriteLine "  Could not find unzip binary. unzip_path will not be set."
  else
    LOCATION_UNZIP=$(which unzip)
    TYPO3_CONFIG=$TYPO3_CONFIG"\$TYPO3_CONF_VARS['BE']['unzip_path'] = '$LOCATION_UNZIP';\n"
  fi
fi

# Write configuration
if [[ "true" != $SKIP_CONFIG ]]; then
  if ! $(cp $BASE/typo3conf/localconf.php $BASE/typo3conf/localconf.php.orig 2> /dev/null); then
    consoleWriteLine "Failed! Unable to create copy of localconf.php"
    exit 1
  fi
  
  if ! sed "/^## INSTALL SCRIPT EDIT POINT TOKEN/a $TYPO3_CONFIG" $BASE/typo3conf/localconf.php.orig > $BASE/typo3conf/localconf.php; then
    consoleWriteLine "Failed! Unable to modify localconf.php"
    exit 1
  fi
  consoleWriteLine "Done."
fi

# Enable install tool
consoleWriteVerbose "Enabling install tool..."
touch "$BASE/typo3conf/FIRST_INSTALL"
consoleWriteLineVerbose "Done."

# Fix permissions
if ! $SKIP_RIGHTS; then
  consoleWrite "Adjusting access permissions for TYPO3 installation..."
  if ! $(id --group $HTTPD_GROUP > /dev/null); then
    consoleWriteLine "Failed! The supplied group '$HTTPD_GROUP' is not known on the system."
    exit 1
  else
    consoleWriteLineVerbose ""
    consoleWriteLineVerbose "Changing owner of '$BASE' to '$OWNER'..."
    sudo chown --recursive $OWNER $BASE
    consoleWriteLineVerbose "Changing group of core TYPO3 folders to '$HTTPD_GROUP'..."
    sudo chgrp --recursive $HTTPD_GROUP $BASE/fileadmin $BASE/typo3temp $BASE/typo3conf $BASE/uploads $BASE/typo3/ext
    consoleWriteLineVerbose "Changing access rights of core TYPO3 folders..."
    sudo chmod --recursive g+rwX,o-w $BASE/fileadmin $BASE/typo3temp $BASE/typo3conf $BASE/uploads $BASE/typo3/ext
  fi
  consoleWriteLine "Done."
fi

# Fix index.php
if $FIX_INDEXPHP; then
  consoleWrite "Replacing index.php symlink with copy of original file..."
  rm -f "$BASE/index.php"
  cp "$BASE/typo3_src/index.php" "$BASE/index.php"
  consoleWriteLine "Done."
fi

if [[ "true" != $SKIP_CONFIG ]]; then
  consoleWriteLine ""
  consoleWriteLine "Your TYPO3 Install Tool password is: '$INSTALL_TOOL_PASSWORD'"
fi

# vim:ts=2:sw=2:expandtab: