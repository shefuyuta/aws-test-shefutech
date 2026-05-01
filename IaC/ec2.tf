#!/bin/bash
set -euxo pipefail

exec > /var/log/mongo-setup.log 2>&1

echo "===== Mongo Setup Start ====="

######################################
# 0. 前提パッケージ + AWS CLI
######################################
apt-get update -y
apt-get install -y curl gnupg lsb-release wget awscli

######################################
# 1. libssl1.1インストール（Ubuntu 22.04でMongoDB 4.4に必要）
######################################
wget -q http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb

######################################
# 2. MongoDB 4.4 リポジトリ追加
######################################
curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-4.4.gpg

echo "deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-4.4.list

apt-get update -y

######################################
# 3. MongoDB インストール
######################################
DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-org

######################################
# 4. bindIp変更（認証有効化前に設定）
######################################
sed -i 's/^  bindIp: .*/  bindIp: 0.0.0.0/' /etc/mongod.conf

######################################
# 5. 起動（認証なし）
######################################
systemctl daemon-reexec
systemctl enable mongod
systemctl start mongod

######################################
# 6. 起動待ち
######################################
for i in $(seq 1 30); do
  mongo --eval "db.runCommand({ ping: 1 })" && break
  echo "Waiting for mongod... ($i/30)"
  sleep 2
done

######################################
# 7. ユーザー作成
######################################
mongo admin <<EOF
db.createUser({
  user: "${mongo_admin_user}",
  pwd:  "${mongo_admin_pass}",
  roles: [{ role: "root", db: "admin" }]
});
EOF

mongo "${mongo_app_db}" <<EOF
db.createUser({
  user: "${mongo_app_user}",
  pwd:  "${mongo_app_pass}",
  roles: [{ role: "readWrite", db: "${mongo_app_db}" }]
});
EOF

######################################
# 8. 認証有効化
######################################
cat >> /etc/mongod.conf <<'MONGOCNF'

security:
  authorization: enabled
MONGOCNF

systemctl restart mongod

######################################
# 9. 再起動待ち
######################################
for i in $(seq 1 30); do
  mongo -u "${mongo_admin_user}" -p "${mongo_admin_pass}" --authenticationDatabase admin --eval "db.runCommand({ ping: 1 })" && break
  echo "Waiting for mongod auth... ($i/30)"
  sleep 2
done

######################################
# 10. データ投入（デモ用）
######################################
mongo -u "${mongo_app_user}" -p "${mongo_app_pass}" --authenticationDatabase "${mongo_app_db}" "${mongo_app_db}" <<'EOF'
db.posts.insertOne({
  text: "Hello from Twizzer! MongoDB is running.",
  createdAt: new Date()
});
EOF

######################################
# 11. バックアップスクリプト
######################################
cat > /usr/local/bin/mongo-backup.sh <<BACKUP_EOF
#!/bin/bash
set -e

TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/mongo-backup-\$TIMESTAMP"

mongodump \
  -u ${mongo_admin_user} \
  -p "${mongo_admin_pass}" \
  --authenticationDatabase admin \
  --out "\$BACKUP_DIR"

tar czf "/tmp/mongo-backup-\$TIMESTAMP.tar.gz" -C "\$BACKUP_DIR" .
rm -rf "\$BACKUP_DIR"

/usr/bin/aws s3 cp "/tmp/mongo-backup-\$TIMESTAMP.tar.gz" \
  "s3://${s3_bucket}/backups/mongo-backup-\$TIMESTAMP.tar.gz" \
  --region ${aws_region} || true

rm -f "/tmp/mongo-backup-\$TIMESTAMP.tar.gz"

echo "Backup done: \$TIMESTAMP"
BACKUP_EOF

chmod +x /usr/local/bin/mongo-backup.sh

######################################
# 12. cron登録
######################################
echo "0 2 * * * root /usr/local/bin/mongo-backup.sh >> /var/log/mongo-backup.log 2>&1" > /etc/cron.d/mongo-backup
chmod 644 /etc/cron.d/mongo-backup

######################################
# 13. 初回バックアップ
######################################
/usr/local/bin/mongo-backup.sh || true

echo "===== Mongo Setup Complete ====="