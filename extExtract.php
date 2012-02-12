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
  --help                 Display this help and exit.
  --update               Tries to update the script to the latest version.
  --base=PATH            The name of the base path where Typo3 is
                         installed. If no base is supplied, "typo3" is used.
  --export-config        Prints the default configuration of this script.
  --extract-config       Extracts configuration parameters from TYPO3.
  
  Options:
  --extension=EXTKEY     The extension key of the extension that should be
                         operated on.
  --dump                 Prints out a dump of the data structure of the
                         extension file.
  --extract              Forces the extraction process even if other commands
                         were invoked.
  --output-dir=DIRECTORY The DIRECTORY to where the extension should be
                         extracted.

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
  file_put_contents( "php://stderr", "Insufficient command line arguments!\n" );
  file_put_contents( "php://stderr", "Use INVNAME --help to get additional information.\n" );
  exit( 1 );
}

# Script Configuration start
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
$EXTENSION="";
# The directory to where the extension should be extracted.
$OUTPUTDIR="";
# Should the data structure of the extension be printed?
$DUMP="false";
# Should the extraction process be skipped?
$EXTRACT="true";
# Script Configuration end

// The base location from where to retrieve new versions of this script
define( "UPDATE_BASE", "http://typo3scripts.googlecode.com/svn/trunk" );

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
  pcntl_exec( "updateScript.sh" );
}

# Make a quick run through the command line arguments to see if the user wants
# to print the help. This saves us a lot of headache with respecting the order
# in which configuration parameters have to be overwritten.
foreach( $argv as $_option ) {
  if( 0 === strpos( $_option, "--help" ) || 0 === strpos( $_option, "-h" ) ) {
    showHelp( $argv[ 0 ] );
    exit( 0 )
    ;;
  }
}

// Read external configuration - Stage 1 - typo3scripts.conf (overwrites default, hard-coded configuration)
define( "BASE_CONFIG_FILENAME", "typo3scripts.conf" );
if( file_exists( BASE_CONFIG_FILENAME ) ) {
  file_put_contents( "php://stderr", "Sourcing script configuration from " . BASE_CONFIG_FILENAME . "..." );
  $_baseConfig = file_get_contents( BASE_CONFIG_FILENAME );
  $_baseConfigFixed = preg_replace( "/^(?P<name>[^#][^=]+)\s*=\s*(?P<value>[^$]*?)$/ms", "$\\1=\"\\2\";", $_baseConfig );
  eval( $_baseConfigFixed );
  file_put_contents( "php://stderr", "Done.\n" );
}

// Read external configuration - Stage 2 - script-specific (overwrites default, hard-coded configuration)
define( "CONFIG_FILENAME", substr( SELF, 0, -4 ) . ".conf" );
if( file_exists( CONFIG_FILENAME ) ) {
  file_put_contents( "php://stderr", "Sourcing script configuration from " . CONFIG_FILENAME . "..." );
  $_config = file_get_contents( CONFIG_FILENAME );
  $_configFixed = preg_replace( "/^(?P<name>[^#][^=]+)\s*=\s*(?P<value>[^$]*?)$/ms", "$\\1=\"\\2\";", $_config );
  eval( $_configFixed );
  file_put_contents( "php://stderr", "Done.\n" );
}

foreach( $argv as $_option ) {
  if( $_option === $argv[ 0 ] ) continue;

  if( 0 === strpos( $_option, "--update" ) ) {
    runSelfUpdate();

  } else if( 0 === strpos( $_option, "--base=" ) ) {
    $BASE = substr( $_option, strpos( $_option, "=" ) + 1 );

  } else if( 0 === strpos( $_option, "--export-config" ) ) {
    exportConfig();
    exit( 0 );

  } else if( 0 === strpos( $_option, "--extract-config" ) ) {
    extractConfig();
    exit( 0 );

  } else if( 0 === strpos( $_option, "--extension=" ) ) {
    $EXTENSION = substr( $_option, strpos( $_option, "=" ) + 1 );
    
  } else if( 0 === strpos( $_option, "--dump" ) ) {
    $DUMP    = "true";
    $EXTRACT = "false";
  
  } else if( 0 === strpos( $_option, "--extract" ) ) {
    $EXTRACT = "true";
    
  } else if( 0 === strpos( $_option, "--output-dir=" ) ) {
    $OUTPUTDIR = substr( $_option, strpos( $_option, "=" ) + 1 );

  } else {
    $EXTENSION = $_option;
  }
}

// Update check
$_sumLatest = file_get_contents( UPDATE_BASE . "/versions" );
$_isListed = preg_match( "/^(?P<sum>[0-9a-zA-Z]{32})\s*" . SELF ."/ms", $_sumLatest, $_ownSumLatest );
if( !$_isListed ) {
  file_put_contents( "php://stderr", "No update information is yet available for " . SELF . ".\n" );
} else {
  file_put_contents( "php://stderr", "Update checking isn't yet implemented for " . SELF . ".\n" );
}

// Begin main operation

