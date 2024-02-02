#!/bin/bash

# Set PATH/Locale
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ScriptPath=$(dirname "${BASH_SOURCE[0]}")

# Load configuration file
if [ -f "$ScriptPath"/cloudnexus.cfg ]
then
	. "$ScriptPath"/cloudnexus.cfg
else
	exit 1
fi

# Service status function
function servicestatus() {
	# Check first via ps
	if (( $(ps -ef | grep -E "[\/ ]$1([^\/]|$)" | grep -v "grep" | wc -l) > 0 ))
	then # Up
		echo "$1,1"
	else # Down, try with systemctl (if available)
		if command -v "systemctl" > /dev/null 2>&1
		then # Use systemctl
			if systemctl is-active --quiet "$1"
			then # Up
				echo "$1,1"
			else # Down
				echo "$1,0"
			fi
		else # No systemctl
			echo "$1,0"
		fi
	fi
}

# Function used to prepare base64 str for url encoding
function base64prep() {
	str=$1
	str="${str//+/%2B}"
	str="${str//\//%2F}"
	echo "$str"
}

# Kill any lingering agent processes
HTProcesses=$(pgrep -f cloudnexus_agent.sh | wc -l)
if [ -z "$HTProcesses" ]
then
	HTProcesses=0
fi
if [ "$HTProcesses" -gt 15 ]
then
	pgrep -f cloudnexus_agent.sh | xargs kill -9
fi
for PID in $(pgrep -f cloudnexus_agent.sh)
do
	PID_TIME=$(ps -p "$PID" -oetime= | tr '-' ':' | awk -F: '{total=0; m=1;} {for (i=0; i < NF; i++) {total += $(NF-i)*m; m *= i >= 2 ? 24 : 60 }} {print total}')
	if [ -n "$PID_TIME" ] && [ "$PID_TIME" -ge 120 ]
	then
		kill -9 "$PID"
	fi
done

# Start timers
START=$(date +%s)
tTIMEDIFF=0
M=$(date +%M | sed 's/^0*//')
if [ -z "$M" ]
then
	M=0
	# Clear the cloudnexus_cron.log every hour
	rm -f "$ScriptPath"/cloudnexus_cron.log
fi

# Network interfaces
if [ -n "$NetworkInterfaces" ]
then
	# Use the network interfaces specified in Settings
	IFS=',' read -r -a NetworkInterfacesArray <<< "$NetworkInterfaces"
else
	# Automatically detect the network interfaces
	NetworkInterfacesArray=()
	while IFS='' read -r line; do NetworkInterfacesArray+=("$line"); done < <(ip a | grep BROADCAST | grep 'state UP' | awk '{print $2}' | awk -F ":" '{print $1}' | awk -F "@" '{print $1}')
fi

# Initial network usage
T=$(cat /proc/net/dev)
declare -A aRX
declare -A aTX
declare -A tRX
declare -A tTX

# Loop through network interfaces
for NIC in "${NetworkInterfacesArray[@]}"
do
	aRX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $2}')
	aTX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $10}')
done

# Port connections
if [ -n "$ConnectionPorts" ]
then
	IFS=',' read -r -a ConnectionPortsArray <<< "$ConnectionPorts"
	declare -A Connections
	netstat=$(ss -ntu | awk '{print $5}')
	for cPort in "${ConnectionPortsArray[@]}"
	do
		Connections[$cPort]=$(echo "$netstat" | grep -c ":$cPort$")
	done
fi

# Temperature
declare -A TempArray
declare -A TempArrayCnt

# Disks IOPS
declare -A vDISKs
for i in $(timeout 3 df | awk '$1 ~ /\// {print}' | awk '{print $(NF)}')
do
	vDISKs[$i]=$(lsblk -l | grep -w "$i" | awk '{print $1}')
done
declare -A IOPSRead
declare -A IOPSWrite
diskstats=$(cat /proc/diskstats)
for i in "${!vDISKs[@]}"
do
	IOPSRead[$i]=$(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $6}')
	IOPSWrite[$i]=$(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $10}')
done

# Collect data loop
for X in $(seq 20)
do
	# Get vmstat
	VMSTAT=$(vmstat 3 2 | tail -1)
	
	# CPU usage
	CPU=$(echo "$VMSTAT" | awk '{print 100 - $15}')
	tCPU=$(echo | awk "{print $tCPU + $CPU}")
	
	# CPU IO wait
	CPUwa=$(echo "$VMSTAT" | awk '{print $16}')
	tCPUwa=$(echo | awk "{print $tCPUwa + $CPUwa}")
	
	# CPU steal time
	CPUst=$(echo "$VMSTAT" | awk '{print $17}')
	tCPUst=$(echo | awk "{print $tCPUst + $CPUst}")

	# CPU user time
	CPUus=$(echo "$VMSTAT" | awk '{print $13}')
	tCPUus=$(echo | awk "{print $tCPUus + $CPUus}")
	
	# CPU system time
	CPUsy=$(echo "$VMSTAT" | awk '{print $14}')
	tCPUsy=$(echo | awk "{print $tCPUsy + $CPUsy}")
	
	# CPU clock
	CPUSpeed=$(grep 'cpu MHz' /proc/cpuinfo | awk -F": " '{print $2}' | awk '{printf "%18.0f",$1}' | sed -e 's/ /+/g')
	if [ -z "$CPUSpeed" ]
	then
		CPUSpeed=0
	fi
	tCPUSpeed=$(echo | awk "{print $tCPUSpeed + $CPUSpeed}")

	# CPU Load
	loadavg=$(cat /proc/loadavg)
	loadavg1=$(echo "$loadavg" | awk '{print $1}')
	tloadavg1=$(echo | awk "{print $tloadavg1 + $loadavg1}")
	loadavg5=$(echo "$loadavg" | awk '{print $2}')
	tloadavg5=$(echo | awk "{print $tloadavg5 + $loadavg5}")
	loadavg15=$(echo "$loadavg" | awk '{print $3}')
	tloadavg15=$(echo | awk "{print $tloadavg15 + $loadavg15}")

	# Get RAM info
	zRAM=$(cat /proc/meminfo)
	
	# RAM usage
	aRAM=$(echo "$VMSTAT" | awk '{print $4 + $5 + $6}')
	bRAM=$(echo "$zRAM" | grep "^MemTotal:" /proc/meminfo | awk '{print $2}')
	RAM=$(echo | awk "{print $aRAM * 100 / $bRAM}")
	RAM=$(echo | awk "{print 100 - $RAM}")
	tRAM=$(echo | awk "{print $tRAM + $RAM}")

	# RAM swap usage
	aRAMSwap=$(echo "$VMSTAT" | awk '{print $3}')
	cRAM=$(echo "$zRAM" | grep "^SwapTotal:" /proc/meminfo | awk '{print $2}')
	if [ "$cRAM" -gt 0 ]
	then
		RAMSwap=$(echo | awk "{print $aRAMSwap * 100 / $cRAM}")
	else
		RAMSwap=0
	fi
	tRAMSwap=$(echo | awk "{print $tRAMSwap + $RAMSwap}")
	
	# RAM buffers usage
	aRAMBuff=$(echo "$VMSTAT" | awk '{print $5}')
	RAMBuff=$(echo | awk "{print $aRAMBuff * 100 / $bRAM}")
	tRAMBuff=$(echo | awk "{print $tRAMBuff + $RAMBuff}")
	
	# RAM cache usage
	aRAMCache=$(echo "$VMSTAT" | awk '{print $6}')
	RAMCache=$(echo | awk "{print $aRAMCache * 100 / $bRAM}")
	tRAMCache=$(echo | awk "{print $tRAMCache + $RAMCache}")
	
	# Network usage
	T=$(cat /proc/net/dev)
	END=$(date +%s)
	TIMEDIFF=$(echo | awk "{print $END - $START}")
	tTIMEDIFF=$(echo | awk "{print $tTIMEDIFF + $TIMEDIFF}")
	START=$(date +%s)
	
	# Loop through network interfaces
	for NIC in "${NetworkInterfacesArray[@]}"
	do
		# Received Traffic
		RX=$(echo | awk "{print $(echo "$T" | grep -w "$NIC:" | awk '{print $2}') - ${aRX[$NIC]}}")
		RX=$(echo | awk "{print $RX / $TIMEDIFF}")
		RX=$(echo "$RX" | awk '{printf "%18.0f",$1}')
		aRX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $2}')
		tRX[$NIC]=$(echo | awk "{print ${tRX[$NIC]} + $RX}")
		tRX[$NIC]=$(echo "${tRX[$NIC]}" | awk '{printf "%18.0f",$1}')
		# Transferred Traffic
		TX=$(echo | awk "{print $(echo "$T" | grep -w "$NIC:" | awk '{print $10}') - ${aTX[$NIC]}}")
		TX=$(echo | awk "{print $TX / $TIMEDIFF}")
		TX=$(echo "$TX" | awk '{printf "%18.0f",$1}' | xargs)
		aTX[$NIC]=$(echo "$T" | grep -w "$NIC:" | awk '{print $10}')
		tTX[$NIC]=$(echo | awk "{print ${tTX[$NIC]} + $TX}")
		tTX[$NIC]=$(echo "${tTX[$NIC]}" | awk '{printf "%18.0f",$1}' | xargs)
	done
	
	# Port connections
	if [ -n "$ConnectionPorts" ]
	then
		netstat=$(ss -ntu | awk '{print $5}')
		for cPort in "${ConnectionPortsArray[@]}"
		do
			Connections[$cPort]=$(echo | awk "{print ${Connections[$cPort]} + $(echo "$netstat" | grep -c ":$cPort$")}")
		done
	fi

	# Temperature
	if [ "$(find /sys/class/thermal/thermal_zone*/type 2> /dev/null | wc -l)" -gt 0 ]
	then
		TempArrayIndex=()
		TempArrayVal=()
		while IFS='' read -r line; do TempArrayIndex+=("$line"); done < <(cat /sys/class/thermal/thermal_zone*/type)
		while IFS='' read -r line; do TempArrayVal+=("$line"); done < <(cat /sys/class/thermal/thermal_zone*/temp)
		TempNameCnt=0
		for TempName in "${TempArrayIndex[@]}"
		do
				TempArray[$TempName]=$((${TempArray[$TempName]} + ${TempArrayVal[$TempNameCnt]}))
				TempArrayCnt[$TempName]=$((TempArrayCnt[$TempName] + 1))
				TempNameCnt=$((TempNameCnt + 1))
		done
	else
		if command -v "sensors" > /dev/null 2>&1
		then
			SensorsArray=()
			while IFS='' read -r line; do SensorsArray+=("$line"); done < <(sensors -A)
			for i in "${SensorsArray[@]}"
			do
				if [ -n "$i" ]
				then
					if [[ "$i" != *":"* ]] && [[ "$i" != *"="* ]]
					then
						SensorsCat="$i"
					else
						if [[ "$i" == *":"* ]] && [[ "$i" == *"°C"* ]]
						then
							TempName="$SensorsCat|"$(echo "$i" | awk -F"°C" '{print $1}' | awk -F":" '{print $1}' | sed 's/ /_/g' | xargs)
							TempVal=$(echo "$i" | awk -F"°C" '{print $1}' | awk -F":" '{print $2}' | sed 's/ //g' | awk '{printf "%18.3f",$1}' | sed -e 's/\.//g' | xargs)
							TempArray[$TempName]=$((${TempArray[$TempName]} + $TempVal))
							TempArrayCnt[$TempName]=$((TempArrayCnt[$TempName] + 1))
						fi
					fi
				fi
			done
		else
			if command -v "ipmitool" > /dev/null 2>&1
			then
				IPMIArray=()
				while IFS='' read -r line; do IPMIArray+=("$line"); done < <(timeout -s 9 3 ipmitool sdr type Temperature)
				for i in "${IPMIArray[@]}"
				do
					if [ -n "$i" ]
					then
						if [[ "$i" == *"degrees"* ]]
						then
							TempName=$(echo "$i" | awk -F"|" '{print $1}' | xargs | sed 's/ /_/g')
							TempVal=$(echo "$i" | awk -F"|" '{print $NF}' | awk -F"degrees" '{print $1}' | sed 's/ //g' | awk '{printf "%18.3f",$1}' | sed -e 's/\.//g' | xargs)
							TempArray[$TempName]=$((${TempArray[$TempName]} + $TempVal))
							TempArrayCnt[$TempName]=$((TempArrayCnt[$TempName] + 1))
						fi
					fi
				done
			fi
		fi
	fi
	
	# Check if minute changed, so we can end the loop
	MM=$(date +%M | sed 's/^0*//')
	if [ -z "$MM" ]
	then
		MM=0
	fi
	if [ "$MM" -gt "$M" ] 
	then
		break
	fi
