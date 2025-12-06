# ComfyUI 维护文档

> 创建日期: 2025-12-06
> 最后更新: 2025-12-06

---

## 1. 当前问题

### 1.1 Git 仓库状态混乱

**问题描述**：
ComfyUI 目录的 `.git` 曾被错误配置，remote 指向了 `rgthree-comfy` 仓库而非官方 ComfyUI 仓库。

**症状**：
- `git status` 显示几乎所有文件为"未跟踪"或"已修改"
- 无法正常 `git checkout` 到任何分支
- `git pull` 会拉取错误的代码

**当前状态**：
```
HEAD detached from v0.3.76
remote origin: https://github.com/comfyanonymous/ComfyUI.git (已修复)
```

### 1.2 Git 误操作风险

**问题描述**：
之前执行 `git clean -fd` 导致：
- 所有 custom_nodes 目录内容被清空
- 部分配置文件丢失
- custom_nodes 内缓存的模型文件被删除

**高风险操作**：
| 命令 | 风险 |
|------|------|
| `git clean -fd` | 删除所有未跟踪文件（包括 custom_nodes） |
| `git reset --hard` | 重置所有已跟踪文件到 HEAD 状态 |
| `git checkout -f` | 强制切换分支，覆盖本地修改 |

---

## 2. 解决方案

> ⚠ 在执行以下任一方案前，建议先在 ComfyUI 目录运行一次备份：
>
> ```powershell
> cd D:\ComfyUI_windows_portable\ComfyUI
> powershell -ExecutionPolicy Bypass -File backup_comfyui.ps1
> ```

### 2.1 方案一：快速修复（仅在已备份且熟悉 Git 时使用）

```powershell
cd D:\ComfyUI_windows_portable\ComfyUI

# 1. 确保本地 master 与远程 origin/master 对齐
git fetch origin
git switch -C master origin/master   # 如果 git 版本较旧，可使用：git checkout -B master origin/master
```

**适用场景**：

- 确认本地仓库的 remote 已指向官方 `https://github.com/comfyanonymous/ComfyUI.git`
- 只是想快速恢复到官方 master 对应版本
- 已通过备份脚本做好完整备份，并且现场有人熟悉 Git

**优点**：  
- 快速，只影响 Git 跟踪的核心代码文件

**缺点 / 风险**：  
- 会丢失对核心代码文件的本地修改  
- 如果本地 `master` 之前曾误操作（例如拉入过其他仓库的提交），结果也会不符合预期

**通常不会被影响的内容**（仍建议有备份）：

- `custom_nodes` 内大多数插件目录（作为未跟踪目录存在）
- `ComfyUI` 下的 `models` 目录（在 `.gitignore` 中）
- 外部模型目录 `D:\ComfyUI_Official\resources\models`

### 2.2 方案二：重新克隆（推荐，默认方案）

```powershell
# 1. （如尚未执行）先在 ComfyUI 目录做一次备份
cd D:\ComfyUI_windows_portable\ComfyUI
powershell -ExecutionPolicy Bypass -File backup_comfyui.ps1

# 2. 在上一级目录重新克隆代码
cd D:\ComfyUI_windows_portable

# 可选：先把旧目录改名，方便回滚
Rename-Item ComfyUI ComfyUI_old

# 从镜像重新克隆官方仓库
git clone https://gitclone.com/github.com/comfyanonymous/ComfyUI.git

# 3. 恢复配置 / workflows / custom nodes
cd ComfyUI
powershell -ExecutionPolicy Bypass -File restore_from_backup.ps1 -BackupPath "D:\ComfyUI_Backup\最新备份"
```

**优点**：  
- 得到一个完全干净的官方仓库状态  
- 彻底摆脱历史上 remote 错配、误操作遗留的脏状态  
- 配合备份脚本，可以自动恢复配置、workflows 和大部分插件

**缺点**：  
- 相比方案一稍慢（需要完整下载仓库、复制文件）  
- 需要确保备份中包含了当前环境需要的所有内容

---

## 3. 备份脚本详细说明

### 3.1 备份脚本 (`backup_comfyui.ps1`)

**位置**：`D:\ComfyUI_windows_portable\ComfyUI\backup_comfyui.ps1`

**运行方式**：
```powershell
cd D:\ComfyUI_windows_portable\ComfyUI
powershell -ExecutionPolicy Bypass -File backup_comfyui.ps1
```

**参数**：
| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-BackupDir` | `D:\ComfyUI_Backup` | 备份存储目录 |
| `-IncludeModels` | `$false` | 是否备份模型文件（很大） |

**备份内容**：

| 步骤 | 内容 | 说明 |
|------|------|------|
| 1/6 | `custom_nodes_list.json` | 所有插件的 Git URL + Commit Hash + **本地修改检测** |
| 1/6 | `patches/` | **本地代码修改的 .patch 文件**（新增） |
| 2/6 | `config/` | extra_model_paths.yaml, comfy.settings.json |
| 3/6 | `workflows/` | 所有 workflow JSON 文件 |
| 4/6 | `manager_data/` | ComfyUI-Manager 快照和配置 |
| 5/6 | `node_models/` | custom_nodes 内模型缓存目录：**手动指定的关键路径**（如 `comfyui_controlnet_aux\ckpts` 等）+ **自动扫描发现的包含大体积模型文件的目录** |
| 6/6 | `models_inventory.json` | 模型文件清单（路径+大小，不复制文件） |

> ⚠ 脚本会自动扫描 `custom_nodes` 下包含 `.safetensors`、`.ckpt`、`.pt`、`.pth`、`.bin`、`.onnx`、`.gguf`、`.ggml` 等后缀且文件较大的目录，并纳入 `node_models/` 备份；如有特别重要但体积较小的模型目录，仍可以通过在 `backup_comfyui.ps1` 中手动补充 `$nodeModelDirs` 的方式强制纳入备份。

> 💡 另外：每次备份目录下还会自动创建 `tools/` 子目录，用于保存本地维护相关的脚本和说明文档，包括：`ComfyUI_维护文档.md`、`backup_comfyui.ps1`、`restore_from_backup.ps1`，以及工作区根目录的一些工具脚本（如 `download_with_hfd.py`、`download_workflow.py`、`GitHub_Access_Solutions.md`）。即使以后按方案二重新克隆 `ComfyUI` 目录，这些运维工具也可以从最近一次备份的 `tools/` 中找回。

### 3.3 本地修改补丁备份（三重保护机制）

备份脚本会自动检测 custom_nodes 中的本地修改（未推送的 commit + 未提交的更改），并导出 `.patch` 文件。

**`custom_nodes_list.json` 新增字段**：

| 字段 | 说明 |
|------|------|
| `commit` | 远程 commit（可从 GitHub 获取，用于恢复基准） |
| `local_commit` | 本地 HEAD commit（可能只存在于本地） |
| `has_local_changes` | 是否有本地修改 |
| `patch_file` | 补丁文件名（如 `ComfyUI-LTXVideo.patch`） |

**三重保护机制**：

| 保护层 | 位置 | 说明 |
|--------|------|------|
| 1. 本地 Git commit | `custom_nodes/*/` | 修改已提交到本地仓库 |
| 2. GitHub Fork | `github.com/wonderstone/*` | 云端备份，永不丢失 |
| 3. 本地 patch 文件 | `D:\ComfyUI_Backup\*\patches\` | 可应用到新克隆的仓库 |

**从 patch 恢复本地修改**：

```powershell
# 1. 克隆仓库到远程 commit
git clone <url>
git checkout <remote_commit>

# 2. 应用补丁恢复本地修改
git apply patches/ComfyUI-LTXVideo.patch
```

**已 Fork 到 GitHub 的仓库**：

| 仓库 | Fork 地址 | 修复内容 |
|------|-----------|----------|
| ComfyUI-LTXVideo | https://github.com/wonderstone/ComfyUI-LTXVideo | `apply_rotary_emb` 兼容性修复 |
| ComfyUI-WarpedToolset | https://github.com/wonderstone/ComfyUI-WarpedToolset | `model_gguf` 路径注册 |

### 3.2 恢复脚本 (`restore_from_backup.ps1`)

**位置**：`D:\ComfyUI_windows_portable\ComfyUI\restore_from_backup.ps1`

**运行方式**：
```powershell
cd D:\ComfyUI_windows_portable\ComfyUI
powershell -ExecutionPolicy Bypass -File restore_from_backup.ps1 -BackupPath "D:\ComfyUI_Backup\20251206_013731"
```

**参数**：
| 参数 | 说明 |
|------|------|
| `-BackupPath` | 必填，备份目录路径 |
| `-RestoreNodes` | 是否恢复 custom nodes（默认 true） |
| `-RestoreConfig` | 是否恢复配置文件（默认 true） |
| `-RestoreWorkflows` | 是否恢复 workflows（默认 true） |
| `-RestoreNodeModels` | 是否恢复 custom_nodes 内的模型缓存（默认 true，对应 `node_models/` 目录） |

---

## 4. 已备份范围

### 4.1 最新备份

**位置**：`D:\ComfyUI_Backup\20251206_013731`

**内容**：
```
D:\ComfyUI_Backup\20251206_013731\
├── custom_nodes_list.json      # 32 个插件的 Git 信息
├── config\
│   ├── extra_model_paths.yaml  # 模型路径配置
│   └── user\default\comfy.settings.json
├── workflows\                  # 63 个 workflow
├── node_models\
│   └── comfyui_controlnet_aux_ckpts\  # 740 MB 模型缓存
├── manager_data\
│   └── ComfyUI-Manager_snapshots\
└── models_inventory.json       # 335 个模型文件清单 (709 GB)
```

### 4.2 Custom Nodes 列表 (32 个)

| 序号 | 插件名称 | 说明 |
|------|----------|------|
| 1 | cg-use-everywhere | 连线简化 |
| 2 | comfyui-advancedliveportrait | LivePortrait 高级版 |
| 3 | ComfyUI-Crystools | 系统监控工具 |
| 4 | comfyui-custom-scripts | 自定义脚本集 |
| 5 | comfyui-easy-use | 易用节点集 |
| 6 | comfyui-florence2 | Florence2 视觉模型 |
| 7 | comfyui-frame-interpolation | 帧插值 |
| 8 | ComfyUI-GGUF | GGUF 量化模型支持 |
| 9 | comfyui-impact-pack | 检测/分割/修复 |
| 10 | comfyui-impact-subpack | Impact Pack 扩展 |
| 11 | comfyui-inspire-pack | 创意节点集 |
| 12 | comfyui-kjnodes | KJ 节点集 |
| 13 | ComfyUI-LTXVideo | LTX 视频生成 |
| 14 | ComfyUI-Manager | 插件管理器 |
| 15 | ComfyUI-NodeAligner | 节点对齐工具 |
| 16 | ComfyUI-QwenVL | Qwen 视觉语言模型 |
| 17 | ComfyUI-RMBG | 背景移除 |
| 18 | ComfyUI-SAM3 | SAM 分割模型 |
| 19 | comfyui-videohelpersuite | 视频处理工具 |
| 20 | ComfyUI-WarpedToolset | 变形工具集 |
| 21 | ComfyUI-WJNodes | WJ 节点集 |
| 22 | comfyui-yaser-nodes | Yaser 节点集 |
| 23 | ComfyUI_Comfyroll_CustomNodes | Comfyroll 节点集 |
| 24 | comfyui_controlnet_aux | ControlNet 预处理器 |
| 25 | comfyui_essentials | 基础节点集 |
| 26 | comfyui_ipadapter_plus | IPAdapter Plus |
| 27 | ComfyUI_Swwan | Swwan 节点集 |
| 28 | comfyui_ultimatesdupscale | 终极 SD 放大 |
| 29 | image-size-tools | 图像尺寸工具 |
| 30 | mikey_nodes | Mikey 节点集 |
| 31 | rgthree-comfy | rgthree 节点集 |
| 32 | was-ns | WAS 节点套件 |

### 4.3 模型存储位置

| 位置 | 大小 | 安全性 | 说明 |
|------|------|--------|------|
| `D:\ComfyUI_Official\resources\models` | 706 GB | ✅ 安全 | 外部目录，不受 git 影响 |
| `ComfyUI\models` | 1.4 GB | ✅ 安全 | 在 .gitignore 中 |
| `C:\Users\ADMIN\.cache\huggingface` | 1.8 GB | ✅ 安全 | 用户目录 |
| `custom_nodes\comfyui_controlnet_aux\ckpts` | 0.72 GB | ⚠️ 危险 | 在 custom_nodes 内 |

### 4.4 模型目录结构 (外部)

```
D:\ComfyUI_Official\resources\models\
├── checkpoints\      # 主模型 (SD1.5, SDXL, FLUX 等)
├── loras\            # LoRA 模型
├── vae\              # VAE 模型
├── controlnet\       # ControlNet 模型
├── diffusion_models\ # 扩散模型
├── ipadapter\        # IPAdapter 模型 (7.55 GB)
├── clip_vision\      # CLIP Vision 模型 (8.18 GB)
├── insightface\      # InsightFace 模型 (0.59 GB)
├── text_encoders\    # 文本编码器
├── upscale_models\   # 放大模型
└── ...
```

---

## 5. 关键配置文件

### 5.1 extra_model_paths.yaml

**位置**：`D:\ComfyUI_windows_portable\ComfyUI\extra_model_paths.yaml`

**作用**：指定外部模型目录

```yaml
comfyui_external:
    base_path: D:\ComfyUI_Official\resources\models
    checkpoints: checkpoints
    loras: loras
    vae: vae
    controlnet: controlnet
    ipadapter: ipadapter
    clip_vision: clip_vision
    insightface: insightface
    # ... 更多映射
```

### 5.2 环境变量

| 变量 | 值 | 说明 |
|------|-----|------|
| `HF_ENDPOINT` | `https://hf-mirror.com` | HuggingFace 镜像 |

---

## 6. 常用命令

### 6.1 备份

```powershell
# 常规备份
cd D:\ComfyUI_windows_portable\ComfyUI
powershell -ExecutionPolicy Bypass -File backup_comfyui.ps1

# 包含模型的完整备份
powershell -ExecutionPolicy Bypass -File backup_comfyui.ps1 -IncludeModels
```

### 6.2 恢复

```powershell
# 从最新备份恢复
cd D:\ComfyUI_windows_portable\ComfyUI
powershell -ExecutionPolicy Bypass -File restore_from_backup.ps1 -BackupPath "D:\ComfyUI_Backup\20251206_013731"
```

### 6.3 启动 ComfyUI

```powershell
cd D:\ComfyUI_windows_portable
.\run_nvidia_gpu.bat
```

### 6.4 安全更新 ComfyUI 代码

```powershell
cd D:\ComfyUI_windows_portable\ComfyUI

# 1. 建议先做一次备份
powershell -ExecutionPolicy Bypass -File backup_comfyui.ps1

# 2. 从官方仓库拉取更新
git fetch origin
git pull origin master
```

> 注意：不要在未备份的情况下在 `ComfyUI` 目录中执行 `git clean -fd`、`git reset --hard`、`git checkout -f` 等高风险命令。

---

## 7. HuggingFace 缓存与自动下载模型处理

### 7.1 问题背景

很多 ComfyUI 节点会在首次使用时自动从 HuggingFace 下载模型，例如：

| 节点包 | 自动下载的模型 | 下载位置 |
|--------|----------------|----------|
| `comfyui_controlnet_aux` | `Intel/zoedepth-nyu-kitti` 等 | HuggingFace 缓存 |
| `comfyui-florence2` | Florence2 视觉模型 | HuggingFace 缓存 |
| `ComfyUI_InstantID` | antelopev2 InsightFace | `models/insightface/` |

**问题**：
- 这些节点**不遵循 `extra_model_paths.yaml`**
- 直连 HuggingFace 在国内网络环境下很慢或失败
- 模型下载到默认缓存目录，不在共享目录中

### 7.2 HuggingFace 缓存结构

**缓存位置**：`%USERPROFILE%\.cache\huggingface\hub\`

**目录结构**（以 `Intel/zoedepth-nyu-kitti` 为例）：
```
models--Intel--zoedepth-nyu-kitti\
├── blobs\
│   ├── <sha256-hash-of-config.json>
│   ├── <sha256-hash-of-model.safetensors>
│   └── ...
├── refs\
│   └── main                    # 内容是 commit hash
└── snapshots\
    └── <commit-hash>\
        ├── config.json         # 指向 blobs 中对应文件
        ├── model.safetensors
        └── ...
```

**关键点**：
- `blobs/` 中的文件名是**文件内容的 SHA256 哈希**
- `refs/main` 存储当前版本的 commit hash
- `snapshots/<commit>/` 中的文件指向 `blobs/` 中的对应文件
- `.incomplete` 后缀表示下载未完成
- `.lock` 文件表示正在下载

### 7.3 解决方案：手动下载 + 缓存配置

**步骤 1：使用镜像手动下载模型**

```powershell
# 使用 hf-mirror.com 镜像下载
python download_with_hfd.py Intel/zoedepth-nyu-kitti "D:\ComfyUI_Official\resources\models\zoedepth" --no-hash-check
```

**步骤 2：创建正确的 HuggingFace 缓存结构**

```powershell
$sharedDir = "D:\ComfyUI_Official\resources\models\zoedepth"
$cacheDir = "$env:USERPROFILE\.cache\huggingface\hub\models--Intel--zoedepth-nyu-kitti"
$commitHash = "c5494fa0938f18d71e215e245472470c3aefebd7b434abd89750e5ae4008e2dc"

# 创建目录结构
New-Item -ItemType Directory -Path "$cacheDir\blobs" -Force
New-Item -ItemType Directory -Path "$cacheDir\refs" -Force
New-Item -ItemType Directory -Path "$cacheDir\snapshots\$commitHash" -Force

# 设置 refs/main
Set-Content -Path "$cacheDir\refs\main" -Value $commitHash -NoNewline

# 为每个文件计算 SHA256 并创建缓存
$fileList = @("config.json", "model.safetensors", "preprocessor_config.json", "README.md")
foreach ($fileName in $fileList) {
    $srcPath = Join-Path $sharedDir $fileName
    if (Test-Path $srcPath) {
        $hash = (Get-FileHash $srcPath -Algorithm SHA256).Hash.ToLower()
        Copy-Item $srcPath "$cacheDir\blobs\$hash" -Force
        Copy-Item $srcPath "$cacheDir\snapshots\$commitHash\$fileName" -Force
    }
}
```

**步骤 3：清理残留文件**

```powershell
# 删除 .incomplete 和 .lock 文件
Remove-Item "$cacheDir\blobs\*.incomplete" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:USERPROFILE\.cache\huggingface\.locks\models--Intel--zoedepth-nyu-kitti" -Recurse -Force -ErrorAction SilentlyContinue
```

### 7.4 已配置的 HuggingFace 模型

| 模型 | 共享目录 | 用途 |
|------|----------|------|
| `Intel/zoedepth-nyu-kitti` | `resources\models\zoedepth\` | Zoe Depth 预处理器 (1316 MB) |

### 7.5 排查自动下载问题

**检查正在下载的模型**：
```powershell
# 查找 .incomplete 文件
Get-ChildItem "$env:USERPROFILE\.cache\huggingface" -Recurse -Filter "*.incomplete"

# 查找 .lock 文件
Get-ChildItem "$env:USERPROFILE\.cache\huggingface\.locks" -Recurse -Filter "*.lock"

# 查看最近修改的缓存目录
Get-ChildItem "$env:USERPROFILE\.cache\huggingface\hub" -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 5
```

**网络活动但无日志时**：通常是 `transformers.pipeline()` 在下载模型，检查 HuggingFace 缓存即可确认。

---

## 8. 待解决问题

- [ ] Git 仓库状态修复（选择方案 1 或 2）
- [ ] 验证所有 custom nodes 正常工作
- [ ] 测试 IPAdapter FaceID workflow

---

## 8. 历史记录

| 日期 | 操作 | 结果 |
|------|------|------|
| 2025-12-06 | 修复 git remote 指向 | ✅ 完成 |
| 2025-12-06 | 安装 insightface 0.7.3 | ✅ 完成 |
| 2025-12-06 | 创建备份脚本 | ✅ 完成 |
| 2025-12-06 | 执行首次备份 | ✅ 完成 |
| 2025-12-06 | 复制 workflows 从备份 | ✅ 完成 |
| 2025-12-06 | 安装 ComfyUI_InstantID 并下载模型 | ✅ 完成 |
| 2025-12-06 | 修复 ComfyUI-WarpedToolset `model_gguf` KeyError | ✅ 完成 |
| 2025-12-06 | 修复 ComfyUI-LTXVideo `apply_rotary_emb` ImportError | ✅ 完成 |
| 2025-12-06 | 创建 antelopev2 符号链接解决 InsightFace 路径问题 | ✅ 完成 |
| 2025-12-06 | 增强备份脚本：添加本地修改补丁导出功能 | ✅ 完成 |
| 2025-12-06 | 安装 GitHub CLI 并配置认证 | ✅ 完成 |
| 2025-12-06 | Fork 并推送修复到 GitHub（三重保护） | ✅ 完成 |
| 2025-12-06 | 下载 control-lora-depth-rank256.safetensors | ✅ 完成 |
| 2025-12-06 | 下载 Intel/zoedepth-nyu-kitti 并配置 HF 缓存 | ✅ 完成 |
| 2025-12-06 | 添加 InstantID 工作流 Note 节点（basic + depth） | ✅ 完成 |


