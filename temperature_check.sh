#!/bin/sh

##
# External programs

SENDMAIL=/usr/local/bin/msmtp
SENDMAIL_PARAMS="-t"
MBMON=/usr/bin/mbmon
MBMON_PARAMS="-c 1 -T 1"
SYSCTL=/sbin/sysctl
SMARTCTL=/usr/local/sbin/smartctl
AWK=/usr/bin/awk
GREP=/usr/bin/grep
EXPR=/bin/expr


##
# Settings

DEST_EMAIL="email@provider.com"

CPU_TEMP_THRESHOLD_WARN=60
CPU_TEMP_THRESHOLD_CRIT=70

HDD_TEMP_THRESHOLD_WARN=45
HDD_TEMP_THRESHOLD_CRIT=55

MB_TEMP_THRESHOLD_WARN=40
MB_TEMP_THRESHOLD_CRIT=50

DISKS_NEEDED=6


##
# Variables

WARN_ACTION=0
CRIT_ACTION=0
LINE_SEPARATOR="\n"
ERR_ACTION=0
ERR_MESSAGE=""
MB_TEMP=0


##
# CPU

CPU_TEMPS=`$SYSCTL dev.cpu | $GREP emperature | $AWK '{print substr($2, 1, length($2) - 3)}'`

if [ -z "$CPU_TEMPS" ]
then
	ERR_ACTION=1
        ERR_MESSAGE=$ERR_MESSAGE$LINE_SEPARATOR"Error reading CPU temperature(s)"
else
	for CPU_TEMP in $CPU_TEMPS
	do
		if [ "$CPU_TEMP" -ge "$CPU_TEMP_THRESHOLD_WARN" ]
		then
			WARN_ACTION=1
		fi
		if [ "$CPU_TEMP" -ge "$CPU_TEMP_THRESHOLD_CRIT" ]
		then
			CRIT_ACTION=1
		fi
	done
fi


##
# Motherboard

if [ -x "$MBMON" ]
then
	MB_TEMP=`${MBMON} ${MBMON_PARAMS}`

	MB_TEMP=${MB_TEMP%.0}

	if [ -n "$MB_TEMP" ]
	then
		if [ "$MB_TEMP" -ge "$MB_TEMP_THRESHOLD_WARN" ]
		then
			WARN_ACTION=1
		fi
		if [ "$MB_TEMP" -ge "$MB_TEMP_THRESHOLD_CRIT" ]
		then
			CRIT_ACTION=1
		fi
	fi
fi


##
# Disks

DISKS=`$SYSCTL -an kern.disks`
HDD_TEMP_MESSAGE=""
OLD_IFS=$IFS
DISKS_FOUND=0

if [ -z "$DISKS" ]
then
	ERR_ACTION=2
	ERR_MESSAGE=$ERR_MESSAGE$LINE_SEPARATOR"Error finding disk names"
else
	for INDEX in ${DISKS}
	do
		#skip usb devices
		TWOCHARS=`echo ${INDEX} | $AWK '{print substr($0, 1, 2)}'`
		if [ "$TWOCHARS" = "da" ]
		then
			#echo "skipping usb disk "$INDEX
			continue
		fi
		#echo ${INDEX}
		HDD_TEMP_MESSAGE=$HDD_TEMP_MESSAGE$LINE_SEPARATOR$LINE_SEPARATOR"Disk: "$INDEX$LINE_SEPARATOR
	
		TEMP=`$SMARTCTL -A /dev/${INDEX} | $GREP emp | $AWK '{print $2,$10}'`

		if [ -z "$TEMP" ]
		then
			ERR_MESSAGE=$ERR_MESSAGE$LINE_SEPARATOR"Error finding temperature for disk "${INDEX}
			continue
		fi

		DISKS_FOUND=`$EXPR $DISKS_FOUND + 1`
	
		IFS=$'
'

		for LINE in $TEMP
		do
			COUNT=0
			IFS=$OLD_IFS
			for ITEM in $LINE
			do
				if [ "$COUNT" -ge 1 ]
				then
					HDD_TEMP_MESSAGE=$HDD_TEMP_MESSAGE$ITEM
					if [ "$ITEM" -ge "$HDD_TEMP_THRESHOLD_WARN" ]
					then
						WARN_ACTION=2
						HDD_TEMP_MESSAGE=$HDD_TEMP_MESSAGE" !!!"				
					fi
					if [ "$ITEM" -ge "$HDD_TEMP_THRESHOLD_CRIT" ]
					then
						CRIT_ACTION=2
						HDD_TEMP_MESSAGE=$HDD_TEMP_MESSAGE" !!! CRITICAL state !!!"
					fi
					HDD_TEMP_MESSAGE=$HDD_TEMP_MESSAGE$LINE_SEPARATOR
				else
					HDD_TEMP_MESSAGE=$HDD_TEMP_MESSAGE$ITEM" - "
					COUNT=1
				fi
			done
			IFS=$'
'
		done
		IFS=$OLD_IFS
	done
fi

if [ "$DISKS_FOUND" -lt "$DISKS_NEEDED" ]
then
	ERR_ACTION=3
	ERR_MESSAGE=$ERR_MESSAGE$LINE_SEPARATOR"Error: insufficient disks found"${LINE_SEPARATOR}`zpool status -v`${LINE_sEPARATOR}
fi


##
# Prepare output

MAIL_TITLE="Temperature status update"
MAIL_BODY=""

if [ "$WARN_ACTION" -gt 0 ]
then
	MAIL_TITLE="WARNING Temperature high!"
fi

if [ "$CRIT_ACTION" -gt 0 ]
then
        MAIL_TITLE="CRITICAL Temperature!"
fi

if [ "$ERR_ACTION" -gt 0 ]
then
	MAIL_TITLE="ERROR processing temperature status"
	MAIL_BODY=$ERR_MESSAGE$LINE_SEPARATOR$LINE_SEPARATOR
fi

COUNT=0
for CPU_TEMP in $CPU_TEMPS
do
	MAIL_BODY=$MAIL_BODY"Logical CPU "$COUNT" temperature: "$CPU_TEMP$LINE_SEPARATOR
	COUNT=`$EXPR $COUNT + 1`
done


if [ -x $MBMON ] && [ -n "$MB_TEMP" ] && [ "$MB_TEMP" -gt 0 ]
then
	MAIL_BODY=${MAIL_BODY}${LINE_SEPARATOR}"Motherboard temperature: "${MB_TEMP}${LINE_SEPARATOR}
fi


MAIL_BODY=$MAIL_BODY$HDD_TEMP_MESSAGE


##
# Send output

if [ "$WARN_ACTION" -gt 0 ] || [ "$CRIT_ACTION" -gt 0 ] || [ "$ERR_ACTION" -gt 0 ]
then
	#echo -e "To: ${DEST_EMAIL}\nSubject: ${MAIL_TITLE}\n\n${MAIL_BODY}" 
	echo -e "To: ${DEST_EMAIL}\nSubject: ${MAIL_TITLE}\n\n${MAIL_BODY}" | $SENDMAIL ${SENDMAIL_PARAMS}
fi

