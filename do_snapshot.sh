#!/bin/sh

DEFAULT_TANK="tank/backup"
COMMON_DATE_FORMAT="%Y-%m-%d"
COMMON_DATETIME_FORMAT="${COMMON_DATE_FORMAT}-%H%M%S"

ZFS=/sbin/zfs
AWK=/usr/bin/awk
DATE=/bin/date

#is_datetime_older()
#{
#	SECONDS=`${DATE} -j -f "$COMMON_DATETIME_FORMAT" "${1}-000000" +%s`
#	DATETIMEOLDEST=`${DATE} -j +${COMMON_DATE_FORMAT}`
#	SECOLDEST=`${DATE} -j -v ${2} -f "$COMMON_DATETIME_FORMAT" "${DATETIMEOLDEST}-000000" +%s`
#	test $(($SECOLDEST - $SECONDS)) -le 0 && return 1 || return 0
#}

is_seconds_older()
{
	DATETIMEOLDEST=`${DATE} -j +${COMMON_DATE_FORMAT}`
        SECOLDEST=`${DATE} -j -v ${2} -f "$COMMON_DATETIME_FORMAT" "${DATETIMEOLDEST}-000000" +%s`
	#echo "${2}"
	#echo "${1} vs $SECOLDEST"
	#echo `${DATE} -j -v ${2} -f "$COMMON_DATETIME_FORMAT" "${DATETIMEOLDEST}-000000"`
	#echo "$(($SECOLDEST - ${1}))"
        test $(($SECOLDEST - ${1})) -ge 0 && return 1 || return 0
}

is_seconds_in_interval()
{
	is_seconds_older ${1} ${3}
	if [ "$?" -gt 0 ]
	then
		return 0
	fi

	is_seconds_older ${1} ${2}
	if [ "$?" -gt 0 ]
	then
		return 1
	fi

	return 0
}


TANK=${1}

echo "DEBUG: tank specified: ${TANK}"

if [ -z "${TANK}" ]
then
	TANK=$DEFAULT_TANK
	echo "DEBUG: using default value for tank"
fi

echo "DEBUG: tank: ${TANK}"

SNAPSHOTS=`${ZFS} list -r -H -t snapshot -o name ${TANK}`

#echo $SNAPSHOTS

OLDEST_M3=""
OLDEST_M3_SECS=""
OLDEST_M2=""
OLDEST_M2_SECS=""
OLDEST_M1=""
OLDEST_M1_SECS=""
OLDEST_W3=""
OLDEST_W3_SECS=""
OLDEST_W2=""
OLDEST_W2_SECS=""

for SNAP in $SNAPSHOTS;
do
	DATETIME=`echo $SNAP | ${AWK} '{split($0,a,"@"); print a[2]}'`
	SECONDS=`${DATE} -j -f "$COMMON_DATETIME_FORMAT" "${DATETIME}-000000" +%s`
#	SECONDS="1309103606" # 15 days
#	SECONDS="1309622156" # 9 days or so
#	SECONDS="1297443905" # 5 months
#	SECONDS="1301933976" # 3 months
#	SECONDS="1304353211" # 2 months
#	SECONDS="1306772456" # 1 month

	# remove everything older than 4 months ago
	is_seconds_older $SECONDS -4m
	if [ "$?" -gt 0 ]
	then
#		${ZFS} destroy $SNAP > /dev/null 2>&1
		echo "DEBUG: destroyed snapshot $SNAP"
		continue
	fi

	is_seconds_older $SECONDS -3m
	if [ "$?" -gt 0 ]
	then
		if [ -z "${OLDEST_M3_SECS}" ] || [ $(($SECONDS - $OLDEST_M3_SECS)) -le 0 ]
		then
			OLDEST_M3_SECS=$SECONDS
			OLDEST_M3=$SNAP
			echo "DEBUG: found new oldest M3 snapshot: $SNAP"
		fi
		continue
	fi
       
	is_seconds_older $SECONDS -2m
	if [ "$?" -gt 0 ]
	then
		if [ -z "${OLDEST_M2_SECS}" ] || [ $(($SECONDS - $OLDEST_M2_SECS)) -le 0 ]
		then
			OLDEST_M2_SECS=$SECONDS
			OLDEST_M2=$SNAP
			echo "DEBUG: found new oldest M2 snapshot: $SNAP"
		fi
		continue
	fi

	is_seconds_older $SECONDS -1m
	if [ "$?" -gt 0 ]
	then
		if [ -z "${OLDEST_M1_SECS}" ] || [ $(($SECONDS - $OLDEST_M1_SECS)) -le 0 ]
		then
			OLDEST_M1_SECS=$SECONDS
			OLDEST_M1=$SNAP
			echo "DEBUG: found new oldest M1 snapshot: $SNAP"
		fi
		continue
	fi

	is_seconds_in_interval $SECONDS -2w -3w
	if [ "$?" -gt 0 ]
	then
		if [ -z "${OLDEST_W3_SECS}" ] || [ $(($SECONDS - $OLDEST_W3_SECS)) -le 0 ]
		then
			OLDEST_W3_SECS=$SECONDS
			OLDEST_W3=$SNAP
			echo "DEBUG: found new oldest W3 snapshot: $SNAP"
		fi
		continue
	fi

	is_seconds_in_interval $SECONDS -1w -2w
	if [ "$?" -gt 0 ]
	then
		if [ -z "${OLDEST_W2_SECS}" ] || [ $(($SECONDS - $OLDEST_W2_SECS)) -le 0 ]
		then
			OLDEST_W2_SECS=$SECONDS
			OLDEST_W2=$SNAP
			echo "DEBUG: found new oldest W2 snapshot: $SNAP"
		fi
		continue
	fi
done


# delete all snapshots (that have not been already deleted) older than one week that are not the oldest in their class

SNAPSHOTS=`${ZFS} list -r -H -t snapshot -o name ${TANK}`

for SNAP in $SNAPSHOTS
do
	DATETIME=`echo $SNAP | ${AWK} '{split($0,a,"@"); print a[2]}'`
	SECONDS=`${DATE} -j -f "$COMMON_DATETIME_FORMAT" "${DATETIME}-000000" +%s`

	is_seconds_older $SECONDS -1w
	if [ "$?" -gt 0 ]
	then
		if [ -n "${OLDEST_W2_SECS}" ] && [ "$SNAP" = "$OLDEST_W2" ]
		then
			continue
		fi

		if [ -n "${OLDEST_W3_SECS}" ] && [ "$SNAP" = "$OLDEST_W3" ]
		then
			continue
		fi

		if [ -n "${OLDEST_M1_SECS}" ] && [ "$SNAP" = "$OLDEST_M1" ]
		then
			continue
		fi

		if [ -n "${OLDEST_M2_SECS}" ] && [ "$SNAP" = "$OLDEST_M2" ]
		then
			continue
		fi

		if [ -n "${OLDEST_M3_SECS}" ] && [ "$SNAP" = "$OLDEST_M3" ]
		then
			continue
		fi

		# whatever is left is a snapshot older than one week and not a weekly or a monthly
		${ZFS} destroy $SNAP > /dev/null 2>&1
		echo "DEBUG: destroyed snapshot $SNAP"
	fi
done


#Create new Snapshot

SNAP_CREATE=`${DATE} -j +${COMMON_DATE_FORMAT}`
${ZFS} snapshot ${TANK}@$SNAP_CREATE

