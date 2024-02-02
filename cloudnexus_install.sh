#!/bin/bash

# Set PATH
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Branch
BRANCH="main"

# Check if install script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
  then echo "ERROR: Please run the install script as root."
  exit
fi
echo "... done."

# Fetch Server Unique ID
SID=$1

# Make sure SID is not empty
echo "Checking Server ID (SID)..."
if [ -z "$SID" ]
	then echo "ERROR: First parameter missing."
	exit
fi
echo "... done."

# Fetch User Unique ID
User_ID=$2

# Make sure UID is not empty
echo "Checking User ID (UID)..."
if [ -z "$User_ID" ]
	then echo "ERROR: Second parameter missing."
	exit
fi
echo "... done."

# Check if user has selected to run agent as 'root' or as 'cloudnexus' user
if [ -z "$3" ]
	then echo "ERROR: third parameter missing."
	exit
fi

# Check if system has crontab and wget
echo "Checking for crontab and wget..."
command -v crontab >/dev/null 2>&1 || { echo "ERROR: Crontab is required to run this agent." >&2; exit 1; }
command -v wget >/dev/null 2>&1 || { echo "ERROR: wget is required to run this agent." >&2; exit 1; }
echo "... done."

# Remove old agent (if exists)
echo "Checking if there's any old cloudnexus agent already installed..."
if [ -d /etc/cloudnexus ]
then
	echo "Old cloudnexus agent found, deleting it..."
	rm -rf /etc/cloudnexus
else
	echo "No old cloudnexus agent found..."
fi
echo "... done."

# Creating agent folder
echo "Creating the cloudnexus agent folder..."
mkdir -p /etc/cloudnexus
echo "... done."

# Fetching the agent
echo "Fetching the agent..."
wget -t 1 -T 30 -qO /etc/cloudnexus/cloudnexus_agent.sh https://raw.githubusercontent.com/hammadkhaliq566/cloudnexus/$BRANCH/cloudnexus_agent.sh
echo "... done."

# Fetching the config file
echo "Fetching the config file..."
wget -t 1 -T 30 -qO /etc/cloudnexus/cloudnexus.cfg https://raw.githubusercontent.com/hammadkhaliq566/cloudnexus/$BRANCH/cloudnexus.cfg
echo "... done."

# Inserting Server ID (SID) into the agent config
echo "Inserting Server ID (SID) into agent config..."
sed -i "s/SID=\"\"/SID=\"$SID\"/" /etc/cloudnexus/cloudnexus.cfg
echo "... done."

# Inserting User ID (UID) into the agent config
echo "Inserting User ID (UID) into agent config..."
sed -i "s/User_ID=\"\"/User_ID=\"$User_ID\"/" /etc/cloudnexus/cloudnexus.cfg
echo "... done."

# Check if any services are to be monitored
echo "Checking if any services should be monitored..."
if [ "$4" != "0" ]
then
	echo "Services found, inserting them into the agent config..."
	sed -i "s/CheckServices=\"\"/CheckServices=\"$4\"/" /etc/cloudnexus/cloudnexus.cfg
fi
echo "... done."

# Check if 'View running processes' should be enabled
# echo "Checking if 'View running processes' should be enabled..."
# if [ "$5" == "1" ]
# then
# 	echo "Enabling 'View running processes' in the agent config..."
# 	sed -i "s/RunningProcesses=0/RunningProcesses=1/" /etc/cloudnexus/cloudnexus.cfg
# fi
# echo "... done."

# Check if any ports to monitor number of connections on
echo "Checking if any ports to monitor number of connections on..."
if [ "$5" != "0" ]
then
	echo "Ports found, inserting them into the agent config..."
	sed -i "s/ConnectionPorts=\"\"/ConnectionPorts=\"$5\"/" /etc/cloudnexus/cloudnexus.cfg
fi
echo "... done."

# Killing any running cloudnexus agents
echo "Making sure no cloudnexus agent scripts are currently running..."
ps aux | grep -ie cloudnexus_agent.sh | awk '{print $2}' | xargs kill -9
echo "... done."

