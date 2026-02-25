#!/bin/bash
dnf update -y
dnf install -y jq
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
