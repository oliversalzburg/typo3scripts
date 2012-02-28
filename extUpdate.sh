#!/bin/bash

# TYPO3 Extension Update Script
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
  --extension=EXTKEY  The extension key of the extension that should be
                      operated on.
  --changelog         Display the upload comments for updated extensions.

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
# The base directory where Typo3 is installed
BASE=typo3
# The hostname of the MySQL server that Typo3 uses
HOST=localhost
# The username used to connect to that MySQL server
USER=*username*
# The password for that user
PASS=*password*
# The name of the database in which Typo3 is stored
DB=typo3
# The extension key for which to retrieve the changelog
EXTENSION=
# Should the upload comments be displayed for extensions that have updates available?
DISPLAY_CHANGELOG=0
# Script Configuration end

# The base location from where to retrieve new versions of this script
UPDATE_BASE=http://typo3scripts.googlecode.com/svn/trunk

# The base location from where to retrieve new versions of this script
UPDATE_BASE=http://typo3scripts.googlecode.com/svn/trunk

# Update check
function updateCheck() {
  SUM_LATEST=$(curl $UPDATE_BASE/versions 2>&1 | grep $SELF | awk '{print $2}')
  SUM_SELF=$(tail --lines=+2 "$0" | md5sum | awk '{print $1}')
  
  $VERBOSE && echo "Remote hash source: '$UPDATE_BASE/versions'" >&2
  $VERBOSE && echo "Own hash: '$SUM_SELF' Remote hash: '$SUM_LATEST'" >&2
  
  if [[ "" == $SUM_LATEST ]]; then
    echo "No update information is available for '$SELF'" >&2
    echo "Please check the project home page 'http://code.google.com/p/typo3scripts/'." >&2
    return 2
    
  elif [[ "$SUM_LATEST" != "$SUM_SELF" ]]; then
    echo "NOTE: New version available!" >&2
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
  $VERBOSE && echo -n "Sourcing script configuration from $BASE_CONFIG_FILENAME..." >&2
  source $BASE_CONFIG_FILENAME
  $VERBOSE && echo "Done." >&2
fi

# Read external configuration - Stage 2 - script-specific (overwrites default, hard-coded configuration)
CONFIG_FILENAME=${SELF:0:${#SELF}-3}.conf
if [[ -e "$CONFIG_FILENAME" ]]; then
  $VERBOSE && echo -n "Sourcing script configuration from $CONFIG_FILENAME..." >&2
  source $CONFIG_FILENAME
  $VERBOSE && echo "Done." >&2
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
    --extension=*)
      EXTENSION=$(echo $option | cut -d'=' -f2)
      ;;
    --changelog)
      DISPLAY_CHANGELOG=1
      ;;
    *)
      EXTENSION=$option
      ;;
  esac
done

# Check for dependencies
function checkDependency() {
  if ! hash $1 2>&-; then
    echo "Failed!" >&2
    echo "This script requires '$1' but it can not be found. Aborting." >&2
    exit 1
  fi
}
echo -n "Checking dependencies..." >&2
checkDependency mysql
checkDependency sed
echo "Succeeded." >&2

# Begin main operation

# Check argument validity
if [[ $EXTENSION == --* ]]; then
  echo "The given extension key '$EXTENSION' looks like a command line parameter." >&2
  echo "Please use the --extension parameter when giving multiple arguments." >&2
  exit 1
fi

# Does the base directory exist?
if [[ ! -d $BASE ]]; then
  echo "The base directory '$BASE' does not seem to exist!" >&2
  exit 1
fi
# Is the base directory readable?
if [[ ! -r $BASE ]]; then
  echo "The base directory '$BASE' is not readable!" >&2
  exit 1
fi

# Check if extChangelog.sh is required and available
if [[ $DISPLAY_CHANGELOG == 1 && ! -e extChangelog.sh ]]; then
  echo "Upload comments will NOT be displayed! To enable this feature, download extChangelog.sh from the typo3scripts project and place it in the same folder as $SELF." >&2
fi

