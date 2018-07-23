SELECT s.name,
    concat (
        "BEGIN:VCALENDAR\n",
        "PRODID:-//Mozilla.org/NONSGML Mozilla Calendar V1.1//EN\n",
        "VERSION:2.0\n\n",
        GROUP_CONCAT(concat(
            "BEGIN:VEVENT\n",
            "UID:","sipwise",p.id,"@sipwise",s.id,"\n",
            "SUMMARY:",s.name," event ",p.id,"\n",
            "DTSTART:",DATE_FORMAT(p.start,'%Y%m%dT%H%i%s'),"\n",
            "RRULE:",
                "FREQ=",p.freq,
                IFNULL(CONCAT(";COUNT=",     p.count),''),
                IFNULL(CONCAT(";UNTIL=",     DATE_FORMAT(p.until,'%Y%m%dT%H%i%s')),''),
                IFNULL(CONCAT(";INTERVAL=",  p.interval),''),
                IFNULL(CONCAT(";BYSECOND=",  p.bysecond),''),
                IFNULL(CONCAT(";BYMINUTE=",  p.byminute),''),
                IFNULL(CONCAT(";BYHOUR=",    p.byhour),''),
                IFNULL(CONCAT(";BYDAY=",     p.byday),''),
                IFNULL(CONCAT(";BYMONTHDAY=",p.bymonthday),''),
                IFNULL(CONCAT(";BYYEARDAY=", p.byyearday),''),
                IFNULL(CONCAT(";BYWEEKNO=",  p.byweekno),''),
                IFNULL(CONCAT(";BYMONTH=",   p.bymonth),''),
                IFNULL(CONCAT(";BYSETPOS=",  p.bysetpos),''),
                "\n",
            IFNULL(CONCAT("DESCRIPTION:",p.comment,"\n"),''),
            "END:VEVENT\n"
        )SEPARATOR '\n'),
        "END:VCALENDAR\n"
    ) AS ical
FROM provisioning.voip_time_sets s JOIN voip_periods p ON s.id = p.time_set_id
GROUP BY s.id
;