#!/bin/env ksh

#################################################################################
####                                                                            #
##  Program name: archlog_purge                                                 # 
##                                                                              # 
##  Description: Purge Oracle archve log file                                   # 
##              Usage: archlog_purge -i <ORACLE_SID> -r <RETENTION>
##                      Default Retention: 30 days
##                                                                              # 
##              Require: run under oracle account
##
#################################################################################
## Revision History                                                     #########
#################################################################################
# Wei           v1.0    18 Dec 2014             Creation
#
################################################################################

#################################Function Define ###############################
function Usage                                  
{                                       
        print "ERROR! Usage: ${0##*/} -i <ORACLE_SID> -r <RETENTION :default 30 days> "                                       
}  

function print_msg
{
        #### Function to print messages with timestamp ####
        msg=$*

        if [ ! -z "${msg}" ]
        then
                curdate=$(date '+%D %T')
                print -- "${curdate} : ${msg}" |tee -a ${LOGFILE}
        else
                print -- "${curdate} :" | tee -a ${LOGFILE}
        fi
}

function check_instance
{
        ##### Function toe check whether instance is running ####
        if [ $# -eq 1 ]; then
                if [[ -z $(ps -ef|grep ora_smon_$1|grep -v grep) ]]; then
                        print_msg "Instance $1 is not running. Exit.."
                        return 1
                fi
                if [[ -z $(ps -eaf|grep ora_arc|grep $1|grep -v grep) ]] ; then
                        pring_msg "Instance $1 is not archive mode. Exit.."
                        return 1
                fi
        else
                print_msg "Bad parameter with check_instance"
                return 1
        fi      
        return 0
}

function log_rotate 
{
        #### Function to trunc the log file (MAX LOG SIZE = 10MB) ####
        MAX_LOG_SIZE=10240000 
        if [ -f $1 ]; then
                LOG_SIZE=$(ls -l $1 |awk '{print $5}')
                if [ $LOG_SIZE -ge $MAX_LOG_SIZE ]; then        
                        print_msg "Cutting off the file $1"
                        mv $1 $1.old || fn_log_warn "Moving file $1 failed"
                fi      
        else
                print_msg "$1 not found"
        fi
}

############################## Function Define End  #############################

## Program PATH, Program Name
PP=$(dirname $0)
PN=$(basename "$0" ".sh")

LOGDIR="$HOME/logs"
[ -d $LOGDIR ] || LOGDIR=/tmp
LOGFILE=$LOGDIR/$PN.log
SQLFILE=$LOGDIR/$PN.sql
TMPFILE=$LOGDIR/$PN.tmp

######### Parameter define ################
while getopts i:r: next; do
        case $next in
                i)
                 SID=$OPTARG
                 ;;
                r)
                 RET=$OPTARG
                 ;;
                *)
                 Usage
                 exit 1
                 ;;
        esac
done

RET=${RET:-30}
if [[ -z $SID ]] ; then
        print_msg "ORACLE SID is null. Exit."
        exit 1
fi

check_instance $SID || exit 1

## Get the variables for ORACLE DB environment
export ORACLE_SID=$SID
export ORACLE_HOME=$(/usr/local/bin/dbhome $SID)

## Switch logfile and get the archive log path
echo "alter system switch logfile;" >$SQLFILE
echo "archive log list" >>$SQLFILE
echo "exit" >> $SQLFILE

$ORACLE_HOME/bin/sqlplus '/ as sysdba' < $SQLFILE >$TMPFILE

## Get the archive log path
ARC_PATH=$(cat $TMPFILE|grep "Archive destination"|sed 's/Archive destination//g'|sed 's/ *//g')
print_msg "Get the archive log dest - $ARC_PATH"
        
## Find the older archive log $RET days before
find $ARC_PATH/ -mtime +$RET >$TMPFILE 
if [ -s $TMPFILE ]; then
        print_msg "Start to delete $(cat $TMPFILE|wc -l) files with retention=$RET days"
        find $ARC_PATH/ -mtime +$RET |xargs ls -l >>$LOGFILE
        find $ARC_PATH/ -mtime +$RET |xargs rm 2>>LOGFILE
        if [ $? -ne 0 ]; then
                print_msg "rm encountered error..."
        fi      
else
        print_msg "No files need be deleted(retention=$RET)"
fi

[ -f $TMPFILE ] && rm $TMPFILE
[ -f $SQLFILE ] && rm $SQLFILE

[ -f $LOGFILE ] && log_rotate $LOGFILE
exit 0
