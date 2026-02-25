
# HA Web App (Load Balancer + Auto Scaling + Multi-AZ)

## Purpose

This project shows how I build a **high-availability (HA) web application on AWS** using:

* **Application Load Balancer (ALB)**
* **Auto Scaling Group (ASG)**
* **EC2 Launch Template**
* **Multi-AZ deployment** (2 Availability Zones)

The goal is to prove I can design a setup that keeps the app available even when one instance fails.

---

## Problem

In real operations, a single EC2 instance is a risk.

### Real “Ops” Scenario

I deploy a web app on one EC2 instance. It works. But then:

* the instance crashes
* the instance becomes unhealthy
* an AZ has an issue
* traffic increases suddenly

If I only have one server, users see downtime.

That is not good for production.

---

## Solution

I build a **high-availability web tier** with:

* **ALB** to distribute traffic
* **ASG** to keep the right number of instances running
* **2 subnets in 2 AZs** for resilience
* **Health checks** so unhealthy instances are replaced automatically

---

## Architecture Diagram

![Architecture Diagram](screenshots/architecture.png)



> **Note:** For demo simplicity, the EC2 instances can be placed in public subnets. For a more production-grade setup, I would place app instances in **private subnets** and keep only the ALB public.

---

## Step-by-step

## Step 1 — Prerequisites

### Step 1.1 — Install and verify tools

```bash
aws --version
```

### Step 1.2 — Configure AWS credentials

```bash
aws configure
```

### Step 1.3 — Confirm identity (important)

```bash
aws sts get-caller-identity
```

**Purpose:** Make sure I am using the correct AWS account before creating resources.


---

## Step 2 — Set variables (use this first)

> I always start with variables so the commands are easier to reuse and update.

### Step 2.1 — Global variables

```bash
# ===== Core project settings =====
export AWS_REGION="us-east-1"
export PROJECT="ha-webapp"
export ENV="dev"

# ===== Networking =====
export VPC_CIDR="10.20.0.0/16"
export SUBNET1_CIDR="10.20.1.0/24"
export SUBNET2_CIDR="10.20.2.0/24"

# ===== Compute / scaling =====
export INSTANCE_TYPE="t3.micro"
export KEY_NAME=""   # optional (leave empty if using SSM only)
export ASG_MIN="2"
export ASG_DESIRED="2"
export ASG_MAX="4"

# ===== Ports =====
export APP_PORT="80"
```

### Step 2.2 — Get available AZs (pick two)

```bash
aws ec2 describe-availability-zones \
  --region "$AWS_REGION" \
  --query 'AvailabilityZones[?State==`available`].ZoneName' \
  --output table
```

Set two AZs:

```bash
export AZ1="us-east-1a"
export AZ2="us-east-1b"
```

**Purpose:** Multi-AZ only works if I intentionally place subnets in different AZs.

### Screenshot (Step 2)

**Should show:** available AZs in the region.

![AZ list](screenshots/02-az-list.png)

---

## Step 3 — Create networking (VPC + subnets + IGW + routes)

### Step 3.1 — Create VPC

```bash
export VPC_ID=$(aws ec2 create-vpc \
  --region "$AWS_REGION" \
  --cidr-block "$VPC_CIDR" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT}-${ENV}-vpc}]" \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC_ID=$VPC_ID"
```

Enable DNS support/hostnames:

```bash
aws ec2 modify-vpc-attribute --region "$AWS_REGION" --vpc-id "$VPC_ID" --enable-dns-support
aws ec2 modify-vpc-attribute --region "$AWS_REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames
```

**Purpose:** VPC is the network boundary for all resources.

### Step 3.2 — Create two subnets in two AZs

```bash
export SUBNET1_ID=$(aws ec2 create-subnet \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block "$SUBNET1_CIDR" \
  --availability-zone "$AZ1" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-${ENV}-subnet-az1}]" \
  --query 'Subnet.SubnetId' \
  --output text)

export SUBNET2_ID=$(aws ec2 create-subnet \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block "$SUBNET2_CIDR" \
  --availability-zone "$AZ2" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT}-${ENV}-subnet-az2}]" \
  --query 'Subnet.SubnetId' \
  --output text)

echo "SUBNET1_ID=$SUBNET1_ID"
echo "SUBNET2_ID=$SUBNET2_ID"
```

Enable auto-assign public IP (demo-friendly):

```bash
aws ec2 modify-subnet-attribute --region "$AWS_REGION" --subnet-id "$SUBNET1_ID" --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --region "$AWS_REGION" --subnet-id "$SUBNET2_ID" --map-public-ip-on-launch
```

**Purpose:** Two subnets in different AZs allow ASG to spread instances for HA.

### Step 3.3 — Create and attach Internet Gateway

```bash
export IGW_ID=$(aws ec2 create-internet-gateway \
  --region "$AWS_REGION" \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT}-${ENV}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --region "$AWS_REGION" \
  --internet-gateway-id "$IGW_ID" \
  --vpc-id "$VPC_ID"

echo "IGW_ID=$IGW_ID"
```

**Purpose:** Needed for internet access (ALB + demo instances).

### Step 3.4 — Create route table and default route

```bash
export RTB_ID=$(aws ec2 create-route-table \
  --region "$AWS_REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT}-${ENV}-public-rt}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route \
  --region "$AWS_REGION" \
  --route-table-id "$RTB_ID" \
  --destination-cidr-block "0.0.0.0/0" \
  --gateway-id "$IGW_ID"

aws ec2 associate-route-table --region "$AWS_REGION" --subnet-id "$SUBNET1_ID" --route-table-id "$RTB_ID"
aws ec2 associate-route-table --region "$AWS_REGION" --subnet-id "$SUBNET2_ID" --route-table-id "$RTB_ID"

echo "RTB_ID=$RTB_ID"
```

**Purpose:** Sends outbound internet traffic through the IGW.

### Screenshots (Step 3)

**Should show:** two subnets in different AZs.
![Subnets in Multi-AZ](screenshots/03-subnets-multi-az.png)
---

**Should show:** route `0.0.0.0/0` to IGW.
![Route table to IGW](screenshots/04-route-table-igw.png)

---

## Step 4 — Create security groups (ALB SG + EC2 SG)

### Step 4.1 — ALB security group

```bash
export ALB_SG_ID=$(aws ec2 create-security-group \
  --region "$AWS_REGION" \
  --group-name "${PROJECT}-${ENV}-alb-sg" \
  --description "ALB SG - allow HTTP from internet" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --region "$AWS_REGION" \
  --group-id "$ALB_SG_ID" \
  --ip-permissions '[
    {
      "IpProtocol":"tcp",
      "FromPort":80,
      "ToPort":80,
      "IpRanges":[{"CidrIp":"0.0.0.0/0","Description":"Allow HTTP"}]
    }
  ]'

echo "ALB_SG_ID=$ALB_SG_ID"
```

**Purpose:** ALB must accept traffic from users on port 80.

### Step 4.2 — EC2 app security group

```bash
export APP_SG_ID=$(aws ec2 create-security-group \
  --region "$AWS_REGION" \
  --group-name "${PROJECT}-${ENV}-app-sg" \
  --description "App SG - allow HTTP only from ALB SG" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --region "$AWS_REGION" \
  --group-id "$APP_SG_ID" \
  --ip-permissions "[
    {
      \"IpProtocol\":\"tcp\",
      \"FromPort\":80,
      \"ToPort\":80,
      \"UserIdGroupPairs\":[{\"GroupId\":\"$ALB_SG_ID\",\"Description\":\"ALB to app\"}]
    }
  ]"

echo "APP_SG_ID=$APP_SG_ID"
```

**Purpose:** App instances should not be open to the internet directly.

### Screenshot (Step 4)

**Should show:** ALB SG and App SG rules.

![Security groups](screenshots/05-security-groups.png)

---

## Step 5 — Create IAM role and instance profile (recommended for SSM)

> This lets me manage instances without SSH keys (cleaner and safer demo).

### Step 5.1 — Create trust policy file

Create file: `iam-ec2-trust-policy.json`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Step 5.2 — Create role and attach SSM managed policy

```bash
export EC2_ROLE_NAME="${PROJECT}-${ENV}-ec2-role"
export EC2_INSTANCE_PROFILE_NAME="${PROJECT}-${ENV}-ec2-profile"

aws iam create-role \
  --role-name "$EC2_ROLE_NAME" \
  --assume-role-policy-document file://iam-ec2-trust-policy.json

aws iam attach-role-policy \
  --role-name "$EC2_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

### Step 5.3 — Create instance profile and add role

```bash
aws iam create-instance-profile --instance-profile-name "$EC2_INSTANCE_PROFILE_NAME"

aws iam add-role-to-instance-profile \
  --instance-profile-name "$EC2_INSTANCE_PROFILE_NAME" \
  --role-name "$EC2_ROLE_NAME"

sleep 15
```

**Purpose:** SSM gives me secure access to troubleshoot instances without opening SSH port 22.

### Screenshot (Step 5)

**Should show:** EC2 role + instance profile + SSM policy.

![IAM role and instance profile](screenshots/06-iam-role-instance-profile.png)

---

## Step 6 — Get a Linux AMI ID (Amazon Linux 2)

```bash
export AMI_ID=$(aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
  --query 'Parameter.Value' \
  --output text)

echo "AMI_ID=$AMI_ID"
```

**Purpose:** Use a current Amazon Linux AMI without hardcoding IDs.

---

## Step 7 — Create user data script (web app install)

Create file: `user-data.sh`

```bash
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
```

Make executable:

```bash
chmod +x user-data.sh
```

**Purpose:** Automatically installs a web server and displays instance info, which helps during testing and failover demos.

---

## Step 8 — Create Launch Template

### Step 8.1 — Base64 encode user data (Linux/macOS)

```bash
export USER_DATA_B64=$(base64 < user-data.sh | tr -d '\n')
```

### Step 8.2 — Create launch template

```bash
export LT_NAME="${PROJECT}-${ENV}-lt"

aws ec2 create-launch-template \
  --region "$AWS_REGION" \
  --launch-template-name "$LT_NAME" \
  --launch-template-data "{
    \"ImageId\":\"$AMI_ID\",
    \"InstanceType\":\"$INSTANCE_TYPE\",
    \"SecurityGroupIds\":[\"$APP_SG_ID\"],
    \"IamInstanceProfile\":{\"Name\":\"$EC2_INSTANCE_PROFILE_NAME\"},
    \"UserData\":\"$USER_DATA_B64\",
    \"TagSpecifications\":[
      {
        \"ResourceType\":\"instance\",
        \"Tags\":[
          {\"Key\":\"Name\",\"Value\":\"${PROJECT}-${ENV}-app\"},
          {\"Key\":\"Project\",\"Value\":\"$PROJECT\"},
          {\"Key\":\"Env\",\"Value\":\"$ENV\"}
        ]
      }
    ]
  }"
```

Get Launch Template ID:

```bash
export LT_ID=$(aws ec2 describe-launch-templates \
  --region "$AWS_REGION" \
  --launch-template-names "$LT_NAME" \
  --query 'LaunchTemplates[0].LaunchTemplateId' \
  --output text)

echo "LT_ID=$LT_ID"
```

**Purpose:** Launch Template standardizes how ASG creates replacement instances.

### Screenshot (Step 8)

**Should show:** launch template created.

![Launch template created](screenshots/07-launch-template-created.png)

---

## Step 9 — Create Target Group (ALB backend)

```bash
export TG_NAME="${PROJECT}-${ENV}-tg"

export TG_ARN=$(aws elbv2 create-target-group \
  --region "$AWS_REGION" \
  --name "$TG_NAME" \
  --protocol HTTP \
  --port 80 \
  --vpc-id "$VPC_ID" \
  --target-type instance \
  --health-check-protocol HTTP \
  --health-check-port traffic-port \
  --health-check-path "/" \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --matcher HttpCode=200 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

echo "TG_ARN=$TG_ARN"
```

**Purpose:** Target Group defines where ALB sends traffic and how health checks work.

---

## Step 10 — Create Application Load Balancer + Listener

### Step 10.1 — Create ALB

```bash
export ALB_NAME="${PROJECT}-${ENV}-alb"

export ALB_ARN=$(aws elbv2 create-load-balancer \
  --region "$AWS_REGION" \
  --name "$ALB_NAME" \
  --subnets "$SUBNET1_ID" "$SUBNET2_ID" \
  --security-groups "$ALB_SG_ID" \
  --scheme internet-facing \
  --type application \
  --ip-address-type ipv4 \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

echo "ALB_ARN=$ALB_ARN"
```

Get ALB DNS:

```bash
export ALB_DNS=$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "ALB_DNS=$ALB_DNS"
```

### Step 10.2 — Create listener (HTTP:80 -> target group)

```bash
export LISTENER_ARN=$(aws elbv2 create-listener \
  --region "$AWS_REGION" \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
  --query 'Listeners[0].ListenerArn' \
  --output text)

echo "LISTENER_ARN=$LISTENER_ARN"
```

**Purpose:** ALB listener receives internet traffic and forwards it to healthy app instances.

### Screenshot (Step 10)

**Should show:** ALB active + HTTP listener.

![ALB listener created](screenshots/08-alb-listener-created.png)

---

## Step 11 — Create Auto Scaling Group (spread across 2 AZs)

```bash
export ASG_NAME="${PROJECT}-${ENV}-asg"

aws autoscaling create-auto-scaling-group \
  --region "$AWS_REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --launch-template "LaunchTemplateId=$LT_ID,Version=\$Latest" \
  --min-size "$ASG_MIN" \
  --max-size "$ASG_MAX" \
  --desired-capacity "$ASG_DESIRED" \
  --vpc-zone-identifier "${SUBNET1_ID},${SUBNET2_ID}" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB \
  --health-check-grace-period 120 \
  --tags "ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=Name,Value=${PROJECT}-${ENV}-asg-instance,PropagateAtLaunch=true" \
         "ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=Project,Value=$PROJECT,PropagateAtLaunch=true" \
         "ResourceId=$ASG_NAME,ResourceType=auto-scaling-group,Key=Env,Value=$ENV,PropagateAtLaunch=true"
```

**Purpose:** ASG keeps the app running by maintaining desired instance count and replacing unhealthy instances.

### Screenshot (Step 11)

**Should show:** ASG desired/min/max and subnet list.

![ASG created](screenshots/09-asg-created.png)

---

## Step 12 — Wait for instances and health checks

### Step 12.1 — Check ASG instances

```bash
aws autoscaling describe-auto-scaling-groups \
  --region "$AWS_REGION" \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]' \
  --output table
```

### Step 12.2 — Check target group health

```bash
aws elbv2 describe-target-health \
  --region "$AWS_REGION" \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table
```

**Purpose:** Confirm the instances are launched and passing ALB health checks before testing from browser.

### Screenshot (Step 12)

**Should show:** two healthy targets.

![Target group healthy](screenshots/10-target-group-healthy.png)

---

## Step 13 — Test the app

### Step 13.1 — Open the app in browser

```bash
echo "http://$ALB_DNS"
```

Or from CLI:

```bash
curl -s "http://$ALB_DNS"
```

**Expected result:** HTML page showing:

* “HA Web App is running”
* instance ID
* AZ

### Screenshot (Step 13)

**Should show:** app page via ALB DNS.

![ALB working](screenshots/11-alb-working.png)

---

## Step 14 — Enable scaling policy 

### Step 14.1 — Create scale-out policy

```bash
aws autoscaling put-scaling-policy \
  --region "$AWS_REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --policy-name "${PROJECT}-${ENV}-cpu-tt" \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 50.0
  }'
```

**Purpose:** Automatically adds/removes instances based on CPU usage.

---

## Testing

## Step 15 — Failure simulation 

This is the part I really like to demo because it proves the design works during a real issue.

### Step 15.1 — Get running instance IDs

```bash
aws autoscaling describe-auto-scaling-groups \
  --region "$AWS_REGION" \
  --auto-scaling-group-names "$ASG_NAME" \
  --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
  --output table
```

Pick one instance ID:

```bash
export BAD_INSTANCE_ID="<paste-one-instance-id>"
```

### Step 15.2 — Terminate one instance (simulate failure)

```bash
aws ec2 terminate-instances \
  --region "$AWS_REGION" \
  --instance-ids "$BAD_INSTANCE_ID"
```

**What I expect:**

* ALB health check marks it unhealthy
* ASG launches a replacement instance automatically
* App remains available through ALB

### Step 15.3 — Watch replacement happen

```bash

watch -n 10 "aws autoscaling describe-auto-scaling-groups \
  --region $AWS_REGION \
  --auto-scaling-group-names $ASG_NAME \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]' \
  --output table"
```

### Step 15.4 — Confirm target group health again

```bash
aws elbv2 describe-target-health \
  --region "$AWS_REGION" \
  --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
  --output table
```

### Step 15.5 — Confirm app still responds

```bash
curl -s "http://$ALB_DNS" | head
```

**This demonstrates:** auto-healing + HA behavior.

### Screenshots (Step 15)

**Should show:** one instance terminated manually.
![Terminate instance](screenshots/12-terminate-instance.png)

**Should show:** ASG launching replacement instance.
![ASG replaced instance](screenshots/13-asg-replaced-instance.png)

**Should show:** app still available after fail simulation.
![App still working after failure](screenshots/14-app-still-working-after-failure.png)

---

## Outcome

By the end of this project, I can confidently explain and demo:

* how I build a **high-availability web tier** on AWS
* how **ALB health checks** work
* how **ASG replaces failed instances automatically**
* how **Multi-AZ** improves resilience
* how I troubleshoot using CLI and health checks

---

## Troubleshooting

### Common issue 1 — ALB shows 503 / targets unhealthy

**Possible causes**

* `httpd` not installed or not started
* user-data script failed
* app listens on wrong port
* app SG not allowing port 80 from ALB SG

**Checks**

```bash
aws elbv2 describe-target-health --region "$AWS_REGION" --target-group-arn "$TG_ARN"
```

If using SSM, connect to instance:

```bash
aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text
```

Start session (replace instance id):

```bash
aws ssm start-session --region "$AWS_REGION" --target <instance-id>
```

Then on the instance:

```bash
sudo systemctl status httpd
sudo journalctl -u httpd --no-pager | tail -50
sudo cat /var/log/cloud-init-output.log | tail -100
curl -I http://localhost
```

---

### Common issue 2 — ASG launches no instances

**Possible causes**

* bad launch template AMI
* IAM instance profile not ready yet
* subnet/route issues
* EC2 quota limits

**Checks**

```bash
aws autoscaling describe-scaling-activities \
  --region "$AWS_REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --max-items 10
```

---

### Common issue 3 — ALB DNS opens but times out

**Possible causes**

* ALB security group missing inbound 80
* route table missing `0.0.0.0/0 -> IGW`
* ALB not active yet

**Checks**

```bash
aws elbv2 describe-load-balancers --region "$AWS_REGION" --load-balancer-arns "$ALB_ARN"
aws ec2 describe-route-tables --region "$AWS_REGION" --route-table-ids "$RTB_ID"
aws ec2 describe-security-groups --region "$AWS_REGION" --group-ids "$ALB_SG_ID"
```

---
---

## Cleanup

> I always include cleanup so I don’t leave resources running and generating cost.

## Step 16 — Delete resources in safe order

### Step 16.1 — Delete ASG

```bash
aws autoscaling update-auto-scaling-group \
  --region "$AWS_REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --min-size 0 \
  --desired-capacity 0

sleep 30

aws autoscaling delete-auto-scaling-group \
  --region "$AWS_REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --force-delete
```

### Step 16.2 — Delete ALB listener, ALB, target group

```bash
aws elbv2 delete-listener --region "$AWS_REGION" --listener-arn "$LISTENER_ARN"

aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$ALB_ARN"

sleep 60

aws elbv2 delete-target-group --region "$AWS_REGION" --target-group-arn "$TG_ARN"
```

### Step 16.3 — Delete launch template

```bash
aws ec2 delete-launch-template --region "$AWS_REGION" --launch-template-id "$LT_ID"
```

### Step 16.4 — Delete security groups

```bash
aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$APP_SG_ID"
aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$ALB_SG_ID"
```

### Step 16.5 — Delete IAM instance profile and role

```bash
aws iam remove-role-from-instance-profile \
  --instance-profile-name "$EC2_INSTANCE_PROFILE_NAME" \
  --role-name "$EC2_ROLE_NAME"

aws iam delete-instance-profile --instance-profile-name "$EC2_INSTANCE_PROFILE_NAME"

aws iam detach-role-policy \
  --role-name "$EC2_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam delete-role --role-name "$EC2_ROLE_NAME"
```

### Step 16.6 — Delete route table, IGW, subnets, VPC

```bash
aws ec2 describe-route-tables \
  --region "$AWS_REGION" \
  --route-table-ids "$RTB_ID" \
  --query 'RouteTables[0].Associations[*].RouteTableAssociationId' \
  --output text
```

Disassociate non-main route table associations (if returned):

```bash
# replace with actual assoc IDs if needed
# aws ec2 disassociate-route-table --region "$AWS_REGION" --association-id rtbassoc-xxxx
```

Delete route + route table:

```bash
aws ec2 delete-route \
  --region "$AWS_REGION" \
  --route-table-id "$RTB_ID" \
  --destination-cidr-block 0.0.0.0/0 || true

aws ec2 delete-route-table --region "$AWS_REGION" --route-table-id "$RTB_ID"
```

Detach and delete IGW:

```bash
aws ec2 detach-internet-gateway --region "$AWS_REGION" --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
aws ec2 delete-internet-gateway --region "$AWS_REGION" --internet-gateway-id "$IGW_ID"
```

Delete subnets and VPC:

```bash
aws ec2 delete-subnet --region "$AWS_REGION" --subnet-id "$SUBNET1_ID"
aws ec2 delete-subnet --region "$AWS_REGION" --subnet-id "$SUBNET2_ID"
aws ec2 delete-vpc --region "$AWS_REGION" --vpc-id "$VPC_ID"
```

### Step 16.7 — Remove local files (optional)

```bash
rm -f user-data.sh iam-ec2-trust-policy.json
```

---

