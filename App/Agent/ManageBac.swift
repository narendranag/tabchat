import Foundation

/// ManageBac (`*.managebac.com`), read only and unattended: `get` fetches one page of the parent
/// pages with the tab's own sign-in, from inside the tab, and `get --save` downloads one attachment.
/// Nothing clicks, types, posts or marks anything. The limits live here, not with the caller: one
/// request at a time, 2–5 s apart, at most 40 an hour, and a stop for an hour at the first login
/// page, 401, 403, 429, challenge page or 5xx. ManageBac's terms forbid automated access; the owner
/// chose this careful reader for his own parent account (DECISIONS.md, 2026-10-16).
enum ManageBac {
    static let budget = 40
    static let window: TimeInterval = 3600
    static let haltFor: TimeInterval = 3600
    static let maxFileBytes: Int64 = 25 * 1024 * 1024
    static let maxText = 50000
    static let maxHTML = 1_500_000

    /// Whether a tab's page is ManageBac: any `https://<school>.managebac.com`.
    static func isManageBac(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host.hasSuffix(".managebac.com")
    }

    /// The path a `get` may ask for, on `origin`: a relative path or a same-origin URL, under `/parent`
    /// for pages (any same-origin path for `save`), no `..`, never a sign-out.
    static func path(_ raw: String, origin: URL, save: Bool) -> Result<String, AgentError> {
        let refused = AgentError.coded(
            save ? "get --save takes a ManageBac path or URL on the tab's own site"
                : "get takes a ManageBac path under /parent (or a URL on the tab's own site)",
            .refused
        )
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard var parts = URLComponents(string: text) else { return .failure(refused) }
        if parts.scheme != nil || parts.host != nil {
            guard parts.scheme == "https", parts.host?.lowercased() == origin.host?.lowercased(),
                  parts.port == nil, parts.user == nil, parts.password == nil
            else { return .failure(refused) }
        }
        parts.fragment = nil
        let path = parts.percentEncodedPath
        let decoded = (path.removingPercentEncoding ?? path).lowercased()
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !decoded.contains("\\"),
              !decoded.split(separator: "/").contains(".."),
              decoded.range(of: #"log_?out|sign_?out"#, options: .regularExpression) == nil
        else { return .failure(refused) }
        if !save, decoded != "/parent", !decoded.hasPrefix("/parent/") {
            return .failure(refused)
        }
        let query = parts.percentEncodedQuery.map { "?" + $0 } ?? ""
        return .success(path + query)
    }

    /// What a response says about the run: nil when it can go on, else why it must stop.
    static func trouble(status: Int, finalURL: URL?, origin: URL, html: String?) -> (AgentErrorCode, String)? {
        let path = finalURL?.path.lowercased() ?? ""
        let signIn = #"/(login|logins|sessions?|sign_in|signin|sso|saml|oauth|auth)(/|$)"#
        if status == 401 || finalURL?.host?.lowercased() != origin.host?.lowercased()
            || path.range(of: signIn, options: .regularExpression) != nil {
            return (.signedOut, "loggedOut: ManageBac asks for a sign-in; log in again in Tabchat")
        }
        if let html, html.range(
            of: #"cf-chl|challenge-platform|<title>\s*Just a moment"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return (.checkpoint, "challenge: ManageBac shows a browser check; stopped for an hour")
        }
        switch status {
        case 403: return (.checkpoint, "forbidden: ManageBac answered 403; stopped for an hour")
        case 429: return (.checkpoint, "rateLimited: ManageBac answered 429; stopped for an hour")
        case 500...: return (.checkpoint, "serverError: ManageBac answered \(status); stopped for an hour")
        default: return nil
        }
    }

    /// The pace and budget, kept for the app's life. Pure, so it can be tested.
    struct Gate {
        var times: [Date] = []
        var haltedUntil: Date?
        var halt: (code: AgentErrorCode, reason: String)?
        var busy = false

        /// Why a request may not start now, if it may not.
        func refusal(now: Date) -> AgentResponse? {
            if let until = haltedUntil, now < until, let halt {
                let minutes = Int((until.timeIntervalSince(now) / 60).rounded(.up))
                return .failure("\(halt.reason) (stopped; \(minutes) min left)", code: halt.code)
            }
            if busy {
                return .failure("another ManageBac request is running; one at a time", code: .busy)
            }
            if times.filter({ now.timeIntervalSince($0) < ManageBac.window }).count >= ManageBac.budget {
                return .failure("the ManageBac budget (\(ManageBac.budget) requests an hour) is spent", code: .rate)
            }
            return nil
        }

        /// How long to wait before the next request: 2–5 s after the last one, with jitter.
        func wait(now: Date, jitter: Double) -> TimeInterval {
            guard let last = times.last else { return 0 }
            return max(0, last.addingTimeInterval(2 + 3 * min(max(jitter, 0), 1)).timeIntervalSince(now))
        }

        mutating func record(now: Date) {
            times = times.filter { now.timeIntervalSince($0) < ManageBac.window } + [now]
        }

        mutating func stop(_ code: AgentErrorCode, _ reason: String, now: Date) {
            haltedUntil = now.addingTimeInterval(ManageBac.haltFor)
            halt = (code, reason)
        }
    }

    /// One GET from inside the tab with its cookies, following redirects; the page's text (lines kept)
    /// and HTML, capped. Never posts, never navigates the tab.
    static let get = #"""
    const res = await fetch(path, {method: "GET", credentials: "include", redirect: "follow", cache: "no-store"});
    const type = res.headers.get("content-type") || "";
    const challenged = (res.headers.get("cf-mitigated") || "") === "challenge";
    const body = await res.text();
    let title = "", text = body;
    if (/html/i.test(type)) {
      const doc = new DOMParser().parseFromString(body, "text/html");
      doc.querySelectorAll("script, style, noscript, template, svg").forEach(e => e.remove());
      const blocks = "p, div, li, tr, br, h1, h2, h3, h4, h5, h6, section, article, header, footer, table, ul, ol, dt, dd";
      doc.querySelectorAll(blocks).forEach(e => e.append("\n"));
      doc.querySelectorAll("td, th").forEach(e => e.append(" \t "));
      title = (doc.title || "").trim();
      text = (doc.body ? doc.body.textContent : "").split("\n").map(l => l.replace(/\s+/g, " ").trim())
        .filter(Boolean).join("\n");
    }
    const password = /html/i.test(type) && /<input[^>]+type=["']?password/i.test(body);
    return JSON.stringify({
      ok: true, url: res.url, status: res.status, contentType: type, title, challenged, password,
      text: text.slice(0, maxText), html: /html/i.test(type) ? body.slice(0, maxHTML) : "",
      truncated: text.length > maxText || body.length > maxHTML
    });
    """#

    struct Fetched: Decodable {
        var ok: Bool
        var url: String
        var status: Int
        var contentType: String
        var title: String
        var challenged: Bool
        var password: Bool
        var text: String
        var html: String
        var truncated: Bool
    }

    /// The answer to `get`, or the trouble that stops the run.
    static func response(json: String, origin: URL) -> (AgentResponse, (AgentErrorCode, String)?) {
        guard let fetched = try? JSONDecoder().decode(Fetched.self, from: Data(json.utf8)) else {
            return (.failure("the ManageBac reader returned something unreadable"), nil)
        }
        let finalURL = URL(string: fetched.url)
        var problem = trouble(
            status: fetched.status, finalURL: finalURL, origin: origin, html: fetched.challenged ? "cf-chl" : fetched.html
        )
        if problem == nil, fetched.password, !(finalURL?.path.lowercased().hasPrefix("/parent") ?? false) {
            problem = (.signedOut, "loggedOut: ManageBac shows a sign-in form; log in again in Tabchat")
        }
        if let problem {
            return (.failure(problem.1, code: problem.0), problem)
        }
        guard (200 ..< 400).contains(fetched.status) else {
            let code: AgentErrorCode = fetched.status == 404 ? .notFound : .failed
            return (.failure("ManageBac answered \(fetched.status)", code: code), nil)
        }
        var response = AgentResponse(ok: true, untrusted: true)
        response.fetched = AgentFetched(
            url: fetched.url, status: fetched.status, contentType: fetched.contentType, title: fetched.title,
            text: fetched.text, html: fetched.html, truncated: fetched.truncated
        )
        return (response, nil)
    }
}
