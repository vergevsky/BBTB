# Vendored Binaries

This directory holds binary frameworks **not** committed to git.

## libbox.xcframework

Download from [SagerNet/sing-box releases](https://github.com/SagerNet/sing-box/releases/tag/v1.13.11)
the `libbox.xcframework.tar.gz` artifact, unpack into this directory so that the
path is:

`BBTB/Vendored/libbox.xcframework/`

Wave 3 (`01-W3-base-tunnel-PLAN.md`) link'ает этот xcframework через `Packages/ProtocolEngine/Package.swift` через `binaryTarget(path: "../../Vendored/libbox.xcframework")`.

Альтернатива: собрать самостоятельно:

```bash
git clone https://github.com/SagerNet/sing-box.git
cd sing-box
gomobile bind -target ios,iossimulator,macos -o libbox.xcframework ./experimental/libbox
```

Требует Go 1.24+ и `golang.org/x/mobile`. См. `.planning/phases/01-foundation/01-RESEARCH.md` §0 «Installation» для деталей.
