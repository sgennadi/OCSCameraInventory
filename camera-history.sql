-- ============================================================
-- OCSCameraInventory-Universal
-- Camera history tracking for MariaDB/MySQL
--
-- Purpose:
--   Preserve camera add/remove/replace history even though the
--   standard OCS inputs table contains only the latest state.
--
-- Install:
--   mysql -u root -p ocsweb < camera-history.sql
--
-- Then make sure the MariaDB/MySQL event scheduler is ON:
--   mysql -u root -p -e "SET GLOBAL event_scheduler=ON;"
-- ============================================================

CREATE TABLE IF NOT EXISTS ocs_camera_history_state (
    HARDWARE_ID      INT NOT NULL,
    DEVICE_KEY       CHAR(64) NOT NULL,
    COMPUTER         VARCHAR(255) NOT NULL,
    IP               VARCHAR(255) NULL,
    CAMERA           VARCHAR(255) NULL,
    MANUFACTURER     VARCHAR(255) NULL,
    VID_PID          VARCHAR(255) NULL,
    PNP_DEVICE_ID    VARCHAR(255) NULL,
    DETAILS          VARCHAR(255) NULL,
    FIRST_SEEN       DATETIME NOT NULL,
    LAST_SEEN        DATETIME NOT NULL,
    PRIMARY KEY (HARDWARE_ID, DEVICE_KEY),
    KEY IDX_CAMERA_STATE_COMPUTER (COMPUTER),
    KEY IDX_CAMERA_STATE_LAST_SEEN (LAST_SEEN)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ocs_camera_history (
    ID                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    EVENT_TIME            DATETIME NOT NULL,
    EVENT_TYPE            VARCHAR(16) NOT NULL,
    HARDWARE_ID           INT NOT NULL,
    COMPUTER              VARCHAR(255) NOT NULL,
    IP                    VARCHAR(255) NULL,
    OLD_CAMERA            VARCHAR(255) NULL,
    OLD_MANUFACTURER      VARCHAR(255) NULL,
    OLD_VID_PID           VARCHAR(255) NULL,
    OLD_PNP_DEVICE_ID     VARCHAR(255) NULL,
    NEW_CAMERA            VARCHAR(255) NULL,
    NEW_MANUFACTURER      VARCHAR(255) NULL,
    NEW_VID_PID           VARCHAR(255) NULL,
    NEW_PNP_DEVICE_ID     VARCHAR(255) NULL,
    PRIMARY KEY (ID),
    KEY IDX_CAMERA_HISTORY_TIME (EVENT_TIME),
    KEY IDX_CAMERA_HISTORY_COMPUTER (COMPUTER),
    KEY IDX_CAMERA_HISTORY_TYPE (EVENT_TYPE),
    KEY IDX_CAMERA_HISTORY_HARDWARE (HARDWARE_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP PROCEDURE IF EXISTS refresh_ocs_camera_history;
DELIMITER $$

CREATE PROCEDURE refresh_ocs_camera_history()
BEGIN
    DECLARE v_now DATETIME;
    SET v_now = NOW();

    DROP TEMPORARY TABLE IF EXISTS tmp_camera_current;
    DROP TEMPORARY TABLE IF EXISTS tmp_camera_removed;
    DROP TEMPORARY TABLE IF EXISTS tmp_camera_added;
    DROP TEMPORARY TABLE IF EXISTS tmp_camera_replaced_hardware;

    CREATE TEMPORARY TABLE tmp_camera_current AS
    SELECT DISTINCT
        h.ID AS HARDWARE_ID,
        SHA2(CONCAT_WS('|',
            COALESCE(i.DESCRIPTION,''),
            COALESCE(i.INTERFACE,''),
            COALESCE(i.CAPTION,''),
            COALESCE(i.MANUFACTURER,'')
        ),256) AS DEVICE_KEY,
        h.NAME AS COMPUTER,
        h.IPADDR AS IP,
        i.CAPTION AS CAMERA,
        i.MANUFACTURER AS MANUFACTURER,
        i.INTERFACE AS VID_PID,
        i.DESCRIPTION AS PNP_DEVICE_ID,
        i.POINTTYPE AS DETAILS
    FROM inputs i
    JOIN hardware h ON h.ID = i.HARDWARE_ID
    WHERE i.TYPE = 'OCS_CAMERA';

    ALTER TABLE tmp_camera_current
        ADD PRIMARY KEY (HARDWARE_ID, DEVICE_KEY);

    CREATE TEMPORARY TABLE tmp_camera_removed AS
    SELECT s.*
    FROM ocs_camera_history_state s
    LEFT JOIN tmp_camera_current c
      ON c.HARDWARE_ID = s.HARDWARE_ID
     AND c.DEVICE_KEY = s.DEVICE_KEY
    WHERE c.HARDWARE_ID IS NULL;

    ALTER TABLE tmp_camera_removed
        ADD PRIMARY KEY (HARDWARE_ID, DEVICE_KEY);

    CREATE TEMPORARY TABLE tmp_camera_added AS
    SELECT c.*
    FROM tmp_camera_current c
    LEFT JOIN ocs_camera_history_state s
      ON s.HARDWARE_ID = c.HARDWARE_ID
     AND s.DEVICE_KEY = c.DEVICE_KEY
    WHERE s.HARDWARE_ID IS NULL;

    ALTER TABLE tmp_camera_added
        ADD PRIMARY KEY (HARDWARE_ID, DEVICE_KEY);

    -- A replacement is recorded when exactly one camera disappeared and
    -- exactly one camera appeared on the same computer between snapshots.
    -- More complex multi-camera changes are recorded as separate ADDED/REMOVED events.
    CREATE TEMPORARY TABLE tmp_camera_replaced_hardware AS
    SELECT r.HARDWARE_ID
    FROM (
        SELECT HARDWARE_ID, COUNT(*) AS CNT
        FROM tmp_camera_removed
        GROUP BY HARDWARE_ID
    ) r
    JOIN (
        SELECT HARDWARE_ID, COUNT(*) AS CNT
        FROM tmp_camera_added
        GROUP BY HARDWARE_ID
    ) a ON a.HARDWARE_ID = r.HARDWARE_ID
    WHERE r.CNT = 1
      AND a.CNT = 1;

    ALTER TABLE tmp_camera_replaced_hardware
        ADD PRIMARY KEY (HARDWARE_ID);

    INSERT INTO ocs_camera_history (
        EVENT_TIME, EVENT_TYPE, HARDWARE_ID, COMPUTER, IP,
        OLD_CAMERA, OLD_MANUFACTURER, OLD_VID_PID, OLD_PNP_DEVICE_ID,
        NEW_CAMERA, NEW_MANUFACTURER, NEW_VID_PID, NEW_PNP_DEVICE_ID
    )
    SELECT
        v_now,
        'REPLACED',
        r.HARDWARE_ID,
        COALESCE(a.COMPUTER, r.COMPUTER),
        COALESCE(a.IP, r.IP),
        r.CAMERA,
        r.MANUFACTURER,
        r.VID_PID,
        r.PNP_DEVICE_ID,
        a.CAMERA,
        a.MANUFACTURER,
        a.VID_PID,
        a.PNP_DEVICE_ID
    FROM tmp_camera_removed r
    JOIN tmp_camera_replaced_hardware x
      ON x.HARDWARE_ID = r.HARDWARE_ID
    JOIN tmp_camera_added a
      ON a.HARDWARE_ID = r.HARDWARE_ID;

    INSERT INTO ocs_camera_history (
        EVENT_TIME, EVENT_TYPE, HARDWARE_ID, COMPUTER, IP,
        OLD_CAMERA, OLD_MANUFACTURER, OLD_VID_PID, OLD_PNP_DEVICE_ID
    )
    SELECT
        v_now,
        'REMOVED',
        r.HARDWARE_ID,
        r.COMPUTER,
        r.IP,
        r.CAMERA,
        r.MANUFACTURER,
        r.VID_PID,
        r.PNP_DEVICE_ID
    FROM tmp_camera_removed r
    LEFT JOIN tmp_camera_replaced_hardware x
      ON x.HARDWARE_ID = r.HARDWARE_ID
    WHERE x.HARDWARE_ID IS NULL;

    INSERT INTO ocs_camera_history (
        EVENT_TIME, EVENT_TYPE, HARDWARE_ID, COMPUTER, IP,
        NEW_CAMERA, NEW_MANUFACTURER, NEW_VID_PID, NEW_PNP_DEVICE_ID
    )
    SELECT
        v_now,
        'ADDED',
        a.HARDWARE_ID,
        a.COMPUTER,
        a.IP,
        a.CAMERA,
        a.MANUFACTURER,
        a.VID_PID,
        a.PNP_DEVICE_ID
    FROM tmp_camera_added a
    LEFT JOIN tmp_camera_replaced_hardware x
      ON x.HARDWARE_ID = a.HARDWARE_ID
    WHERE x.HARDWARE_ID IS NULL;

    DELETE s
    FROM ocs_camera_history_state s
    JOIN tmp_camera_removed r
      ON r.HARDWARE_ID = s.HARDWARE_ID
     AND r.DEVICE_KEY = s.DEVICE_KEY;

    UPDATE ocs_camera_history_state s
    JOIN tmp_camera_current c
      ON c.HARDWARE_ID = s.HARDWARE_ID
     AND c.DEVICE_KEY = s.DEVICE_KEY
    SET
        s.COMPUTER = c.COMPUTER,
        s.IP = c.IP,
        s.CAMERA = c.CAMERA,
        s.MANUFACTURER = c.MANUFACTURER,
        s.VID_PID = c.VID_PID,
        s.PNP_DEVICE_ID = c.PNP_DEVICE_ID,
        s.DETAILS = c.DETAILS,
        s.LAST_SEEN = v_now;

    INSERT INTO ocs_camera_history_state (
        HARDWARE_ID, DEVICE_KEY, COMPUTER, IP, CAMERA, MANUFACTURER,
        VID_PID, PNP_DEVICE_ID, DETAILS, FIRST_SEEN, LAST_SEEN
    )
    SELECT
        c.HARDWARE_ID,
        c.DEVICE_KEY,
        c.COMPUTER,
        c.IP,
        c.CAMERA,
        c.MANUFACTURER,
        c.VID_PID,
        c.PNP_DEVICE_ID,
        c.DETAILS,
        v_now,
        v_now
    FROM tmp_camera_current c
    LEFT JOIN ocs_camera_history_state s
      ON s.HARDWARE_ID = c.HARDWARE_ID
     AND s.DEVICE_KEY = c.DEVICE_KEY
    WHERE s.HARDWARE_ID IS NULL;
END$$

DELIMITER ;

-- Capture the current state immediately. Existing cameras become initial ADDED events.
CALL refresh_ocs_camera_history();

-- Refresh history automatically every 5 minutes.
DROP EVENT IF EXISTS ev_ocs_camera_history_refresh;
CREATE EVENT ev_ocs_camera_history_refresh
    ON SCHEDULE EVERY 5 MINUTE
    STARTS CURRENT_TIMESTAMP + INTERVAL 5 MINUTE
    DO CALL refresh_ocs_camera_history();

-- Useful view for human-readable history.
CREATE OR REPLACE VIEW ocs_camera_history_readable AS
SELECT
    EVENT_TIME,
    EVENT_TYPE,
    COMPUTER,
    IP,
    OLD_CAMERA,
    OLD_MANUFACTURER,
    OLD_VID_PID,
    NEW_CAMERA,
    NEW_MANUFACTURER,
    NEW_VID_PID
FROM ocs_camera_history;
