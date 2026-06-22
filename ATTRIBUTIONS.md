# Attributions

This file collects attribution and license notices for Mailbell's upstream source, app icon, and resolved third-party packages. The project's MIT license is in [LICENSE](LICENSE).

## Original Project

This repository is a fork of [samzong/mailbell](https://github.com/samzong/mailbell). The original MIT copyright notice remains in [LICENSE](LICENSE); later changes in this fork are covered by the additional copyright line in the same file.

## App Icon

The app icon was generated with [IconKitchen][icon-kitchen-app-icon] using these settings:

- Clipart: `notifications_active`, round
- Effects: none
- Background: 270-degree gradient, no texture, `#FFD54A` to `#D89B00`
- Foreground: `#FFFFFF`
- Padding: 15%

[icon-kitchen-app-icon]: https://icon.kitchen/i/H4sIAAAAAAAAA0VR0W6DIBT9l7tX01CdVn1b2m5PS5Zsb02zICCSKBjEpo3x33dB7Xjh3sPhHO5hghttRzFAOUEtj6Y1Fkp4qcOCCKp_LKMJF3nAfh69QEhaypXQLmAfW4NKgzN9kCSLGE9fKZLIrijIPk7zLCepX5k_5nlREQJzBFTLFnXjA8Gmkp9iaLxIb5R2KHeZ4A4l2cVpBI-tYNvz0iQ7vZ9RZmUdNpYvnqzsLTmdc5ivweG7oWEQpixD5wgjWEdjreqpDZNRLsUzhD0XRZUtIYi7Gy2SJ9Sq5RflXGnpH4zTQ7lHW6tkg4H4sjLOmW6pW1EHNNw7rk4-NoEbWDNqjg6KGY2tNk7VilGnjB5-KXPqJmDGq53hY-t_7gIdZWaA6_wHPt2MQs4BAAA

## Third-Party Packages

Mailbell does not vendor third-party source directly. The SwiftPM application build resolves the packages below through `Package.resolved`.

### FlyingFox 0.26.2

- Repository: https://github.com/swhitty/FlyingFox
- Package pin: `de38230104cf63ef4843cb569ba11c13f8165685`
- License: MIT
- Notes: Mailbell uses FlyingFox for the local OAuth loopback HTTP callback server. The resolved macOS product compiles Swift targets from FlyingFox/FlyingSocks; FlyingFox's `CSystemLinux` shim is conditional for Linux/Android and is not a macOS product target.

```text
MIT License

Copyright (c) 2022 Simon Whitty

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### SwiftSoup 2.13.5

- Repository: https://github.com/scinfu/SwiftSoup
- Package pin: `49dcadd93161f4a44b4994d3a3e8de9f085aface`
- License: MIT
- Notes: Mailbell uses SwiftSoup for generic HTML parsing, non-visible markup removal, text extraction, and HTML entity decoding in bounded previews.

```text
The MIT License

Copyright (c) 2009-2025 Jonathan Hedley <https://jsoup.org/>
Copyright (c) 2016-2025 Nabil Chatbi (Swift port)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
