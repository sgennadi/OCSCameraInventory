# CentOS / MariaDB one-line search commands

All examples below connect directly to the OCS database `ocsweb` and prompt for the MySQL/MariaDB root password.

General form:

```bash
mysql -u root -p ocsweb -e "SQL QUERY"
```

## 1. Show all detected cameras

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,h.USERID AS UserName,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId,i.POINTTYPE AS Details FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' ORDER BY h.NAME,i.CAPTION;"
```

## 2. Count all detected cameras

```bash
mysql -u root -p ocsweb -e "SELECT COUNT(*) AS TotalCameras FROM inputs WHERE TYPE='OCS_CAMERA';"
```

## 3. Find Logitech C920 by USB VID/PID

Logitech C920 commonly uses `VID_046D` and `PID_082D`.

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,h.USERID AS UserName,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(CONCAT(COALESCE(i.INTERFACE,''),' ',COALESCE(i.DESCRIPTION,''))) LIKE '%VID_046D%PID_082D%' ORDER BY h.NAME;"
```

## 4. Find Logitech C920 by model name

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(i.CAPTION) LIKE '%C920%' ORDER BY h.NAME;"
```

## 5. Find all Logitech cameras

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,h.USERID AS UserName,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(CONCAT(COALESCE(i.MANUFACTURER,''),' ',COALESCE(i.CAPTION,''),' ',COALESCE(i.DESCRIPTION,''))) LIKE '%LOGITECH%' ORDER BY h.NAME,i.CAPTION;"
```

## 6. Find any camera by USB VID/PID

Replace `XXXX` with the USB vendor ID and `YYYY` with the product ID.

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,h.USERID AS UserName,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(CONCAT(COALESCE(i.INTERFACE,''),' ',COALESCE(i.DESCRIPTION,''))) LIKE '%VID_XXXX%PID_YYYY%' ORDER BY h.NAME;"
```

## 7. Search by part of camera/model name

Example: `BRIO`.

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(i.CAPTION) LIKE '%BRIO%' ORDER BY h.NAME;"
```

Replace `BRIO` with any model text, for example `C920`, `C930`, `MEETUP`, `POLY`, or `INTEGRATED`.

## 8. Count computers by camera model / VID-PID

```bash
mysql -u root -p ocsweb -e "SELECT i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,COUNT(DISTINCT i.HARDWARE_ID) AS Computers FROM inputs i WHERE i.TYPE='OCS_CAMERA' GROUP BY i.CAPTION,i.MANUFACTURER,i.INTERFACE ORDER BY Computers DESC,Camera;"
```

## 9. Find computers with more than one camera

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,COUNT(*) AS CameraCount FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' GROUP BY h.ID,h.NAME,h.IPADDR HAVING COUNT(*)>1 ORDER BY CameraCount DESC,h.NAME;"
```

## 10. Show cameras on one computer

Replace `COMPUTER-NAME` with the required computer name, for example `IT-ARTUMU`.

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(h.NAME)=UPPER('COMPUTER-NAME') ORDER BY i.CAPTION;"
```

