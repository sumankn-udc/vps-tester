#!/bin/bash

set -e

echo "🚀 HEAVY VPS BENCHMARK STARTING..."

# -------------------------------
# 1. Install dependencies
# -------------------------------
apt update -y
apt install -y docker.io docker-compose stress-ng sysstat fio apache2-utils curl

systemctl start docker
systemctl enable docker

# -------------------------------
# 2. Generate docker-compose dynamically (20 servers)
# -------------------------------
echo "🐳 Creating 20 app containers..."

cat <<EOF > docker-compose.yml
version: '3.8'

services:
EOF

# Create 20 app containers (simulate FastAPI/Django)
for i in {1..20}
do
cat <<EOF >> docker-compose.yml
  app$i:
    image: nginx
    ports:
      - "$((8000 + i)):80"
EOF
done

# Add core services
cat <<EOF >> docker-compose.yml

  postgres:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: test
    ports:
      - "5432:5432"

  redis:
    image: redis:7
    ports:
      - "6379:6379"

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    command: start-dev
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin
    ports:
      - "8080:8080"

  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"

EOF

# -------------------------------
# 3. Start containers
# -------------------------------
echo "🚀 Starting containers..."
docker-compose up -d

echo "⏳ Waiting for services..."
sleep 60

docker ps

# -------------------------------
# 4. System baseline
# -------------------------------
echo "📊 System baseline:"
free -m
nproc

# -------------------------------
# 5. CPU + Memory stress
# -------------------------------
echo "🔥 Running system stress..."
stress-ng --cpu 6 --vm 3 --vm-bytes 8G --timeout 600s &
STRESS_PID=$!

# -------------------------------
# 6. HTTP Load test (10k requests per server)
# -------------------------------
echo "🌐 Running heavy HTTP load..."

for port in {8001..8020}
do
  echo "➡️ Hitting port $port"
  ab -n 10000 -c 100 http://127.0.0.1:$port/ &
done

# -------------------------------
# 7. Postgres stress
# -------------------------------
echo "🗄️ Preparing Postgres..."

PG_CONTAINER=$(docker ps -qf "ancestor=postgres:15")

until docker exec -e PGPASSWORD=test $PG_CONTAINER pg_isready -U postgres >/dev/null 2>&1; do
  echo "⏳ Waiting for Postgres..."
  sleep 2
done

echo "✅ Postgres ready"

docker exec -e PGPASSWORD=test -i $PG_CONTAINER \
  pgbench -i -U postgres postgres

docker exec -e PGPASSWORD=test -i $PG_CONTAINER \
  pgbench -c 40 -j 4 -T 180 -U postgres postgres &

# -------------------------------
# 8. Redis stress
# -------------------------------
echo "⚡ Stressing Redis..."

REDIS_CONTAINER=$(docker ps -qf "ancestor=redis:7")

docker exec -i $REDIS_CONTAINER \
  redis-benchmark -n 200000 -c 100 &

# -------------------------------
# 9. Monitoring
# -------------------------------
echo "📈 Monitoring system..."

for i in {1..12}
do
  echo "------ SNAPSHOT $i ------"
  uptime
  free -m
  docker stats --no-stream
  sleep 30
done

# -------------------------------
# 10. Cleanup
# -------------------------------
echo "🧹 Cleaning up..."

kill $STRESS_PID || true
docker-compose down

echo "✅ HEAVY BENCHMARK COMPLETE"