# Checking if cloudnexus user exists
echo "Checking if cloudnexus user already exists..."
if id -u cloudnexus >/dev/null 2>&1
then
	echo "The cloudnexus user already exists, killing its processes..."
	pkill -9 -u `id -u cloudnexus`
	echo "Deleting cloudnexus user..."
	userdel cloudnexus
	echo "Creating the new cloudnexus user..."
	useradd cloudnexus -r -d /etc/cloudnexus -s /bin/false
	echo "Assigning permissions for the cloudnexus user..."
	chown -R cloudnexus:cloudnexus /etc/cloudnexus
	chmod -R 700 /etc/cloudnexus
else
	echo "The cloudnexus user doesn't exist, creating it now..."
	useradd cloudnexus -r -d /etc/cloudnexus -s /bin/false
	echo "Assigning permissions for the cloudnexus user..."
	chown -R cloudnexus:cloudnexus /etc/cloudnexus
	chmod -R 700 /etc/cloudnexus
fi
echo "... done."

# Removing old cronjob (if exists)
echo "Removing any old cloudnexus cronjob, if exists..."
crontab -u root -l | grep -v 'cloudnexus_agent.sh'  | crontab -u root - >/dev/null 2>&1
crontab -u cloudnexus -l | grep -v 'cloudnexus_agent.sh'  | crontab -u cloudnexus - >/dev/null 2>&1
echo "... done."

# Setup the new cronjob to run the agent either as 'root' or as 'cloudnexus' user, depending on client's installation choice.
# Default is running the agent as 'cloudnexus' user, unless chosen otherwise by the client when fetching the installation code from the cloudnexus website.
if [ "$2" == "root" ]; then
    echo "Setting up the new cronjob as 'root' user..."
    crontab -l -u root 2>/dev/null | { cat; echo "* * * * * /bin/bash /etc/cloudnexus/cloudnexus_agent.sh >> /etc/cloudnexus/cloudnexus_cron.log 2>&1"; } | crontab -u root - >/dev/null 2>&1
	sudo systemctl start crond	
	sudo systemctl enable crond
	sudo chmod +x /etc/cloudnexus/cloudnexus_agent.sh
else
    echo "Setting up the new cronjob as 'cloudnexus' user..."
    crontab -l -u cloudnexus 2>/dev/null | { cat; echo "* * * * * /bin/bash /etc/cloudnexus/cloudnexus_agent.sh >> /etc/cloudnexus/cloudnexus_cron.log 2>&1"; } | crontab -u cloudnexus - >/dev/null 2>&1
	sudo systemctl start crond	
	sudo systemctl enable crond
	sudo chmod +x /etc/cloudnexus/cloudnexus_agent.sh
fi
echo "... done."

# Start the agent
if [ "$2" == "root" ]
then
	echo "Starting the agent under the 'root' user..."
	bash /etc/cloudnexus/cloudnexus_agent.sh > /dev/null 2>&1 &
else
	echo "Starting the agent under the 'cloudnexus' user..."
	sudo -u cloudnexus bash /etc/cloudnexus/cloudnexus_agent.sh > /dev/null 2>&1 &
fi
echo "... done."

# Let cloudnexus platform know install has been completed
# Check if the agent installation was successful
echo "Letting cloudnexus platform know the installation has been completed..."
if [ $? -eq 0 ]; then
    status_code=200
    message="Agent installation completed successfully."
else
    status_code=404
    message="Agent installation failed."
fi

# Create JSON response
json_response='{"status":"'"$status_code"'","UID":"'"$User_ID"'"}'

# Print JSON response
echo "$json_response"

wget --retry-connrefused --waitretry=1 -t 3 -T 15 -qO- --header="Content-Type: text/plain" --post-data "$json_response" https://3d2a-72-255-40-12.ngrok-free.app/api/user/installServer/ &> /dev/null
echo "... done."

# Cleaning up install file
echo "Cleaning up the installation file..."
if [ -f $0 ]
then
    rm -f $0
fi
echo "... done."
