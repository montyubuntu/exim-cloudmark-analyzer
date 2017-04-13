#!/usr/bin/env bash

#20150612, Jannick Sikkema, Tool that finds CMAE fingerprints and additional mail logging with -v option in EXIM mail logfiles.

# User defined variables:
BASE="/opt/syslog"
CDATE=`date +%Y%m%d`
TMP="/var/tmp"
CORES='2' # Number of available cores
SMTP_PREFIX='smtp' #Directory prefix for your SMTP logfiles
MX_PREFIX='mx' #Directory prefix for your MX/POP/IMAP logfiles
ZGREP='/bin/bzgrep' # Define tour bzgrep / zgrep binary for zipped files
VERBOSE='0'

# Common variables
SID="`echo $RANDOM`e`date +%s`"
INDEX="$TMP/index_"$SID"_`date +%Y%m%d`.txt"
EIDLIST="$TMP/elements_"$SID"_`date +%Y%m%d`.txt"
OUT_FILE="$TMP/out_file_"$SID"_`date +%Y%m%d`.txt"
LC_ALL='C'

#Help info
show_help () {
    echo -e "---This tool finds CMAE fingerprints in exim smtp & mx mail log files---\n
Specify search operand flag for smtp or mx logs, email address and date.\n
Usage: ${0##*/} [-f "$SMTP_PREFIX"/"$MX_PREFIX"].... [-a ADDRESS].... [-d DATE 'YYYYMMDD'].... [-v VERBOSE]...\n"
}

#Validate supplied arguments and bail out if the conditions are not met.
validate_args () {
    if [ ! "$flag" == "$SMTP_PREFIX" ] && [ ! "$flag" == "$MX_PREFIX" ]; then
        echo -e "\n"$flag" Flag parameter is not a valid "$SMTP_PREFIX" / "$MX_PREFIX" identifier... exiting...\n"
        exit 1
    fi

    if [ -z `echo "$address"  | grep -F '@'` ] || [ -z `echo "$address" | grep -F '.'` ] || [ `echo "$address" | wc -m` -lt '8' ]; then
        echo -e "\n"$address" Address parameter is not a valid email address... exiting...\n"
        exit 1
    fi

    nrregex='^[0-9]+$'
    if [[ ! "$date" =~ $nrregex ]] || [ ! `echo "$date" | wc -c` -eq 9 ]; then
        echo -e "\n"$date" Date parameter has invalid numerical format, use: YYYYMMDD\n"
        exit 1
    fi
}

#Stop the script nicely if ctrl+c was pressed.
interrupt_handler () {
    trap '{ echo " - Interrupt signal received, please wait for all file handlers to finish...";
    p_kill 2> /dev/null;
    uniq "$INDEX" 2> /dev/null;
    uniq "$EIDLIST" 2> /dev/null;
    uniq "$OUT_FILE" 2> /dev/null;
    unlink "$INDEX" 2> /dev/null;
    unlink "$EIDLIST" 2> /dev/null;
    unlink "$OUT_FILE" 2> /dev/null;
    exit 0;}' INT
}

#Validation run, set the grep/bzgrep binary on basis of timestamp argument and find all relevant mail logging with the mail address argument.
get_mail () {
    filecount="$(ls -1 $BASE/$flag*/maillog-$date* | wc -l)"
    if [ "$filecount" -lt '1' ]; then
        echo -e "\nNo log files available for: "$date", try a different timestamp...\n"
        exit 1
    fi

    if [ "$date" == "$CDATE" ]; then
        grep_bin='/bin/grep'
    else
        grep_bin="$ZGREP"
    fi

    if [ -d "$TMP" ]; then
        echo -e "\nSearching mail sessions for "$address" with timestamp: "$date" within "$BASE/$flag*" in "$filecount" exim log files...\n
This might take some time... relax and get a cup of coffee..."
        touch "$INDEX"
        find $BASE/$flag* -name "maillog-$date*" -print0 | xargs -0 -n1 -P"$CORES" $grep_bin -EHi "[</ ]"$address"[>/ ]" >> $INDEX;
    else
        echo -e "\nError - Failed accessing "$TMP", exiting...\n"
        exit 1
    fi

    if [ `tail -c 10 "$INDEX" | wc -m` -eq 0 ]; then
        echo -e "\nNo mails found in "$flag" logfiles for "$address" with date: "$date"... exiting...\n"
        unlink "$INDEX"
        exit 0
    fi

    if [ "$VERBOSE" == 1 ]; then
        echo -e "\nSession ID = "$SID", Displaying terse exim logging for "$address" with date: "$date" within "$flag" log files...\n"
        cat "$INDEX"
    fi
}

