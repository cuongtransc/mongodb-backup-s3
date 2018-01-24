#!/bin/bash

BACKUP_SCRIPT=/usr/local/bin/backup.sh
RESTORE_SCRIPT=/usr/local/bin/restore.sh
LIST_SCRIPT=/usr/local/bin/listbackups.sh

function create_backup_script() {
    # echo "=> Creating backup script"

    rm -f $BACKUP_SCRIPT
    cat <<EOF >> $BACKUP_SCRIPT
#!/bin/bash
TIMESTAMP=\`/bin/date +"%Y%m%dT%H%M%S"\`
BACKUP_NAME=\${TIMESTAMP}.dump.gz
S3BACKUP=${S3PATH}\${BACKUP_NAME}
S3LATEST=${S3PATH}latest.dump.gz

echo "=> Backup started"
if mongodump --host ${MONGODB_HOST} --port ${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} --archive=\${BACKUP_NAME} --gzip ${EXTRA_OPTS} && aws s3 cp \${BACKUP_NAME} \${S3BACKUP} && aws s3 cp \${S3BACKUP} \${S3LATEST} && rm \${BACKUP_NAME} ;then
    echo "   > Backup succeeded"
else
    echo "   > Backup failed"
fi
echo "=> Done"
EOF
    chmod +x $BACKUP_SCRIPT
    # echo "=> Backup script created"
}

function create_restore_script() {
    # echo "=> Creating restore script"

    rm -f $RESTORE_SCRIPT
    cat <<EOF >> $RESTORE_SCRIPT
#!/bin/bash
if [[( -n "\${1}" )]];then
    RESTORE_ME=\${1}.dump.gz
else
    RESTORE_ME=latest.dump.gz
fi
S3RESTORE=${S3PATH}\${RESTORE_ME}
echo "=> Restore database from \${RESTORE_ME}"
if aws s3 cp \${S3RESTORE} \${RESTORE_ME} && mongorestore --host ${MONGODB_HOST} --port ${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} --drop --archive=\${RESTORE_ME} --gzip && rm \${RESTORE_ME}; then
    echo "   Restore succeeded"
else
    echo "   Restore failed"
fi
echo "=> Done"
EOF
    chmod +x $RESTORE_SCRIPT
    # echo "=> Restore script created"
}

function create_list_script() {
    # echo "=> Creating list script"

    rm -f $LIST_SCRIPT
    cat <<EOF >> $LIST_SCRIPT
#!/bin/bash
aws s3 ls ${S3PATH}
EOF
    chmod +x $LIST_SCRIPT
    # echo "=> List script created"
}

MONGODB_HOST=${MONGODB_PORT_27017_TCP_ADDR:-${MONGODB_HOST}}
MONGODB_HOST=${MONGODB_PORT_1_27017_TCP_ADDR:-${MONGODB_HOST}}

MONGODB_PORT=${MONGODB_PORT_27017_TCP_PORT:-${MONGODB_PORT}}
MONGODB_PORT=${MONGODB_PORT_1_27017_TCP_PORT:-${MONGODB_PORT}}

MONGODB_USER=${MONGODB_USER:-${MONGODB_ENV_MONGODB_USER}}
MONGODB_PASS=${MONGODB_PASS:-${MONGODB_ENV_MONGODB_PASS}}

S3PATH="s3://$BUCKET/$BACKUP_FOLDER"

[[ ( -z "${MONGODB_USER}" ) && ( -n "${MONGODB_PASS}" ) ]] && MONGODB_USER='admin'

[[ ( -n "${MONGODB_USER}" ) ]] && USER_STR=" --username ${MONGODB_USER}"
[[ ( -n "${MONGODB_PASS}" ) ]] && PASS_STR=" --password ${MONGODB_PASS}"
[[ ( -n "${MONGODB_DB}" ) ]] && DB_STR=" --db ${MONGODB_DB}"

# Export AWS Credentials into env file for cron job
printenv | sed 's/^\([a-zA-Z0-9_]*\)=\(.*\)$/export \1="\2"/g' | grep -E "^export AWS" > /root/project_env.sh

# Create scripts
create_backup_script
create_restore_script
create_list_script

# Create log
touch /mongo_backup.log


if [ "$1" = 'CRON' ]; then
    if [ -n "${INIT_BACKUP}" ]; then
        echo "=> Create a backup on the startup"
        backup.sh
    fi

    if [ -n "${INIT_RESTORE}" ]; then
        echo "=> Restore store from lastest backup on startup"
        restore.sh
    fi

    if [ -z "${DISABLE_CRON}" ]; then
        echo "${CRON_TIME} . /root/project_env.sh; /backup.sh >> /mongo_backup.log 2>&1" > /crontab.conf
        crontab  /crontab.conf

        echo "=> Running cron job"
        cron && tail -f /mongo_backup.log
    fi

    exit 0
fi

exec "$@"
