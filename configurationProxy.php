#!/usr/bin/php
<?php
// TYPO3 Configuration Manipulation Helper
// written by Oliver Salzburg

define( "SELF", basename( __FILE__ ) );
define( "INVNAME", $argv[ 0 ] );

/**
 * Show the help for this script
 * @name string The name of this script as invoked by the user (usually $argv[0])
 */
function showHelp( $name ) {
  echo <<<EOS
  Usage: $name [OPTIONS] [--extension=]EXTKEY
  
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
  --dump              Prints out a dump of the current configuration.
  --get=SETTING       Retrieves the value for the configuration item SETTING.
  --set=SETTING       Marks SETTING to be changed by --value.
  --value=VALUE       Sets previously marked setting to VALUE.

EOS;
}

/**
 * Print the default configuration to ease creation of a config file.
 */
function exportConfig() {
  $config = "";
  preg_match_all( "/# Script Configuration start.+?# Script Configuration end/ms", file_get_contents( INVNAME ), $config );
  $_configuration = preg_replace( "/\\$(?P<name>[^=]+)\s*=\s*\"(?P<value>[^\"]*)\";/", "\\1=\\2", $config[ 0 ][ 1 ] );
  echo $_configuration;
}

function extractConfig() {
  echo "Extracting a configuration is currently not supported!\n";
  return;

  $LOCALCONF = $BASE . "/typo3conf/localconf.php";
  $_configFileContent = file_get_contents( $LOCALCONF );

  $_hostMatch = "";
  preg_match_all( "/(?<=typo_db_host = ')[^']*(?=';)/", $_configFileContent, $_hostMatch );
}

define( "REQUIRED_ARGUMENT_COUNT", 1 );
if( $argc <= REQUIRED_ARGUMENT_COUNT ) {
  consoleWriteLine( "Insufficient command line arguments!" );
  consoleWriteLine( "Use " . INVNAME . " --help to get additional information." );
  exit( 1 );
}

# Script Configuration start
# Should the script give more detailed feedback?
$VERBOSE="false";
# Should the script surpress all feedback?
$QUIET="false";
# Should the script ignore reasons that would otherwise cause it to abort?
$FORCE="false";
# The base directory where Typo3 is installed
$BASE="typo3";
# The hostname of the MySQL server that Typo3 uses
$HOST="localhost";
# The username used to connect to that MySQL server
$USER="*username*";
# The password for that user
$PASS="*password*";
# The name of the database in which Typo3 is stored
$DB="typo3";
# The extension key for which to retrieve the changelog
# Should the whole configuration be printed?
$DUMP="false";
# The name of the variable for which the value should be retrieved.
$GET_VARIABLE="";
# The name of the variable that should be set to a given value.
$SET_VARIABLE="";
# The value for the variable that should be set.
$VARIABLE_VALUE="";
# Script Configuration end

function consoleWrite( $args ) {
  if( "false" == "$QUIET" ) file_put_contents( "php://stderr", $args );
  return 0;
}
function consoleWriteLine( $args ) {
  if( "false" == "$QUIET" ) file_put_contents( "php://stderr", $args . "\n" );
  return 0;
}
function consoleWriteVerbose( $args ) {
  if( $VERBOSE ) consoleWrite( $args );
  return 0;
}
function consoleWriteLineVerbose( $args ) {
  if( $VERBOSE ) consoleWriteLine( $args );
  return 0;
}

// The base location from where to retrieve new versions of this script
$UPDATE_BASE = "https://raw.github.com/oliversalzburg/typo3scripts/master";

/**
 * Update check
 */
function updateCheck() {
  $_contentVersions = file_get_contents( $UPDATE_BASE . "/versions" );
  $_contentSelf     = split( "\n", file_get_contents( INVNAME ), 2 );
  $_sumSelf         = md5( $_contentSelf[ 1 ] );
  
  consoleWriteLineVerbose( "Remote hash source: '" . $UPDATE_BASE . "/versions'" );
  consoleWriteLineVerbose( "Own hash: '" . $SUM_SELF . "' Remote hash: '" . $SUM_LATEST . "'" );
  
  $_isListed = preg_match( "/^" . SELF . " (?P<sum>[0-9a-zA-Z]{32})/ms", $_contentVersions, $_sumLatest );
  if( !$_isListed ) {
    consoleWriteLine( "No update information is available for '" . SELF . "'." );
    consoleWriteLine( "Please check the project home page https://github.com/oliversalzburg/typo3scripts." );
    return 2;
    
  } else if( $_sumSelf != $_sumLatest[ 1 ] ) {
    consoleWriteLine( "NOTE: New version available!" );
    return 1;
  }
  return 0;
}

/**
 * Self-update
 */
