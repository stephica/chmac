#!/bin/bash

# Copyright 2013 Omid Khanmohamadi (OmidLink@Gmail.com)
#
# chkeyval.sh is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

# We use "$@" to let each command-line parameter expand to a separate
# word. The doublequotes around it are essential!
params="$(getopt -o k:v:s: --long key:,value:,section: --name "$0" -- "$@")"

# We need the temporary variable params as the eval set -- would nuke
# the return value of getopt. Here again the double quotes are
# essential!
eval set -- "$params"

while true
do
    case "$1" in
        -k|--key)
            key=$2
            shift 2
            ;;
        -v|--value)
            value=$2
            shift 2
            ;;
	-s|--section)
	    section=$2
	    shift 2
	    ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

filename=$1

tmpfilename=$(mktemp)
keyvaluepair=${key}${value}

if grep -q "$key" "$filename"; then # $key exists in $filename
    # https://unix.stackexchange.com/questions/91080/maintain-or-restore-file-permissions-when-replacing-file/91181#91181

    cp --preserve=mode,ownership,timestamps \
	"$filename" "$tmpfilename"

    sed "s#^\($key\).*#\1$value#" \
	"$filename" > "$tmpfilename"

    mv --force "$tmpfilename" "$filename"
else
    # 1st condition: $0 ~ sec
    # 
    # meaning: does current line ($0) contain (~) sec (which here is
    # an awk dynamic var to which the value "$section" from the shell
    # variable is assigned)?
    # 
    # 1st action: { print; print keyval; next}
    #
    # meaning: print current line (equiv to print $0); print keyval;
    # stop processing further conditions/actions for current line and
    # move on to the next line (next)
    # 
    # 2nd condition: empty
    #
    # meaning: always true
    #
    # 2nd action: print current line
    #
    # The second condition+action may be abbreviated to 1 (1 being the
    # always true condition resulting in the default action which is {
    # print $0} ) so that we get
    # 
    # '$0 ~ sec { print; print keyval; next }1'
    #
    # https://www.gnu.org/software/gawk/manual/html_node/Using-Shell-Variables.html

    cp --preserve=mode,ownership,timestamps \
	"$filename" "$tmpfilename"

    awk -v keyval="$keyvaluepair" \
	-v sec="$section" \
	'$0 ~ sec { print; print keyval; next } { print }' \
	"$filename" > "$tmpfilename"

    mv --force "$tmpfilename" "$filename"
fi
