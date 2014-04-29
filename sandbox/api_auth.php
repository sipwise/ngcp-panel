<?php
$ua = curl_init();
$options = array( 
    CURLOPT_SSLCERT => '/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate-1385650532.pem',
    CURLOPT_SSLKEY  => '/etc/ngcp-panel/api_ssl/NGCP-API-client-certificate-1385650532.pem',
    CURLOPT_CAINFO => '/etc/ngcp-panel/api_ssl/api_ca.crt',
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_RETURNTRANSFER => true,
);
curl_setopt_array($ua , $options);

curl_setopt($ua, CURLOPT_URL, 'https://serenity:4443/api/contacts/?id=10');
$res = curl_exec($ua);
if(!$res) {
    echo "Curl Error : " . curl_error($ua);
}
else {
    echo $res;
}
?>
