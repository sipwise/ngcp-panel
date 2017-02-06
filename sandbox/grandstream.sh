key='zL4rwLSBr5Pz5us'
time=$(curl -s 'fm.grandstream.com/api/provision' | jq '.time') 
request='{"cid":"cid","method":"listProfile","params":{}}'
str=$request$time
sig=$(echo -n $str | openssl sha1 -hmac $key -binary|xxd -p)
response=$(curl -H "Content-Type: application/json" -X POST -d $request "http://fm.grandstream.com/api/provision?time=${time}&sig=${sig}")

key='zL4rwLSBr5Pz5us'
time=$(curl -s 'fm.grandstream.com/api/provision' | jq '.time') 
echo "time=$time;"
request='{"cid":"2018","method":"listProfile","params":{}}'
echo "request=$request;"
str=$request$time
echo "str=$str;"
sig=$(echo -n $str | openssl sha1 -hmac $key -binary|xxd -p)
echo "sig=$sig;"
curl -H "Content-Type: application/json" -X POST -d $request "http://fm.grandstream.com/api/provision?time=${time}&sig=${sig}"



=============================================================



key='zL4rwLSBr5Pz5us'
time='1486348900' 
echo "time=$time;"
request='{"cid":"2018","method":"listProfile","params":{}}'
echo "request=$request;"
str=$request$time
echo "str=$str;"
sig=$(echo -n $str | openssl sha1 -hmac $key -binary|xxd -p)
echo "sig=$sig;"
curl -H "Content-Type: application/json" -X POST -d $request "http://fm.grandstream.com/api/provision?time=${time}&sig=${sig}"


key='zL4rwLSBr5Pz5us'
time=$(date '+%s') 
echo "time=$time;"
request='{"cid":"2018","method":"listProfile","params":{}}'
echo "request=$request;"
str=$request$time
echo "str=$str;"
sig=$(echo -n $str | openssl sha1 -hmac $key -binary|xxd -p)
echo "sig=$sig;"
curl -H "Content-Type: application/json" -X POST -d $request "http://fm.grandstream.com/api/provision?time=${time}&sig=${sig}"


key='zL4rwLSBr5Pz5us'
time=$(curl -s 'fm.grandstream.com/api/provision' | jq '.time') 
echo "time=$time;"
request='{"cid":"2018","method":"redirectDefault","params":{"macs":["00000000001","00000000002"]}}'
echo "request=$request;"
str=$request$time
echo "str=$str;"
sig=$(echo -n $str | openssl sha1 -hmac $key -binary|xxd -p)
echo "sig=$sig;"
curl -H "Content-Type: application/json" -X POST -d $request "http://fm.grandstream.com/api/provision?time=${time}&sig=${sig}"

key='zL4rwLSBr5Pz5us'
time=$(curl -s 'fm.grandstream.com/api/provision' | jq '.time') 
echo "time=$time;"
request='{"cid":"2018","method":"listDevicesConfig","params":{"macs":["00000000001","00000000002"]}}'
echo "request=$request;"
str=$request$time
echo "str=$str;"
sig=$(echo -n $str | openssl sha1 -hmac $key -binary|xxd -p)
echo "sig=$sig;"
curl -H "Content-Type: application/json" -X POST -d $request "http://fm.grandstream.com/api/provision?time=${time}&sig=${sig}"

key='zL4rwLSBr5Pz5us'
time=$(curl -s 'fm.grandstream.com/api/provision' | jq '.time') 
echo "time=$time;"
request='{"cid":"2018","method":"redirectDefault","params":{"macs":["00000000003"]}}'
echo "request=$request;"
str=$request$time
echo "str=$str;"
sig=$(echo -n $str | openssl sha1 -hmac $key -binary|xxd -p)
echo "sig=$sig;"
curl -H "Content-Type: application/json" -X POST -d $request "http://fm.grandstream.com/api/provision?time=${time}&sig=${sig}"

key='zL4rwLSBr5Pz5us'
time=$(curl -s 'fm.grandstream.com/api/provision' | jq '.time')  
echo "time=$time;"
request='{"cid":"2018","method":"listDevicesConfig","params":{"macs":["00000000001","00000000002","00000000003"]}}'
echo "request=$request;"
str=$request$time
echo "str=$str;"
sig=$(echo -n $str | openssl sha1 -hmac $key -binary|xxd -p)
echo "sig=$sig;"
curl -H "Content-Type: application/json" -X POST -d $request "http://fm.grandstream.com/api/provision?time=${time}&sig=${sig}"


=============================================

key='zL4rwLSBr5Pz5us'
time=$(curl -s 'fm.grandstream.com/api/provision' | jq '.time')  
echo "time=$time;"
request='{"cid":"2018","method":"listProfile","params":{}}'
echo "request=$request;"
str=$request$time
echo "str=$str;"
sig=$(openssl sha1 -hmac $key -binary <(echo -n $str)|xxd -p)
echo "sig=$sig;"
curl -H "Content-Type: application/json" -X GET -d $request "http://fm.grandstream.com/api/provision?time=${time}&sig=${sig}"

