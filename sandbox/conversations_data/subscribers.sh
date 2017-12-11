set -x

customer_id=69
amount=10
domain="192.168.1.118"
nameprefix=sipsub2
host=127.0.0.1
port=1443
login=administrator
password=administrator


function get_sub_url {
    username=$1
    url=`curl -X GET -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user $login:$password 'https://'$host':'$port'/api/subscribers/?username='$username|jq '.["_links"] | .["ngcp:subscribers"] | .["href"]'|sed -r 's/^"|"$//g'`;
    echo -n $url;
}

function get_sub_id {
    username=$1
    id=`curl -X GET -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user $login:$password 'https://'$host':'$port'/api/subscribers/?username='$username|jq '.["_embedded"] | .["ngcp:subscribers"] | .[] | .["id"]'`;
    echo -n $id;
}

function get_suffix {
    number=$1
    if [ $number -le 9 ]; then
      suffix='100'$number
    else
      suffix='10'$number
    fi
    echo -n $suffix;
}

function get_suffix_num {
    number=$1
    if [ $number -le 9 ]; then
      suffix_num='210'$number
    else
      suffix_num='21'$number
    fi
    echo -n $suffix_num;
}



##====================        DELETE        ===========================
#
#for i in $(seq 1 $amount) ; do 
#
#suffix=$(get_suffix $i)
#suburl=$(get_sub_url 'sub_'$suffix);
#
#curl -i -X DELETE -H 'Connection: close'  -H 'Content-Type: application/json-patch+json' -H 'Prefer: return=representation' --insecure --user $login:$password 'https://127.0.0.1:1443'$suburl
#
#done
#return 1

##====================        GO!        ===========================

#for i in $(seq 1 $amount) ; do 
#  suffix_num=$(get_suffix_num $i)
#  suffix=$(get_suffix $i)
#  curl -i -X POST -H 'Connection: close' -H 'Content-Type: application/json' -H 'Prefer: return=representation' --insecure --user $login:$password 'https://'$host':'$port'/api/subscribers/' --data-binary '{ "administrative" : false, "customer_id" : '$customer_id', "domain" : "'$domain'", "primary_number" : { "ac" : "1111", "cc" : "2222", "sn" : "4444'$i'" }, "status" : "active", "username" : "'$nameprefix'_'$suffix'", "password" : "'$nameprefix'_pwd_'$suffix'", "display_name" : "'$nameprefix' '$suffix'"}'
#
#done

for i in $(seq 1 $amount) ; do 

suffix=$(get_suffix $i)
id=$(get_sub_id $nameprefix'_'$suffix)

curl -i -X PATCH -H 'Connection: close'  -H 'Content-Type: application/json-patch+json' -H 'Prefer: return=representation' --insecure --user $login:$password 'https://'$host':'$port'/api/subscriberpreferences/'$id --data-binary '[{ "op": "add", "path" : "/allow_out_foreign_domain", "value" : true}]'

done


