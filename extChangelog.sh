#!/bin/bash

# TYPO3 Extension Changelog Extraction Script
# written by Oliver Salzburg

set -o nounset
set -o errexit

SELF=$(basename "$0")

# Show the help for this script
function showHelp() {
  cat << EOF
  Usage: $0 [OPTIONS] [--extension=]EXTKEY

  Core:
  --help              Display this help and exit.
  --update            Tries to update the script to the latest version.
  --base=PATH         The name of the base path where Typo3 is
                      installed. If no base is supplied, "typo3" is used.
  --export-config     Prints the default configuration of this script.
  --extract-config    Extracts configuration parameters from TYPO3.
  
  Options:
  --extension=EXTKEY  The extension key of the extension for which to retrieve
                      the changelog.
  --first=VERSION     The first version that should be listed.
  --last=VERSION      The last version that should be listed.
  --skip-first        Skip the first found version.

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
REQUIRED_ARGUMENT_COUNT=1
if [[ $# -lt $REQUIRED_ARGUMENT_COUNT ]]; then
  echo "Insufficient command line arguments!" >&2
  echo "Use $0 --help to get additional information." >&2
  exit 1
fi

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
# The extension key for which to retrieve the changelog
EXTENSION=
# The first version to list
VERSION_FIRST=
# The last version to list
VERSION_LAST=
# Should the first found version be skipped?
SKIP_FIRST=0
# Script Configuration end

# The base location from where to retrieve new versions of this script
UPDATE_BASE=http://typo3scripts.googlecode.com/svn/trunk

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
  echo -n "Sourcing script configuration from $BASE_CONFIG_FILENAME..." >&2
  source $BASE_CONFIG_FILENAME
  echo "Done." >&2
fi

# Read external configuration - Stage 2 - script-specific (overwrites default, hard-coded configuration)
CONFIG_FILENAME=${SELF:0:${#SELF}-3}.conf
if [[ -e "$CONFIG_FILENAME" ]]; then
  echo -n "Sourcing script configuration from $CONFIG_FILENAME..." >&2
  source $CONFIG_FILENAME
  echo "Done." >&2
fi

# Read command line arguments (overwrites config file)
for option in $*; do
  case "$option" in
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
    --extension=*)
      EXTENSION=$(echo $option | cut -d'=' -f2)
      ;;
    --first=*)
      VERSION_FIRST=$(echo $option | cut -d'=' -f2)
      ;;
    --last=*)
      VERSION_LAST=$(echo $option | cut -d'=' -f2)
      ;;
    --skip-first)
      SKIP_FIRST=1
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

# Update check
SUM_LATEST=$(curl $UPDATE_BASE/versions 2>&1 | grep $SELF | awk '{print $2}')
SUM_SELF=$(tail --lines=+2 "$0" | md5sum | awk '{print $1}')
if [[ "" == $SUM_LATEST ]]; then
  echo "No update information is available for '$SELF'" >&2
  echo "Please check the project home page http://code.google.com/p/typo3scripts/." >&2
  
elif [[ "$SUM_LATEST" != "$SUM_SELF" ]]; then
  echo "NOTE: New version available!" >&2
fi

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

# Read upload comments from cached extensions data
echo -n "Retrieving upload comment history..." >&2
set +e errexit
_query="SELECT CONCAT(\`version\`,'\n',\`lastuploaddate\`,'\n',\`uploadcomment\`) FROM \`cache_extensions\` WHERE (\`extkey\` = '$EXTENSION');"
_errorMessage=$(echo $_query | mysql --host=$HOST --user=$USER --pass=$PASS --database=$DB --batch --skip-column-names 2>&1 | sed 's/\\n/|/g' > extChangelog.out)
_status=$?
set -e errexit
if [[ 0 < $_status ]]; then
  echo "Failed!" >&2
  echo "Error: $_errorMessage" >&2
  exit 1
fi
echo "Done." >&2

_isFirstVersionFound=1
while read _versionEntry; do
  _versionString=$(echo $_versionEntry | cut --delimiter=\| --fields=1 -)
  _uploadDate=$(echo $_versionEntry | cut --delimiter=\| --fields=2 -)
  
  # Check if lower limit for version listing is provided
  if [[ $VERSION_FIRST != "" ]]; then
  
    set +e errexit
    compareVersions $_versionString $VERSION_FIRST
    _versionsEqual=$?
    set -e errexit
    
    case $_versionsEqual in
      0) 
        # Versions equal
        ;;
      1) 
        # This version comment is of a later version than the first we should list
        ;;
      2)
        # This version comment is of an earlier version than the first we should list, skip it
        continue
        ;;
    esac
    
  fi
  
  # Check if upper limit for version listing is provided
  if [[ $VERSION_LAST != "" ]]; then
  
    set +e errexit
    compareVersions $_versionString $VERSION_LAST
    _versionsEqual=$?
    set -e errexit
    
    case $_versionsEqual in
      0) 
        # Versions equal
        ;;
      1) 
        # This version comment is of a later version than the last we should list, skip it
        continue
        ;;
      2)
        # This version comment is of an earlier version than the last we should list
        ;;
    esac
    
  fi
  
  if [[ 1 == $SKIP_FIRST && 1 == $_isFirstVersionFound ]]; then
    _isFirstVersionFound=0
    continue
  fi
  
  echo $_versionString \($(date --date @$_uploadDate "+%Y-%m-%d %T")\)
  _versionComment=$(echo $_versionEntry | cut --delimiter=\| --fields=3- -)
  echo "  $_versionComment" | sed 's/|/\n  /g'
  
done < extChangelog.out

rm -f extChangelog.out

# vim:ts=2:sw=2:expandtab: