//
//  BKWebViewBuilder.swift
//  BookKit
//
//  Created by Josep Cerdá Penadés on 26/11/25.
//

import WebKit

final class BKWebViewBuilder {
    @MainActor
    func build(frame: CGRect,
               configuration: WKWebViewConfiguration,
               router: BKWebViewRouterProtocol) -> BKWebView {
        let viewModel = BKWebViewModel(router: router)
        let view = BKWebView(frame: frame, configuration: configuration)
        view.viewModel = viewModel
        return view
    }
}
