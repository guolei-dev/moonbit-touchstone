# Development contract

- Implement the frozen scope in docs/SCOPE.md; do not declare completion while checkpoints remain open.
- Keep parsing, matrices and RF operations in MoonBit. Node may only handle files, CLI arguments and the compiled bridge.
- Comment units, matrix orientation, normalization, loss of metadata and numerical rejection conditions, with standard references. Do not narrate obvious statements.
- Commit working semantic milestones, with actual checks and remaining limits in the body. No empty commits or history rewriting for counts.
- Add meaningful independent and boundary tests for numerical/format changes. Avoid mirroring the implementation as the sole oracle.
- Run scoped checks; after they pass, broaden only for changed contracts or unresolved concerns. Record local and remote evidence separately.
- This is a local-review namespace, not a published package. Do not invent a remote owner or claim remote CI succeeded.
