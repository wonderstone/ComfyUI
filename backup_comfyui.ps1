# ComfyUI 备份脚本
# 运行方式: powershell -ExecutionPolicy Bypass -File backup_comfyui.ps1

param(
    [string]$BackupDir = "D:\ComfyUI_Backup",
    [switch]$IncludeModels = $false,  # 模型文件很大，默认不备份
    [switch]$Force = $false
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path $BackupDir $timestamp

Write-Host @"
╔══════════════════════════════════════════════════════════════╗
║              ComfyUI 备份工具 v1.0                           ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# 创建备份目录
if (-not (Test-Path $backupPath)) {
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
}
Write-Host "备份目录: $backupPath" -ForegroundColor Yellow

# ============================================================
# 1. 备份 Custom Nodes 信息 (Git URL + Commit)
# ============================================================
Write-Host "`n[1/6] 导出 Custom Nodes 列表..." -ForegroundColor Cyan

$nodesDir = "custom_nodes"
$nodes = Get-ChildItem $nodesDir -Directory | Where-Object { $_.Name -ne "__pycache__" -and $_.Name -ne ".disabled" }

# 加载 fork 映射配置
$forksConfig = @{}
$forksFile = "my_forks.json"
if (Test-Path $forksFile) {
    try {
        $forksJson = Get-Content $forksFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($forksJson.forks) {
            $forksJson.forks.PSObject.Properties | ForEach-Object {
                $forksConfig[$_.Name] = $_.Value
            }
        }
        Write-Host "  ✓ 已加载 $($forksConfig.Count) 个 fork 映射配置" -ForegroundColor Gray
    } catch {
        Write-Host "  ⚠ 无法加载 fork 映射配置: $_" -ForegroundColor Yellow
    }
}

# 创建补丁目录用于保存本地修改
$patchesDir = Join-Path $backupPath "patches"
New-Item -ItemType Directory -Path $patchesDir -Force | Out-Null

$nodeList = @()
$patchCount = 0
foreach ($node in $nodes) {
    $gitDir = Join-Path $node.FullName ".git"
    if (Test-Path $gitDir) {
        Push-Location $node.FullName
        $remoteUrl = git remote get-url origin 2>$null
        $commit = git rev-parse HEAD 2>$null
        $branch = git rev-parse --abbrev-ref HEAD 2>$null

        # 检测本地修改：未推送的提交 + 未提交的更改
        $hasLocalCommits = $false
        $hasUncommittedChanges = $false
        $patchFile = $null

        # 检查是否有未推送到远程的提交
        $remoteBranch = "origin/$branch"
        $unpushedCommits = git log "$remoteBranch..HEAD" --oneline 2>$null
        if ($unpushedCommits) {
            $hasLocalCommits = $true
        }

        # 检查是否有未提交的更改
        $uncommitted = git status --porcelain 2>$null
        if ($uncommitted) {
            $hasUncommittedChanges = $true
        }

        # 如果有本地修改，导出补丁
        if ($hasLocalCommits -or $hasUncommittedChanges) {
            $patchFileName = "$($node.Name).patch"
            $patchFilePath = Join-Path $patchesDir $patchFileName

            # 使用 git diff 导出相对于远程的所有差异（包括已提交和未提交的）
            $remoteCommit = git rev-parse "$remoteBranch" 2>$null
            if ($remoteCommit) {
                # 导出从远程到当前工作区的完整差异
                git diff "$remoteCommit" HEAD -- | Out-File $patchFilePath -Encoding UTF8
                # 追加未提交的更改
                git diff HEAD -- | Out-File $patchFilePath -Encoding UTF8 -Append
                $patchFile = $patchFileName
                $patchCount++
                Write-Host "  ⚠ $($node.Name): 检测到本地修改，已导出补丁" -ForegroundColor Yellow
            }
        }

        # 记录远程 commit（用于恢复基准）而不是本地 commit
        $remoteCommit = git rev-parse "$remoteBranch" 2>$null
        if (-not $remoteCommit) { $remoteCommit = $commit }

        Pop-Location

        # 检查是否有对应的 fork 配置
        $forkUrl = $null
        $isFork = $false
        if ($forksConfig.ContainsKey($node.Name)) {
            $forkUrl = $forksConfig[$node.Name].fork_url
            $isFork = $true
        }

        $nodeList += [PSCustomObject]@{
            name = $node.Name
            url = $remoteUrl                  # 当前 origin URL
            fork_url = $forkUrl               # 用户的 fork URL（如果有）
            is_fork = $isFork                 # 是否有 fork
            commit = $remoteCommit            # 远程 commit（可从 GitHub 获取）
            local_commit = $commit            # 本地 commit（可能只存在于本地）
            branch = $branch
            has_local_changes = ($hasLocalCommits -or $hasUncommittedChanges)
            patch_file = $patchFile
        }
    }
}

$nodeListPath = Join-Path $backupPath "custom_nodes_list.json"
$nodeList | ConvertTo-Json -Depth 3 | Out-File $nodeListPath -Encoding UTF8
Write-Host "  ✓ 已导出 $($nodeList.Count) 个 custom nodes -> custom_nodes_list.json" -ForegroundColor Green
if ($patchCount -gt 0) {
    Write-Host "  ✓ 已导出 $patchCount 个本地修改补丁 -> patches/" -ForegroundColor Green
}

# ============================================================
# 2. 备份配置文件
# ============================================================
Write-Host "`n[2/6] 备份配置文件..." -ForegroundColor Cyan

$configFiles = @(
    "extra_model_paths.yaml",
    "user\default\comfy.settings.json"
)

$configBackupDir = Join-Path $backupPath "config"
New-Item -ItemType Directory -Path $configBackupDir -Force | Out-Null

foreach ($file in $configFiles) {
    if (Test-Path $file) {
        $destDir = Join-Path $configBackupDir (Split-Path $file -Parent)
        if ($destDir -and -not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item $file -Destination (Join-Path $configBackupDir $file) -Force
        Write-Host "  ✓ $file" -ForegroundColor Green
    }
}

# ============================================================
# 3. 备份 Workflows
# ============================================================
Write-Host "`n[3/6] 备份 Workflows..." -ForegroundColor Cyan

$workflowsDir = "user\default\workflows"
$workflowsBackup = Join-Path $backupPath "workflows"

if (Test-Path $workflowsDir) {
    Copy-Item $workflowsDir -Destination $workflowsBackup -Recurse -Force
    $count = (Get-ChildItem $workflowsBackup -Filter "*.json").Count
    Write-Host "  ✓ 已备份 $count 个 workflow" -ForegroundColor Green
}

# ============================================================
# 4. 备份 ComfyUI-Manager 数据
# ============================================================
Write-Host "`n[4/6] 备份 ComfyUI-Manager 数据..." -ForegroundColor Cyan

$managerDataDirs = @(
    "custom_nodes\ComfyUI-Manager\snapshots",
    "user\default\ComfyUI-Manager"
)

$managerBackup = Join-Path $backupPath "manager_data"
New-Item -ItemType Directory -Path $managerBackup -Force | Out-Null

foreach ($dir in $managerDataDirs) {
	if (Test-Path $dir) {
		$destName = $dir -replace "\\", "_" -replace "custom_nodes_", ""
		Copy-Item $dir -Destination (Join-Path $managerBackup $destName) -Recurse -Force
		Write-Host "  ✓ $dir" -ForegroundColor Green
	}
}

# ============================================================
# 附加：备份维护文档与工具脚本
# ============================================================
Write-Host "`n[附加] 备份维护文档和工具脚本..." -ForegroundColor Cyan

$toolsBackup = Join-Path $backupPath "tools"
New-Item -ItemType Directory -Path $toolsBackup -Force | Out-Null

$toolFiles = @(
	"ComfyUI_维护文档.md",
	"backup_comfyui.ps1",
	"restore_from_backup.ps1",
	"..\download_with_hfd.py",
	"..\download_workflow.py",
	"..\GitHub_Access_Solutions.md"
)

foreach ($tool in $toolFiles) {
	if (Test-Path $tool) {
		$name = Split-Path $tool -Leaf
		Copy-Item $tool -Destination (Join-Path $toolsBackup $name) -Force
		Write-Host "  ✓ $name" -ForegroundColor Green
	}
}

# ============================================================
# 5. 备份 custom_nodes 内的模型文件 (controlnet_aux 等)
# ============================================================
Write-Host "`n[5/6] 备份 custom_nodes 内的模型缓存..." -ForegroundColor Cyan

# 手动指定的关键目录（历史已踩过坑的路径）
$nodeModelDirs = @(
	"custom_nodes\comfyui_controlnet_aux\ckpts",
	"custom_nodes\comfyui-impact-pack\models",
	"custom_nodes\ComfyUI-SAM3\models"
)

# 智能扫描：自动发现 custom_nodes 下包含大体积模型文件的目录
$repoRoot = (Get-Location).Path
$modelExtensions = @(".safetensors", ".ckpt", ".pt", ".pth", ".bin", ".onnx", ".gguf", ".ggml")
$minSizeBytes = 5MB
$autoNodeModelDirsSet = New-Object System.Collections.Generic.HashSet[string]

Get-ChildItem "custom_nodes" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
	$ext = $_.Extension.ToLower()
	if ($modelExtensions -contains $ext -and $_.Length -ge $minSizeBytes) {
		$dirFull = $_.Directory.FullName
		if ($dirFull.ToLower().StartsWith($repoRoot.ToLower())) {
			$relativeDir = $dirFull.Substring($repoRoot.Length + 1) -replace '/', '\\'
			[void]$autoNodeModelDirsSet.Add($relativeDir)
		}
	}
}

$autoNodeModelDirs = @($autoNodeModelDirsSet) | Sort-Object
if ($autoNodeModelDirs.Count -gt 0) {
	Write-Host "  自动发现以下 node 模型目录：" -ForegroundColor Cyan
	foreach ($d in $autoNodeModelDirs) {
		Write-Host "    - $d" -ForegroundColor DarkCyan
	}
}

$nodeModelDirs = $nodeModelDirs + $autoNodeModelDirs | Select-Object -Unique

$nodeModelsBackup = Join-Path $backupPath "node_models"
New-Item -ItemType Directory -Path $nodeModelsBackup -Force | Out-Null

$nodeModelsIndex = @()

foreach ($dir in $nodeModelDirs) {
	if (Test-Path $dir) {
		$files = Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue
		if ($files.Count -eq 0) { continue }
		$size = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
		if ($size -gt 0) {
			$destName = $dir -replace "\\", "_" -replace "custom_nodes_", ""
			$destPath = Join-Path $nodeModelsBackup $destName
			Copy-Item $dir -Destination $destPath -Recurse -Force
			Write-Host "  ✓ $dir ($size MB)" -ForegroundColor Green

			$nodeModelsIndex += [PSCustomObject]@{
				source        = $dir
				backup_subdir = $destName
				size_mb       = $size
			}
		}
	}
}

if ($nodeModelsIndex.Count -gt 0) {
	$indexPath = Join-Path $backupPath "node_models_index.json"
	$nodeModelsIndex | ConvertTo-Json -Depth 3 | Out-File $indexPath -Encoding UTF8
}

# ============================================================
# 6. 记录模型文件清单（不复制大文件，只记录路径）
# ============================================================
Write-Host "`n[6/6] 记录模型文件信息..." -ForegroundColor Cyan

$modelPaths = @(
    "D:\ComfyUI_Official\resources\models",
    "models",
    "$env:USERPROFILE\.insightface",
    "$env:USERPROFILE\.cache\huggingface"
)

$modelInventory = @()
foreach ($path in $modelPaths) {
    if (Test-Path $path) {
        Get-ChildItem $path -Recurse -File | ForEach-Object {
            $modelInventory += [PSCustomObject]@{
                path = $_.FullName
                size_mb = [math]::Round($_.Length / 1MB, 2)
                modified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
}

$modelListPath = Join-Path $backupPath "models_inventory.json"
$modelInventory | ConvertTo-Json -Depth 3 | Out-File $modelListPath -Encoding UTF8
$totalSize = ($modelInventory | Measure-Object -Property size_mb -Sum).Sum / 1024
Write-Host "  ✓ 已记录 $($modelInventory.Count) 个模型文件 (共 $([math]::Round($totalSize, 2)) GB)" -ForegroundColor Green

if ($IncludeModels) {
    Write-Host "`n[额外] 备份模型文件 (这可能需要很长时间)..." -ForegroundColor Yellow
    # 使用 robocopy 增量备份
    foreach ($path in $modelPaths) {
        if (Test-Path $path) {
            $destPath = Join-Path $backupPath "models" (Split-Path $path -Leaf)
            robocopy $path $destPath /E /XO /R:1 /W:1 /NP /NFL /NDL
        }
    }
}

# ============================================================
# 完成
# ============================================================
Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                    ✅ 备份完成!                              ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green

Write-Host "备份位置: $backupPath" -ForegroundColor Yellow
Write-Host "`n备份内容:"
Get-ChildItem $backupPath | ForEach-Object { 
    $size = if ($_.PSIsContainer) { 
        (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum 
    } else { $_.Length }
    Write-Host "  - $($_.Name) ($([math]::Round($size/1KB, 1)) KB)"
}

Write-Host "`n提示: 如需恢复 custom nodes，运行 restore_custom_nodes.ps1" -ForegroundColor Cyan