function runSelfUpdate() {
  echo "Performing self-update...\n";

  $_tempFileName = INVNAME . ".tmp";
  
  // Download new version
  echo "Downloading latest version...";
  global $UPDATE_BASE;
  $_fileContents = @file_get_contents( $UPDATE_BASE . "/" . SELF );
  if( strlen( $_fileContents ) <= 0 ) {
    echo "Failed: Error while trying to download new version!\n";
    echo "File requested: " . $UPDATE_BASE . "/" . SELF . "\n";
    exit( 1 );
  }
  $_payload = split( "\n", $_fileContents, 2 );
  echo "Done.\n";
  
  // Restore shebang
  $_selfContent = split( "\n", file_get_contents( INVNAME ), 2 );
  $_interpreter = $_selfContent[ 0 ];
  file_put_contents( $_tempFileName, $_interpreter . "\n" );
  file_put_contents( $_tempFileName, $_payload[ 1 ], FILE_APPEND );
  
  // Copy over modes from old version
  $_octalMode = fileperms( INVNAME );
  if( FALSE == chmod( $_tempFileName, $_octalMode ) ) {
    echo "Failed: Error while trying to set mode on $_tempFileName.\n";
    exit( 1 );
  }
  
  // Spawn update script
  $_name = INVNAME;
  $_updateScript = <<<EOS
#!/bin/bash
# Overwrite old file with new
if mv "$_tempFileName" "$_name"; then
  echo "Done."
  echo "Update complete."
  rm -- $0
else
  echo "Failed!"
fi
EOS;
  file_put_contents( "updateScript.sh", $_updateScript );

  echo "Inserting update process...";
  file_put_contents( "updateScript.sh", $_updateScript );
  chmod( "updateScript.sh", 0700 );

  if( function_exists( "pcntl_exec" ) ) {
    pcntl_exec( "/bin/bash", array( "./updateScript.sh" ) );
    
  } else if( function_exists( "passthru" ) ) {
    die( passthru( "./updateScript.sh" ) );
    
  } else {
    die( "Please execute ./updateScript.sh now." );
  }
}

# Make a quick run through the command line arguments to see if the user wants
# to print the help. This saves us a lot of headache with respecting the order
# in which configuration parameters have to be overwritten.
foreach( $argv as $_option ) {
  if( 0 === strpos( $_option, "--help" ) || 0 === strpos( $_option, "-h" ) ) {
    showHelp( $argv[ 0 ] );
    exit( 0 );
  }
}

// Read external configuration - Stage 1 - typo3scripts.conf (overwrites default, hard-coded configuration)
$BASE_CONFIG_FILENAME = "typo3scripts.conf";
if( file_exists( $BASE_CONFIG_FILENAME ) ) {
  if( is_readable( $BASE_CONFIG_FILENAME ) ) {
    consoleWriteLine( "Unable to read '" . $BASE_CONFIG_FILENAME . "'. Check permissions." );
    exit( 1 );
  }
  consoleWriteVerbose( "Sourcing script configuration from " . $BASE_CONFIG_FILENAME . "..." );
  $_baseConfig = file_get_contents( $BASE_CONFIG_FILENAME );
  $_baseConfigFixed = preg_replace( "/^(?!\s*$)(?P<name>[^#][^=]+)\s*=\s*(?P<value>[^$]*?)$/ms", "$\\1=\"\\2\";", $_baseConfig );
  eval( $_baseConfigFixed );
  consoleWriteLineVerbose( "Done." );
}

// Read external configuration - Stage 2 - script-specific (overwrites default, hard-coded configuration)
$CONFIG_FILENAME = substr( SELF, 0, -4 ) . ".conf";
if( file_exists( $CONFIG_FILENAME ) ) {
  if( is_readable( $CONFIG_FILENAME ) ) {
    consoleWriteLine( "Unable to read '" . $CONFIG_FILENAME . "'. Check permissions." );
    exit( 1 );
  }
  consoleWriteVerbose( "Sourcing script configuration from " . $CONFIG_FILENAME . "..." );
  $_config = file_get_contents( $CONFIG_FILENAME );
  $_configFixed = preg_replace( "/^(?!\s*$)(?P<name>[^#][^=]+)\s*=\s*(?P<value>[^$]*?)$/ms", "$\\1=\"\\2\";", $_config );
  eval( $_configFixed );
  consoleWriteLineVerbose( "Done." );
}

foreach( $argv as $_option ) {
  if( $_option === $argv[ 0 ] ) continue;

         if( 0 === strpos( $_option, "--verbose" ) ) {
    $VERBOSE = "true";
    
  } else if( 0 === strpos( $_option, "--quiet" ) ) {
    $QUIET = "true";
  
  } else if( 0 === strpos( $_option, "--force" ) ) {
    $FORCE = "true";
      
  } else if( 0 === strpos( $_option, "--update" ) ) {
    runSelfUpdate();
    
  } else if( 0 === strpos( $_option, "--update-check" ) ) {
    $returnValue = updateCheck();
    exit( $returnValue );

  } else if( 0 === strpos( $_option, "--base=" ) ) {
    $BASE = substr( $_option, strpos( $_option, "=" ) + 1 );

  } else if( 0 === strpos( $_option, "--export-config" ) ) {
    exportConfig();
    exit( 0 );

  } else if( 0 === strpos( $_option, "--extract-config" ) ) {
    extractConfig();
    exit( 0 );
    
  } else if( 0 === strpos( $_option, "--dump" ) ) {
    $DUMP    = "true";
    
  } else if( 0 === strpos( $_option, "--get=" ) ) {
    $GET_VARIABLE = substr( $_option, strpos( $_option, "=" ) + 1 );
  
  } else if( 0 === strpos( $_option, "--set=" ) ) {
    $SET_VARIABLE = substr( $_option, strpos( $_option, "=" ) + 1 );
    
  } else if( 0 === strpos( $_option, "--value=" ) ) {
    $VARIABLE_VALUE = substr( $_option, strpos( $_option, "=" ) + 1 );
    
  } else {
    $GET_VARIABLE = $_option;
  }
}

// Begin main operation

$GLOBALS[ 'TYPO3_CONF_VARS' ] = require( "typo3/typo3conf/LocalConfiguration.php" );

echo "<?php\n";
echo "return ";
var_export($GLOBALS['TYPO3_CONF_VARS']);
echo ";";

# vim:ts=2:sw=2:expandtab: