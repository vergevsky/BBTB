// OnboardingView.figma.swift
//
// Figma Code Connect mapping — `1. Onboarding Screen` frame → `OnboardingView` SwiftUI view.
//
// **Status (2026-05):** Documentation contract. Not published (Education plan).
//
// **Figma source:** `1. Onboarding Screen` (frame in iOS page)
// URL: https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg/BBTB-v3?node-id=3062-304
//
// **Inner sub-components (NOT separately mapped):**
//   - `PrimaryButton` (3062:345) — «Добавить из буфера», accent green pill
//   - `SecondaryButton` (3062:348) — «Сканировать QR-код», white outlined pill
//   - `OnboardingActions` (3062:315) — bottom CTA container
//
// **Pixel-perfect spec (see CODE-CONNECT.md §1.7 and §3 typography):**
//   - hero text "Интернет, каким он должен быть" — SF Pro Expanded Semibold 16 split into:
//     "Интернет, каким он " white + "должен быть" accent green (#14664B)
//   - "Добавьте конфигурацию" hint — SF Pro Expanded Light 10 (Tips style), grayWarmDim
//   - Primary button fill: #14664B accent, white text, 49pt height, full-width
//   - Secondary button: white fill, accent text, 49pt height
//   - Both buttons have small corner radius (likely DS.Radius.button = 12pt)
//
// **TODO before publish:** add `MainScreenViewModel.preview` static helper. When CodeConnect
// package added and `figma connect publish` запускается, тут компилятор подскажет, что нужно
// добавить — это намеренно (force-update preview helpers).

#if canImport(CodeConnect)
import CodeConnect
import SwiftUI

struct OnboardingView_doc: FigmaConnect {
    let component = OnboardingView.self
    let figmaNodeUrl = "https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg/BBTB-v3?node-id=3062-304"

    var body: some View {
        // NOTE: `MainScreenViewModel.preview` will be needed at publish time.
        // Add it as `public static let preview = MainScreenViewModel(...)` in
        // MainScreenViewModel.swift with mocked dependencies.
        OnboardingView(
            viewModel: MainScreenViewModel.preview,
            onPaste: {},
            onScanQR: {},
            onDismiss: {}
        )
    }
}
#endif
