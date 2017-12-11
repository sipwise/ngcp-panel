set -x

customer_id=15
domain="voip.sipwise.local"
#domain="192.168.1.102"
#domain="10.15.17.210"
#domain="10.15.17.79"
#192.168.1.102

#jq

function get_sub_url {
    username=$1
    url=`curl -i -X GET -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/subscribers/?username='$username|grep -P '"href" : "/api/subscribers/\d+"'|sort -b -u|awk '{print $3}'|awk --field-separator '"' '{print $2}'`;
    echo -n $url;
}

function get_sub_id {
    username=$1
    id=`curl -i -X GET -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/subscribers/?username='$username|grep -P '"href" : "/api/subscribers/\d+"'|sort -b -u|awk '{print $3}'|awk --field-separator '"' '{print $2}'|awk --field-separator '/' '{print $4}'`;
    echo -n $id;
}


function get_dev_profile_id {
    name=$1
    id=`curl -i -X GET -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/pbxdeviceprofiles/?name='$name|grep -P '"href" : "/api/pbxdeviceprofiles/\d+"'|sort -b -u|awk '{print $3}'|awk --field-separator '"' '{print $2}'|awk --field-separator '/' '{print $4}'`;
    echo -n $id;
}

function get_suffix {
    number=$1
    if [ $number -le 9 ]; then
      suffix='000'$number
    else
      suffix='00'$number
    fi
    echo -n $suffix;
}
function get_suffix_num {
    number=$1
    if [ $number -le 9 ]; then
      suffix_num='200'$number
    else
      suffix_num='20'$number
    fi
    echo -n $suffix_num;
}



##====================        DELETE        ===========================
#
#for i in {1..48} ; do 
#
#suffix=$(get_suffix $i)
#suburl=$(get_sub_url 'sub_'$suffix);
#
#curl -i -X DELETE -H 'Connection: close'  -H 'Content-Type: application/json-patch+json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443'$suburl
#
#done
#return 1

##====================        GO!        ===========================

curl -i -X POST -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/subscribers/' --data-binary '{ "administrative" : false, "customer_id" : '$customer_id', "domain" : "'$domain'", "is_pbx_pilot" : true,  "primary_number" : { "ac" : "111", "cc" : "222", "sn" : "444" }, "status" : "active", "username" : "pilotSub", "password" : "pilotSub", "display_name" : "display pilotSub"}'


curl -i -X POST -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/subscribers/' --data-binary '{ "administrative" : false, "customer_id" : '$customer_id', "domain" : "'$domain'", "is_pbx_pilot" : true,  "primary_number" : { "ac" : "111", "cc" : "222", "sn" : "444" }, "status" : "active", "username" : "pilotSub", "password" : "pilotSub", "display_name" : "display pilotSub"}'

for i in {1..48} ; do 
  suffix_num=$(get_suffix_num $i)
  suffix=$(get_suffix $i)
  curl -i -X POST -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/subscribers/' --data-binary '{ "administrative" : false, "customer_id" : '$customer_id', "domain" : "'$domain'", "is_pbx_pilot" : false, "primary_number" : { "ac" : "1112", "cc" : "2222", "sn" : "4442" }, "status" : "active", "pbx_extension":"'$suffix_num'", "username" : "subsub_'$suffix'", "password" : "subsub_pwd_'$suffix'", "display_name" : "subsub '$suffix'"}'

done

for i in {1..48} ; do 

suffix=$(get_suffix $i)
id=$(get_sub_id 'sub_'$suffix)

curl -i -X PATCH -H 'Connection: close'  -H 'Content-Type: application/json-patch+json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/subscriberpreferences/'$id --data-binary '[{ "op": "add", "path" : "/music_on_hold", "value" : true}]'

done


for i in {1..3} ; do 
case $i in
1)
    name="Gr_VVX300_VVX400"
    member1_id=$(get_sub_id 'sub_001')
    member2_id=$(get_sub_id 'sub_011')
    ;;
2)
    name="Gr_VVX400_VVX500"
    member1_id=$(get_sub_id 'sub_011')
    member2_id=$(get_sub_id 'sub_021')
    ;;
3)
    name="Gr_VVX500_VVX300"
    member1_id=$(get_sub_id 'sub_022')
    member2_id=$(get_sub_id 'sub_002')
    ;;
esac


  curl -i -X POST -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/subscribers/' --data-binary '{"administrative":false,"customer_id":'$customer_id',"domain" : "'$domain'","email":null,"external_id":"'$name'","is_pbx_group":true,"is_pbx_pilot":false,"password":"group1_00'$i'","pbx_extension":"44'$i'","pbx_group_ids":[],"pbx_groupmember_ids":['$member1_id','$member2_id'],"pbx_hunt_policy":"serial","pbx_hunt_timeout":30,"primary_number":{"ac":"111","cc":"222","sn":"888"},"profile_id":null,"profile_set_id":null,"status":"active","username":"'$name'","webpassword":null,"webusername":"'$name'", "display_name" : "'$name'"}'

