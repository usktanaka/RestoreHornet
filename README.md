# RestoreHornet — TFS DB 復旧スクリプト集

SQL Server の `Tfs_Hornet` データベースをバックアップから復元するためのスクリプト群です。

---

## ファイル構成

| ファイル | 説明 |
|----------|------|
| `CheckLogChain.ps1` | トランザクションログの連続性を時間ベースで検証する |
| `RestoreTfs.ps1` | フル → 差分 → ログの順に RESTORE コマンドを生成・実行する |
| `CheckDB.ps1` | 復旧後に `DBCC CHECKDB` で整合性を確認する |

---

## バックアップファイルの命名規則

| パターン | 種別 |
|----------|------|
| `Tfs_Hornet_????F.bak` | フルバックアップ |
| `Tfs_Hornet_????D.bak` | 差分バックアップ |
| `Tfs_Hornet_????L.trn` | トランザクションログ |

---

## 📋 復旧手順（推奨フロー）

実行する前に、まずはセーフな検証をしてから本復旧を実行します。

### ステップ 1: ログの連続性確認

```powershell
.\CheckLogChain.ps1
```

- ログに大きなギャップがないか確認
- ファイル喪失がないか確認（`.log_inventory.txt` との差分）

---

### ステップ 2: 復旧スクリプトのドライラン

```powershell
# RestoreTfs.ps1 内の $ExecuteRestore = $false のまま実行
.\RestoreTfs.ps1
```

- 生成される RESTORE コマンドが正しいか確認
- フル → 差分 → ログの順序が正しいか確認

---

### ステップ 3: 本復旧実行

```powershell
# RestoreTfs.ps1 内の設定を変更してから実行
# $ExecuteRestore = $true
.\RestoreTfs.ps1
```

---

### ステップ 4: 復旧後の整合性確認

```powershell
.\CheckDB.ps1
```

- `DBCC CHECKDB` で論理破損がないか確認
- ログファイル（`E:\Backup\TFS\DBCC_CHECKDB_*.log`）で結果を確認

---

## ⚠️ 実行前チェックリスト

- [ ] SQL Server が起動している
- [ ] バックアップファイルがすべて `E:\Backup\TFS` に存在する
- [ ] `Tfs_Hornet` DB が NORECOVERY 状態に置ける（接続クライアントがない）
- [ ] ログファイル出力先 `E:\Backup\TFS` に書き込み権限がある
- [ ] 十分なディスク容量がある（復旧中は 2 倍必要な場合もある）

---

## 🔧 各スクリプトの設定値

### RestoreTfs.ps1

| 変数 | デフォルト値 | 説明 |
|------|-------------|------|
| `$BackupDir` | `E:\Backup\TFS` | バックアップ格納先 |
| `$DatabaseName` | `Tfs_Hornet` | 復旧対象 DB 名 |
| `$SqlInstance` | `localhost` | SQL Server インスタンス |
| `$ExecuteRestore` | `$false` | `$true` にすると実際に復旧を実行 |

### CheckLogChain.ps1

| 変数 | デフォルト値 | 説明 |
|------|-------------|------|
| `$MaxLogGapHours` | `25` | ログ間隔の最大許容時間（時間単位） |

### CheckDB.ps1

| 変数 | デフォルト値 | 説明 |
|------|-------------|------|
| `$CommandTimeoutSec` | `3600` | DBCC CHECKDB のタイムアウト（秒） |
| `$RepairOption` | `NOREPAIR` | `REPAIR_REBUILD` / `REPAIR_ALLOW_DATA_LOSS` も選択可 |

---

## 事前確認コマンド

SQL Server のバージョン確認:

```powershell
sqlcmd -S localhost -Q "SELECT @@VERSION"
```

バックアップファイルの確認:

```powershell
Get-ChildItem E:\Backup\TFS | Where-Object { $_.Name -match "\.bak$|\.trn$" } | Sort-Object LastWriteTime -Descending
```

DB の現在の状態確認:

```powershell
sqlcmd -S localhost -Q "SELECT state_desc FROM sys.databases WHERE name='Tfs_Hornet'"
```

---

## 注記

- `CheckLogChain.ps1` は `LastWriteTime` による時間ベースの簡易チェックです。
  より正確な検証には SQL Server バックアップヘッダー情報の確認を推奨します：
  ```sql
  RESTORE HEADERONLY FROM DISK='<backup file>' WITH NO_INFOMSGS
  ```
- HDD 障害による一部ファイル喪失がある場合、ログチェーンが途切れる可能性があります。
  その場合は途切れた直前の時点までの復旧が上限となります。