done

# Get user running the agent
User=$(whoami)

# Check if system requires reboot
RequiresReboot=0
if [ -f  /var/run/reboot-required ]
then
	RequiresReboot=1
fi

# Operating System
# Check via lsb_release if possible
if command -v "lsb_release" > /dev/null 2>&1
then
	OS=$(lsb_release -s -d)
# Check if it's Debian
elif [ -f /etc/debian_version ]
then
	OS="Debian $(cat /etc/debian_version)"
# Check if it's CentOS/Fedora
elif [ -f /etc/redhat-release ]
then
	OS=$(cat /etc/redhat-release)

 	# Check if system is CloudLinux release 8 (CL8 will only output "This system is receiving updates from CloudLinux Network server.")
  	if [[ "$OS" != "CloudLinux release 8."* ]]
	then
		# Check if system requires reboot (Only supported in CentOS/RHEL 7 and later, with yum-utils installed)
		if timeout -s 9 5 needs-restarting -r | grep -q 'Reboot is required'
		then
			RequiresReboot=1
		fi
  	fi
# If all else fails
else
	OS="$(uname -s)"
fi
OS=$(echo -ne "$OS" | sed 's/ //g')

# Kernel
Kernel=$(uname -r  | sed 's/ //g')

# Hostname
Hostname=$(uname -n  | sed 's/ //g')

