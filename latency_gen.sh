#!/bin/bash
#
### set the paths
command="/bin/ping -q -n -c 3"
gawk="/usr/bin/gawk"
rrdtool="/usr/bin/rrdtool"
iface="enp5s0"
bind=`ifconfig $iface| grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`
log="latency.log"


usage() { echo "Usage: $0 [-h <192.168.1.1>] [-d <192.168.1.1.rrd>] [-o </var/www/html/latency>]" 1>&2; exit 1; }

while getopts ":h:d:o:" options; do
    case "${options}" in
        h)
            h=${OPTARG}
            ;;
        d)
            d=${OPTARG}
            ;;
	o)
	    o=${OPTARG}
	    ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${h}" ] || [ -z "${d}" ] || [ -z "${o}" ] ; then
    usage
fi


echo "Getting ARGS ..."
echo
echo "h = ${h}"
echo "d = ${d}"
echo "o = ${o}"
echo
echo "Got ARGS, continue ..."

#Set ARGS to variables

hosttoping=$h
database=$d
graphsdir=$o


### write log

write_log()
{
    echo "`date '+%m/%d %H:%M:%S'` $1" >> $log
}



### change to the script directory
cd ${graphsdir}

if [[ ! -d bin/ ]] ; then

        mkdir -p bin
        cp "$0" bin/
fi

if [[ ! -f  ${d} ]]; then

	echo "Database not exists! Creating!"
	echo
	rrdtool create $database \
	--step 300 \
	DS:pl:GAUGE:540:0:100 \
	DS:rtt:GAUGE:540:0:10000000 \
	RRA:MAX:0.5:1:500\

	if [ $? == 0 ] ; then
           write_log "Generating initial database for $hosttoping"
        fi

	echo "Adding CRON Job for user $USER"
        tmpfile=$(mktemp)
        crontab -l >"$tmpfile"
        printf '%s\n' "*/5 * * * * $graphsdir/bin/latency_gen.sh -h $hosttoping -d $database -o $graphsdir 2>/dev/null" >>"$tmpfile"
        crontab "$tmpfile" && rm -f "$tmpfile"

	if [ $? == 0 ] ; then
           write_log "Added cron job for $hosttoping"
        fi
fi


### data collection routine 
get_data() {
    local output=$($command $1 2>&1)
    local method=$(echo "$output" | $gawk '
        BEGIN {pl=100; rtt=0.1}
        /packets transmitted/ {
            match($0, /([0-9]+)% packet loss/, datapl)
            pl=datapl[1]
        }
        /min\/avg\/max/ {
            match($4, /(.*)\/(.*)\/(.*)\/(.*)/, datartt)
            rtt=datartt[2]
        }
        END {print pl ":" rtt}
        ')
    RETURN_DATA=$method
}
 
 
### collect the data
get_data $hosttoping

if [ $? == 0 ] ; then
write_log "Collected host data for $hosttoping"
fi

### update the database
$rrdtool update $database --template pl:rtt N:$RETURN_DATA

if [ $? == 0 ] ; then
write_log "Updating database for $hosttoping"
fi

## Graph for last 24 hours
/usr/bin/rrdtool graph $hosttoping-day.png \
-w 785 -h 120 -a PNG \
--slope-mode \
--start -86400 --end now \
--font DEFAULT:7: \
--title "Host: $hosttoping" \
--watermark "`date`" \
--vertical-label "latency(ms)" \
--lower-limit 0 \
--right-axis 1:0 \
--x-grid MINUTE:10:HOUR:1:MINUTE:120:0:%R \
--alt-y-grid --rigid \
DEF:roundtrip=$database:rtt:MAX \
DEF:packetloss=$database:pl:MAX \
CDEF:PLNone=packetloss,0,0,LIMIT,UN,UNKN,INF,IF \
CDEF:PL10=packetloss,1,10,LIMIT,UN,UNKN,INF,IF \
CDEF:PL25=packetloss,10,25,LIMIT,UN,UNKN,INF,IF \
CDEF:PL50=packetloss,25,50,LIMIT,UN,UNKN,INF,IF \
CDEF:PL100=packetloss,50,100,LIMIT,UN,UNKN,INF,IF \
AREA:roundtrip#AFE1AF:"latency(ms)" \
GPRINT:roundtrip:LAST:"Cur\: %5.2lf" \
GPRINT:roundtrip:AVERAGE:"Avg\: %5.2lf" \
GPRINT:roundtrip:MAX:"Max\: %5.2lf" \
GPRINT:roundtrip:MIN:"Min\: %5.2lf\t\t\t" \
COMMENT:"pkt loss\:" \
AREA:PLNone#FFFFFF:"0%":STACK \
AREA:PL10#FFFF00:"1-10%":STACK \
AREA:PL25#FFCC00:"10-25%":STACK \
AREA:PL50#FF8000:"25-50%":STACK \
AREA:PL100#FF0000:"50-100%":STACK

if [ $? == 0 ] ; then
write_log "Generating graphs for $hosttoping"
fi	


gen_index() {

graphs=`ls *.png`

### delete current index

rm index.html

cat <<EOF >index.html
<HTML>
<HEAD><TITLE>Latency Statistics</TITLE>
<meta http-equiv=refresh content=30>
</HEAD>
<BODY>
        <center><H1>LATENCY - Ping statistics</H1></center>
<br>
<center>
<table>
<td>
EOF

for item in $graphs
do

cat <<EOF >>index.html
<tr>
        <td><img src=http://$bind/`basename $graphsdir`/$item alt="alt text" ></td>
</tr>
EOF


done


cat <<EOF >>index.html
</td>
</table>
</center>
<br>
EOF

}


if { set -C; 2>/dev/null >latency_gen.lock; }; then
	echo "Generating index"
	gen_index
	trap "rm -f latency_gen.lock" EXIT
   else
        echo "Lock file exists… exiting"
        exit 0
fi
