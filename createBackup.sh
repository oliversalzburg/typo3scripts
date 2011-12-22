#!/bin/bash

# Typo3 Installation Backup Script
# written by Oliver Salzburg
#
# Changelog:
# 1.4.0 - Code cleaned up
#         Extended command line paramter support
#         Improved self-updating
# 1.3.4 - Fixed update location
# 1.3.3 - Now using generic config file sourcing approach
# 1.3.2 - Now using explicit modifiers
# 1.3.1 - Typo3 base installation directory is now configurable
# 1.3.0 - Added update check functionality
# 1.2.0 - Added self-updating functionality
# 1.1.0 - Configuration can now be sourced from createBackup.conf
# 1.0.0 - Initial release

set -o nounset
set -o errexit

SELF=$(basename $0)

# Show the help for this script
showHelp() {
  cat << EOF
  Usage: $0 [OPTIONS]
  
  Core:
  --help              Display this help and exit.
  --update            Tries to update the script to the latest version.
  --base=PATH         The name of the base path where Typo3 should be 
                      installed. If no base is supplied, "typo3" is used.
  Database:
  --hostname=HOST     The name of the host where the Typo3 database is running.
  --username=USER     The username to use when connecting to the Typo3
                      database.
  --password=PASSWORD The password to use when connecting to the Typo3
                      database.
  --database=DB       The name of the database in which Typo3 is stored.
EOF
  exit 0
}

# Script Configuration start
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
# Script Configuration end

# The base location from where to retrieve new versions of this script
UPDATE_BASE=http://typo3scripts.googlecode.com/svn/trunk

# Self-update
runSelfUpdate() {
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
  rm \$0
else
  echo "Failed!"
fi
EOF
  
  echo -n "Inserting update process..."
  exec /bin/bash updateScript.sh
}

# Read external configuration
CONFIG_FILENAME=${SELF:0:${#SELF}-3}.conf
if [[ -e "$CONFIG_FILENAME" ]]; then
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
    *)
      echo "Unrecognized option \"$option\""
      exit 1
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

# Does the base directory exist?
if [ ! -d $BASE ]; then
  echo "The base directory '$BASE' does not seem to exist!"
  exit 1
fi
# Is the base directory readable?
if [ ! -r $BASE ]; then
  echo "The base directory '$BASE' is not readable!"
  exit 1
fi

# Filename for snapshot
FILE=$BASE-$(date +%Y-%m-%d-%H-%M).tgz

echo "Creating Typo3 backup '$FILE'..."

# Create database dump
echo -n "Creating database dump at $BASE/database.sql..."
if ! mysqldump --host=$HOST --user=$USER --password=$PASS --add-drop-table --add-drop-database --databases $DB > $BASE/database.sql; then
  echo "Failed!"
  exit 1
fi
echo "Done."

# Create backup archive
echo -n "Compressing Typo3 installation..."
if ! tar --create --gzip --file $FILE $BASE > /dev/null; then
  echo "Failed!"
  exit 1
fi
echo "Done."

# Now that the database dump is packed up, delete it
echo -n "Deleting database dump..."
rm --force $BASE/database.sql
echo "Done!"

# vim:ts=2:sw=2:expandtab: