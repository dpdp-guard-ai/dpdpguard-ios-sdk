# dpdpguard-ios-sdk

DPDP Guard iOS SDK (Swift) - native consent banner, on-device gating, offline durability

Package: `DPDPGuardConsent`

Part of the DPDP Guard SDK family. See the design spec:
https://github.com/chintans/dpdpbot/blob/main/docs/specs/mobile-server-sdk.md

> **Note:** the Swift toolchain was not found on PATH when this repo was
> scaffolded, so this is a minimal hand-written skeleton, not the output of
> swift package init. Once Swift is installed, regenerate properly with:
> `
> swift package init --name DPDPGuardConsent --type library
> `
"@
    New-CiWorkflow E:\Github\chintans\dpdpguard-ios-sdk @"
name: CI
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - run: swift build
