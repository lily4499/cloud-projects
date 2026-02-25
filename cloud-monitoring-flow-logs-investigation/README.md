
# Cloud Monitoring + Flow Logs Investigation (CloudWatch + Logs + VPC Flow Logs)

## Purpose

I built this project to show that I can **monitor cloud infrastructure**, **detect network issues**, and **investigate traffic problems** using AWS native tools.

This project demonstrates how I use:

- **Amazon CloudWatch** (metrics, dashboards, alarms)
- **Amazon SNS** (alert notifications)
- **VPC Flow Logs** (network traffic visibility)
- **CloudWatch Logs + Logs Insights** (log investigation)
- **EC2 + Security Groups** (real test target)



---

## Problem

In real production environments, an application can go down even when the EC2 instance is still running.

### Real “Ops” Scenario 

I deployed a web app on an EC2 instance. Suddenly users say:

- “The app is not loading”
- “The server is up, but the site times out”

At first glance:

- EC2 is **running**
- CPU looks normal
- No obvious crash

So the problem may be:

- wrong **security group rule**
- wrong **port**
- blocked **network traffic**
- app listening on the wrong interface/port

Without monitoring and network visibility, troubleshooting becomes slow and risky.

---

## Solution

I built a monitoring and investigation setup that gives me:

1. **CloudWatch dashboard** for quick visibility (CPU, status checks, network)
2. **CloudWatch alarms** to detect issues early
3. **SNS notifications** for alerting
4. **VPC Flow Logs** to see ACCEPT/REJECT traffic
5. **CloudWatch Logs Insights queries** to investigate traffic problems
6. **Failure simulation** to prove the setup works

This helps me move from:

- “Users say it is down”

to

- “I can see the alarm, identify the blocked traffic, fix the rule, and verify recovery.”

---

## Architecture Diagram

![Architecture Diagram](screenshots/architecture.png)


---

## Step-by-step CLI 

## Step 0 — Create a small EC2 web server (from scratch)

**Purpose:** create a simple EC2 target (with a web page) that I will monitor and investigate in the rest of the project.

### variables

**Purpose:** keep EC2 creation commands reusable.

```bash
# ===== EC2 Build Variables =====
export AWS_REGION="us-east-1"
export PROJECT_NAME="cloud-monitoring-flowlogs"
export ENV="dev"

# Use an existing VPC and PUBLIC subnet (same VPC you will monitor)
export VPC_ID="vpc-03701e181332d26eb"
export PUBLIC_SUBNET_ID="subnet-00fca5c7582084872"

# EC2 settings
export INSTANCE_TYPE="t3.micro"
export EC2_NAME="${PROJECT_NAME}-${ENV}-web"
export INSTANCE_NAME="ec2-ssm-lab"
export EC2_SG_ID="sg-091906568d27d3894"
export PROFILE_NAME="ec2-ssm-instance-profile"
export AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --region "$AWS_REGION" \
  --query 'Parameter.Value' \
  --output text)

echo "AMI_ID=$AMI_ID"

# Optional tagging
export OWNER_TAG="Liliane"


```

---

###  Create user-data script (install web server + sample page)

**Purpose:** automatically install and start a web server when the instance launches.

```bash
cat > user-data.sh <<'EOF'
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
EOF
```

---

### Launch EC2 instance

**Purpose:** create the EC2 instance that will be monitored in this project.


```bash
export INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$PUBLIC_SUBNET_ID" \
  --security-group-ids "$EC2_SG_ID" \
  --iam-instance-profile Name="$PROFILE_NAME" \
  --associate-public-ip-address \
  --user-data file://user-data.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$EC2_NAME},{Key=Project,Value=$PROJECT_NAME},{Key=Env,Value=$ENV},{Key=Owner,Value=$OWNER_TAG}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "$INSTANCE_ID"
```


###  Wait until instance is running and verify details

**Purpose:** confirm the instance is ready before testing.

```bash
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# Confirm SSM sees the instance
aws ssm describe-instance-information \
  --query "InstanceInformationList[?InstanceId=='$INSTANCE_ID']"

# Login using Session Manager (NO SSH)
aws ssm start-session --target "$INSTANCE_ID"

```

---

###  Test the web page

**Purpose:** confirm the app is reachable before setting up monitoring.

```bash
export EC2_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "$EC2_PUBLIC_IP"

curl -I "http://$EC2_PUBLIC_IP"
curl "http://$EC2_PUBLIC_IP"
```

**Screenshot to attach**

* `screenshots/step0-webpage-working-cli.png`
    * Should show: successful curl output 
![Web page working CLI](screenshots/step0-webpage-working-cli.png)

---

* `screenshots/step0-webpage-working-browser-cli.png`
  * Should show: successful  browser page loading
![Web page working Browser](screenshots/step0-webpage-working-browser.png)

---

---

## Step 1 — Set monitoring variables (foundation)

**Purpose:** keep monitoring commands reusable and clean.

> Reuse values from Step 0 (`INSTANCE_ID`, `EC2_SG_ID`, `VPC_ID`, `APP_PORT`).

```bash
# ===== Monitoring / Logs =====
export CW_LOG_GROUP="/aws/vpc/${PROJECT_NAME}-${ENV}-flowlogs"
export FLOW_LOG_NAME="${PROJECT_NAME}-${ENV}-vpc-flowlog"

# ===== CloudWatch =====
export DASHBOARD_NAME="${PROJECT_NAME}-${ENV}-dashboard"
export CPU_ALARM_NAME="${PROJECT_NAME}-${ENV}-high-cpu"
export STATUS_ALARM_NAME="${PROJECT_NAME}-${ENV}-status-check-failed"

# ===== SNS Alerts =====
export SNS_TOPIC_NAME="${PROJECT_NAME}-${ENV}-alerts"
export ALERT_EMAIL="konissil@gmail.com"

# ===== IAM role for Flow Logs =====
export FLOWLOGS_ROLE_NAME="${PROJECT_NAME}-${ENV}-flowlogs-role"
export FLOWLOGS_POLICY_NAME="${PROJECT_NAME}-${ENV}-flowlogs-policy"
```

---

## Step 2 — Verify AWS identity and target instance

**Purpose:** confirm I am in the correct AWS account/region before creating resources.

```bash
aws sts get-caller-identity
aws configure get region

aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PrivateIpAddress,PublicIpAddress,VpcId,SubnetId]' \
  --output table
```

**Screenshot to attach**

* `screenshots/step2-sts-and-ec2-verify.png`

  * Should show: AWS identity + EC2 details with running state
![AWS identity and EC2 verification](screenshots/step2-sts-and-ec2-verify.png)
---

## Step 3 — Create SNS topic and subscribe email (alerts)

**Purpose:** receive CloudWatch alarm notifications.

```bash
export SNS_TOPIC_ARN=$(aws sns create-topic \
  --name "$SNS_TOPIC_NAME" \
  --query 'TopicArn' \
  --output text)

echo "$SNS_TOPIC_ARN"

aws sns subscribe \
  --topic-arn "$SNS_TOPIC_ARN" \
  --protocol email \
  --notification-endpoint "$ALERT_EMAIL"
```

> **Important:** Check your email and **confirm the SNS subscription**.

**Screenshot to attach**
* `screenshots/step3-sns-subscription-pending-or-confirmed.png`
  * Should show: subscription status (pending/confirmed)
![SNS subscription pending or confirmed](screenshots/step3-sns-subscription-pending-or-confirmed.png)

---

## Step 4 — Create CloudWatch dashboard (EC2 visibility)

**Purpose:** get one place to quickly see instance health and traffic.

Create the dashboard JSON file:

```bash
cat > dashboard.json <<EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0, "y": 0, "width": 12, "height": 6,
      "properties": {
        "title": "EC2 CPU Utilization",
        "region": "$AWS_REGION",
        "metrics": [
          [ "AWS/EC2", "CPUUtilization", "InstanceId", "$INSTANCE_ID" ]
        ],
        "stat": "Average",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 12, "y": 0, "width": 12, "height": 6,
      "properties": {
        "title": "EC2 Status Checks",
        "region": "$AWS_REGION",
        "metrics": [
          [ "AWS/EC2", "StatusCheckFailed", "InstanceId", "$INSTANCE_ID" ],
          [ ".", "StatusCheckFailed_Instance", ".", "." ],
          [ ".", "StatusCheckFailed_System", ".", "." ]
        ],
        "stat": "Maximum",
        "period": 60
      }
    },
    {
      "type": "metric",
      "x": 0, "y": 6, "width": 12, "height": 6,
      "properties": {
        "title": "Network In/Out",
        "region": "$AWS_REGION",
        "metrics": [
          [ "AWS/EC2", "NetworkIn", "InstanceId", "$INSTANCE_ID" ],
          [ ".", "NetworkOut", ".", "." ]
        ],
        "stat": "Sum",
        "period": 300
      }
    }
  ]
}
EOF
```

Create/update the dashboard:

```bash
aws cloudwatch put-dashboard \
  --dashboard-name "$DASHBOARD_NAME" \
  --dashboard-body file://dashboard.json
```

**Screenshot to attach**

* `screenshots/12-step4-cloudwatch-dashboard.png`

  * Should show: dashboard with CPU, status checks, and network graphs
![CloudWatch dashboard](screenshots/step4-cloudwatch-dashboard.png)
---

## Step 5 — Create CloudWatch alarms (CPU + status check)

**Purpose:** detect problems early and notify by email.

### Step 5.1 — High CPU alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "$CPU_ALARM_NAME" \
  --alarm-description "High CPU on EC2 instance" \
  --namespace "AWS/EC2" \
  --metric-name "CPUUtilization" \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --ok-actions "$SNS_TOPIC_ARN"
```

### Step 5.2 — Status check failed alarm

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "$STATUS_ALARM_NAME" \
  --alarm-description "EC2 status check failure" \
  --namespace "AWS/EC2" \
  --metric-name "StatusCheckFailed" \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --ok-actions "$SNS_TOPIC_ARN"
```

Verify alarms:

```bash
aws cloudwatch describe-alarms \
  --alarm-names "$CPU_ALARM_NAME" "$STATUS_ALARM_NAME" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName]' \
  --output table
```

**Screenshot to attach**

* `screenshots/step5-cloudwatch-alarms-created.png`

  * Should show: alarm names and current state (OK / INSUFFICIENT_DATA)
![CloudWatch alarms](screenshots/step5-cloudwatch-alarms-created.png)
---

## Step 6 — Create CloudWatch Log Group for VPC Flow Logs

**Purpose:** store flow logs in CloudWatch Logs for investigation.

```bash
aws logs create-log-group \
  --log-group-name "$CW_LOG_GROUP" 2>/dev/null || true

aws logs put-retention-policy \
  --log-group-name "$CW_LOG_GROUP" \
  --retention-in-days 14
```

Verify:

```bash
aws logs describe-log-groups \
  --log-group-name-prefix "$CW_LOG_GROUP" \
  --query 'logGroups[*].[logGroupName,retentionInDays]' \
  --output table
```

**Screenshot to attach**

* `screenshots/step6-log-group-created.png`

  * Should show: log group name and retention policy
![CloudWatch log group](screenshots/step6-log-group-created.png)
---

## Step 7 — Create IAM role for VPC Flow Logs (CloudWatch Logs destination)

**Purpose:** allow VPC Flow Logs service to publish to CloudWatch Logs.

Create trust policy:

```bash
cat > flowlogs-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": { "Service": "vpc-flow-logs.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
```

Create role:

```bash
aws iam create-role \
  --role-name "$FLOWLOGS_ROLE_NAME" \
  --assume-role-policy-document file://flowlogs-trust-policy.json
```

Create permissions policy:

```bash
cat > flowlogs-permissions-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
EOF
```

Attach inline policy:

```bash
aws iam put-role-policy \
  --role-name "$FLOWLOGS_ROLE_NAME" \
  --policy-name "$FLOWLOGS_POLICY_NAME" \
  --policy-document file://flowlogs-permissions-policy.json
```

Get role ARN:

```bash
export FLOWLOGS_ROLE_ARN=$(aws iam get-role \
  --role-name "$FLOWLOGS_ROLE_NAME" \
  --query 'Role.Arn' \
  --output text)

echo "$FLOWLOGS_ROLE_ARN"
```

**Screenshot to attach**

* `screenshots/step7-flowlogs-iam-role.png`

  * Should show: IAM role created and role ARN
![Flow Logs IAM role](screenshots/step7-flowlogs-iam-role.png)
---

## Step 8 — Enable VPC Flow Logs to CloudWatch Logs

**Purpose:** capture ACCEPT/REJECT traffic for investigation.

```bash
export FLOW_LOG_ID=$(aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids "$VPC_ID" \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name "$CW_LOG_GROUP" \
  --deliver-logs-permission-arn "$FLOWLOGS_ROLE_ARN" \
  --tag-specifications "ResourceType=vpc-flow-log,Tags=[{Key=Name,Value=$FLOW_LOG_NAME},{Key=Project,Value=$PROJECT_NAME},{Key=Env,Value=$ENV}]" \
  --query 'FlowLogIds[0]' \
  --output text)

echo "$FLOW_LOG_ID"
```

Verify flow log status:

```bash
aws ec2 describe-flow-logs \
  --filter Name=flow-log-id,Values="$FLOW_LOG_ID" \
  --query 'FlowLogs[*].[FlowLogId,FlowLogStatus,ResourceId,TrafficType,LogGroupName]' \
  --output table
```

**Screenshot to attach**

* `screenshots/step8-vpc-flowlogs-enabled.png`

  * Should show: flow log status ACTIVE and log group name
![VPC Flow Logs enabled](screenshots/step8-vpc-flowlogs-enabled.png)
---

## Step 9 — Generate test traffic (good traffic)

**Purpose:** produce normal traffic so I can confirm logs are coming in.

```bash
export EC2_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "$EC2_PUBLIC_IP"

curl -I "http://$EC2_PUBLIC_IP:$APP_PORT" || true
curl -I "http://$EC2_PUBLIC_IP:$APP_PORT" || true
curl -I "http://$EC2_PUBLIC_IP:$APP_PORT" || true
```

If your app is on port 80, this also works:

```bash
curl -I "http://$EC2_PUBLIC_IP" || true
```

**Screenshot to attach**

* `screenshots/step9-app-traffic-success.png`

  * Should show: successful curl response (200/301/302/etc.) and EC2 public IP
![Generate normal traffic](screenshots/step9-app-traffic-success.png)
---

## Step 10 — Investigate logs in CloudWatch Logs Insights

**Purpose:** confirm we can see network records and filter ACCEPT/REJECT traffic.

Open **CloudWatch Logs Insights** and select log group:

* `$CW_LOG_GROUP`

### Query 1 — Show latest records

```sql
fields @timestamp, @message
| sort @timestamp desc
| limit 20
```

### Query 2 — Find REJECT traffic quickly

```sql
fields @timestamp, @message
| filter @message like /REJECT/
| sort @timestamp desc
| limit 50
```

### Query 3 — Focus on your EC2 private IP (optional)

Get private IP first:

```bash
export EC2_PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

echo "$EC2_PRIVATE_IP"
```

Then use this query (replace `YOUR_PRIVATE_IP_HERE`):

```sql
fields @timestamp, @message
| filter @message like /REJECT/ or @message like /ACCEPT/
| filter @message like /YOUR_PRIVATE_IP_HERE/
| sort @timestamp desc
| limit 50
```

**Screenshot to attach**

* `screenshots/step10-logs-insights-accept-traffic.png`

  * Should show: flow log entries visible in Logs Insights (ACCEPT traffic)
![Logs Insights ACCEPT traffic](screenshots/step10-logs-insights-accept-traffic.png)
---

## Testing

---

### Test 1 — Simulate blocked app traffic (security group issue)

**Goal:** prove I can detect and investigate a network access issue.

#### Test 1.1 — Remove app port from Security Group (simulate mistake)

> Example: if app is on port 80, revoke 80. If app is on 8080, revoke 8080.

```bash
aws ec2 revoke-security-group-ingress \
  --group-id "$EC2_SG_ID" \
  --protocol tcp \
  --port "$APP_PORT" \
  --cidr 0.0.0.0/0
```

Try access again:

```bash
curl -I --max-time 5 "http://$EC2_PUBLIC_IP:$APP_PORT" || true
```

Expected result:

* timeout / connection failure from client side
![App timeout after block](screenshots/test1.1-app-timeout-after-block.png)
---

#### Test 1.2 — Investigate REJECT traffic in Flow Logs

Use CloudWatch Logs Insights query:

```sql
fields @timestamp, @message
| filter @message like /REJECT/
| sort @timestamp desc
| limit 50
```

You should see traffic being **REJECTED**.
![Flow Logs REJECT traffic](screenshots/test1.2-flowlogs-reject-traffic.png)

---
#### Test 1.3 — Fix the issue (restore SG rule)

```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$EC2_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=$APP_PORT,ToPort=$APP_PORT,IpRanges=[{CidrIp=0.0.0.0/0,Description='Restore app port access'}]"
```

Verify recovery:

```bash
curl -I "http://$EC2_PUBLIC_IP:$APP_PORT" || true
```
  * Should show: successful curl after fix
![App recovered](screenshots/test1.3-app-recovered.png)
---

### Test 2 — Trigger CloudWatch CPU alarm 

**Goal:** prove alarms + SNS notifications work.

SSH/SSM into EC2, run CPU stress :

```bash
# Run on the EC2 instance (SSH or SSM Session Manager)
yes > /dev/null &
yes > /dev/null &
yes > /dev/null &
yes > /dev/null &
```

Stop it later:

```bash
# Run on the EC2 instance
pkill yes
```

Check alarm state from your local terminal:

```bash
aws cloudwatch describe-alarms \
  --alarm-names "$CPU_ALARM_NAME" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table
```

Expected:

* alarm may move to `ALARM`
* SNS email notification sent
* after stopping stress, alarm returns to `OK`

**Screenshots to attach**

* `screenshots/test2.1-cpu-alarm-triggered.png`

  * Should show: CPU alarm in ALARM state
![CPU alarm triggered](screenshots/test2.1-cpu-alarm-triggered.png)
---

* `screenshots/test2.2-sns-email-alert.png`

  * Should show: SNS email alert received

![SNS email alert](screenshots/test2.2-sns-email-alert.png)

---


## Outcome

By the end of this project, I can confidently show that I can:

* build a **CloudWatch dashboard** for EC2 monitoring
* create **CloudWatch alarms** and send alerts with **SNS**
* enable and use **VPC Flow Logs**
* investigate **ACCEPT vs REJECT traffic**
* simulate a real network issue (security group mistake)
* identify the issue using logs
* restore service and verify recovery

This is the exact troubleshooting flow I would use in a real Ops/DevOps role.

---

## Troubleshooting

### 1) No flow logs appear in CloudWatch Logs

**Possible causes**

* IAM role for Flow Logs is missing/incorrect
* wrong log group name
* flow log not active yet (wait a few minutes)
* no traffic generated yet

**Checks**

```bash
aws ec2 describe-flow-logs --flow-log-ids "$FLOW_LOG_ID" --output table
aws iam get-role --role-name "$FLOWLOGS_ROLE_NAME"
aws logs describe-log-groups --log-group-name-prefix "$CW_LOG_GROUP"
```

---

### 2) Flow Logs created but no REJECT records

**Possible causes**

* traffic is not actually reaching the VPC (client-side issue)
* wrong port tested
* security group still allows traffic
* query filter too strict

**Fix**

* test again with `curl`
* verify security group rules
* check both `ACCEPT` and `REJECT`

Quick query:

```sql
fields @timestamp, @message
| sort @timestamp desc
| limit 100
```

---

### 3) CPU alarm not triggering

**Possible causes**

* threshold too high
* not enough load
* not enough time passed (evaluation periods)

**Fix**

* generate more CPU load
* temporarily reduce threshold (for demo only)
* wait for evaluation periods to complete

---

### 4) SNS email not received

**Possible causes**

* subscription not confirmed
* wrong email address

**Fix / Check**

```bash
aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN"
```

Make sure status is not `PendingConfirmation`.

---

### 5) Curl works without port but fails with port (or vice versa)

**Cause**

* app may be listening on a different port than expected
* security group allows only one port

**Fix**

* confirm app port on EC2
* update `APP_PORT`
* verify SG inbound rule matches app port

---

## Cleanup

> Run cleanup after testing to avoid unnecessary cost.

### Step C1 — Delete VPC Flow Logs

```bash
aws ec2 delete-flow-logs --flow-log-ids "$FLOW_LOG_ID"
```

### Step C2 — Delete CloudWatch alarms

```bash
aws cloudwatch delete-alarms \
  --alarm-names "$CPU_ALARM_NAME" "$STATUS_ALARM_NAME"
```

### Step C3 — Delete CloudWatch dashboard

```bash
aws cloudwatch delete-dashboards \
  --dashboard-names "$DASHBOARD_NAME"
```

### Step C4 — Delete SNS topic (subscriptions are deleted with it)

Optional check first:

```bash
aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN"
```

Delete topic:

```bash
aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
```

### Step C5 — Delete CloudWatch log group

```bash
aws logs delete-log-group --log-group-name "$CW_LOG_GROUP"
```

### Step C6 — Delete IAM role policy and role (Flow Logs)

```bash
aws iam delete-role-policy \
  --role-name "$FLOWLOGS_ROLE_NAME" \
  --policy-name "$FLOWLOGS_POLICY_NAME"

aws iam delete-role \
  --role-name "$FLOWLOGS_ROLE_NAME"
```

### Step C7 — Delete EC2 instance and security group (Step 0 resources)

Terminate EC2:

```bash
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
```

Delete security group:

```bash
aws ec2 delete-security-group --group-id "$EC2_SG_ID"
```

Delete local helper files (optional):

```bash
rm -f user-data.sh dashboard.json flowlogs-trust-policy.json flowlogs-permissions-policy.json
```


---




