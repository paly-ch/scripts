#!/bin/bash

# set -x

HOSTSFILE=${1:-"hosts.txt"}
SCRIPTFILE=${2:-"script.sh"}

echo $HOSTSFILE
echo $SCRIPTFILE

script="date"
if [ -e $SCRIPTFILE ]
then
    i=0
    while read line
    do
	[[ "$line" == "" || "$line" == "#"* ]] && continue
	script="${script};${line}"
    done < $SCRIPTFILE
fi

echo $script
if [ -e $HOSTSFILE ]
then
    cat $HOSTSFILE | while read h
    do
    [[ "$h" == "" || "$h" == "#"* ]] && continue
    echo $h

#    ssh-copy-id $host && true
    ssh -n root@$h 'date'

    if [ -e $SCRIPTFILE ]
    then
#    echo qqqq
        (ssh -n root@$h 'bash '< $SCRIPTFILE) 2>&1 > $h.log &
    fi

    done
fi

