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
  --update            Tries to update the script to the latest version.
  --base=PATH         The name of the base path where TYPO3 is 
                      installed. If no base is supplied, "typo3" is used.
  --export-config     Prints the default configuration of this script.
  --extract-config    Extracts configuration parameters from TYPO3.
  
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

# Script Configuration start
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
# Script Configuration end

# The base location from where to retrieve new versions of this script
UPDATE_BASE=http://typo3scripts.googlecode.com/svn/trunk

# Self-update
function runSelfUpdate() {
  echo "Performing self-update..."
  
  # Download new version
  echo -n "Downloading latest version..."
  if ! wget --quiet --output-document="$0.tmp" $UPDATE_BASE/$SELF ; then
    echo "Failed: Error while trying to wget new version!"
    echo "File requested: $UPDATE_BASE/$SELF"
    exit 1
  fi
  echo "Done."
  
  # Copy over modes from old version
  OCTAL_MODE=$(stat -c '%a' $SELF)
  if ! chmod $OCTAL_MODE "$0.tmp" ; then
    echo "Failed: Error while trying to set mode on $0.tmp."
    exit 1
  fi
  
  # Spawn update script
  cat > updateScript.sh << EOF
#!/bin/bash
# Overwrite old file with new
if mv "$0.tmp" "$0"; then
  echo "Done. Update complete."
  rm -- \$0
else
  echo "Failed!"
fi
EOF
  
  echo -n "Inserting update process..."
  exec /bin/bash updateScript.sh
}

# Read external configuration - Stage 1 - typo3scripts.conf (overwrites default, hard-coded configuration)
BASE_CONFIG_FILENAME="typo3scripts.conf"
if [[ -e "$BASE_CONFIG_FILENAME" && !( $# > 1 && "$1" != "--help" && "$1" != "-h" ) ]]; then
  echo -n "Sourcing script configuration from $BASE_CONFIG_FILENAME..."
  source $BASE_CONFIG_FILENAME
  echo "Done."
fi

# Read external configuration - Stage 2 - script-specific (overwrites default, hard-coded configuration)
CONFIG_FILENAME=${SELF:0:${#SELF}-3}.conf
if [[ -e "$CONFIG_FILENAME" && !( $# > 1 && "$1" != "--help" && "$1" != "-h" ) ]]; then
  echo -n "Sourcing script configuration from $CONFIG_FILENAME..."
  source $CONFIG_FILENAME
  echo "Done."
fi

# Read command line arguments (overwrites config file)
for option in $*; do
  case "$option" in
    --help|-h)
      showHelp
      exit 0
      ;;
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
      echo "Unrecognized option \"$option\""
      exit 1
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
checkDependency mysqldump
echo "Succeeded."

# Update check
SUM_LATEST=$(curl $UPDATE_BASE/versions 2>&1 | grep $SELF | awk '{print $1}')
SUM_SELF=$(md5sum "$0" | awk '{print $1}')
if [[ "$SUM_LATEST" != "$SUM_SELF" ]]; then
  echo "NOTE: New version available!"
fi

# Begin main operation

# Does the base directory exist?
if [[ ! -d $BASE ]]; then
  echo "The base directory '$BASE' does not seem to exist!"
  exit 1
fi
# Is the base directory readable?
if [[ ! -r $BASE ]]; then
  echo "The base directory '$BASE' is not readable!"
  exit 1
fi

# Filename for snapshot
FILE=$BASE-$(date +%Y-%m-%d-%H-%M).tgz

echo "Creating TYPO3 backup '$FILE'..."

# Create database dump
echo -n "Creating database dump at $BASE/database.sql..."
set +e errexit
_errorMessage=$(mysqldump --host=$HOST --user=$USER --password=$PASS --add-drop-table --add-drop-database --databases $DB 2>&1 > $BASE/database.sql)
_status=$?
set -e errexit
if [[ 0 < $_status ]]; then
  echo "Failed!"
  echo "Error: $_errorMessage"
  exit 1
fi
echo "Done."


# Create backup archive
_statusMessage="Compressing TYPO3 installation..."
echo -n $_statusMessage
if hash pv 2>&- && hash gzip 2>&- && hash du 2>&-; then
  echo
  _folderSize=`du --summarize --bytes $BASE | cut --fields 1`
  if ! tar --create --file - $BASE | pv --progress --rate --bytes --size $_folderSize | gzip --best > $FILE; then
    echo "Failed!"
    exit 1
  fi
  # Clear pv output and position cursor after status message
  tput cuu 2 && tput cuf ${#_statusMessage} && tput ed
else
  if ! tar --create --gzip --file $FILE $BASE; then
    echo "Failed!"
    exit 1
  fi
fi

echo "Done."

# Now that the database dump is packed up, delete it
echo -n "Deleting database dump..."
rm --force -- $BASE/database.sql
echo "Done!"

# vim:ts=2:sw=2:expandtab:
