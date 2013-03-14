This is a collection of shell scripts that aid in TYPO3 deployment and maintenance.

The scripts in this project and their primary intended purpose are outlined as such:

- [bootstrap.sh](https://github.com/oliversalzburg/typo3scripts/wiki/BootstrapSh)  
  Starting a new TYPO3 installation (no relation to Twitter Bootstrap).
- [createBackup.sh](https://github.com/oliversalzburg/typo3scripts/wiki/CreateBackupSh)  
  Creates a snapshot of a TYPO3 installation.
- [restoreBackup.sh](https://github.com/oliversalzburg/typo3scripts/wiki/RestoreBackupSh)  
  Restores aforementioned snapshots.
- [switchVersion.sh](https://github.com/oliversalzburg/typo3scripts/wiki/SwitchVersionSh)  
  Switches between multiple versions of the TYPO3 core package.
- [fixPermissions.sh](https://github.com/oliversalzburg/typo3scripts/wiki/FixPermissionsSh)  
  Fixes access permissions on the files of a TYPO3 installation.
- [extChangelog.sh](https://github.com/oliversalzburg/typo3scripts/wiki/ExtChangelogSh)  
  Retrieve the upload comment history for an extension.
- [extUpdate.sh](https://github.com/oliversalzburg/typo3scripts/wiki/ExtUpdateSh)  
  Retrieve update information for an extension (or all extensions) directly from the shell.
- [extExtract.php](https://github.com/oliversalzburg/typo3scripts/wiki/ExtExtractPhp)  
  Extract and save or display the contents of a `.t3x` file.



## Downloads

After moving to GitHub, we no longer provide any pre-packaged downloads. If you want to retrieve the scripts without the use of git, please use the the [download as ZIP](archive/master.zip) feature. 

The recommended way of obtaining a needed script is directly from the source repository like so:

    $ wget https://raw.github.com/oliversalzburg/typo3scripts/master/bootstrap.sh

You can obtain the latest development version of a script the same way:

    $ wget https://raw.github.com/oliversalzburg/typo3scripts/dev/bootstrap.sh

Optionally, you can clone the whole project:

    $ git clone git://github.com/oliversalzburg/typo3scripts.git /var/www/my-typo3-site/

## Usage Examples
These usage examples should give a quick overview of the main, intended purpose of the provided scripts. For additional applications of these scripts, please see their dedicated wiki pages (as available).

### Creating a new TYPO3 installation with bootstrap.sh
This is the output of a run of `bootstrap.sh` creating a fresh installation of TYPO3.

    /var/www/t3site$ sudo ./bootstrap.sh
	Checking dependencies...Succeeded.
	Using TYPO3 package store '.'.
	Trying to resume download from 'http://prdownloads.sourceforge.net/typo3/blankpackage-4.7.7.tar.gz'...Done.
	Extracting TYPO3 package './blankpackage-4.7.7.tar.gz'...Done.
	Moving TYPO3 package to 'typo3'...Done.
	Generating localconf.php...Done.
	Adjusting access permissions for TYPO3 installation...Done.
	
	Your TYPO3 Install Tool password is: '541b883dce0a3699'

### Creating a backup of a TYPO3 installation with createBackup.sh
This is the output of a run of `createBackup.sh` creating a backup of a TYPO3 installation.

    /var/www/t3site$ sudo ./createBackup.sh
	Checking dependencies...Succeeded.
	Creating TYPO3 backup 'typo3-2013-03-14-23-43.tgz'...
	Creating database dump at 'typo3/database.sql'...Done
	Compressing TYPO3 installation...Done.

### Restoring a backup with restoreBackup.sh
This is the output of a run of `restoreBackup.sh` restoring a backup snapshot previously created by a run of `createBackup.sh`.

    /var/www/t3site$ sudo ./restoreBackup.sh typo3-2013-03-14-23-43.tgz
	Checking dependencies...Succeeded.
	Testing write permissions in typo3...Succeeded
	Erasing current TYPO3 installation 'typo3'...Done.
	Extracting TYPO3 backup 'typo3-2013-03-14-23-43.tgz'...Done.
	Importing database dump...Done.

### Upgrading a TYPO3 installation with switchVersion.sh
This is the output of a run of `switchVersion.sh` switching (in this case upgrading) a TYPO3 installation to version 4.6.3.

    /var/www/t3site$ ./switchVersion.sh 4.7.8
	Checking dependencies...Succeeded.
	Using TYPO3 package store 'typo3'.
	Downloading http://prdownloads.sourceforge.net/typo3/typo3_src-4.7.8.tar.gz...Done.
	Extracting source package typo3/typo3_src-4.7.8.tar.gz...Done.
	Switching TYPO3 source symlink to 'typo3/typo3_src-4.7.8/'...Done.
	Checking 't3lib' symlink...Skipped.
	Checking 'typo3' symlink...Skipped.
	Done!
	Version switched to 4.7.8.

### Cloning a TYPO3 installation using createBackup.sh and restoreBackup.sh
In the latest development builds, you're able to restore a backup made on a different installation, thus, replicating the original installation.

    /var/www/t3site$ sudo ./createBackup.sh
    Checking dependencies...Succeeded.
    Creating TYPO3 backup 'typo3-2012-11-28-16-32.tgz'...
    Creating database dump at 'typo3/database.sql'...Done.
    Compressing TYPO3 installation...Done.
    /var/www/t3site$ cp typo3-2012-11-28-16-32.tgz ../t3site-test/
    /var/www/t3site$ cd ../t3site-test/
    /var/www/t3site-test$ sudo ./restoreBackup.sh typo3-2012-11-28-16-32.tgz
    Checking dependencies...Succeeded.
    Testing write permissions in typo3...Succeeded
    Erasing current TYPO3 installation 'typo3'...Done.
    Extracting TYPO3 backup 'typo3-2012-11-28-16-32.tgz'...Done.
    Importing database dump...Done.

You may have to utilize [fixPermissions.sh](wiki/FixPermissionsSh) afterwards to adjust permissions for your webserver user. You'll also have to adjust your database settings and domain records in the cloned TYPO3 instance afterwards.