#!/bin/bash

# TYPO3 Clear Caches Script
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
  --all               Clear everything.
  --cache-tables      Truncate cache_* tables.
  --cf-tables         Truncate cf_* tables.
  --rearlurl-tables   Truncate tx_realurl_*cache tables.
  --rearlurl-aliases  Truncate tx_realurl_alias table.
  --typo3temp         Clear typo3temp folder.
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
  LOCALCONFIGURATION="$BASE/typo3conf/LocalConfiguration.php"
  if [[ -r $LOCALCONF ]]; then
    echo HOST=$(tac $LOCALCONF | grep --perl-regexp --only-matching "(?<=typo_db_host = ')[^']*(?=';)")
    echo USER=$(tac $LOCALCONF | grep --perl-regexp --only-matching "(?<=typo_db_username = ')[^']*(?=';)")
    echo PASS=$(tac $LOCALCONF | grep --perl-regexp --only-matching "(?<=typo_db_password = ')[^']*(?=';)")
    echo DB=$(tac $LOCALCONF | grep --perl-regexp --only-matching "(?<=typo_db = ')[^']*(?=';)")
  elif [[ -r $LOCALCONFIGURATION ]]; then
    if [[ ! -e "./configurationProxy.php" ]]; then
      echo "Required 'configurationProxy.php' is missing.";
      exit 1
    fi
    echo HOST=$(./configurationProxy.php --get=TYPO3_CONF_VARS.DB.host)
    echo USER=$(./configurationProxy.php --get=TYPO3_CONF_VARS.DB.username)
    echo PASS=$(./configurationProxy.php --get=TYPO3_CONF_VARS.DB.password)
    echo DB=$(./configurationProxy.php --get=TYPO3_CONF_VARS.DB.database)
  else
    echo "Unable to find readable configuration file." >&2
  fi
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
# Truncate cache_* tables.
CLEAR_CACHE_TABLES=false
# Truncate cf_* tables.
CLEAR_CF_TABLES=false
# Truncate tx_realurl_*cache tables.
CLEAR_REALURL_TABLES=false
# Truncate tx_realurl_uniqalias table.
CLEAR_REALURL_ALIASES=false
# Clear typo3temp folder.
CLEAR_TYPO3TEMP=false
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
UPDATE_BASE=https://raw.github.com/oliversalzburg/typo3scripts/master

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
    consoleWriteLine "Please check the project home page 'https://github.com/oliversalzburg/typo3scripts'."
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
  if [[ ! -r $BASE_CONFIG_FILENAME ]]; then
    consoleWriteLine "Unable to read '$BASE_CONFIG_FILENAME'. Check permissions."
    exit 1
  fi
  consoleWriteVerbose "Sourcing script configuration from $BASE_CONFIG_FILENAME..."
  source $BASE_CONFIG_FILENAME
  consoleWriteLineVerbose "Done."
fi

# Read external configuration - Stage 2 - script-specific (overwrites default, hard-coded configuration)
CONFIG_FILENAME=${SELF:0:${#SELF}-3}.conf
if [[ -e "$CONFIG_FILENAME" ]]; then
  if [[ ! -r $CONFIG_FILENAME ]]; then
    consoleWriteLine "Unable to read '$CONFIG_FILENAME'. Check permissions."
    exit 1
  fi
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
    --base=*)
      BASE=$(echo $option | cut -d'=' -f2)
      ;;
    --cache-tables)
      CLEAR_CACHE_TABLES=true
      ;;
    --cf-tables)
      CLEAR_CF_TABLES=true
      ;;
    --realurl-tables)
      CLEAR_REALURL_TABLES=true
      ;;
	--realurl-aliases)
      CLEAR_REALURL_ALIASES=true
      ;;
    --typo3temp)
      CLEAR_TYPO3TEMP=true
      ;;
    --all)
      CLEAR_CACHE_TABLES=true
      CLEAR_CF_TABLES=true
      CLEAR_TYPO3TEMP=true
      CLEAR_REALURL_TABLES=true
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
checkDependency mysql
consoleWriteLine "Succeeded."

# Begin main operation

if [[ "true" == $CLEAR_CACHE_TABLES || "true" == $CLEAR_CF_TABLES || "true" == $CLEAR_REALURL_TABLES || "true" == $CLEAR_REALURL_ALIASES ]]; then
  consoleWriteVerbose "Getting list of database tables..."
  # Get all table names
  _tablesList=./database.sql.tables
  set +e errexit
  _errorMessage=$(echo "SHOW TABLES;" | mysql --host=$HOST --user=$USER --password=$PASS $DB 2>&1 > $_tablesList)
  _status=$?
  set -e errexit
  if [[ 0 < $_status ]]; then
    consoleWriteLine "Failed!"
    consoleWriteLine "Error: $_errorMessage"
    # Try to delete temporary file
    rm $_tablesList 2>&1 > /dev/null
    exit 1
  fi
  consoleWriteLineVerbose "Done."

  consoleWrite "Truncating database tables..."
  consoleWriteLineVerbose

  while read _tableName; do
    if [[ ( $_tableName = cf_* && "true" == $CLEAR_CF_TABLES ) || ( $_tableName = cache_* && "true" == $CLEAR_CACHE_TABLES ) || ( $_tableName = tx_realurl_*cache && "true" == $CLEAR_REALURL_TABLES ) || ( $_tableName = tx_realurl_uniqalias && "true" == $CLEAR_REALURL_ALIASES ) ]]; then
      consoleWriteVerbose "Truncating $_tableName..."
        set +e errexit
        _errorMessage=$(echo "TRUNCATE TABLE $_tableName;" | mysql --host=$HOST --user=$USER --password=$PASS $DB 2>&1 >/dev/null)
        _status=$?
        set -e errexit
        if [[ 0 < $_status ]]; then
          consoleWriteLine "Failed!"
          consoleWriteLine "Error: $_errorMessage"
          # Try to delete temporary file
          rm $_tablesList 2>&1 > /dev/null
          exit 1
        fi
      consoleWriteLineVerbose "Done."
    fi
  done < $_tablesList
  rm $_tablesList 2>&1 > /dev/null
  consoleWriteLine "Done."
fi

if [[ "true" == $CLEAR_TYPO3TEMP ]]; then
  consoleWrite "Clearing typo3temp..."
  # Delete the directory contents
  rm -rf $BASE/typo3temp
  mkdir "$BASE/typo3temp"
  mkdir "$BASE/typo3temp/compressor"
  mkdir "$BASE/typo3temp/cs"
  mkdir "$BASE/typo3temp/Cache"
  mkdir "$BASE/typo3temp/GB"
  mkdir "$BASE/typo3temp/llxml"
  mkdir "$BASE/typo3temp/pics"
  mkdir "$BASE/typo3temp/sprites"
  mkdir "$BASE/typo3temp/temp"
  touch "$BASE/typo3temp/index.html"
  consoleWriteLine "Done."
fi

# vim:ts=2:sw=2:expandtab:
