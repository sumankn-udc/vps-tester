#!/bin/bash

LOG_FILE="cpu_disk_eval_$(date +%Y%m%d_%H%M%S).log"

echo "🚀 CPU + DISK EVALUATION START" | tee -a $LOG_FILE
echo "---------------------------------" | tee -a $LOG_FILE

# -------------------------------
# 1. CPU INFO
# -------------------------------
echo -e "\n🧠 CPU INFO" | tee -a $LOG_FILE
lscpu | tee -a $LOG_FILE

echo -e "\n🔥 CPU FREQUENCY" | tee -a $LOG_FILE
grep "MHz" /proc/cpuinfo | head -10 | tee -a $LOG_FILE

# -------------------------------
# 2. CPU PERFORMANCE TEST
# -------------------------------
echo -e "\n⚡ CPU BENCHMARK (stress-ng)" | tee -a $LOG_FILE

apt update -y > /dev/null 2>&1
apt install -y stress-ng > /dev/null 2>&1

stress-ng --cpu 6 --timeout 60s --metrics-brief | tee -a $LOG_FILE

# -------------------------------
# 3. DISK TYPE CHECK
# -------------------------------
echo -e "\n💾 DISK TYPE CHECK" | tee -a $LOG_FILE

lsblk -d -o name,rota,size,model | tee -a $LOG_FILE

echo -e "\n👉 rota=0 means SSD/NVMe, rota=1 means HDD" | tee -a $LOG_FILE

# -------------------------------
# 4. DISK PERFORMANCE TEST
# -------------------------------
echo -e "\n📊 DISK PERFORMANCE (fio)" | tee -a $LOG_FILE

apt install -y fio > /dev/null 2>&1

fio --name=randrw \
    --rw=randrw \
    --size=1G \
    --bs=4k \
    --numjobs=4 \
    --runtime=60 \
    --group_reporting | tee -a $LOG_FILE

# -------------------------------
# 5. QUICK WRITE SPEED TEST
# -------------------------------
echo -e "\n⚡ QUICK WRITE TEST (dd)" | tee -a $LOG_FILE

dd if=/dev/zero of=testfile bs=1G count=1 oflag=direct 2>&1 | tee -a $LOG_FILE
rm -f testfile

# -------------------------------
# 6. SUMMARY HINTS
# -------------------------------
echo -e "\n📌 QUICK INTERPRETATION GUIDE" | tee -a $LOG_FILE
echo "CPU: Look for high bogo ops in stress-ng" | tee -a $LOG_FILE
echo "Disk IOPS:" | tee -a $LOG_FILE
echo "  >20k  = Excellent (NVMe)" | tee -a $LOG_FILE
echo "  5k-20k = OK (SSD)" | tee -a $LOG_FILE
echo "  <3k   = BAD (Avoid)" | tee -a $LOG_FILE

echo -e "\n✅ TEST COMPLETE" | tee -a $LOG_FILE
echo "📄 LOG FILE: $LOG_FILE"
