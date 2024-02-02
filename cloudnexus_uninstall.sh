#!/bin/bash

# Set PATH
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Check if install script is run by root
echo "Checking root privileges..."
if [ "$EUID" -ne 0 ]
  then echo "Please run the install script as root."
  exit
fi
echo "... done."

# Fetch Server Unique ID
SID=$1

# Fetch User Unique ID
User_Id=$2

# Remove old agent (if exists)
echo "Checking if cloudnexus agent folder exists..."
if [ -d /etc/cloudnexus ]
then
	echo "Old cloudnexus agent found, deleting it..."
	rm -rf /etc/cloudnexus
else
	echo "No old cloudnexus agent folder found..."
fi
echo "... done."

# Killing any running cloudnexus agents
echo "Killing any cloudnexus agent scripts that may be currently running..."
ps aux | grep -ie cloudnexus_agent.sh | awk '{print $2}' | xargs kill -9
echo "... done."

# Checking if cloudnexus user exists
echo "Checking if hetrixtool user exists..."
if id -u cloudnexus >/dev/null 2>&1
then
	echo "The cloudnexus user exists, killing its processes..."
	pkill -9 -u `id -u cloudnexus`
	echo "Deleting cloudnexus user..."
	userdel cloudnexus
else
	echo "The cloudnexus user doesn't exist..."
fi
echo "... done."

# Removing cronjob (if exists)
echo "Removing any cloudnexus cronjob, if exists..."
crontab -u root -l | grep -v 'cloudnexus_agent.sh'  | crontab -u root - >/dev/null 2>&1
crontab -u cloudnexus -l | grep -v 'cloudnexus_agent.sh'  | crontab -u cloudnexus - >/dev/null 2>&1
echo "... done."

# Cleaning up uninstall file
echo "Cleaning up the installation file..."
if [ -f $0 ]
then
    rm -f $0
fi
echo "... done."


echo "Letting cloudnexus platform know the Uninstallation has been completed..."
if [ $? -eq 0 ]; then
    status_code=200
    message="Agent Uninstallation completed successfully."
else
    status_code=404
    message="Agent Uninstallation failed."
fi

json_response='{"status":"'"$status_code"'","SID":"'"$SID"'","UID":"'"$User_Id"'"}'

# Let cloudnexus platform know uninstall has been completed
# echo "Letting cloudnexus platform know the uninstallation has been completed..."

wget --retry-connrefused --waitretry=1 -t 3 -T 15 -qO- --header="Content-Type: text/plain" --post-data="$json_response" https://3d2a-72-255-40-12.ngrok-free.app/api/user/uninstallServer/ &> /dev/null
# echo "... done."

# All done
echo "cloudnexus agent uninstallation completed."
