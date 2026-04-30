#!/bin/bash
set -euxo pipefail

# ログ
exec > /var/log/mongo-setup.log 2>&1

echo "===== Mongo Setup Start ====="

######################################
# 0. 前提パッケージ
######################################
apt-get update -y
apt-get install -y curl gnupg lsb-release

######################################
# 1. MongoDB 4.0 Repo追加（Ubuntu 20.04でもfocal指定）
######################################
curl -fsSL https://www.mongodb.org/static/pgp/server-4.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-4.0.gpg

echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-4.0.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.0 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-4.0.list

apt-get update -y

######################################
# 2. MongoDB インストール
######################################
DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-org

######################################
# 3. 起動（認証なし）
######################################
systemctl daemon-reexec
systemctl enable mongod
systemctl start mongod

######################################
# 4. 起動待ち
######################################
for i in $(seq 1 30); do
  mongo --eval "db.runCommand({ ping: 1 })" && break
  echo "Waiting for mongod... ($i/30)"
  sleep 2
done

######################################
# 5. ユーザー作成
######################################
mongo admin <<'EOF'
db.createUser({
  user: "adminUser",
  pwd:  "WizAdmin2026!",
  roles: [{ role: "root", db: "admin" }]
});
EOF

mongo wizdb <<'EOF'
db.createUser({
  user: "appUser",
  pwd:  "WizApp2026!",
  roles: [{ role: "readWrite", db: "wizdb" }]
});
EOF

######################################
# 6. 認証有効化 + 外部公開（Wiz用）
######################################
sed -i 's/^  bindIp: .*/  bindIp: 0.0.0.0/' /etc/mongod.conf || true

cat >> /etc/mongod.conf <<'EOF'

security:
  authorization: enabled
EOF

systemctl restart mongod

######################################
# 7. 再起動待ち
######################################
for i in $(seq 1 30); do
  mongo -u adminUser -p "WizAdmin2026!" --authenticationDatabase admin --eval "db.runCommand({ ping: 1 })" && break
  echo "Waiting for mongod auth... ($i/30)"
  sleep 2
done

######################################
# 8. データ投入（デモ用）
######################################
mongo -u appUser -p "WizApp2026!" --authenticationDatabase wizdb wizdb <<'EOF'
db.posts.insertOne({
  text: "Hello from Twizzer! MongoDB is running.",
  createdAt: new Date()
});
EOF

######################################
# 9. バックアップスクリプト
######################################
cat > /usr/local/bin/mongo-backup.sh <<'EOF'
#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/mongo-backup-$TIMESTAMP"

mongodump \
  -u adminUser \
  -p "WizAdmin2026!" \
  --authenticationDatabase admin \
  --out "$BACKUP_DIR"

tar czf "/tmp/mongo-backup-$TIMESTAMP.tar.gz" -C "$BACKUP_DIR" .
rm -rf "$BACKUP_DIR"

# S3（失敗してもOK）
aws s3 cp "/tmp/mongo-backup-$TIMESTAMP.tar.gz" \
  "s3://wiz-backup-eae397b7/backups/mongo-backup-$TIMESTAMP.tar.gz" \
  --region us-west-2 || true

rm -f "/tmp/mongo-backup-$TIMESTAMP.tar.gz"

echo "Backup done: $TIMESTAMP"
EOF

chmod +x /usr/local/bin/mongo-backup.sh

######################################
# 10. cron登録
######################################
echo "0 2 * * * root /usr/local/bin/mongo-backup.sh >> /var/log/mongo-backup.log 2>&1" > /etc/cron.d/mongo-backup
chmod 644 /etc/cron.d/mongo-backup

######################################
# 11. 初回バックアップ（失敗OK）
######################################
/usr/local/bin/mongo-backup.sh || true

echo "===== Mongo Setup Complete ====="