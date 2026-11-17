-- Run on SOURCE MySQL; never blindly apply changes in a production database.
SELECT VERSION() AS mysql_version;
SHOW GLOBAL VARIABLES LIKE 'server_id';
SHOW GLOBAL VARIABLES LIKE 'log_bin';
SHOW GLOBAL VARIABLES LIKE 'binlog_format';
SHOW GLOBAL VARIABLES LIKE 'binlog_row_image';
SHOW GLOBAL VARIABLES LIKE 'binlog_expire_logs_seconds';
SHOW DATABASES;
-- For ongoing AWS DMS CDC, require log_bin=ON, binlog_format=ROW,
-- binlog_row_image=FULL and adequate binary log retention.
-- DMS migration account needs SELECT + REPLICATION CLIENT + REPLICATION SLAVE.
-- The source schema/target mapping must be reviewed by the owner before loading.
