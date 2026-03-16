import AVFoundation
import CoreMedia
import Flutter
import ImageIO
import UIKit
import Photos
import PhotosUI

// MARK: - Plugin Registration

class LivePhotoPlugin: NSObject, FlutterPlugin, PHPickerViewControllerDelegate {
    private var pendingPickResult: FlutterResult?
    private var isMultiPick = false

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
        case "pickLiveForUpload":
            pickLiveForUpload(result: result)
        case "pickMultipleLiveForUpload":
            let limit = (call.arguments as? [String: Any])?["limit"] as? Int ?? 20
            pickMultipleLiveForUpload(limit: limit, result: result)
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

    private func presentLivePicker(selectionLimit: Int, multi: Bool, result: @escaping FlutterResult) {
        if pendingPickResult != nil {
            result(FlutterError(code: "BUSY", message: "Live picker is busy", details: nil))
            return
        }

        let presentPicker = { [weak self] in
            guard let self = self else {
                result(FlutterError(code: "INTERNAL", message: "Plugin released", details: nil))
                return
            }
            guard #available(iOS 14, *) else {
                result(FlutterError(code: "UNSUPPORTED", message: "iOS 14+ required", details: nil))
                return
            }
            guard let rootVC = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController else {
                result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Unable to find root view controller", details: nil))
                return
            }

            var config = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
            config.filter = .livePhotos
            config.selectionLimit = selectionLimit

            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            self.pendingPickResult = result
            self.isMultiPick = multi
            rootVC.present(picker, animated: true)
        }

        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    if status == .authorized || status == .limited {
                        presentPicker()
                    } else {
                        result(FlutterError(code: "PERMISSION_DENIED", message: "Photo library permission denied", details: nil))
                    }
                }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    if status == .authorized {
                        presentPicker()
                    } else {
                        result(FlutterError(code: "PERMISSION_DENIED", message: "Photo library permission denied", details: nil))
                    }
                }
            }
        }
    }

    private func pickLiveForUpload(result: @escaping FlutterResult) {
        presentLivePicker(selectionLimit: 1, multi: false, result: result)
    }

    private func pickMultipleLiveForUpload(limit: Int, result: @escaping FlutterResult) {
        presentLivePicker(selectionLimit: limit, multi: true, result: result)
    }

    @available(iOS 14, *)
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let flutterResult = pendingPickResult
        let multi = isMultiPick
        pendingPickResult = nil
        isMultiPick = false

        picker.dismiss(animated: true)

        guard let result = flutterResult else { return }

        if results.isEmpty {
            result(multi ? [] : nil)
            return
        }

        // 收集所有有效 assetId
        let assetIds = results.compactMap { $0.assetIdentifier }
        if assetIds.isEmpty {
            result(multi ? [] : nil)
            return
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var phAssets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in
            phAssets.append(asset)
        }

        if !multi {
            // 单选模式：返回单个 dict
            guard let asset = phAssets.first else {
                result(FlutterError(code: "ASSET_NOT_FOUND", message: "Unable to fetch selected Live asset", details: nil))
                return
            }
            exportLiveAsset(asset: asset) { exportResult in
                switch exportResult {
                case .success(let payload): result(payload)
                case .failure(let error): result(FlutterError(code: "LIVE_EXPORT_FAILED", message: error.localizedDescription, details: nil))
                }
            }
            return
        }

        // 多选模式：逐个导出，收集结果数组
        let group = DispatchGroup()
        var payloads: [[String: Any]] = []
        var errors: [String] = []
        let lock = NSLock()

        for asset in phAssets {
            group.enter()
            exportLiveAsset(asset: asset) { exportResult in
                lock.lock()
                switch exportResult {
                case .success(let payload): payloads.append(payload)
                case .failure(let error): errors.append(error.localizedDescription)
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            result(payloads)
        }
    }

    private func exportLiveAsset(asset: PHAsset, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let resources = PHAssetResource.assetResources(for: asset)
        // 优先取 fullSizePhoto（原始 HEIC），fallback 到 photo（JPG 降级版本）
        let photoResource = resources.first { $0.type == .fullSizePhoto } ?? resources.first { $0.type == .photo }
        let videoResource = resources.first { $0.type == .pairedVideo } ?? resources.first { $0.type == .fullSizeVideo } ?? resources.first { $0.type == .video }

        guard let imageRes = photoResource, let videoRes = videoResource else {
            completion(.failure(NSError(domain: "LivePhotoPlugin", code: -1001, userInfo: [NSLocalizedDescriptionKey: "未找到 Live 必需资源（静态图或动态视频）"])))
            return
        }

        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("live_upload_\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }

        // 使用原始文件名（如 IMG_1234.HEIC / IMG_1234.MOV），确保不同 Live Photo
        // 有不同的 baseName，避免多次上传时服务端错误配对。
        let imageOrigName = imageRes.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let videoOrigName = videoRes.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)

        let imageFileName: String
        let videoFileName: String

        if !imageOrigName.isEmpty && imageOrigName != videoOrigName {
            // 正常情况：使用原始文件名（例如 IMG_1234.HEIC + IMG_1234.MOV）
            imageFileName = imageOrigName
            videoFileName = videoOrigName
        } else {
            // 兜底：原始文件名为空或相同时，用 UUID 区分
            let imageExt = (imageRes.originalFilename as NSString).pathExtension.isEmpty ? "heic" : (imageRes.originalFilename as NSString).pathExtension
            let videoExt = (videoRes.originalFilename as NSString).pathExtension.isEmpty ? "mov" : (videoRes.originalFilename as NSString).pathExtension
            let pairId = UUID().uuidString.prefix(8)
            imageFileName = "live_\(pairId)_image.\(imageExt)"
            videoFileName = "live_\(pairId)_video.\(videoExt)"
        }

        let imageURL = baseDir.appendingPathComponent(imageFileName)
        let videoURL = baseDir.appendingPathComponent(videoFileName)

        let manager = PHAssetResourceManager.default()
        let group = DispatchGroup()
        var firstError: Error?

        group.enter()
        manager.writeData(for: imageRes, toFile: imageURL, options: nil) { error in
            if let error = error, firstError == nil {
                firstError = error
            }
            group.leave()
        }

        group.enter()
        manager.writeData(for: videoRes, toFile: videoURL, options: nil) { error in
            if let error = error, firstError == nil {
                firstError = error
            }
            group.leave()
        }

        group.notify(queue: .main) {
            if let error = firstError {
                completion(.failure(error))
                return
            }
            completion(.success([
                "image_path": imageURL.path,
                "video_path": videoURL.path,
                "image_name": imageRes.originalFilename,
                "video_name": videoRes.originalFilename,
                "source": "ios_live_photo"
            ]))
        }
    }
    
    private func saveLivePhoto(imageURL: String, videoURL: String, result: @escaping FlutterResult) {
        let group = DispatchGroup()
        var imageData: Data?
        var rawVideoURL: URL?
        var downloadError: Error?

        // Download image
        group.enter()
        downloadFile(from: imageURL) { data, error in
            if let data = data { imageData = data } else { downloadError = error }
            group.leave()
        }

        // Download video
        group.enter()
        let tempVideoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        downloadFileToURL(from: videoURL, to: tempVideoURL) { url, error in
            if let url = url { rawVideoURL = url } else { downloadError = error }
            group.leave()
        }

        group.notify(queue: .main) {
            guard let imageData = imageData,
                  let rawVideoURL = rawVideoURL,
                  downloadError == nil else {
                result(FlutterError(code: "DOWNLOAD_FAILED",
                                    message: downloadError?.localizedDescription ?? "Download failed",
                                    details: nil))
                return
            }

            // 生成唯一 ContentIdentifier，注入 image 和 video，使 iOS 识别为合法 Live Photo 对
            let contentID = UUID().uuidString

            // --- 注入 image 元数据 ---
            let processedImageData = self.injectContentID(intoImage: imageData, uuid: contentID) ?? imageData
            let tempImageURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            do {
                try processedImageData.write(to: tempImageURL)
            } catch {
                result(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
                return
            }

            // --- 注入 video 元数据（AVAssetReader/Writer passthrough + still-image-time timed track）---
            let processedVideoURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".mov")
            self.injectContentID(intoVideo: rawVideoURL, outputURL: processedVideoURL, uuid: contentID) { exportError in
                if let exportError = exportError {
                    result(FlutterError(code: "VIDEO_PROCESS_FAILED",
                                       message: exportError.localizedDescription,
                                       details: nil))
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    let opts = PHAssetResourceCreationOptions()
                    opts.shouldMoveFile = true
                    request.addResource(with: .photo, fileURL: tempImageURL, options: opts)
                    request.addResource(with: .pairedVideo, fileURL: processedVideoURL, options: opts)
                }) { success, saveError in
                    DispatchQueue.main.async {
                        // 清理临时文件（shouldMoveFile=true 时成功后系统已移走，removeItem 会静默失败，无妨）
                        try? FileManager.default.removeItem(at: tempImageURL)
                        try? FileManager.default.removeItem(at: rawVideoURL)
                        try? FileManager.default.removeItem(at: processedVideoURL)

                        if success {
                            result(true)
                        } else {
                            result(FlutterError(code: "SAVE_FAILED",
                                                message: saveError?.localizedDescription ?? "Save failed",
                                                details: nil))
                        }
                    }
                }
            }
        }
    }

    /// 向 JPEG/HEIC 图片数据注入 ContentIdentifier（MakerApple tag 0x0011 = key "17"）
    private func injectContentID(intoImage data: Data, uuid: String) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeUTI = CGImageSourceGetType(source) else { return nil }
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, typeUTI, 1, nil) else { return nil }

        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        var makerApple = (props[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any]) ?? [:]
        makerApple["17"] = uuid   // 0x0011 = ContentIdentifier
        props[kCGImagePropertyMakerAppleDictionary as String] = makerApple

        CGImageDestinationAddImageFromSource(dest, source, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    /// 向视频文件注入 Live Photo 必需元数据，输出为 .mov 容器
    /// 使用 AVAssetReader/AVAssetWriter 实现 passthrough，同时注入：
    ///   - 全局: com.apple.quicktime.content.identifier
    ///   - 全局: com.apple.quicktime.live-photo.version
    ///   - timed metadata track: com.apple.quicktime.still-image-time（PHAssetCreationRequest 必需）
    private func injectContentID(intoVideo inputURL: URL, outputURL: URL, uuid: String,
                                  completion: @escaping (Error?) -> Void) {
        let asset = AVURLAsset(url: inputURL)

        asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) {
            var loadErr: NSError?
            guard asset.statusOfValue(forKey: "tracks", error: &loadErr) == .loaded else {
                completion(loadErr ?? NSError(domain: "LivePhoto", code: -2,
                           userInfo: [NSLocalizedDescriptionKey: "Cannot load asset tracks"]))
                return
            }

            do {
                try? FileManager.default.removeItem(at: outputURL)

                let reader = try AVAssetReader(asset: asset)
                let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
                writer.shouldOptimizeForNetworkUse = false

                // 全局元数据
                let cidItem = AVMutableMetadataItem()
                cidItem.key = "com.apple.quicktime.content.identifier" as NSString
                cidItem.keySpace = .quickTimeMetadata
                cidItem.value = uuid as NSString
                cidItem.dataType = "com.apple.metadata.datatype.UTF-8"

                let verItem = AVMutableMetadataItem()
                verItem.key = "com.apple.quicktime.live-photo.version" as NSString
                verItem.keySpace = .quickTimeMetadata
                verItem.value = NSNumber(value: 1)
                verItem.dataType = "com.apple.metadata.datatype.int8"

                writer.metadata = [cidItem, verItem]

                // 视频/音频 passthrough
                var readerOutputs = [AVAssetReaderTrackOutput]()
                var writerInputs = [AVAssetWriterInput]()

                for track in asset.tracks {
                    let rOut = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                    rOut.alwaysCopiesSampleData = false
                    let hint = track.formatDescriptions.first.map { $0 as! CMFormatDescription }
                    let wIn = AVAssetWriterInput(mediaType: track.mediaType,
                                               outputSettings: nil,
                                               sourceFormatHint: hint)
                    wIn.expectsMediaDataInRealTime = false
                    guard reader.canAdd(rOut) && writer.canAdd(wIn) else { continue }
                    reader.add(rOut)
                    writer.add(wIn)
                    readerOutputs.append(rOut)
                    writerInputs.append(wIn)
                }

                guard !readerOutputs.isEmpty else {
                    completion(NSError(domain: "LivePhoto", code: -6,
                               userInfo: [NSLocalizedDescriptionKey: "Video has no readable tracks"]))
                    return
                }

                // Timed metadata track: com.apple.quicktime.still-image-time
                // PHAssetCreationRequest 要求此 track，否则返回 PHPhotosErrorDomain -1
                var metaAdaptor: AVAssetWriterInputMetadataAdaptor?
                let metaSpec: [String: Any] = [
                    kCMMetadataFormatDescriptionKey_Namespace as String: "mdta",
                    kCMMetadataFormatDescriptionKey_Value as String: "com.apple.quicktime.still-image-time",
                    kCMMetadataFormatDescriptionKey_LocalID as String: NSNumber(value: UInt32(1))
                ]
                var metaFmtDesc: CMFormatDescription?
                if CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
                    kCFAllocatorDefault,
                    kCMMetadataFormatType_Boxed,
                    [metaSpec as NSDictionary] as NSArray,
                    &metaFmtDesc) == noErr,
                   let fmtDesc = metaFmtDesc {
                    let metaIn = AVAssetWriterInput(mediaType: .metadata,
                                                   outputSettings: nil,
                                                   sourceFormatHint: fmtDesc)
                    metaIn.expectsMediaDataInRealTime = false
                    if writer.canAdd(metaIn) {
                        writer.add(metaIn)
                        metaAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metaIn)
                    }
                }

                guard reader.startReading() else {
                    completion(reader.error ?? NSError(domain: "LivePhoto", code: -3,
                               userInfo: [NSLocalizedDescriptionKey: "Reader failed to start"]))
                    return
                }
                writer.startWriting()
                writer.startSession(atSourceTime: .zero)

                let wg = DispatchGroup()
                let q = DispatchQueue(label: "com.xiaoyanquan.livevideo.writer", qos: .userInitiated)

                // 写入 still-image-time timed metadata（标记静态帧在 t=0）
                if let adaptor = metaAdaptor {
                    let stillItem = AVMutableMetadataItem()
                    stillItem.key = "com.apple.quicktime.still-image-time" as NSString
                    stillItem.keySpace = .quickTimeMetadata
                    stillItem.value = NSNumber(value: Float(0))
                    let timedGroup = AVTimedMetadataGroup(
                        items: [stillItem],
                        timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 100))
                    )
                    wg.enter()
                    adaptor.assetWriterInput.requestMediaDataWhenReady(on: q) {
                        while adaptor.assetWriterInput.isReadyForMoreMediaData {
                            adaptor.append(timedGroup)
                            adaptor.assetWriterInput.markAsFinished()
                            wg.leave()
                            return
                        }
                    }
                }

                // 逐轨道 passthrough
                for (rOut, wIn) in zip(readerOutputs, writerInputs) {
                    wg.enter()
                    wIn.requestMediaDataWhenReady(on: q) {
                        while wIn.isReadyForMoreMediaData {
                            if let sb = rOut.copyNextSampleBuffer() {
                                if !wIn.append(sb) {
                                    wIn.markAsFinished()
                                    wg.leave()
                                    return
                                }
                            } else {
                                wIn.markAsFinished()
                                wg.leave()
                                return
                            }
                        }
                    }
                }

                wg.notify(queue: .global(qos: .userInitiated)) {
                    if reader.status == .failed {
                        writer.cancelWriting()
                        DispatchQueue.main.async {
                            completion(reader.error ?? NSError(domain: "LivePhoto", code: -5,
                                       userInfo: [NSLocalizedDescriptionKey: "Reader error during copy"]))
                        }
                        return
                    }
                    writer.finishWriting {
                        DispatchQueue.main.async {
                            if writer.status == .completed {
                                completion(nil)
                            } else {
                                completion(writer.error ?? NSError(
                                    domain: "LivePhoto", code: -4,
                                    userInfo: [NSLocalizedDescriptionKey: "Writer failed: status=\(writer.status.rawValue)"]))
                            }
                        }
                    }
                }

            } catch {
                completion(error)
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
        
        // Show loading spinner (compatible with iOS 12+)
        let spinner: UIActivityIndicatorView
        if #available(iOS 13.0, *) {
            spinner = UIActivityIndicatorView(style: .medium)
        } else {
            spinner = UIActivityIndicatorView(style: .gray)
        }
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