# Location
Location=$(curl ipinfo.io | grep country | awk -F'"' '{print $4}')

# Vendor
sysVendor=$(cat /sys/class/dmi/id/sys_vendor)

# Server uptime
Uptime=$(awk '{print $1}' < /proc/uptime | awk '{printf "%18.0f",$1}')

# lscpu
lscpu=$(lscpu)

# CPU model
CPUModel=$(grep -m1 'model name' /proc/cpuinfo | awk -F": " '{print $NF}')
if [ -z "$CPUModel" ]
then
	CPUModel=$(echo "$lscpu" | grep "^Model name:" | awk -F": " '{print $NF}')
fi
CPUModel=$(echo -ne "$CPUModel" | sed 's/ //g')

# CPU sockets
CPUSockets=$(grep -i "physical id" /proc/cpuinfo | sort -u | wc -l)

# CPU cores
CPUCores=$(echo "$lscpu" | grep "^CPU(s):" | awk '{print $(NF)}')

# CPU threads
CPUThreads=$(echo "$lscpu" | grep "^Thread(s) per core:" | awk '{print $(NF)}')

# CPU clock speed
if [ -z "$tCPUSpeed" ] || [ "$tCPUSpeed" -eq 0 ]
then
	CPUSpeed=$(echo "$lscpu" | grep "^CPU max MHz" | awk '{print $NF}' | awk '{printf "%18.0f",$1}')
else
	CPUSpeed=$(echo | awk "{print $tCPUSpeed / $CPUCores / $X}" | awk '{printf "%18.0f",$1}' )
fi

# Average CPU usage
CPU=$(echo | awk "{print $tCPU / $X}")

# Average CPU IO wait
CPUwa=$(echo | awk "{print $tCPUwa / $X}")

# Average CPU steal time
CPUst=$(echo | awk "{print $tCPUst / $X}")

# Average CPU user time
CPUus=$(echo | awk "{print $tCPUus / $X}")

# Average CPU system time
CPUsy=$(echo | awk "{print $tCPUsy / $X}")

# Total Storage Usage in Percentage
total_storage=$(df -TP | awk 'NR>1 {print $3,$5}' | awk '{total+=$1; used+=$2} END {printf "%.2f\n", used/total*100}')

