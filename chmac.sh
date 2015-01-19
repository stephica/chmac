#!/bin/bash

# Copyright 2013 Omid Khanmohamadi (OmidLink@Gmail.com)
#
# chmac.sh is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
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

if [[ $EUID -ne 0 ]]; then
   echo "$0 must be run as root, e.g. using sudo."
   exit 1
fi

macsdir=$HOME/.chmac
macsfile=$macsdir/eth-wlan-macs.txt
scriptdir=$(dirname $(readlink -f $0))
chkeyval=$scriptdir/chkeyval.sh
lscmdoutout=$scriptdir/lscmdoutput.sh

trymac(){
    ifconfig $ethorwlan hw ether $newmac>/dev/null 2>&1
}

genmac(){
    # This function generates a valid MAC by making sure that the
    # least significant bit (LSB) of the left-most byte is 0.
    #
    # See:
    # https://en.wikipedia.org/wiki/MAC_address#Address_details.
    # Src:
    # http://osxdaily.com/2012/05/02/generate-and-set-random-valid-mac-address/
    #
    # When piped to bc, for some reason any hex number of the form
    # "digitletter", such as "8a" leads to a syntax error if the
    # letter is lower case. Try
    #
    # echo 8a | xargs echo "obase=2;ibase=16;" | "bc"
    #
    # gives
    #
    # (standard_in) 1: syntax error
    #
    # while
    #
    # echo 8A | xargs echo "obase=2;ibase=16;" | "bc"
    #
    # works. As a result, I'm converting everything to upper.
    #
    # "bc" makes sure the unaliased version of bc is invokes, just in
    # case there is some unintended effects caused by an aliased version.
    openssl rand -hex 1 |			# gen rand hex byte
	tr '[:lower:]' '[:upper:]' |            # upper case
	xargs echo "obase=2;ibase=16;" | "bc" |	# convert to base 2 (binary)
	cut -c1-6 |				# keep 6 highest bits (drop LSB)
	sed 's/$/00/' |				# tack to right (make LSB) 00
	xargs echo "obase=16;ibase=2;" | "bc" |	# convert to base 16 (hex)
	sed "s/$/:$(openssl rand -hex 5 | sed 's/\(..\)/\1:/g; s/.$//')/" |
	tr '[:lower:]' '[:upper:]'              # upper case
}

lsmac(){
    # grep -oE ...: -o will cause grep to only print the part of the line
    # that matches the expression. [[:xdigit:]]{1,2} will match 1 or 2
    # hexidecimal digits (Solaris doesn't output leading zeros).
    #
    # http://stackoverflow.com/questions/245916/best-way-to-extract-mac-address-from-ifconfig-output
    ifconfig $ethorwlan |
	grep -oE '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' |
	tr '[:lower:]' '[:upper:]'
}

writemac(){
    mkdir --parents $macsdir;
    echo $msg>>$macsfile
}

disableautoconnect(){
    # N.B.: Using "[connection]" instead of "connection]" would lead
    # to a fatal "Unmatched [ or [^" error, due to "[" being a special
    # character in regex context.
    $chkeyval --key "autoconnect=" --value "false" \
	--section "connection]" \
	"$netmansysconfile"
}

writemac2netmansysconfile(){
    $chkeyval --key "cloned-mac-address=" --value "$setmac" \
	--section "802-11-wireless]" \
	"$netmansysconfile"
}

findAPname(){
echo $outputrow | \
    cut --delimiter \' --field 2 --only-delimited --output-delimiter=
}

params="$(getopt -o w:e: --long wlan:,wireless:,eth:,ethernet: --name "$0" -- "$@")"

eval set -- "$params"

iswlan=true
while true
do
    case "$1" in
        -w|--wlan|--wireless)
            ethorwlan=$2
	    rfkill block wlan	     # rfkill is necessary to down wlan later
            shift 2
            ;;
        -e|--eth|--ethernet)
            ethorwlan=$2
	    iswlan=false
            shift 2
            ;;
        --)			# default to wlan0 if no arg passed in
            ethorwlan=wlan0
            shift
            break
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

