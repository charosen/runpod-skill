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

#### 6.2 启动 slurmd（计算节点，以 root 身份）

```bash
# 以 root 用户启动 slurmd
# -D 参数表示前台调试模式运行，方便查看日志
nohup /usr/sbin/slurmd -D > /var/log/slurm/slurmd.log 2>&1 &
sleep 2
```

**说明：**
- `nohup ... &` 后台运行，关闭终端也能继续运行
- `-D` 参数让 slurmd 以前台模式运行，方便调试
- 日志输出到 `/var/log/slurm/slurmd.log`

#### 6.3 启动 slurmctld（控制器，以 root 身份）

```bash
# 以 root 用户启动 slurmctld
# -D 参数表示前台调试模式运行
nohup /usr/sbin/slurmctld -D > /var/log/slurm/slurmctld.log 2>&1 &
sleep 3
```

**说明：**
- slurmctld 是 Slurm 控制器，负责作业调度
- 需要在 slurmd 启动后再启动
- 使用 root 身份是因为容器环境配置了 `SlurmUser=root` 和 `SlurmdUser=root`

#### 6.4 为什么用 nohup？

| 原因 | 说明 |
|------|------|
| 容器无 systemd | RunPod 容器的 PID 1 是 docker-init，不是 systemd，无法用 systemctl |
| 保持运行 | nohup 保证关闭终端后进程继续运行 |
| 日志持久化 | 输出重定向到日志文件，方便排查问题 |
| 后台执行 | `&` 让进程在后台运行 |

**如果不用 nohup：**
```bash
# 错误方式（关闭终端后进程会终止）
/usr/sbin/slurmd -D

# 正确方式
nohup /usr/sbin/slurmd -D > /var/log/slurm/slurmd.log 2>&1 &
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

## sinfo 命令详解

`sinfo` 用于查看集群/分区和节点状态。

### 7.1 基本用法

```bash
sinfo              # 查看所有分区
sinfo -N          # 按节点显示（简洁）
sinfo -l           # 详细显示
sinfo -p gpu       # 查看特定分区
sinfo -o "%.10N %.6t"  # 自定义格式
```

### 7.2 输出格式

```
PARTITION  AVAIL  TIMELIMIT  NODES  STATE   NODELIST
gpu*       up    infinite   1      idle    localhost
```

### 7.3 字段说明

| 字段 | 说明 |
|------|------|
| PARTITION | 分区名（队列名），如 gpu, batch, default |
| AVAIL | 可用状态：up=可用, down=不可用 |
| TIMELIMIT | 最大运行时间，infinite=无限制 |
| NODES | 节点数量 |
| STATE | 节点状态 |
| NODELIST | 节点列表 |

### 7.4 状态说明

| 状态 | 含义 | 严重程度 |
|------|------|----------|
| `idle` | 空闲，可接收任务 | ✅ 正常 |
| `allocated` | 正在运行任务 | ✅ 正常 |
| `mixed` | 部分CPU已分配 | ✅ 正常 |
| `drain` | 节点被排除，不接收新任务 | ⚠️ 需要修复 |
| `draining` | 正在排空现有任务 | ⚠️ 正在退出 |
| `down` | 节点下线 | 🔴 严重 |
| `inval` | 节点配置无效 | 🔴 严重 |
| `unknown` | 状态未知 | ⚠️ 待确认 |

### 7.5 状态组合

节点状态可能组合出现：
- `IDLE+DRAIN` - 空闲但被排空
- `IDLE+DRAIN+INVALID_REG` - 空闲但注册无效
- `DOWN*` - 节点已下线

### 7.6 常用示例

```bash
# 查看所有节点
sinfo

# 只看 gpu 分区
sinfo -p gpu

# 详细模式
sinfo -l

# 只看节点名和状态
sinfo -o "%.10N %.6t"

# 刷新状态
sinfo -r
```

---

## scontrol 命令详解

`scontrol` 是 Slurm 控制器管理命令，用于查看和修改集群配置。

### 8.1 基本用法

```bash
scontrol show config      # 查看配置
scontrol show node        # 查看所有节点
scontrol show node <name> # 查看特定节点
scontrol show partition   # 查看所有分区
scontrol show job         # 查看所有作业
scontrol show job <id>    # 查看特定作业
```

### 8.2 查看节点详情

```bash
scontrol show node localhost
```

**输出示例（正常状态）：**
```
NodeName=localhost Arch=x86_64 CoresPerSocket=16
CPUAlloc=0 CPUTot=64 CPULoad=5.79
AvailableFeatures=(null) ActiveFeatures=(null)
Gres=gpu:1
NodeAddr=localhost NodeHostName=localhost Version=21.08.5
OS=Linux 6.5.0-35-generic
RealMemory=125000 AllocMem=0 FreeMem=509863
Sockets=2 Boards=1 State=IDLE
ThreadsPerCore=2 TmpDisk=0 Weight=1
Partitions=gpu
BootTime=2024-06-20T18:07:52
SlurmdStartTime=2026-03-10T08:04:33
LastBusyTime=2026-03-10T08:03:59
```

**输出示例（异常状态）：**
```
NodeName=localhost State=IDLE+DRAIN+INVALID_REG
Reason=gres/gpu count reported lower than configured (0 < 1) [slurm@2026-03-10T08:04:33]
```

### 8.3 节点详情字段说明

| 字段 | 说明 |
|------|------|
| NodeName | 节点名称 |
| Arch | CPU 架构 |
| CoresPerSocket | 每socket核心数 |
| CPUAlloc | 已分配的CPU核心数 |
| CPUTot | 总CPU核心数 |
| RealMemory | 总内存 (MB) |
| AllocMem | 已分配内存 (MB) |
| FreeMem | 可用内存 (MB) |
| Sockets | 物理CPU颗数 |
| State | 节点状态（可能组合） |
| Gres | 通用资源（如 gpu:1） |
| NodeAddr | 节点地址 |
| NodeHostName | 节点主机名 |
| Reason | 状态原因（如有问题） |
| LastBusyTime | 最后忙碌时间 |
| SlurmdStartTime | slurmd 启动时间 |
| Partitions | 所属分区 |

### 8.4 常用操作

```bash
# 清除 drain 状态（最常用！）
scontrol update NodeName=localhost State=IDLE

# 设置节点下线
scontrol update NodeName=localhost State=DOWN

# 重置节点状态为UNKNOWN
scontrol update NodeName=localhost State=UNKNOWN

# 查看分区信息
scontrol show partition

# 查看分区详情
scontrol show partition gpu

# 查看作业详情
scontrol show job 1

# 重新排队作业
scontrol requeue 1

# 取消作业
scancel 1

# 挂起作业
scontrol suspend 1

# 恢复作业
scontrol resume 1
```

### 8.5 查看配置

```bash
# 查看所有配置
scontrol show config

# 查看特定配置项
scontrol show config | grep -i cluster
scontrol show config | grep -i slurmd
```

---

## squeue 命令详解

`squeue` 用于查看作业队列状态。

### 9.1 基本用法

```bash
squeue                    # 查看所有作业
squeue -u username        # 查看特定用户作业
squeue -p gpu            # 查看特定分区作业
squeue -l                # 详细显示
squeue -t RUNNING        # 只看运行中的
squeue -t PENDING        # 只看排队的
squeue -j 1234           # 查看特定作业
```

### 9.2 输出格式

```
JOBID PARTITION NAME     USER ST TIME  NODES NODELIST
1     gpu      eval-dee root PD 0:00  1     localhost
```

### 9.3 字段说明

| 字段 | 说明 |
|------|------|
| JOBID | 作业ID |
| PARTITION | 分区 |
| NAME | 作业名称 |
| USER | 用户名 |
| ST | 状态 |
| TIME | 运行时间 |
| NODES | 节点数 |
| NODELIST | 分配的节点 |

### 9.4 状态说明

| 状态 | 含义 | 说明 |
|------|------|------|
| `PD` | Pending | 排队等待中 |
| `R` | Running | 正在运行 |
| `CG` | Completing | 正在完成 |
| `F` | Failed | 失败 |
| `CA` | Cancelled | 已取消 |
| `TO` | Timeout | 超时 |
| `NF` | Node Fail | 节点故障 |
| `SE` | Special Exit | 特殊退出 |

### 9.5 常用示例

```bash
# 查看我的所有作业
squeue -u $USER

# 只看运行中的
squeue -t RUNNING

# 只看排队的
squeue -t PENDING

# 详细输出
squeue -l

# 每秒刷新
watch -n 1 squeue

# 查看作业详情
scontrol show job 1

# 取消作业
scancel 1

# 取消所有我的作业
scancel -u $USER

# 强制取消
scancel -9 1
```

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

## 常见问题汇总

### 10.1 服务启动问题

| 报错 | 原因 | 解决方案 |
|------|------|----------|
| `System has not been booted with systemd as init system (PID 1)` | 容器无 systemd | 使用 nohup 手动启动 |
| `Failed to connect to bus: Host is down` | 同上 | 同上 |
| `create-munge-key: command not found` | 命令不在 PATH | 直接手动生成密钥 |
| `Failed to check socket dir "/run/munge"` | /run/munge 不存在 | `mkdir -p /run/munge && chown munge:munge /run/munge` |
| `cannot change directory to /nonexistent` | 用户 home 目录不存在 | `usermod -d /var/lib/slurm slurm` |
| `Logfile is insecure: invalid ownership` | 密钥/日志权限问题 | 检查权限 |

### 10.2 配置问题

| 报错 | 原因 | 解决方案 |
|------|------|----------|
| `ClusterName needs to be specified` | 缺少 ClusterName | 添加 `ClusterName=localhost` |
| `Parsing error at unrecognized key: LogFile` | 配置名错误 | 用 `SlurmctldLogFile` 和 `SlurmdLogFile` |
| `Node configuration differs from hardware: CPUs=8:64` | CPU配置与实际不符 | 根据实际硬件填写 |
| `Invalid PrologFlag: NOContain` | PrologFlags 无此选项 | 删除 PrologFlags 行 |
| `Duplicated NodeHostName` | gres 配置格式错误 | gres 写在同一行 |

### 10.3 节点状态问题

| 报错 | 原因 | 解决方案 |
|------|------|----------|
| `gres/gpu count reported lower than configured (0 < 1)` | GPU 检测不到 | 去掉 gres 配置 |
| `cgroup namespace 'freezer' not mounted` | 容器无 cgroup | 使用 `ProctrackType=proctrack/linuxproc` |
| 节点 drain | 节点被排空 | `scontrol update NodeName=localhost State=IDLE` |
| 节点 inval | 配置无效 | 检查 slurm.conf |

### 10.4 任务问题

| 报错 | 原因 | 解决方案 |
|------|------|----------|
| `Nodes required for job are DOWN, DRAINED` | 节点不可用 | 检查节点状态 |
| 任务一直 PD | 节点不接收任务 | 检查节点是否 drain |

---

## 关键经验总结

1. **MUNGE 以 munge 用户运行**
   - 使用 `su - munge -s /bin/bash -c "/usr/sbin/munged"` 启动
   - 确保 `/run/munge` 目录存在并权限正确

2. **Slurm 以 root 用户运行**
   - 配置 `SlurmUser=root` 和 `SlurmdUser=root`
   - 使用 nohup 后台启动

3. **容器环境使用 ProctrackType=proctrack/linuxproc**
   - 不要使用 cgroup，容器不支持
   - 会报错：`cgroup namespace 'freezer' not mounted`

4. **不配置 gres，GPU 通过 CUDA_VISIBLE_DEVICES 指定**
   - 容器 GPU 设备是只读的
   - Slurm 无法直接管理 GPU
   - 任务脚本中手动指定：`export CUDA_VISIBLE_DEVICES=0`

5. **日志配置名是 SlurmctldLogFile 和 SlurmdLogFile**
   - 错误写法：`LogFile`（会导致报错）
   - 正确写法：`SlurmctldLogFile` 和 `SlurmdLogFile`

6. **PrologFlags 在容器环境不要使用**
   - 删除或注释掉 PrologFlags 行
   - 使用会报错：`Invalid PrologFlag: NOContain`

7. **节点 drain 时用 scontrol update 恢复**
   - `scontrol update NodeName=localhost State=IDLE`

8. **必须预先创建日志文件并设置权限**
   - `touch /var/log/slurm/slurmctld.log`
   - `chown slurm:slurm /var/log/slurm/*.log`

9. **所有目录必须对运行用户有写权限**
   - `/var/spool/slurm/ctld`
   - `/var/spool/slurm/d`
   - `/var/log/slurm`

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
