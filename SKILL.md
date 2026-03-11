---
name: runpod-slurm
description: "在 RunPod 单GPU容器中安装和配置 Slurm 作业调度器。包括 MUNGE 认证、slurm.conf 配置、服务启动、sinfo/scontrol/squeue 命令使用，以及常见问题排查。"
metadata: { "openclaw": { "emoji": "🎛️", "requires": { "bins": ["munge", "slurm-wlm", "slurm-client"] } } }
---

# RunPod 单GPU安装Slurm教程

在 RunPod 容器中安装 Slurm 作业调度器。

## 环境

| 项目 | 配置 |
|------|------|
| 平台 | RunPod 容器 |
| 系统 | Ubuntu |
| GPU | A100 PCIe 1卡 |
| CPU | 8 vCPU (64线程) |
| 内存 | 125GB RAM |

**⚠️ 重要说明：**
- 容器 PID 1 是 docker-init，**不是 systemd**
- GPU 设备只读，Slurm 无法直接管理
- 通过 `CUDA_VISIBLE_DEVICES` 指定 GPU

---

## 安装步骤

### 1. 安装依赖

```bash
apt update
apt install -y munge slurm-wlm slurm-client libslurm-dev sudo
```

### 2. 配置MUNGE

```bash
# 检查密钥
ls -lh /etc/munge/munge.key

# 生成密钥（如不存在）
dd if=/dev/urandom bs=1 count=1024 2>/dev/null | openssl enc -base64 > /etc/munge/munge.key
chown munge:munge /etc/munge/munge.key
chmod 400 /etc/munge/munge.key
```

### 3. 创建必要目录

```bash
mkdir -p /var/spool/slurm/ctld /var/spool/slurm/d /var/log/slurm /var/log/munge /run/munge
chmod 755 /var/spool/slurm /var/log/munge /run/munge
```

### 4. slurm.conf 配置

```bash
cat > /etc/slurm/slurm.conf << 'EOF'
ClusterName=localhost
SlurmctldHost=localhost
NodeName=localhost CPUs=64 Sockets=2 CoresPerSocket=16 ThreadsPerCore=2 RealMemory=125000 State=UNKNOWN
PartitionName=gpu Nodes=localhost Default=YES MaxTime=INFINITE State=UP
SlurmUser=root
SlurmdUser=root
StateSaveLocation=/var/spool/slurm/ctld
SlurmdSpoolDir=/var/spool/slurm/d
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
ReturnToService=2
ProctrackType=proctrack/linuxproc
EOF
```

**⚠️ 关键：不要配置 GPU (gres)**

### 5. 启动服务

**MUNGE（以 munge 用户）：**
```bash
mkdir -p /run/munge
chown munge:munge /run/munge
chmod 755 /run/munge
su - munge -s /bin/bash -c "/usr/sbin/munged"
```

**Slurm（以 root 用户）：**
```bash
pkill -9 slurmd 2>/dev/null
pkill -9 slurmctld 2>/dev/null
sleep 1

nohup /usr/sbin/slurmd -D > /var/log/slurm/slurmd.log 2>&1 &
sleep 2
nohup /usr/sbin/slurmctld -D > /var/log/slurm/slurmctld.log 2>&1 &
sleep 3

sinfo
```

### 6. 修复节点状态

```bash
scontrol update NodeName=localhost State=IDLE
sinfo
```

---

## sinfo 命令

### 输出格式
```
PARTITION  AVAIL  TIMELIMIT  NODES  STATE   NODELIST
gpu*       up    infinite   1      idle    localhost
```

### 状态说明
| 状态 | 含义 |
|------|------|
| idle | 空闲 ✅ |
| allocated | 运行中 ✅ |
| drain | 被排除 ⚠️ |
| down | 下线 🔴 |
| inval | 无效 🔴 |

---

## scontrol 命令

```bash
# 查看节点详情
scontrol show node localhost

# 清除 drain 状态
scontrol update NodeName=localhost State=IDLE

# 查看分区
scontrol show partition
```

---

## squeue 命令

| 状态 | 含义 |
|------|------|
| PD | Pending，排队中 |
| R | Running，运行中 |
| CG | Completing，完成中 |
| F | Failed，失败 |
| CA | Cancelled，已取消 |

---

## 调试命令

```bash
# 查看日志
tail -f /var/log/slurm/slurmctld.log
tail -f /var/log/slurm/slurmd.log

# 检查进程
ps aux | grep slurm
ps aux | grep munge

# 停止所有
pkill -9 munged
pkill -9 slurmd
pkill -9 slurmctld
```

---

## 关键经验

1. **MUNGE 以 munge 用户运行**
2. **Slurm 以 root 用户运行**（SlurmUser=root, SlurmdUser=root）
3. **容器用 ProctrackType=proctrack/linuxproc**
4. **不配置 gres，GPU 通过 CUDA_VISIBLE_DEVICES 指定**
5. **日志配置名是 SlurmctldLogFile 和 SlurmdLogFile**

---

## 任务脚本示例

```bash
#!/bin/bash
#SBATCH --job-name=eval
#SBATCH --output=%j.out
#SBATCH --error=%j.err
#SBATCH --partition=gpu
#SBATCH --time=01:00:00

# 指定 GPU
export CUDA_VISIBLE_DEVICES=0

python main.py ...
```
