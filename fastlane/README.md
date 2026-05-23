fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build the project from a clean checkout and push it to TestFlight

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Push localized metadata and screenshots to App Store Connect (no binary)

### ios metadata_copy

```sh
[bundle exec] fastlane ios metadata_copy
```

Push text metadata only (name/subtitle/keywords/description/promo/notes). Skips screenshots for fast ASO iteration.

### ios metadata_screenshots

```sh
[bundle exec] fastlane ios metadata_screenshots
```

Push screenshots only (no metadata).

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Submit the most recent build for App Store review

### ios register_bundle_id

```sh
[bundle exec] fastlane ios register_bundle_id
```

Register the bundle id in the Developer Portal (one-time). Enables Sign In with Apple and In-App Purchase capabilities.

### ios create_subscriptions

```sh
[bundle exec] fastlane ios create_subscriptions
```

Create the Pro subscription group + monthly / annual products via App Store Connect API

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
