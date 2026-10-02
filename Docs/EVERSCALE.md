# Everscale support in TonSdkSwift

Baseline: TON SDK 1.4.3 (`5dd7e33`). TON remains the default;
compatibility with `ever_block` 1.11.22 rules is explicitly enabled.

## Key changes

- `Cell`, `CellBuilder.cell`, `Boc.deserialize`: added `compatibility: .everscale`.
  Descriptor masks differ when computing higher-level hashes, especially for gapped level masks.
  Incompatible TON/Everscale subtrees and roots cannot be mixed within one BOC.
- Depth: TON allows up to 1024; Everscale has a numerical limit of 65534.
  The decoder also enforces `maxDepth` (default: 2048); tested up to 2049.
  Safe handling of a chain with depth 65534 in Swift is not guaranteed.
- Big cells: `Cell(bigData:)`, up to `0xffffff` bytes, no references, SHA-256 of the payload.
  Reading requires `allowBigCells: true`; an ordinary parent must use `.everscale`.
- Legacy BOCs can explicitly use `validateIndex: false` and `checkMerkleMetadata: false`.
  CRC validation remains enabled; these options do not authenticate a Merkle proof.
- SDK virtualization caps the effective level according to TON rules.
  The consumer retains its Everscale level-offset adapter; virtual views cannot be serialized to BOC.
  Wrapping subclasses preserves their overridden `Cell.bits` / `refs` behavior.
- Added generic `Cell` views, `UsageTree`, Merkle proof/update operations and dictionaries:
  `RawHashmap`, `HashmapAugE`, `TypedHashmapAugE`, `PfxHashmapE`.
  Dictionary builders create TON cells; descendants that depend on Everscale rules need a consumer adapter.
- Also fixed BOC handling (multiple roots, shared references, indexes, validation),
  ordinary dictionaries, StateInit and message serialization. These fixes apply across the SDK.

## Added test suites

Files are in `Tests/TonSdkSwiftTests`:

```text
AugmentedDictionaryTests
BOCOrderingAuditTests
CellCoreAuditTests
CellViewsRegressionTests
DictionaryAuditRegressionTests
GenericMerkleRegressionTests
HashmapRegressionTests
MalformedBOCRegressionTests
MessageWireAuditTests
MessageWireRegressionTests
PrefixDictionaryTests
RawDictionaryTests
StateInitMessageRegressionTests
UpstreamBaselineRegressionTests
UpstreamCellBOCRegressionTests
ViewMerkleAuditTests
```