done




member1_id=$(get_sub_id 'sub_001')
member2_id=$(get_sub_id 'sub_002')
member3_id=$(get_sub_id 'sub_007')
member4_id=$(get_sub_id 'sub_008')
member5_id=$(get_sub_id 'sub_017')
member6_id=$(get_sub_id 'sub_027')
profile_id=$(get_dev_profile_id '%VVX300')

curl -i -H 'Connection: close' -H 'Content-Type: application/json' -k --user administrator:administrator -X POST 'https://127.0.0.1:1443/api/pbxdevices/' --data-binary '{ "customer_id" : '$customer_id', "profile_id":'$profile_id', "identifier" : "0004F2717AD9", "station_name" : "vvx300", "lines": [{"linerange":"Phone Keys","key_num": "0","type": "private", "subscriber_id":'$member1_id'},{"linerange":"Phone Keys","key_num": "1","type": "private", "subscriber_id":'$member2_id'},{"linerange":"Phone Keys","key_num": "2","type": "private", "subscriber_id":'$member3_id'},{"linerange":"Phone Keys","key_num": "3","type": "shared",  "subscriber_id":'$member4_id'},{"linerange":"Phone Keys","key_num": "4","type": "blf",     "subscriber_id":'$member5_id'},{"linerange":"Phone Keys","key_num": "5","type": "shared",  "subscriber_id":'$member6_id'}]}'

member1_id=$(get_sub_id 'sub_011')
member2_id=$(get_sub_id 'sub_012')
member3_id=$(get_sub_id 'sub_017')
member4_id=$(get_sub_id 'sub_018')
member5_id=$(get_sub_id 'sub_017')
member6_id=$(get_sub_id 'sub_008')
profile_id=$(get_dev_profile_id '%VVX400')

curl -i -H 'Connection: close' -H 'Content-Type: application/json' -k --user administrator:administrator -X POST 'https://127.0.0.1:1443/api/pbxdevices/' --data-binary '{ "customer_id" : '$customer_id', "profile_id":'$profile_id', "identifier" : "0004F2898DA5", "station_name" : "vvx400", "lines": [{"linerange":"Phone Keys","key_num": "0","type": "private", "subscriber_id":'$member1_id'},{"linerange":"Phone Keys","key_num": "1","type": "private", "subscriber_id":'$member2_id'},{"linerange":"Phone Keys","key_num": "2","type": "private", "subscriber_id":'$member3_id'},{"linerange":"Phone Keys","key_num": "3","type": "shared",  "subscriber_id":'$member4_id'},{"linerange":"Phone Keys","key_num": "4","type": "blf",     "subscriber_id":'$member5_id'},{"linerange":"Phone Keys","key_num": "5","type": "shared",  "subscriber_id":'$member6_id'}] }'

member1_id=$(get_sub_id 'sub_011')
member2_id=$(get_sub_id 'sub_012')
member3_id=$(get_sub_id 'sub_017')
member4_id=$(get_sub_id 'sub_018')
member5_id=$(get_sub_id 'sub_017')
member6_id=$(get_sub_id 'sub_008')
profile_id=$(get_dev_profile_id '%VVX400')

curl -i -H 'Connection: close' -H 'Content-Type: application/json' -k --user administrator:administrator -X POST 'https://127.0.0.1:1443/api/pbxdevices/' --data-binary '{ "customer_id" : '$customer_id', "profile_id":'$profile_id', "identifier" : "00:04:F2:89:8D:A5", "station_name" : "vvx410", "lines": [{"linerange":"Phone Keys","key_num": "0","type": "private", "subscriber_id":'$member1_id'},{"linerange":"Phone Keys","key_num": "1","type": "private", "subscriber_id":'$member2_id'},{"linerange":"Phone Keys","key_num": "2","type": "private", "subscriber_id":'$member3_id'},{"linerange":"Phone Keys","key_num": "3","type": "shared",  "subscriber_id":'$member4_id'},{"linerange":"Phone Keys","key_num": "4","type": "blf",     "subscriber_id":'$member5_id'},{"linerange":"Phone Keys","key_num": "5","type": "shared",  "subscriber_id":'$member6_id'}] }'

member1_id=$(get_sub_id 'sub_021')
member2_id=$(get_sub_id 'sub_022')
member3_id=$(get_sub_id 'sub_027')
member4_id=$(get_sub_id 'sub_028')
member5_id=$(get_sub_id 'sub_007')
member6_id=$(get_sub_id 'sub_018')
profile_id=$(get_dev_profile_id '%VVX500')

