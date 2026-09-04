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
    private var hasInitialLayout = false

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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasInitialLayout && scrollView.bounds.width > 0 && scrollView.bounds.height > 0 {
            hasInitialLayout = true
            updateImageLayout()
        } else {
            updateImageCenter()
        }
    }

    private func setupUI() {
        view.backgroundColor = .black
        title = fileURL.lastPathComponent

        // Navigation Bar buttons
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

        let saveButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.down"),
            style: .plain,
            target: self,
            action: #selector(saveToPhotosTapped)
        )
        saveButton.tintColor = .white

        navigationItem.rightBarButtonItems = [shareButton, saveButton]

        // Navigation appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithTransparentBackground()
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navigationController?.navigationBar.standardAppearance = navBarAppearance
        navigationController?.navigationBar.scrollEdgeAppearance = navBarAppearance
        navigationController?.navigationBar.tintColor = .white

        // Scroll view for zoom and pan
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 6.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        view.addSubview(scrollView)

        // Image View (MUST use manual layout inside zooming UIScrollView)
        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 20
        imageView.layer.borderWidth = 0.5
        imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        scrollView.addSubview(imageView)

        // Metadata badge pill
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

        // Double tap to zoom
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        // Single tap to toggle chrome (navigation bar & badge)
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

        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        let fileSizeString = formattedFileSize(for: fileURL)
        infoLabel.text = "\(pixelWidth) × \(pixelHeight) px  •  \(fileSizeString)"
    }

    private func updateImageLayout() {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return }

        let boundsSize = scrollView.bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        let maxAvailableWidth = boundsSize.width - 48
        let maxAvailableHeight = boundsSize.height - 180

        let widthRatio = maxAvailableWidth / image.size.width
        let heightRatio = maxAvailableHeight / image.size.height
        let fitRatio = min(widthRatio, heightRatio)

        let targetWidth: CGFloat
        let targetHeight: CGFloat

        // For small icons, scale up to a clear, comfortable preview size (e.g. 240pt)
        if image.size.width < 240 && image.size.height < 240 {
            let scaleUp = min(fitRatio, 240.0 / max(image.size.width, image.size.height))
            targetWidth = round(image.size.width * max(scaleUp, 1.0))
            targetHeight = round(image.size.height * max(scaleUp, 1.0))
        } else {
            let scaleDown = min(fitRatio, 1.0)
            targetWidth = round(image.size.width * scaleDown)
            targetHeight = round(image.size.height * scaleDown)
        }

        imageView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        scrollView.contentSize = CGSize(width: targetWidth, height: targetHeight)
        scrollView.minimumZoomScale = 1.0
        scrollView.zoomScale = 1.0
        scrollView.maximumZoomScale = 6.0

        updateImageCenter()
    }

    private func updateImageCenter() {
        let boundsSize = scrollView.bounds.size
        let contentSize = scrollView.contentSize

        let offsetX = max((boundsSize.width - contentSize.width) * 0.5, 0)
        let offsetY = max((boundsSize.height - contentSize.height) * 0.5, 0)

        imageView.center = CGPoint(
            x: contentSize.width * 0.5 + offsetX,
            y: contentSize.height * 0.5 + offsetY
        )
    }

    private func formattedFileSize(for url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return "Unknown size"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // MARK: - UIScrollViewDelegate
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateImageCenter()
    }

    // MARK: - Gestures & Actions
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.15 {
            scrollView.setZoomScale(1.0, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let zoomWidth = imageView.bounds.width / 2.5
            let zoomHeight = imageView.bounds.height / 2.5
            let zoomRect = CGRect(
                x: point.x - (zoomWidth / 2.0),
                y: point.y - (zoomHeight / 2.0),
                width: zoomWidth,
                height: zoomHeight
            )
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

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func saveToPhotosTapped() {
        guard let image = imageView.image else { return }
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            NotificationServer.NotifyUser(level: .error, notification: "Failed to save: \(error.localizedDescription)")
        } else {
            NotificationServer.NotifyUser(level: .note, notification: "Saved to Photos!")
        }
    }

    @objc private func shareTapped() {
        guard let image = imageView.image else { return }
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(activityVC, animated: true)
    }
}
