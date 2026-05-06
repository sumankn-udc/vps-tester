#!/bin/bash

set -e

LOG_FILE="vps_benchmark_$(date +%Y%m%d_%H%M%S).log"

echo "🚀 VPS BENCHMARK STARTING..." | tee -a $LOG_FILE

# -------------------------------
# 1. Install dependencies
# -------------------------------
apt update -y >> $LOG_FILE 2>&1
apt install -y docker.io docker-compose stress-ng sysstat fio apache2-utils curl openssl >> $LOG_FILE 2>&1

systemctl start docker
systemctl enable docker

# -------------------------------
# 2. System Info
# -------------------------------
echo "📊 SYSTEM INFO" | tee -a $LOG_FILE
echo "------------------------" >> $LOG_FILE
date >> $LOG_FILE
uname -a >> $LOG_FILE
lscpu >> $LOG_FILE
free -m >> $LOG_FILE
df -h >> $LOG_FILE

# -------------------------------
# 3. Docker Setup
# -------------------------------
cat <<EOF > docker-compose.yml
version: '3.8'
services:
EOF

for i in {1..20}
do
cat <<EOF >> docker-compose.yml
  app$i:
    image: nginx
    ports:
      - "$((8000 + i)):80"
EOF
done

cat <<EOF >> docker-compose.yml

  postgres:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: test

  redis:
    image: redis:7

EOF

docker-compose up -d >> $LOG_FILE 2>&1
sleep 60

# -------------------------------
# 4. CPU COMPUTE LOAD
# -------------------------------
echo "🔥 CPU LOAD START" | tee -a $LOG_FILE

for i in {1..6}
do
  bash -c "while :; do factor \$RANDOM$RANDOM$RANDOM > /dev/null; done" &
done

for i in {1..4}
do
  bash -c "while :; do echo test\$RANDOM | sha256sum > /dev/null; done" &
done

# -------------------------------
# 5. stress-ng
# -------------------------------
stress-ng --cpu 6 --vm 4 --vm-bytes 9G --io 4 --timeout 600s >> $LOG_FILE 2>&1 &
STRESS_PID=$!

# -------------------------------
# 6. HTTP LOAD (capture results)
# -------------------------------
echo "🌐 HTTP TEST" | tee -a $LOG_FILE

for port in {8001..8020}
do
  echo "---- PORT $port ----" >> $LOG_FILE
  ab -n 10000 -c 100 http://127.0.0.1:$port/ >> $LOG_FILE 2>&1 &
done

# -------------------------------
# 7. Postgres benchmark
# -------------------------------
PG_CONTAINER=$(docker ps -qf "ancestor=postgres:15")

until docker exec -e PGPASSWORD=test $PG_CONTAINER pg_isready -U postgres >/dev/null 2>&1; do
  sleep 2
done

echo "🗄️ POSTGRES TEST" | tee -a $LOG_FILE

docker exec -e PGPASSWORD=test -i $PG_CONTAINER \
  pgbench -i -U postgres postgres >> $LOG_FILE 2>&1

docker exec -e PGPASSWORD=test -i $PG_CONTAINER \
  pgbench -c 50 -j 6 -T 180 -U postgres postgres >> $LOG_FILE 2>&1 &

# -------------------------------
# 8. Redis benchmark
# -------------------------------
REDIS_CONTAINER=$(docker ps -qf "ancestor=redis:7")

echo "⚡ REDIS TEST" | tee -a $LOG_FILE

docker exec -i $REDIS_CONTAINER \
  redis-benchmark -n 200000 -c 100 >> $LOG_FILE 2>&1 &

# -------------------------------
# 9. Monitoring snapshots
# -------------------------------
echo "📈 MONITORING START" | tee -a $LOG_FILE

for i in {1..12}
do
  echo "------ SNAPSHOT $i ------" >> $LOG_FILE
  date >> $LOG_FILE
  uptime >> $LOG_FILE
  free -m >> $LOG_FILE
  docker stats --no-stream >> $LOG_FILE
  sleep 30
done

# -------------------------------
# 10. Cleanup
# -------------------------------
echo "🧹 CLEANUP" | tee -a $LOG_FILE

pkill -f factor || true
pkill -f sha256sum || true
kill $STRESS_PID || true

docker-compose down >> $LOG_FILE 2>&1

echo "✅ BENCHMARK COMPLETE" | tee -a $LOG_FILE
echo "📄 LOG FILE: $LOG_FILE"
