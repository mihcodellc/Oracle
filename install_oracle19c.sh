#!/bin/bash

:'
Download Oracle Database 19c for Linux x86-64 from Oracle's website (LINUX.X64_193000_db_home.zip)
Customize the parameters at the beginning of the script:
Set the Oracle user and password
Configure directory paths
Set database parameters (SID, PDB name, character set)
Set strong passwords for SYS and SYSTEM accounts
Update the path to your Oracle installation zip file
Save the script as install_oracle19c.sh
Make it executable:
    chmod +x install_oracle19c.sh  # Make it executable:
    sudo ./install_oracle19c.sh # Run the script as root:

Important Notes
This script is designed for Ubuntu 18.04, 20.04, or 22.04 (other versions may require adjustments)

The script:
Installs required dependencies
Creates the Oracle user and groups
Configures kernel parameters
Sets up swap space if needed
Installs Oracle software silently
Creates a container database with one PDB
Configures the listener
Sets up automatic startup
The installation process may take 30-60 minutes depending on your system
After installation, remember to:
Change the default passwords
Configure your network settings if needed
Set up backups
For production environments, you should:
Use more secure passwords
Adjust memory parameters based on your system
Consider additional security hardening




'

# Oracle Database 19c Installation Script for Ubuntu
# Must be run as root or with sudo privileges

# =============================================
# CONFIGURATION PARAMETERS - EDIT THESE VALUES
# =============================================

# Oracle installation user and group
ORACLE_USER="oracle"
ORACLE_GROUP="oinstall"
ORACLE_PASSWORD="OraclePassword123"  # Change this!
SUDO_PASSWORD="YourSudoPassword123"  # Change this!

# Oracle directory paths
ORACLE_BASE="/opt/oracle"
ORACLE_HOME="$ORACLE_BASE/product/19c/dbhome_1"
ORACLE_INVENTORY="/opt/oraInventory"

# Oracle software location (must be pre-downloaded)
ORACLE_INSTALL_FILE="LINUX.X64_193000_db_home.zip"
ORACLE_INSTALL_SOURCE="/path/to/installation/files"  # Change this to your download location

# Database configuration
ORACLE_SID="orcl"
ORACLE_PDB="pdb1"
ORACLE_CHARSET="AL32UTF8"
ORACLE_NCHARSET="UTF8"
ORACLE_MEMORY_PERCENT="40"  # Percentage of total memory for Oracle
SYS_PASSWORD="SysPassword123"  # Change this!
SYSTEM_PASSWORD="SystemPassword123"  # Change this!

# System configuration
SWAP_FILE_SIZE="8G"  # Recommended: equal to or larger than physical RAM
TMPFS_SIZE="2G"     # Size for /dev/shm

# =============================================
# INSTALLATION SCRIPT - DO NOT EDIT BELOW HERE
# =============================================

# Define colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to print error messages
error_exit() {
    echo -e "${RED}[ERROR] $1${NC}" 1>&2
    exit 1
}

# Function to print success messages
success_msg() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Function to print info messages
info_msg() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root or with sudo privileges."
fi

# Verify Ubuntu version
UBUNTU_VERSION=$(lsb_release -rs)
if [[ "$UBUNTU_VERSION" != "18.04" && "$UBUNTU_VERSION" != "20.04" && "$UBUNTU_VERSION" != "22.04" ]]; then
    error_exit "This script is designed for Ubuntu 18.04, 20.04, or 22.04. Detected version: $UBUNTU_VERSION"
fi

# =============================================
# PRE-INSTALLATION: SYSTEM SETUP
# =============================================

info_msg "Starting Oracle Database 19c installation on Ubuntu $UBUNTU_VERSION"

# Update system packages
info_msg "Updating system packages..."
apt-get update -y || error_exit "Failed to update package list"
apt-get upgrade -y || error_exit "Failed to upgrade packages"

