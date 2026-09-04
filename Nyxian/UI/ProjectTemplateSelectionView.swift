/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2026 Kyle-Ye
 Copyright (C) 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

import SwiftUI

struct ProjectTemplateSelectionView: View {
    enum templateRowFlavour {
        case last
        case first
        case generic
    }
    
    @ObservedObject var model: ProjectTemplateOptionsModel
    
    private var textColor: Color { Color(uiColor: currentTheme?.textColor ?? .label) }
    private var backgroundColor: Color { Color(uiColor: currentTheme?.backgroundColor ?? .systemBackground) }
    private var hairlineColor: Color { Color(uiColor: currentTheme?.gutterHairlineColor ?? .separator) }
    
    var body: some View {
        VStack(spacing: 0) {
            templateRow(title: "App", subtitle: "UI app for iPhone & iPad", systemImage: "appstore.app.fill", schemeKind: .app, scale: .large, flavour: .first)
            templateRow(title: "Command Line Tool", subtitle: "Headless iOS app", systemImage: "terminal.fill", schemeKind: .utility)
            templateRow(title: "Library", subtitle: "Library project", systemImage: "building.columns.fill", schemeKind: .library, isEnabled: false)
            templateRow(title: "Ksurface Kernel Extension", subtitle: "Extend the ksurface microkernel your self", systemImage: "puzzlepiece.extension.fill", schemeKind: .kSurfaceKext, isEnabled: true, flavour: .last)
        }
        .padding(.top, 2)
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private func templateRow(title: String,
                             subtitle: String,
                             systemImage: String,
                             schemeKind: NXProjectSchemeKind,
                             scale: UIImage.SymbolScale = .default,
                             isEnabled: Bool = true,
                             flavour: templateRowFlavour = .generic) -> some View {
        let isSelected = model.schemeKind == schemeKind
        
        let clipTop: CGFloat = flavour == .first ? 16 : 0
        let clipBottom: CGFloat = flavour == .last ? 16 : 0
        let strokeTop: CGFloat = flavour == .first ? 16 : 4
        let strokeBottom: CGFloat = flavour == .last ? 16 : 4
        
        return Button {
            model.selectProjectType(schemeKind)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? textColor : textColor.opacity(0.08))
                    
                    let base = UIImage(systemName: systemImage) ?? UIImage(privateSystemName: systemImage) ?? UIImage(systemName: "app.fill")
                    let configuredBase: UIImage? = base?.applyingSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold, scale: scale))
                    let img = configuredBase?.withRenderingMode(.alwaysTemplate) ?? UIImage()
                    
                    Image(uiImage: img)
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(isSelected ? backgroundColor : textColor.opacity(0.6))
                }
                .frame(width: 42, height: 42)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(textColor)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.6))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(textColor.opacity(0.05))
            .clipShape(
                    UnevenRoundedRectangle(topLeadingRadius: clipTop, bottomLeadingRadius: clipBottom, bottomTrailingRadius: clipBottom, topTrailingRadius: clipTop, style: .continuous)
                )
                .overlay {
                    UnevenRoundedRectangle(topLeadingRadius: strokeTop, bottomLeadingRadius: strokeBottom, bottomTrailingRadius: strokeBottom, topTrailingRadius: strokeTop, style: .continuous)
                    .stroke(isSelected ? textColor : hairlineColor.opacity(0.0), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
