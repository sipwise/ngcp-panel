<?php

require_once 'nusoap/nusoap.php';
$wsdl = 'https://10.15.17.233:2443/SOAP/Intercept.wsdl';
#$wsdl = 'https://192.168.0.126:1443/SOAP/Intercept.wsdl';

$client = new nusoap_client($wsdl, true);
$client->setCredentials('ngcpsoap', 'password', 'basic');
$error = $client->getError();
if($error) {
    echo "Error: " . $error;
    return;
}

echo "Fetched wsdl, starting tasks\n";

$res = $client->call('create_interception', 
        array(
            'authentication' => array(
                'username' => 'intercept',
                'password' => 'secret',
                'type' => 'admin'
            ),
            'parameters' => array(
                'LIID' => '1234',
                'number' => '439991001',
                'cc_required' => 0,
                'iri_delivery' => array(
                    'host' => '1.2.3.4',
                    'port' => 1234,
                ),
            )
        )
);
echo "Request:";
echo $client->request;
echo "\n";
echo "Response:";
echo $client->response;
echo "\n\n\n";

if($client->fault) {
    echo "Fault";
    print_r($res);
    exit;
} else {
    $error = $client->getError();
    if($error) {
        echo "Server Error: " . $error;
        exit;
    } else {
        echo "Result:";
        echo $res;
        echo "\n\n\n";
    }
}
$id = $res;

$res = $client->call('update_interception', 
        array(
            'authentication' => array(
                'username' => 'intercept',
                'password' => 'secret',
                'type' => 'admin'
            ),
            'parameters' => array(
                'id' => $res,
                'data' => array(
                    'cc_required' => 1,
                    'iri_delivery' => array(
                        'host' => '1.2.3.5',
                        'port' => 1234,
                    ),
                    'cc_delivery' => array(
                        'host' => '1.2.3.6',
                        'port' => 1236,
                    )
                )
            )
        )
);
echo "Request:";
echo $client->request;
echo "\n";
echo "Response:";
echo $client->response;
echo "\n\n\n";

if($client->fault) {
    echo "Fault";
    print_r($res);
    exit;
} else {
    $error = $client->getError();
    if($error) {
        echo "Server Error: " . $error;
        exit;
    } else {
        echo "Result:";
        echo $res;
        echo "\n\n\n";
    }
}


$res = $client->call('get_interceptions_by_liid', 
    array(
        'authentication' => array(
            'username' => 'administrator',
            'password' => 'administrator',
            'type' => 'admin'
        ),
        'parameters' => array(
            'LIID' => 1234
        )
    )
);
echo "Request:";
echo $client->request;
echo "\n";
echo "Response:";
echo $client->response;
echo "\n\n\n";

if($client->fault) {
    echo "Fault";
    print_r($res);
} else {
    $error = $client->getError();
    if($error) {
        echo "Server Error: " . $error;
    } else {
        echo "Result:";
        print_r($res);
        echo "\n\n\n";
    }
}

$res = $client->call('delete_interception', 
    array(
        'authentication' => array(
            'username' => 'administrator',
            'password' => 'administrator',
            'type' => 'admin'
        ),
        'parameters' => array(
            'id' => $id
        )
    )
);
echo "Request:";
echo $client->request;
echo "\n";
echo "Response:";
echo $client->response;
echo "\n\n\n";

if($client->fault) {
    echo "Fault";
    print_r($res);
} else {
    $error = $client->getError();
    if($error) {
        echo "Server Error: " . $error;
    } else {
        echo "Result:";
        print_r($res);
        echo "\n\n\n";
    }
}

$res = $client->call('get_interception_by_id', 
    array(
        'authentication' => array(
            'username' => 'administrator',
            'password' => 'administrator',
            'type' => 'admin'
        ),
        'parameters' => array(
            'id' => $id
        )
    )
);
echo "Request:";
echo $client->request;
echo "\n";
echo "Response:";
echo $client->response;
echo "\n\n\n";

if($client->fault) {
    echo "Fault";
    print_r($res);
} else {
    $error = $client->getError();
    if($error) {
        echo "Server Error: " . $error;
    } else {
        echo "Result:";
        print_r($res);
        echo "\n\n\n";
    }
}


$res = $client->call('get_interceptions_by_number', 
    array(
        'authentication' => array(
            'username' => 'administrator',
            'password' => 'administrator',
            'type' => 'admin'
        ),
        'parameters' => array(
            'number' => '439991001'
        )
    )
);
echo "Request:";
echo $client->request;
echo "\n";
echo "Response:";
echo $client->response;
echo "\n\n\n";

if($client->fault) {
    echo "Fault";
    print_r($res);
} else {
    $error = $client->getError();
    if($error) {
        echo "Server Error: " . $error;
    } else {
        echo "Result:";
        print_r($res);
        echo "\n\n\n";
    }
}

$res = $client->call('get_interceptions', 
    array(
        'authentication' => array(
            'username' => 'administrator',
            'password' => 'administrator',
            'type' => 'admin'
        ),
        'parameters' => array(
        )
    )
);
echo "Request:";
echo $client->request;
echo "\n";
echo "Response:";
echo $client->response;
echo "\n\n\n";

if($client->fault) {
    echo "Fault";
    print_r($res);
} else {
    $error = $client->getError();
    if($error) {
        echo "Server Error: " . $error;
    } else {
        echo "Result:";
        print_r($res);
        echo "\n\n\n";
    }
}

?>
