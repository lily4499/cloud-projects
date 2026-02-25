# Backup/Restore + DR Mini Project (AWS)

## Purpose

In this mini project, I show how I protect an application from data loss and how I recover fast when something breaks.

I built a simple **backup / restore + disaster recovery (DR) workflow** on AWS using:

* **EC2** (application server)
* **EBS snapshots** (server disk backup)
* **S3 with versioning** (app backups / files)
* **RDS snapshots** *(optional if using DB)* or backup files to S3
* **Cross-region copy** (basic DR idea)
* **CloudWatch + AWS CLI** for verification

This project is small, but it demonstrates a real Ops mindset:

* backup regularly
* test restore (not just create backups)
* keep a copy in another region
* document the recovery steps (runbook style)

---

## Problem

In real production, backups are often enabled but **restore is never tested**.

That is risky.

### Real Ops Scenario (simple)

I have a small web app running on EC2.
One day:

* someone deletes important files, **or**
* the EC2 instance gets corrupted, **or**
* the database is damaged, **or**
* I lose access to the original region during an incident

If I only say “backup is enabled” but cannot restore quickly, the business still loses time and data.

---

## Solution

I created a mini backup/restore + DR project with these controls:

1. **EBS snapshot backup** for the EC2 data volume
2. **S3 versioning** for backup files and rollback protection
3. **Cross-region copy** of snapshots / backup files for DR
4. **Restore test** (create volume from snapshot and attach to recovery instance)
5. **Documented CLI runbook** with variables (easy to repeat)


---

## Architecture Diagram

![Architecture Diagram](screenshots/architecture.png)

---

## Step-by-step 
> I use **AWS CLI** and simple variables so I can repeat the same steps in another environment.

---

### Step 1 — Set variables (Primary + DR regions)

**Purpose:** Keep commands reusable and avoid hardcoding values.

```bash
# ===== General =====
export PROJECT_NAME="backup-restore-dr-mini"
export ENV="dev"

# ===== Regions =====
export AWS_REGION_PRIMARY="us-east-1"
export AWS_REGION_DR="us-west-2"

# ===== EC2 / EBS =====
export INSTANCE_ID="i-xxxxxxxxxxxxxxxxx"              # existing app EC2
export DATA_DEVICE_NAME="/dev/xvdf"                   # data volume device on EC2
export AVAILABILITY_ZONE_PRIMARY="us-east-1a"

# ===== S3 =====
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export S3_BACKUP_BUCKET="${PROJECT_NAME}-${ENV}-${ACCOUNT_ID}-primary"
export S3_DR_BUCKET="${PROJECT_NAME}-${ENV}-${ACCOUNT_ID}-dr"

# ===== Snapshot tags / names =====
export SNAPSHOT_NAME="${PROJECT_NAME}-${ENV}-data-$(date +%Y%m%d-%H%M%S)"
export DR_COPY_SNAPSHOT_NAME="${PROJECT_NAME}-${ENV}-dr-copy-$(date +%Y%m%d-%H%M%S)"

# ===== Restore test =====
export RESTORE_VOLUME_TYPE="gp3"
export RECOVERY_INSTANCE_NAME="${PROJECT_NAME}-${ENV}-recovery-ec2"
```

**Verify identity**

```bash
aws sts get-caller-identity
```

![Step 1 — AWS identity verified](screenshots/01-aws-sts-identity.png)
*Should show: successful `aws sts get-caller-identity` output with AWS account ID and IAM identity.*

---

### Step 2 — Create S3 backup buckets (primary + DR(Disaster Recovery.))

**Purpose:** Store backup files (app exports, DB dumps, config backups) and enable versioning.

#### 2.1 Create primary bucket

```bash
aws s3api create-bucket \
  --bucket "$S3_BACKUP_BUCKET" \
  --region "$AWS_REGION_PRIMARY"
```

> If primary region is not `us-east-1`, use `--create-bucket-configuration LocationConstraint=<region>`.

#### 2.2 Enable versioning on primary bucket

```bash
aws s3api put-bucket-versioning \
  --bucket "$S3_BACKUP_BUCKET" \
  --versioning-configuration Status=Enabled \
  --region "$AWS_REGION_PRIMARY"
```

#### 2.3 Enable default encryption on primary bucket

```bash
aws s3api put-bucket-encryption \
  --bucket "$S3_BACKUP_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
    }]
  }' \
  --region "$AWS_REGION_PRIMARY"
```