// Check argument validity
if( 0 === strpos( $EXTENSION, "--" ) ) {
  echo "The given extension key '$EXTENSION' looks like a command line parameter.\n";
  echo "Please use the --extension parameter when giving multiple arguments.\n";
  exit( 1 );
}

// Is the provided extension not just an extension key, but a filename?
$_extensionFile = $EXTENSION;
if( !file_exists( $_extensionFile ) ) {
  // It must be a reference to an extension installed in the local TYPO3 installation.
  if( file_exists( "$BASE/typo3conf/ext/$EXTENSION" ) ) {
    file_put_contents( "php://stderr", "Retrieving original extension file for '$BASE/typo3conf/ext/$EXTENSION'..." );
    $_extensionFile = "downloaded.temp";
    
  } else {
    file_put_contents( "php://stderr", "Unable to find extension '$EXTENSION'.\n" );
    file_put_contents( "php://stderr", "Directory requested: '$BASE/typo3conf/ext/$EXTENSION'\n" );
    exit( 1 );
  }
}

// If no output directory is yet defined, use the extension filename as a base
if( 0 === strlen( $OUTPUTDIR ) ) {
  $OUTPUTDIR = $_extensionFile . "-extracted";
}

// Don't overwrite existing data!
if( is_dir( $OUTPUTDIR ) ) {
  file_put_contents( "php://stderr", "Error: The target directory '$OUTPUTDIR' already exists.\n" );
  exit( 1 );
}

/**
 * Extracts extension array from extension file.
 */
function extractExtensionData( $extensionFile ) {
  if( file_exists( $extensionFile ) ) {
    $_fileContents = file_get_contents( $extensionFile );
    $_fileParts = explode( ":", $_fileContents, 3 );
    $_extensionContent = "";
    if( "gzcompress" == $_fileParts[ 1 ] ) {
      if( function_exists( "gzuncompress" ) ) {
        $_extensionContent = gzuncompress( $_fileParts[ 2 ] );
  
      } else {
        file_put_contents( "php://stderr", "Error: Unable to decode extension. gzuncompress() is unavailable.\n" );
        exit( 1 );
      }
    }
    $_extension = null;
    if( md5( $_extensionContent ) == $_fileParts[ 0 ] ) {
      $_extension = unserialize( $_extensionContent );
      if( is_array( $_extension ) ) {
        return $_extension;
        
      } else {
        file_put_contents( "php://stderr", "Error: Unable to unserialize extension! (Shouldn't happen)\n" );
        exit( 1 );
      }
    } else {
      file_put_contents( "php://stderr", "Error: MD5 mismatch. Extension file may be corrupt!\n" );
      exit( 1 );
    }
  
  } else {
    file_put_contents( "php://stderr", "Error: Unable to open '$_extensionFile'!\n" );
    exit( 1 );
  }
}

/**
 * Dump the contents of a PHP array and apply some pretty-printing
 */
function printArray( $array, $indent, $nameIndent ) {
  foreach( $array as $name => $value ) {
    echo $indent . $name . substr( $nameIndent, 0, -strlen( $name ) ) . " = ";
    if( is_array( $value ) ) {
      echo "\n";

      $_maxValueLength = 0;
      foreach( $value as $string => $_ignoredValue ) {
        if( strlen( $string ) > $_maxValueLength ) {
          $_maxValueLength = strlen( $string );
        }
      }
      printArray( $value, $indent . "  ", str_repeat( " ", $_maxValueLength  ) );

    } else if( is_int( $value ) ) {
      echo $value;

    } else if( is_string( $value ) ) {
      $_stringValue = quoted_printable_encode( $value );
      $_stringValueLength = strlen( $_stringValue );
      echo ( $_stringValueLength > 60 ) ? "String[$_stringValueLength]" : $_stringValue;
    }
    echo "\n";
  }
}

file_put_contents( "php://stderr", "Extracting file '$_extensionFile'..." );
$_extension = extractExtensionData( $_extensionFile );

// Dump data structure first (if requested).
// $DUMP is a string due to configuration file interoperability concerns
if( $DUMP === "true" ) {
  printArray( $_extension, "", "" );
}

if( $EXTRACT === "true" ) {
  // Extract contents
  foreach( $_extension[ "FILES" ] as $_filename => $_file ) {
    $_directoryName = dirname( $_file[ "name" ] );
  
    $_fullPathName = $OUTPUTDIR . "/" . $_directoryName;
    // is_dir() and mkdir() seem highly unreliable in their return values,
    // so we must ignore failures on mkdir() and have to catch issues later.
    if( FALSE === is_dir( $_fullPathName ) ) {
      @mkdir( $_fullPathName, 0700, true );
    }
    
    $_fullFileName = $OUTPUTDIR . "/" . $_file[ "name" ];
    if( FALSE === file_put_contents( $_fullFileName, $_file[ "content" ] ) ) {
      file_put_contents( "php://stderr", "Error: Failed to write file '$_fullFileName'.\n" );
    }
  }
  file_put_contents( "php://stderr", "Done.\n" );
  
} else {
  file_put_contents( "php://stderr", "Skipped.\n" );
}



# vim:ts=2:sw=2:expandtab:
?>
