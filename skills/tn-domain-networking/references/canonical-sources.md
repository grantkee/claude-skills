# Networking-domain canonical sources

| Value | Source | Avoid |
|---|---|---|
| Swarm | `ConsensusNetwork` from `spawn_node_networks` | Per-epoch construction |
| Topic name | `LibP2pConfig::*_topic_for(epoch)` | Hardcoded strings |
| Active peer set | Committee for current epoch + configured observers | Live peer list (includes retired) |
| Peer score | Per-peer accumulator (metered events) | Boolean trust |
| Request timeout | Per-protocol config | Default tokio timeout |
| Pending fetch cap | Per-peer + per-protocol | Unbounded |
| Mesh size | Gossipsub config | Default if not set |
| Cross-epoch validation | Signature against `msg.epoch`'s committee | Peer's claimed epoch alone |
