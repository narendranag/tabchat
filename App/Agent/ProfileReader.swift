import AppKit
import Foundation
import WebKit

/// `profile`: one LinkedIn or X profile, read in a hidden web view that shares a tab's sign-in, so
/// the owner's tab never moves. It loads the page, waits for it to draw and reads the first screen:
/// no scrolling, clicking or typing. Only `https://www.linkedin.com/in/<slug>` and
/// `https://x.com/<handle>` are loaded.
enum ProfileReader {
    struct Target: Equatable {
        /// "linkedin" or "x": also the service id of the tab whose sign-in is used.
        var site: String
        var url: URL
    }

    /// X paths that are pages, not handles.
    private static let xReserved: Set<String> = [
        "home", "explore", "i", "settings", "messages", "notifications", "search", "compose", "login", "logout",
        "signup", "tos", "privacy", "share", "intent", "hashtag", "jobs", "lists", "communities", "premium"
    ]

    /// The profile a URL names, as a clean address, or why it is refused.
    static func target(_ text: String) -> Result<Target, AgentError> {
        let refused = AgentError.coded(
            "profile takes https://www.linkedin.com/in/<slug> or https://x.com/<handle>, nothing else", .refused
        )
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespaces)),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil, parts.port == nil,
              let host = parts.host?.lowercased()
        else { return .failure(refused) }
        let path = parts.percentEncodedPath
        if host == "www.linkedin.com" || host == "linkedin.com" {
            guard let range = path.range(of: #"^/in/[A-Za-z0-9_%-]{2,100}/?$"#, options: .regularExpression),
                  range == path.startIndex ..< path.endIndex
            else { return .failure(refused) }
            let slug = path.split(separator: "/")[1]
            return URL(string: "https://www.linkedin.com/in/\(slug)/").map { .success(Target(site: "linkedin", url: $0)) }
                ?? .failure(refused)
        }
        if host == "x.com" || host == "www.x.com" {
            guard path.range(of: #"^/[A-Za-z0-9_]{1,15}/?$"#, options: .regularExpression) != nil else {
                return .failure(refused)
            }
            let handle = path.split(separator: "/")[0]
            guard !xReserved.contains(handle.lowercased()) else { return .failure(refused) }
            return URL(string: "https://x.com/\(handle)").map { .success(Target(site: "x", url: $0)) } ?? .failure(refused)
        }
        return .failure(refused)
    }

    /// Loads `target` with `dataStore`'s sign-in and reads it. The view lives only for this call.
    @MainActor
    static func read(_ target: Target, dataStore: WKWebsiteDataStore) async throws -> AgentResponse {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.mediaTypesRequiringUserActionForPlayback = .all
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 1400)
        let webView = WKWebView(frame: frame, configuration: config)
        webView.customUserAgent = safariUserAgent
        // A window keeps WebKit drawing and running timers; it is never shown, and sits off screen.
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        defer {
            webView.stopLoading()
            window.contentView = nil
            window.close()
        }
        webView.load(URLRequest(url: target.url, timeoutInterval: 30))
        for _ in 0 ..< 300 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        let json = try await PageReaders.run(
            script, arguments: ["site": target.site, "max": AgentWire.maxPageCharacters], in: webView
        )
        return response(json: json, target: target)
    }

    private struct ReaderResult: Decodable {
        var ok: Bool
        var reason: String?
        var code: String?
        var url: String?
        var name: String?
        var headline: String?
        var bio: String?
        var location: String?
        var links: [String]?
        var posts: [AgentProfilePost]?
        var text: String?
        var truncated: Bool?
    }

    static func response(json: String, target: Target) -> AgentResponse {
        guard let result = try? JSONDecoder().decode(ReaderResult.self, from: Data(json.utf8)) else {
            return .failure("the profile reader returned something unreadable")
        }
        guard result.ok else {
            return .failure(
                result.reason ?? "could not read the profile",
                code: result.code.flatMap(AgentErrorCode.init(rawValue:)) ?? .failed
            )
        }
        var response = AgentResponse(ok: true, untrusted: true)
        response.profile = AgentProfile(
            site: target.site, url: target.url.absoluteString, finalURL: result.url ?? "",
            name: result.name ?? "", headline: result.headline ?? "", bio: result.bio ?? "",
            location: result.location ?? "", links: result.links ?? [], posts: result.posts,
            text: result.text ?? "", truncated: result.truncated ?? false
        )
        return response
    }

    /// Waits up to 15 seconds for the profile to draw, then reads it. Checkpoint, captcha and sign-in
    /// pages answer with a `code` and no text.
    static let script = #"""
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const clean = t => (t || "").replace(/\s+/g, " ").trim();
    const linkedin = site === "linkedin";
    const blocked = () => {
      const path = location.pathname, early = ((document.body && document.body.innerText) || "").slice(0, 3000);
      if (linkedin) {
        if (/^\/(checkpoint|authwall)/.test(path)) return "checkpoint";
        if (document.querySelector('#captcha-internal, iframe[src*="captcha" i]')) return "checkpoint";
        if (/^\/(login|uas\/login|signup)/.test(path)) return "signed-out";
        return "";
      }
      if (/^\/account\/access/.test(path)) return "checkpoint";
      if (document.querySelector('iframe[src*="arkoselabs" i], iframe[src*="captcha" i]')) return "checkpoint";
      const named = document.querySelector('[data-testid="UserName"]');
      if (!named && /unusual activity|verify you.re (a )?human/i.test(early)) return "checkpoint";
      if (/^\/(i\/flow\/login|login)/.test(path)) return "signed-out";
      return "";
    };
    const missing = () => /this page doesn.t exist|page not found|this account doesn.t exist|account suspended/i
      .test(((document.body && document.body.innerText) || "").slice(0, 3000));
    const drawn = () => linkedin ? document.querySelector("main h1") : document.querySelector('[data-testid="UserName"]');
    for (let i = 0; i < 150 && !drawn() && !blocked() && !missing(); i++) await wait(100);
    const why = blocked();
    const siteName = linkedin ? "LinkedIn" : "X";
    if (why === "checkpoint") {
      return JSON.stringify({ok: false, code: why, reason: siteName + " shows a security check; stop for today"});
    }
    if (why) return JSON.stringify({ok: false, code: why, reason: siteName + " is signed out in Tabchat"});
    if (!drawn()) {
      return missing() ? JSON.stringify({ok: false, code: "not-found", reason: "no such profile"})
        : JSON.stringify({ok: false, code: "failed", reason: "the profile did not draw within 15 seconds"});
    }
    const external = href => {
      try {
        const u = new URL(href, location.origin);
        if (/linkedin\.com$/.test(u.hostname) && u.pathname.startsWith("/redir/redirect")) return u.searchParams.get("url") || "";
        return /(^|\.)(linkedin\.com|x\.com|twitter\.com)$/.test(u.hostname) || !/^https?:$/.test(u.protocol) ? "" : u.href;
      } catch (e) { return ""; }
    };
    const unique = list => Array.from(new Set(list.filter(Boolean)));
    let out = {};
    if (linkedin) {
      const h1 = document.querySelector("main h1");
      const card = h1.closest("section") || document.querySelector("main");
      const about = document.getElementById("about");
      const aboutSection = about && about.closest("section");
      const aboutText = aboutSection
        && (aboutSection.querySelector('.inline-show-more-text span[aria-hidden="true"], .inline-show-more-text')
          || aboutSection.querySelector('div.display-flex span[aria-hidden="true"]'));
      const place = card.querySelector(".text-body-small.inline.t-black--light, .text-body-small.t-black--light.break-words");
      out = {
        name: clean(h1.innerText),
        headline: clean((card.querySelector(".text-body-medium") || {}).innerText),
        location: clean(place && place.innerText),
        bio: aboutText ? aboutText.innerText.trim() : "",
        links: unique(Array.from(card.querySelectorAll("a[href]")).map(a => external(a.getAttribute("href"))))
      };
    } else {
      // The first screen only: X loads posts as you scroll, and this never scrolls.
      const posted = () => document.querySelector('article[data-testid="tweet"], [data-testid="emptyState"]');
      for (let i = 0; i < 50 && !posted(); i++) await wait(100);
      const user = document.querySelector('[data-testid="UserName"]');
      // X shows links as t.co redirects with the real address as their text, cut with "…" when long.
      const shown = a => {
        const label = a.innerText.trim().replace(/…$/, "");
        return label ? "https://" + label.replace(/^https?:\/\//, "") : external(a.getAttribute("href"));
      };
      const shownName = clean(user.innerText);
      const handle = (shownName.match(/@[A-Za-z0-9_]{1,15}/) || [""])[0];
      const lines = [handle ? clean(shownName.slice(0, shownName.indexOf(handle))) : shownName];
      const bio = document.querySelector('[data-testid="UserDescription"]');
      const url = document.querySelector('[data-testid="UserUrl"]');
      const posts = Array.from(document.querySelectorAll('article[data-testid="tweet"]'))
        .filter(a => a.getBoundingClientRect().top < window.innerHeight)
        .map(a => {
          const time = a.querySelector("time[datetime]");
          const link = time && time.closest('a[href*="/status/"]');
          const social = clean((a.querySelector('[data-testid="socialContext"]') || {}).innerText).toLowerCase();
          const body = a.querySelector('[data-testid="tweetText"]');
          return {
            url: link ? new URL(link.getAttribute("href"), location.origin).href : "",
            time: time ? time.getAttribute("datetime") : "",
            text: body ? body.innerText.trim() : "",
            kind: social.includes("pinned") ? "pinned" : (social.includes("repost") ? "repost" : null)
          };
        }).filter(p => p.url);
      out = {
        name: lines[0] || "",
        headline: handle,
        bio: bio ? bio.innerText.trim() : "",
        location: clean((document.querySelector('[data-testid="UserLocation"]') || {}).innerText),
        links: unique([url ? shown(url) : ""].concat(bio ? Array.from(bio.querySelectorAll("a[href]"))
          .filter(a => /\./.test(a.innerText) && !/^[@#$]/.test(a.innerText.trim())).map(shown) : [])),
        posts
      };
    }
    const text = (document.body && document.body.innerText) || "";
    const page = {ok: true, url: location.href, text: text.slice(0, max), truncated: text.length > max};
    return JSON.stringify(Object.assign(page, out));
    """#
}
