#!/bin/bash
set -eux

dnf update -y
dnf install -y httpd

systemctl enable httpd
systemctl start httpd

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html>
<head>
  <title>Cloud Monitoring + Flow Logs Demo</title>
</head>
<body>
  <h1>Cloud Monitoring + Flow Logs Demo</h1>
  <p>Hello from EC2.</p>
  <p>Project: cloud-monitoring-flowlogs</p>
  <p>Environment: dev</p>
</body>
</html>
HTML
