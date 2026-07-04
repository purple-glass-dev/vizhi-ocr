import SwiftUI

/// Displays the binary's Terms of Service. The text is baked into the app (no network), so edit
/// `TermsText.body` below to update it; the change ships with the next build.
struct TermsView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Terms of Service")
                .font(.headline)

            ScrollView {
                Text(TermsText.body)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Close") { dismissWindow(id: WindowID.terms) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 420)
    }
}

/// The Terms of Service shown in `TermsView`. Edit this string to update the terms.
private enum TermsText {
    static let body = """
        Vizhi OCR — Terms of Service

        TL;DR: We want you to enjoy this app! You're totally free to use it for personal or business tasks. We just ask that you don't take this compiled app, rename it, and sell it as your own. (If you want the code, it's open-source on GitHub under the GPLv3!).
        ========================================================================

        THE FINE PRINT:
        By installing and using the official pre-compiled version of Vizhi OCR, you agree to the following terms:

        1. Usage: You are granted a non-exclusive license to run this binary on your macOS devices.
        2. Distribution: You may not sell, rent, or commercially redistribute this specific compiled binary.
        3. Source Code: If you want to modify or redistribute the source code, you must do so under the terms of the GNU General Public License v3.0 (GPL-3.0) found in our public repository.
        4. Disclaimer: This software is provided "as is", without warranty of any kind.

        Copyright © 2026 SA.

        ========================================================================
        THIRD-PARTY OPEN-SOURCE ACKNOWLEDGEMENTS
        ========================================================================

        This application includes third-party open-source software packages components.
        In accordance with their respective permissive licenses, the original copyright
        notices and permission texts are reproduced below:

        1. swift-markdown-ui (MIT License)
        https://github.com/gonzalezreal/swift-markdown-ui
        Copyright (c) 2020 Guillermo Gonzalez

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


        2. SwiftMath (MIT License)
        https://github.com/mgriebling/SwiftMath
        Copyright (c) 2023 Computer Inspirations

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
}
