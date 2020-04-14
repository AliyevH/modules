#!/bin/bash

cat > index.html <<EOF
<h1>$HOSTNAME</h1>
<h1>Hello, World</h1>
<p>DB Adress: ${db_address}</p>
<p>DB Port: ${db_port}</p>
EOF

nohup busybox httpd -f -p ${server_port} &

