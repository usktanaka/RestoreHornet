# ============================================
# TFS トランザクションログチェーン検証スクリプト
# ============================================

$BackupDir    = "E:\Backup\TFS"
$DatabaseName = "Tfs_Hornet"
$MaxLogGapHours = 25  # ログ間隔の最大許容時間（運用に応じて調整）
$HistoryFile  = Join-Path $BackupDir ".log_inventory.txt"

Write-Host "=== ログチェーン検証開始 ===" -ForegroundColor Cyan

$files = Get-ChildItem $BackupDir | Sort-Object LastWriteTime

$full = $files | Where-Object { $_.Name -match "F\.bak$" } | Sort-Object LastWriteTime
$diff = $files | Where-Object { $_.Name -match "D\.bak$" } | Sort-Object LastWriteTime
$logs = $files | Where-Object { $_.Name -match "L\.trn$" } | Sort-Object LastWriteTime

if ($full.Count -eq 0) {
    Write-Error "フルバックアップがありません。"
    exit
}

# ======================================
# ■ ファイル喪失チェック
# ======================================

if (Test-Path $HistoryFile) {
    $previousLogs = @(Get-Content $HistoryFile | Where-Object { $_ -match "\.trn$" })
    $currentLogs = @($logs | ForEach-Object { $_.FullName })
    
    $missing = @($previousLogs | Where-Object { $_ -notin $currentLogs })
    if ($missing.Count -gt 0) {
        Write-Warning "削除されたログが検出されました:"
        $missing | ForEach-Object { Write-Host "  - $_" }
    }
}

# 現在のインベントリを保存（次回の比較用）
@($full; $diff; $logs) | ForEach-Object { $_.FullName } | Set-Content $HistoryFile -Force

$fullBackup = $full[-1]
$diffBackup = $null
if ($diff.Count -gt 0) { $diffBackup = $diff[-1] }

# 差分がフルより古いかチェック
if ($diffBackup -and $diffBackup.LastWriteTime -lt $fullBackup.LastWriteTime) {
    Write-Warning "⚠ 差分バックアップがフルより古いです（復旧スキャンから除外）"
    $diffBackup = $null
}

Write-Host "使用予定フル: $($fullBackup.Name) ($($fullBackup.LastWriteTime))"
if ($diffBackup) { Write-Host "使用予定差分: $($diffBackup.Name) ($($diffBackup.LastWriteTime))" }

# フル（＋差分）以降のログを抽出
$baseTime = $fullBackup.LastWriteTime
if ($diffBackup) { $baseTime = $diffBackup.LastWriteTime }

$logChain = $logs | Where-Object {
    $_.LastWriteTime -gt $baseTime
} | Sort-Object LastWriteTime

Write-Host "`n検証対象ログ本数: $($logChain.Count)"
Write-Host "対象期間: $baseTime ～ $(($logChain[-1].LastWriteTime))"

if ($logChain.Count -eq 0) {
    Write-Warning "適用対象のログがありません。"
    exit
}

# ======================================
# ■ 連続性チェック（時間ベース）
# ======================================

Write-Host "`n=== ログ間隔チェック（最大許容: ${MaxLogGapHours}時間） ===" -ForegroundColor Cyan

$prev = $null
$issues = @()
$logDetails = @()

foreach ($log in $logChain) {
    if ($prev -ne $null) {
        $delta = $log.LastWriteTime - $prev.LastWriteTime
        $hours = [math]::Round($delta.TotalHours, 2)
        
        $logDetails += [PSCustomObject]@{
            From  = $prev.Name
            To    = $log.Name
            Gap   = "$hours 時間"
            Alert = $($hours -gt $MaxLogGapHours ? "⚠ 長" : "✓")
        }

        # 最大許容時間を超えたら警告
        if ($delta.TotalHours -gt $MaxLogGapHours) {
            $issues += "ログ間隔が長すぎます: $($prev.Name) -> $($log.Name) ($hours 時間)"
        }
    }
    $prev = $log
}

$logDetails | Format-Table -AutoSize

if ($issues.Count -eq 0) {
    Write-Host "`n✓ ログチェーンに大きなギャップは見られません" -ForegroundColor Green
} else {
    Write-Warning "=== ログチェーンに疑わしい箇所があります ==="
    $issues | ForEach-Object { Write-Host "  $_" }
}

Write-Host "`n=== 検証終了 ===" -ForegroundColor Cyan
Write-Host "注記:" -ForegroundColor Yellow
Write-Host "  • このスクリプトは LastWriteTime による時間ベースの簡易チェックです"
Write-Host "  • 本格的な検証には SQL Server バックアップヘッダー情報の確認をお勧めします："
Write-Host "    例) RESTORE HEADERONLY FROM DISK='<backup file>' WITH NO_INFOMSGS"
Write-Host "  • ファイル喪失検出（.log_inventory.txt）を使用しています"