#### 2.4 Create DR bucket

```bash
aws s3api create-bucket \
  --bucket "$S3_DR_BUCKET" \
  --region "$AWS_REGION_DR" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION_DR"
```

#### 2.5 Enable versioning on DR bucket

```bash
aws s3api put-bucket-versioning \
  --bucket "$S3_DR_BUCKET" \
  --versioning-configuration Status=Enabled \
  --region "$AWS_REGION_DR"
```

![Step 2 — S3 primary bucket versioning enabled](screenshots/02-s3-primary-bucket-versioning.png)
*Should show: primary S3 bucket exists and Versioning = Enabled.*

---

![Step 2 — S3 DR bucket versioning enabled](screenshots/03-s3-dr-bucket-versioning.png)
*Should show: DR S3 bucket in DR region with Versioning = Enabled.*

---

### Step 3 — Create sample app backup file and upload to S3

**Purpose:** Simulate a real app backup (config export / DB dump / tar file).

```bash
mkdir -p backups
echo "Backup created at $(date)" > backups/app-backup.txt
echo "Environment: $ENV" >> backups/app-backup.txt
echo "Project: $PROJECT_NAME" >> backups/app-backup.txt

aws s3 cp backups/app-backup.txt "s3://$S3_BACKUP_BUCKET/app/app-backup.txt" \
  --region "$AWS_REGION_PRIMARY"
```

#### 3.1 Simulate accidental overwrite (to test S3 versioning later)

```bash
echo "BAD CHANGE - overwritten file" > backups/app-backup.txt

aws s3 cp backups/app-backup.txt "s3://$S3_BACKUP_BUCKET/app/app-backup.txt" \
  --region "$AWS_REGION_PRIMARY"
```

![Step 3 — Backup file uploaded to S3](screenshots/04-s3-uploaded-backup-file.png)
*Should show: `app/app-backup.txt` present in the primary S3 bucket.*

---

### Step 4 — Find the EC2 data volume attached to the app server

**Purpose:** Identify the correct EBS volume to snapshot.

```bash
aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION_PRIMARY" \
  --query 'Reservations[].Instances[].BlockDeviceMappings[]'
```

If you know the device name, get the volume ID:

```bash
export DATA_VOLUME_ID=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION_PRIMARY" \
  --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" \
  --output text)

echo "$DATA_VOLUME_ID"
```

![Step 4 — EC2 data volume identified](screenshots/05-ebs-volume-id-from-instance.png)
*Should show: EC2 block device mappings and the selected data volume ID.*

---

### Step 5 — Create EBS snapshot (backup)

**Purpose:** Back up the EC2 data disk so I can restore later.

```bash
export SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --volume-id "$DATA_VOLUME_ID" \
  --description "$SNAPSHOT_NAME" \
  --region "$AWS_REGION_PRIMARY" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=$SNAPSHOT_NAME},{Key=Project,Value=$PROJECT_NAME},{Key=Env,Value=$ENV}]" \
  --query 'SnapshotId' \
  --output text)

echo "$SNAPSHOT_ID"
```

Wait until snapshot completes:

```bash
aws ec2 wait snapshot-completed \
  --snapshot-ids "$SNAPSHOT_ID" \
  --region "$AWS_REGION_PRIMARY"

echo "Snapshot completed: $SNAPSHOT_ID"
```

![Step 5 — EBS snapshot completed](screenshots/06-ebs-snapshot-completed.png)
*Should show: snapshot in primary region with state = `completed`.*

---

### Step 6 — Copy EBS snapshot to DR region (mini DR)

**Purpose:** Keep a backup copy in another region in case the primary region has a major issue.

```bash
export DR_SNAPSHOT_ID=$(aws ec2 copy-snapshot \
  --source-region "$AWS_REGION_PRIMARY" \
  --source-snapshot-id "$SNAPSHOT_ID" \
  --description "$DR_COPY_SNAPSHOT_NAME" \
  --region "$AWS_REGION_DR" \
  --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=$DR_COPY_SNAPSHOT_NAME},{Key=Project,Value=$PROJECT_NAME},{Key=Env,Value=$ENV}]" \
  --query 'SnapshotId' \
  --output text)

echo "$DR_SNAPSHOT_ID"
```

Wait in DR region:

```bash
aws ec2 wait snapshot-completed \
  --snapshot-ids "$DR_SNAPSHOT_ID" \
  --region "$AWS_REGION_DR"

echo "DR snapshot copy completed: $DR_SNAPSHOT_ID"
```

![Step 6 — DR snapshot copy completed](screenshots/07-ebs-snapshot-copy-dr-completed.png)
*Should show: copied snapshot exists in DR region and state = `completed`.*
![alt text](image.png)
---

### Step 7 — Copy backup file to DR S3 bucket

**Purpose:** Keep application backup files in DR region too.

```bash
aws s3 cp "s3://$S3_BACKUP_BUCKET/app/app-backup.txt" "s3://$S3_DR_BUCKET/app/app-backup.txt" \
  --source-region "$AWS_REGION_PRIMARY" \
  --region "$AWS_REGION_DR"
```

![Step 7 — Backup file copied to DR S3 bucket](screenshots/08-s3-dr-file-copy.png)
*Should show: `app/app-backup.txt` exists in the DR S3 bucket.*

---

### Step 8 — Restore test (EBS): create a volume from the snapshot

**Purpose:** Prove that backup is usable (real recovery test).

```bash
export RESTORED_VOLUME_ID=$(aws ec2 create-volume \
  --snapshot-id "$SNAPSHOT_ID" \
  --availability-zone "$AVAILABILITY_ZONE_PRIMARY" \
  --volume-type "$RESTORE_VOLUME_TYPE" \
  --region "$AWS_REGION_PRIMARY" \
  --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${PROJECT_NAME}-${ENV}-restored-volume},{Key=Project,Value=$PROJECT_NAME},{Key=Env,Value=$ENV}]" \
  --query 'VolumeId' \
  --output text)

echo "$RESTORED_VOLUME_ID"
```

Wait until available:

```bash
aws ec2 wait volume-available \
  --volume-ids "$RESTORED_VOLUME_ID" \
  --region "$AWS_REGION_PRIMARY"

echo "Restored volume is ready: $RESTORED_VOLUME_ID"
```

![Step 8 — Restored EBS volume created](screenshots/09-restored-volume-created.png)
*Should show: new EBS volume created from snapshot with state = `available`.*


---

### Step 9 — Attach restored volume to a recovery EC2 (test)

**Purpose:** Mount the restored volume and verify files/data are present.

> Use a separate recovery instance for testing.
> If you already have one, set its instance ID below.

```bash
export RECOVERY_INSTANCE_ID="i-0e0cc89bc74601cb8"   # existing recovery/test EC2
export RECOVERY_DEVICE_NAME="/dev/xvdg"

aws ec2 attach-volume \
  --volume-id "$RESTORED_VOLUME_ID" \
  --instance-id "$RECOVERY_INSTANCE_ID" \
  --device "$RECOVERY_DEVICE_NAME" \
  --region "$AWS_REGION_PRIMARY"
```

**Then connect (SSM or SSH) and verify filesystem/data on the attached disk.**

Example verification commands on the EC2 instance:

```bash
lsblk
sudo mkdir -p /mnt/recovery
# File system may already exist; adjust device path if needed
sudo mount -o ro,nouuid /dev/nvme1n1p1 /mnt/recovery
ls -lah /mnt/recovery
```

![Step 9 — Restored volume attached to recovery EC2](screenshots/10-volume-attached-recovery-ec2.png)
*Should show: restored volume attached to the recovery/test EC2 instance.*
---
![Step 9 — Mounted recovery volume and files visible](screenshots/11-mounted-recovery-volume-files.png)
*Should show: `lsblk` output and files visible under `/mnt/recovery`.*

---

### Step 10 — Restore test (S3 versioning rollback)

**Purpose:** Prove I can recover from accidental file overwrite.

List versions:

```bash
aws s3api list-object-versions \
  --bucket "$S3_BACKUP_BUCKET" \
  --prefix "app/app-backup.txt" \
  --region "$AWS_REGION_PRIMARY"
```

Download the file to check current content:

```bash
aws s3 cp "s3://$S3_BACKUP_BUCKET/app/app-backup.txt" ./restored-current.txt \
  --region "$AWS_REGION_PRIMARY"

cat restored-current.txt
```

Find the older version ID (good version), then restore it by copying that specific version:

```bash
export GOOD_VERSION_ID="yRhEjxvkQu6xvZZ5oIlg3ixiHBRy9s1s"

aws s3api get-object \
  --bucket "$S3_BACKUP_BUCKET" \
  --key "app/app-backup.txt" \
  --version-id "$GOOD_VERSION_ID" \
  ./restored-good-version.txt \
  --region "$AWS_REGION_PRIMARY"

cat restored-good-version.txt
```

(Optional) Put the good version back as current:

```bash
aws s3 cp ./restored-good-version.txt "s3://$S3_BACKUP_BUCKET/app/app-backup.txt" \
  --region "$AWS_REGION_PRIMARY"
```

![Step 10 — S3 object versions listed](screenshots/12-s3-object-versions.png)
*Should show: multiple versions for `app/app-backup.txt` (good + overwritten version).*


---
![Step 10 — S3 rollback restored good version](screenshots/13-s3-rollback-restored-good-version.png)
*Should show: restored file content is the original good version.*


---

## Outcome

By the end of this project, I can clearly demonstrate:

* how I back up EC2 data (EBS snapshots)
* how I store backup files safely (S3 + versioning)
* how I prepare for DR (cross-region copy)
* how I test restores (volume restore + file rollback)
* how I document recovery steps for a real incident

This is the kind of project that shows I am not just deploying systems — I am also thinking about **recovery, resilience, and operations**.

---

## Troubleshooting

### 1) `create-bucket` fails in non-`us-east-1`

**Cause:** Missing `LocationConstraint`
**Fix:** Add:

```bash
--create-bucket-configuration LocationConstraint="$AWS_REGION_DR"
```

---

### 2) Snapshot creation works but restore volume fails in wrong AZ

**Cause:** EBS volume must be created in an AZ in the same region and then attached to an EC2 in the same AZ
**Fix:** Use the correct AZ for the recovery EC2 and restored volume

---

### 3) `attach-volume` fails

**Cause:** Wrong instance ID, wrong device name, or instance/AZ mismatch
**Fix:**

* verify recovery instance ID
* verify instance AZ
* verify restored volume AZ
* choose a valid device name like `/dev/xvdg`

---

### 4) Volume attached but mount fails

**Cause:** Wrong partition/device path, filesystem issue, or unformatted disk
**Fix:**

```bash
lsblk
sudo file -s /dev/xvdg
# Try partition device:
sudo mount /dev/xvdg1 /mnt/recovery
```

---

### 5) Cannot restore S3 previous version

**Cause:** Using wrong version ID or versioning was not enabled before overwrite
**Fix:**

* confirm versioning is enabled
* run `list-object-versions`
* copy the correct version ID

---

### 6) `copy-snapshot` permission/KMS issue (if encrypted snapshots)

**Cause:** KMS key permissions not configured for cross-region copy
**Fix:** Start with SSE-S3 / unencrypted lab snapshot for demo, then document KMS key policy requirements for production

---

## Cleanup

> Run cleanup after testing to avoid extra cost.

### 1) Detach and delete restored test volume

```bash
aws ec2 detach-volume \
  --volume-id "$RESTORED_VOLUME_ID" \
  --region "$AWS_REGION_PRIMARY"

aws ec2 wait volume-available \
  --volume-ids "$RESTORED_VOLUME_ID" \
  --region "$AWS_REGION_PRIMARY"

aws ec2 delete-volume \
  --volume-id "$RESTORED_VOLUME_ID" \
  --region "$AWS_REGION_PRIMARY"
```

### 2) Delete snapshots (primary + DR)

```bash
aws ec2 delete-snapshot \
  --snapshot-id "$SNAPSHOT_ID" \
  --region "$AWS_REGION_PRIMARY"

aws ec2 delete-snapshot \
  --snapshot-id "$DR_SNAPSHOT_ID" \
  --region "$AWS_REGION_DR"
```

### 3) Remove S3 objects and buckets

```bash
aws s3 rm "s3://$S3_BACKUP_BUCKET" --recursive --region "$AWS_REGION_PRIMARY"
aws s3 rm "s3://$S3_DR_BUCKET" --recursive --region "$AWS_REGION_DR"

aws s3api delete-bucket --bucket "$S3_BACKUP_BUCKET" --region "$AWS_REGION_PRIMARY"
aws s3api delete-bucket --bucket "$S3_DR_BUCKET" --region "$AWS_REGION_DR"
```

---

