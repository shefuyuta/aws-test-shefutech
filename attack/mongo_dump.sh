#!/bin/bash

MONGO_IP=$1

echo "[+] Dumping MongoDB..."
mongodump --host $MONGO_IP --port 27017 --out ./dump

echo "[+] Data extracted."
