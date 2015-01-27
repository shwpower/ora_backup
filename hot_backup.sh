#!/bin/env ksh

#################################################################################
####                                                                            #
##  Program name: hot_backup                                                    # 
##                                                                              # 
##  Description: Oracle hot backup (archvelog mode)                             # 
##              Usage: archlog_purge -i <ORACLE_SID> -b <BACKUP PATH>
##                      Default Archive Log Retention: 2 days
##                                                                              # 
##              Require: run under oracle account
##                       Instance in archive log mode
##
#################################################################################
## Revision History                                                     #########
#################################################################################
# Wei           v1.0    19 Mar 2014             Creation
#
################################################################################

#################################Function Define ###############################
function Usage                                  
{                                       
        print "ERROR! Usage: ${0##*/} -i <ORACLE_SID> -b <BACKUP PATH> "                                       
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

function paramctl_backup {
        #### Function to backup pfile, password file and control file ####
        print_msg "Remove the older backup on ${BACK_DIR} "
        [ -f ${BACK_DIR}/controlfile.bak ] && rm -f ${BACK_DIR}/controlfile.bak
        [ -f ${BACK_DIR}/spfile${SID}.ora ] && rm -f ${BACK_DIR}/spfile${SID}.ora
        [ -f ${BACK_DIR}/orapw${SID} ] && rm -f ${BACK_DIR}/orapw${SID}

        print_msg "Backup Control file"
        sqlplus -s "/ as sysdba" << EOF
        alter database backup controlfile to '${BACK_DIR}/controlfile.bak';
        exit
EOF

        print_msg "Backup Server Parameter file"
        if [ -f ${ORACLE_HOME}/dbs/spfile${SID}.ora ] ;then
                print_msg "cp -p ${ORACLE_HOME}/dbs/spfile${SID}.ora ${BACK_DIR}"
                cp -p ${ORACLE_HOME}/dbs/spfile${SID}.ora ${BACK_DIR}
        else
                print_msg "File spfile${SID}.ora not found"
        fi

        print_msg "Backup Passwd file"
        if [ -f ${ORACLE_HOME}/dbs/orapw${SID} ]; then
                print_msg "cp -p ${ORACLE_HOME}/dbs/orapw${SID} ${BACK_DIR}"
                cp -p ${ORACLE_HOME}/dbs/orapw${SID} ${BACK_DIR}
        else
                print_msg "File orapw${SID}.ora not found"
        fi
}

function arch_backup {
        #### Function to backup archive log 
        print_msg "Remove the last backup archive log"
        [ ls ${BACK_DIR}/*.arc >/dev/null 2>&1 ] || rm -f ${BACK_DIR}/*.arc             
        
        print_msg "Switch lastest online log file to be archived"
        sqlplus -s "/as sysdba" >$TMPFILE  << EOF
        alter system switch logfile;
        show parameter log_archive_format;
        archive log list
        exit;
EOF
        ## Get the archive log path
        ARC_DIR=$(cat $TMPFILE|grep "Archive destination"|sed 's/Archive destination//g'|sed 's/ *//g')

        ## Get archive log list in $ARCH_RET days - to backup
        ARC_SEQ=`sqlplus -s "/ as sysdba" << EOF
        set heading off
        set feedback off
        select sequence# from v\\$loghist where first_time > sysdate-${ARCH_RET};
        exit;
EOF`
        if [ -d $ARC_DIR ]; then
                print_msg "Backup the archive log file within $ARCH_RET days"   
                for SEQ in $(echo $ARC_SEQ)
                do
                        if [ -f ${ARC_DIR}/*${SEQ}*.arc ]; then
                                print_msg "Copy the archive log file SEQ=${SEQ}"
                                cp -p ${ARC_DIR}/*${SEQ}*.arc ${BACK_DIR}/ 2>>$LOGFILE
                                [ $? -ne 0 ] && print_msg "Copy archive log failed ..."
                        else
                                print_msg "Archive log SEQ=${SEQ} not found"
                        fi      
                done
        fi
}

function dbfile_backup {
        #### Function to backup data file
        
        ## Create the db file backup script
        sqlplus "/ as sysdba" << EOF
                set echo off
                set feedback off
                set heading off
                set verify off
                set linesize 120
                set long 2000
                set pages 0
                col ts_name noprint
                col order_by noprint
                spool /tmp/copy_dbfile.sql
                select 'spool ${PP}/copy_dbfile_${SID}.log' from dual;
                select distinct 'host mkdir -p ${BACK_DIR}'||substr(name,1,instr(name,'/',-1)) 
        from v\$datafile;
                select name ts_name, 1 order_by, 'alter tablespace '||trim(name)||' begin backup;'
        from v\$tablespace where name<>'TEMP'
                union
                select t.name ts_name, 2 order_by, 'host cp '||trim(f.name)||' ${BACK_DIR}'||substr(f.name,1,instr(f.name,'/',-1))
        from v\$tablespace t, v\$datafile f where t.ts#=f.ts# 
                union 
                select name ts_name, 3 order_by, 'alter tablespace '||trim(name)||' end backup;'
        from v\$tablespace where name<>'TEMP'
                order by 1, 2;
                select 'spool off' from dual;
        spool off
        exit
EOF
        sed '/^SQL/d' /tmp/copy_dbfile.sql|sed '/^ /d' > $PP/copy_dbfile_${SID}.sql && rm /tmp/copy_dbfile.sql
        
        print_msg "Start to backup ${SID} database file (copy_dbfile_${SID}.sql)"
        sqlplus "/ as sysdba" << EOF
        @$PP/copy_dbfile_${SID}.sql
        exit
EOF
        print_msg "End to backup ${SID} database file"
}

############################## Function Define End  #############################

## Program PATH, Program Name
PP=$(dirname $0)
PN=$(basename "$0" ".sh")

LOGFILE=$PP/$PN.log
TMPFILE=$PP/$PN.tmp

######### Parameter define ################
while getopts i:b: next; do
        case $next in
                i)
                 SID=$OPTARG
                 ;;
                b)
                 BACK_DIR=$OPTARG
                 ;;
                *)
                 Usage
                 exit 1
                 ;;
        esac
done

## Check the SID & BACK_DIR
[[ -z $SID ]] && (print_msg "SID is null" ; Usage )&& exit 1
BACK_DIR=${BACK_DIR:-/backup}
[ ! -d $BACK_DIR ] && print_msg "Backup Folder $BACK_DIR not found" && exit 1

## Archive log backup retention(Unit: days)
ARCH_RET=1

## Get the variables for ORACLE DB environment
export ORACLE_SID=$SID
export ORACLE_HOME=$(/usr/local/bin/dbhome $ORACLE_SID)
alias sqlplus=$ORACLE_HOME/bin/sqlplus

[[ -z $(ps -ef|grep ora_smon_${SID}|grep -v grep) ]] && print_msg "Instance $SID not running" && exit 1
[[ -z $(ps -eaf|grep ora_arc|grep ${SID}|grep -v grep) ]] && print_msg "Instance $SID is not archivelog mode" && exit 1

print_msg "Hotbackup Started ..."
dbfile_backup 
paramctl_backup
arch_backup
print_msg "Finished Hotbackup "

[ -f $TMPFILE ] && rm $TMPFILE
exit 0