# Install required packages
info_msg "Installing required packages..."
apt-get install -y \
    alien \
    binutils \
    build-essential \
    curl \
    elfutils \
    gcc \
    g++ \
    glibc-source \
    ksh \
    libaio1 \
    libaio-dev \
    libcap-dev \
    libcap1 \
    libelf-dev \
    libnsl-dev \
    libpam0g-dev \
    libstdc++6 \
    libxext6 \
    libxt6 \
    libxtst6 \
    make \
    openssh-server \
    rlwrap \
    sysstat \
    unixodbc \
    unixodbc-dev \
    unzip \
    xauth \
    zlib1g \
    zlib1g-dev || error_exit "Failed to install required packages"

# Create Oracle user and groups
info_msg "Creating Oracle user and groups..."
if ! grep -q "^${ORACLE_GROUP}:" /etc/group; then
    groupadd $ORACLE_GROUP || error_exit "Failed to create group $ORACLE_GROUP"
fi

if ! grep -q "^dba:" /etc/group; then
    groupadd dba || error_exit "Failed to create group dba"
fi

if ! grep -q "^oper:" /etc/group; then
    groupadd oper || error_exit "Failed to create group oper"
fi

if ! id -u $ORACLE_USER >/dev/null 2>&1; then
    useradd -m -s /bin/bash -g $ORACLE_GROUP -G dba,oper $ORACLE_USER || error_exit "Failed to create user $ORACLE_USER"
    echo "$ORACLE_USER:$ORACLE_PASSWORD" | chpasswd || error_exit "Failed to set password for $ORACLE_USER"
fi

# Configure system parameters
info_msg "Configuring system parameters..."

# Set kernel parameters
cat >> /etc/sysctl.conf <<EOF
# Oracle 19c recommended parameters
fs.aio-max-nr = 1048576
fs.file-max = 6815744
kernel.shmall = 2097152
kernel.shmmax = 4294967295
kernel.shmmni = 4096
kernel.sem = 250 32000 100 128
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
EOF

# Apply kernel parameters
sysctl -p || error_exit "Failed to apply kernel parameters"

# Set user limits
cat >> /etc/security/limits.conf <<EOF
# Oracle 19c recommended limits
$ORACLE_USER   soft   nofile    1024
$ORACLE_USER   hard   nofile    65536
$ORACLE_USER   soft   nproc    16384
$ORACLE_USER   hard   nproc    16384
$ORACLE_USER   soft   stack    10240
$ORACLE_USER   hard   stack    32768
$ORACLE_USER   hard   memlock    134217728
$ORACLE_USER   soft   memlock    134217728
EOF

# Create directories
info_msg "Creating Oracle directories..."
mkdir -p $ORACLE_BASE $ORACLE_HOME $ORACLE_INVENTORY || error_exit "Failed to create Oracle directories"
chown -R $ORACLE_USER:$ORACLE_GROUP $ORACLE_BASE $ORACLE_INVENTORY || error_exit "Failed to set permissions on Oracle directories"
chmod -R 775 $ORACLE_BASE $ORACLE_INVENTORY || error_exit "Failed to set permissions on Oracle directories"

# Configure tmpfs
info_msg "Configuring /dev/shm..."
mount -t tmpfs shmfs -o size=$TMPFS_SIZE /dev/shm || error_exit "Failed to configure /dev/shm"
echo "tmpfs /dev/shm tmpfs size=$TMPFS_SIZE 0 0" >> /etc/fstab || error_exit "Failed to update /etc/fstab"

# Configure swap space
info_msg "Configuring swap space..."
if [ $(free | awk '/Swap:/ {print $2}') -eq 0 ]; then
    fallocate -l $SWAP_FILE_SIZE /swapfile || error_exit "Failed to create swap file"
    chmod 600 /swapfile || error_exit "Failed to set swap file permissions"
    mkswap /swapfile || error_exit "Failed to format swap file"
    swapon /swapfile || error_exit "Failed to enable swap"
    echo "/swapfile none swap sw 0 0" >> /etc/fstab || error_exit "Failed to update /etc/fstab"