# Version number compare helper function
# Created by Dennis Williamson (http://stackoverflow.com/questions/4023830/bash-how-compare-two-strings-in-version-format)
function compareVersions() {
  if [[ $1 == $2 ]]
  then
    return 0
  fi
  local IFS=.
  local i ver1=($1) ver2=($2)
  # fill empty fields in ver1 with zeros
  for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
  do
    ver1[i]=0
  done
  for ((i=0; i<${#ver1[@]}; i++))
  do
    if [[ -z ${ver2[i]} ]]
    then
      # fill empty fields in ver2 with zeros
      ver2[i]=0
    fi
    if ((10#${ver1[i]} > 10#${ver2[i]}))
    then
      return 1
    fi
    if ((10#${ver1[i]} < 10#${ver2[i]}))
    then
      return 2
    fi
  done
  return 0
}

# Check if extension cache has been updated recently
_extensionCacheFile="$BASE/typo3temp/1.extensions.xml.gz"
if [[ ! -e $_extensionCacheFile ]]; then
  echo "Unable to find extension cache '$_extensionCacheFile'. Either you are using a repository with a non-standard ID (not TYPO3.org) or you have never loaded an extension list." >&2
else
  _lastUpdateTime=$(date --reference=$_extensionCacheFile +%s)
  _currentTime=$(date +%s)
  _lastUpdatePeriod=$(( $_currentTime - $_lastUpdateTime ))
  # Longest period the cache can be left not update without extUpdate.sh complaining
  # By default, 172800 seconds = 48 hours
  MAX_CACHE_UPDATE_DELAY=172800
  if [[ "$_lastUpdatePeriod" -ge "$MAX_CACHE_UPDATE_DELAY" ]]; then
    echo "WARNING: Did you forget to update your extension cache? Last update: $(date --date @$_lastUpdateTime "+%Y-%m-%d %T")" >&2
  fi
  
fi

# Check versions on all installed extensions
_updatesAvailable=0
for _extDirectory in "$BASE/typo3conf/ext/"*; do
  # Skip non-directories
  if [[ ! -d $_extDirectory ]]; then
    continue
  fi
  
  _extKey=$(basename "$_extDirectory")
  if [[ "" != $EXTENSION && $_extKey != $EXTENSION ]]; then
    continue
  fi

  # Determine installed version from ext_emconf.php
  _installedVersion=$(grep --perl-regexp "'version'\s*=>\s*'\d{1,3}\.\d{1,3}\.\d{1,3}'" "$_extDirectory/ext_emconf.php" | grep --perl-regexp --only-matching "\d{1,3}\.\d{1,3}\.\d{1,3}")
  
  # Get the latest known version from the cache in the database
  set +e errexit
  _query="SELECT \`version\` FROM \`cache_extensions\` WHERE (\`extkey\` = '$_extKey') ORDER BY \`intversion\` DESC LIMIT 1;"
  _errorMessage=$(echo $_query | mysql --host=$HOST --user=$USER --pass=$PASS --database=$DB --batch --skip-column-names 2>&1 > extVersion.out)
  _status=$?
  _latestVersion=$(cat extVersion.out)
  if [[ "" == $_latestVersion ]]; then
    echo "Warning: Could not determine the latest version of extension '$_extKey'!" >&2
    echo "         No entry for the extension could be found in the extension cache." >&2
    continue
  fi
  rm -f extVersion.out
  set -e errexit
  if [[ 0 < $_status ]]; then
    echo "Failed!" >&2
    echo "Error: $_errorMessage" >&2
    exit 1
  fi
  
  # Compare versions
  set +e errexit
  compareVersions $_installedVersion $_latestVersion
  _versionsEqual=$?
  set -e errexit
  
  if [[ $_versionsEqual != 0 ]]; then
    (( ++_updatesAvailable ))
    echo "New version of '$_extKey' available. Installed: $_installedVersion Latest: $_latestVersion"
    if [[ $DISPLAY_CHANGELOG == 1 && -e extChangelog.sh ]]; then
      ./extChangelog.sh --extension=$_extKey --first=$_installedVersion --skip-first 2>/dev/null
      echo
    fi
  fi
done

if [[ 0 -eq $_updatesAvailable ]]; then
  echo "No updates available." >&2
fi

# vim:ts=2:sw=2:expandtab: