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
# 1. MongoDB 4.4 Repo追加
# [変更] 4.0 → 4.4（4.0リポジトリは削除済みで404になるため）
# Ubuntu 22.04向け公式リポジトリは存在しないが、
# focal(20.04)リポジトリはUbuntu 22.04でも動作する
######################################
curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-4.4.gpg

echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-4.4.list

apt-get update -y

######################################
# 2. MongoDB インストール
# [変更] mongoshを追加インストール
# Ubuntu 22.04では旧来の`mongo` shellが廃止されているため
######################################
DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-org mongodb-mongosh

######################################
# 3. 起動（認証なし）
######################################
systemctl daemon-reexec
systemctl enable mongod
systemctl start mongod

######################################
# 4. 起動待ち
# [変更] mongo → mongosh
######################################
for i in $(seq 1 30); do
  mongosh --eval "db.runCommand({ ping: 1 })" && break
  echo "Waiting for mongod... ($i/30)"
  sleep 2
done

######################################
# 5. ユーザー作成
# [変更] mongo → mongosh（2箇所）
######################################
mongosh admin <<'EOF'
db.createUser({
  user: "adminUser",
  pwd:  "WizAdmin2026!",
  roles: [{ role: "root", db: "admin" }]
});
EOF

mongosh wizdb <<'EOF'
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
# [変更] mongo → mongosh
######################################
for i in $(seq 1 30); do
  mongosh -u adminUser -p "WizAdmin2026!" --authenticationDatabase admin --eval "db.runCommand({ ping: 1 })" && break
  echo "Waiting for mongod auth... ($i/30)"
  sleep 2
done

######################################
# 8. データ投入（デモ用）
# [変更] mongo → mongosh
######################################
mongosh -u appUser -p "WizApp2026!" --authenticationDatabase wizdb wizdb <<'EOF'
db.posts.insertOne({
  text: "Hello from Twizzer! MongoDB is running.",
  createdAt: new Date()
});
EOF

######################################
# 9. バックアップスクリプト
# [変更] S3バケット名とリージョンをハードコードから
#        templatefile変数に変更（ec2.tfのtemplatefileと対応）
######################################
cat > /usr/local/bin/mongo-backup.sh <<'BACKUP_EOF'
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
  "s3://${s3_bucket}/backups/mongo-backup-$TIMESTAMP.tar.gz" \
  --region ${aws_region} || true

rm -f "/tmp/mongo-backup-$TIMESTAMP.tar.gz"

echo "Backup done: $TIMESTAMP"
BACKUP_EOF

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