else
    info_msg "Swap space already exists, skipping creation."
fi

# Set environment variables for Oracle user
info_msg "Setting environment variables..."
cat >> /home/$ORACLE_USER/.bashrc <<EOF
# Oracle Environment Variables
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/lib:/usr/lib
export NLS_LANG=AMERICAN_AMERICA.$ORACLE_CHARSET
EOF

# =============================================
# ORACLE SOFTWARE INSTALLATION
# =============================================

# Install Oracle software
info_msg "Installing Oracle Database 19c software..."

# Check if installation file exists
if [ ! -f "$ORACLE_INSTALL_SOURCE/$ORACLE_INSTALL_FILE" ]; then
    error_exit "Oracle installation file not found at $ORACLE_INSTALL_SOURCE/$ORACLE_INSTALL_FILE"
fi

# Copy installation files to Oracle home
cp "$ORACLE_INSTALL_SOURCE/$ORACLE_INSTALL_FILE" $ORACLE_HOME/ || error_exit "Failed to copy Oracle installation file"

# Change ownership of files
chown -R $ORACLE_USER:$ORACLE_GROUP $ORACLE_HOME || error_exit "Failed to set permissions on Oracle home"

# Unzip Oracle installation files
info_msg "Unzipping Oracle installation files..."
cd $ORACLE_HOME || error_exit "Failed to change to Oracle home directory"
su - $ORACLE_USER -c "unzip -q $ORACLE_INSTALL_FILE" || error_exit "Failed to unzip Oracle installation files"
rm $ORACLE_INSTALL_FILE || error_exit "Failed to remove Oracle installation zip file"

# Create response file
info_msg "Creating response file for silent installation..."
cat > $ORACLE_HOME/install.rsp <<EOF
oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0
oracle.install.option=INSTALL_DB_SWONLY
ORACLE_HOSTNAME=localhost
UNIX_GROUP_NAME=$ORACLE_GROUP
INVENTORY_LOCATION=$ORACLE_INVENTORY
SELECTED_LANGUAGES=en
ORACLE_HOME=$ORACLE_HOME
ORACLE_BASE=$ORACLE_BASE
oracle.install.db.InstallEdition=EE
oracle.install.db.OSDBA_GROUP=dba
oracle.install.db.OSOPER_GROUP=oper
oracle.install.db.OSBACKUPDBA_GROUP=dba
oracle.install.db.OSDGDBA_GROUP=dba
oracle.install.db.OSKMDBA_GROUP=dba
oracle.install.db.OSRACDBA_GROUP=dba
oracle.install.db.rootconfig.executeRootScript=false
oracle.install.db.rootconfig.configMethod=ROOT
oracle.install.db.rootconfig.sudoPath=/usr/bin/sudo
oracle.install.db.rootconfig.sudoUserName=root
EOF

# Run Oracle installer
info_msg "Starting Oracle installer..."
cd $ORACLE_HOME || error_exit "Failed to change to Oracle home directory"
su - $ORACLE_USER -c "export DISPLAY=:0.0; $ORACLE_HOME/runInstaller -silent -ignorePrereqFailure -waitforcompletion -responseFile $ORACLE_HOME/install.rsp" || error_exit "Oracle software installation failed"

# Run root scripts
info_msg "Running root scripts..."
$ORACLE_HOME/root.sh || error_exit "Failed to run root.sh"

# =============================================
# DATABASE CREATION
# =============================================

info_msg "Creating Oracle database..."

