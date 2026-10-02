# Xcode Security Settings

Widgets adopts the baseline [Enhanced Security capability](https://developer.apple.com/documentation/xcode/enabling-enhanced-security-for-your-app.md).

## Enabled settings

- `ENABLE_ENHANCED_SECURITY = YES` in `Configuration/Shared.xcconfig` applies to all targets and configurations. Its defaults enable pointer authentication and add the `arm64e` device slice alongside `arm64`; simulator architectures remain SDK-controlled.
- The app's entitlements enable `com.apple.security.hardened-process`, Enhanced Security version `2`, `hardened-heap`, `dyld-ro`, and platform restrictions version `2`. Frameworks and test bundles have no separate runtime entitlements.
- Cascaded compiler protections use Xcode's defaults. This repository contains only Swift, so no additional C, C++, or Objective-C warnings or bounds-safety annotations are configured.

## Deferred

- Hardware memory tagging (`checked-allocations`) and hardware-checked pointer arithmetic (`ENABLE_HARDWARE_CHECKED_POINTER_ARITHMETIC_SLICE` and its enforcement entitlement) are outside the approved baseline.
- Physical-device validation of pointer authentication and the runtime protections is still required. Simulator builds and execution do not establish hardware enforcement or device provisioning compatibility.
