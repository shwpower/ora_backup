#!/bin/ksh


# SCRIPT:       expdp_fulldb_bkp_cron
# AUTHOR:       Shen Wei
# DATE:         Jun 09 2014
# REV:          1.0

# PLATFORM:     Linux/AIX/Solaris (Not platform dependent)
#
# REQUIREMENTS: Oracle database 9i/10g/11g/12c  is installed
#               expdp commnad is required
#               It run under oracle user (Oracle database owner)
#
#
# PURPOSE: The script is backup multi Oracle database fully by expdp
#               DB information from configure fiel(default: oradb.conf)
#
#
# REV LIST:
#        DATE: Jun  09 2014
#        BY:   Wei
#        MODIFICATION: Creation

#
# set -n   # Uncomment to check script syntax, without execution.
#          # NOTE: Do not forget to put the # comment back in or
#          #       the shell script will never execute!
# set -x   # Uncomment to debug this shell script
#

PROGRAM_NAME=$(basename $0)
PROGRAM_PATH=$(dirname $0)
PROGRAM_VERSION=1.0
HOST=$(hostname)
BKPDIR=$PROGRAM_PATH

LOGFILE=$PROGRAM_PATH/${PROGRAM_NAME}.${HOST}.log
MAILFILE=$PROGRAM_PATH/${PROGRAM_NAME}.${HOST}.mail
MAIL_SENDER="$PROGRAM_NAME@××××××.com"
PROGRAM_ADMIN_MAIL="wei.w.shen@××××××.com"
BKP_TYPE="expdp"

##########################################################
#              DEFINE FUNCTIONS HERE
##########################################################
############################
function print_usage
{
        # Function to print script usage
        echo "Usage:"
        #echo "  $PROGRAM_NAME"
        echo "  $PROGRAM_NAME -s <Oracle SID>"
        echo "  $PROGRAM_NAME -s <Oracle SID> -f <Oracle Config File>"
        echo "  $PROGRAM_NAME -v"
        echo "  $PROGRAM_NAME -h"
}
############################
function print_version
{
        #### Function to print script's version
        echo "$1 v$2"
}
############################
function print_help
{
        # Function to print help messages
        print_version $PROGRAM_NAME $PROGRAM_VERSION
        echo ""
        print_usage
        echo ""
        echo "Oracle expdp backup cronjob for all platform Unix/Linux System"
        echo ""
        echo " -s <Oracle SID>"
        echo ""
        echo " -f <Oracle Config File>"
        echo "  File includes SID ORACLE_HOME User Password Direcotory_name Mail_receiver "
        echo "  The default : oradb.conf"
        echo ""
}

############################
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

############################
function pre_status
{
        # Judge the previous cronjob running is existed
        ## The below is not support Solaris platform
        # Add "grep -v "sh -c"" for cron on solaris system
        STATUS=$(ps -eaf|grep $PROGRAM_NAME|grep -v grep |grep -v $$|grep -v "sh -c"|wc -l)
        if [ $STATUS -ge 1 ]
        then
                print_msg "Program previous $PROGRAM_NAME is running -- " > $MAILFILE
                echo -e "\n" >>$MAILFILE
                ps -eaf|grep $PROGRAM_NAME|grep -v grep >> $MAILFILE
                #cat $MAILFILE |mailx -r $MAIL_SENDER -s "Please stop the previous $PROGRAM_NAME before this time running" $PROGRAM_ADMIN_MAIL
                send_mail $MAILFILE $MAIL_SENDER "Please stop the previous $PROGRAM_NAME before this time running" $PROGRAM_ADMIN_MAIL
                print_msg "Exit..."

                rm $MAILFILE
                exit
        fi
}
############################
function send_mail
{
        # Send the mail , get mail related content by variables
        # $1 - mail contents file
        # $2 - mail sender
        # $3 - mail subjects
        # $4 - mail receiver

        if [ $# -eq 4 ] 
        then
                cat $1|mailx -r $2 -s "$3 at $(date '+%Y/%m/%d %H:%M:%S') on $HOST" "$4"                
                if [ $? -ne 0 ]
                then
                        print_msg "function send_mail executing error."
                        exit 1
                fi
        else
                print_msg "Wrong prameter with send_mail"
                exit 1
        fi
}

##########################################################
#               BEGINNING OF MAIN
##########################################################
while getopts f:s:hv next; do
        case $next in
                f)
                 CFGFILE=$OPTARG
                 ;;
                s)
                 SID=$OPTARG
                 ;;
                h)
                 print_help
                 exit
                 ;;
                v)
                 print_version $PROGRAM_NAME $PROGRAM_VERSION
                 exit
                 ;;
                *)
                 print_usage
                 exit
                 ;;
        esac
