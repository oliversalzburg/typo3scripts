#!/bin/bash
 
# Typo3 Installation Backup Restore Script
# written by Oliver Salzburg
#
# Changelog:
# 1.3.4 - Fixed update location
# 1.3.3 - Now using generic config file sourcing approach
# 1.3.2 - Now using explicit modifiers
# 1.3.1 - Typo3 base installation directory is now configurable
# 1.3.0 - Added update check functionality
# 1.2.0 - Added self-updating functionality
# 1.1.1 - Fixed database not being interpreted as UTF-8 after restore
# 1.1.0 - Configuration can now be sourced from restoreBackup.conf
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
  --update            Tries to update the script to the latest version.
  --base=PATH         The name of the base path where Typo3 should be 
                      installed. If no base is supplied, "typo3" is used.
  Options:
  --file=FILE         The file in which the backup is stored.
  
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

# Check on minimal command line argument count
REQUIRED_ARGUMENT_COUNT=1
if [ $# -lt $REQUIRED_ARGUMENT_COUNT ]; then
  echo "Insufficient command line arguments!"
  echo "Use $0 --help to get additional information."
  exit -1
fi
 
# Script Configuration start
# The base directory where Typo3 is installed
BASE=typo3
# The file to restore the backup from
FILE=$1
# The hostname of the MySQL server that Typo3 uses
HOST=localhost
# The username used to connecto to that MySQL server
USER=root
# The password for that user
PASS=*password*
# The name of the database in which Typo3 is stored
DB=typo3
#Script Configuration end

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
    --base=*)
      BASE=`echo $option | cut -d'=' -f2`
      ;;
    --file=*)
      FILE=`echo $option | cut -d'=' -f2`
      ;;
    --hostname=*)
      HOST=`echo $option | cut -d'=' -f2`
      ;;
    --username=*)
      USER=`echo $option | cut -d'=' -f2`
      ;;
    --password=*)
      PASS=`echo $option | cut -d'=' -f2`
      ;;
    --database=*)
      DB=`echo $option | cut -d'=' -f2`
      ;;
    *)
      FILE=$option
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

echo -n "Erasing current Typo3 installation '$BASE'..."
rm --recursive --force $BASE > /dev/null
echo "Done."
echo -n "Extracting Typo3 backup '$FILE'..."
tar --extract --gzip --file $FILE > /dev/null
echo "Done."
echo -n "Importing database dump..."
mysql --host=$HOST --user=$USER --password=$PASS --default-character-set=utf8 $DB < $BASE/database.sql
echo "Done."
echo -n "Deleting database dump..."
rm $BASE/database.sql
echo "Done."
echo "Done!"

# vim:ts=2:sw=2:expandtab: