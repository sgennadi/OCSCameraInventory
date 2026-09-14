-- All cameras
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
JOIN hardware h
    ON h.ID = i.HARDWARE_ID
WHERE i.TYPE = 'OCS_CAMERA'
ORDER BY h.NAME, i.CAPTION;

-- Logitech C920 = USB VID 046D, PID 082D
SELECT
    h.NAME AS Computer,
    h.IPADDR AS IP,
    h.USERID AS UserName,
    i.CAPTION AS Camera,
    i.MANUFACTURER AS Manufacturer,
    i.INTERFACE AS VID_PID,
    i.DESCRIPTION AS PnpDeviceId
FROM inputs i
JOIN hardware h
    ON h.ID = i.HARDWARE_ID
WHERE i.TYPE = 'OCS_CAMERA'
  AND UPPER(
      CONCAT(
          COALESCE(i.INTERFACE,''),
          ' ',
          COALESCE(i.DESCRIPTION,'')
      )
  ) LIKE '%VID_046D%PID_082D%'
ORDER BY h.NAME;
