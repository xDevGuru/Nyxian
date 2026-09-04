/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

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

import UIKit

class ProjectTableCell: UITableViewCell {
    static var reuseIdentifier: String = "NXProjectTableCell"
    
    let cellImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.borderWidth = 0.5
        iv.layer.borderColor = UIColor.gray.cgColor
        iv.layer.cornerRadius = 10
        return iv
    }()
    
    let cellTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        return label
    }()
    
    let cellDetailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = UIFont.systemFont(ofSize: 10)
        return label
    }()
    
    private var titleCenterYConstraint: NSLayoutConstraint?
    private var titleTopConstraint: NSLayoutConstraint?
    private var detailTopConstraint: NSLayoutConstraint?
    private var imageConstraints: [NSLayoutConstraint] = []
    
    private var leadingConstraintWImage: NSLayoutConstraint?
    private var leadingConstraintWHImage: NSLayoutConstraint?
    private var detailLeadingConstraintWImage: NSLayoutConstraint?
    private var detailLeadingConstraintWHImage: NSLayoutConstraint?
    
    override init(style: UITableViewCell.CellStyle,
                  reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.setupConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupConstraints() {
        self.contentView.addSubview(self.cellImageView)
        self.contentView.addSubview(self.cellTitleLabel)
        self.contentView.addSubview(self.cellDetailLabel)
        
        let imageSize: CGFloat = 50
        
        self.imageConstraints = [
            self.cellImageView.widthAnchor.constraint(equalToConstant: imageSize),
            self.cellImageView.heightAnchor.constraint(equalToConstant: imageSize),
            self.cellImageView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16),
            self.cellImageView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor)
        ]
        
        self.leadingConstraintWImage = self.cellTitleLabel.leadingAnchor.constraint(equalTo: self.cellImageView.trailingAnchor, constant: 16)
        self.leadingConstraintWHImage = self.cellTitleLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16)
        self.detailLeadingConstraintWImage = self.cellDetailLabel.leadingAnchor.constraint(equalTo: self.cellImageView.trailingAnchor, constant: 16)
        self.detailLeadingConstraintWHImage = self.cellDetailLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16)
        
        self.titleCenterYConstraint = self.cellTitleLabel.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor)
        self.titleTopConstraint = self.cellTitleLabel.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor, constant: -10)
        self.detailTopConstraint = self.cellDetailLabel.topAnchor.constraint(equalTo: self.cellTitleLabel.bottomAnchor, constant: 4)
        
        var baseConstraints: [NSLayoutConstraint] = [
            self.titleTopConstraint!,
            self.detailTopConstraint!,
            self.cellTitleLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16),
            self.cellDetailLabel.trailingAnchor.constraint(equalTo: self.cellTitleLabel.trailingAnchor)
        ]
        baseConstraints.append(contentsOf: self.imageConstraints)
        NSLayoutConstraint.activate(baseConstraints)
        
        self.leadingConstraintWImage?.isActive = true
        self.detailLeadingConstraintWImage?.isActive = true
        
        self.separatorInset = .zero
        self.layoutMargins = .zero
        self.preservesSuperviewLayoutMargins = false
    }
    
    func configure(displayName: String?,
                   bundleIdentifier: String?,
                   appIcon: UIImage?,
                   showArrow: Bool) {
        self.cellTitleLabel.text = displayName ?? "Project"
        self.cellTitleLabel.textColor = currentTheme?.textColor ?? .label
        self.cellDetailLabel.textColor = (currentTheme?.textColor ?? .label).withAlphaComponent(0.6)
        self.cellImageView.image = appIcon
        self.accessoryType = showArrow ? .disclosureIndicator : .none
        
        if let bundleIdentifier = bundleIdentifier, !bundleIdentifier.isEmpty {
            self.cellDetailLabel.text = bundleIdentifier
            self.cellDetailLabel.isHidden = false
            self.detailTopConstraint?.isActive = true
            self.titleCenterYConstraint?.isActive = false
            self.titleTopConstraint?.isActive = true
        } else {
            self.cellDetailLabel.isHidden = true
            self.detailTopConstraint?.isActive = false
            self.titleTopConstraint?.isActive = false
            self.titleCenterYConstraint?.isActive = true
        }
        
        if appIcon != nil {
            self.cellImageView.isHidden = false
            self.leadingConstraintWHImage?.isActive = false
            self.detailLeadingConstraintWHImage?.isActive = false
            self.leadingConstraintWImage?.isActive = true
            self.detailLeadingConstraintWImage?.isActive = true
        } else {
            self.cellImageView.isHidden = true
            self.leadingConstraintWImage?.isActive = false
            self.detailLeadingConstraintWImage?.isActive = false
            self.leadingConstraintWHImage?.isActive = true
            self.detailLeadingConstraintWHImage?.isActive = true
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.cellTitleLabel.text = nil
        self.cellDetailLabel.text = nil
        self.cellImageView.image = nil
        self.accessoryType = .none
        self.cellImageView.isHidden = false
        self.cellDetailLabel.isHidden = false
    }
}
