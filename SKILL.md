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

### 4. slurm.conf 完整配置

#### 4.1 创建配置文件

```bash
cat > /etc/slurm/slurm.conf << 'EOF'
# ============================================
# Slurm 配置文件
# 参考: https://slurm.schedmd.com/slurm.conf.html
# ============================================

# -------------------
# 基础配置
# -------------------

# 集群名称（必须填写）
ClusterName=localhost

# 控制器地址（单机节点写 localhost）
SlurmctldHost=localhost

# -------------------
# 节点配置
# -------------------

# NodeName: 节点名称
# CPUs: CPU 核心数
# Sockets: 物理 CPU 颗数
# CoresPerSocket: 每颗 CPU 的核心数
# ThreadsPerCore: 每核心的线程数
# RealMemory: 内存大小 (MB)
# State: 节点状态 (UNKNOWN=未知, IDLE=空闲, DOWN=下线)
NodeName=localhost CPUs=64 Sockets=2 CoresPerSocket=16 ThreadsPerCore=2 RealMemory=125000 State=UNKNOWN

# -------------------
# 分区配置
# -------------------

# PartitionName: 分区名称（可自定义，如 gpu, batch, default）
# Nodes: 分区包含的节点
# Default: 是否为默认分区
# MaxTime: 最大运行时间 (INFINITE=无限制，也可用 01:00:00 格式)
# State: 分区状态 (UP=可用, DOWN=不可用)
PartitionName=gpu Nodes=localhost Default=YES MaxTime=INFINITE State=UP

# -------------------
# 用户配置
# -------------------

# SlurmUser: slurmctld 运行用户
# SlurmdUser: slurmd 运行用户
# ⚠️ 容器环境用 root
SlurmUser=root
SlurmdUser=root

# -------------------
# 目录配置
# -------------------

# StateSaveLocation: 状态保存目录（slurmctld 重启后恢复任务用）
StateSaveLocation=/var/spool/slurm/ctld

# SlurmdSpoolDir: slurmd spool 目录（存放 job 脚本等）
SlurmdSpoolDir=/var/spool/slurm/d

# -------------------
# 日志配置
# -------------------

# SlurmctldLogFile: 控制器日志路径
# ⚠️ 注意：正确的配置名是 SlurmctldLogFile 和 SlurmdLogFile
# 错误写法：LogFile（会导致报错：Parsing error at unrecognized key: LogFile）
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log

# -------------------
# 其他配置
# -------------------

# ReturnToService: 节点恢复策略
# 2 = 自动重新上线
ReturnToService=2

# ProctrackType: 进程追踪方式
# ⚠️ 关键：容器环境使用 linuxproc，不使用 cgroup
# proctrack/linuxproc: 使用 /proc 文件系统（适用于容器环境）
# proctrack/cgroup: 使用 cgroup（需要 cgroup 支持，容器通常不支持，会报错）
ProctrackType=proctrack/linuxproc
EOF
```

#### 4.2 配置项说明

| 配置项 | 说明 | 示例 |
|--------|------|------|
| `ClusterName` | 集群名称 | `localhost` |
| `SlurmctldHost` | 控制器地址 | `localhost` |
| `NodeName` | 节点名+硬件 | `CPUs=64 RealMemory=125000` |
| `PartitionName` | 分区名称 | `gpu`, `batch` |
| `SlurmUser` | Slurm运行用户 | `root` |
| `SlurmdUser` | Slurmd运行用户 | `root` |
| `StateSaveLocation` | 状态保存目录 | `/var/spool/slurm/ctld` |
| `SlurmdSpoolDir` | 作业脚本目录 | `/var/spool/slurm/d` |
| `SlurmctldLogFile` | 控制器日志 | `/var/log/slurm/slurmctld.log` |
| `SlurmdLogFile` | 计算节点日志 | `/var/log/slurm/slurmd.log` |
| `ReturnToService` | 节点恢复策略 | `2` |
| `ProctrackType` | 进程追踪方式 | `proctrack/linuxproc` |

#### 4.3 ⚠️ 关键警告

**不要在 slurm.conf 中配置 GPU（gres 相关配置）**
- 容器环境 GPU 设备是只读的，Slurm 无法直接管理
- 任务运行时通过 `CUDA_VISIBLE_DEVICES` 环境变量手动指定

---

### 5. 启动 MUNGE 服务