# CPU Load
loadavg1=$(echo | awk "{print $tloadavg1 / $X}")
loadavg5=$(echo | awk "{print $tloadavg5 / $X}")
loadavg15=$(echo | awk "{print $tloadavg15 / $X}")

# RAM size
RAMSize=$(free -h | awk '/^Mem:/ {print $2}')

# RAM Usage
RAM=$(echo | awk "{print $tRAM / $X}")

# RAM swap size
RAMSwapSize=$(grep "^SwapTotal:" /proc/meminfo | awk '{print $2}')

# Total Users
total_users=$(cut -d: -f1 /etc/passwd | wc -l)

# RAM swap usage
if [ "$RAMSwapSize" -gt 0 ]
then
	RAMSwap=$(echo | awk "{print $tRAMSwap / $X}")
else
	RAMSwap=0
fi

# RAM buffers usage
RAMBuff=$(echo | awk "{print $tRAMBuff / $X}")

# RAM cache usage
RAMCache=$(echo | awk "{print $tRAMCache / $X}")

# Disks usage
DISKs=$(echo -ne "$(timeout 3 df -Th | sed 1d | awk '{print $(NF)","$1","$2","$3","$4","$5","$6";"}')" | sed 's/ //g'  | sed 's/ //g')

# Disks inodes Usage
INODEs=$(echo -ne "$(timeout 3 df -Ti | sed 1d | awk '{print $(NF)","$1","$2","$3","$4","$5","$6","$7";"}')" | sed 's/ //g' | sed 's/ //g')

