#!/bin/bash

# TYPO3 Installation Backup Script
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
  --skip-db           Skips dumping the database before creating the archive.
  --skip-fs           Skips archiving the TYPO3 directory.
  --exclude=pattern   Will exclude files that match the pattern from the 
                      backup.
  --no-data=pattern   For MySQL tables that match the pattern, only the table
                      structure will be exported.
                      
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
# The base directory where TYPO3 is installed
BASE=typo3
# The hostname of the MySQL server that TYPO3 uses
HOST=localhost
# The username used to connect to that MySQL server
USER=*username*
# The password for that user
PASS=*password*
# The name of the database in which TYPO3 is stored
DB=typo3
# Skip dumping the database before archiving
SKIP_DB=false
# Skips archiving the TYPO3 base directory.
SKIP_FS=false
# The patterns that describe files that should not be included in the backup
EXCLUDE=()
# The patterns that describe for which MySQL tables only the structure should be exported.
NO_DATA=()
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
    --extract-config)
      extractConfig
      exit 0
      ;;
    --base=*)
      BASE=$(echo $option | cut -d'=' -f2)
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
    --skip-db)
      SKIP_DB=true
      ;;
    --skip-fs)
      SKIP_FS=true
      ;;
    --exclude=*)
      EXCLUDE+=($(echo $option | cut -d'=' -f2))
      ;;
    --no-data=*)
      NO_DATA+=($(echo $option | cut -d'=' -f2))
      ;;
    *)
      echo "Unrecognized option \"$option\""
      exit 1
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
checkDependency mysqldump
consoleWriteLine "Succeeded."

# Begin main operation

# Does the base directory exist?
if [[ ! -d $BASE ]]; then
  consoleWriteLine "The base directory '$BASE' does not seem to exist!"
  exit 1
fi
# Is the base directory readable?
if [[ ! -r $BASE ]]; then
  consoleWriteLine "The base directory '$BASE' is not readable!"
  exit 1
fi

# Adding parameters to the filename
PARAMS=""
if [[ "true" == $SKIP_DB ]]; then
  PARAMS+="-no-DB"
fi

if [[ "true" == $SKIP_FS ]]; then
  PARAMS+="-no-FS"
fi

# Filename for snapshot
FILE=$BASE-$(date +%Y-%m-%d-%H-%M)$PARAMS.tgz

consoleWriteLine "Creating TYPO3 backup '$FILE'..."

# Create database dump
if [[ "false" == $SKIP_DB ]]; then
  consoleWrite "Creating database dump at '$BASE/database.sql'..."
  
  # Get all table names
  _tablesList=$BASE/database.sql.tables
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
  
  _fullTables=()
  _bareTables=()
  _noDataTables=
  _fullDataTables=
  
  if [[ ${#NO_DATA[@]} > 0 ]]; then
    consoleWriteLineVerbose
    while read _tableName; do
      for _noDataPattern in "${NO_DATA[@]}"; do
        if [[ $_tableName = $_noDataPattern ]]; then
          _noDataTables+="--ignore-table=$DB.$_tableName "
          consoleWriteLineVerbose "Excluding '$DB.$_tableName'"
        else
          _fullDataTables+="--ignore-table=$DB.$_tableName "
        fi
      done
    done < $_tablesList
    
    # Try to delete temporary file
    rm $_tablesList 2>&1 > /dev/null
  fi
  
  set +e errexit
  _errorMessage=$(mysqldump --host=$HOST --user=$USER --password=$PASS --add-drop-table --add-drop-database $_noDataTables $DB 2>&1 > $BASE/database.sql)
  _status=$?
  set -e errexit
  if [[ 0 < $_status ]]; then
    consoleWriteLine "Failed!"
    consoleWriteLine "Error: $_errorMessage"
    exit 1
  fi
  
  if [[ ! "" = $_noDataTables ]]; then
    # We now export the tables for which we ignore the data.
    # We do so by ignoring all tables we previously selected for exporting.
    consoleWriteLine "Done"
    consoleWrite "Exporting structure for previously ignored tables..."
    
    set +e errexit
    _errorMessage=$(mysqldump --host=$HOST --user=$USER --password=$PASS --add-drop-table --add-drop-database --no-data $_fullDataTables $DB 2>&1 >> $BASE/database.sql)
    _status=$?
    set -e errexit
    if [[ 0 < $_status ]]; then
      consoleWriteLine "Failed!"
      consoleWriteLine "Error: $_errorMessage"
      exit 1
    fi
  fi
  consoleWriteLine "Done"
  
else
  consoleWriteLine "Skipping database export."
fi


# Create backup archive

if [[ "false" == $SKIP_FS ]]; then
  
  _excludes=
  if [[ ${#EXCLUDE[@]} > 0 ]]; then
    for _excludePattern in "${EXCLUDE[@]}"; do
      _excludes+="--exclude=$BASE/$_excludePattern "
      consoleWriteLineVerbose "Excluding '$BASE/$_excludePattern'"
    done
  fi
  
  _statusMessage="Compressing TYPO3 installation..."
  _compressionTarget=$BASE

else

  _excludes=
  _statusMessage="Compressing TYPO3 database..."
  _compressionTarget=$BASE/database.sql
fi

consoleWrite $_statusMessage
if hash pv 2>&- && hash gzip 2>&- && hash du 2>&-; then
  consoleWriteLine
  _dataSize=`du --summarize --bytes $_compressionTarget | cut --fields 1`
  if ! tar --create $_excludes --file - $_compressionTarget | pv --progress --rate --bytes --size $_dataSize | gzip --best > $FILE; then
    consoleWriteLine "Failed!"
    exit 1
  fi
  # Clear pv output and position cursor after status message
  # If stderr was redirected from the console, this messes up the prompt.
  # It's unfortunate, but ignored for the time being
  tput cuu 2 && tput cuf ${#_statusMessage} && tput ed
else
  if ! tar --create $_excludes --gzip --file $FILE $_compressionTarget; then
    consoleWriteLine "Failed!"
    exit 1
  fi
fi

consoleWriteLine "Done."

# Now that the database dump is packed up, delete it
# We don't want to delete it if we never even exported it
if [[ "false" == $SKIP_DB ]]; then
  consoleWriteVerbose "Deleting database dump..."
  rm --force -- $BASE/database.sql
  # Also delete list of tables
  rm $_tablesList 2>&1 > /dev/null
fi
consoleWriteLineVerbose "Done!"

# vim:ts=2:sw=2:expandtab: