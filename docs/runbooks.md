# `docs/runbooks.md`

# Operations Runbooks

## Purpose

This file contains simple operational runbooks for common incidents and maintenance tasks related to the projects in this repository.

The goal is to show how I would respond in a real Ops/DevOps environment using a repeatable process.

---

## How to Use These Runbooks

Each runbook follows the same pattern:

1. **Trigger / Symptom** (what happened)
2. **Checks** (what to verify first)
3. **Investigation** (where to look)
4. **Mitigation** (how to stabilize service)
5. **Recovery / Validation** (confirm issue is resolved)
6. **Post-Incident Notes** (what to document)

---

# Runbook 1 — EC2 Instance Failure (HA Web App)

## Trigger / Symptom
- Website becomes slow or partially unavailable
- One target in ALB target group shows unhealthy
- CloudWatch alarm (if configured) triggers
- EC2 instance stopped/terminated unexpectedly

## Immediate Goal
Keep the application available and confirm Auto Scaling recovers capacity.

## Checks
1. Check ALB target group health
2. Check Auto Scaling Group desired / current / healthy count
3. Check EC2 instance state(s)
4. Check recent scaling activities

## Investigation
- Confirm whether failure is isolated to one instance or all instances
- Review instance status checks
- Review user-data / app startup logs (if needed)
- Confirm security group and target group health check path/port are correct

## Mitigation
- If ASG is healthy and replacing automatically, monitor only (do not manually interfere too early)
- If ASG is not replacing instance:
  - verify launch template configuration
  - verify subnets and instance profile
  - verify security group rules
  - verify AMI / user-data startup success

## Recovery / Validation
- New EC2 instance launches successfully
- ALB target group shows healthy target(s)
- Application returns HTTP 200/expected response
- Traffic flows normally

## Post-Incident Notes
Document:
- what failed
- detection time
- recovery time
- root cause (if known)
- preventive fix (if needed)

---

# Runbook 2 — High CPU Alarm on EC2 (Monitoring Project)

## Trigger / Symptom
- CloudWatch CPU alarm enters ALARM state
- SNS email notification received
- Application becomes slow

## Immediate Goal
Determine if CPU spike is expected load or a problem (runaway process / attack / bad deployment).

## Checks
1. Confirm alarm details (metric, threshold, duration)
2. Check EC2 CPUUtilization metric graph
3. Check application availability (curl / browser)
4. Confirm whether this is one instance or all instances

## Investigation
- Check process usage on the EC2 instance (top / htop if available)
- Review application logs
- Check recent deployments or config changes
- Check traffic pattern (normal burst vs suspicious traffic)
- Review Flow Logs / ALB access logs (if enabled)

## Mitigation
Possible actions depending on cause:
- Restart misbehaving application process
- Scale out (if ASG is used)
- Block suspicious traffic (security group/WAF in larger setup)
- Roll back recent change
- Increase instance size temporarily (short-term only)

## Recovery / Validation
- CPU returns below threshold
- Alarm returns to OK
- App response times improve
- No ongoing error spikes

## Post-Incident Notes
Record:
- cause of CPU spike
- actions taken
- whether alarm threshold tuning is needed

---

# Runbook 3 — VPC Flow Logs Show REJECT Traffic

## Trigger / Symptom
- Logs Insights shows `REJECT` traffic
- Application is unreachable from expected source
- Security test intentionally failed (simulation)

## Immediate Goal
Identify whether REJECT traffic is expected (good security) or a real misconfiguration blocking valid traffic.

## Checks
1. Confirm source and destination IPs
2. Confirm destination port (e.g., 80, 443, 22, app port)
3. Confirm EC2 private IP
4. Confirm security group rules
5. Confirm NACL rules (if custom NACLs are used)

## Investigation
- Run Logs Insights query for `REJECT`
- Filter logs by EC2 private IP
- Compare allowed ports in Security Group
- Check if traffic should be allowed from ALB only or internet directly
- Verify route tables if connectivity path is broken

## Mitigation
- If valid traffic is blocked: update Security Group/NACL rule safely
- If invalid traffic is blocked: no change needed (expected protective behavior)
- Re-test with `curl` after changes

## Recovery / Validation
- Expected traffic shows `ACCEPT`
- Application reachable (if it should be)
- No unnecessary ports opened

## Post-Incident Notes
Document:
- which rule blocked traffic
- whether block was expected
- final secure rule design

---

# Runbook 4 — IAM AccessDenied for Secret Read (IAM + Secrets Project)

## Trigger / Symptom
- `aws secretsmanager get-secret-value` returns `AccessDenied`
- Application cannot read a required secret
- Test user intentionally denied access (security validation)

## Immediate Goal
Verify whether AccessDenied is expected (least privilege test) or a real permission issue.

## Checks
1. Confirm caller identity (`aws sts get-caller-identity`)
2. Confirm correct AWS profile / role is being used
3. Confirm secret name and region are correct
4. Review IAM policy attached to user/role
5. Review KMS permissions (if customer-managed KMS key is used)

## Investigation
Common causes:
- Wrong AWS profile configured locally
- IAM policy missing `secretsmanager:GetSecretValue`
- IAM policy resource ARN mismatch
- KMS key policy / decrypt permission missing
- Secret is in another region

## Mitigation
- If test user should be denied: no fix needed (test passed)
- If app role should be allowed:
  - add least-privilege secret read permission
  - add KMS decrypt permission (if needed)
  - verify resource ARN scope is correct

## Recovery / Validation
- Authorized role can read secret successfully
- Unauthorized user still receives AccessDenied
- Secret remains encrypted and access is controlled

## Post-Incident Notes
Document:
- expected vs actual behavior
- policy fix applied
- verification result

---

# Runbook 5 — Restore Data from EBS Snapshot (Backup / DR Project)

## Trigger / Symptom
- Files on EC2 volume are lost/corrupted
- EC2 instance replaced and data volume missing
- Recovery simulation / DR test is being performed

## Immediate Goal
Restore data quickly and validate integrity.

## Checks
1. Identify correct snapshot ID
2. Confirm region (primary or DR copy region)
3. Confirm target availability zone
4. Confirm recovery EC2 instance exists (if attaching restored volume)
5. Confirm device name for attachment

## Investigation
- Verify latest snapshot completion state
- Check snapshot tags / naming convention
- Confirm original volume size and type
- Confirm file path expected after mount

## Mitigation / Recovery Steps (summary)
1. Create volume from snapshot
2. Attach restored volume to recovery EC2
3. Mount the volume on the instance
4. Verify files exist and are readable
5. (Optional) Copy recovered files back to production path

## Recovery / Validation
- Restored volume attaches successfully
- Mount succeeds
- Expected files are present
- File contents match backup expectation

## Post-Incident Notes
Document:
- snapshot used
- restore duration
- data verified
- any manual steps that should be automated later

---

# Runbook 6 — S3 Backup File Recovery Using Versioning

## Trigger / Symptom
- Backup file overwritten or deleted in S3
- Need previous version of file

## Immediate Goal
Recover the correct version quickly.

## Checks
1. Confirm bucket name
2. Confirm object key
3. List object versions
4. Identify required version ID

## Investigation
- Compare timestamps and object sizes
- Confirm latest vs previous version
- Confirm region and permissions

## Mitigation / Recovery
- Download the needed object version
- Or copy the previous version back as current
- Verify file content after recovery

## Recovery / Validation
- Correct version restored
- Application/ops file usable again
- Versioning remains enabled for future recovery

## Post-Incident Notes
Record:
- cause (overwrite/delete)
- recovered version ID
- prevention improvement (access controls / naming policy)

---

## Runbook Writing Principles Used in This Repo

- Keep steps simple and repeatable
- Validate before making changes
- Prefer least-risk mitigation first
- Document what happened after recovery
- Improve the process after each incident

---

## Outcome

These runbooks show operational readiness beyond deployment:
- detection
- investigation
- mitigation
- recovery
- documentation
````

---