shouldwrite=true
ifconfig $ethorwlan down && \
newmac=$(genmac)
until trymac
do
    newmac=$(genmac)
done
msgsuffix="(also appended to $macsfile)"

sleep 4s # down or rfkill seem to run asynchronously and without some
	 # sleep we cannot wake up wlan reliably, because it might not
	 # be blocked/downed yet

# [[ ... ]]: compare the actual MAC (stored in setmac) from
# ifconfig with the MAC generated above (stored in newmac) to make
# sure the change went through. (This is an extra check, since "&&" in
# "ifconfig ... up" makes sure we don't do anything unless the
# said command is successful, which means we can up the device with
# the generated newmac.)
ifconfig $ethorwlan up && setmac=$(lsmac)
if [[ "$setmac" != "$newmac" ]]; then
    exec $0		      # call chmac.sh recursively till success
    exit 0
fi
msg="$(date +%Y/%m/%d,%H:%M%Z),${ethorwlan}MAC=$setmac"
if [[ $shouldwrite == true ]]; then
    writemac
fi
echo "$msg $msgsuffix"

# The rest applies only to a wireless connection so exit if not.
if [[ $iswlan == false ]]; then
    exit 0
fi

read -e -p "At this point, you have two options: (1) ENTER y to be presented with a list of Wireless Access Points (AP) in range, choose an AP from the list to have the cloned MAC $setmac written to the connection file associated with the AP chosen (under /etc/NetworkManager/system-connections/), and get connected to it. This ensures that if you get disconnected and reconnect, the cloned MAC $setmac will be used again for that AP, instead of the actual MAC. (2) ENTER n to skip this final step. WARNING: MAC has been cloned for now, but if you choose this option, it will return to its actual value if you get disconnected and reconnect.
(y/N)? " waitreply

inputcmd="nmcli dev wifi list"
dispmsg="Enter # of the Wireless Access Point to connect to (r to RESCAN): "
tmpfile=$(mktemp --tmpdir=/tmp lscmdoutput.XXXXXX)

if [[ ! $waitreply =~ ^[Yy]$ ]]; then
    exit 0
fi

# Enable the wireless devivce $ethorwlan, but make sure we are not
# connected to the internet via that device. The former is required to
# scan for AP's around and the latter ensures we're not reading file
# under /etc/NetworkManager/system-connections/.
action="r"
rfkill unblock wlan && \
nmcli dev disconnect iface "$ethorwlan"
while [[ $action == "r" ]]
do
    $lscmdoutout "$inputcmd" --message "$dispmsg" --file "$tmpfile"
    action=$(awk 'NR==1' "$tmpfile")	# return arg 1 from lscmdoutout.sh
    outputrow=$(awk 'NR==2' "$tmpfile")	# return arg 2 from lscmdoutout.sh
done
rm "$tmpfile"

APname=$(findAPname)
netmansyscondir="/etc/NetworkManager/system-connections"
netmansysconfile="$netmansyscondir/$APname"
keyvaluepair="cloned-mac-address=$setmac"

if [[ ! -f "$netmansysconfile" ]]; then
    # https://unix.stackexchange.com/questions/44471/display-a-menu-of-files-names-and-let-the-user-select-a-file-by-entering-a-numbe
    #
    # The value of PS3 is used as the prompt for the select
    # command. If this variable is not set, the select command
    # prompts with ‘#? ’
    #
    # https://www.gnu.org/software/bash/manual/bashref.html
    #
    PS3="There is no file named $APname under $netmansyscondir. Either you haven't connected to this Access Point before, or NetworkManager has saved it under a different name. Enter # of the file associated with $AP: "
    select netmansysconfile in $netmansyscondir/*
    do
	break		# break after one file number is input
    done
fi

echo -ne "Disabling auto connect in $netmansysconfile ...\r"
disableautoconnect && \
    echo -ne "Disabling auto connect in $netmansysconfile [ DONE ]\r\n"

echo -ne "Writing cloned MAC to $netmansysconfile ...\r"
writemac2netmansysconfile && \
    echo -ne "Writing cloned MAC to $netmansysconfile [ DONE ]\r\n"

sleep 2s
nmcli con up id "$APname"
exit 0
