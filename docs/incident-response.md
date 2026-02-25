# `docs/incident-response.md`

# Incident Response Guide

## Purpose

This document explains a simple incident response process for the cloud projects in this repository.

It is written in a practical way to show how I would handle incidents in an Ops/DevOps role.

---

## Real Ops Scenario

A production issue happens:
- website is down
- users report errors
- CPU is high
- traffic is being rejected
- instance failed
- secret access is broken
- data must be restored

The team needs a calm, repeatable process to reduce downtime.

---

## Incident Response Goals

1. **Protect users / service availability**
2. **Detect and confirm the issue quickly**
3. **Stabilize the system**
4. **Recover normal operation**
5. **Document what happened**
6. **Prevent repeat incidents**

---

## Severity Levels (Simple Model)

### Sev 1 — Critical
- Full outage
- Major customer impact
- No workaround

**Example:** ALB has no healthy targets and website is down.

### Sev 2 — High
- Partial outage or major degradation
- Many users affected
- Workaround may exist

**Example:** One AZ/instance unhealthy but service still partially available.

### Sev 3 — Medium
- Limited impact
- Non-critical function affected
- Monitoring alert without user impact

**Example:** CPU alarm spike but app still responding.

### Sev 4 — Low
- Informational / maintenance issue
- Minimal or no user impact

**Example:** Expected AccessDenied in a security validation test.

---

## Incident Response Lifecycle

## 1) Detect

### How incidents are detected in these projects
- CloudWatch alarms
- SNS email alerts
- ALB health checks
- User-reported issue
- Logs Insights review
- Manual testing (`curl`)

### Example
- CPU alarm email arrives
- ALB target becomes unhealthy
- Logs show REJECT traffic
- App endpoint returns error

---

## 2) Triage (First Assessment)

### Objective
Quickly understand:
- What is broken?
- Who is affected?
- How severe is it?
- Is this ongoing or already recovered?

### Triage Questions
- Is the application fully down or partially degraded?
- Is this one instance or all instances?
- Did a recent change happen?
- Is this security-related?
- Is data at risk?

### Important Rule
Do not make random changes too early.
First confirm the symptom and scope.

---

## 3) Contain / Stabilize

### Objective
Reduce impact fast while continuing investigation.

### Examples in this repo
- Let ASG replace failed EC2 instance
- Revert incorrect security group rule
- Restart application process if stuck
- Use healthy instance(s) behind ALB
- Temporarily scale out if CPU is high
- Restore access for the correct IAM role (least privilege)

### Principle
Prefer the **lowest-risk action** that restores service.

---

## 4) Investigate Root Cause

### Data sources used in these projects
- CloudWatch metrics and graphs
- CloudWatch alarms history
- VPC Flow Logs (ACCEPT/REJECT)
- Logs Insights queries
- EC2 status checks
- Auto Scaling activity history
- IAM identity and policy checks
- Snapshot / backup records

### Examples of root cause categories
- Misconfiguration (security group / route / policy)
- Instance failure
- App process failure
- Permission issue
- Resource exhaustion (CPU/memory)
- Human error (wrong profile, wrong region, wrong command)

---

## 5) Recover

### Objective
Return service to normal and validate functionality.

### Recovery examples in this repo
- New ASG instance becomes healthy behind ALB
- Security rule corrected and traffic shows ACCEPT
- IAM permissions fixed for authorized role only
- Data volume restored from EBS snapshot
- S3 file recovered using versioning

### Validation checklist
- Service endpoint responds correctly
- Metrics trend back to normal
- Alarm state returns to OK
- Logs show expected behavior
- Recovery steps documented

---

## 6) Communicate (Simple Team Model)

Even in a small team, communication matters.

### During incident
Share:
- current symptom
- impact
- mitigation in progress
- ETA (if known) or next checkpoint

### After recovery
Share:
- issue summary
- cause
- resolution
- prevention actions

> In this portfolio repo, communication is simulated through documentation and post-incident notes.

---

## 7) Post-Incident Review (Mini Postmortem)

## Template (simple)
- **Incident title**
- **Date / time detected**
- **Severity**
- **Impact**
- **Detection method** (alarm, user report, logs, etc.)
- **Root cause**
- **Mitigation**
- **Recovery validation**
- **What went well**
- **What needs improvement**
- **Action items**

### Example Action Items
- Add alarm for earlier detection
- Improve IAM policy naming clarity
- Add validation script before deployment
- Add backup restore automation script
- Improve runbook steps/screenshots

---

## Incident Response Examples Mapped to This Repository

### Example 1 — HA Web App Instance Failure
- **Detection:** target unhealthy / app degraded
- **Containment:** ASG replaces instance
- **Recovery:** ALB routes to healthy target
- **Prevention improvement:** add more alarms / startup checks

### Example 2 — Flow Logs REJECT Traffic Investigation
- **Detection:** app test fails / REJECT entries in logs
- **Containment:** confirm if expected security behavior
- **Recovery:** adjust SG/NACL only if valid traffic is blocked
- **Prevention improvement:** document allowed traffic paths clearly

### Example 3 — IAM Secret Access Failure
- **Detection:** AccessDenied
- **Containment:** confirm identity/profile/region
- **Recovery:** fix least-privilege policy for app role only
- **Prevention improvement:** standardize IAM policy templates

### Example 4 — Data Recovery From Snapshot
- **Detection:** missing/corrupted data
- **Containment:** stop risky writes if needed
- **Recovery:** restore volume from snapshot and validate files
- **Prevention improvement:** automate backup checks and restore drills

---

## Operational Habits I Follow (Portfolio Practice)

- Verify identity/account/region before changes
- Make one change at a time during incidents
- Validate results after every fix
- Keep least privilege during emergency changes
- Document what happened (not just what worked)
- Treat recovery testing as part of reliability

---

## What I Would Add in a Larger Production Team

- On-call rotation and escalation policy
- Incident channel templates (Slack/Teams)
- PagerDuty integration
- Service health dashboard / status page
- Automated rollback in CI/CD
- Postmortem tracking and action item ownership
- SLO/SLI-based alerting

---

## Outcome

This incident response guide shows that I do not only deploy infrastructure — I also think about:

- detection
- triage
- recovery
- communication
- prevention

That is a key part of real DevOps / Cloud Operations work.
```

---




