// PhosphorReexport.swift — 2026-05-16 design pass.
//
// Делает Phosphor Icons (`Ph` namespace) частью DesignSystem surface — features,
// которые делают `import DesignSystem`, автоматически получают доступ к
// `Ph.list.bold`, `Ph.plus.bold` и пр. без явного `import PhosphorSwift`.
//
// Иконки — часть design system по той же причине, что и DS.Color / DS.Typography:
// единый icon family консистентен по всему приложению (Figma BBTB v3 spec).
//
// `@_exported` underscored, но стабильно используется в SPM ecosystem
// (Foundation / Glibc / etc.); fallback при необходимости — explicit
// `import PhosphorSwift` в consumer-features.

@_exported import PhosphorSwift
