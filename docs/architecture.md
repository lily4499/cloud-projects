

# `docs/architecture.md`


# Cloud Projects Platform Architecture

## Purpose

This document explains the overall architecture pattern used across the projects in this repository.

It shows how the projects connect into one production-style cloud platform story:
- networking foundation
- high availability
- security
- observability
- backup and disaster recovery

---

## Real Ops Scenario

A small company hosts customer-facing applications in AWS.

The Ops/DevOps team must make sure the platform is:

- available during failures
- secure (least privilege + secrets protection)
- monitored (logs, alarms, dashboards)
- recoverable after incidents (backup/restore + DR)

This repository simulates that work using hands-on projects.

---

## High-Level Architecture (Platform View)

```text
Users / Clients
      |
      v
Application Load Balancer (Public)
      |
      v
Auto Scaling EC2 Application Tier (Multi-AZ)
      |
      v
Private Networking Components (secure placement / controlled access)
      |
      v
Monitoring + Logs + Alerts (CloudWatch, SNS, Flow Logs)
      |
      v
Backup / Restore + Disaster Recovery (EBS snapshots, S3 versioning, DR copy)
````

---

## Architecture Layers

## 1) Network Foundation (Production VPC)

**Goal:** build a secure and reusable network layout for applications.

### What is included

* VPC
* Public subnets (for load balancer / NAT)
* Private subnets (for app workloads)
* Route tables
* Internet Gateway (IGW)
* NAT Gateway (for outbound internet from private subnets)

### Why it matters

Without a proper VPC design, backend systems may be exposed to the internet or unable to reach required services securely.

---

## 2) High Availability Compute Layer (HA Web App)

**Goal:** keep the application available if one instance fails.

### What is included

* Launch Template
* Auto Scaling Group (ASG)
* Multi-AZ deployment
* Application Load Balancer (ALB)
* Target Group + health checks

### Why it matters

If one EC2 instance fails, the ASG replaces it automatically and the ALB routes traffic to healthy instances.

---

## 3) Security Layer (IAM + Secrets + Encryption)

**Goal:** protect access and application credentials.

### What is included

* IAM roles for EC2
* Least privilege IAM policies
* AWS Secrets Manager
* KMS encryption for secrets

### Why it matters

Hardcoding credentials in application files is risky. Secrets Manager + IAM roles provides a secure pattern.

---

## 4) Observability Layer (Monitoring + Logs Investigation)

**Goal:** detect incidents early and investigate traffic behavior.

### What is included

* CloudWatch dashboard
* CloudWatch alarms
* SNS notifications
* VPC Flow Logs
* CloudWatch Logs Insights queries

### Why it matters

Ops teams need visibility to answer:

* Is the app healthy?
* Is traffic reaching the server?
* Are connections being rejected?
* Did CPU spike?
* Did the instance fail?

---

## 5) Reliability Layer (Backup / Restore / DR)

**Goal:** recover data and workloads after failures.

### What is included

* EBS snapshots
* Volume restore testing
* S3 versioning for file backups
* Optional cross-region copy (DR thinking)

### Why it matters

Backups are only useful if restore is tested. This project demonstrates both backup creation and recovery validation.

---

## How These Projects Work Together

This repository is organized as separate projects, but they represent one platform lifecycle:

1. **Production VPC** → secure cloud foundation
2. **HA Web App** → resilient workload deployment
3. **IAM + Secrets** → secure access and credentials
4. **Monitoring + Flow Logs** → visibility and investigation
5. **Backup/Restore + DR** → recovery and resilience

This mirrors how real teams build cloud systems step-by-step.

---

## Security & Operations Principles Used

* Least privilege IAM access
* Separation of public and private resources
* Multi-AZ design for higher availability
* Monitoring + alerting before incidents grow
* Backup and restore validation (not backup only)
* Documented runbooks and incident response process

---

## Example Failure Scenarios Covered in This Repo

* EC2 instance terminated unexpectedly → ASG replaces instance
* Security Group misconfiguration blocks traffic → Flow Logs investigation
* Unauthorized IAM user tries to read secret → AccessDenied validation
* Data volume lost / detached → restore from EBS snapshot
* Missing file version → recover from S3 versioning

---

## What I Would Improve in a Full Production Environment (Next Phase)

If this were expanded into a larger production platform, next improvements would include:

* Terraform modules for all projects
* CI/CD pipeline automation for infrastructure and app deployments
* EKS platform for containerized workloads
* Centralized logging across multiple accounts
* WAF in front of ALB
* Route 53 health checks and DNS failover
* Cross-region backup replication automation
* Cost monitoring and tagging policies
* AWS Config / Security Hub / GuardDuty integration

---

## Outcome

This architecture demonstrates a practical production mindset:

* build secure foundations
* design for failure
* monitor everything important
* recover quickly
* document operational procedures

````

---

