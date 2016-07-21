DELIMITER $$

--
--  Create database and table 
--
CREATE DATABASE IF NOT EXISTS `eventdb`$$

-- 
-- Table Procedure need to be created under some data base;
--
USE eventdb$$


--
-- Create table with multiple cluster indexes under tokudb engine
--
CREATE TABLE IF NOT EXISTS `tb_events` (
  `id` BIGINT(20) UNSIGNED NOT NULL AUTO_INCREMENT,
  `gen_time` DATETIME NOT NULL DEFAULT '1972-01-01 00:00:00',
  `created_by` INT NOT NULL,
  `type`    INT NOT NULL,
  `details` BLOB NOT NULL,
  PRIMARY KEY (id, gen_time),
  INDEX idx_event_create_by_time (created_by, gen_time) clustering = yes,
  INDEX idx_event_type_time (type,gen_time) clustering = yes
) ENGINE=TOKUDB DEFAULT CHARSET=utf8mb4$$

--
-- MariaDB does not support partition with clustering index in one statement,
-- need to use anther statement to create it.
--
ALTER TABLE `tb_events` PARTITION BY RANGE(TO_DAYS(gen_time)) (
    PARTITION pbasic VALUES LESS THAN (0)
)$$

--
-- Check the table status: engine and partitioned, and so on.
--
SHOW TABLE STATUS LIKE 'tb_events'$$

--
-- Procedure to print message for debuging
--
CREATE PROCEDURE debug_msg(enabled INTEGER, msg VARCHAR(255))
BEGIN
  IF enabled THEN BEGIN
    select concat("** ", msg) AS '** DEBUG:';
  END; END IF;
END $$


--
-- Porcedure to create one partition by day, the partitoin must be added increased, otherwise you can not
-- create partition sucessfully but encounter error: 
--          "VALUES LESS THAN value must be strictly increasing for each partition".
--
CREATE PROCEDURE sp_create_partition (day_value datetime, db_name varchar(128), tb_name varchar(128))
BEGIN
  DECLARE par_name varchar(32);
  DECLARE par_value varchar(32);
  DECLARE _err int(1);
  DECLARE par_exist int(1);
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION, SQLWARNING, NOT FOUND SET _err = 1;
  START TRANSACTION;
    SET par_name = CONCAT('p', DATE_FORMAT(day_value, '%Y%m%d'));
    SELECT
      COUNT(1) INTO par_exist
    FROM information_schema.PARTITIONS
    WHERE TABLE_SCHEMA = db_name AND TABLE_NAME = tb_name AND PARTITION_NAME = par_name;
    -- call debug_msg(TRUE, (select concat_ws('',"par_exist:", par_exist)));
    IF (par_exist = 0) THEN
      SET par_value = DATE_FORMAT(day_value, '%Y-%m-%d');
      SET @alter_sql = CONCAT('alter table ', db_name,'.', tb_name, ' add PARTITION (PARTITION ', par_name, ' VALUES LESS THAN (TO_DAYS("', par_value, '")+1))');
    --  call debug_msg(TRUE, @alter_sql);
      PREPARE stmt1 FROM @alter_sql;
      EXECUTE stmt1;
    END IF;
  END
  $$

--
-- Procedure to delete one partition by one day
--
CREATE PROCEDURE sp_drop_partition (day_value datetime, db_name varchar(128), tb_name varchar(128))
BEGIN
  DECLARE str_day varchar(64);
  DECLARE _err int(1);
  DECLARE done int DEFAULT 0;
  DECLARE par_name varchar(64);
  DECLARE cur_partition_name CURSOR FOR
  SELECT
    partition_name
  FROM INFORMATION_SCHEMA.PARTITIONS
  WHERE TABLE_SCHEMA = db_name AND table_name = tb_name
  ORDER BY partition_ordinal_position;
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION, SQLWARNING, NOT FOUND SET _err = 1;
  DECLARE CONTINUE HANDLER FOR SQLSTATE '02000' SET done = 1;
  SET str_day = DATE_FORMAT(day_value, '%Y%m%d');
  OPEN cur_partition_name;
  REPEAT
    FETCH cur_partition_name INTO par_name;
    IF (str_day > SUBSTRING(par_name, 2)) THEN
      SET @alter_sql = CONCAT('alter table ', tb_name, ' drop PARTITION ', par_name);
      PREPARE stmt1 FROM @alter_sql;
      EXECUTE stmt1;
    END IF;
  UNTIL done END REPEAT;
  CLOSE cur_partition_name;
END
$$

--
-- Event to create necessary partition in advance, and rotate the oldest partition: last statement
-- will drop the partition 90 days' ago.
--
CREATE
EVENT event_auto_partition
ON SCHEDULE EVERY '1' DAY
STARTS '1972-01-01 00:00:00'
ON COMPLETION PRESERVE
DO
BEGIN
  CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL - 3 DAY), 'eventdb','tb_events');
  CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL - 2 DAY), 'eventdb','tb_events');
  CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL - 1 DAY), 'eventdb','tb_events');
  CALL sp_create_partition(NOW(), 'eventdb’,'tb_events');
  CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL 1 DAY), 'eventdb','tb_events');
  CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL 2 DAY), 'eventdb','tb_events');
  CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL 3 DAY), 'eventdb','tb_events');
  CALL sp_drop_partition(DATE_ADD(NOW(), INTERVAL - 90 DAY), 'eventdb','tb_events');

END
$$

--
-- Create partitions by manul, need to create from past to now
--
CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL - 3 DAY), 'eventdb','tb_events')$$
CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL - 2 DAY), 'eventdb','tb_events')$$
CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL - 1 DAY), 'eventdb','tb_events')$$
CALL sp_create_partition(NOW(), 'eventdb','tb_events')$$
CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL 1 DAY), 'eventdb','tb_events')$$
CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL 2 DAY), 'eventdb','tb_events')$$
CALL sp_create_partition(DATE_ADD(NOW(), INTERVAL 3 DAY), 'eventdb','tb_events')$$

DELIMITER ;

— Check the partition status, TABLE_SCHEMA: database name, TABLE_NAME: table name.
select TABLE_SCHEMA, TABLE_NAME,PARTITION_NAME from INFORMATION_SCHEMA.PARTITIONS where TABLE_SCHEMA='eventdb' and table_name='tb_events';  
