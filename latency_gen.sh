#!/bin/bash
#
### set the paths
command="/bin/ping -q -n -c 3"
gawk="/usr/bin/gawk"
rrdtool="/usr/bin/rrdtool"



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


### change to the script directory
cd ${graphsdir}



if [[ ! -f  ${d} ]]; then

	echo "Database not exists! Creating!"
	echo
	rrdtool create $database \
	--step 180 \
	DS:pl:GAUGE:540:0:100 \
	DS:rtt:GAUGE:540:0:10000000 \
	RRA:MAX:0.5:1:500\

	echo "Adding CRON Job for user $USER"
        tmpfile=$(mktemp)
        crontab -l >"$tmpfile"
        printf '%s\n' "*/5 * * * * $graphsdir/bin/latency_gen.sh -h $hosttoping -d $database -o $graphsdir 2>/dev/null" >>"$tmpfile"
        crontab "$tmpfile" && rm -f "$tmpfile"
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
 
### update the database
$rrdtool update $database --template pl:rtt N:$RETURN_DATA


## Graph for last 24 hours
/usr/bin/rrdtool graph $hosttoping.png \
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
LINE1:roundtrip#0000FF:"latency(ms)" \
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

