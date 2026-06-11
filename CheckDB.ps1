# ============================================
# 復旧後 DBCC CHECKDB 実行スクリプト
# ============================================

$DatabaseName     = "Tfs_Hornet"
$SqlInstance      = "localhost"   # 必要に応じて変更
$LogFile          = "E:\Backup\TFS\DBCC_CHECKDB_$($DatabaseName)_$(Get-Date -Format yyyyMMdd_HHmmss).log"
$CommandTimeoutSec = 3600         # DBCC CHECKDB はデータサイズに応じて時間がかかるため（大規模DB用）
$RepairOption     = "NOREPAIR"    # NOREPAIR / REPAIR_REBUILD / REPAIR_ALLOW_DATA_LOSS

Write-Host "=== DBCC CHECKDB 開始: $DatabaseName ===" -ForegroundColor Cyan
Write-Host "ログファイル: $LogFile"
Write-Host "タイムアウト: ${CommandTimeoutSec}秒`n"

# 修復オプション警告
if ($RepairOption -ne "NOREPAIR") {
    Write-Warning "修復オプション($RepairOption)が有効です。実行前に確認してください。"
}

# DBCC CHECKDB クエリ生成
$query = @"
DBCC CHECKDB([$DatabaseName]) WITH $RepairOption;
"@

try {
    Write-Host "実行中..."
    
    # メッセージ出力キャプチャ付き実行
    $result = Invoke-Sqlcmd `
        -ServerInstance $SqlInstance `
        -Query $query `
        -QueryTimeout $CommandTimeoutSec `
        -ErrorAction Stop `
        -WarningAction SilentlyContinue
    
    $output = @()
    $output += "=== DBCC CHECKDB 実行結果 ==="
    $output += "実行日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $output += "データベース: $DatabaseName"
    $output += "修復オプション: $RepairOption"
    $output += ""
    
    if ($result) {
        $output += "■ 検査結果:"
        $output += $result | Out-String
    } else {
        $output += "検査結果なし。（エラーが検出されなかった可能性があります）"
    }
    
    # ログファイルに出力
    $output | Out-File -FilePath $LogFile -Encoding UTF8
    
    Write-Host "✓ DBCC CHECKDB 完了" -ForegroundColor Green
    Write-Host "ログファイル: $LogFile" -ForegroundColor Cyan
}
catch {
    $errorMsg = $_.Exception.Message
    
    # ログファイルに出力
    @(
        "=== DBCC CHECKDB 実行エラー ==="
        "実行日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "データベース: $DatabaseName"
        ""
        "エラーメッセージ:"
        $errorMsg
        ""
        "※ DBCC で破損が検出された場合、別途修復処理が必要です"
    ) | Out-File -FilePath $LogFile -Encoding UTF8
    
    Write-Error "DBCC CHECKDB 実行中にエラーが発生しました:`n$errorMsg`n`nログ: $LogFile"
    exit 1
}

Write-Host "`n=== 注記 ===" -ForegroundColor Yellow
Write-Host "• NO_INFOMSGS は削除しました（SQL Server 2019+ では ALL_ERRORMSGS は非推奨）"
Write-Host "• 破損が検出された場合は、REPAIR_REBUILD の使用を検討してください"
Write-Host "• 詳細はログファイルを確認してください: $LogFile"
