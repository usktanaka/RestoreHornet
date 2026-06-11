# ============================================
# TFS DB 自動復旧スクリプト
# ============================================

# 設定
$BackupDir = "E:\Backup\TFS"
$DatabaseName = "Tfs_Hornet"
$SqlInstance = "localhost"   # 必要に応じて変更
$ExecuteRestore = $false      # true にすると実際に復旧を実行

Write-Host "=== バックアップファイルをスキャン中 ==="

# ファイル一覧取得
$files = Get-ChildItem $BackupDir | Sort-Object LastWriteTime

# フル・差分・ログ分類
$full = $files | Where-Object { $_.Name -match "F\.bak$" } | Sort-Object LastWriteTime
$diff = $files | Where-Object { $_.Name -match "D\.bak$" } | Sort-Object LastWriteTime
$logs = $files | Where-Object { $_.Name -match "L\.trn$" } | Sort-Object LastWriteTime

if ($full.Count -eq 0) {
    Write-Error "フルバックアップが見つかりません。復旧できません。"
    exit
}

$fullBackup = $full[-1]   # 最新のフル
Write-Host "フルバックアップ: $($fullBackup.Name)"

# 差分があれば最新を使う
$diffBackup = $null
if ($diff.Count -gt 0) {
    $diffBackup = $diff[-1]
    Write-Host "差分バックアップ: $($diffBackup.Name)"
} else {
    Write-Host "差分バックアップなし（フル → ログで復旧）"
}

# 差分があれば検証
if ($diffBackup -and $diffBackup.LastWriteTime -lt $fullBackup.LastWriteTime) {
    Write-Error "差分バックアップ($($diffBackup.Name))がフル($($fullBackup.Name))より古いです。復旧できません。"
    exit
}

# ログチェーン（最後のバックアップより後のもの）
$lastBackupTime = $diffBackup ? $diffBackup.LastWriteTime : $fullBackup.LastWriteTime
$logChain = $logs | Where-Object {
    $_.LastWriteTime -gt $lastBackupTime
} | Sort-Object LastWriteTime

Write-Host "ログ本数: $($logChain.Count)"

# ============================================
# RESTORE コマンド生成
# ============================================

$restoreCommands = @()

# 1. フル
$restoreCommands += @"
-- ■ フルバックアップ復元
RESTORE DATABASE [$DatabaseName]
FROM DISK = '$($fullBackup.FullName)'
WITH NORECOVERY;
"@

# 2. 差分
if ($diffBackup) {
$restoreCommands += @"
-- ■ 差分バックアップ復元 ($($diffBackup.LastWriteTime))
RESTORE DATABASE [$DatabaseName]
FROM DISK = '$($diffBackup.FullName)'
WITH NORECOVERY;
"@
}

# 3. ログ
if ($logChain.Count -gt 0) {
    $restoreCommands += "-- ■ トランザクションログ復元"
}
foreach ($log in $logChain) {
    $isLast = ($log -eq $logChain[-1])
    $recovery = $isLast ? "RECOVERY" : "NORECOVERY"

$restoreCommands += @"
RESTORE LOG [$DatabaseName]
FROM DISK = '$($log.FullName)'
WITH $recovery;
"@
}

if ($logChain.Count -eq 0) {
    Write-Host "警告: トランザクションログがありません。最新ポイントまで復旧できません。" -ForegroundColor Yellow
}

# ============================================
# 出力
# ============================================

Write-Host "`n=== 生成された RESTORE コマンド ==="
$restoreCommands | ForEach-Object { Write-Host $_ }

# ============================================
# 実行
# ============================================

if ($ExecuteRestore) {
    Write-Host "`n=== SQL Server に復旧を実行します ==="

    try {
        foreach ($cmd in $restoreCommands) {
            Write-Host "実行中: $cmd"
            Invoke-Sqlcmd -ServerInstance $SqlInstance -Query $cmd -ErrorAction Stop
        }
        Write-Host "=== 復旧完了 ===" -ForegroundColor Green
    }
    catch {
        Write-Error "復旧中にエラーが発生しました: $_"
        exit 1
    }
} else {
    Write-Host "`n※ ExecuteRestore = false のため実行しません（Dry-run）"
}
