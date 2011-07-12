#!/bin/sh

##
# Option variables

OUTPUTFILE="raid-status.txt"
OUTPUTDIR="/root/"

##
# External programs

AWK=/usr/bin/awk
GREP=/bin/grep
MDADM=/sbin/mdadm
CHOWN=/bin/chown
CHMOD=/bin/chmod
TAIL=/usr/bin/tail
MV=/bin/mv

MDADMPARAMS="--detail"
MDADMDEVICE="/dev/md2"

if [ -d "/home/storage" ]
then
	OUTPUTDIR="/home/storage/"
else
	if [ -d "/home/backup" ]
	then
		OUTPUTDIR="/home/backup/"
	fi
fi

FIXPERMS=0
if [ ! -w "$OUTPUTDIR$OUTPUTFILE" ]
then
	FIXPERMS=1
else
	# keep only the last 100 lines in the file
	$TAIL -q -n 100 $OUTPUTDIR$OUTPUTFILE > ${OUTPUTDIR}${OUTPUTFILE}-new
	$MV -f ${OUTPUTDIR}${OUTPUTFILE}-new $OUTPUTDIR$OUTPUTFILE
	FIXPERMS=1
fi


echo >> $OUTPUTDIR$OUTPUTFILE
echo "---------------------------------------------------------------" >> $OUTPUTDIR$OUTPUTFILE
date >> $OUTPUTDIR$OUTPUTFILE

if [ "$FIXPERMS" -gt 0 ]
then
	$CHOWN nobody:nogroup $OUTPUTDIR$OUTPUTFILE
	$CHMOD a+w $OUTPUTDIR$OUTPUTFILE
fi

OUTPUT=`$MDADM $MDADMPARAMS --test $MDADMDEVICE`
MDADMRESULT=$?

STATE=`$MDADM $MDADMPARAMS $MDADMDEVICE | $AWK ' /State :/ { for (i=3; i<=NF; i++) print $i } '`

if [ "$MDADMRESULT" -eq 0 ] || [ "clean" == "$STATE" ] || [ "active" == "$STATE" ]
then
	echo "Raid status normal" >> $OUTPUTDIR$OUTPUTFILE
else
	echo "Potential raid issue" >> $OUTPUTDIR$OUTPUTFILE
	
	if [ -x $MDADM ]
	then
		DEGRADED=0
		RECOVERING=0
		for STATUS in ${STATE}
		do
			if [ "degraded" == "$STATUS" ] || [ "degraded," == "$STATUS" ]
			then
				DEGRADED=1
			fi
			if [ "recovering" == "$STATUS" ] || [ "recovering," == "$STATUS" ] || [ "resyncing" == "$STATUS" ] || [ "resyncing," == "$STATUS" ]
                        then
                                RECOVERING=1
                        fi
		done

		if [ "$RECOVERING" -gt 0 ]
		then
			echo "Raid is recovering after a previous issue. You may find it slow during this operation. This operation's progress is displayed below." >> $OUTPUTDIR$OUTPUTFILE
		else
			if [ "$DEGRADED" -gt 0 ]
			then
				echo "Raid degraded. If power failures / unclean shutdowns occured this is expected. Otherwise REPLACE the failed drive!" >> $OUTPUTDIR$OUTPUTFILE
				echo "Assuming power failure / unclean shutdown and attempting to recover." >> $OUTPUTDIR$OUTPUTFILE
				echo "Check following reports. If raid does not go into recovering you may have FAILED DRIVE(S)." >> $OUTPUTDIR$OUTPUTFILE
				$MDADM --manage /dev/md0 --add /dev/sda1 &> /dev/null
				$MDADM --manage /dev/md1 --add /dev/sda2 &> /dev/null
				$MDADM --manage /dev/md2 --add /dev/sda3 &> /dev/null
				$MDADM --manage /dev/md0 --add /dev/sdb1 &> /dev/null
				$MDADM --manage /dev/md1 --add /dev/sdb2 &> /dev/null
				$MDADM --manage /dev/md2 --add /dev/sdb3 &> /dev/null

			else
				echo "UNKNOWN non-normal status. Investigate the situation using the output below." >> $OUTPUTDIR$OUTPUTFILE
			fi
		fi

		echo >> $OUTPUTDIR$OUTPUTFILE
		echo -e "Original command output:\n$OUTPUT" >> $OUTPUTDIR$OUTPUTFILE
	else
		echo "Cannot find raid administartion command: $MDADM" >> $OUTPUTDIR$OUTPUTFILE
	fi
fi


