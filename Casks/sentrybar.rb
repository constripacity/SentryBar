cask "sentrybar" do
  version "0.6.0"
  sha256 "37ac9e5f386b1917f77e053188569a16d9c11ca2d027442a6776cdd02fe0fec5"

  url "https://github.com/constripacity/SentryBar/releases/download/v#{version}/SentryBar.dmg"
  name "SentryBar"
  desc "Lightweight macOS menubar app for system health and network security monitoring"
  homepage "https://github.com/constripacity/SentryBar"
  license :mit

  livecheck do
    url :homepage
    regex(/^v?(\d+(?:\.\d+)*)$/i)
    strategy :github_latest
  end

  app "SentryBar.app"

  zap trash: [
    "~/Library/Application Support/SentryBar",
    "~/Library/Preferences/com.sentrybar.plist",
  ]
end
