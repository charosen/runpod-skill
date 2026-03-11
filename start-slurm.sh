#!/bin/bash
# ============================================
# Slurm 启动脚本（RunPod 容器环境）
# ============================================

echo "=== Creating directories ==="
mkdir -p /var/spool/slurm/ctld /var/spool/slurm/d /var/log/slurm /var/log/munge /run/munge
chmod 755 /var/spool/slurm /var/log/munge /run/munge

echo "=== Stopping old processes ==="
pkill -9 slurmd 2>/dev/null
pkill -9 slurmctld 2>/dev/null
pkill -9 munged 2>/dev/null
sleep 1

echo "=== Starting MUNGE (as munge user) ==="
mkdir -p /run/munge
chown munge:munge /run/munge
chmod 755 /run/munge
su - munge -s /bin/bash -c "/usr/sbin/munged"
sleep 2

# 验证 MUNGE
if ps aux | grep -v grep | grep munged > /dev/null; then
    echo "MUNGE started successfully"
else
    echo "ERROR: MUNGE failed to start"
    exit 1
fi

echo "=== Starting Slurmd (as root) ==="
nohup /usr/sbin/slurmd -D > /var/log/slurm/slurmd.log 2>&1 &
sleep 2

# 验证 slurmd
if ps aux | grep -v grep | grep slurmd > /dev/null; then
    echo "Slurmd started successfully"
else
    echo "ERROR: Slurmd failed to start"
    exit 1
fi

echo "=== Starting Slurmctld (as root) ==="
nohup /usr/sbin/slurmctld -D > /var/log/slurm/slurmctld.log 2>&1 &
sleep 3

# 验证 slurmctld
if ps aux | grep -v grep | grep slurmctld > /dev/null; then
    echo "Slurmctld started successfully"
else
    echo "ERROR: Slurmctld failed to start"
    exit 1
fi

echo "=== Checking node status ==="
sinfo

echo "=== Fix drain state if needed ==="
scontrol update NodeName=localhost State=IDLE 2>/dev/null

echo "=== Final status ==="
sinfo
echo ""
echo "Slurm is ready! Submit jobs with: sbatch your_script.sh"
