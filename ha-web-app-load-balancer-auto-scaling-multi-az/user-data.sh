#!/bin/bash
yum update -y
yum install -y httpd

TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /var/www/html/index.html <<EOF
<html>
  <head><title>HA Web App Demo</title></head>
  <body style="font-family: Arial; margin: 40px;">
    <h1>HA Web App is running ✅</h1>
    <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
    <p><strong>Availability Zone:</strong> $AZ</p>
    <p><strong>Project:</strong> HA Web App (ALB + ASG + Multi-AZ)</p>
  </body>
</html>
EOF

systemctl enable httpd
systemctl start httpd