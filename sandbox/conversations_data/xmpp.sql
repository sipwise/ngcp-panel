SELECT ( "xmpp" ) AS `type`, ( `mam_id` ) AS `id`, ( `epoch` ) AS `timestamp`, ( `me`.`id` ) AS `field1`, ( `me`.`user` ) AS `field2`, ( `me`.`with` ) AS `field3`, ( `me`.`epoch` ) AS `field4`, ( "" ) AS `field5`, ( "" ) AS `field6`, ( "" ) AS `field7`, ( "" ) AS `field8`, ( "" ) AS `field9`, ( "" ) AS `field10`, ( "" ) AS `field11`, ( "" ) AS `field12`, ( "" ) AS `field13`, ( "" ) AS `field14`, ( "" ) AS `field15`, ( "" ) AS `field16`, ( "" ) AS `field17`, ( "" ) AS `field18`, ( "" ) AS `field19`, ( "" ) AS `field20`, ( "" ) AS `field21` 

FROM (

SELECT `me`.`id`, `me`.`username`, `me`.`domain_id`, `me`.`uuid`, `me`.`password`, `me`.`admin`, `me`.`account_id`, `me`.`webusername`, `me`.`webpassword`, `me`.`pbx_hunt_policy`, `me`.`pbx_hunt_timeout`, `me`.`pbx_extension`, `me`.`profile_set_id`, `me`.`profile_id`, `me`.`is_pbx_pilot`, `me`.`is_pbx_group`, `me`.`modify_timestamp`, `me`.`create_timestamp`, ( "out" ) AS `direction`, ( `sipwise_mam_user`.`id` ) AS `mam_id`, ( `sipwise_mam_user`.`username` ) AS `user`, ( `sipwise_mam_user`.`with` ) AS `with`, ( `sipwise_mam_user`.`epoch` ) AS `epoch` 

FROM `provisioning`.`voip_subscribers` `me`  
JOIN `provisioning`.`voip_domains` `domain` ON `domain`.`id` = `me`.`domain_id` 
INNER JOIN `prosody`.`sipwise_mam` `sipwise_mam_user` ON `sipwise_mam_user`.`username` = concat(me.username,"@",domain.domain) 

UNION ALL 

SELECT `me`.`id`, `me`.`username`, `me`.`domain_id`, `me`.`uuid`, `me`.`password`, `me`.`admin`, `me`.`account_id`, `me`.`webusername`, `me`.`webpassword`, `me`.`pbx_hunt_policy`, `me`.`pbx_hunt_timeout`, `me`.`pbx_extension`, `me`.`profile_set_id`, `me`.`profile_id`, `me`.`is_pbx_pilot`, `me`.`is_pbx_group`, `me`.`modify_timestamp`, `me`.`create_timestamp`, ( "in" ) AS `direction`, ( `sipwise_mam_with`.`id` ) AS `mam_id`, ( `sipwise_mam_with`.`username` ) AS `user`, ( `sipwise_mam_with`.`with` ) AS `with`, ( `sipwise_mam_with`.`epoch` ) AS `epoch` 

FROM `provisioning`.`voip_subscribers` `me` 
JOIN `provisioning`.`voip_domains` `domain` ON `domain`.`id` = `me`.`domain_id` 
INNER JOIN `prosody`.`sipwise_mam` `sipwise_mam_with` ON `sipwise_mam_with`.`with` = concat(me.username,"@",domain.domain)


) `me` 
WHERE ( `id` = '7' )