#!/bin/bash

set -e

echo "🚀 ULTRA VPS BENCHMARK STARTING..."

# -------------------------------
# 1. Install dependencies
# -------------------------------
apt update -y
apt install -y docker.io docker-compose stress-ng sysstat fio apache2-utils curl openssl

systemctl start docker
systemctl enable docker

# -------------------------------
# 2. Create docker-compose (20 apps)
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

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    command: start-dev
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin

EOF

# -------------------------------
# 3. Start containers
# -------------------------------
docker-compose up -d
sleep 60

# -------------------------------
# 4. CPU INTENSIVE COMPUTE LOAD 🔥
# -------------------------------
echo "🔥 Starting heavy compute load..."

# Prime number calculations (CPU heavy)
for i in {1..6}
do
  bash -c "while :; do factor \$RANDOM$RANDOM$RANDOM > /dev/null; done" &
done

# SHA256 hashing loop (real-world compute)
for i in {1..4}
do
  bash -c "while :; do echo 'data'$RANDOM | sha256sum > /dev/null; done" &
done

# Compression workload
for i in {1..2}
do
  bash -c "while :; do dd if=/dev/urandom bs=1M count=50 2>/dev/null | gzip > /dev/null; done" &
done

# -------------------------------
# 5. stress-ng mixed load
# -------------------------------
stress-ng --cpu 6 --vm 4 --vm-bytes 9G --io 4 --timeout 600s &
STRESS_PID=$!

# -------------------------------
# 6. HTTP LOAD (10k x 20 servers)
# -------------------------------
echo "🌐 HTTP load..."

for port in {8001..8020}
do
  ab -n 10000 -c 100 http://127.0.0.1:$port/ &
done

# -------------------------------
# 7. Postgres load
# -------------------------------
PG_CONTAINER=$(docker ps -qf "ancestor=postgres:15")

until docker exec -e PGPASSWORD=test $PG_CONTAINER pg_isready -U postgres >/dev/null 2>&1; do
  sleep 2
done

docker exec -e PGPASSWORD=test -i $PG_CONTAINER \
  pgbench -i -U postgres postgres

docker exec -e PGPASSWORD=test -i $PG_CONTAINER \
  pgbench -c 50 -j 6 -T 300 -U postgres postgres &

# -------------------------------
# 8. Redis load
# -------------------------------
REDIS_CONTAINER=$(docker ps -qf "ancestor=redis:7")

docker exec -i $REDIS_CONTAINER \
  redis-benchmark -n 300000 -c 150 &

# -------------------------------
# 9. LIVE MONITORING
# -------------------------------
echo "📊 Monitoring..."

for i in {1..15}
do
  echo "------ SNAPSHOT $i ------"
  uptime
  free -m
  docker stats --no-stream
  sleep 20
done

# -------------------------------
# 10. Cleanup
# -------------------------------
echo "🧹 Cleaning up..."

pkill -f factor || true
pkill -f sha256sum || true
pkill -f gzip || true
kill $STRESS_PID || true

docker-compose down

echo "✅ ULTRA TEST COMPLETE"
