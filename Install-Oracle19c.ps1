<#
.SYNOPSIS
    Installs Oracle Database 19c with customizable parameters.
.DESCRIPTION
    This script automates the installation of Oracle Database 19c on Windows systems.
    All installation parameters can be configured at the beginning of the script.
.NOTES
    File Name      : Install-Oracle19c.ps1
    Prerequisites  : PowerShell 5.1 or later, Administrator privileges
    Version        : 1.0

Customize the parameters at the beginning of the script according to your requirements:
Set paths (OracleBase, OracleHome, OracleInventory)
Configure database settings (SID, character set, passwords)
Specify the location of your Oracle installation files
Save the script as Install-Oracle19c.ps1
Run the script as Administrator: .\Install-Oracle19c.ps1

Important Notes
You must have the Oracle Database 19c installation files (zip) available at the specified location.
The script creates an Oracle Windows user account with the specified credentials.
The script performs a silent installation using a response file.
Make sure to use strong passwords for the database accounts.
The script assumes you're installing on a clean system - it doesn't handle upgrades or migrations.
You may need to adjust the script based on your specific environment requirements or Oracle version variations.
#>

#region Parameters - Customize these values for your installation
$OracleBase = "C:\app\oracle"
$OracleHome = "C:\app\oracle\product\19.0.0\dbhome_1"
$OracleInventory = "C:\Program Files\Oracle\Inventory"
$OracleInstallSource = "\\path\to\oracle\install\files" # or local path like "C:\temp\oracle_install"
$OracleInstallFile = "WINDOWS.X64_193000_db_home.zip"  # Name of the Oracle installation zip file

# Database configuration
$GlobalDatabaseName = "orcl.example.com"
$Sid = "orcl"
$CharacterSet = "AL32UTF8"
$NationalCharacterSet = "UTF8"
$MemoryPercentage = "40" # Percentage of total memory to allocate
$SysPassword = "MySysPassword123"
$SystemPassword = "MySystemPassword123"

# Windows accounts
$OracleUser = "oracle"  # Will be created if doesn't exist
$OraclePassword = "OracleAccountPassword123"

# Installation options
$InstallType = "EE" # EE = Enterprise Edition, SE = Standard Edition
$CreateDatabase = $true
$EnableArchiving = $true
$SampleSchema = $true
#endregion

#region Script Constants
$ResponseFileTemplate = @"
[GENERAL]
RESPONSEFILE_VERSION="19.0"
OPERATION_TYPE="install"
[UNIX_GROUP_NAME]
UNIX_GROUP_NAME=""
[LICENSE AGREEMENT]
ACCEPT_LICENSE_AGREEMENT=true
[TOPLEVEL_COMPONENT]
ORACLE_HOME="$OracleHome"
ORACLE_HOME_NAME="OraDB19Home1"
[INSTALL_TYPE]
INSTALL_TYPE="$InstallType"
[SELECTED_LANGUAGES]
SELECTED_LANGUAGES=en
[ORACLE_HOME_USER]
ORACLE_HOME_USER="$OracleUser"
[ORACLE_HOME_USER_PWD]
ORACLE_HOME_USER_PWD="$OraclePassword"
[ORACLE_BASE]
ORACLE_BASE="$OracleBase"
[ORACLE_INVENTORY]
INVENTORY_LOCATION="$OracleInventory"
INSTALL_GROUP=""
[Installation Details]
ORACLE_HOME="$OracleHome"
ORACLE_HOME_NAME="OraDB19Home1"
[Database Configuration]
GDBNAME="$GlobalDatabaseName"
SID="$Sid"
CREATE_AS_CONTAINER_DATABASE="false"
NUMBER_OF_PDBS="0"
CHARACTERSET="$CharacterSet"
NATIONALCHARACTERSET="$NationalCharacterSet"
DATABASETYPE="MULTIPURPOSE"
AUTOMATIC_MEMORY_MANAGEMENT="FALSE"
TOTALMEMORY="$MemoryPercentage"
ENABLE_ARCHIVING="$EnableArchiving"
RECOVERY_AREA_DESTINATION=""
RECOVERY_AREA_SIZE=""
SAMPLE_SCHEMA="$SampleSchema"
SYSPASSWORD="$SysPassword"
SYSTEMPASSWORD="$SystemPassword"
[Database Storage]
STORAGETYPE="FS"
[Options]
[Configuration Options]
[Cluster Configuration]
[EM Configuration]
[Security Updates]
DECLINE_SECURITY_UPDATES="true"
[Proxy]
[Runtime Prerequisite Checks]
[Installation Scripts]
"@
#endregion

