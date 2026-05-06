#!/bin/bash

set -e

echo "🚀 VPS BENCHMARK STARTING..."

# -------------------------------
# 1. Install dependencies
# -------------------------------
echo "📦 Installing dependencies..."
apt update -y
apt install -y docker.io docker-compose stress-ng apache2-utils curl

systemctl start docker
systemctl enable docker

# -------------------------------
# 2. Create docker-compose setup
# -------------------------------
echo "🐳 Creating Docker workload..."

cat <<EOF > docker-compose.yml
version: '3.8'

services:

  # 8 FastAPI containers (simulated using nginx)
  fastapi1: { image: nginx, ports: ["8001:80"] }
  fastapi2: { image: nginx, ports: ["8002:80"] }
  fastapi3: { image: nginx, ports: ["8003:80"] }
  fastapi4: { image: nginx, ports: ["8004:80"] }
  fastapi5: { image: nginx, ports: ["8005:80"] }
  fastapi6: { image: nginx, ports: ["8006:80"] }
  fastapi7: { image: nginx, ports: ["8007:80"] }
  fastapi8: { image: nginx, ports: ["8008:80"] }

  django:
    image: nginx
    ports:
      - "8010:80"

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

sleep 20

docker ps

# -------------------------------
# 4. System baseline
# -------------------------------
echo "📊 System baseline:"
free -m
nproc

# -------------------------------
# 5. CPU + Memory stress (background)
# -------------------------------
echo "🔥 Running system stress..."
stress-ng --cpu 6 --vm 2 --vm-bytes 6G --timeout 300s &
STRESS_PID=$!

# -------------------------------
# 6. HTTP Load test (simulate users)
# -------------------------------
echo "🌐 Running HTTP load tests..."

for port in {8001..8008}
do
  echo "Testing FastAPI on port $port"
  ab -n 5000 -c 100 http://127.0.0.1:$port/ &
done

echo "Testing Django"
ab -n 5000 -c 100 http://127.0.0.1:8010/ &

# -------------------------------
# 7. DB stress (Postgres)
# -------------------------------
echo "🗄️ Stressing Postgres..."

docker exec -i $(docker ps -qf "ancestor=postgres:15") \
  bash -c "apt update && apt install -y postgresql-contrib"

docker exec -i $(docker ps -qf "ancestor=postgres:15") \
  bash -c "pgbench -i -U postgres"

docker exec -i $(docker ps -qf "ancestor=postgres:15") \
  bash -c "pgbench -c 20 -T 120 -U postgres" &

# -------------------------------
# 8. Redis stress
# -------------------------------
echo "⚡ Stressing Redis..."

docker exec -i $(docker ps -qf "ancestor=redis:7") \
  redis-benchmark -n 100000 -c 50 &

# -------------------------------
# 9. Monitor for 5 mins
# -------------------------------
echo "📈 Monitoring system for 5 minutes..."

for i in {1..10}
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

echo "✅ BENCHMARK COMPLETE"
