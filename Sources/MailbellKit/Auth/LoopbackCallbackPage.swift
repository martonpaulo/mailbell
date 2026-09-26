import Foundation

public enum LoopbackCallbackPage {
    public enum State: Sendable {
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

    public enum ErrorReason: Equatable, Sendable {
        case providerError(String)
        case missingState
        case stateMismatch
        case missingCode
        case alreadyHandled
        case serverUnavailable
        case unexpectedPath
        case unsupportedMethod
    }

    public static func html(state: State) -> String {
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
            // This page is written when the browser hands the code back, before
            // token exchange, identity lookup and account persistence have run.
            // It can only honestly confirm the handoff.
            eyebrow = "Signed in"
            title = "Return to Mailbell"
            message = "You can close this tab. Mailbell is finishing the setup."
            detailsHTML = ""
            footnote = "Open Mailbell from the menu bar to confirm the account connected. "
                + "No email content is shown on this page."
            badgeSVG = """
            <svg viewBox="0 0 32 32" aria-hidden="true" focusable="false">
                <path d="M9 16.5l4.4 4.4L23 11.5"></path>
            </svg>
            """
        case let .error(reason):
            stateClass = state.dataState
            eyebrow = "Google sign-in stopped"
            title = "Sign-in didn't finish"
            message = "Return to Mailbell and sign in again."
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
iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3Cc
ulE8AAAAeGVYSWZNTQAqAAAACAAEARoABQAAAAEAAAA+ARsABQAAAAEAAABGASgAAwAAAAEAAgAAh2kABAAAAAEAAABOAAAAAAAAAJAAAAABAAAAkAAAAAEA
A6ABAAMAAAABAAEAAKACAAQAAAABAAAAgKADAAQAAAABAAAAgAAAAACaA7zWAAAACXBIWXMAABYlAAAWJQFJUiTwAAABzWlUWHRYTUw6Y29tLmFkb2JlLnht
cAAAAAAAPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iWE1QIENvcmUgNi4wLjAiPgogICA8cmRmOlJERiB4bWxuczpyZGY9
Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPgogICAgICA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIgogICAgICAg
ICAgICB4bWxuczpleGlmPSJodHRwOi8vbnMuYWRvYmUuY29tL2V4aWYvMS4wLyI+CiAgICAgICAgIDxleGlmOkNvbG9yU3BhY2U+MTwvZXhpZjpDb2xvclNw
YWNlPgogICAgICAgICA8ZXhpZjpQaXhlbFhEaW1lbnNpb24+MTAyNDwvZXhpZjpQaXhlbFhEaW1lbnNpb24+CiAgICAgICAgIDxleGlmOlBpeGVsWURpbWVu
c2lvbj4xMDI0PC9leGlmOlBpeGVsWURpbWVuc2lvbj4KICAgICAgPC9yZGY6RGVzY3JpcHRpb24+CiAgIDwvcmRmOlJERj4KPC94OnhtcG1ldGE+CsHtO6kA
ABxDSURBVHgB7V15sCVXWT/dd32ZeZM3mRGDTIBMAiRUEkMmCZsaKALJH6RUKKmyqITN0SqQAi0UF7BU0BJX/rCiVpRAtApLDVKChUAomYhQhEySYhu2TMBE
AslsYd56+95uf79z+ut7um9339vLfYv0mbn3nPN953z7Wfp0335KNamxQGOBxgKNBRoLNBZoLNBYoLFAY4HGAo0FGgs0Fmgs0FigsUBjgcYCjQUaCzQW+P9s
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
"""
