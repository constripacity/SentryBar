# Homebrew cask for SentryBar.
#
# The `sha256` below MUST match the DMG published for `version`. It is rewritten
# automatically by the release workflow (`.github/workflows/build.yml`), which
# computes it from the artifact it just built. Do not hand-edit `version`
# without also updating `sha256` — a cask whose checksum does not match its
# download fails to install, and a cask whose checksum is stale is worse than
# one that fails.
#
# CI asserts that this file's `version` matches `MARKETING_VERSION` in
# `project.yml`, because they had already drifted (cask 0.6.0, project 0.7.0).
cask "sentrybar" do
  version "0.8.0"
  sha256 :no_check # replaced by the release workflow with the real digest

  url "https://github.com/constripacity/SentryBar/releases/download/v#{version}/SentryBar.dmg",
      verified: "github.com/constripacity/SentryBar/"
  name "SentryBar"
  desc "Menu-bar watcher for what your Mac is connected to"
  homepage "https://github.com/constripacity/SentryBar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura" # MenuBarExtra requires macOS 13

  app "SentryBar.app"

  # SentryBar is not signed or notarised. Homebrew will surface the Gatekeeper
  # prompt; this caveat explains why rather than leaving the user to guess.
  caveats <<~EOS
    SentryBar is not code-signed or notarised, so macOS will refuse to open it
    until you clear the quarantine flag:

      xattr -dr com.apple.quarantine "#{appdir}/SentryBar.app"

    SentryBar watches and warns. It reads the socket table with lsof and nettop,
    installs no system extension, and cannot block a connection. For blocking,
    use a firewall such as LuLu.
  EOS

  zap trash: [
    "~/Library/Application Support/SentryBar",
    "~/Library/Preferences/com.sentrybar.SentryBar.plist",
    "~/Library/Caches/com.sentrybar.SentryBar",
  ]
end