#### 5.1 创建 run/munge 目录

```bash
mkdir -p /run/munge
chown munge:munge /run/munge
chmod 755 /run/munge
```

#### 5.2 以 munge 用户启动

```bash
su - munge -s /bin/bash -c "/usr/sbin/munged"
```

#### 5.3 验证 MUNGE 运行状态

```bash
# 检查进程
ps aux | grep munged

# 预期输出：
# munge  5521  0.0  0.0  71352  2048 ?  Sl  07:02  0:00 /usr/sbin/munged
```

#### 5.4 查看 MUNGE 日志

```bash
# 如果启动失败，查看日志
tail -f /var/log/munge/munged.log

# 预期成功日志：
# 2026-03-10 07:02:18 +0000 Info: Created socket "/run/munge/munge.socket.2"
# 2026-03-10 07:02:18 +0000 Info: Created 2 work threads
```

#### 5.5 常见 MUNGE 报错

| 报错 | 原因 | 解决方案 |
|------|------|----------|
| `Failed to check socket dir "/run/munge"` | /run/munge 不存在 | `mkdir -p /run/munge && chown munge:munge /run/munge` |
| `cannot change directory to /nonexistent` | 用户 home 目录不存在 | `usermod -d /var/lib/munge munge` |
| `Logfile is insecure: invalid ownership` | 密钥权限问题 | `chown munge:munge /etc/munge/munge.key && chmod 400 /etc/munge/munge.key` |

---

### 6. 启动 Slurm 服务

#### 6.1 停止旧进程

```bash
pkill -9 slurmd 2>/dev/null
pkill -9 slurmctld 2>/dev/null
sleep 1
```

#### 6.2 启动 slurmd（计算节点）

```bash
nohup /usr/sbin/slurmd -D > /var/log/slurm/slurmd.log 2>&1 &
sleep 2
```

#### 6.3 启动 slurmctld（控制器）

```bash
nohup /usr/sbin/slurmctld -D > /var/log/slurm/slurmctld.log 2>&1 &
sleep 3
```

#### 6.4 验证 Slurm 服务状态

```bash
# 检查进程
ps aux | grep slurm

# 预期输出：
# root     1234  0.0  0.0  ...  /usr/sbin/slurmd -D
# slurm    1235  0.0  0.0  ...  /usr/sbin/slurmctld -D
```

#### 6.5 验证 sinfo

```bash
sinfo

# 预期输出：
# PARTITION  AVAIL  TIMELIMIT  NODES  STATE   NODELIST
# gpu*       up    infinite   1      idle    localhost
```

#### 6.6 修复节点状态（如需要）

如果节点状态不是 `idle`，执行：

```bash
# 清除 drain 状态
scontrol update NodeName=localhost State=IDLE

# 再次查看状态
sinfo
```

---

## sinfo 命令

### 输出格式
```
PARTITION  AVAIL  TIMELIMIT  NODES  STATE   NODELIST
gpu*       up    infinite   1      idle    localhost
```

### 字段说明
| 字段 | 说明 |
|------|------|
| PARTITION | 分区名（队列名） |
| AVAIL | 可用状态：up=可用, down=不可用 |
| TIMELIMIT | 最大运行时间 |
| NODES | 节点数量 |
| STATE | 节点状态 |
| NODELIST | 节点列表 |

### 状态说明
| 状态 | 含义 |
|------|------|
| idle | 空闲，可接收任务 ✅ |
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

# 查看作业详情
scontrol show job <JOB_ID>

# 取消作业
scancel <JOB_ID>
```

### 关键字段说明
| 字段 | 说明 |
|------|------|
| State | 节点状态组合 |
| Reason | 状态原因（如有问题） |
| LastBusyTime | 最后忙碌时间 |
| SlurmdStartTime | slurmd 启动时间 |

---

## squeue 命令

### 任务状态
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
# 查看 slurmctld 日志
tail -f /var/log/slurm/slurmctld.log

# 查看 slurmd 日志
tail -f /var/log/slurm/slurmd.log

# 查看 MUNGE 日志
tail -f /var/log/munge/munged.log

# 检查进程
ps aux | grep slurm
ps aux | grep munge

# 停止所有服务
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
6. **PrologFlags 在容器环境不要使用**

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

提交任务：
```bash
sbatch test.sh
```

查看任务：
```bash
squeue
```
