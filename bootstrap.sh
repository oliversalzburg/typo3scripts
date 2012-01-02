#!/bin/bash

# Typo3 Bootstrapper Script
# written by Oliver Salzburg
#
# Changelog:
# 1.4.1 - Added validity check for version parameter
# 1.4.0 - Script is now fully able to create an installation from scratch to
#         Typo3 1-2-3 installer
# 1.3.1 - Adjusting the access rights can now be skipped
# 1.3.0 - The access rights for the Typo3 installation will now be adjusted
# 1.2.1 - Added ability to skip database configuration
# 1.2.0 - Added some settings to localconf.php generation
# 1.1.0 - Code cleaned up
#         Extended command line paramter support
#         Improved self-updating
# 1.0.0 - Initial release

set -o nounset
set -o errexit

SELF=$(basename "$0")

# Show the help for this script
function showHelp() {
  cat << EOF
  Usage: $0 [OPTIONS --version=<VERSION>]|<VERSION>

  Core:
  --help              Display this help and exit.
  --update            Tries to update the script to the latest version.
  --base=PATH         The name of the base path where Typo3 should be
                      installed. If no base is supplied, "typo3" is used.

  Options:
  --version=VERSION   The version to install.
  --skip-db-config    Skips writing the database configuration to localconf.php
  --skip-gm-detect    Skips the detection of GraphicsMagick.
  --skip-unzip-detect Skips the detection of the unzip utility.
  --skip-rights       Skip trying to fix access rights.
  --owner=OWNER       The name of the user that owns the installation.
  --httpd-group=GROUP The user group the local HTTP daemon is running as.

  Database:
  --hostname=HOST     The name of the host where the Typo3 database is running.
  --username=USER     The username to use when connecting to the Typo3
                      database.
  --password=PASSWORD The password to use when connecting to the Typo3
                      database.
  --database=DB       The name of the database in which Typo3 is stored.

  Note: When using an external configuration file, it is sufficient to supply
        just the target version as a parameter.
        When supplying other any command line argument, supply the target
        version through the --version command line parameter.
EOF
  exit 0
}

