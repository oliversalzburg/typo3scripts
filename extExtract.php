#!/usr/bin/php
<?php
// TYPO3 Extension Extraction Script
// written by Oliver Salzburg

define( "SELF", basename( __FILE__ ) );
define( "INVNAME", $argv[ 0 ] );
  
/**
 * Show the help for this script
 * @name string The name of this script as invoked by the user (usually $argv[0])
 */
function showHelp( $name ) {
  echo <<<EOS
  Usage: $name [OPTIONS]
  
  Core:
  --help              Display this help and exit.
  --update            Tries to update the script to the latest version.
  --base=PATH         The name of the base path where Typo3 is
                    installed. If no base is supplied, "typo3" is used.
  --export-config     Prints the default configuration of this script.
  --extract-config    Extracts configuration parameters from TYPO3.
  
  Options:
  --extension=EXTKEY  The extension key of the extension that should be
                      operated on.
EOS;
}

/**
 * Print the default configuration to ease creation of a config file.
 */
function exportConfig() {
  $config = "";
  preg_match_all( "/# Script Configuration start.+?# Script Configuration end/ms", file_get_contents( INVNAME ), $config );
  $_configuration = preg_replace( "/\\$/", "", $config[ 0 ][ 1 ] );
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

define( "REQUIRED_ARGUMENT_COUNT", 0 );
if( $argc < REQUIRED_ARGUMENT_COUNT ) {
  file_put_contents( "php://stderr", "Insufficient command line arguments!" );
  file_put_contents( "php://stderr", "Use INVNAME --help to get additional information." );
  exit( 1 );
}

# Script Configuration start
// The base directory where Typo3 is installed
$BASE="typo3";
// The hostname of the MySQL server that Typo3 uses
$HOST="localhost";
// The username used to connect to that MySQL server
$USER="*username*";
// The password for that user
$PASS="*password*";
// The name of the database in which Typo3 is stored
$DB="typo3";
// The extension key for which to retrieve the changelog
$EXTENSION="";
# Script Configuration end

// The base location from where to retrieve new versions of this script
#define( "UPDATE_BASE", "http://typo3scripts.googlecode.com/svn/trunk" );
define( "UPDATE_BASE", "http://typo3scripts.googlecode.com/svn/branches/dev" );

/**
 * Self-update
 */
function runSelfUpdate() {
  echo "Performing self-update...\n";

  $_tempFileName = INVNAME . ".tmp";

  // Download new version
  echo "Downloading latest version...";
  $_fileContents = @file_get_contents( UPDATE_BASE . "/" . SELF );
  if( strlen( $_fileContents ) <= 0 ) {
    echo "Failed: Error while trying to download new version!\n";
    echo "File requested: " . UPDATE_BASE . "/" . SELF . "\n";
    exit( 1 );
  }
  file_put_contents( $_tempFileName, $_fileContents );
  echo "Done.\n";

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
  echo "Done. Update complete."
  rm -- $0
else
  echo "Failed!"
fi
EOS;

  echo "Inserting update process...";
  pcntl_exec( "/bin/bash updateScript.sh" );
}

// Read external configuration - Stage 1 - typo3scripts.conf (overwrites default, hard-coded configuration)
define( "BASE_CONFIG_FILENAME", "typo3scripts.conf" );

exportConfig();

//echo $BASE;
# vim:ts=2:sw=2:expandtab:
?>