curl -i -H 'Connection: close' -H 'Content-Type: application/json' -k --user administrator:administrator -X POST 'https://127.0.0.1:1443/api/pbxdevices/' --data-binary '{ "customer_id" : '$customer_id', "profile_id":'$profile_id', "identifier" : "64167FA0F0FF", "station_name" : "vvx500", "lines": [{"linerange":"Phone Keys","key_num": "0","type": "private", "subscriber_id":'$member1_id'},{"linerange":"Phone Keys","key_num": "1","type": "private", "subscriber_id":'$member2_id'},{"linerange":"Phone Keys","key_num": "2","type": "private", "subscriber_id":'$member3_id'},{"linerange":"Phone Keys","key_num": "3","type": "shared",  "subscriber_id":'$member4_id'},{"linerange":"Phone Keys","key_num": "4","type": "blf",     "subscriber_id":'$member5_id'},{"linerange":"Phone Keys","key_num": "5","type": "shared",  "subscriber_id":'$member6_id'}] }'

member1_id=$(get_sub_id 'sub_031')
member2_id=$(get_sub_id 'sub_032')
member3_id=$(get_sub_id 'sub_033')
profile_id=$(get_dev_profile_id '%SIP-T23G')

curl -i -H 'Connection: close' -H 'Content-Type: application/json' -k --user administrator:administrator -X POST 'https://127.0.0.1:1443/api/pbxdevices/' --data-binary '{ "customer_id" : '$customer_id', "profile_id":'$profile_id', "identifier" : "001565A708C5", "station_name" : "Yealink 23G" , "lines": [{"linerange":"Full Keys","key_num": "0","type": "private", "subscriber_id":'$member1_id'},{"linerange":"Full Keys","key_num": "1","type": "private", "subscriber_id":'$member2_id'},{"linerange":"Full Keys","key_num": "2","type": "private", "subscriber_id":'$member3_id'} ] }'



#"lines": [
#{"linerange":"Phone Keys","key_num": "0","type": "private", "subscriber_id":'$member1_id'},
#{"linerange":"Phone Keys","key_num": "1","type": "private", "subscriber_id":'$member2_id'},
#{"linerange":"Phone Keys","key_num": "2","type": "private", "subscriber_id":'$member3_id'},
#{"linerange":"Phone Keys","key_num": "3","type": "shared",  "subscriber_id":'$member4_id'},
#{"linerange":"Phone Keys","key_num": "4","type": "blf",     "subscriber_id":'$member5_id'},
#{"linerange":"Phone Keys","key_num": "5","type": "shared",  "subscriber_id":'$member6_id'}]
#

#=============       OLD - pbx_extension and display_name update        ================

#for i in {1..48} ; do 
#
#suffix=$(get_suffix $i)
#suffix_num=$(get_suffix_num $i)
#suburl=$(get_sub_url 'sub_'$suffix)

#
#curl -i -X PATCH -H 'Connection: close'  -H 'Content-Type: application/json-patch+json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443'$suburl --data-binary '[{ "op": "replace", "path" : "/pbx_extension", "value" : "'$suffix_num'"}]'
#
#done
#
#for i in {1..48} ; do 
#
#suffix=$(get_suffix $i)
#suffix_num=$(get_suffix_num $i)
#suburl=$(get_sub_url 'sub_'$suffix)
#id=$(get_sub_id 'sub_'$suffix)

#curl -i -X PATCH -H 'Connection: close'  -H 'Content-Type: application/json-patch+json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/subscriberpreferences/'$id --data-binary '[{ "op": "add", "path" : "/display_name", "value" : "sub '$suffix_num'"}]'
#
#done
#

#for groupurl in `curl -X GET -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/subscribers/?username=%group%'|jq  '.["_links"] | .["ngcp:subscribers"] | .[] | .["href"]'|awk --field-separator '"' '{print $2}'`; do 
#
#id=`echo $groupurl|awk --field-separator '/' '{print $4}'`;
#
#groupname=`curl -X GET -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/'$groupurl|jq '.["webusername"]'|awk --field-separator '"' '{print $2}'`;
#
#curl -i -X PATCH -H 'Connection: close'  -H 'Content-Type: application/json-patch+json' -H 'Prefer: return=representation' --insecure --user administrator:administrator 'https://127.0.0.1:1443/api/subscriberpreferences/'$id --data-binary '[{ "op": "add", "path" : "/display_name", "value" : "'$groupname'"}]'
#
#done


#


#=================== CREATE DEVICES TO TEST CONFIGS =======================
#
#identifier=10
#for profile in 'Panasonic' 'Yealink' 'Cisco' 'Polycom'; do
#  profile_ids=$(get_dev_profile_id $profile'%')
#  echo $profile_ids
#  for profile_id in $profile_ids; do
#    echo '{ "customer_id" : '$customer_id', "profile_id":'$profile_id', "identifier" : "0000000000'$identifier'", "station_name" : "'$profile' '$profile_id'", "lines": [] }'
#    curl -i -H 'Connection: close' -H 'Content-Type: application/json' -k --user administrator:administrator -X POST 'https://127.0.0.1:1443/api/pbxdevices/' --data-binary '{ "customer_id" : '$customer_id', "profile_id":'$profile_id', "identifier" : "0000000000'$identifier'", "station_name" : "'$profile' '$profile_id'", "lines": [] }'
#    identifier=$(($identifier+1))
#  done
#done


