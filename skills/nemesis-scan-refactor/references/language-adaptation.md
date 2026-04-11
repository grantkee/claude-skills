# Language Adaptation Table

Shared reference for nemesis-scan phase agents. Detect the target language and adapt terminology accordingly. The questions and methodology are universal — only the vocabulary changes.

## Terminology Mapping

| Concept | Solidity | Move | Rust | Go | C++ |
|---------|----------|------|------|----|-----|
| Module/unit | contract | module | crate/mod | package | class/namespace |
| Entry point | external/public fn | public fun | pub fn | Exported fn | public method |
| State storage | storage variables | global storage / resources | struct fields / state | struct fields / DB | member variables |
| Access guard | modifier | access control / friend | trait bound / #[cfg] | middleware / auth | access specifier |
| Mapping | mapping(k => v) | Table\<K, V\> | HashMap / BTreeMap | map[K]V | std::map |
| Delete | delete mapping[key] | table::remove | map.remove(&key) | delete(map, key) | map.erase(key) |
| Caller identity | msg.sender | &signer | caller / Context | ctx / request.User | this / session |
| Error/abort | revert / require | abort / assert! | panic! / Result::Err | error / panic | throw / exception |
| Checked math | 0.8+ auto / SafeMath | built-in overflow abort | checked_add | math/big | safe int libs |
| External call | .call() / interface | cross-module call | CPI (Solana) | RPC / HTTP | virtual call |
| Test framework | Foundry / Hardhat | Move Prover / aptos test | cargo test | go test | gtest / catch2 |

## How to Use

1. At the start of analysis, detect the primary language from file extensions and project structure
2. Use the corresponding column for all terminology in your output
3. If the codebase is multi-language (e.g., Solidity + Rust), use each language's terms when discussing that layer
4. Do NOT force Solidity terminology onto non-Solidity code — adapt naturally