done

CFGFILE=$PROGRAM_PATH/${CFGFILE:-oradb.conf}
if [ "$SID" == "" ]; then
        print_msg "No SID provided"     
        print_usage
        exit
fi

if [ ! -f $CFGFILE ]; then
        echo "Could not find the Oracle DB Configure File" > $MAILFILE
        echo "$CFGFILE" >> $MAILFILE
        send_mail $MAILFILE $MAIL_SENDER "Error while running $PROGRAM_NAME" $PROGRAM_ADMIN_MAIL
        exit 
fi

STATUS=$(cat $CFGFILE |grep ^$SID |grep -v ^#|wc -l)
if [ $STATUS  == "1" ]; then
        SID=$(cat $CFGFILE|grep ^$SID|grep -v ^#|awk '{print $1}')
        ORACLE_HOME=$(cat $CFGFILE|grep ^$SID|grep -v ^#|awk '{print $2}')
        USR=$(cat $CFGFILE|grep ^$SID|grep -v ^#|awk '{print $3}')
        PASSWD=$(cat $CFGFILE|grep ^$SID|grep -v ^#|awk '{print $4}')
        DIR=$(cat $CFGFILE|grep ^$SID|grep -v ^#|awk '{print $5}')
        MAIL_RCV=$(cat $CFGFILE|grep ^$SID|grep -v ^#|awk '{print $6}')
        
        print_msg "Start to Backup the $DB (under $ORACLE_HOME)"
        if [ ! -x $ORACLE_HOME/bin/$BKP_TYPE ] ;then
                echo "Could not find the $BKP_TYPE" > $MAILFILE
                echo "$ORACLE_HOME/bin/$BKP_TYPE" >> $MAILFILE
                send_mail $MAILFILE $MAIL_SENDER "Error while running $PROGRAM_NAME" $PROGRAM_ADMIN_MAIL
        else
                export ORACLE_SID=$SID
                DUMPFILE=$HOST.$SID.$(date '+%s').dmp
                DUMPLOG=$HOST.$SID.$(date '+%s').log
                STIME=$(date '+%D %T')
                print_msg "Executing $ORACLE_HOME/bin/$BKP_TYPE $USR/***** directory=$DIR dumpfile=$DUMPFILE logfile=$DUMPLOG full=y"
                $ORACLE_HOME/bin/$BKP_TYPE $USR/$PASSWD directory=$DIR dumpfile=$DUMPFILE logfile=$DUMPLOG full=y
                #ETIME=$(date '+%D %T')
                if [ $? -ne 0 ]; then
                        print_msg "Error while executing $ORACLE_HOME/bin/$BKP_TYPE"
                        echo "Oracle backup Error, Please check $LOGFILE" > $MAILFILE
                        echo "$LOGFILE" >> $MAILFILE
                        send_mail $MAILFILE $MAIL_SENDER "Error while running $PROGRAM_NAME" $MAIL_RCV                  
                else
                        ETIME=$(date '+%D %T')
                        print_msg "End to execute $ORACLE_HOME/bin/$BKP_TYPE"
                        print_msg "$(ls -l $BKPDIR/$HOST.$SID-$(date '+%s').dmp) "
                        print_msg "Successfully backup $SID"
                        echo "The below is last dump backup file (Time from $STIME to $ETIME) ..."  >$MAILFILE
                        ls -l $BKPDIR/$HOST.$SID-`date +'%s'`.dmp >> $MAILFILE
                        echo "" >>$MAILFILE
                        #echo "All backup contents" >>$MAILFILE
                        #ls -l $BKPDIR/$SID/ >>$MAILFILE
                        send_mail $MAILFILE $MAIL_SENDER "$SID PGDB backup($BKP_TYPE) finished" $MAIL_RCV
                fi              
        fi
else
        print_msg "Wrong Oracle DB Configure file"
        echo "No configuration for $SID" >$MAILFILE
        cat $CFGFILE |grep $SID |grep -v ^# >>$MAILFILE
        send_mail $MAILFILE $MAIL_SENDER "Error while running $PROGRAM_NAME" $PROGRAM_ADMIN_MAIL
fi

[ -f $MAILFILE ] && rm $MAILFILE
