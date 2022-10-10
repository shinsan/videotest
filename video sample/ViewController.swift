//
//  ViewController.swift
//  video sample
//
//  Created by coper on 2022/10/05.
//

import UIKit
import AVFoundation
import Photos
import AVKit

class ViewController: UIViewController,AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    
    @IBOutlet weak var previewImageView: UIImageView!
    
    private var captureVideoLayer: AVCaptureVideoPreviewLayer?
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "session_queue")

    //video
    var camera: AVCaptureDevice!
    var videoInput: AVCaptureDeviceInput!
    var videoOutput: AVCaptureVideoDataOutput!
    var audioInput:AVCaptureDeviceInput!
    var audioDataOutput:AVCaptureAudioDataOutput!

    var assetWriter: AVAssetWriter!
    var videoAssetInput: AVAssetWriterInput!
    var audioAssetInput: AVAssetWriterInput!

    var pixelBuffer: AVAssetWriterInputPixelBufferAdaptor!
    var startTime: CMTime!
    var endTime: CMTime!
    var frameNumber: Int64 = 0
    
    var isRecording = false
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupCaptureSession()
    }
    
    func setupCaptureSession() {
        // 入力の設定
        
        // ビルトインカメラを見つける
        let discoverSession = AVCaptureDevice.DiscoverySession.init(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back)
        let devices = discoverSession.devices
        
        camera = devices.first

        // カメラの設定
        do {
            // カメラの設定を触るときはデバイスをロックする
            try camera.lockForConfiguration()
            
            // 対応するフレームレートをチェックする (フレームレートを30fpsにしたいとして)
            let fps: Int32 = 30
            //          let frameRateRanges = camera.videoSupportedFrameRateRangs
            //          for(frameRate in frameRateRanges) {
            //            if Int32(frameRate.minFrameRate) <= fps && Int32(frameRate.maxFrameRate) >= fps {
            //              // 30fpsで行ける！
            //            }
            //            // 30fpsで行けない場合はframeRate.maxFrameRateを使うなどの処理を書く
            //          }
            
            // カメラにフレームレートを設定する
            camera.activeVideoMinFrameDuration = CMTime(value:1, timescale: fps)
            
            // 低照度で撮影する場合の明るさのブースト
            if camera.isLowLightBoostEnabled {
                camera.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            
            // ビデオHDRの設定
            if camera.isVideoHDREnabled {
                camera.isVideoHDREnabled = true
            }
            
            // フォーカスの設定 (画面の中心にオートフォーカス)
            if camera.isFocusModeSupported(.autoFocus) && camera.isFocusPointOfInterestSupported {
                // 画面上の位置はCGPointで指定する。(0, 0) から (1, 1)の範囲。
                camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                camera.focusMode = .autoFocus
            }
            
            // 露出の設定 （画面の中心に露出を合わせる）
            if camera.isExposureModeSupported(.continuousAutoExposure) && camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                camera.exposureMode = .continuousAutoExposure
            }
            
            // デバイスのアンロック
            camera.unlockForConfiguration()
            
        } catch {
            print(error)
            return
        }
        
        captureSession.beginConfiguration()

        // AVCaptureSessionへの入力を設定
        do {
            videoInput = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                }
            }
        } catch {
            print(error)
            return
        }

        // AVCaptureSessionのsessionPresetを設定 (映像品質)
        captureSession.sessionPreset = .hd1920x1080 // フルHD
        print(captureSession.sessionPreset)
        
        
        // 出力の設定
        
        // ビデオデータ出力
        videoOutput = AVCaptureVideoDataOutput()
        
        // ビデオ設定
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)] as [String : Any]
        // リアルタイムキャプチャーしながら画像処理をするときは必須
        videoOutput.alwaysDiscardsLateVideoFrames = true
        // キャプチャーセッション用のキュー
        let queue = DispatchQueue(label: "VideoQueue")
        // フレームごとのデータを処理するデリゲートを設定
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        captureSession.addOutput(videoOutput)
        if let videoConnection = videoOutput.connection(with: .video) {
            // 必要ならVideoの向き設定
            if videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = .portrait
            }
            // Video安定化設定
            if videoConnection.isVideoStabilizationSupported {
                videoConnection.preferredVideoStabilizationMode = .cinematic
            }
        }
        audioDataOutput = AVCaptureAudioDataOutput()
        if captureSession.canAddOutput(audioDataOutput) {
            audioDataOutput.setSampleBufferDelegate(self, queue: queue)
            captureSession.addOutput(audioDataOutput)
        }
        captureSession.commitConfiguration()

        // ビデオプレビュー画面の設定
        // （割愛）
        //
        //        if self.captureSession.canAddOutput(self.movieFileOutput) {
        //            self.captureSession.addOutput(self.movieFileOutput)
        //        }
        DispatchQueue.main.async {
            self.captureVideoLayer = AVCaptureVideoPreviewLayer.init(session: self.captureSession)
            self.captureVideoLayer?.frame = self.previewImageView.bounds
            if let captureVideoLayer = self.captureVideoLayer {
                self.previewImageView?.layer.addSublayer(captureVideoLayer)
            }
        }
        
        // AVCaptureSessionを開始する
        self.sessionQueue.async {
            self.captureSession.startRunning()
        }
    }
    
    func startCapture() {
        // ビデオの保存先ファイル
        let documentPath = NSHomeDirectory() + "/Documents/"
        let filePath = documentPath + "\(UUID().uuidString).mp4"
        print(filePath)
        let fileURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("\(UUID().uuidString).mp4")
        
        // ビデオ入力設定 (h264コーデックを使用・フルHD)
        let videoSettings = [
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920,
            AVVideoCodecKey: AVVideoCodecType.h264
        ] as [String: Any]
        
        videoAssetInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        
        // フレームごとの画像を処理するためのバッファーを準備
        pixelBuffer = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoAssetInput, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        
        // フレーム番号の初期化
        frameNumber = 0
        
        do {
            // アセットライターの準備
            try assetWriter = AVAssetWriter(outputURL: fileURL, fileType: .mp4)
            videoAssetInput.expectsMediaDataInRealTime = true
            // アセットライターにビデオ入力を接続
            assetWriter.add(videoAssetInput)
            audioAssetInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 1,
                    AVSampleRateKey: 44100,
                    AVEncoderBitRateKey: 64000,
                ])
            audioAssetInput.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(audioAssetInput) {
                assetWriter.add(audioAssetInput)
            }

            assetWriter.startWriting()
            isRecording = true
        } catch {
            print("could not start video recording ", error)
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        print("----------------------------")
        // キャプチャーしたデータが来なかったら処理しない
        if !CMSampleBufferDataIsReady(sampleBuffer) {
            return
        }
        
        guard isRecording else {return}
        // キャプチャー開始時刻を記録
        if frameNumber == 0 {
            startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter.startSession(atSourceTime: startTime)

        }
        
        // 現在時刻
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let frameTime = CMTimeSubtract(timestamp, CMTime.zero)
        
        // ビデオ入力かどうか？（このコードスニペットでは不要だけど）
        let isVideo = output is AVCaptureVideoDataOutput
        
        if isVideo {
            if videoAssetInput.isReadyForMoreMediaData {
                
                // フレーム画像の合成
                if let pxBuffer:CVPixelBuffer = composeVideo(buffer: sampleBuffer) {
                    // アセットに書き出す
                    pixelBuffer.append(pxBuffer, withPresentationTime: frameTime)
                    
                }
                frameNumber += 1
            }
        } else if output == audioDataOutput,
                  audioAssetInput.isReadyForMoreMediaData {
            //Write audio buffer
            audioAssetInput.append(sampleBuffer)
        }
        endTime = frameTime
    }
    
    // フレーム合成メソッド
    private func composeVideo(buffer: CMSampleBuffer) -> CVPixelBuffer? {
        // CMSampleBufferをUIImageに変換
        let image = uiImageFromSampleBuffer(buffer: buffer)
        // フレーム画像の大きさ
        let width = image.size.width
        let height = image.size.height
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        // 合成する文字列のフォント
        let font = UIFont.systemFont(ofSize: 14.0)
        
        // グラフィックスコンテクストの開始
        UIGraphicsBeginImageContext(image.size)
        
        // 合成する領域
        let timestampRect = CGRect(x: 8, y: height - 38, width: 180, height: 30)
        // テキストスタイル
        let textStyle = NSMutableParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        // 合成する文字列の属性
        let textAttributes = [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: UIColor.orange,
            NSAttributedString.Key.paragraphStyle: textStyle
        ]
        
        let timestampText = Date().description
        
        // 現在のグラフィックスコンテクストに画像を描画
        image.draw(in: rect)
        // 現在のブラフィックスコンテクストに文字列を描画 (これで合成)
        timestampText.draw(in: timestampRect, withAttributes: textAttributes)
        
        // 合成したイメージを取得
        let composedImage = UIGraphicsGetImageFromCurrentImageContext()
        // グラフィックスコンテクストを終了
        UIGraphicsEndImageContext()
        
        return pixelBufferFromUIImage(image: composedImage!)
    }
    
    // CMSampleBufferをUIImageに変換
    private func uiImageFromSampleBuffer(buffer: CMSampleBuffer) -> UIImage {
        let imageBuffer = CMSampleBufferGetImageBuffer(buffer)!
        
        // イメージバッファのロック
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        // 画像情報を取得
        let base = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)!
        let bytesPerRow = UInt(CVPixelBufferGetBytesPerRow(imageBuffer))
        let width = UInt(CVPixelBufferGetWidth(imageBuffer))
        let height = UInt(CVPixelBufferGetHeight(imageBuffer))
        
        // ビットマップコンテキスト作成
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerCompornent = 8
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) as UInt32)
        let newContext = CGContext(data: base, width: Int(width), height: Int(height), bitsPerComponent: Int(bitsPerCompornent), bytesPerRow: Int(bytesPerRow), space: colorSpace, bitmapInfo: bitmapInfo.rawValue)! as CGContext
        
        // 画像作成
        let imageRef = newContext.makeImage()!
        let image = UIImage(cgImage: imageRef, scale: 1.0, orientation: UIImage.Orientation.up)
        
        // イメージバッファのアンロック
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return image
    }
    
    // UIImageをCVPixelBufferに変換
    private func pixelBufferFromUIImage(image: UIImage) -> CVPixelBuffer? {
        let cgImage = image.cgImage!
        let options = [kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        var pxBuffer: CVPixelBuffer? = nil
        let width = cgImage.height
        let height = cgImage.width
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, options as CFDictionary?, &pxBuffer)
        if status != kCVReturnSuccess {
            return nil
        }
        CVPixelBufferLockBaseAddress(pxBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pxData = CVPixelBufferGetBaseAddress(pxBuffer!)!
        let bitsPerComponent: size_t = 8
        let bytePerRow: size_t = 4 * width
        let rgbColorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
        let context: CGContext = CGContext(data: pxData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytePerRow, space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        context.draw(cgImage, in: CGRect(x:0, y:0, width: CGFloat(width), height: CGFloat(height)))
        CVPixelBufferUnlockBaseAddress(pxBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pxBuffer
    }
    
    func stopCapture() {
        // 書き込み時間により、ストップを押した瞬間より早く動画が終了してしまうので、終了処理を遅延させる
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { timer in
            self.isRecording = false
            self.videoAssetInput.markAsFinished()
            self.audioAssetInput.markAsFinished()

            // endSession()を呼ばないとキャプチャーを正常終了できない
            self.assetWriter.endSession(atSourceTime: self.endTime)

            // キャプチャー（ビデオ保存）を終了
            self.assetWriter.finishWriting {
                self.videoAssetInput = nil
                let outputURL = self.assetWriter.outputURL
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
                }) { saved, error in
                    if saved {
                        try? FileManager.default.removeItem(at: outputURL)
                        DispatchQueue.main.async {
                            let alertController = UIAlertController(title: "動画をフォトライブラリに保存しました", message: nil, preferredStyle: .alert)
                            let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                            alertController.addAction(defaultAction)
                            self.present(alertController, animated: true, completion: nil)
                        }
                    }
                }
            }
        }
    }
    
    
    @IBAction func didTapRecord(_ sender: UIButton) {
        if !isRecording {
            startCapture()
        }
    }
    @IBAction func didTapStop(_ sender: Any) {
        if isRecording {
            stopCapture()
        }
    }
    
    private func makeUniqueTempFileURL(extension type: String) -> URL {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
        let uniqueFilename = ProcessInfo.processInfo.globallyUniqueString
        let urlNoExt = temporaryDirectoryURL.appendingPathComponent(uniqueFilename)
        let url = urlNoExt.appendingPathExtension(type)
        return url
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        closeCamera()
    }
    
    func closeCamera(){
        self.captureSession.stopRunning()

        if let videoDeviceInput = videoInput{
            self.captureSession.removeInput(videoDeviceInput)
        }

        if let audioDeviceInput = audioInput {
            self.captureSession.removeInput(audioDeviceInput)
        }

        self.captureSession.removeOutput(videoOutput)
        self.captureVideoLayer?.removeFromSuperlayer()
        self.videoInput = nil
        self.audioInput = nil
        self.captureVideoLayer = nil
    }
    
    
}
