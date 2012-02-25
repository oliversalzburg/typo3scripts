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
  --extension=EXTKEY      The extension key of the extension that should be
                          operated on.
  --force-version=VERSION Forces download of specific extension version.
  --dump                  Prints out a dump of the data structure of the
                          extension file.
  --string-limit=LENGTH   The LENGTH at which string data should be summarized
                          as String[N]. Default: 60 No Limit: 0
  --extract               Forces the extraction process even if other commands
                          were invoked.
  --output-dir=DIRECTORY  The DIRECTORY to where the extension should be
                          extracted.
  --output-file[=NAME]    Write the downloaded extension file to disk with and
                          optional NAME.

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
  file_put_contents( "php://stderr", "Use " . INVNAME . " --help to get additional information.\n" );
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
$EXTENSION="";
# The directory to where the extension should be extracted.
$OUTPUTDIR="";
# The file where possibly downloaded, temporary files should be stored
$OUTPUTFILE="";
# Should the data structure of the extension be printed?
$DUMP="false";
# The length at which strings should be summarized in the dump output.
$STRING_LIMIT="60";
# Should the extraction process be skipped?
$EXTRACT="true";
# Force a specific extension version to be downloaded
$FORCE_VERSION="";
# Script Configuration end

// The base location from where to retrieve new versions of this script
$UPDATE_BASE = "http://typo3scripts.googlecode.com/svn/trunk";

/**
 * Update check
 */
function updateCheck() {
  $_contentVersions = file_get_contents( $UPDATE_BASE . "/versions" );
  $_contentSelf     = split( "\n", file_get_contents( INVNAME ), 2 );
  $_sumSelf         = md5( $_contentSelf[ 1 ] );
  
  $_isListed = preg_match( "/^" . SELF . " (?P<sum>[0-9a-zA-Z]{32})/ms", $_contentVersions, $_sumLatest );
  if( !$_isListed ) {
    file_put_contents( "php://stderr", "No update information is available for '" . SELF . "'.\n" );
    file_put_contents( "php://stderr", "Please check the project home page http://code.google.com/p/typo3scripts/.\n" );
    
  } else if( $_sumSelf != $_sumLatest[ 1 ] ) {
    file_put_contents( "php://stderr", "NOTE: New version available!\n" );
  }
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
  file_put_contents( "php://stderr", "Sourcing script configuration from " . $BASE_CONFIG_FILENAME . "..." );
  $_baseConfig = file_get_contents( $BASE_CONFIG_FILENAME );
  $_baseConfigFixed = preg_replace( "/^(?!\s*$)(?P<name>[^#][^=]+)\s*=\s*(?P<value>[^$]*?)$/ms", "$\\1=\"\\2\";", $_baseConfig );
  eval( $_baseConfigFixed );
  file_put_contents( "php://stderr", "Done.\n" );
}

// Read external configuration - Stage 2 - script-specific (overwrites default, hard-coded configuration)
$CONFIG_FILENAME = substr( SELF, 0, -4 ) . ".conf";
if( file_exists( $CONFIG_FILENAME ) ) {
  file_put_contents( "php://stderr", "Sourcing script configuration from " . $CONFIG_FILENAME . "..." );
  $_config = file_get_contents( $CONFIG_FILENAME );
  $_configFixed = preg_replace( "/^(?!\s*$)(?P<name>[^#][^=]+)\s*=\s*(?P<value>[^$]*?)$/ms", "$\\1=\"\\2\";", $_config );
  eval( $_configFixed );
  file_put_contents( "php://stderr", "Done.\n" );
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
    $returnValue = updateCheck()
    exit( $returnValue );

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
    
  } else if( 0 === strpos( $_option, "--force-version=" ) ) {
    $FORCE_VERSION = substr( $_option, strpos( $_option, "=" ) + 1 );
    
  } else if( 0 === strpos( $_option, "--dump" ) ) {
    $DUMP    = "true";
    $EXTRACT = "false";
    
  } else if( 0 === strpos( $_option, "--string-limit=" ) ) {
    $STRING_LIMIT = substr( $_option, strpos( $_option, "=" ) + 1 );
  
  } else if( 0 === strpos( $_option, "--extract" ) ) {
    $EXTRACT = "true";
    
  } else if( 0 === strpos( $_option, "--output-dir=" ) ) {
    $OUTPUTDIR = substr( $_option, strpos( $_option, "=" ) + 1 );

  } else if( 0 === strpos( $_option, "--output-file" ) ) {
    $_equalSignIndex = strpos( $_option, "=" );
    if( FALSE === $_equalSignIndex ) {
      $OUTPUTFILE = FALSE;
      
    } else {
      $OUTPUTFILE = substr( $_option, $_equalSignIndex + 1 );
    }
    echo "Output file ='" . $OUTPUTFILE . "'\n";
    
  } else {
    $EXTENSION = $_option;
  }
}

// Begin main operation

// Check argument validity
if( 0 === strpos( $EXTENSION, "--" ) ) {
  echo "The given extension key '$EXTENSION' looks like a command line parameter.\n";
  echo "Please use the --extension parameter when giving multiple arguments.\n";
  exit( 1 );
}

if( "" === $EXTENSION ) {
  echo "No extension given.\n";
  exit( 1 );
}

/**
 * Downloads an extension from the TYPO3 extension repository
 */
function downloadExtension( $_extKey, $_version ) {
  $_firstLetter  = substr( $_extKey, 0, 1 );
  $_secondLetter = substr( $_extKey, 1, 1 );
  $_t3xName      = $_extKey . "_" . $_version . ".t3x";
  $_extensionUrl = "http://typo3.org/fileadmin/ter/" . $_firstLetter . "/" . $_secondLetter . "/" . $_t3xName;
  
  $_extensionData = @file_get_contents( $_extensionUrl );
  if( FALSE === $_extensionData ) {
    file_put_contents( "php://stderr", "Error: Could not retrieve extension file.\n" );
    file_put_contents( "php://stderr", "File requested: $_extensionUrl\n" );
    exit( 1 );
  }
  
  $_tempFileName  = $_t3xName;
  global $OUTPUTFILE;
  if( FALSE !== $OUTPUTFILE && "" !== $OUTPUTFILE ) {
    $_tempFileName = $OUTPUTFILE;
  }
  
  file_put_contents( $_tempFileName, $_extensionData );
  if( "" === $OUTPUTFILE ) {
    register_shutdown_function( "cleanUpTempFile", &$_tempFileName );
  }
  
  return $_tempFileName;
}

function cleanUpTempFile( &$_tempFileName ) {
  unlink( $_tempFileName );
}

// Is the provided extension not just an extension key, but a filename?
$_extensionFile = $EXTENSION;
if( !file_exists( $_extensionFile ) ) {
  // It must be a reference to an extension installed in the local TYPO3 installation.
  $_extensionDirectory = "$BASE/typo3conf/ext/$EXTENSION";
  // But we only need to check it if the user doesn't want a specific version.
  if( is_dir( $_extensionDirectory ) && "" == $FORCE_VERSION ) {
    // The user wants to get the latest, official extension file for an installed extension
    file_put_contents( "php://stderr", "Retrieving original extension file for '$EXTENSION' " );
    $_extensionConfigFile = "$_extensionDirectory/ext_emconf.php";
    
    // While it's not very nice to polute our script with the contents of ext_emconf.php,
    // it's the most reliable way to parse the information.
    $_EXTKEY = $EXTENSION;
    include( $_extensionConfigFile );
    $_extensionConfiguration = $EM_CONF[ $EXTENSION ];
    
    $_installedVersion = $_extensionConfiguration[ "version" ];
    file_put_contents( "php://stderr", "$_installedVersion..." );
    
    $_tempFileName = downloadExtension( $EXTENSION, $_installedVersion );
    
    file_put_contents( "php://stderr", "Done.\n" );
    
    $_extensionFile = $_tempFileName;
    
  } else if( "" != $FORCE_VERSION ) {
    // The user is looking for a specific version of an extension. Retrieve it.
    file_put_contents( "php://stderr", "Retrieving original extension file for '$EXTENSION' " );
    
    file_put_contents( "php://stderr", "$FORCE_VERSION..." );
    
    $_tempFileName = downloadExtension( $EXTENSION, $FORCE_VERSION );
    
    file_put_contents( "php://stderr", "Done.\n" );
    
    $_extensionFile = $_tempFileName;
    
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
      $_valueLength = strlen( $value );
      global $STRING_LIMIT;
      // $STRING_LIMIT is a string due to configuration file interoperability concerns
      if( !ctype_print( $value ) || ( intval( $STRING_LIMIT ) > 0 && $_valueLength > intval( $STRING_LIMIT ) ) ) {
        echo "String[$_valueLength]";
        
      } else {
        echo $value;
      }
      
    } else {
      echo gettype( $value );
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

// Finally extract the extension files.
// $EXTRACT is a string due to configuration file interoperability concerns
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