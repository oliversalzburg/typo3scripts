#!/bin/bash
 
# TYPO3 Installation Backup Restore Script
# written by Oliver Salzburg

set -o nounset
set -o errexit

SELF=$(basename "$0")

# Show the help for this script
function showHelp() {
  cat << EOF
  Usage: $0 [OPTIONS --file=<FILE>]|<FILE>
  
  Core:
  --help              Display this help and exit.
  --update            Tries to update the script to the latest version.
  --base=PATH         The name of the base path where TYPO3 is 
                      installed. If no base is supplied, "typo3" is used.
  --export-config     Prints the default configuration of this script.
  --extract-config    Extracts configuration parameters from TYPO3.
  
  Options:
  --file=FILE         The file in which the backup is stored.
  
  Database:
  --hostname=HOST     The name of the host where the TYPO3 database is running.
  --username=USER     The username to use when connecting to the TYPO3
                      database.
  --password=PASSWORD The password to use when connecting to the TYPO3
                      database.
  --database=DB       The name of the database in which TYPO3 is stored.
  
  Note: When using an external configuration file, it is sufficient to supply
        just the name of the file that contains the backup as a parameter.
        When supplying any other command line argument, supply the target file
        through the --file command line parameter.
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
# The file to restore the backup from
FILE=$1
# The hostname of the MySQL server that TYPO3 uses
HOST=localhost
# The username used to connecto to that MySQL server
USER=root
# The password for that user
PASS=*password*
# The name of the database in which TYPO3 is stored
DB=typo3
#Script Configuration end

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
    --file=*)
      FILE=$(echo $option | cut -d'=' -f2)
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
      FILE=$option
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
checkDependency find
checkDependency tar
checkDependency mysql
echo "Succeeded."

# Update check
SUM_LATEST=$(curl $UPDATE_BASE/versions 2>&1 | grep $SELF | awk '{print $1}')
SUM_SELF=$(md5sum "$0" | awk '{print $1}')
if [[ "$SUM_LATEST" != "$SUM_SELF" ]]; then
  echo "NOTE: New version available!"
fi

# Begin main operation

# Check argument validity
if [[ ! -e "$FILE" ]]; then
  if [[ $FILE == --* ]]; then
    echo "The given TYPO3 snapshot '$FILE' looks like a command line parameter."
    echo "Please use the --file parameter when giving multiple arguments."
    exit 1
  fi
  
  echo "The given snapshot '$FILE' does not exist."
  exit 1
fi

# Does the base directory exist?
if [[ ! -d $BASE ]]; then
  echo "The base directory '$BASE' does not seem to exist!"
  exit 1
fi
# Is the base directory writeable?
if [[ ! -w $BASE ]]; then
  echo "The base directory '$BASE' is not writeable!"
  exit 1
fi
# Check if we can delete the target base folder
echo -n "Testing write permissions in $BASE..."
if ! find $BASE \( -exec test -w {} \; -o \( -exec echo {} \; -quit \) \) | xargs -I {} bash -c "if [ -n "{}" ]; then echo Failed\!; echo {} is not writable\!; exit 1; fi"; then
  exit 1
fi
echo "Succeeded"

echo -n "Erasing current TYPO3 installation '$BASE'..."
if ! rm --recursive --force -- $BASE > /dev/null; then
  echo "Failed!"
  exit 1
fi
echo "Done."

echo -n "Extracting TYPO3 backup '$FILE'..."
if ! tar --extract --gzip --file $FILE > /dev/null; then
  echo "Failed!"
  exit 1
fi
echo "Done."

echo -n "Importing database dump..."
set +e errexit
_errorMessage=$(mysql --host=$HOST --user=$USER --password=$PASS --default-character-set=utf8 $DB < $BASE/database.sql 2>&1 >/dev/null)
_status=$?
set -e errexit
if [[ 0 < $_status ]]; then
  echo "Failed!"
  echo "Error: $_errorMessage"
  exit 1
fi
echo "Done."

echo -n "Deleting database dump..."
rm --force -- $BASE/database.sql
echo "Done!"

# vim:ts=2:sw=2:expandtab: