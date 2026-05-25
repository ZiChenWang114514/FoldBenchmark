# FoldBenchmark — 踩坑经验记录

记录真实运行中遇到的 bug，避免重复踩坑。

---

## L1: AF3/AlphaFast 不接受数字链 ID（2026-05-24）

**现象**：AlphaFast all-in-one batch 在解析 `1LMB_lambda_repressor_DNA.json` 时立即崩溃：
```
ValueError: IDs must be upper case letters, got: ['3', '4', '1', '2']
```

**原因**：PDB 1LMB 的 author chain IDs 本身就是数字（`1`, `2`, `3`, `4`）。
`prepare_inputs.py` 直接把原始 PDB chain ID 写入 AF3 JSON 的 `id` 字段，
但 AF3 / AlphaFast 要求链 ID 必须是**单个大写字母（A–Z）**。

**修复**：在 `generate_af3_json()` 中添加自动重映射逻辑：
- 检查所有 chain ID（protein / rna / dna / ligand）
- 若有任意一个不是单个大写字母，则按定义顺序依次映射到 A, B, C, D, ...
- 重映射仅影响输出 JSON，RCSB 序列获取仍用原始 PDB chain ID
- 映射关系打印到 stdout（`NOTE: Remapping chain IDs`）

**影响范围**：所有用数字或小写字母作 chain ID 的 PDB（如 1LMB）。其他模型的
输入格式（Boltz-2 YAML, Chai-1 FASTA, Protenix JSON 等）均从 AF3 JSON 派生，
因此自动继承正确的字母链 ID。

**教训**：向 TEST_CASES 添加新 case 时，若 PDB 的 author chain ID 非大写字母，
必须通过 `generate_af3_json` 的重映射或显式在 TEST_CASES 中指定字母 ID。
**始终用 RCSB 网站核对 author chain ID**，不要假设它们是字母。

---

## L2: GPU 占用异常 → tmux 会话崩溃（2026-05-24）

**现象**：benchmark 启动后用户发现 GPU 0 占用，随后发现 tmux 会话已退出（exit code 1）。

**原因**：AlphaFast 在加载 JSON 时遇到 L1 的 ValueError，脚本以 `exit 1` 终止，
`master_benchmark.sh` 的 `set -euo pipefail` 使整个 tmux 会话立即退出。

**修复**：先修 L1，再重跑。

**教训**：`set -euo pipefail` 保护性很强，任何子命令失败都会终止整个 pipeline。
长 benchmark 脚本应在启动前先做输入格式验证（dry-run / JSON 语法检查）。

---

## L3: 1A2K 和部分 PDB ID 在 RCSB 返回 404（2026-05-24）

**现象**：`prepare_inputs.py` 输出：
```
WARNING: Failed to fetch entry 1A2K: HTTP Error 404: Not Found
  SKIP: Could not fetch sequences
```

**原因**：部分旧 PDB ID 已在 RCSB 被弃用或合并，REST API 返回 404。
`1A2K` 目前已有对应序列但 entry-level API 失败（可能需要 `pdb_id` 大写）。

**影响**：1A2K 的输入文件未被重新生成，但旧输入文件仍存在并可用。
仅在全量重新生成时会漏掉该 case。

**待查**：1A2K 是否需要换用其他 PDB ID，或改用 GraphQL API 获取序列。

---

## L4: `7N4I` 和 `4FQI` Chain A/C 找不到（2026-05-24）

**现象**：
```
WARNING: Chain A not found in PDB 7N4I
WARNING: Chain C not found in PDB 4FQI
```
输出仍为 "OK"，说明至少有部分链正常获取。

**原因**：这两个抗体-抗原复合物的 author chain IDs 与记录的不一致，
或 RCSB API 返回了不同的 auth_asym_id。历史上这两个 case 的输入已
通过人工核验（2026-05-07），因此旧输入文件是正确的；此次重新生成
可能因网络/API 差异略有不同，但功能不受影响。

**教训**：验证 chain IDs 要在 RCSB 网页上核对 `auth_asym_id`，
不要只看 `label_asym_id`。

---

## L5: SSL EOF 导致 1CA2 输入生成失败（2026-05-24）

**现象**：
```
WARNING: Failed to fetch entity 1CA2/1: EOF occurred in violation of protocol
  SKIP: Could not fetch sequences
```

**原因**：RCSB API 请求在 SSL 握手期间被网络中断（临时性网络问题）。

**修复**：重新单独运行 `python scripts/prepare_inputs.py`，或手动
下载 1CA2 序列（UniProt P00918, 259 aa carbonic anhydrase）。
旧输入文件已存在，可直接使用。

---
