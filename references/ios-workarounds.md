# iOS workarounds

Workarounds for iOS bugs. Recheck each one on every iOS release and beta, and remove it once iOS fixes the bug.

- **Split view in a hidden tab (iPad, seen on iOS 27.2):** a `NavigationSplitView` inserted while its tab is hidden comes back with its columns under the tab bar. `PortfolioScene` keeps its last presentation while its tab is hidden and updates when the tab appears. To recheck, remove `hiddenPresentation`, switch a window's network in Settings, and open Portfolio.