# Disks IOPS
IOPS=""
diskstats=$(cat /proc/diskstats)
for i in "${!vDISKs[@]}"
do
	IOPSRead[$i]=$(echo | awk "{print $(echo | awk "{print $(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $6}') - ${IOPSRead[$i]}}" 2> /dev/null) * 512 / $tTIMEDIFF}" 2> /dev/null)
	IOPSRead[$i]=$(echo "${IOPSRead[$i]}" | awk '{printf "%18.0f",$1}')
	IOPSWrite[$i]=$(echo | awk "{print $(echo | awk "{print $(echo "$diskstats" | grep -w "${vDISKs[$i]}" | awk '{print $10}') - ${IOPSWrite[$i]}}" 2> /dev/null) * 512 / $tTIMEDIFF}" 2> /dev/null)
	IOPSWrite[$i]=$(echo "${IOPSWrite[$i]}" | awk '{printf "%18.0f",$1}')
	IOPS="$IOPS$i,${IOPSRead[$i]},${IOPSWrite[$i]};"
done
IOPS=$(echo -ne "$IOPS" | sed 's/ //g')

# Total network usage and IP addresses
RX=0
TX=0
NICS=""
IPv4=""
IPv6=""
MAC=""
for NIC in "${NetworkInterfacesArray[@]}"
do
    # Individual NIC network usage
    RX=$(echo | awk "{print ${tRX[$NIC]} / $X}")
    RX=$(echo "$RX" | awk '{printf "%18.0f",$1}' | xargs)
    TX=$(echo | awk "{print ${tTX[$NIC]} / $X}")
    TX=$(echo "$TX" | awk '{printf "%18.0f",$1}' | xargs)
    NICS="$NICS$NIC,$RX,$TX;"

    # Individual NIC IP addresses
    IPv4="$IPv4$NIC,$(ip -4 addr show "$NIC" | grep -oP 'inet \K[\d.]+' | sed 's/ /,/g');"
    IPv6="$IPv6$NIC,$(ip -6 addr show "$NIC" | grep -w "global" | grep -oP 'inet6 \K[0-9a-fA-F:]+' | sed 's/ /,/g');"

    # Individual NIC MAC address
    MAC="$MAC$NIC,$(ip link show "$NIC" | awk '/ether/ {print $2}');"
done
NICS=$(echo -ne "$NICS" | sed 's/ //g')
IPv4=$(echo -ne "$IPv4" | sed 's/ //g')
IPv6=$(echo -ne "$IPv6" | sed 's/ //g')
MAC=$(echo -ne "$MAC" | sed 's/ //g')

# Port connections
CONN=""
if [ -n "$ConnectionPorts" ]
then
	for cPort in "${ConnectionPortsArray[@]}"
	do
		CON=$(echo | awk "{print ${Connections[$cPort]} / $X}")
		CON=$(echo "$CON" | awk '{printf "%18.0f",$1}')
		CONN="$CONN$cPort,$CON;"
	done
fi
CONN=$(echo -ne "$CONN" | sed 's/ //g')

# Temperature
TEMP=""
if [ -n "$TempName" ]
then
	for TempName in "${!TempArray[@]}"
	do
		TMP=$(echo | awk "{print ${TempArray[$TempName]} / ${TempArrayCnt[$TempName]}}")
		TMP=$(echo "$TMP" | awk '{printf "%18.0f",$1}')
		TEMP="$TEMP$TempName,$TMP;"
	done
fi
TEMP=$(echo -ne "$TEMP" | sed 's/ //g')

# Check Services (if any are set to be checked)
SRVCS=""
if [ -n "$CheckServices" ]
then
	IFS=',' read -r -a CheckServicesArray <<< "$CheckServices"
	for i in "${CheckServicesArray[@]}"
	do
		SRVCS="$SRVCS$(servicestatus "$i");"
	done
fi
SRVCS=$(echo -ne "$SRVCS" | sed 's/ //g')

# Custom Variables
CV=""
if [ -n "$CustomVars" ]
then
	if [ -s "$ScriptPath"/"$CustomVars" ]
	then
		CV=$(< "$ScriptPath"/"$CustomVars" | sed 's/ //g')
	fi
fi

# Current time/date
currentDateTime=$(date "+%Y-%m-%d_%H:%M:%S")

# Extract date and time into separate variables
Date=$(echo $currentDateTime | awk -F_ '{print $1}')
Time=$(echo $currentDateTime | awk -F_ '{print $2}')

# Prepare data
json='{"SID":"'"$SID"'","UID":"'"$User_ID"'","agent":"0","user":"'"$User"'","os":"'"$OS"'","kernel":"'"$Kernel"'","hostname":"'"$Hostname"'","date":"'"$Date"'","time":"'"$Time"'","location":"'"$Location"'","Vendor":"'"$sysVendor"'","totalusers":"'"$total_users"'","totalstorage":"'"$total_storage"'","reqreboot":"'"$RequiresReboot"'","uptime":"'"$Uptime"'","cpumodel":"'"$CPUModel"'","cpusockets":"'"$CPUSockets"'","cpucores":"'"$CPUCores"'","cputhreads":"'"$CPUThreads"'","cpuspeed":"'"$CPUSpeed"'","cpu":"'"$CPU"'","wa":"'"$CPUwa"'","st":"'"$CPUst"'","us":"'"$CPUus"'","sy":"'"$CPUsy"'","load1":"'"$loadavg1"'","load5":"'"$loadavg5"'","load15":"'"$loadavg15"'","ramsize":"'"$RAMSize"'","ram":"'"$RAM"'","ramswapsize":"'"$RAMSwapSize"'","ramswap":"'"$RAMSwap"'","rambuff":"'"$RAMBuff"'","ramcache":"'"$RAMCache"'","disks":"'"$DISKs"'","inodes":"'"$INODEs"'","iops":"'"$IOPS"'","nics":"'"$NICS"'","ipv4":"'"$IPv4"'","ipv6":"'"$IPv6"'","macaddress":"'"$MAC"'","conn":"'"$CONN"'","temp":"'"$TEMP"'","serv":"'"$SRVCS"'","cust":"'"$CV"'"}'

Filename="cloudnexus_agent_$Date_$Time.log"																																																						

# Save data to file
echo "$json" > "$ScriptPath"/"$Filename"

# Post data
wget --retry-connrefused --waitretry=1 -t 3 -T 15 -qO- --header="Content-Type: text/plain" --post-data="$json"  https://3d2a-72-255-40-12.ngrok-free.app/api/user/addServer/ &> /dev/null

if [ $? -eq 0 ]; then
    echo "Data posted successfully!"
else
    echo "Error posting data. Exit status: $?"
fi