Example for `IT-ARTUMU`:

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID,i.DESCRIPTION AS PnpDeviceId FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(h.NAME)=UPPER('IT-ARTUMU') ORDER BY i.CAPTION;"
```

## 11. Show all distinct camera VID/PID values

```bash
mysql -u root -p ocsweb -e "SELECT i.INTERFACE AS VID_PID,i.MANUFACTURER AS Manufacturer,i.CAPTION AS Camera,COUNT(DISTINCT i.HARDWARE_ID) AS Computers FROM inputs i WHERE i.TYPE='OCS_CAMERA' GROUP BY i.INTERFACE,i.MANUFACTURER,i.CAPTION ORDER BY Computers DESC,i.INTERFACE;"
```

## 12. Show cameras from one manufacturer

Replace `LOGITECH` with the required manufacturer text.

```bash
mysql -u root -p ocsweb -e "SELECT h.NAME AS Computer,h.IPADDR AS IP,i.CAPTION AS Camera,i.MANUFACTURER AS Manufacturer,i.INTERFACE AS VID_PID FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' AND UPPER(COALESCE(i.MANUFACTURER,'')) LIKE '%LOGITECH%' ORDER BY h.NAME,i.CAPTION;"
```

## 13. Show computers that have any camera

```bash
mysql -u root -p ocsweb -e "SELECT DISTINCT h.NAME AS Computer,h.IPADDR AS IP FROM inputs i JOIN hardware h ON h.ID=i.HARDWARE_ID WHERE i.TYPE='OCS_CAMERA' ORDER BY h.NAME;"
```

## 14. Count computers that have at least one camera

```bash
mysql -u root -p ocsweb -e "SELECT COUNT(DISTINCT i.HARDWARE_ID) AS ComputersWithCamera FROM inputs i WHERE i.TYPE='OCS_CAMERA';"
```

# Optional camera history

Install the history tables/procedure/event from the repository file:

```bash
mysql -u root -p ocsweb < camera-history.sql
```

Enable the MariaDB/MySQL event scheduler and verify it:

```bash
mysql -u root -p -e "SET GLOBAL event_scheduler=ON; SHOW VARIABLES LIKE 'event_scheduler';"
```

## 15. Show all camera history

```bash
mysql -u root -p ocsweb -e "SELECT EVENT_TIME,EVENT_TYPE,COMPUTER,IP,OLD_CAMERA,OLD_VID_PID,NEW_CAMERA,NEW_VID_PID FROM ocs_camera_history_readable ORDER BY EVENT_TIME DESC;"
```

## 16. Show camera replacements only

```bash
mysql -u root -p ocsweb -e "SELECT EVENT_TIME,COMPUTER,OLD_CAMERA,OLD_VID_PID,NEW_CAMERA,NEW_VID_PID FROM ocs_camera_history_readable WHERE EVENT_TYPE='REPLACED' ORDER BY EVENT_TIME DESC;"
```

## 17. Show camera additions only

```bash
mysql -u root -p ocsweb -e "SELECT EVENT_TIME,COMPUTER,NEW_CAMERA,NEW_MANUFACTURER,NEW_VID_PID FROM ocs_camera_history_readable WHERE EVENT_TYPE='ADDED' ORDER BY EVENT_TIME DESC;"
```

## 18. Show camera removals only

```bash
mysql -u root -p ocsweb -e "SELECT EVENT_TIME,COMPUTER,OLD_CAMERA,OLD_MANUFACTURER,OLD_VID_PID FROM ocs_camera_history_readable WHERE EVENT_TYPE='REMOVED' ORDER BY EVENT_TIME DESC;"
```

## 19. Show history for one computer

Replace `COMPUTER-NAME` with the required computer name.

```bash
mysql -u root -p ocsweb -e "SELECT EVENT_TIME,EVENT_TYPE,COMPUTER,OLD_CAMERA,OLD_VID_PID,NEW_CAMERA,NEW_VID_PID FROM ocs_camera_history_readable WHERE UPPER(COMPUTER)=UPPER('COMPUTER-NAME') ORDER BY EVENT_TIME DESC;"
```

Example for `IT-ARTUMU`:

```bash
mysql -u root -p ocsweb -e "SELECT EVENT_TIME,EVENT_TYPE,COMPUTER,OLD_CAMERA,OLD_VID_PID,NEW_CAMERA,NEW_VID_PID FROM ocs_camera_history_readable WHERE UPPER(COMPUTER)=UPPER('IT-ARTUMU') ORDER BY EVENT_TIME DESC;"
```

## 20. Show the current history snapshot

```bash
mysql -u root -p ocsweb -e "SELECT COMPUTER,IP,CAMERA,MANUFACTURER,VID_PID,FIRST_SEEN,LAST_SEEN FROM ocs_camera_history_state ORDER BY COMPUTER,CAMERA;"
```

## 21. Run history refresh manually now

```bash
mysql -u root -p ocsweb -e "CALL refresh_ocs_camera_history();"
```

## 22. Check the automatic history event

```bash
mysql -u root -p ocsweb -e "SHOW EVENTS LIKE 'ev_ocs_camera_history_refresh';"
```

All commands are intentionally written as a single shell line so they can be pasted directly into a CentOS terminal.