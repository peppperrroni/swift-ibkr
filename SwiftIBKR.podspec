Pod::Spec.new do |s|
  s.name         = 'SwiftIBKR'
  s.module_name  = 'IBKR'
  s.version      = '1.0.0'
  s.summary      = 'Pure-Swift client for Interactive Brokers IB Gateway and TWS (TWS API socket protocol).'
  s.homepage     = 'https://github.com/peppperrroni/swift-ibkr'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = 'peppperrroni'
  s.source       = { :git => 'https://github.com/peppperrroni/swift-ibkr.git', :tag => s.version.to_s }
  s.swift_versions = ['6.0']
  s.ios.deployment_target = '16.0'
  s.osx.deployment_target = '13.0'
  s.source_files = 'Sources/IBKR/**/*.swift'
end
