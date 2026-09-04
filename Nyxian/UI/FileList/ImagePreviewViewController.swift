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

class ImagePreviewViewController: UIViewController, UIScrollViewDelegate {
    private let fileURL: URL
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let infoContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let infoLabel = UILabel()
    private var doubleTapGesture: UITapGestureRecognizer?

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadImage()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        centerImage()
    }

    private func setupUI() {
        view.backgroundColor = .black
        title = fileURL.lastPathComponent

        let closeButton = UIBarButtonItem(
            title: "Close",
            style: .done,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.tintColor = .white
        navigationItem.leftBarButtonItem = closeButton

        let shareButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareTapped)
        )
        shareButton.tintColor = .white
        navigationItem.rightBarButtonItem = shareButton

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithTransparentBackground()
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navigationController?.navigationBar.standardAppearance = navBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navBarAppearance
        navigationController?.navigationBar.tintColor = .white

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 8.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        view.addSubview(scrollView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)

        infoContainer.translatesAutoresizingMaskIntoConstraints = false
        infoContainer.layer.cornerRadius = 16
        infoContainer.layer.masksToBounds = true
        view.addSubview(infoContainer)

        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        infoLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        infoLabel.textAlignment = .center
        infoContainer.contentView.addSubview(infoLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            infoContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            infoContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            infoContainer.heightAnchor.constraint(equalToConstant: 32),

            infoLabel.leadingAnchor.constraint(equalTo: infoContainer.contentView.leadingAnchor, constant: 14),
            infoLabel.trailingAnchor.constraint(equalTo: infoContainer.contentView.trailingAnchor, constant: -14),
            infoLabel.centerYAnchor.constraint(equalTo: infoContainer.contentView.centerYAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        self.doubleTapGesture = doubleTap

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)
    }

    private func loadImage() {
        guard let image = UIImage(contentsOfFile: fileURL.path) else {
            let errorLabel = UILabel()
            errorLabel.translatesAutoresizingMaskIntoConstraints = false
            errorLabel.text = "Unable to load image"
            errorLabel.textColor = .white
            errorLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
            view.addSubview(errorLabel)
            NSLayoutConstraint.activate([
                errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            infoContainer.isHidden = true
            return
        }

        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.contentSize = image.size

        view.layoutIfNeeded()
        updateZoomScaleForSize(view.bounds.size)
        centerImage()

        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        let fileSizeString = formattedFileSize(for: fileURL)
        infoLabel.text = "\(pixelWidth) × \(pixelHeight) px  •  \(fileSizeString)"
    }

    private func formattedFileSize(for url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return "Unknown size"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func updateZoomScaleForSize(_ size: CGSize) {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return }

        let widthScale = size.width / image.size.width
        let heightScale = size.height / image.size.height
        let minScale = min(widthScale, heightScale, 1.0)

        scrollView.minimumZoomScale = minScale
        scrollView.zoomScale = minScale
        scrollView.maximumZoomScale = max(minScale * 8.0, 4.0)
    }

    private func centerImage() {
        guard let image = imageView.image else { return }

        let boundsSize = scrollView.bounds.size
        var frameToCenter = imageView.frame

        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2.0
        } else {
            frameToCenter.origin.x = 0
        }

        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2.0
        } else {
            frameToCenter.origin.y = 0
        }

        imageView.frame = frameToCenter
    }

    // MARK: - UIScrollViewDelegate
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    // MARK: - Actions
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let newScale = min(scrollView.zoomScale * 3.0, scrollView.maximumZoomScale)
            let zoomRect = zoomRectForScale(newScale, center: point)
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    @objc private func handleSingleTap() {
        let isHidden = navigationController?.navigationBar.isHidden ?? false
        UIView.animate(withDuration: 0.25) {
            self.navigationController?.setNavigationBarHidden(!isHidden, animated: true)
            self.infoContainer.alpha = isHidden ? 1.0 : 0.0
        }
    }

    private func zoomRectForScale(_ scale: CGFloat, center: CGPoint) -> CGRect {
        var zoomRect = CGRect.zero
        zoomRect.size.height = imageView.frame.size.height / scale
        zoomRect.size.width = imageView.frame.size.width / scale
        zoomRect.origin.x = center.x - (zoomRect.size.width / 2.0)
        zoomRect.origin.y = center.y - (zoomRect.size.height / 2.0)
        return zoomRect
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func shareTapped() {
        let activityVC: UIActivityViewController
        if let image = imageView.image {
            activityVC = UIActivityViewController(activityItems: [fileURL, image], applicationActivities: nil)
        } else {
            activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        }
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(activityVC, animated: true)
    }
}
