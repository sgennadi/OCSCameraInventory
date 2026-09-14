-- ============================================================
-- OCSCameraInventory-Universal
-- MariaDB/MySQL examples
-- Camera records are stored in inputs with TYPE='OCS_CAMERA'
-- ============================================================

-- 1. All detected cameras
SELECT
    h.NAME AS Computer,
    h.IPADDR AS IP,
    h.USERID AS UserName,
    i.CAPTION AS Camera,
    i.MANUFACTURER AS Manufacturer,
    i.INTERFACE AS VID_PID,
    i.DESCRIPTION AS PnpDeviceId,
    i.POINTTYPE AS Details
FROM inputs i
JOIN hardware h ON h.ID = i.HARDWARE_ID
WHERE i.TYPE = 'OCS_CAMERA'
ORDER BY h.NAME, i.CAPTION;


-- 2. Logitech C920 by USB VID/PID
-- Logitech VID = 046D
-- C920 PID    = 082D
SELECT
    h.NAME AS Computer,
    h.IPADDR AS IP,
    h.USERID AS UserName,
    i.CAPTION AS Camera,
    i.MANUFACTURER AS Manufacturer,
    i.INTERFACE AS VID_PID,
    i.DESCRIPTION AS PnpDeviceId
FROM inputs i
JOIN hardware h ON h.ID = i.HARDWARE_ID
WHERE i.TYPE = 'OCS_CAMERA'
  AND UPPER(CONCAT(
        COALESCE(i.INTERFACE,''),
        ' ',
        COALESCE(i.DESCRIPTION,'')
      )) LIKE '%VID_046D%PID_082D%'
ORDER BY h.NAME;


-- 3. Logitech C920 by model/friendly name
SELECT
    h.NAME AS Computer,
    h.IPADDR AS IP,
    h.USERID AS UserName,
    i.CAPTION,
    i.MANUFACTURER,
    i.INTERFACE,
    i.DESCRIPTION
FROM inputs i
JOIN hardware h ON h.ID = i.HARDWARE_ID
WHERE i.TYPE = 'OCS_CAMERA'
  AND UPPER(i.CAPTION) LIKE '%C920%'
ORDER BY h.NAME;


-- 4. All Logitech cameras
SELECT
    h.NAME AS Computer,
    h.IPADDR AS IP,
    h.USERID AS UserName,
    i.CAPTION,
    i.MANUFACTURER,
    i.INTERFACE,
    i.DESCRIPTION
FROM inputs i
JOIN hardware h ON h.ID = i.HARDWARE_ID
WHERE i.TYPE = 'OCS_CAMERA'
  AND UPPER(CONCAT(
        COALESCE(i.MANUFACTURER,''),
        ' ',
        COALESCE(i.CAPTION,''),
        ' ',
        COALESCE(i.DESCRIPTION,'')
      )) LIKE '%LOGITECH%'
ORDER BY h.NAME, i.CAPTION;


-- 5. Any camera by USB VID/PID
-- Replace XXXX and YYYY.
SELECT
    h.NAME AS Computer,
    h.IPADDR AS IP,
    h.USERID AS UserName,
    i.CAPTION,
    i.MANUFACTURER,
    i.INTERFACE,
    i.DESCRIPTION
FROM inputs i
JOIN hardware h ON h.ID = i.HARDWARE_ID
WHERE i.TYPE = 'OCS_CAMERA'
  AND UPPER(CONCAT(
        COALESCE(i.INTERFACE,''),
        ' ',
        COALESCE(i.DESCRIPTION,'')
      )) LIKE '%VID_XXXX%PID_YYYY%'
ORDER BY h.NAME;


-- 6. Search by part of the camera/model name
-- Example: BRIO
SELECT
    h.NAME AS Computer,
    h.IPADDR AS IP,
    i.CAPTION,
    i.MANUFACTURER,
    i.INTERFACE
FROM inputs i
JOIN hardware h ON h.ID = i.HARDWARE_ID
WHERE i.TYPE = 'OCS_CAMERA'
  AND UPPER(i.CAPTION) LIKE '%BRIO%'
ORDER BY h.NAME;


-- 7. Count computers by camera model / VID-PID
SELECT
    i.CAPTION AS Camera,
    i.MANUFACTURER AS Manufacturer,
    i.INTERFACE AS VID_PID,
    COUNT(DISTINCT i.HARDWARE_ID) AS Computers
FROM inputs i
WHERE i.TYPE = 'OCS_CAMERA'
GROUP BY
    i.CAPTION,
    i.MANUFACTURER,
    i.INTERFACE
ORDER BY Computers DESC, Camera;


-- 8. Computers with more than one detected camera
SELECT
    h.NAME AS Computer,
    h.IPADDR AS IP,
    COUNT(*) AS CameraCount
FROM inputs i
JOIN hardware h ON h.ID = i.HARDWARE_ID
WHERE i.TYPE = 'OCS_CAMERA'
GROUP BY h.ID, h.NAME, h.IPADDR
HAVING COUNT(*) > 1
ORDER BY CameraCount DESC, h.NAME;


-- 9. Cameras on one computer
-- Replace COMPUTER-NAME.
SELECT
    h.NAME AS Computer,
    h.IPADDR AS IP,
    i.CAPTION,
    i.MANUFACTURER,
    i.INTERFACE,
    i.DESCRIPTION
FROM inputs i
JOIN hardware h ON h.ID = i.HARDWARE_ID
WHERE i.TYPE = 'OCS_CAMERA'
  AND UPPER(h.NAME) = UPPER('COMPUTER-NAME')
ORDER BY i.CAPTION;


-- 10. Distinct USB camera VID/PID values in the estate
SELECT
    i.INTERFACE AS VID_PID,
    i.MANUFACTURER,
    i.CAPTION,
    COUNT(DISTINCT i.HARDWARE_ID) AS Computers
FROM inputs i
WHERE i.TYPE = 'OCS_CAMERA'
GROUP BY
    i.INTERFACE,
    i.MANUFACTURER,
    i.CAPTION
ORDER BY Computers DESC, i.INTERFACE;