# Function to check if running as administrator
function Test-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to create Oracle user account
function Create-OracleUser {
    param (
        [string]$Username,
        [string]$Password
    )

    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        Write-Host "Creating Oracle user account..."
        $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
        New-LocalUser -Name $Username -Password $securePassword -FullName "Oracle Service Account" -Description "Account for Oracle Database services"
        Add-LocalGroupMember -Group "Administrators" -Member $Username
        Write-Host "Oracle user account created successfully."
    } else {
        Write-Host "Oracle user account already exists."
    }
}

# Function to prepare directories
function Prepare-Directories {
    param (
        [string]$OracleBase,
        [string]$OracleHome,
        [string]$OracleInventory
    )

    Write-Host "Creating Oracle directories..."
    
    # Create directories if they don't exist
    $directories = @($OracleBase, $OracleHome, $OracleInventory)
    foreach ($dir in $directories) {
        if (-not (Test-Path -Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Host "Created directory: $dir"
        }
    }

    # Set permissions
    $acl = Get-Acl $OracleBase
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($OracleUser, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl -Path $OracleBase -AclObject $acl
    
    Write-Host "Directory preparation completed."
}

# Function to extract Oracle installation files
function Extract-OracleInstallation {
    param (
        [string]$SourcePath,
        [string]$ZipFile,
        [string]$Destination
    )

    Write-Host "Extracting Oracle installation files..."
    
    $zipPath = Join-Path -Path $SourcePath -ChildPath $ZipFile
    
    if (-not (Test-Path -Path $zipPath)) {
        throw "Oracle installation file not found at: $zipPath"
    }

    # Load the .NET compression assembly
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Extract the zip file
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $Destination)
    
    Write-Host "Extraction completed."
}

# Function to install Oracle Database
function Install-OracleDatabase {
    param (
        [string]$OracleHome,
        [string]$ResponseFile
    )

    Write-Host "Starting Oracle Database installation..."
    
    $setupExe = Join-Path -Path $OracleHome -ChildPath "setup.exe"
    
    if (-not (Test-Path -Path $setupExe)) {
        throw "Oracle setup.exe not found in: $OracleHome"
    }

    # Save response file
    $ResponseFileTemplate | Out-File -FilePath $ResponseFile -Encoding ASCII -Force

    # Run the installer
    $arguments = "-silent -waitforcompletion -responseFile `"$ResponseFile`""
    $process = Start-Process -FilePath $setupExe -ArgumentList $arguments -Wait -PassThru
    
    if ($process.ExitCode -ne 0) {
        throw "Oracle installation failed with exit code $($process.ExitCode)"
    }
    
    Write-Host "Oracle Database installation completed successfully."
}

# Main script execution
try {
    # Check if running as administrator
    if (-not (Test-Administrator)) {
        throw "This script must be run as Administrator. Please restart PowerShell as Administrator and try again."
    }

    # Create Oracle user account
    Create-OracleUser -Username $OracleUser -Password $OraclePassword

    # Prepare directories
    Prepare-Directories -OracleBase $OracleBase -OracleHome $OracleHome -OracleInventory $OracleInventory

    # Extract Oracle installation files
    Extract-OracleInstallation -SourcePath $OracleInstallSource -ZipFile $OracleInstallFile -Destination $OracleHome

    # Install Oracle Database
    $responseFilePath = Join-Path -Path $env:TEMP -ChildPath "oracle_install.rsp"
    Install-OracleDatabase -OracleHome $OracleHome -ResponseFile $responseFilePath

    # Set environment variables
    Write-Host "Setting environment variables..."
    [System.Environment]::SetEnvironmentVariable("ORACLE_HOME", $OracleHome, "Machine")
    [System.Environment]::SetEnvironmentVariable("ORACLE_BASE", $OracleBase, "Machine")
    [System.Environment]::SetEnvironmentVariable("ORACLE_SID", $Sid, "Machine")
    $env:Path += ";$OracleHome\bin"

    Write-Host "Oracle Database 19c installation and configuration completed successfully."
    Write-Host "Oracle Home: $OracleHome"
    Write-Host "SID: $Sid"
    Write-Host "Global Database Name: $GlobalDatabaseName"
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
