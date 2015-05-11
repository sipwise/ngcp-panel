importcreds () {
    if [ -f "$CREDS" ]; then
        echo "$CREDS present, checking perms"
        set +e; stat "$CREDS" | grep 'Access: (0600' 1>/dev/null; r=$?; set -e
        if [ "$r" = "0" ]; then
            echo "$CREDS permissions ok"
            . "$CREDS"
        else
            echo "$CREDS must have permissions 600"
            exit 1
        fi
    fi
}


