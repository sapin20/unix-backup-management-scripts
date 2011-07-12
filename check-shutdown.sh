#!/bin/sh

##
# Option variables

TRIGGERFILE="/home/storage/shut-down"
TRIGGERFILEALT="/home/storage/shut-down"

##
# External programs

RM=/bin/rm
POWEROFF=/sbin/poweroff
LOGGER=/usr/bin/logger

if [ -f "$TRIGGERFILE" ] || [ -f "$TRIGGERFILEALT" ]
then
	$LOGGER Shutdown requested by flag file
	$RM -f $TRIGGERFILE
	$RM -f $TRIGGERFILEALT
	$POWEROFF
fi