#Get exim ID on basis of filename, exim ID and related time stamp in {Month day hour minute} format.
#Fill the array with these arguments and if 2 exim id's are found on the same line insert these in the array seperatly.
get_exim_id () {
    IFS=$'\n'
    declare -a EIDARRAY
    for i in `uniq "$INDEX"`; do
        file_split=`echo "$i" | grep -Eo "^/opt/.*2[0-1][0-9][0-9][0-9][0-9][0-9][0-9]|.*\.bz2"`
        id_split=`echo "$i" | grep -Eo 'exim\[[0-9]*\]'`
        time_split=`echo "$i" | grep -Eo '[A-S][a-u][a-z]\ .[1-9]\ [0-2][0-9]:[0-6][0-9]:'`
        if [ -r "$file_split" ] && [ -n "$id_split" ] && [ -n "$time_split" ]; then
            if [ `echo "$id_split" | wc -w` -gt '1' ] ||  [ `echo "$time_split" | wc -w` -gt '3' ]; then
                id_split1=`echo "$id_split" | awk '{print $1}'`; time_split1=`echo "$time_split" | cut -d ' ' -f 1-3`
                id_split2=`echo "$id_split" | awk '{print $2}'`; time_split2=`echo "$time_split" | cut -d ' ' -f 4-6`
                EIDARRAY+=("$file_split $id_split1 $time_split1")
                EIDARRAY+=("$file_split $id_split2 $time_split2")
                unset file_split id_split1 id_split2 time_split1 time_split2
            else
                EIDARRAY+=("$file_split $id_split $time_split")
                unset file_split id_split time_split
            fi
        else
            unset file_split id_split time_split
            continue
        fi
    done

    touch "$EIDLIST"
    for i in "${EIDARRAY[@]}"; do
        echo "$i" >> "$EIDLIST"
    done
    #Delete mashed lines, since syslog uses UDP lines may be cut off.
    sed -i '/^[^/]/d' "$EIDLIST"; sed -i '/[:$]$/!d' "$EIDLIST";

    if [ "$VERBOSE" == 1 ]; then
        echo -e "\nShowing unique exim mail instances for "$address" with date: "$date" within "$flag" log files...\n"
        uniq "$EIDLIST"
    fi
    unset IFS
}

# Get the cloudmark header on basis of filename, exim id, timestamp or spew out all related exim logging if verbose ('-v') was set.
get_cmae () {
    if [ "$VERBOSE" == 0 ]; then
        echo -e "\nGetting CMAE fingerprint headers...\n"
    else
        echo -e "\nGetting all "$flag" exim logging for "$address" at "$date"...\n"
    fi

    IFS=$'\n'
    log_count=`uniq "$EIDLIST" | wc -l`
    for i in `uniq "$EIDLIST"`; do
        file_split=`echo "$i" | awk '{print $1}'`
        id_split=`echo "$i" | awk '{print $2}'`
        time_split=`echo "$i" | cut -d ' ' -f 3-8`
        if [ ! -r "$file_split" ] || [ -z "$id_split" ] || [ -z "$time_split" ]; then
            continue
        fi
        touch "$OUT_FILE"
        if [ "$VERBOSE" == 1 ]; then
            LANG=C $grep_bin -F "$id_split" "$file_split" | grep -F "$time_split" >> "$OUT_FILE" & p_wait "$CORES"
        else
            LANG=C $grep_bin -F "$id_split" "$file_split" | grep -F "$time_split" | grep -F 'report=CMAE Analysis:' | grep -F ' p=' >> "$OUT_FILE" & p_wait "$CORES"
        fi
    done
    unset file_split id_split time_split IFS
    p_watch
}

# Function that speeds up operations in a for loop by spawning multiple instances of a binary.
p_wait () {
    while [ $(jobs -p | wc -l) -ge "$1" ]; do
        sleep 1
    done
}

# Kill all jobs that are still running if the interrupt_handler is used.
p_kill () {
    if [ $(jobs -p | wc -l) -ge 1 ]; then
        for i in `jobs -p`; do
            kill -9 "$i"
        done
    fi
}

# Wait for jobs to finish nicely.
p_watch () {
    for i in `jobs -p`; do
        wait "$i"
    done
}

# Show gathered data.
print_output () {
    if [ "$VERBOSE" == 0 ]; then
        cat "$OUT_FILE" | sort -u 2> /dev/null
        echo -e "\nDone, only showing results if positive CMAE headers are found in "$log_count" exim log(s)...\n"
    else
        cat "$OUT_FILE" 2> /dev/null
        echo -e "\nDone... showing verbose results from "$log_count" log(s)...\n"
    fi
    unlink "$INDEX" 2> /dev/null
    unlink "$EIDLIST" 2> /dev/null
    unlink "$OUT_FILE" 2> /dev/null
}

#Get shell options and initiate functions.
while getopts "f:a:d:v" opt; do
    case $opt in
    f) flag=$OPTARG
       flag=`echo "$flag" | tr '[:upper:]' '[:lower:]'`
        ;;
    a) address=$OPTARG
        ;;
    d) date=$OPTARG
        ;;
    v) VERBOSE='1'
        ;;
    esac
done

shift $(( OPTIND - 1 ))

[ "$1" = "--" ] && shift

if [ -z "$flag" ] || [ -z "$address" ] || [ -z "$date" ]; then
    echo -e "\nError: Invalid or missing argument... exiting...\n"
    show_help
    exit 1
else
    validate_args
    interrupt_handler
    get_mail
    get_exim_id
    get_cmae
    print_output
fi
