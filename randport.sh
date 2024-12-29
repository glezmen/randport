#!/bin/bash
#
#	Select a random airport
#	options:
#		-i only with IATA codes
#		-b enable balloonports
#		-h enable heliports
#		-o only open airports (ignore closed)
#		-s only seaplane bases
#		-l only large airports
#		-m only medium and large airports
#		-v verbose output
#		-c <countrycode> select country
#		-C <continent> select continent

###############
# Database file
###############
DIR=$(dirname $(readlink -f $0))
FILENAME="ourairports-data/airports.csv"
DBFILE="$DIR/$FILENAME"
LINECOUNT=$(wc -l "$DBFILE" | grep -o '[0-9]\+\s')

# Columns
# "id","ident","type","name","latitude_deg","longitude_deg","elevation_ft","continent","iso_country","iso_region","municipality","scheduled_service","gps_code","iata_code","local_code","home_link","wikipedia_link","keywords"
COL_IDENT=2
COL_TYPE=3
COL_NAME=4
COL_LAT=5
COL_LON=6
COL_CONTINENT=8
COL_COUNTRY=9
COL_REGION=10
COL_IATA=14
COL_LOCALCODE=15
COL_HOMELINK=16
COL_WIKIPEDIA=17

ARR_TYPES=$(cat $DBFILE | cut -d , -f $COL_TYPE | tr -d \" | sort| uniq | grep -v type)
ARR_CONTINENTS=$(cat $DBFILE | cut -d , -f $COL_CONTINENT | tr -d \" | sort| uniq | grep -v continent | grep -v '[0-9]')
ARR_COUNTRIES=$(cat $DBFILE | cut -d , -f $COL_COUNTRY | tr -d \" | sort| uniq | grep -v continent | grep -v '[0-9]')

#for t in ${ARR_TYPES[@]}; do
#	echo "TYPE: $t"
#done

get_random_line() {
	RAND=$(od -N 4 -t uL -An /dev/urandom | tr -d " ")
	LINENR=$((RAND % $LINECOUNT + 1))
	LINE=$(head -n $LINENR "$DBFILE" | tail -n 1)
}

get_col() {
	echo $LINE | cut -d , -f $1 | tr -d \"
}

help() {
	echo "Usage: $0 [-b] [-h] [-o] [-s] [-l] [-m] [-c <countrycode>] [-C <continent>]"
	echo "Options:"
	echo "	-i Only with IATA codes"
	echo "	-b Enable balloonports"
	echo "	-h Enable heliports"
	echo "	-o Only open airports (ignore closed)"
	echo "	-s Enable seaplane bases"
	echo "	-l Only large airports"
	echo "	-m Only medium and large airports"
	echo "	-v verbose output"
	echo "	-c <countrycode> Select country"
	echo "	-C <continent> Select continent"
	exit 1
}

###############
# Parse args
###############

IATA=""
BALLOONPORTS=""
HELIPORTS=""
OPEN=""
SEAPLANEBASES=""
LARGE=""
MEDIUM=""
COUNTRY=""
CONTINENT=""
VERBOSE=""
while getopts "ibhoslmvc:C:" opt; do
	case ${opt} in
		i ) IATA=1 ;;
		b ) BALLOONPORTS=1 ;;
		h ) HELIPORTS=1 ;;
		o ) OPEN=1 ;;
		s ) SEAPLANEBASES=1 ;;
		l ) LARGE=1 ;;
		m ) MEDIUM=1 ;;
		v ) VERBOSE=1 ;;
		c ) COUNTRY=$OPTARG ;;
		C ) CONTINENT=$OPTARG ;;
		* ) help ;;
	esac
done

[ -n "$VERBOSE" ] && echo DB file: $DBFILE, $LINECOUNT lines

# Airport size/type filter
###############

TYPE=""
if [ -n "$LARGE" ]; then
	TYPE="\"large_airport\""
elif [ -n "$MEDIUM" ]; then
	TYPE="\(\"large_airport\"\|\"medium_airport\"\)"
fi
if [ -n "$SEAPLANEBASES" ]; then
	if [ -n "$TYPE" ]; then
		echo "ERROR: Can't combine seaplane bases with other airport types"
		exit 1
	fi
	TYPE="\"seaplane_base\""
fi
[ -n "$VERBOSE" -a -n "$TYPE" ] && echo Type filter: $TYPE

# Location
###############

if [ -n "$COUNTRY" ]; then
	COUNTRY=\"$(echo "$COUNTRY" | tr '[:lower:]' '[:upper:]')\"
	[ -n "$VERBOSE" ] && echo Country filter: $COUNTRY
fi

if [ -n "$CONTINENT" ]; then
	if [ -n "$COUNTRY" ]; then
		echo WARNING: Both continent and country specified
	fi
	CONTINENT=\"$(echo "$CONTINENT" | tr '[:lower:]' '[:upper:]')\"
	[ -n "$VERBOSE" ] && echo Continent filter: $CONTINENT
fi

##############################
# Filter DB to make it smaller
##############################

FILTERED_DB="$DIR/filtered.csv"
cat $DBFILE | grep "$COUNTRY" | grep "$CONTINENT" | grep "$TYPE" > $FILTERED_DB
DBFILE=$FILTERED_DB
LINECOUNT=$(wc -l "$DBFILE" | grep -o '[0-9]\+\s')

if [ $LINECOUNT -eq 0 ]; then
	echo ERROR: No airports match filters!
	exit 1
fi

[ -n "$VERBOSE" ] && echo Filtered lines in $FILTERED_DB: $LINECOUNT

##############################
# Find matching airport
##############################

COUNT=1
FAIL=1
while [ "$FAIL" == "1" ]; do
	[ -n "$VERBOSE" ] && echo Attempt $COUNT
	FAIL=0

	get_random_line

	[ -n "$VERBOSE" ] && echo Trying $LINE

	if [ -n "$COUNTRY" -a "\"$(get_col $COL_COUNTRY)\"" != "$COUNTRY" ]; then
		FAIL=1
	fi
	if [ -n "$CONTINENT" -a "\"$(get_col $COL_CONTINENT)\"" != "$CONTINENT" ]; then
		FAIL=1
	fi

	type="$(get_col $COL_TYPE)"
	if [ -z "$BALLOONPORTS" -a "$type" == "balloonport" ]; then
		FAIL=1
		[ -n "$VERBOSE" ] && echo "Balloonports disabled"
	fi
	if [ -z "$HELIPORTS" -a "$type" == "heliport" ]; then
		FAIL=1
		[ -n "$VERBOSE" ] && echo "Heliports disabled"
	fi

	if [ "$type" == "closed" -a -n "$OPEN" ]; then
		FAIL=1
		[ -n "$VERBOSE" ] && echo "Closed airports disabled"
	fi

	if [ -z "$(get_col $COL_IATA)" -a -n "$IATA" ]; then
		FAIL=1
		[ -n "$VERBOSE" ] && echo "IATA code required"
	fi

	COUNT=$((COUNT + 1))
done

##############################
# FOUND
##############################

echo
echo Name: $(get_col $COL_NAME)
echo Type: $(get_col $COL_TYPE)
echo IATA: $(get_col $COL_IATA)
echo Local code: $(get_col $COL_LOCALCODE)
echo Ident: $(get_col $COL_IDENT)
echo Continent: $(get_col $COL_CONTINENT)
echo Country: $(get_col $COL_COUNTRY)
echo Region: $(get_col $COL_REGION)
echo Home page: $(get_col $COL_HOMELINK)
echo Wikipedia: $(get_col $COL_WIKIPEDIA)
