#!/bin/bash

# Copyright 2013 Omid Khanmohamadi (OmidLink@Gmail.com)
#
# lscmdoutput.sh is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

params="$(getopt -o m:f: --long message:,file: --name "$0" -- "$@")"
eval set -- "$params"

while true
do
    case "$1" in
        -m|--message)
	    dispmsg=$2
            shift 2
            ;;
        -f|--file)
	    tmpfile=$2
            shift 2
            ;;
        --)			# default to wlan0 if no arg passed in
            shift
            break
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done
inputcmd=$1

getactionrowNum(){
    action=${actionrowNum:0:1}		# get first character of $actionrowNum

    # Double bracket operator "[[ ]]" supports regular expressions via
    # the "=~" operator.

    # if the first character is a number, keep all characters.
    if [[ ${action} =~ [0-9] ]]; then
	action=""
	rowNum=$actionrowNum
	# double parentheses "(())" do integer arithmetic in bash
	outputrow="${outputarray[((${rowNum} - 1))]}"

    # otherwise, remove first character from $actionrowNum
    else
	rowNum=${actionrowNum#?}
	if [[ -z $rowNum ]]; then
	    outputrow=""
	else
	    outputrow="${outputarray[((${rowNum} - 1))]}"
	fi
    fi
}

IFS=$'\n'

outputarray=( $(eval "$inputcmd") )
echo "${outputarray[*]}" | cat -n | \
    less --quit-at-eof --quit-if-one-screen \
    --ignore-case --hilite-unread --no-init

read -p $dispmsg actionrowNum

getactionrowNum

# There is no straightforward and general way to return an arbitrary
# value by a shell script, let alone return several arbitary values,
# especially when the script writes to stdout values that are not part
# of the return values, as is the case here. In particular, none of the hacks discussed below works in our case:
# http://tldp.org/LDP/abs/html/assortedtips.html
# http://www.linuxjournal.com/content/return-values-bash-functions
# https://stackoverflow.com/questions/3236871/how-to-return-a-string-value-from-a-bash-function/14541533#14541533
# 
# The hack I'm using below is due to myself: Write the return values
# to a tmp file whose name is passed in by the script calling us and
# leave the task of retrieving the return values from that file to the
# caller. Another solution would be to use a named pipe (fifo) instead
# of a tmp file, since the data to be comuunicated is less than 64kB
# (what a named pipe can handle). That would have the advantage that
# only an inode is created for the file (rather than the whole file);
# no data would be written to disk. (N.B. reading and writing to a
# named pipe are blocking.) A better solution is to use another
# language (Python maybe) that does not have this limitation!

echo $action>"$tmpfile"
echo $outputrow>>"$tmpfile"

unset IFS
