import Flutter
import UIKit
import Photos
import PhotosUI

// MARK: - Plugin Registration

class LivePhotoPlugin: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        // PlatformView factory
        let factory = LivePhotoViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "com.xiaoyanquan/live_photo_view")
        
        // MethodChannel for save operations
        let channel = FlutterMethodChannel(name: "com.xiaoyanquan/live_photo", binaryMessenger: registrar.messenger())
        let instance = LivePhotoPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "saveLivePhoto":
            guard let args = call.arguments as? [String: Any],
                  let imageURL = args["image_url"] as? String,
                  let videoURL = args["video_url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Missing image_url or video_url", details: nil))
                return
            }
            saveLivePhoto(imageURL: imageURL, videoURL: videoURL, result: result)
        case "requestPermission":
            requestPhotoLibraryPermission(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func requestPhotoLibraryPermission(result: @escaping FlutterResult) {
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async {
                    result(status == .authorized || status == .limited)
                }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    result(status == .authorized)
                }
            }
        }
    }
    
    private func saveLivePhoto(imageURL: String, videoURL: String, result: @escaping FlutterResult) {
        let group = DispatchGroup()
        var imageData: Data?
        var videoLocalURL: URL?
        var downloadError: Error?
        
        // Download image
        group.enter()
        downloadFile(from: imageURL) { data, error in
            if let data = data {
                imageData = data
            } else {
                downloadError = error
            }
            group.leave()
        }
        
        // Download video
        group.enter()
        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        downloadFileToURL(from: videoURL, to: tempVideoURL) { url, error in
            if let url = url {
                videoLocalURL = url
            } else {
                downloadError = error
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            guard let imageData = imageData, let videoLocalURL = videoLocalURL, downloadError == nil else {
                result(FlutterError(code: "DOWNLOAD_FAILED", message: downloadError?.localizedDescription ?? "Download failed", details: nil))
                return
            }
            
            // Save as Live Photo
            let tempImageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".heic")
            do {
                try imageData.write(to: tempImageURL)
            } catch {
                result(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                request.addResource(with: .photo, fileURL: tempImageURL, options: options)
                request.addResource(with: .pairedVideo, fileURL: videoLocalURL, options: options)
            }) { success, error in
                DispatchQueue.main.async {
                    // Cleanup temp files
                    try? FileManager.default.removeItem(at: tempImageURL)
                    try? FileManager.default.removeItem(at: videoLocalURL)
                    
                    if success {
                        result(true)
                    } else {
                        result(FlutterError(code: "SAVE_FAILED", message: error?.localizedDescription ?? "Save failed", details: nil))
                    }
                }
            }
        }
    }
    
    private func downloadFile(from urlString: String, completion: @escaping (Data?, Error?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil, NSError(domain: "LivePhoto", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            completion(data, error)
        }.resume()
    }
    
    private func downloadFileToURL(from urlString: String, to destURL: URL, completion: @escaping (URL?, Error?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil, NSError(domain: "LivePhoto", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            guard let tempURL = tempURL, error == nil else {
                completion(nil, error)
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                completion(destURL, nil)
            } catch {
                completion(nil, error)
            }
        }.resume()
    }
}

// MARK: - PlatformView Factory

class LivePhotoViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    
    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }
    
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return LivePhotoPlatformView(frame: frame, viewId: viewId, args: args as? [String: Any], messenger: messenger)
    }
    
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - PlatformView

class LivePhotoPlatformView: NSObject, FlutterPlatformView {
    private let containerView: UIView
    private var livePhotoView: PHLivePhotoView?
    private let viewId: Int64
    
    init(frame: CGRect, viewId: Int64, args: [String: Any]?, messenger: FlutterBinaryMessenger) {
        self.containerView = UIView(frame: frame)
        self.viewId = viewId
        super.init()
        
        containerView.backgroundColor = .black
        
        if let imageURL = args?["image_url"] as? String,
           let videoURL = args?["video_url"] as? String {
            loadLivePhoto(imageURL: imageURL, videoURL: videoURL)
        }
        
        // Listen for updates via method channel
        let channel = FlutterMethodChannel(name: "com.xiaoyanquan/live_photo_view_\(viewId)", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            if call.method == "updateURLs",
               let args = call.arguments as? [String: Any],
               let imageURL = args["image_url"] as? String,
               let videoURL = args["video_url"] as? String {
                self?.loadLivePhoto(imageURL: imageURL, videoURL: videoURL)
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    func view() -> UIView {
        return containerView
    }
    
    private func loadLivePhoto(imageURL: String, videoURL: String) {
        guard let imgURL = URL(string: imageURL), let vidURL = URL(string: videoURL) else { return }
        
        // Show loading spinner
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .white
        spinner.center = CGPoint(x: containerView.bounds.midX, y: containerView.bounds.midY)
        spinner.startAnimating()
        containerView.addSubview(spinner)
        
        // Download files to temp
        let tempDir = FileManager.default.temporaryDirectory
        let tempImagePath = tempDir.appendingPathComponent("lp_\(viewId)_img.heic")
        let tempVideoPath = tempDir.appendingPathComponent("lp_\(viewId)_vid.mov")
        
        let group = DispatchGroup()
        var success = true
        
        group.enter()
        URLSession.shared.downloadTask(with: imgURL) { url, _, error in
            defer { group.leave() }
            guard let url = url, error == nil else { success = false; return }
            try? FileManager.default.removeItem(at: tempImagePath)
            try? FileManager.default.moveItem(at: url, to: tempImagePath)
        }.resume()
        
        group.enter()
        URLSession.shared.downloadTask(with: vidURL) { url, _, error in
            defer { group.leave() }
            guard let url = url, error == nil else { success = false; return }
            try? FileManager.default.removeItem(at: tempVideoPath)
            try? FileManager.default.moveItem(at: url, to: tempVideoPath)
        }.resume()
        
        group.notify(queue: .main) { [weak self] in
            spinner.removeFromSuperview()
            guard success, let self = self else { return }
            
            // Create PHLivePhoto from local files
            PHLivePhoto.request(
                withResourceFileURLs: [tempImagePath, tempVideoPath],
                placeholderImage: nil,
                targetSize: self.containerView.bounds.size,
                contentMode: .aspectFit
            ) { [weak self] livePhoto, info in
                guard let self = self, let livePhoto = livePhoto else { return }
                let isDegraded = (info[PHLivePhotoInfoIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    DispatchQueue.main.async {
                        self.showLivePhoto(livePhoto)
                    }
                }
            }
        }
    }
    
    private func showLivePhoto(_ livePhoto: PHLivePhoto) {
        livePhotoView?.removeFromSuperview()
        
        let lpView = PHLivePhotoView(frame: containerView.bounds)
        lpView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        lpView.livePhoto = livePhoto
        lpView.contentMode = .scaleAspectFit
        containerView.addSubview(lpView)
        self.livePhotoView = lpView
        
        // Add Live Photo badge
        let badge = PHLivePhotoView.livePhotoBadgeImage(options: .overContent)
        let badgeView = UIImageView(image: badge)
        badgeView.frame = CGRect(x: 8, y: 8, width: 24, height: 24)
        lpView.addSubview(badgeView)
    }
}