# Create database creation response file
cat > $ORACLE_HOME/dbca.rsp <<EOF
responseFileVersion=/oracle/assistants/rspfmt_dbca_response_schema_v19.0.0
gdbName=${ORACLE_SID}.localdomain
sid=$ORACLE_SID
databaseConfigType=SI
policyManaged=false
createAsContainerDatabase=true
numberOfPDBs=1
pdbName=$ORACLE_PDB
useLocalUndoForPDBs=true
templateName=General_Purpose.dbc
sysPassword=$SYS_PASSWORD
systemPassword=$SYSTEM_PASSWORD
emConfiguration=NONE
emExpressPort=5500
runCVUChecks=FALSE
dbsnmpPassword=snmpPassword123
dvConfiguration=false
olsConfiguration=false
datafileJarLocation={ORACLE_HOME}/assistants/dbca/templates/
datafileDestination={ORACLE_BASE}/oradata/
recoveryAreaDestination={ORACLE_BASE}/fast_recovery_area/
storageType=FS
characterSet=$ORACLE_CHARSET
nationalCharacterSet=$ORACLE_NCHARSET
registerWithDirService=false
listeners=LISTENER
variables=ORACLE_BASE_HOME=$ORACLE_HOME,ORACLE_BASE=$ORACLE_BASE
initParams=sga_target=${ORACLE_MEMORY_PERCENT}%MEMORY_TARGET,pga_aggregate_target=${ORACLE_MEMORY_PERCENT}%MEMORY_TARGET,db_create_file_dest=$ORACLE_BASE/oradata/,db_recovery_file_dest=$ORACLE_BASE/fast_recovery_area/,audit_file_dest=$ORACLE_BASE/admin/$ORACLE_SID/adump/,audit_trail=db,dispatchers=(PROTOCOL=TCP) (SERVICE=${ORACLE_SID}XDB),remote_login_passwordfile=EXCLUSIVE
sampleSchema=true
memoryPercentage=$ORACLE_MEMORY_PERCENT
databaseType=MULTIPURPOSE
automaticMemoryManagement=false
totalMemory=0
EOF

# Create database using dbca
su - $ORACLE_USER -c "export ORACLE_HOME=$ORACLE_HOME; export PATH=\$ORACLE_HOME/bin:\$PATH; $ORACLE_HOME/bin/dbca -silent -createDatabase -responseFile $ORACLE_HOME/dbca.rsp" || error_exit "Database creation failed"

# =============================================
# POST-INSTALLATION CONFIGURATION
# =============================================

info_msg "Performing post-installation configuration..."

# Set Oracle environment variables system-wide
cat > /etc/profile.d/oracle.sh <<EOF
# Oracle Environment Variables
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:/lib:/usr/lib
export NLS_LANG=AMERICAN_AMERICA.$ORACLE_CHARSET
EOF

# Configure listener
su - $ORACLE_USER -c "export ORACLE_HOME=$ORACLE_HOME; export PATH=\$ORACLE_HOME/bin:\$PATH; lsnrctl start" || error_exit "Failed to start listener"

# Enable Oracle services to start automatically
cat > /etc/systemd/system/oracle-rdbms.service <<EOF
[Unit]
Description=Oracle Database Service
After=network.target

[Service]
Type=forking
User=$ORACLE_USER
Group=$ORACLE_GROUP
Environment="ORACLE_HOME=$ORACLE_HOME"
Environment="ORACLE_SID=$ORACLE_SID"
ExecStart=$ORACLE_HOME/bin/dbstart $ORACLE_HOME
ExecStop=$ORACLE_HOME/bin/dbshut $ORACLE_HOME
TimeoutSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable oracle-rdbms.service

success_msg "Oracle Database 19c installation completed successfully!"
echo ""
echo "Database Information:"
echo "  SID: $ORACLE_SID"
echo "  PDB: $ORACLE_PDB"
echo "  Oracle Home: $ORACLE_HOME"
echo "  Connection String: localhost:1521/$ORACLE_SID"
echo ""
echo "You can connect to the database using:"
echo "  sqlplus sys/$SYS_PASSWORD@$ORACLE_SID as sysdba"
echo "  sqlplus system/$SYSTEM_PASSWORD@$ORACLE_SID"
echo ""
echo "Remember to change the default passwords!"
