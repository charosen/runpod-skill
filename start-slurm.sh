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
sleep 1

echo "=== Starting MUNGE (as munge user) ==="
su - munge -s /bin/bash -c "/usr/sbin/munged"
sleep 2

echo "=== Starting Slurmd (as root) ==="
nohup /usr/sbin/slurmd -D > /var/log/slurm/slurmd.log 2>&1 &
sleep 2

echo "=== Starting Slurmctld (as root) ==="
nohup /usr/sbin/slurmctld -D > /var/log/slurm/slurmctld.log 2>&1 &
sleep 3

echo "=== Status ==="
sinfo

echo "=== Fix drain state if needed ==="
scontrol update NodeName=localhost State=IDLE 2>/dev/null

echo "=== Done ==="
sinfo
