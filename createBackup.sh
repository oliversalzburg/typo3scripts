#!/bin/bash

# Typo3 Installation Backup Script
# written by Oliver Salzburg
#
# Changelog:
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

SELF=`basename $0`

# Show the help for this script
showHelp() {
  cat << EOF
  Usage: $0 [OPTIONS]
  
  Core:
  --help              Display this help and exit.
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
DB=*database*
# Script Configuration end

# The base location from where to retrieve new versions of this script
UPDATE_BASE=http://typo3scripts.googlecode.com/svn/trunk

# Self-update
runSelfUpdate() {
  echo "Performing self-update..."
  wget --quiet --output-document=$0.tmp $UPDATE_BASE/$SELF
  chmod u+x $0.tmp
  mv $0.tmp $0
  exit 0
}

# Read external configuration
CONFIG_FILENAME=${SELF:0:${#SELF}-3}.conf
if [ -e "$CONFIG_FILENAME" ]; then
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
    --base|-b)
      BASE=`echo $option | cut -d'=' -f2`
      ;;
    --hostname)
      HOST=`echo $option | cut -d'=' -f2`
      ;;
    --username)
      USER=`echo $option | cut -d'=' -f2`
      ;;
    --PASSWORD)
      PASS=`echo $option | cut -d'=' -f2`
      ;;
    --database)
      DB=`echo $option | cut -d'=' -f2`
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

FILE=$BASE-`date +%Y-%m-%d-%H-%M`.tgz
echo "Creating Typo3 backup '$FILE'..."
echo -n "Creating database dump at $BASE/database.sql..."
mysqldump --host=$HOST --user=$USER --password=$PASS --add-drop-table --add-drop-database --databases $DB > $BASE/database.sql
echo "Done."
echo -n "Compressing Typo3 installation..."
tar --create --gzip --file $FILE $BASE > /dev/null
echo "Done."
echo -n "Deleting database dump..."
rm --force $BASE/database.sql
echo "Done!"

# vim:ts=2:sw=2:expandtab: