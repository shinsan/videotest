//
//  ViewController.swift
//  video sample
//
//  Created by coper on 2022/10/05.
//

import UIKit
import AVFoundation
import Photos

class ViewController: UIViewController {


    @IBOutlet weak var previewImageView: UIImageView!
    
    private var captureVideoLayer: AVCaptureVideoPreviewLayer?
    private let captureSession = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private let movieFileOutput = AVCaptureMovieFileOutput()
    
    private let sessionQueue = DispatchQueue(label: "session_queue")
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        
        self.captureSession.beginConfiguration()
        do {
            var defaultVideoDevice: AVCaptureDevice?
             // 古いデバイスはtrue depth cameraではない可能性があるので確認する
            if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back){
                defaultVideoDevice = backCameraDevice
                
            }
            
            guard let videoDevice = defaultVideoDevice else {
                self.captureSession.commitConfiguration()
                return
            }
            
            
             let input = try AVCaptureDeviceInput(device: videoDevice)
             try videoDevice.lockForConfiguration()
                            
             if self.captureSession.canAddInput(input) {
                  self.captureSession.addInput(input)
                  self.videoDeviceInput = input

                  if self.captureSession.canAddOutput(self.movieFileOutput) {
                       self.captureSession.addOutput(self.movieFileOutput)

                       self.captureVideoLayer = AVCaptureVideoPreviewLayer.init(session: self.captureSession)
                       // fit で表示する場合
                       self.captureVideoLayer?.videoGravity = AVLayerVideoGravity.resizeAspect

                       DispatchQueue.main.async {
                           self.captureVideoLayer?.frame = self.previewImageView.bounds
                            if let captureVideoLayer = self.captureVideoLayer {
                                 self.previewImageView?.layer.addSublayer(captureVideoLayer)
                            }
                          
                       }
                  }

                  if let audioDevice = AVCaptureDevice.default(for: .audio){
                       do {
                            let input = try AVCaptureDeviceInput(device: audioDevice)

                            if self.captureSession.canAddInput(input) {
                            self.captureSession.addInput(input)
                            self.audioDeviceInput = input
                            //ミュート時
                                 //  self.captureSession.removeInput(input)
                       }
                       } catch {
                            print("Error input audio device to capture session : \(error)")
                       }
                  }
                 self.captureSession.sessionPreset = .hd1920x1080
             }
             
             videoDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1,timescale: Int32(30))
             videoDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1,timescale: Int32(30))
             
             videoDevice.unlockForConfiguration()
             
        } catch {
            print("Error configure capture session : \(error)")
            
            self.captureSession.commitConfiguration()
            return
        }
        self.captureSession.commitConfiguration()
        
        
        
        self.sessionQueue.async {
             self.captureSession.startRunning()
        }
        
    }

    @IBAction func didTapRecord(_ sender: UIButton) {
        var fileURL = self.makeUniqueTempFileURL(extension: "mov")
        self.movieFileOutput.startRecording(to: fileURL, recordingDelegate: self)

        
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
         
         if let videoDeviceInput = videoDeviceInput{
              self.captureSession.removeInput(videoDeviceInput)
         }
         
         if let audioDeviceInput = audioDeviceInput {
              self.captureSession.removeInput(audioDeviceInput)
         }
         
         self.captureSession.removeOutput(movieFileOutput)
         self.captureVideoLayer?.removeFromSuperlayer()
         self.videoDeviceInput = nil
         self.audioDeviceInput = nil
         self.captureVideoLayer = nil
    }
    
    
}


extension UIViewController: AVCaptureFileOutputRecordingDelegate{
    
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        }) { _, error in
            DispatchQueue.main.async {
            }

            if let error = error {
                print(error)
            }
            
            cleanup()
        }
        
        // Clean file path.
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Error clean up: \(error)")
                }
            }
        }
    }
}
