// ServerScore.swift — D-03: pure-function autoSelect.
// Phase 3 / Plan 02.

import Foundation

/// Pure-function namespace для server selection logic.
///
/// Нет IO, нет actor — testable изолированно от network (см. AutoSelectTests).
/// Consumer (MainScreenViewModel в Plan 05) подаёт уже посчитанные score'ы.
public enum ServerScore {

    /// Выбирает сервер с минимальным score из достижимых. Кандидаты с nil score
    /// (unreachable) отфильтровываются. Возвращает nil если empty или все nil.
    ///
    /// - Parameter candidates: пары (id, score). nil score означает «unreachable».
    /// - Returns: id сервера с минимальным score, либо nil.
    public static func autoSelect(_ candidates: [(id: UUID, score: Double?)]) -> UUID? {
        candidates
            .compactMap { entry in entry.score.map { (entry.id, $0) } }
            .min(by: { $0.1 < $1.1 })?
            .0
    }
}
