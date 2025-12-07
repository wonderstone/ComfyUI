# ComfyUI 从备份恢复脚本
# 运行方式: powershell -ExecutionPolicy Bypass -File restore_from_backup.ps1 -BackupPath "D:\ComfyUI_Backup\20231205_120000"

param(
	[Parameter(Mandatory=$true)]
	[string]$BackupPath,
	[switch]$RestoreNodes = $true,
	[switch]$RestoreConfig = $true,
	[switch]$RestoreWorkflows = $true,
	[switch]$RestoreNodeModels = $true
)

$ErrorActionPreference = "Stop"

Write-Host @"
╔══════════════════════════════════════════════════════════════╗
║              ComfyUI 恢复工具 v1.0                           ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

if (-not (Test-Path $BackupPath)) {
    Write-Host "错误: 备份目录不存在: $BackupPath" -ForegroundColor Red
    exit 1
}

Write-Host "从备份恢复: $BackupPath" -ForegroundColor Yellow

# ============================================================
# 1. 恢复 Custom Nodes
# ============================================================
if ($RestoreNodes) {
    Write-Host "`n[1/3] 恢复 Custom Nodes..." -ForegroundColor Cyan
    
    $nodeListPath = Join-Path $BackupPath "custom_nodes_list.json"
    if (Test-Path $nodeListPath) {
        $nodes = Get-Content $nodeListPath | ConvertFrom-Json
        
        $nodesDir = "custom_nodes"
        if (-not (Test-Path $nodesDir)) {
            New-Item -ItemType Directory -Path $nodesDir -Force | Out-Null
        }
        
        foreach ($node in $nodes) {
            $nodePath = Join-Path $nodesDir $node.name
            
            if (Test-Path $nodePath) {
                Write-Host "  - 跳过 (已存在): $($node.name)" -ForegroundColor Gray
                continue
            }
            
            Write-Host "  克隆: $($node.name)..." -ForegroundColor Yellow
            
            # 尝试使用镜像
            $url = $node.url
            if ($url -match "github\.com") {
                $mirrorUrl = $url -replace "github\.com", "gitclone.com/github.com"
                try {
                    git clone --depth 1 $mirrorUrl $nodePath 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        # 恢复原始 remote
                        Push-Location $nodePath
                        git remote set-url origin $url
                        Pop-Location
                        Write-Host "    ✓ 成功 (镜像)" -ForegroundColor Green
                        continue
                    }
                } catch {}
            }
            
            # 尝试原始 URL
            try {
                git clone --depth 1 $url $nodePath 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "    ✓ 成功" -ForegroundColor Green
                } else {
                    Write-Host "    ✗ 失败" -ForegroundColor Red
                }
            } catch {
                Write-Host "    ✗ 失败: $_" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  ⚠ 未找到 custom_nodes_list.json" -ForegroundColor Yellow
    }
}

# ============================================================
# 2. 恢复配置文件
# ============================================================
if ($RestoreConfig) {
    Write-Host "`n[2/3] 恢复配置文件..." -ForegroundColor Cyan
    
    $configBackup = Join-Path $BackupPath "config"
    if (Test-Path $configBackup) {
        Get-ChildItem $configBackup -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($configBackup.Length + 1)
            $destPath = $relativePath
            
            $destDir = Split-Path $destPath -Parent
            if ($destDir -and -not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            Copy-Item $_.FullName -Destination $destPath -Force
            Write-Host "  ✓ $relativePath" -ForegroundColor Green
        }
    }
}

# ============================================================
# 3. 恢复 Workflows
# ============================================================
if ($RestoreWorkflows) {
	Write-Host "`n[3/4] 恢复 Workflows..." -ForegroundColor Cyan
	
	$workflowsBackup = Join-Path $BackupPath "workflows"
	$workflowsDest = "user\default\workflows"
	
	if (Test-Path $workflowsBackup) {
		if (-not (Test-Path $workflowsDest)) {
			New-Item -ItemType Directory -Path $workflowsDest -Force | Out-Null
		}
		
		$copied = 0
		Get-ChildItem $workflowsBackup -Filter "*.json" | ForEach-Object {
			$destFile = Join-Path $workflowsDest $_.Name
			if (-not (Test-Path $destFile)) {
				Copy-Item $_.FullName -Destination $destFile
				$copied++
			}
		}
		Write-Host "  ✓ 恢复了 $copied 个 workflow" -ForegroundColor Green
	}
}

# ============================================================
# 4. 恢复 custom_nodes 内的模型缓存 (node_models)
# ============================================================
if ($RestoreNodeModels) {
	Write-Host "`n[4/4] 恢复 custom_nodes 内的模型缓存..." -ForegroundColor Cyan
	
	$nodeModelsBackup = Join-Path $BackupPath "node_models"
	$indexPath = Join-Path $BackupPath "node_models_index.json"
	
	if (-not (Test-Path $nodeModelsBackup) -or -not (Test-Path $indexPath)) {
		Write-Host "  - 未找到 node_models 备份或索引，跳过。" -ForegroundColor Gray
	} else {
		$index = Get-Content $indexPath | ConvertFrom-Json
		if ($index -is [System.Array]) {
			$entries = $index
		} else {
			$entries = @($index)
		}
		
		$restored = 0
		foreach ($entry in $entries) {
			$source = $entry.source
			$backupSubdir = $entry.backup_subdir
			$srcDir = Join-Path $nodeModelsBackup $backupSubdir
			
			if (-not (Test-Path $srcDir)) {
				Write-Host "  - 跳过 (备份目录不存在): $backupSubdir" -ForegroundColor Gray
				continue
			}
			
			$destDir = Split-Path $source -Parent
			if ($destDir -and -not (Test-Path $destDir)) {
				New-Item -ItemType Directory -Path $destDir -Force | Out-Null
			}
			
			try {
				Copy-Item $srcDir\* -Destination $source -Recurse -Force
				Write-Host "  ✓ $source" -ForegroundColor Green
				$restored++
			} catch {
				Write-Host "  ✗ 恢复失败: $source ($_ )" -ForegroundColor Red
			}
		}
		Write-Host "  共恢复 $restored 个 node 模型目录" -ForegroundColor Green
	}
}

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                    ✅ 恢复完成!                              ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green

Write-Host "`n提示: 请重启 ComfyUI 使更改生效" -ForegroundColor Cyan

