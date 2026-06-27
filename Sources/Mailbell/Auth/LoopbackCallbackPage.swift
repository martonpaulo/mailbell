// swiftlint:disable file_length
import Foundation

enum LoopbackCallbackPage {
    enum State {
        case success
        case error(ErrorReason)

        var dataState: String {
            switch self {
            case .success:
                "success"
            case .error:
                "error"
            }
        }
    }

    enum ErrorReason: Equatable {
        case providerError(String)
        case missingState
        case stateMismatch
        case missingCode
        case alreadyHandled
        case serverUnavailable
        case unexpectedPath
        case unsupportedMethod
    }

    static func html(state: State) -> String {
        let content = CallbackPageContent(state: state)
        return callbackPageTemplate
            .replacingOccurrences(of: "{{stateClass}}", with: content.stateClass)
            .replacingOccurrences(of: "{{title}}", with: content.title)
            .replacingOccurrences(of: "{{iconDataURI}}", with: callbackPageIconDataURI)
            .replacingOccurrences(of: "{{badgeSVG}}", with: content.badgeSVG)
            .replacingOccurrences(of: "{{eyebrow}}", with: content.eyebrow)
            .replacingOccurrences(of: "{{message}}", with: content.message)
            .replacingOccurrences(of: "{{detailsHTML}}", with: content.detailsHTML)
            .replacingOccurrences(of: "{{footnote}}", with: content.footnote)
    }
}

private struct CallbackPageContent {
    let stateClass: String
    let eyebrow: String
    let title: String
    let message: String
    let footnote: String
    let badgeSVG: String
    let detailsHTML: String

    init(state: LoopbackCallbackPage.State) {
        switch state {
        case .success:
            stateClass = state.dataState
            eyebrow = "Google sign-in complete"
            title = "Mailbell connected"
            message = "You can close this tab and return to Mailbell."
            detailsHTML = ""
            footnote = "Mailbell will continue from the menu bar. No email content is shown on this page."
            badgeSVG = """
            <svg viewBox="0 0 32 32" aria-hidden="true" focusable="false">
                <path d="M9 16.5l4.4 4.4L23 11.5"></path>
            </svg>
            """
        case let .error(reason):
            stateClass = state.dataState
            eyebrow = "Google sign-in stopped"
            title = "Mailbell could not connect"
            message = "Return to Mailbell and try signing in again."
            detailsHTML = reason.detailsHTML
            footnote = "Mailbell does not show email content on this local page."
            badgeSVG = """
            <svg viewBox="0 0 32 32" aria-hidden="true" focusable="false">
                <path d="M11 11l10 10"></path>
                <path d="M21 11L11 21"></path>
            </svg>
            """
        }
    }
}

private extension LoopbackCallbackPage.ErrorReason {
    var detailsHTML: String {
        """
        <div class="details" role="note" aria-label="What happened">
            <p class="detail-title">\(title)</p>
            <p class="detail-message">\(explanation)</p>
        </div>
        """
    }

    var title: String {
        switch self {
        case let .providerError(code):
            providerTitle(for: code)
        case .missingState:
            "The sign-in session expired"
        case .stateMismatch:
            "The sign-in session changed"
        case .missingCode:
            "Google sign-in did not finish"
        case .alreadyHandled:
            "This sign-in was already handled"
        case .serverUnavailable:
            "Mailbell was not ready for the response"
        case .unexpectedPath:
            "This sign-in page is not available"
        case .unsupportedMethod:
            "This sign-in request is not supported"
        }
    }

    var explanation: String {
        switch self {
        case let .providerError(code):
            providerExplanation(for: code)
        case .missingState:
            "Start sign-in again from Mailbell so the browser and app use the same fresh session."
        case .stateMismatch:
            "Start sign-in again from Mailbell. This protects you from completing the wrong browser response."
        case .missingCode:
            "Try again and complete the Google prompt before returning to Mailbell."
        case .alreadyHandled:
            "Return to Mailbell. If the account is not connected, start sign-in again."
        case .serverUnavailable:
            "Return to Mailbell and start sign-in again."
        case .unexpectedPath:
            "Return to Mailbell and start sign-in again from the app."
        case .unsupportedMethod:
            "Open sign-in again from Mailbell instead of reloading or submitting this page."
        }
    }

    private func providerTitle(for code: String) -> String {
        switch code {
        case "access_denied":
            "Permission was not granted"
        case "invalid_scope":
            "Google rejected the requested access"
        case "invalid_request":
            "Google could not start sign-in"
        case "server_error", "temporarily_unavailable":
            "Google had a temporary problem"
        default:
            "Google could not finish sign-in"
        }
    }

    private func providerExplanation(for code: String) -> String {
        switch code {
        case "access_denied":
            "This usually happens when the Google prompt is cancelled or the permission is denied."
        case "invalid_scope":
            "Mailbell needs Gmail access to watch for new mail. Check the local Google setup, then try again."
        case "invalid_request":
            "Start sign-in again from Mailbell."
        case "server_error", "temporarily_unavailable":
            "Try signing in again in a moment."
        default:
            "Start sign-in again from Mailbell. If this keeps happening, check the local Google setup."
        }
    }
}

private let callbackPageTemplate = """
<!doctype html>
<html lang="en" data-state="{{stateClass}}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<title>{{title}}</title>
<style>
:root {
    color-scheme: light dark;
    --background: #f5f5f7;
    --panel: rgba(255, 255, 255, 0.82);
    --text: #1d1d1f;
    --secondary: #6e6e73;
    --border: rgba(0, 0, 0, 0.08);
    --shadow: rgba(0, 0, 0, 0.16);
    --state-accent: #007aff;
    --state-glow: rgba(0, 122, 255, 0.12);
    --state-glow-fade: rgba(255, 255, 255, 0);
    --state-bar: linear-gradient(90deg, #0a84ff 0%, #64d2ff 100%);
    --detail-background: rgba(0, 122, 255, 0.08);
    --detail-border: rgba(0, 122, 255, 0.16);
    --badge-ring: #ffffff;
}

:root[data-state="success"] {
    --state-accent: #248a3d;
    --state-glow: rgba(52, 199, 89, 0.14);
    --state-bar: linear-gradient(90deg, #34c759 0%, #30d158 52%, #64d2ff 100%);
}

:root[data-state="error"] {
    --state-accent: #d70015;
    --state-glow: rgba(255, 59, 48, 0.12);
    --state-bar: linear-gradient(90deg, #ff3b30 0%, #ff453a 52%, #ff9f0a 100%);
    --detail-background: rgba(255, 59, 48, 0.07);
    --detail-border: rgba(255, 59, 48, 0.16);
}

* {
    box-sizing: border-box;
}

html {
    min-height: 100%;
}

body {
    min-height: 100vh;
    margin: 0;
    display: grid;
    place-items: center;
    padding:
        max(48px, env(safe-area-inset-top))
        24px
        max(40px, env(safe-area-inset-bottom));
    background:
        linear-gradient(180deg, var(--state-glow), var(--state-glow-fade) 32%),
        linear-gradient(180deg, #ffffff 0%, var(--background) 100%);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
    -webkit-font-smoothing: antialiased;
    text-align: center;
    text-rendering: optimizeLegibility;
}

body::before {
    content: "";
    position: fixed;
    inset: 0 0 auto;
    height: 6px;
    background: var(--state-bar);
}

.panel {
    width: min(430px, 100%);
    padding: 40px 34px 32px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--panel);
    box-shadow: 0 18px 60px var(--shadow);
    -webkit-backdrop-filter: saturate(180%) blur(18px);
    backdrop-filter: saturate(180%) blur(18px);
}

.icon-stack {
    position: relative;
    width: 92px;
    height: 92px;
    margin: 0 auto 24px;
}

.app-icon {
    display: block;
    width: 80px;
    height: 80px;
    margin: 0 auto;
    border-radius: 18px;
    box-shadow: 0 10px 30px rgba(92, 72, 0, 0.20);
}

.status-badge {
    position: absolute;
    right: 2px;
    bottom: 2px;
    width: 30px;
    height: 30px;
    display: grid;
    place-items: center;
    border: 2px solid var(--badge-ring);
    border-radius: 999px;
    background: var(--state-accent);
    box-shadow:
        0 6px 16px rgba(0, 0, 0, 0.18),
        inset 0 1px 0 rgba(255, 255, 255, 0.26);
    color: #ffffff;
}

.status-badge svg {
    width: 21px;
    height: 21px;
    fill: none;
    stroke: currentColor;
    stroke-linecap: round;
    stroke-linejoin: round;
    stroke-width: 3;
}

.eyebrow {
    margin: 0 0 8px;
    color: var(--state-accent);
    font-size: 13px;
    font-weight: 600;
    line-height: 1.3;
}

h1 {
    margin: 0;
    font-size: 32px;
    font-weight: 700;
    letter-spacing: 0;
    line-height: 1.1;
}

.message {
    max-width: 30rem;
    margin: 14px auto 0;
    color: var(--secondary);
    font-size: 17px;
    line-height: 1.45;
}

.details {
    max-width: 28rem;
    margin: 18px auto 0;
    padding: 14px 16px;
    border: 1px solid var(--detail-border);
    border-radius: 8px;
    background: var(--detail-background);
    text-align: left;
}

.detail-title {
    margin: 0;
    color: var(--text);
    font-size: 14px;
    font-weight: 600;
    line-height: 1.35;
}

.detail-message {
    margin: 5px 0 0;
    color: var(--secondary);
    font-size: 13px;
    line-height: 1.4;
}

.footnote {
    max-width: 28rem;
    margin: 22px auto 0;
    color: var(--secondary);
    font-size: 13px;
    line-height: 1.4;
}

@media (prefers-color-scheme: dark) {
    :root {
        --background: #111113;
        --panel: rgba(30, 30, 32, 0.74);
        --text: #f5f5f7;
        --secondary: #a1a1a6;
        --border: rgba(255, 255, 255, 0.12);
        --shadow: rgba(0, 0, 0, 0.36);
        --state-accent: #0a84ff;
        --state-glow: rgba(10, 132, 255, 0.10);
        --state-glow-fade: rgba(0, 0, 0, 0);
        --state-bar: linear-gradient(90deg, #0a84ff 0%, #64d2ff 100%);
        --detail-background: rgba(10, 132, 255, 0.10);
        --detail-border: rgba(10, 132, 255, 0.18);
        --badge-ring: #1c1c1e;
    }

    :root[data-state="success"] {
        --state-accent: #30d158;
        --state-glow: rgba(48, 209, 88, 0.12);
        --state-bar: linear-gradient(90deg, #34c759 0%, #30d158 52%, #64d2ff 100%);
    }

    :root[data-state="error"] {
        --state-accent: #ff453a;
        --state-glow: rgba(255, 69, 58, 0.12);
        --state-bar: linear-gradient(90deg, #ff3b30 0%, #ff453a 52%, #ff9f0a 100%);
        --detail-background: rgba(255, 69, 58, 0.10);
        --detail-border: rgba(255, 69, 58, 0.20);
    }

    body {
        background:
            linear-gradient(180deg, var(--state-glow), var(--state-glow-fade) 34%),
            linear-gradient(180deg, #1c1c1e 0%, var(--background) 100%);
    }
}

@media (max-width: 520px) {
    body {
        place-items: start center;
        padding:
            max(32px, env(safe-area-inset-top))
            18px
            max(28px, env(safe-area-inset-bottom));
    }

    .panel {
        padding: 34px 24px 28px;
    }

    h1 {
        font-size: 28px;
    }
}

@media (prefers-reduced-motion: no-preference) {
    .panel {
        animation: appear 0.28s ease-out both;
    }

    @keyframes appear {
        from {
            opacity: 0;
            transform: translateY(6px) scale(0.99);
        }

        to {
            opacity: 1;
            transform: translateY(0) scale(1);
        }
    }
}
</style>
</head>
<body>
<main class="panel" aria-labelledby="page-title">
    <div class="icon-stack" aria-hidden="true">
        <img class="app-icon" src="{{iconDataURI}}" alt="" width="80" height="80">
        <span class="status-badge">
            {{badgeSVG}}
        </span>
    </div>
    <p class="eyebrow">{{eyebrow}}</p>
    <h1 id="page-title">{{title}}</h1>
    <p class="message">{{message}}</p>
    {{detailsHTML}}
    <p class="footnote">{{footnote}}</p>
</main>
</body>
</html>
"""

private let callbackPageIconDataURI = "data:image/png;base64,"
    + callbackPageIconBase64.replacingOccurrences(of: "\n", with: "")

private let callbackPageIconBase64 = """
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
BiLw/wC/OFAui4GweAAAAABJRU5ErkJggg==
"""
