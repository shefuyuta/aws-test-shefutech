#!/bin/bash
set -ex
exec > /var/log/mongo-setup.log 2>&1

######################################
# 1. MongoDB 4.0 Repository
######################################
cat > /etc/yum.repos.d/mongodb-org-4.0.repo << 'REPO'
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.0.asc
REPO

######################################
# 2. Install MongoDB 4.0
######################################
yum install -y mongodb-org

######################################
# 3. Start MongoDB (no auth first)
######################################
systemctl start mongod
systemctl enable mongod

# Wait for mongod to be ready
for i in $(seq 1 30); do
  mongo --eval "db.runCommand({ ping: 1 })" && break
  echo "Waiting for mongod to start... ($i/30)"
  sleep 2
done

######################################
# 4. Create admin user + app user
######################################
mongo admin << MONGOEOF
db.createUser({
  user: "${mongo_admin_user}",
  pwd:  "${mongo_admin_pass}",
  roles: [{ role: "root", db: "admin" }]
});
MONGOEOF

mongo ${mongo_app_db} << MONGOEOF
db.createUser({
  user: "${mongo_app_user}",
  pwd:  "${mongo_app_pass}",
  roles: [{ role: "readWrite", db: "${mongo_app_db}" }]
});
MONGOEOF

######################################
# 5. Enable authentication
######################################
cat >> /etc/mongod.conf << 'AUTHCONF'

security:
  authorization: enabled
AUTHCONF

# Bind to all interfaces (needed for K8s access)
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

systemctl restart mongod

# Wait for restart
for i in $(seq 1 30); do
  mongo -u "${mongo_admin_user}" -p "${mongo_admin_pass}" --authenticationDatabase admin --eval "db.runCommand({ ping: 1 })" && break
  sleep 2
done

######################################
# 6. Insert seed data (demo用)
######################################
mongo -u "${mongo_app_user}" -p "${mongo_app_pass}" --authenticationDatabase "${mongo_app_db}" ${mongo_app_db} << MONGOEOF
db.posts.insertOne({
  text: "Hello from Twizzer! MongoDB is running.",
  createdAt: new Date()
});
MONGOEOF

######################################
# 7. Daily backup cron → S3
######################################
cat > /usr/local/bin/mongo-backup.sh << 'BACKUP'
#!/bin/bash
set -e
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/mongo-backup-$$TIMESTAMP"

mongodump \
  -u "${mongo_admin_user}" \
  -p "${mongo_admin_pass}" \
  --authenticationDatabase admin \
  --out "$$BACKUP_DIR"

tar czf "/tmp/mongo-backup-$$TIMESTAMP.tar.gz" -C "$$BACKUP_DIR" .
rm -rf "$$BACKUP_DIR"

aws s3 cp \
  "/tmp/mongo-backup-$$TIMESTAMP.tar.gz" \
  "s3://${s3_bucket}/backups/mongo-backup-$$TIMESTAMP.tar.gz" \
  --region ${aws_region}

rm -f "/tmp/mongo-backup-$$TIMESTAMP.tar.gz"

echo "[$(date)] Backup completed: mongo-backup-$$TIMESTAMP.tar.gz"
BACKUP

chmod +x /usr/local/bin/mongo-backup.sh

# Run first backup immediately
/usr/local/bin/mongo-backup.sh || echo "Initial backup failed (S3 may not be ready)"

# Schedule daily backup at 2:00 AM
echo "0 2 * * * root /usr/local/bin/mongo-backup.sh >> /var/log/mongo-backup.log 2>&1" > /etc/cron.d/mongo-backup
chmod 644 /etc/cron.d/mongo-backup

echo "[$(date)] MongoDB setup complete."
