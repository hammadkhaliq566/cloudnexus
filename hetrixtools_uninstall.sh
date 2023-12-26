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

# Let cloudnexus platform know uninstall has been completed
# echo "Letting cloudnexus platform know the uninstallation has been completed..."
# POST="v=uninstall&s=$SID"
# wget -t 1 -T 30 -qO- --post-data "$POST" https://sm.cloudnexus.net/ &> /dev/null
# echo "... done."

# All done
echo "cloudnexus agent uninstallation completed."