# Check on minimal command line argument count
REQUIRED_ARGUMENT_COUNT=1
if [[ $# -lt $REQUIRED_ARGUMENT_COUNT ]]; then
  echo "Insufficient command line arguments!"
  echo "Use $0 --help to get additional information."
  exit -1
fi

# Script Configuration start
# The base directory where Typo3 should be installed
BASE=typo3
# The version to install
VERSION=$1
# The hostname of the MySQL server that Typo3 uses
HOST=localhost
# The username used to connect to that MySQL server
USER=*username*
# The password for that user
PASS=*password*
# The name of the database in which Typo3 is stored
DB=typo3
# Should the database configuration be written to the Typo3 configuration?
SKIP_DB_CONFIG=false
# Should the detection of GraphicsMagick be skipped?
SKIP_GM_DETECT=false
# Should the detection of the unzip utility be skipped?
SKIP_UNZIP_DETECT=false
# Should we try to fix access permissions for files of the new
# installation?
SKIP_RIGHTS=false
# The owner of the Typo3 installation
OWNER=$(id --user --name)
# The group the local http daemon is running as (usually www-data or apache)
HTTPD_GROUP=www-data
# Script Configuration end

# Pre-initialize password to random 16-character string if possible
if [[ -e /dev/urandom ]]; then
  PASS=$(head --bytes=100 /dev/urandom | sha1sum | head --bytes=16)
fi

# Pre-initialize the owner to the user that called sudo (if applicable)
if [ "$(id -u)" == "0" ]; then
  OWNER=$SUDO_USER
fi

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

# Read external configuration (overwrites default, hard-coded configuration)
CONFIG_FILENAME=${SELF:0:${#SELF}-3}.conf
if [[ -e "$CONFIG_FILENAME" ]] && [[ "$1" != "--help" ]] && [[ "$1" != "-h" ]]; then
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
    --version=*)
      VERSION=$(echo $option | cut -d'=' -f2)
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

# Update check
SUM_LATEST=$(curl $UPDATE_BASE/versions 2>&1 | grep $SELF | awk '{print $1}')
SUM_SELF=$(md5sum "$0" | awk '{print $1}')
if [[ "$SUM_LATEST" != "$SUM_SELF" ]]; then
  echo "NOTE: New version available!"
fi

# Begin main operation

# Check for existing installations
if [[ -d "$BASE" ]]; then
  echo "A directory named $BASE already exists. $SELF will not overwrite existing content."
  echo "Please remove the folder $BASE manually and run this script again."
  exit 1
fi

# Check argument validity
if [[ $VERSION == --* ]]; then
  echo "The given Typo3 version '$VERSION' looks like a command line parameter."
  echo "Please use the --version parameter when giving multiple arguments."
  exit 1
fi

# Are we running as root?
if [ "$(id -u)" != "0" ]; then
  if ! $SKIP_RIGHTS; then
    SKIP_RIGHTS=true
    echo "Adjusting access rights for the target installation will be skipped because this script is not running with root privileges!"
  fi
fi

# The name of the package and the folder it will live in
VERSION_NAME=blankpackage-$VERSION
# The name of the file that contains the package
VERSION_FILENAME=$VERSION_NAME.tar.gz
# The location where the package can be downloaded
TYPO3_DOWNLOAD_URL=http://prdownloads.sourceforge.net/typo3/$VERSION_FILENAME

echo -n "Looking for Typo3 package at $VERSION_FILENAME..."
if [[ ! -e "$VERSION_FILENAME" ]]; then
  echo "NOT found!"
  echo -n "Downloading $TYPO3_DOWNLOAD_URL..."
  wget --quiet $TYPO3_DOWNLOAD_URL --output-document=$VERSION_FILENAME
else
  echo "Found!"
  echo -n "Trying to resume download from $TYPO3_DOWNLOAD_URL..."
  wget --quiet --continue $TYPO3_DOWNLOAD_URL --output-document=$VERSION_FILENAME
fi
echo "Done."

echo -n "Extracting Typo3 package $VERSION_FILENAME..."
if ! tar --extract --gzip --file $VERSION_FILENAME; then
  echo "Failed!"
  exit 1
fi
echo "Done."

echo -n "Moving Typo3 package to $BASE..."
if ! mv $VERSION_NAME $BASE; then
  echo "Failed!"
  exit 1
fi
echo "Done."

# Generate configuration

# Print a single newline, but only the first time it is called
_NEWLINE_PRINTED=false
function newLineOnce() {
  if $_NEWLINE_PRINTED; then
      return
  fi
  echo
  _NEWLINE_PRINTED=true
}

echo -n "Generating localconf.php..."
TYPO3_CONFIG=

# Add database configuration
if ! $SKIP_DB_CONFIG; then
  TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db_username = '$USER';\n"
  TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db_password = '$PASS';\n"
  TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db_host     = '$HOST';\n"
  # Writing the database name is currently disabled. There doesn't seem to be
  # any advantage to it and it conflicts with the Typo3 installer.
  #TYPO3_CONFIG=$TYPO3_CONFIG"\$typo_db          = '$DB';\n"
fi

# Add GraphicsMagick (if available)
if ! $SKIP_GM_DETECT; then
  if ! hash gm 2>&-; then
    newLineOnce
    echo "  Could not find GraphicsMagick binary. im_version_5 will not be set."
  else
    LOCATION_GM=$(which gm)
    TYPO3_CONFIG=$TYPO3_CONFIG"\$TYPO3_CONF_VARS['GFX']['im_version_5'] = '$LOCATION_GM';\n"
  fi
fi

# Add unzip utility
if ! $SKIP_UNZIP_DETECT; then
  if ! hash unzip 2>&-; then
    newLineOnce
    echo "  Could not find unzip binary. unzip_path will not be set."
  else
    LOCATION_UNZIP=$(which unzip)
    TYPO3_CONFIG=$TYPO3_CONFIG"\$TYPO3_CONF_VARS['BE']['unzip_path'] = '$LOCATION_UNZIP';\n"
  fi
fi

# Write configuration
if ! cp $BASE/typo3conf/localconf.php $BASE/typo3conf/localconf.php.orig; then
  echo "Failed! Unable to create copy of localconf.php"
  exit 1
fi

if ! sed "/^## INSTALL SCRIPT EDIT POINT TOKEN/a $TYPO3_CONFIG" $BASE/typo3conf/localconf.php.orig > $BASE/typo3conf/localconf.php; then
  echo "Failed! Unable to modify localconf.php"
  exit 1
fi
echo "Done."

# Fix permissions
if ! $SKIP_RIGHTS; then
  echo -n "Adjusting access permissions for Typo3 installation..."
  if ! $(id --group $HTTPD_GROUP > /dev/null); then
    echo "Failed! The supplied group '$HTTPD_GROUP' is not known on the system."
    exit 1
  else
    sudo chown --recursive $OWNER $BASE
    sudo chgrp --recursive $HTTPD_GROUP $BASE/fileadmin $BASE/typo3temp $BASE/typo3conf $BASE/uploads
    sudo chmod --recursive g+rwX,o-w $BASE/fileadmin $BASE/typo3temp $BASE/typo3conf $BASE/uploads
  fi
  echo "Done."
fi

# Enable install tool
echo -n "Enabling install tool..."
touch $BASE/typo3conf/ENABLE_INSTALL_TOOL
echo "Done."

# vim:ts=2:sw=2:expandtab: