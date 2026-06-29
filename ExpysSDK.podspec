Pod::Spec.new do |s|
  s.name             = 'ExpysSDK'
  # Synced from the release tag by the release workflow, mirroring Version.swift.
  s.version          = '0.0.0'
  s.summary          = 'Official Expys data SDK for Swift: offers, redemptions, eligibility, wallet'
  s.description      = <<-DESC
    ExpysSDK is the official Expys data SDK for Swift. It exposes a small,
    member-facing surface (browse offers, redeem them, check eligibility, read the
    wallet) over async/await with zero external dependencies (Foundation only). It
    handles token refresh, full-jitter retry on 429/5xx, and idempotent writes, and
    shares one contract with the Expys TypeScript and Kotlin SDKs. SwiftPM is the
    primary distribution channel; this podspec is for CocoaPods consumers.
  DESC
  s.homepage         = 'https://github.com/Utopia-Members-Club-Inc/expys-swift'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Expys' => 'support@expys.dev' }
  s.source           = {
    :git => 'https://github.com/Utopia-Members-Club-Inc/expys-swift.git',
    :tag => s.version.to_s,
  }

  s.swift_versions = ['6.0']

  s.ios.deployment_target     = '15.0'
  s.osx.deployment_target     = '12.0'

  s.source_files = 'Sources/ExpysSDK/**/*.swift'
  s.frameworks   = 'Foundation'
end
